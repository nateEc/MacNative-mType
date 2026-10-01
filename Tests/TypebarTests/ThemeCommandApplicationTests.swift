import SwiftUI
import XCTest
@testable import Typebar

@MainActor
final class ThemeCommandApplicationTests: XCTestCase {
  private func withSettings(_ body: (AppSettings, UserDefaults) throws -> Void) rethrows {
    let name = "TypebarTests.theme-command-application.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    try body(AppSettings(defaults: defaults), defaults)
  }

  private func addTheme(_ settings: AppSettings) throws -> CustomThemeDefinition {
    try XCTUnwrap(settings.addCustomTheme(
      name: "Evening Window", background: .black, panel: .gray, accent: .orange, prefersDark: true))
  }

  func testMissingCustomTargetDoesNotDisableSystemFollowingOrPersistChanges() {
    withSettings { settings, defaults in
      settings.selectBuiltInTheme(.grove)
      settings.followSystemTheme = true
      let saved = defaults.data(forKey: "appSettings.v1")
      XCTAssertFalse(ThemeCommandApplication.apply(.custom(UUID()), to: settings))
      XCTAssertTrue(settings.followSystemTheme)
      XCTAssertEqual(settings.theme, .grove)
      XCTAssertNil(settings.activeCustomThemeID)
      XCTAssertTrue(defaults.data(forKey: "appSettings.v1") == saved, "Rejected target must not rewrite Typebar settings")
    }
  }

  func testCapturedCommandRejectsAThemeRemovedBeforeExecution() throws {
    try withSettings { settings, defaults in
      let theme = try addTheme(settings)
      let item = try XCTUnwrap(ThemeCommandCatalog.items(
        builtInThemes: [], customThemes: settings.customThemes, favoriteThemeIDs: []).first)
      settings.selectBuiltInTheme(.grove)
      settings.followSystemTheme = true
      // Simulate a catalog update without writing production deletion tombstones.
      settings.customThemes.removeAll { $0.id == theme.id }
      let saved = defaults.data(forKey: "appSettings.v1")
      let target = try XCTUnwrap(ThemeCommandCatalog.target(for: item.id))
      XCTAssertFalse(ThemeCommandApplication.apply(target, to: settings))
      XCTAssertTrue(settings.followSystemTheme)
      XCTAssertEqual(settings.currentThemeQuickPickerTarget(for: .dark), .builtIn(.midnight))
      XCTAssertTrue(defaults.data(forKey: "appSettings.v1") == saved, "Expired command must not rewrite Typebar settings")
    }
  }

  func testValidBuiltInCommitDisablesSystemFollowingAndPersistsSelection() throws {
    try withSettings { settings, defaults in
      let custom = try addTheme(settings)
      settings.followSystemTheme = true
      settings.favoriteThemeIDs = [ThemeFavoritePolicy.customID(for: custom.id)]
      XCTAssertTrue(ThemeCommandApplication.apply(.builtIn(.paper), to: settings))
      XCTAssertFalse(settings.followSystemTheme)
      XCTAssertNil(settings.activeCustomThemeID)
      XCTAssertEqual(settings.theme, .paper)
      XCTAssertEqual(settings.customThemes.map(\.id), [custom.id])
      XCTAssertTrue(settings.isFavoriteCustomTheme(custom.id))
      let restored = AppSettings(defaults: defaults)
      XCTAssertFalse(restored.followSystemTheme)
      XCTAssertEqual(restored.currentThemeQuickPickerTarget(for: .dark), .builtIn(.paper))
    }
  }

  func testValidCustomCommitPreservesThePreviousBuiltInAndPersistsCustomSelection() throws {
    try withSettings { settings, defaults in
      let custom = try addTheme(settings)
      settings.selectBuiltInTheme(.grove)
      settings.followSystemTheme = true
      XCTAssertTrue(ThemeCommandApplication.apply(.custom(custom.id), to: settings))
      XCTAssertFalse(settings.followSystemTheme)
      XCTAssertEqual(settings.activeCustomThemeID, custom.id)
      XCTAssertEqual(settings.theme, .grove)
      let restored = AppSettings(defaults: defaults)
      XCTAssertEqual(restored.currentThemeQuickPickerTarget(for: .light), .custom(custom.id))
      XCTAssertEqual(restored.resolvedTheme(for: .light).accent, custom.accent.color)
      XCTAssertFalse(restored.followSystemTheme)
    }
  }

  func testMissingTargetPreservesAnEphemeralRandomCustomSelection() throws {
    try withSettings { settings, defaults in
      let custom = try addTheme(settings)
      settings.selectBuiltInTheme(.paper)
      settings.randomThemeMode = .custom
      settings.randomizeTheme(for: .dark, using: 0)
      let saved = defaults.data(forKey: "appSettings.v1")
      XCTAssertFalse(ThemeCommandApplication.apply(.custom(UUID()), to: settings))
      XCTAssertEqual(settings.currentThemeQuickPickerTarget(for: .dark), .custom(custom.id))
      XCTAssertEqual(settings.randomThemeMode, .custom)
      XCTAssertEqual(settings.theme, .paper)
      XCTAssertTrue(defaults.data(forKey: "appSettings.v1") == saved, "Rejected target must not rewrite random-theme settings")
    }
  }
}
