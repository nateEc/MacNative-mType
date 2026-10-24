import AppKit
import SwiftUI

enum WebsiteConfigPublishedPromptError: Error {
  case wrongOwner, unprepared, requiresDifferentRenderer, inconsistentCaret, inconsistentRetirement, invalidGeometry
}

@MainActor
struct WebsiteConfigPublishedPromptInputs {
  let font: NSFont
  let presentation: WebsiteConfigNativePresentation
  let maximumTextWidth: CGFloat?
  init(publication: WebsiteConfigCommitCoordinator.Publication, owner: UUID) throws {
    guard publication.owner == owner else { throw WebsiteConfigPublishedPromptError.wrongOwner }
    guard let resource = publication.font else { throw WebsiteConfigPublishedPromptError.unprepared }
    font = resource.renderingFont; presentation = publication.draft.presentation
    if presentation.practiceTapeMode == .off, let columns = publication.draft.keyboardTypography.columns {
      let width = columns * resource.chAdvance
      guard width.isFinite, width > 0 else { throw WebsiteConfigPublishedPromptError.invalidGeometry }
      maximumTextWidth = width
    } else { maximumTextWidth = nil }
  }
  func width(limitedBy host: CGFloat?) throws -> CGFloat? {
    guard let host else { return maximumTextWidth }
    guard host.isFinite, host > 0 else { throw WebsiteConfigPublishedPromptError.invalidGeometry }
    return maximumTextWidth.map { min($0, host) } ?? host
  }
  func validate(_ configuration: PromptCaretNativeView.Configuration, session: TypingSession) throws {
    guard configuration.font == font,
      configuration.attemptID == session.automaticInputAttemptID,
      configuration.mainStyle == presentation.caretStyle,
      configuration.paceStyle == presentation.paceCaretStyle,
      configuration.motion == presentation.smoothCaretMotion,
      configuration.lineSpacing == (session.configuration.usesJoiningScriptPrompt ? 8 : 12),
      configuration.rightToLeft == session.configuration.usesRightToLeftPrompt else {
      throw WebsiteConfigPublishedPromptError.inconsistentCaret
    }
  }
  func style(theme: ResolvedTheme) -> PromptRenderStyle {
    var style = PromptRenderStyle(theme: theme, fontSize: font.pointSize)
    style.flipTestColors = presentation.flipTestColors
    style.colorfulMode = presentation.colorfulMode
    style.typedCharacterEffect = presentation.typedCharacterEffect
    style.compositionDisplayStyle = presentation.compositionDisplayStyle
    style.typoIndicatorStyle = presentation.typoIndicatorStyle
    style.caretStyle = presentation.caretStyle
    style.paceCaretStyle = presentation.paceCaretStyle
    style.highlightMode = presentation.promptHighlightMode
    style.usesTapePractice = presentation.practiceTapeMode != .off
    return style
  }
}

extension PromptViewportPracticePrompt {
  /// Uses one committed font for glyphs, viewport metrics and both carets.
  /// The caller still owns the session, input providers and resolved theme.
  init(publication: WebsiteConfigCommitCoordinator.Publication, owner: UUID,
    session: TypingSession, theme: ResolvedTheme,
    carets: (NSFont, WebsiteConfigNativePresentation) -> PromptCaretNativeView.Configuration,
    wrapLayout: PromptInputWrapLayout? = nil,
    fallbackPosition: PromptViewportFallbackPosition? = nil,
    onFailure: @escaping (UUID) -> Void,
    onReady: @escaping (PromptViewportPresentationReady) -> Void = { _ in }) throws {
    let inputs = try WebsiteConfigPublishedPromptInputs(publication: publication, owner: owner)
    let presentation = inputs.presentation
    let effect = PracticeVisualEffect.make(modifiers: session.configuration.modifiers)
    guard PracticeLineDisplayPolicy.shouldShowAllLines(settingEnabled: presentation.showAllPracticeLines,
      tapeMode: presentation.practiceTapeMode, configuration: session.configuration),
      !session.isFinished, !effect.usesASL, !effect.usesChoo,
      PromptFieldProjectionPolicy.supports(session.configuration) else {
      throw WebsiteConfigPublishedPromptError.requiresDifferentRenderer
    }
    let configuration = carets(inputs.font, presentation)
    try inputs.validate(configuration, session: session)
    let style = inputs.style(theme: theme), font = inputs.font
    self.init(session: session, style: style, font: font, carets: configuration,
      wrapLayout: wrapLayout, fallbackPosition: fallbackPosition,
      onFailure: onFailure, onReady: onReady)
    maximumTextWidth = inputs.maximumTextWidth
  }
}
