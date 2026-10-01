import SwiftUI
import XCTest
@testable import Typebar

@MainActor
final class ThemeQuickPickerScopeTests: XCTestCase {
  private func withSettings(_ body: (AppSettings, UserDefaults) throws -> Void) rethrows {
    let suite = "TypebarTests.theme-picker-scope.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(AppSettings(defaults: defaults), defaults)
  }

  private func addTheme(_ settings: AppSettings, name: String = "Local Window") throws -> CustomThemeDefinition {
    try XCTUnwrap(settings.addCustomTheme(
      name: name, background: .black, panel: .gray, accent: .orange, prefersDark: true))
  }

  func testAnEnabledManualCustomThemeOpensOnlyTheCustomList() throws {
    try withSettings { settings, _ in
      _ = try addTheme(settings)
      XCTAssertEqual(ThemeQuickSwitchPolicy.pickerScope(settings: settings), .custom)
    }
  }

  func testABuiltInSelectionDoesNotOpenCustomsJustBecauseThereIsSelectionMemory() throws {
    try withSettings { settings, _ in
      let custom = try addTheme(settings)
      settings.selectBuiltInTheme(.grove)
      XCTAssertEqual(settings.lastCustomThemeID, custom.id)
      XCTAssertEqual(ThemeQuickSwitchPolicy.pickerScope(settings: settings), .builtIn)
    }
  }

  func testRandomCustomAndSystemFollowingDoNotMasqueradeAsManualCustomMode() throws {
    try withSettings { settings, _ in
      let custom = try addTheme(settings)
      settings.randomThemeMode = .custom
      settings.randomizeTheme(for: .dark, using: 0)
      XCTAssertEqual(settings.currentThemeQuickPickerTarget(for: .dark), .custom(custom.id))
      XCTAssertEqual(ThemeQuickSwitchPolicy.pickerScope(settings: settings), .builtIn)
      settings.followSystemTheme = true
      XCTAssertEqual(ThemeQuickSwitchPolicy.pickerScope(settings: settings), .builtIn)
    }
  }

  func testBuiltInScopeContainsOnlyBuiltInsAndKeepsFavoriteKeyboardOrder() throws {
    try withSettings { settings, _ in
      let sameName = try addTheme(settings, name: AppTheme.paper.displayName)
      let results = ThemeQuickPickerSearch.results(
        scope: .builtIn, query: "", builtInThemes: [.paper, .grove],
        customThemes: [sameName], favoriteThemeIDs: [ThemeFavoritePolicy.builtInID(for: .grove)])
      XCTAssertEqual(results.builtInThemes, [.grove, .paper])
      XCTAssertTrue(results.customThemes.isEmpty)
      XCTAssertEqual(results.target(at: 0), .builtIn(.grove))
      XCTAssertEqual(results.target(at: 1), .builtIn(.paper))
    }
  }

  func testSearchingACustomOnlyNameCannotLeakIntoBuiltInScopeOrActivateIt() throws {
    try withSettings { settings, _ in
      let custom = try addTheme(settings)
      let results = ThemeQuickPickerSearch.results(
        scope: .builtIn, query: custom.name, builtInThemes: [.paper],
        customThemes: [custom], favoriteThemeIDs: [])
      XCTAssertTrue(results.isEmpty)
      XCTAssertNil(results.target(at: 0))
    }
  }

  func testAllScopeAndCommandPaletteStillProvideBothThemeCategories() throws {
    try withSettings { settings, _ in
      let custom = try addTheme(settings)
      let results = ThemeQuickPickerSearch.results(
        scope: .all, query: "", builtInThemes: [.paper], customThemes: [custom], favoriteThemeIDs: [])
      XCTAssertEqual(results.targets, [.builtIn(.paper), .custom(custom.id)])
      let commands = ThemeCommandCatalog.items(
        builtInThemes: [.paper], customThemes: [custom], favoriteThemeIDs: [])
      let commandTargets = commands.compactMap { ThemeCommandCatalog.target(for: $0.id) }
      XCTAssertEqual(commandTargets.count, results.targets.count)
      for target in results.targets { XCTAssertTrue(commandTargets.contains(target)) }
    }
  }

  func testScopeLookupIsReadOnlyAndMissingCustomIdentityFallsBackToBuiltIns() throws {
    try withSettings { settings, defaults in
      let custom = try addTheme(settings)
      settings.customThemes.removeAll { $0.id == custom.id }
      let saved = defaults.data(forKey: "appSettings.v1")
      XCTAssertEqual(ThemeQuickSwitchPolicy.pickerScope(settings: settings), .builtIn)
      XCTAssertEqual(settings.activeCustomThemeID, custom.id)
      XCTAssertTrue(defaults.data(forKey: "appSettings.v1") == saved, "Scope lookup must not rewrite settings")
    }
  }
}
