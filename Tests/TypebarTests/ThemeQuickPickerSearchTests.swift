import XCTest
@testable import Typebar

final class ThemeQuickPickerSearchTests: XCTestCase {
  func testKeyboardTargetsFollowVisibleOrderAndWrapWithoutSelectingEmptyResults() {
    let custom = customTheme(id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", name: "Ocean")
    let results = ThemeQuickPickerSearch.results(
      scope: .all, query: "", builtInThemes: [.paper, .grape], customThemes: [custom],
      favoriteThemeIDs: [ThemeFavoritePolicy.builtInID(for: .grape)])
    XCTAssertEqual(results.targets, [.builtIn(.grape), .builtIn(.paper), .custom(custom.id)])
    XCTAssertEqual(CommandPaletteKeyboardSelection.moved(current: 0, count: results.targets.count, offset: -1), 2)
    XCTAssertEqual(CommandPaletteKeyboardSelection.moved(current: 2, count: results.targets.count, offset: 1), 0)

    let empty = ThemeQuickPickerSearch.results(
      scope: .custom, query: "missing", builtInThemes: [.paper], customThemes: [custom],
      favoriteThemeIDs: [])
    XCTAssertTrue(empty.targets.isEmpty)
    XCTAssertNil(CommandPaletteKeyboardSelection.index(current: 0, count: empty.targets.count))
  }

  func testBuiltInSearchFindsDisplayNamesAndIDsWithFavoritesFirst() {
    let favorites = [
      ThemeFavoritePolicy.builtInID(for: .grape),
      ThemeFavoritePolicy.builtInID(for: .cherry_blossom),
    ]
    let builtIns: [AppTheme] = [.paper, .cherry_blossom, .grape]
    func results(_ query: String) -> [AppTheme] {
      ThemeQuickPickerSearch.results(
        scope: .all, query: query, builtInThemes: builtIns, customThemes: [],
        favoriteThemeIDs: favorites).builtInThemes
    }

    XCTAssertEqual(results(""), [.cherry_blossom, .grape, .paper])
    XCTAssertEqual(results("  CHERRY_blossom  "), [.cherry_blossom])
    XCTAssertEqual(results("樱花"), [.cherry_blossom])
    XCTAssertEqual(results("not-a-theme"), [])
  }

  func testCustomSearchIsAccentInsensitiveAndNeverShowsBuiltInsInCustomScope() {
    let creme = customTheme(id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", name: "Crème")
    let sunset = customTheme(id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", name: "Sunset")
    let favorites = [ThemeFavoritePolicy.customID(for: sunset.id)]

    let all = ThemeQuickPickerSearch.results(
      scope: .all, query: "", builtInThemes: [.paper], customThemes: [creme, sunset],
      favoriteThemeIDs: favorites)
    XCTAssertEqual(all.customThemes.map(\.id), [sunset.id, creme.id])

    let onlyCustom = ThemeQuickPickerSearch.results(
      scope: .custom, query: "CREME", builtInThemes: [.paper], customThemes: [creme, sunset],
      favoriteThemeIDs: favorites)
    XCTAssertTrue(onlyCustom.builtInThemes.isEmpty)
    XCTAssertEqual(onlyCustom.customThemes.map(\.id), [creme.id])

    let missing = ThemeQuickPickerSearch.results(
      scope: .custom, query: "missing", builtInThemes: [.paper], customThemes: [creme],
      favoriteThemeIDs: favorites)
    XCTAssertTrue(missing.builtInThemes.isEmpty)
    XCTAssertTrue(missing.customThemes.isEmpty)
  }

  private func customTheme(id: String, name: String) -> CustomThemeDefinition {
    .init(
      id: UUID(uuidString: id)!, name: name,
      background: .init(red: 0.1, green: 0.2, blue: 0.3),
      panel: .init(red: 0.2, green: 0.3, blue: 0.4),
      accent: .init(red: 0.7, green: 0.4, blue: 0.2), prefersDark: true)
  }
}
