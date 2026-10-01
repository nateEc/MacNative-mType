import SwiftUI
import XCTest
@testable import Typebar

@MainActor
final class ThemePreviewPresentationTests: XCTestCase {
  private func withSettings(_ body: (AppSettings, UserDefaults) throws -> Void) rethrows {
    let name = "TypebarTests.theme-preview-presentation.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    try body(AppSettings(defaults: defaults), defaults)
  }

  func testBuiltInPreviewUsesOneThemeForColorsIndicatorFavoriteAndAppearance() {
    withSettings { settings, defaults in
      settings.selectBuiltInTheme(.midnight)
      settings.followSystemTheme = false
      settings.favoriteThemeIDs = [ThemeFavoritePolicy.builtInID(for: .paper)]
      let saved = defaults.dictionaryRepresentation() as NSDictionary
      let preview = ThemePreviewPresentation(
        settings: settings, systemColorScheme: .dark, previewTarget: .builtIn(.paper))
      XCTAssertEqual(preview.target, .builtIn(.paper))
      XCTAssertEqual(preview.theme.background, AppTheme.paper.resolvedTheme.background)
      XCTAssertEqual(preview.theme.accent, AppTheme.paper.accent)
      XCTAssertEqual(preview.preferredColorScheme, .light)
      XCTAssertEqual(preview.indicator, .init(name: AppTheme.paper.displayName,
                                             isCustom: false, isFavorite: true))
      XCTAssertEqual(settings.theme, .midnight)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, saved)
    }
  }

  func testCustomPreviewDoesNotSelectOrPersistTheCustomTheme() throws {
    try withSettings { settings, defaults in
      settings.selectBuiltInTheme(.midnight)
      settings.followSystemTheme = false
      let custom = try XCTUnwrap(settings.addCustomTheme(
        name: "Cloud Window", background: .white, panel: .gray, accent: .orange, prefersDark: false))
      settings.selectBuiltInTheme(.midnight)
      settings.favoriteThemeIDs = [ThemeFavoritePolicy.customID(for: custom.id)]
      let saved = defaults.dictionaryRepresentation() as NSDictionary
      let preview = ThemePreviewPresentation(
        settings: settings, systemColorScheme: .dark, previewTarget: .custom(custom.id))
      XCTAssertEqual(preview.target, .custom(custom.id))
      XCTAssertEqual(preview.theme.accent, custom.accent.color)
      XCTAssertEqual(preview.indicator, .init(name: custom.name, isCustom: true, isFavorite: true))
      XCTAssertEqual(preview.preferredColorScheme, .light)
      XCTAssertNil(settings.activeCustomThemeID)
      let restored = ThemePreviewPresentation(settings: settings, systemColorScheme: .dark, previewTarget: nil)
      XCTAssertEqual(restored.target, .builtIn(.midnight))
      XCTAssertEqual(restored.preferredColorScheme, .dark)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, saved)
    }
  }

  func testPreviewOverridesSystemAppearanceThenRestoresTheCurrentSystemTheme() {
    withSettings { settings, defaults in
      settings.systemLightTheme = .paper
      settings.systemDarkTheme = .grove
      settings.followSystemTheme = true
      let saved = defaults.dictionaryRepresentation() as NSDictionary
      let preview = ThemePreviewPresentation(
        settings: settings, systemColorScheme: .dark, previewTarget: .builtIn(.paper))
      XCTAssertEqual(preview.preferredColorScheme, .light)
      XCTAssertEqual(preview.indicator.name, AppTheme.paper.displayName)
      let restored = ThemePreviewPresentation(settings: settings, systemColorScheme: .dark, previewTarget: nil)
      XCTAssertEqual(restored.target, .builtIn(.grove))
      XCTAssertEqual(restored.indicator.name, AppTheme.grove.displayName)
      XCTAssertNil(restored.preferredColorScheme)
      XCTAssertTrue(settings.followSystemTheme)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, saved)
    }
  }

  func testClearingPreviewUsesNewSystemStateInsteadOfAStaleSnapshot() {
    withSettings { settings, _ in
      settings.systemLightTheme = .paper
      settings.systemDarkTheme = .grove
      settings.followSystemTheme = true
      _ = ThemePreviewPresentation(settings: settings, systemColorScheme: .dark, previewTarget: .builtIn(.grape))
      let restored = ThemePreviewPresentation(settings: settings, systemColorScheme: .light, previewTarget: nil)
      XCTAssertEqual(restored.target, .builtIn(.paper))
      XCTAssertEqual(restored.theme.colorScheme, .light)
      XCTAssertNil(restored.preferredColorScheme)
    }
  }

  func testCancelPreviewPreservesTheEphemeralRandomCustomTheme() throws {
    try withSettings { settings, defaults in
      settings.selectBuiltInTheme(.midnight)
      settings.followSystemTheme = false
      let custom = try XCTUnwrap(settings.addCustomTheme(
        name: "Evening Window", background: .black, panel: .gray, accent: .orange, prefersDark: true))
      settings.selectBuiltInTheme(.midnight)
      settings.randomThemeMode = .custom
      settings.randomizeTheme(for: .dark, using: 0)
      let saved = defaults.dictionaryRepresentation() as NSDictionary
      _ = ThemePreviewPresentation(settings: settings, systemColorScheme: .dark, previewTarget: .builtIn(.paper))
      let restored = ThemePreviewPresentation(settings: settings, systemColorScheme: .dark, previewTarget: nil)
      XCTAssertEqual(restored.target, .custom(custom.id))
      XCTAssertEqual(restored.indicator.name, custom.name)
      XCTAssertEqual(restored.theme.accent, custom.accent.color)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, saved)
      XCTAssertEqual(AppSettings(defaults: defaults).currentThemeQuickPickerTarget(for: .dark), .builtIn(.midnight))
    }
  }

  func testMissingCustomPreviewFallsBackWithoutForcingSystemAppearance() {
    withSettings { settings, defaults in
      settings.systemDarkTheme = .grove
      settings.followSystemTheme = true
      let saved = defaults.dictionaryRepresentation() as NSDictionary
      let preview = ThemePreviewPresentation(
        settings: settings, systemColorScheme: .dark, previewTarget: .custom(UUID()))
      XCTAssertEqual(preview.target, .builtIn(.grove))
      XCTAssertEqual(preview.indicator.name, AppTheme.grove.displayName)
      XCTAssertEqual(preview.theme.background, AppTheme.grove.resolvedTheme.background)
      XCTAssertNil(preview.preferredColorScheme)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, saved)
    }
  }

  func testVisiblePickerTargetChangesAndEmptyResultsClearPreview() {
    let favorites = [ThemeFavoritePolicy.builtInID(for: .grape)]
    let all = ThemeQuickPickerSearch.results(scope: .all, query: "", builtInThemes: [.paper, .grape],
                                            customThemes: [], favoriteThemeIDs: favorites)
    XCTAssertEqual(all.target(at: 0), .builtIn(.grape))
    XCTAssertEqual(all.target(at: 1), .builtIn(.paper))
    let filtered = ThemeQuickPickerSearch.results(scope: .all, query: "paper", builtInThemes: [.paper, .grape],
                                                 customThemes: [], favoriteThemeIDs: favorites)
    XCTAssertEqual(filtered.target(at: 0), .builtIn(.paper))
    let empty = ThemeQuickPickerSearch.results(scope: .all, query: "missing", builtInThemes: [.paper, .grape],
                                              customThemes: [], favoriteThemeIDs: favorites)
    XCTAssertNil(empty.target(at: 0))
  }
}
