import Foundation

/// Prepared, window-owned random controller effects. This value does not
/// publish a page, save a file, change legacy settings or render a theme.
@MainActor struct WebsiteRandomThemeConfiguration {
  struct Result {
    let steps: [WebsiteConfigNativeDraft]
    let draw: WebsiteRandomThemeSequence.Draw?
    let disablesSystemFollowing: Bool
  }
  private var sequence: WebsiteRandomThemeSequence
  private var favorites: WebsiteRandomThemeSequence.Favorites
  var active: String? { sequence.active }

  init(entries: [WebsiteRandomThemeSequence.Entry], draft: WebsiteConfigNativeDraft) throws {
    sequence = try .init(entries: entries)
    favorites = .init(draft.themes.favorites.map(\.rawValue))
  }

  /// Called after an accepted randomTheme setter. Save that setter's draft
  /// BEFORE using this result: the listener shuffles the runtime array only.
  mutating func modeChanged(draft: WebsiteConfigNativeDraft, customIDs: [String], pointsPerRem: Double,
    chooseIndex: (Int) -> Int = { Int.random(in: 0...$0) }) throws -> WebsiteConfigNativeDraft {
    try sequence.rebuild(mode: draft.themes.randomMode, favorites: &favorites, customIDs: customIDs, chooseIndex: chooseIndex)
    return try applyingFavoriteOrder(to: draft, pointsPerRem: pointsPerRem)
  }

  /// A real favorite setter or full store replacement breaks the old alias,
  /// even when the new values compare equal. Neither rebuilds the old bag.
  mutating func favoritesReplaced(draft: WebsiteConfigNativeDraft) {
    favorites.replace(with: draft.themes.favorites.map(\.rawValue))
  }
  @discardableResult mutating func clearActive() -> Bool { sequence.clearActive() }

  mutating func draw(draft: WebsiteConfigNativeDraft, customIDs: [String], systemIsDark: Bool,
    pointsPerRem: Double, context: WebsiteConfigRuntimeContext,
    chooseIndex: (Int) -> Int = { Int.random(in: 0...$0) }) throws -> Result {
    guard let draw = try sequence.next(mode: draft.themes.randomMode, favorites: &favorites,
      customIDs: customIDs, systemIsDark: systemIsDark, chooseIndex: chooseIndex) else {
      return .init(steps: [], draw: nil, disablesSystemFollowing: false)
    }
    let runtime = try applyingFavoriteOrder(to: draft, pointsPerRem: pointsPerRem)
    let flag = try WebsiteConfigNativeProfile.editDraft(runtime, key: "customTheme", value: .bool(false),
      pointsPerRem: pointsPerRem, context: context, nosave: true)
    var steps = [flag]
    // The source's awaited customTheme subscriber disables system following
    // after applying the random color. That saved setter reapplies Config.theme.
    if flag.themes.followsSystem {
      steps.append(try WebsiteConfigNativeProfile.editDraft(flag, key: "autoSwitchTheme", value: .bool(false),
        pointsPerRem: pointsPerRem, context: context))
    }
    return .init(steps: steps, draw: draw, disablesSystemFollowing: flag.themes.followsSystem)
  }

  private func applyingFavoriteOrder(to draft: WebsiteConfigNativeDraft, pointsPerRem: Double) throws -> WebsiteConfigNativeDraft {
    var projection = draft.projection
    projection.runtime["favThemes"] = .array(favorites.names.map(WebsiteConfigValue.string))
    // Retain the original setter events and settings snapshot. Inventing a
    // favThemes event here would incorrectly save or update the Solid store.
    return try draft.replacingProjection(projection, memory: draft.lazyMemory, pointsPerRem: pointsPerRem)
  }
}
