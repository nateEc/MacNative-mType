import Foundation
import Observation

/// Window-owned display state, never a configuration setter or input lease.
@MainActor @Observable final class WebsiteThemePreview {
  @MainActor struct Prepared {
    fileprivate let owner: UUID
    fileprivate let application: UUID
    fileprivate let applied: UUID
    let theme: ResolvedTheme
    func resolve(publication: WebsiteConfigCommitCoordinator.Publication, owner: UUID, applied: UUID) throws -> ResolvedTheme {
      guard self.owner == owner, publication.owner == owner else { throw WebsiteConfigPublishedPresentationError.wrongOwner }
      guard application == publication.applicationID, self.applied == applied else { throw WebsiteConfigPublishedPresentationError.staleThemePreview }
      return theme
    }
  }
  typealias Schedule = @MainActor (Int, @escaping @MainActor () -> Void) -> (@MainActor () -> Void)
  private var owner: UUID?
  private var application: UUID?
  private var visible: ResolvedTheme?
  private var indicatorOverride: ThemeCommandTarget?
  private var changes: WebsiteConfigPublishedPresentation.ThemeChanges?
  private(set) var isPreviewing = false
  @ObservationIgnored private weak var presentation: WebsiteConfigPublishedPresentation?
  @ObservationIgnored private let schedule: Schedule
  @ObservationIgnored private var cancelPending: (@MainActor () -> Void)?
  @ObservationIgnored private var request = UUID()

  init(schedule: @escaping Schedule = { milliseconds, action in
    let task = Task { @MainActor in
      do { try await Task.sleep(for: .milliseconds(milliseconds)) } catch { return }
      guard !Task.isCancelled else { return }; action()
    }
    return { task.cancel() }
  }) { self.schedule = schedule }

  func prepared(for next: WebsiteConfigPublishedPresentation, owner: UUID) -> Prepared? {
    let publication = next.publication
    guard self.owner == owner, publication.owner == owner, changes?.previewReset == next.themeChanges.previewReset,
      changes?.applied == next.themeChanges.applied, let visible else { return nil }
    return .init(owner: owner, application: publication.applicationID, applied: next.themeChanges.applied, theme: visible)
  }

  func synchronize(_ next: WebsiteConfigPublishedPresentation?) {
    guard let next else { stop(); return }
    let publication = next.publication
    guard owner == publication.owner else {
      stop(); owner = publication.owner; application = publication.applicationID; presentation = next
      changes = next.themeChanges; indicatorOverride = next.themeChanges.systemIndicator.map(ThemeCommandTarget.builtIn)
      return
    }
    presentation = next
    guard application != publication.applicationID || changes != next.themeChanges else { return }
    application = publication.applicationID
    if changes?.previewReset != next.themeChanges.previewReset { clear(applyTheme: false) }
    if changes?.applied != next.themeChanges.applied { visible = nil }
    if changes?.indicator != next.themeChanges.indicator { indicatorOverride = next.themeChanges.systemIndicator.map(ThemeCommandTarget.builtIn) }
    changes = next.themeChanges
  }

  @discardableResult func select(_ target: ThemeCommandTarget?, presentation: WebsiteConfigPublishedPresentation?,
    customThemes: [CustomThemeDefinition]) -> Bool {
    synchronize(presentation)
    guard let target else { clear(); return true }
    guard let presentation, owner == presentation.publication.owner else { return false }
    let theme: ResolvedTheme
    switch target {
    case .builtIn(let value): theme = value.resolvedTheme
    case .custom:
      guard let fields = try? WebsiteThemeCommand.fields(for: .select(target), customThemes: customThemes),
        let colors = fields.first(where: { $0.key == "customThemeColors" })?.value else { clear(); return false }
      var runtime = presentation.publication.draft.projection.runtime; runtime["customThemeColors"] = colors
      guard let themes = try? WebsiteConfigNativeThemes(runtime: runtime),
        let custom = try? themes.makeCustomTheme(id: UUID(), name: "Theme preview") else { clear(); return false }
      theme = custom.resolvedTheme
    }
    cancelPending?(); cancelPending = nil
    let token = UUID(); request = token
    cancelPending = schedule(250) { [weak self] in
      guard let self, self.request == token, self.owner != nil else { return }
      self.visible = theme; self.indicatorOverride = target; self.isPreviewing = true; self.cancelPending = nil
    }
    return true
  }

  func clear(applyTheme: Bool = true) {
    request = UUID(); cancelPending?(); cancelPending = nil
    if !applyTheme { isPreviewing = false; visible = nil; indicatorOverride = nil; return }
    guard isPreviewing else { return }
    isPreviewing = false
    if applyTheme, let presentation {
      visible = presentation.previewRestorationTheme
      indicatorOverride = nil
    } else { visible = nil; indicatorOverride = nil }
  }

  func stop() {
    request = UUID(); cancelPending?(); cancelPending = nil
    presentation = nil; owner = nil; application = nil; changes = nil; visible = nil; indicatorOverride = nil; isPreviewing = false
  }

  func systemAppearanceChanged(_ presentation: WebsiteConfigPublishedPresentation, isDark: Bool) {
    _ = presentation.updateSystemAppearance(isDark: isDark)
    synchronize(presentation)
  }

  func indicator(for next: WebsiteConfigPublishedPresentation, customThemes: [CustomThemeDefinition]) -> ThemeIndicatorPresentation? {
    let publication = next.publication
    guard owner == publication.owner else { return nil }
    let indicatorOverride = changes?.indicator == next.themeChanges.indicator
      ? self.indicatorOverride : next.themeChanges.systemIndicator.map(ThemeCommandTarget.builtIn)
    let themes = publication.draft.themes
    let randomIndicator = next.themeChanges.randomIndicator
    return Self.indicator(themes: themes, randomIndicator: randomIndicator,
      indicatorOverride: indicatorOverride, customThemes: customThemes)
  }

  static func indicator(themes: WebsiteConfigNativeThemes, randomIndicator: String? = nil,
    indicatorOverride: ThemeCommandTarget?, customThemes: [CustomThemeDefinition]) -> ThemeIndicatorPresentation {
    var name = randomIndicator ?? themes.theme.rawValue, isCustom = themes.customEnabled
    if themes.customEnabled {
      let match = WebsiteThemeCommand.matchingCustomTheme(themes, in: customThemes)
      name = match.map { "\($0.name) (custom)" } ?? "custom"
    }
    var favoriteTheme: AppTheme? = randomIndicator != nil ? randomIndicator.flatMap(AppTheme.init(rawValue:)) : themes.theme
    if let indicatorOverride {
      switch indicatorOverride {
      case .builtIn(let theme): name = theme.rawValue; favoriteTheme = theme; isCustom = false
      case .custom: name = "custom"; isCustom = true
      }
    }
    return .init(name: name.replacingOccurrences(of: "_", with: " "), isCustom: isCustom,
      isFavorite: !themes.customEnabled && (favoriteTheme.map(themes.favorites.contains) ?? false) && !isCustom)
  }
}

enum WebsiteThemeFooterAction: Equatable {
  case custom(Bool, emptyNotice: Bool), picker(ThemeQuickPickerScope)
  static func action(shift: Bool, customEnabled: Bool, authenticated: Bool, libraryCount: Int) -> Self {
    if !shift { return .picker(customEnabled ? .custom : .builtIn) }
    if customEnabled { return .custom(false, emptyNotice: false) }
    if authenticated && libraryCount < 1 { return .custom(false, emptyNotice: true) }
    return .custom(true, emptyNotice: false)
  }
}
