import SwiftUI
import XCTest
@testable import Typebar

@MainActor
final class ThemeQuickSwitchMemoryTests: XCTestCase {
  private func withSettings(_ body: (AppSettings, UserDefaults) throws -> Void) rethrows {
    let suite = "TypebarTests.theme-switch-memory.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(AppSettings(defaults: defaults), defaults)
  }

  private func addThemes(_ settings: AppSettings) throws -> [CustomThemeDefinition] {
    try ["First Window", "Second Window"].map { name in
      try XCTUnwrap(settings.addCustomTheme(
        name: name, background: .black, panel: .gray, accent: .orange, prefersDark: true))
    }
  }

  private func action(_ settings: AppSettings) -> ThemeQuickSwitchAction {
    ThemeQuickSwitchPolicy.shiftClickAction(settings: settings)
  }

  func testSwitchingOffCustomThenBackRestoresTheChosenThemeAmongSeveral() throws {
    try withSettings { settings, _ in
      let themes = try addThemes(settings)
      settings.selectCustomTheme(themes[0].id)
      XCTAssertEqual(action(settings), .selectBuiltIn)
      ThemeCommandApplication.apply(.builtIn(.grove), to: settings)
      XCTAssertEqual(action(settings), .selectCustom(themes[0].id))
      if case .selectCustom(let id) = action(settings) {
        ThemeCommandApplication.apply(.custom(id), to: settings)
      }
      XCTAssertEqual(settings.activeCustomThemeID, themes[0].id)
      XCTAssertEqual(settings.theme, .grove)
      XCTAssertEqual(action(settings), .selectBuiltIn)
    }
  }

  func testDirectBuiltInSettingKeepsTheLastCustomChoice() throws {
    try withSettings { settings, _ in
      let themes = try addThemes(settings)
      settings.selectCustomTheme(themes[0].id)
      settings.theme = .paper
      XCTAssertNil(settings.activeCustomThemeID)
      XCTAssertEqual(action(settings), .selectCustom(themes[0].id))
    }
  }

  func testTheLastExplicitCustomChoiceReplacesAnEarlierOne() throws {
    try withSettings { settings, _ in
      let themes = try addThemes(settings)
      settings.selectCustomTheme(themes[0].id)
      settings.selectBuiltInTheme(.grove)
      settings.selectCustomTheme(themes[1].id)
      settings.selectBuiltInTheme(.paper)
      XCTAssertEqual(action(settings), .selectCustom(themes[1].id))
    }
  }

  func testRestartWithBuiltInSelectedRestoresTheRememberedCustomChoice() throws {
    try withSettings { settings, defaults in
      let themes = try addThemes(settings)
      settings.selectCustomTheme(themes[0].id)
      settings.selectBuiltInTheme(.grove)
      let restored = AppSettings(defaults: defaults)
      XCTAssertEqual(restored.currentThemeQuickPickerTarget(for: .dark), .builtIn(.grove))
      XCTAssertEqual(action(restored), .selectCustom(themes[0].id))
    }
  }

  func testExportDecodeAndApplyKeepTheInactiveCustomChoice() throws {
    try withSettings { source, _ in
      let themes = try addThemes(source)
      source.selectCustomTheme(themes[0].id)
      source.selectBuiltInTheme(.grove)
      let decoded = try JSONDecoder().decode(
        AppSettingsSnapshot.self, from: JSONEncoder().encode(source.snapshot))
      withSettings { destination, _ in
        destination.apply(decoded)
        XCTAssertEqual(destination.currentThemeQuickPickerTarget(for: .dark), .builtIn(.grove))
        XCTAssertEqual(action(destination), .selectCustom(themes[0].id))
      }
    }
  }

  func testLegacyActiveSelectionSeedsMemoryButInactiveLegacyDataDoesNotInventAChoice() throws {
    try withSettings { settings, defaults in
      let themes = try addThemes(settings)
      settings.selectCustomTheme(themes[0].id)
      var payload = try XCTUnwrap(JSONSerialization.jsonObject(
        with: JSONEncoder().encode(settings.snapshot)) as? [String: Any])
      payload.removeValue(forKey: "lastCustomThemeID")
      let legacy = try JSONSerialization.data(withJSONObject: payload)
      defaults.set(legacy, forKey: "appSettings.v1")
      let restored = AppSettings(defaults: defaults)
      restored.selectBuiltInTheme(.grove)
      XCTAssertEqual(action(restored), .selectCustom(themes[0].id))

      payload.removeValue(forKey: "activeCustomThemeID")
      let inactiveLegacy = try JSONDecoder().decode(
        AppSettingsSnapshot.self, from: JSONSerialization.data(withJSONObject: payload))
      restored.apply(inactiveLegacy)
      XCTAssertNil(restored.lastCustomThemeID)
      XCTAssertEqual(action(restored), .chooseCustom)
    }
  }

  func testActiveSelectionWinsOverAnInconsistentRememberedIDAndUnknownIDsAreDiscarded() throws {
    try withSettings { settings, _ in
      let themes = try addThemes(settings)
      settings.selectCustomTheme(themes[0].id)
      var payload = try XCTUnwrap(JSONSerialization.jsonObject(
        with: JSONEncoder().encode(settings.snapshot)) as? [String: Any])
      payload["lastCustomThemeID"] = themes[1].id.uuidString
      let decoded = try JSONDecoder().decode(
        AppSettingsSnapshot.self, from: JSONSerialization.data(withJSONObject: payload))
      settings.apply(decoded)
      settings.selectBuiltInTheme(.grove)
      XCTAssertEqual(action(settings), .selectCustom(themes[0].id))

      payload.removeValue(forKey: "activeCustomThemeID")
      payload["lastCustomThemeID"] = UUID().uuidString
      let invalid = try JSONDecoder().decode(
        AppSettingsSnapshot.self, from: JSONSerialization.data(withJSONObject: payload))
      settings.apply(invalid)
      XCTAssertNil(settings.lastCustomThemeID)
      XCTAssertEqual(action(settings), .chooseCustom)
    }
  }

  func testDeletedRememberedThemeIsNotRecoveredLocallyOrThroughArchiveMerge() throws {
    try withSettings { settings, _ in
      let themes = try addThemes(settings)
      settings.selectCustomTheme(themes[0].id)
      settings.selectBuiltInTheme(.grove)
      let beforeRemoval = settings.snapshot
      // Exercise directory changes without writing production deletion tombstones.
      settings.customThemes.removeAll { $0.id == themes[0].id }
      XCTAssertNil(settings.lastCustomThemeID)
      XCTAssertEqual(action(settings), .selectCustom(themes[1].id))
      settings.customThemes = []
      XCTAssertEqual(action(settings), .noCustomThemes)

      let local = TypebarArchive(
        exportedAt: Date(timeIntervalSince1970: 100), settings: beforeRemoval,
        deletedCustomThemeIDs: [themes[0].id], results: [], presets: [])
      let remote = TypebarArchive(
        exportedAt: Date(timeIntervalSince1970: 101), settings: beforeRemoval, results: [], presets: [])
      let merged = try TypebarArchiveConflictMerge.merge(local: local, remote: remote)
      XCTAssertNil(merged.settings.lastCustomThemeID)
      XCTAssertEqual(merged.settings.customThemes.map(\.id), [themes[1].id])
      XCTAssertEqual(merged.deletedCustomThemeIDs, [themes[0].id])
    }
  }

  func testThemePresetsCarryMemoryButUnrelatedPartialPresetsLeaveItAlone() throws {
    try withSettings { settings, _ in
      let themes = try addThemes(settings)
      settings.selectCustomTheme(themes[0].id)
      settings.selectBuiltInTheme(.grove)
      let source = SavedTestPreset(configuration: .timed(seconds: 30), settingsSnapshot: settings.snapshot)
      settings.selectCustomTheme(themes[1].id)
      settings.selectBuiltInTheme(.paper)
      let current = SavedTestPreset(configuration: .words(50), settingsSnapshot: settings.snapshot)
      let themed = PresetApplicationPolicy.applying(current: current, preset: source.with(settingGroups: [.theme]))
      settings.apply(try XCTUnwrap(themed.settingsSnapshot))
      XCTAssertEqual(action(settings), .selectCustom(themes[0].id))

      let unrelated = PresetApplicationPolicy.applying(current: current, preset: source.with(settingGroups: [.sound]))
      settings.apply(try XCTUnwrap(unrelated.settingsSnapshot))
      XCTAssertEqual(action(settings), .selectCustom(themes[1].id))
    }
  }

  func testRandomAndPreviewDoNotReplaceTheLastExplicitChoiceAndPolicyDoesNotWrite() throws {
    try withSettings { settings, defaults in
      let themes = try addThemes(settings)
      settings.selectCustomTheme(themes[0].id)
      settings.selectBuiltInTheme(.grove)
      settings.randomThemeMode = .custom
      settings.randomizeTheme(for: .dark, using: 1)
      XCTAssertEqual(settings.currentThemeQuickPickerTarget(for: .dark), .custom(themes[1].id))
      XCTAssertEqual(settings.lastCustomThemeID, themes[0].id)
      _ = ThemePreviewPresentation(settings: settings, systemColorScheme: .dark, previewTarget: .custom(themes[1].id))
      settings.followSystemTheme = true
      let saved = defaults.data(forKey: "appSettings.v1")
      XCTAssertEqual(action(settings), .selectCustom(themes[0].id))
      XCTAssertEqual(action(settings), .selectCustom(themes[0].id))
      XCTAssertTrue(settings.followSystemTheme)
      XCTAssertTrue(defaults.data(forKey: "appSettings.v1") == saved, "Reading the toggle action must not persist settings")
    }
  }

  func testShiftFromARandomCustomPreviewRestoresTheExplicitCustomChoice() throws {
    try withSettings { settings, _ in
      let themes = try addThemes(settings)
      settings.selectCustomTheme(themes[0].id)
      settings.selectBuiltInTheme(.grove)
      settings.randomThemeMode = .custom
      settings.randomizeTheme(for: .dark, using: 1)
      XCTAssertEqual(settings.currentThemeQuickPickerTarget(for: .dark), .custom(themes[1].id))
      XCTAssertEqual(action(settings), .selectCustom(themes[0].id))
      if case .selectCustom(let id) = action(settings) {
        ThemeCommandApplication.apply(.custom(id), to: settings)
      }
      XCTAssertEqual(settings.currentThemeQuickPickerTarget(for: .dark), .custom(themes[0].id))
      XCTAssertEqual(settings.randomThemeMode, .custom)
      XCTAssertEqual(action(settings), .selectBuiltIn)
    }
  }

  func testWithoutHistorySeveralThemesStillRequireAChoiceAndAStaleIDIsIgnored() throws {
    try withSettings { settings, _ in
      let themes = try addThemes(settings)
      settings.apply(.init(customThemes: themes))
      XCTAssertNil(settings.lastCustomThemeID)
      XCTAssertEqual(action(settings), .chooseCustom)
      XCTAssertEqual(ThemeQuickSwitchPolicy.shiftClickAction(
        activeCustomThemeID: nil, customThemes: themes, lastCustomThemeID: UUID()), .chooseCustom)
      XCTAssertEqual(ThemeQuickSwitchPolicy.shiftClickAction(
        activeCustomThemeID: nil, customThemes: [themes[0]], lastCustomThemeID: UUID()), .selectCustom(themes[0].id))
      XCTAssertEqual(ThemeQuickSwitchPolicy.shiftClickAction(
        activeCustomThemeID: nil, customThemes: [], lastCustomThemeID: UUID()), .noCustomThemes)
    }
  }
}
