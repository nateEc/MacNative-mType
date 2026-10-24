import AppKit
import SwiftUI

enum WebsiteConfigPublishedPromptError: Error {
  case wrongOwner, unprepared, requiresDifferentRenderer, inconsistentCaret
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
    guard publication.owner == owner else { throw WebsiteConfigPublishedPromptError.wrongOwner }
    guard let resource = publication.font else { throw WebsiteConfigPublishedPromptError.unprepared }
    let presentation = publication.draft.presentation
    let effect = PracticeVisualEffect.make(modifiers: session.configuration.modifiers)
    guard PracticeLineDisplayPolicy.shouldShowAllLines(settingEnabled: presentation.showAllPracticeLines,
      tapeMode: presentation.practiceTapeMode, configuration: session.configuration),
      !session.isFinished, !effect.usesASL, !effect.usesChoo,
      PromptFieldProjectionPolicy.supports(session.configuration) else {
      throw WebsiteConfigPublishedPromptError.requiresDifferentRenderer
    }
    let font = resource.renderingFont
    let configuration = carets(font, presentation)
    guard configuration.font == font,
      configuration.attemptID == session.automaticInputAttemptID,
      configuration.mainStyle == presentation.caretStyle,
      configuration.paceStyle == presentation.paceCaretStyle,
      configuration.motion == presentation.smoothCaretMotion,
      configuration.lineSpacing == (session.configuration.usesJoiningScriptPrompt ? 8 : 12),
      configuration.rightToLeft == session.configuration.usesRightToLeftPrompt else {
      throw WebsiteConfigPublishedPromptError.inconsistentCaret
    }
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
    self.init(session: session, style: style, font: font, carets: configuration,
      wrapLayout: wrapLayout, fallbackPosition: fallbackPosition,
      onFailure: onFailure, onReady: onReady)
  }
}
