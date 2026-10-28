import AppKit
import Observation
import SwiftUI

enum WebsiteConfigPublishedPresentationError: Error { case wrongOwner, unprepared, staleThemePreview }

/// One immutable resource publication, with source-ordered visible theme state.
/// No library activation, configuration write, input ownership or OS observer.
@MainActor @Observable
final class WebsiteConfigPublishedPresentation {
  struct Appearance: Equatable {
    let selection: WebsiteConfigNativeThemes.Selection
    let theme: ResolvedTheme
  }
  /// Carries source theme effects across several synchronous publications;
  /// SwiftUI may observe only the final setter in a compound command.
  struct ThemeChanges: Equatable {
    var previewReset = UUID()
    var applied = UUID()
    var indicator = UUID()
    var systemIndicator: AppTheme?
    var randomIndicator: String?
  }
  let publication: WebsiteConfigCommitCoordinator.Publication
  let backgroundDisplay: WebsiteConfigBackgroundDisplay?
  let backgroundFallback: WebsiteConfigBackgroundDisplay.Snapshot?
  let backgroundFitOverride: CustomBackgroundFit?
  struct BackgroundFilterPreview { let image: UUID; let filter: WebsiteConfigNativePagePreferences.BackgroundFilter }
  private(set) var backgroundFilterPreview: BackgroundFilterPreview?
  var backgroundSnapshot: WebsiteConfigBackgroundDisplay.Snapshot? {
    let snapshot = unmodifiedBackgroundSnapshot
    let fitted = backgroundFitOverride.flatMap { snapshot?.fitting($0) } ?? snapshot
    if let preview = backgroundFilterPreview, fitted?.identity == preview.image { return fitted?.filtering(preview.filter) }
    return fitted
  }
  func previewBackgroundFilter(_ filter: WebsiteConfigNativePagePreferences.BackgroundFilter, image: UUID) {
    backgroundFilterPreview = .init(image: image, filter: filter)
  }
  private var unmodifiedBackgroundSnapshot: WebsiteConfigBackgroundDisplay.Snapshot? {
    if let backgroundDisplay { return backgroundDisplay.snapshot }
    if let backgroundFallback { return backgroundFallback }
    guard let resource = publication.background else { return nil }
    return .init(owner: owner, identity: publication.applicationID, resource: resource,
      preferences: publication.draft.pagePreferences, pointsPerRem: publication.pointsPerRem)
  }
  private let owner: UUID
  private let themes: WebsiteConfigNativeThemes
  private let customTheme: ResolvedTheme
  private(set) var appearance: Appearance
  private(set) var themeChanges: ThemeChanges
  let randomThemes: WebsiteRandomThemeConfiguration
  @ObservationIgnored private var systemIsDark: Bool
  @ObservationIgnored private var updating = false
  var currentSystemIsDark: Bool { systemIsDark }

  struct PreparedAppearance {
    fileprivate let themes: WebsiteConfigNativeThemes
    fileprivate let custom: ResolvedTheme
    fileprivate let appearance: Appearance
    fileprivate let systemIsDark: Bool
    fileprivate let changes: ThemeChanges
    fileprivate let randomThemes: WebsiteRandomThemeConfiguration
  }

  /// Full-config theme effects precede asynchronous practice initialization.
  /// This owns colors only; it cannot publish fonts, media, input or a session.
  @MainActor @Observable final class PendingTheme {
    let owner: UUID
    private let values: [String: WebsiteConfigValue]
    private var prepared: PreparedAppearance
    var appearance: Appearance { prepared.appearance }
    var themes: WebsiteConfigNativeThemes { prepared.themes }
    var systemIndicator: AppTheme? { prepared.changes.systemIndicator }
    init(owner: UUID, draft: WebsiteConfigNativeDraft, prepared: PreparedAppearance) {
      self.owner = owner; self.prepared = prepared
      values = draft.projection.runtime.filter { WebsiteConfigNativeThemes.mappedKeys.contains($0.key) }
    }
    func matching(_ draft: WebsiteConfigNativeDraft) -> PreparedAppearance? {
      values == draft.projection.runtime.filter { WebsiteConfigNativeThemes.mappedKeys.contains($0.key) } ? prepared : nil
    }
    func updateSystemAppearance(isDark: Bool) {
      guard isDark != prepared.systemIsDark else { return }
      var changes = prepared.changes
      let selection = prepared.themes.systemAppearanceChange(systemIsDark: isDark)
      if selection != nil {
        changes.applied = UUID(); changes.indicator = UUID()
        changes.systemIndicator = isDark ? themes.darkTheme : themes.lightTheme
      }
      prepared = .init(themes: themes, custom: prepared.custom,
        appearance: selection.map { WebsiteConfigPublishedPresentation.resolve($0, custom: prepared.custom) } ?? prepared.appearance,
        systemIsDark: isDark, changes: changes, randomThemes: prepared.randomThemes)
    }
  }

  static func prepareAppearance(draft: WebsiteConfigNativeDraft, applicationID: UUID,
    systemIsDark: Bool, previous: WebsiteConfigPublishedPresentation? = nil) throws -> PreparedAppearance {
    let themes = draft.themes
    let custom = try themes.makeCustomTheme(id: applicationID, name: "Imported configuration").resolvedTheme
    var random = try previous?.randomThemes ?? .init(entries: WebsiteRandomThemeConfiguration.nativeCatalog(), draft: draft)
    // Restarting setters and received test settings share this resource
    // handoff, but do not dispatch the full configuration lifecycle.
    switch draft.origin {
    case .imported, .restored:
      random.favoritesReplaced(draft: draft)
      random.clearActive()
    case .edited, .received:
      if let previous {
        return .init(themes: themes, custom: custom, appearance: previous.appearance,
          systemIsDark: systemIsDark, changes: previous.themeChanges, randomThemes: random)
      }
    }
    return .init(themes: themes, custom: custom,
      appearance: resolve(themes.initialSelection(systemIsDark: systemIsDark), custom: custom), systemIsDark: systemIsDark,
      changes: .init(systemIndicator: themes.followsSystem ? (systemIsDark ? themes.darkTheme : themes.lightTheme) : nil,
        randomIndicator: random.active), randomThemes: random)
  }

  /// Internal synchronous handoff: resource and owner checks have already run
  /// before the durable commit. This construction has no fallible operations.
  init(publication: WebsiteConfigCommitCoordinator.Publication, preparedAppearance: PreparedAppearance,
    backgroundDisplay: WebsiteConfigBackgroundDisplay? = nil,
    backgroundFallback: WebsiteConfigBackgroundDisplay.Snapshot? = nil, backgroundFitOverride: CustomBackgroundFit? = nil,
    backgroundFilterPreview: BackgroundFilterPreview? = nil) {
    self.backgroundDisplay = backgroundDisplay
    self.backgroundFallback = backgroundFallback; self.backgroundFitOverride = backgroundFitOverride
    self.backgroundFilterPreview = backgroundFilterPreview
    self.publication = publication; owner = publication.owner; themes = preparedAppearance.themes
    customTheme = preparedAppearance.custom; systemIsDark = preparedAppearance.systemIsDark
    appearance = preparedAppearance.appearance
    themeChanges = preparedAppearance.changes
    randomThemes = preparedAppearance.randomThemes
  }

  /// A next-attempt-only selection must not replay theme/random/system events.
  func retainingAppearance(for publication: WebsiteConfigCommitCoordinator.Publication) -> WebsiteConfigPublishedPresentation {
    .init(publication: publication, preparedAppearance: .init(themes: themes, custom: customTheme,
      appearance: appearance, systemIsDark: systemIsDark, changes: themeChanges, randomThemes: randomThemes),
      backgroundDisplay: backgroundDisplay, backgroundFallback: backgroundFallback ?? (backgroundDisplay == nil ? backgroundSnapshot : nil),
      backgroundFitOverride: backgroundFitOverride, backgroundFilterPreview: backgroundFilterPreview)
  }
  func changingBackground(for publication: WebsiteConfigCommitCoordinator.Publication,
    display: WebsiteConfigBackgroundDisplay?, fit: CustomBackgroundFit?, fallback: WebsiteConfigBackgroundDisplay.Snapshot?) -> WebsiteConfigPublishedPresentation {
    .init(publication: publication, preparedAppearance: .init(themes: themes, custom: customTheme,
      appearance: appearance, systemIsDark: systemIsDark, changes: themeChanges, randomThemes: randomThemes),
      backgroundDisplay: display, backgroundFallback: fallback, backgroundFitOverride: fit, backgroundFilterPreview: backgroundFilterPreview)
  }
  func hasSameBackgroundConfiguration(as draft: WebsiteConfigNativeDraft) -> Bool {
    WebsiteBackgroundCommand.keys.allSatisfy { publication.draft.projection.runtime[$0] == draft.projection.runtime[$0] }
  }

  struct PreparedThemeEdit { let draft: WebsiteConfigNativeDraft; let appearance: PreparedAppearance }
  func prepareThemeChange(draft original: WebsiteConfigNativeDraft, key: String, customThemeIDs: [String],
    chooseIndex: (Int) -> Int = { Int.random(in: 0...$0) }) throws -> PreparedThemeEdit {
    var random = randomThemes, draft = original
    if key == "favThemes" { random.favoritesReplaced(draft: draft) }
    if key == "randomTheme" {
      draft = try random.modeChanged(draft: draft, customIDs: customThemeIDs,
        pointsPerRem: publication.pointsPerRem, chooseIndex: chooseIndex)
    }
    let clearedRandom = key == "theme" || (key == "randomTheme" && draft.themes.randomMode == .off)
      ? random.clearActive() : false
    let themes = draft.themes
    let custom = try themes.makeCustomTheme(id: owner, name: "Imported configuration").resolvedTheme
    var selection = themes.selectionAfterSaving(key: key, visible: appearance.selection, systemIsDark: systemIsDark)
    if key == "randomTheme" && clearedRandom { selection = themes.customEnabled ? .inlineCustom : .builtIn(themes.theme) }
    var changes = themeChanges
    if key == "theme" { changes.previewReset = UUID() }
    let systemApplies = themes.followsSystem && ((key == "themeLight" && !systemIsDark) || (key == "themeDark" && systemIsDark))
    if ["theme", "customTheme", "customThemeColors", "autoSwitchTheme"].contains(key) || systemApplies || clearedRandom {
      changes.applied = UUID(); changes.indicator = UUID()
      changes.systemIndicator = systemApplies || (key == "autoSwitchTheme" && themes.followsSystem)
        ? (systemIsDark ? themes.darkTheme : themes.lightTheme) : nil
    }
    if ["theme", "customTheme", "customThemeColors", "favThemes", "randomTheme"].contains(key) {
      changes.indicator = UUID(); changes.systemIndicator = nil
    }
    if changes.indicator != themeChanges.indicator { changes.randomIndicator = random.active }
    return .init(draft: draft, appearance: .init(themes: themes, custom: custom,
      appearance: Self.resolve(selection, custom: custom), systemIsDark: systemIsDark, changes: changes, randomThemes: random))
  }

  func prepareRandomEffect(draft: WebsiteConfigNativeDraft, random: WebsiteRandomThemeConfiguration,
    draw: WebsiteRandomThemeSequence.Draw?, customColors: WebsiteConfigValue?) throws -> PreparedAppearance {
    let themes = draft.themes
    let custom = try themes.makeCustomTheme(id: owner, name: "Imported configuration").resolvedTheme
    var visible = appearance, changes = themeChanges
    if let draw {
      if draw.theme == "custom" {
        var runtime = draft.projection.runtime
        if let customColors { runtime["customThemeColors"] = customColors }
        let override = try WebsiteConfigNativeThemes(runtime: runtime).makeCustomTheme(id: owner, name: "Random theme").resolvedTheme
        visible = .init(selection: .inlineCustom, theme: override)
      } else {
        guard let theme = AppTheme(rawValue: draw.theme), theme != .grove else { throw WebsiteThemeCommandError.unsupported }
        visible = Self.resolve(.builtIn(theme), custom: custom)
      }
      changes.applied = UUID(); changes.indicator = UUID(); changes.systemIndicator = nil
      changes.randomIndicator = random.active
    }
    return .init(themes: themes, custom: custom, appearance: visible, systemIsDark: systemIsDark,
      changes: changes, randomThemes: random)
  }

  /// clearPreview applies the active random ID again, without a custom color
  /// override; it deliberately ignores system-following priority.
  var previewRestorationTheme: ResolvedTheme? {
    if let active = randomThemes.active {
      if active == "custom" { return customTheme }
      return AppTheme(rawValue: active).map(\.resolvedTheme)
    }
    return themes.customEnabled ? customTheme : themes.theme.resolvedTheme
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
    let changed = next != appearance
    themeChanges.applied = UUID(); themeChanges.indicator = UUID()
    themeChanges.systemIndicator = isDark ? themes.darkTheme : themes.lightTheme
    themeChanges.randomIndicator = randomThemes.active
    appearance = next
    return changed
  }
  func background(fallbackStyle: PracticeBackdropStyle, reduceMotion: Bool, themePreview: WebsiteThemePreview.Prepared? = nil,
    pendingTheme: PendingTheme? = nil,
    pendingBackground: WebsiteConfigBackgroundDisplay? = nil,
    onFailure: @escaping BackgroundFailureFeedback.Sink = { _ in }) throws -> WebsiteConfigPublishedBackground {
    if let pendingTheme, pendingTheme.owner != owner { throw WebsiteConfigPublishedPresentationError.wrongOwner }
    guard let snapshot = pendingBackground?.snapshot ?? backgroundSnapshot else { throw WebsiteConfigPublishedPresentationError.unprepared }
    return try .init(snapshot: snapshot, owner: owner, fallbackStyle: fallbackStyle,
      theme: pendingTheme?.appearance.theme ?? themePreview?.resolve(publication: publication, owner: owner, applied: themeChanges.applied) ?? appearance.theme, reduceMotion: reduceMotion, onFailure: onFailure)
  }
  func wholePreview(session: TypingSession, fontPreview: WebsiteConfigFontPreview.Prepared? = nil,
    themePreview: WebsiteThemePreview.Prepared? = nil,
    carets: (NSFont, WebsiteConfigNativePresentation) -> PromptCaretNativeView.Configuration,
    wrapLayout: PromptInputWrapLayout? = nil, fallbackPosition: PromptViewportFallbackPosition? = nil,
    onFailure: @escaping (UUID) -> Void,
    onReady: @escaping (PromptViewportPresentationReady) -> Void = { _ in }) throws -> PromptViewportPracticePrompt {
    let theme = try themePreview?.resolve(publication: publication, owner: owner, applied: themeChanges.applied) ?? appearance.theme
    return try .init(publication: publication, owner: owner, session: session, theme: theme, fontPreview: fontPreview,
      carets: { font, p in
        var config = carets(font, p); config.accent = theme.caret; return config
      }, wrapLayout: wrapLayout, fallbackPosition: fallbackPosition, onFailure: onFailure, onReady: onReady)
  }
  func inline(session: TypingSession, composition: String = "", fontPreview: WebsiteConfigFontPreview.Prepared? = nil,
    themePreview: WebsiteThemePreview.Prepared? = nil,
    carets: (PromptRendering, NSFont, WebsiteConfigNativePresentation) -> PromptCaretNativeView.Configuration,
    retirement: (PromptRendering, WebsiteConfigNativePresentation) -> PromptLineScrollContext,
    maximumTextWidth: CGFloat? = nil, wrapLayout: PromptInputWrapLayout? = nil,
    fallbackPosition: PromptViewportFallbackPosition? = nil,
    latestProjection: (() -> TapePromptProjectionSnapshot?)? = nil,
    onTapeWordsRemoved: ((PromptTapeWordRemoval) -> Void)? = nil) throws -> WebsiteConfigPublishedInlinePrompt {
    let theme = try themePreview?.resolve(publication: publication, owner: owner, applied: themeChanges.applied) ?? appearance.theme
    return try .init(publication: publication, owner: owner, session: session, composition: composition, theme: theme, fontPreview: fontPreview,
      carets: { rendering, font, p in
        var config = carets(rendering, font, p); config.accent = theme.caret; return config
      }, retirement: retirement, maximumTextWidth: maximumTextWidth, wrapLayout: wrapLayout,
      fallbackPosition: fallbackPosition, latestProjection: latestProjection, onTapeWordsRemoved: onTapeWordsRemoved)
  }
}
