import AppKit
import Observation
import SwiftUI

enum WebsiteConfigPublishedPresentationError: Error { case wrongOwner, unprepared }

/// One immutable resource publication, with source-ordered visible theme state.
/// No library activation, configuration write, input ownership or OS observer.
@MainActor @Observable
final class WebsiteConfigPublishedPresentation {
  struct Appearance: Equatable {
    let selection: WebsiteConfigNativeThemes.Selection
    let theme: ResolvedTheme
  }
  let publication: WebsiteConfigCommitCoordinator.Publication
  private let owner: UUID
  private let themes: WebsiteConfigNativeThemes
  private let customTheme: ResolvedTheme
  private(set) var appearance: Appearance
  @ObservationIgnored private var systemIsDark: Bool
  @ObservationIgnored private var updating = false

  init(publication: WebsiteConfigCommitCoordinator.Publication, owner: UUID, systemIsDark: Bool) throws {
    guard publication.owner == owner else { throw WebsiteConfigPublishedPresentationError.wrongOwner }
    guard publication.font != nil, publication.background != nil else {
      throw WebsiteConfigPublishedPresentationError.unprepared
    }
    let themes = publication.draft.themes
    let custom = try themes.makeCustomTheme(id: publication.applicationID, name: "Imported configuration").resolvedTheme
    self.publication = publication; self.owner = owner; self.themes = themes
    customTheme = custom; self.systemIsDark = systemIsDark
    appearance = Self.resolve(themes.initialSelection(systemIsDark: systemIsDark), custom: custom)
  }
  private static func resolve(_ selection: WebsiteConfigNativeThemes.Selection, custom: ResolvedTheme) -> Appearance {
    switch selection {
    case .builtIn(let theme): .init(selection: selection, theme: theme.resolvedTheme)
    case .inlineCustom: .init(selection: selection, theme: custom)
    }
  }
  /// Host supplies the real system appearance, not this view's forced scheme.
  /// A complete import and a later media event have different source priority.
  @discardableResult
  func updateSystemAppearance(isDark: Bool) -> Bool {
    guard !updating, systemIsDark != isDark else { return false }
    updating = true
    defer { updating = false }
    systemIsDark = isDark
    guard let selection = themes.systemAppearanceChange(systemIsDark: isDark) else { return false }
    let next = Self.resolve(selection, custom: customTheme)
    guard next != appearance else { return false }
    appearance = next
    return true
  }
  func background(fallbackStyle: PracticeBackdropStyle, reduceMotion: Bool,
    onFailure: @escaping BackgroundFailureFeedback.Sink = { _ in }) throws -> WebsiteConfigPublishedBackground {
    try .init(publication: publication, owner: owner, fallbackStyle: fallbackStyle,
      theme: appearance.theme, reduceMotion: reduceMotion, onFailure: onFailure)
  }
  func wholePreview(session: TypingSession,
    carets: (NSFont, WebsiteConfigNativePresentation) -> PromptCaretNativeView.Configuration,
    wrapLayout: PromptInputWrapLayout? = nil, fallbackPosition: PromptViewportFallbackPosition? = nil,
    onFailure: @escaping (UUID) -> Void,
    onReady: @escaping (PromptViewportPresentationReady) -> Void = { _ in }) throws -> PromptViewportPracticePrompt {
    let theme = appearance.theme
    return try .init(publication: publication, owner: owner, session: session, theme: theme,
      carets: { font, p in
        var config = carets(font, p); config.accent = theme.caret; return config
      }, wrapLayout: wrapLayout, fallbackPosition: fallbackPosition, onFailure: onFailure, onReady: onReady)
  }
  func inline(session: TypingSession, composition: String = "",
    carets: (PromptRendering, NSFont, WebsiteConfigNativePresentation) -> PromptCaretNativeView.Configuration,
    retirement: (PromptRendering, WebsiteConfigNativePresentation) -> PromptLineScrollContext,
    maximumTextWidth: CGFloat? = nil, wrapLayout: PromptInputWrapLayout? = nil,
    fallbackPosition: PromptViewportFallbackPosition? = nil,
    latestProjection: (() -> TapePromptProjectionSnapshot?)? = nil,
    onTapeWordsRemoved: ((PromptTapeWordRemoval) -> Void)? = nil) throws -> WebsiteConfigPublishedInlinePrompt {
    let theme = appearance.theme
    return try .init(publication: publication, owner: owner, session: session, composition: composition, theme: theme,
      carets: { rendering, font, p in
        var config = carets(rendering, font, p); config.accent = theme.caret; return config
      }, retirement: retirement, maximumTextWidth: maximumTextWidth, wrapLayout: wrapLayout,
      fallbackPosition: fallbackPosition, latestProjection: latestProjection, onTapeWordsRemoved: onTapeWordsRemoved)
  }
}
