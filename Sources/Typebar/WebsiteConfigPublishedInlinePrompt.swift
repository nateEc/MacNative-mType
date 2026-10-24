import AppKit
import SwiftUI

/// Bounded field / composition fallback and tape consumers. Not the input owner
/// or a replacement for the ASL/Choo and full-preview routing policies.
struct WebsiteConfigPublishedInlinePrompt: View {
  @MainActor private final class Snapshot {
    let session: TypingSession
    let inputs: WebsiteConfigPublishedPromptInputs
    let rendering: PromptRendering
    let carets: PromptCaretNativeView.Configuration
    let retirement: PromptLineScrollContext
    let showsAllLines: Bool
    init(session: TypingSession, inputs: WebsiteConfigPublishedPromptInputs,
      rendering: PromptRendering, carets: PromptCaretNativeView.Configuration,
      retirement: PromptLineScrollContext) {
      self.session = session; self.inputs = inputs; self.rendering = rendering
      self.carets = carets; self.retirement = retirement
      showsAllLines = PracticeLineDisplayPolicy.shouldShowAllLines(
        settingEnabled: inputs.presentation.showAllPracticeLines,
        tapeMode: inputs.presentation.practiceTapeMode, configuration: session.configuration)
    }
  }
  private let snapshot: Snapshot
  private let wrapLayout: PromptInputWrapLayout?
  private let fallbackPosition: PromptViewportFallbackPosition?
  private let maximumTextWidth: CGFloat?
  private let latestProjection: (() -> TapePromptProjectionSnapshot?)?
  private let onTapeWordsRemoved: ((PromptTapeWordRemoval) -> Void)?

  init(publication: WebsiteConfigCommitCoordinator.Publication, owner: UUID,
    session: TypingSession, composition: String = "", theme: ResolvedTheme,
    carets: (PromptRendering, NSFont, WebsiteConfigNativePresentation) -> PromptCaretNativeView.Configuration,
    retirement: (PromptRendering, WebsiteConfigNativePresentation) -> PromptLineScrollContext,
    maximumTextWidth: CGFloat? = nil, wrapLayout: PromptInputWrapLayout? = nil,
    fallbackPosition: PromptViewportFallbackPosition? = nil,
    latestProjection: (() -> TapePromptProjectionSnapshot?)? = nil,
    onTapeWordsRemoved: ((PromptTapeWordRemoval) -> Void)? = nil) throws {
    let inputs = try WebsiteConfigPublishedPromptInputs(publication: publication, owner: owner)
    if let maximumTextWidth, !maximumTextWidth.isFinite || maximumTextWidth <= 0 {
      throw WebsiteConfigPublishedPromptError.invalidGeometry
    }
    let effect = PracticeVisualEffect.make(modifiers: session.configuration.modifiers)
    guard !effect.usesASL, !effect.usesChoo, PromptFieldProjectionPolicy.supports(session.configuration) else {
      throw WebsiteConfigPublishedPromptError.requiresDifferentRenderer
    }
    let rendering = PromptRenderPlan(session: session, composition: composition, style: inputs.style(theme: theme)).render()
    guard rendering.compositionTextMap != nil else { throw WebsiteConfigPublishedPromptError.requiresDifferentRenderer }
    let configuration = carets(rendering, inputs.font, inputs.presentation)
    try inputs.validate(configuration, session: session)
    let context = retirement(rendering, inputs.presentation)
    let field = session.promptCompositionField, words = PromptLineScrollWord.compositionFields(field)
    guard context.attemptID == session.automaticInputAttemptID,
      context.firstRetainedWordIndex == session.firstRetainedPromptWordIndex,
      context.smoothScroll == inputs.presentation.smoothPracticeLineScroll,
      context.centersActiveLine == !inputs.presentation.showAllPracticeLines,
      context.reducesMotion == configuration.reducesMotion,
      context.caretMotion == nil || context.caretMotion === configuration.coordinator,
      context.activeWordID == field?.index,
      context.characterOffsets == rendering.compositionTextMap?.fieldCharacterOffsets,
      context.words.map(\.index) == words.map(\.index),
      context.words.map(\.glyphID) == words.map(\.glyphID) else {
      throw WebsiteConfigPublishedPromptError.inconsistentRetirement
    }
    snapshot = .init(session: session, inputs: inputs, rendering: rendering, carets: configuration, retirement: context)
    self.maximumTextWidth = maximumTextWidth; self.wrapLayout = wrapLayout
    self.fallbackPosition = fallbackPosition; self.latestProjection = latestProjection
    self.onTapeWordsRemoved = onTapeWordsRemoved
  }

  var body: some View {
    let s = snapshot, p = s.inputs.presentation
    if p.practiceTapeMode != .off {
      TapePracticePrompt(session: s.session, rendering: s.rendering, mode: p.practiceTapeMode,
        margin: p.practiceTapeMargin, fontSize: s.inputs.font.pointSize,
        animatesScroll: p.smoothPracticeLineScroll, carets: s.carets, retirement: s.retirement,
        latestProjection: latestProjection, onTapeWordsRemoved: onTapeWordsRemoved)
    } else if s.showsAllLines { field }
    else {
      PracticePromptViewport(text: s.rendering.text, font: s.inputs.font,
        lineSpacing: s.carets.lineSpacing, isRightToLeft: s.carets.rightToLeft,
        lineCount: s.session.configuration.mode == .zen ? 2 : 3,
        maximumTextWidth: maximumTextWidth, horizontalTextInset: 4,
        measuresTextRows: false, measuresCustomRows: true) { field }
    }
  }
  private var field: some View {
    let s = snapshot
    return PromptFieldPracticePrompt(rendering: s.rendering, font: s.inputs.font,
      lineSpacing: s.carets.lineSpacing, rightToLeft: s.carets.rightToLeft,
      joinsLetters: s.session.configuration.usesJoiningScriptPrompt, carets: s.carets,
      lineScroll: s.showsAllLines ? nil : s.retirement,
      viewportLineCount: s.showsAllLines ? nil : (s.session.configuration.mode == .zen ? 2 : 3),
      wrapLayout: wrapLayout, fallbackPosition: fallbackPosition,
      fallbackTargetID: s.session.promptTargetID)
      .frame(maxWidth: maximumTextWidth ?? .infinity)
  }
}
