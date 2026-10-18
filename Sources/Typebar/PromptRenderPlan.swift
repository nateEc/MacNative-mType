import AppKit
import SwiftUI

/// Values used by one prompt render. No AppSettings reference survives a yield.
struct PromptRenderStyle: Equatable {
  let theme: ResolvedTheme
  var fontSize: Double = 28
  var flipTestColors = false
  var colorfulMode = false
  var typedCharacterEffect: TypedCharacterEffect = .keep
  var compositionDisplayStyle: CompositionDisplayStyle = .replace
  var typoIndicatorStyle: TypoIndicatorStyle = .off
  var caretStyle: TypingCaretStyle = .bar
  var paceCaretStyle: TypingCaretStyle = .bar
  var highlightMode: PromptHighlightMode = .letter
  var usesTapePractice = false
}

/// Candidate-session projection and appearance are frozen before asynchronous
/// glyph batches. Callers still own attempt/style/width validation at publish.
@MainActor struct PromptRenderPlan {
  private let composition: String?
  private let style: PromptRenderStyle
  private let removedTapeWordIndices: Set<Int>
  private let presentation: PromptCompositionPresentation?
  private let glyphs: [TypingPromptGlyph]
  private let words: [TypingPromptWordPresentation]
  private let indices: [Int]
  private let appearances: [PromptGlyphAppearance]
  private let completedCharacterIndices: Set<Int>
  private let caretIndex: Int?
  private let emptyWordPlaceholder: Int?
  private let targetGlyphCount: Int
  private let isZen: Bool
  private let sessionPolicy: PromptRenderSessionPolicy
  private let completedPromptColor: Color
  private let futurePromptColor: Color
  private let errorFeedbackColor: Color
  private let extraInputFeedbackColor: Color

  init(session: TypingSession, composition: String?, style: PromptRenderStyle) {
    let usesProjection = composition != nil && PromptFieldProjectionPolicy.supports(session.configuration)
    let presentation = usesProjection
      ? PromptCompositionPresentation(session: session, composition: composition ?? "",
        style: style.compositionDisplayStyle) : nil
    self.init(session: session, composition: composition, style: style,
      usesProjection: usesProjection, presentation: presentation)
  }

  static func prepareCooperatively(session: TypingSession, composition: String?,
    style: PromptRenderStyle, batchSize: Int = 512
  ) async throws -> PromptRenderPlan {
    try Task.checkCancellation()
    let usesProjection = composition != nil && PromptFieldProjectionPolicy.supports(session.configuration)
    let presentation: PromptCompositionPresentation?
    if usesProjection {
      presentation = try await PromptCompositionPresentation.makeCooperatively(session: session,
        composition: composition ?? "", style: style.compositionDisplayStyle, batchSize: batchSize)
    } else { presentation = nil }
    try Task.checkCancellation()
    return .init(session: session, composition: composition, style: style,
      usesProjection: usesProjection, presentation: presentation)
  }

  private init(session: TypingSession, composition: String?, style: PromptRenderStyle,
    usesProjection: Bool, presentation: PromptCompositionPresentation?) {
    self.composition = composition
    self.style = style
    removedTapeWordIndices = session.removedTapePromptWordIndices
    targetGlyphCount = session.prompt.count
    isZen = session.configuration.mode == .zen
    sessionPolicy = PromptRenderSessionPolicy(session: session,
      highlightMode: style.highlightMode, usesTapePractice: style.usesTapePractice,
      mainCaretDrawsMarker: style.caretStyle.drawsMarker,
      paceCaretDrawsMarker: style.paceCaretStyle.drawsMarker)
    self.presentation = presentation
    CompositionProjectionDiagnostics.observe(expected: usesProjection,
      available: presentation != nil, marked: composition?.isEmpty == false, session: session)
    completedCharacterIndices = presentation?.completedIndices ?? session.completedPromptCharacterIndices
    glyphs = presentation?.glyphs ?? session.promptGlyphs
    words = presentation?.words ?? session.promptWordPresentations
    caretIndex = presentation.map { value in value.projection.caret.flatMap { anchor in
      value.projection.cells.firstIndex { $0.id == anchor.cellID }
    } } ?? session.promptCaretGlyphIndex
    indices = PromptGlyphLayout.indices(glyphs: glyphs, words: words,
      hideExtraLetters: session.configuration.rules.hideExtraLetters,
      firstRetainedWordIndex: session.firstRetainedPromptWordIndex)
    appearances = PromptGlyphAppearance.plan(glyphs: glyphs, words: words,
      mode: sessionPolicy.highlightMode, blindMode: session.configuration.rules.blindMode,
      typedEffect: style.typedCharacterEffect,
      hidesUntypedGlyphs: session.configuration.modifiers.contains(.listening))
    emptyWordPlaceholder = presentation?.emptyPlaceholderIndex ?? session.zenEmptyWordPlaceholderGlyphIndex
    completedPromptColor = Self.promptColor(.completed, style: style)
    futurePromptColor = Self.promptColor(.future, style: style)
    errorFeedbackColor = style.theme.errorColor(usesColorfulMode: style.colorfulMode)
    extraInputFeedbackColor = style.theme.extraInputColor(usesColorfulMode: style.colorfulMode)
  }

  func render() -> PromptRendering {
    var painter = GlyphPainter(plan: self)
    if let presentation { return presentation.render { painter.render($0, $1, $2) } }
    return PromptRendering.make(glyphs: glyphs, indices: indices,
      emptyWordPlaceholderGlyphID: emptyWordPlaceholder,
      words: words, removedTapeWordIndices: removedTapeWordIndices) {
        painter.render($0, $1, nil)
      }
  }

  func renderCooperatively(batchSize: Int = 512, didRender: (Int) -> Void = { _ in }) async throws -> PromptRendering {
    try Task.checkCancellation()
    var painter = GlyphPainter(plan: self)
    if let presentation {
      return try await presentation.renderCooperatively(batchSize: batchSize,
        didRender: didRender) { painter.render($0, $1, $2) }
    }
    return try await PromptRendering.makeCooperatively(glyphs: glyphs, indices: indices,
      emptyWordPlaceholderGlyphID: emptyWordPlaceholder,
      words: words, removedTapeWordIndices: removedTapeWordIndices,
      batchSize: batchSize, didRender: didRender) { painter.render($0, $1, nil) }
  }

  private static func promptColor(_ role: PromptTextRole, style: PromptRenderStyle) -> Color {
    switch PromptTextColorPolicy.tone(for: role,
      flipsCompletionAndFuture: style.flipTestColors,
      usesAccentForCompleted: style.colorfulMode) {
    case .primary: style.theme.text
    case .secondary: style.theme.secondaryText
    case .accent: style.theme.accent
    }
  }

  @MainActor private struct GlyphPainter {
    let plan: PromptRenderPlan
    let style: PromptRenderStyle
    let theme: ResolvedTheme
    var plainPendingInk: [PlainPendingGlyphInkKey: AttributedString] = [:]

    init(plan: PromptRenderPlan) {
      self.plan = plan
      style = plan.style
      theme = plan.style.theme
    }

    mutating func render(_ index: Int, _ glyph: TypingPromptGlyph,
      _ markedCell: PromptCompositionProjection.Cell?) -> AttributedString {
      let isCompleted = plan.completedCharacterIndices.contains(index)
      let appearance = plan.appearances[index]
      let plainKey = PlainPendingGlyphInkKey.make(glyph: glyph, appearance: appearance,
        isCompleted: isCompleted, hasSpecialPresentation: plan.presentation == nil || markedCell != nil
          || index == plan.caretIndex || index == plan.sessionPolicy.paceGuideIndex
          || index == plan.emptyWordPlaceholder)
      if let plainKey, let cached = plainPendingInk[plainKey] { return cached }
      let turnsIntoDot = TypedCharacterEffectPolicy.replacesCommittedCharacterWithDot(
        isCompleted: isCompleted, character: glyph.character, effect: style.typedCharacterEffect)
      let replacesCurrentWithComposition = index == plan.caretIndex
        && plan.presentation == nil && style.compositionDisplayStyle == .replace
        && plan.composition?.isEmpty == false
      let textPlan = PromptControlCharacterPresentation.plan(for: glyph,
        style: style.typoIndicatorStyle, isZen: plan.isZen,
        isExtra: glyph.state == .extra || (plan.presentation == nil && index >= plan.targetGlyphCount),
        compositionReplacement: markedCell?.text
          ?? (replacesCurrentWithComposition ? plan.composition : nil),
        isEmptyWordPlaceholder: index == plan.emptyWordPlaceholder)
      var character = AttributedString(turnsIntoDot ? "•" : textPlan.text)
      if !plan.sessionPolicy.usesIndependentPromptCarets,
        index == plan.sessionPolicy.paceGuideIndex, index != plan.caretIndex {
        Self.applyPaceCaret(to: &character, theme: theme, style: style.paceCaretStyle)
      }
      switch appearance.color {
      case .completed: character.foregroundColor = plan.completedPromptColor
      case .future: character.foregroundColor = plan.futurePromptColor
      case .error: character.foregroundColor = plan.errorFeedbackColor
      case .extra: character.foregroundColor = plan.extraInputFeedbackColor
      case .hidden: character.foregroundColor = .clear
      }
      switch glyph.state {
      case .correct:
        switch style.typedCharacterEffect {
        case .hide where isCompleted: character.foregroundColor = .clear
        case .fade where isCompleted: character.foregroundColor = theme.fadedText.opacity(0.24)
        case .dots where turnsIntoDot: character.foregroundColor = theme.accent.opacity(0.74)
        default: break
        }
      case .current, .incorrect, .pending, .hidden, .extra: break
      }
      if index == plan.caretIndex, plan.sessionPolicy.highlightMode != .off,
        style.caretStyle.drawsMarker && !plan.sessionPolicy.usesIndependentPromptCarets {
        Self.applyCaret(to: &character, theme: theme, style: style.caretStyle)
      }
      appearance.applyVisibility(to: &character)
      if let color = character.foregroundColor { character.foregroundColor = color.opacity(textPlan.opacity) }
      if style.typedCharacterEffect != .hide || !isCompleted {
        appearance.applyErrorUnderline(to: &character, errorColor: plan.errorFeedbackColor)
      }
      if markedCell != nil {
        let underline = appearance.color == .hidden ? Color.clear : plan.futurePromptColor
        character.underlineStyle = Text.LineStyle(color: underline)
        character.appKit.underlineColor = NSColor(underline)
      }
      if appearance.color != .hidden, let hintText = textPlan.hint {
        var hint = AttributedString(hintText)
        hint.font = .system(size: max(9, style.fontSize * 0.48), weight: .semibold, design: .monospaced)
        hint.foregroundColor = plan.errorFeedbackColor.opacity(0.72)
        hint.baselineOffset = -style.fontSize * 0.42
        hint.kern = -style.fontSize * 0.62
        character += hint
      }
      if let plainKey { plainPendingInk[plainKey] = character }
      return character
    }

    private static func applyCaret(to character: inout AttributedString,
      theme: ResolvedTheme, style: TypingCaretStyle) {
      switch style {
      case .off: break
      case .bar:
        character.foregroundColor = theme.caret
        character.underlineStyle = .single
      case .outline: character.backgroundColor = theme.caret.opacity(0.14)
      case .underline:
        character.underlineStyle = .single
        character.backgroundColor = theme.caret.opacity(0.12)
      case .block: character.backgroundColor = theme.caret.opacity(0.55)
      case .carrot, .banana, .monkey: character.foregroundColor = theme.caret
      }
    }

    private static func applyPaceCaret(to character: inout AttributedString,
      theme: ResolvedTheme, style: TypingCaretStyle) {
      switch style {
      case .off: break
      case .bar:
        character.backgroundColor = theme.caret.opacity(0.16)
        character.underlineStyle = .single
      case .outline: character.backgroundColor = theme.caret.opacity(0.12)
      case .underline: character.underlineStyle = .single
      case .block: character.backgroundColor = theme.caret.opacity(0.34)
      case .carrot, .banana, .monkey: character.foregroundColor = theme.caret.opacity(0.72)
      }
    }
  }
}
