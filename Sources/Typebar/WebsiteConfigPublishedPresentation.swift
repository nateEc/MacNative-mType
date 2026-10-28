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
  var currentSystemIsDark: Bool { systemIsDark }

  struct PreparedAppearance {
    fileprivate let themes: WebsiteConfigNativeThemes
    fileprivate let custom: ResolvedTheme
    fileprivate let appearance: Appearance
    fileprivate let systemIsDark: Bool
  }

  static func prepareAppearance(draft: WebsiteConfigNativeDraft, applicationID: UUID,
    systemIsDark: Bool) throws -> PreparedAppearance {
    let themes = draft.themes
    let custom = try themes.makeCustomTheme(id: applicationID, name: "Imported configuration").resolvedTheme
    return .init(themes: themes, custom: custom,
      appearance: resolve(themes.initialSelection(systemIsDark: systemIsDark), custom: custom), systemIsDark: systemIsDark)
  }

  /// Internal synchronous handoff: resource and owner checks have already run
  /// before the durable commit. This construction has no fallible operations.
  init(publication: WebsiteConfigCommitCoordinator.Publication, preparedAppearance: PreparedAppearance) {
    self.publication = publication; owner = publication.owner; themes = preparedAppearance.themes
    customTheme = preparedAppearance.custom; systemIsDark = preparedAppearance.systemIsDark
    appearance = preparedAppearance.appearance
  }

  /// A next-attempt-only selection must not replay theme/random/system events.
  func retainingAppearance(for publication: WebsiteConfigCommitCoordinator.Publication) -> WebsiteConfigPublishedPresentation {
    .init(publication: publication, preparedAppearance: .init(themes: themes, custom: customTheme,
      appearance: appearance, systemIsDark: systemIsDark))
  }

  func prepareThemeChange(draft: WebsiteConfigNativeDraft, key: String) throws -> PreparedAppearance {
    let themes = draft.themes
    let custom = try themes.makeCustomTheme(id: owner, name: "Imported configuration").resolvedTheme
    let selection = themes.selectionAfterSaving(key: key, visible: appearance.selection, systemIsDark: systemIsDark)
    return .init(themes: themes, custom: custom, appearance: Self.resolve(selection, custom: custom), systemIsDark: systemIsDark)
  }

  convenience init(publication: WebsiteConfigCommitCoordinator.Publication, owner: UUID, systemIsDark: Bool) throws {
    guard publication.owner == owner else { throw WebsiteConfigPublishedPresentationError.wrongOwner }
    guard publication.font != nil, publication.background != nil else {
      throw WebsiteConfigPublishedPresentationError.unprepared
    }
    self.init(publication: publication, preparedAppearance: try Self.prepareAppearance(draft: publication.draft,
      applicationID: publication.applicationID, systemIsDark: systemIsDark))
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
  func wholePreview(session: TypingSession, fontPreview: WebsiteConfigFontPreview.Prepared? = nil,
    carets: (NSFont, WebsiteConfigNativePresentation) -> PromptCaretNativeView.Configuration,
    wrapLayout: PromptInputWrapLayout? = nil, fallbackPosition: PromptViewportFallbackPosition? = nil,
    onFailure: @escaping (UUID) -> Void,
    onReady: @escaping (PromptViewportPresentationReady) -> Void = { _ in }) throws -> PromptViewportPracticePrompt {
    let theme = appearance.theme
    return try .init(publication: publication, owner: owner, session: session, theme: theme, fontPreview: fontPreview,
      carets: { font, p in
        var config = carets(font, p); config.accent = theme.caret; return config
      }, wrapLayout: wrapLayout, fallbackPosition: fallbackPosition, onFailure: onFailure, onReady: onReady)
  }
  func inline(session: TypingSession, composition: String = "", fontPreview: WebsiteConfigFontPreview.Prepared? = nil,
    carets: (PromptRendering, NSFont, WebsiteConfigNativePresentation) -> PromptCaretNativeView.Configuration,
    retirement: (PromptRendering, WebsiteConfigNativePresentation) -> PromptLineScrollContext,
    maximumTextWidth: CGFloat? = nil, wrapLayout: PromptInputWrapLayout? = nil,
    fallbackPosition: PromptViewportFallbackPosition? = nil,
    latestProjection: (() -> TapePromptProjectionSnapshot?)? = nil,
    onTapeWordsRemoved: ((PromptTapeWordRemoval) -> Void)? = nil) throws -> WebsiteConfigPublishedInlinePrompt {
    let theme = appearance.theme
    return try .init(publication: publication, owner: owner, session: session, composition: composition, theme: theme, fontPreview: fontPreview,
      carets: { rendering, font, p in
        var config = carets(rendering, font, p); config.accent = theme.caret; return config
      }, retirement: retirement, maximumTextWidth: maximumTextWidth, wrapLayout: wrapLayout,
      fallbackPosition: fallbackPosition, latestProjection: latestProjection, onTapeWordsRemoved: onTapeWordsRemoved)
  }
}
