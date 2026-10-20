import XCTest

@testable import Typebar

@MainActor
final class ThresholdPreferencesTests: XCTestCase {
  private func withSettings(source: Bool = true, _ body: (AppSettings, UserDefaults) throws -> Void)
    throws
  {
    let suite = "typebar.threshold-preferences.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    if source {
      var raw = PracticeThresholdConfiguration()
      try raw.apply(.minimumWpm(mode: .off, customValue: 37))
      XCTAssertTrue(
        ThresholdSettingsStore(defaults: defaults).save(
          PracticeThresholdSource(configuration: raw).applying(to: AppSettingsSnapshot())))
    }
    try body(AppSettings(defaults: defaults), defaults)
  }

  func testToggleRestoresRememberedValuesInsteadOfLegacyDefaults() throws {
    try withSettings { settings, defaults in
      let controls = PracticeThresholdPreferences(settings: settings)
      controls.wpmEnabled.wrappedValue = true
      controls.accuracyEnabled.wrappedValue = true
      XCTAssertEqual(settings.minimumWpm, 37)
      XCTAssertEqual(settings.minimumAccuracy, 90)
      controls.wpmEnabled.wrappedValue = false
      controls.wpmEnabled.wrappedValue = true
      XCTAssertEqual(
        AppSettings(defaults: defaults).thresholdConfiguration?.minimumWpmCustomValue, 37)
    }
  }

  func testEnabledZeroIsNotDisplayedAsOff() throws {
    try withSettings { settings, _ in
      XCTAssertTrue(
        settings.updateThresholdConfiguration(.minimumWpm(mode: .custom, customValue: 0)))
      XCTAssertTrue(
        settings.updateThresholdConfiguration(.minimumAccuracy(mode: .custom, customValue: 0)))
      let controls = PracticeThresholdPreferences(settings: settings)
      XCTAssertTrue(controls.wpmEnabled.wrappedValue)
      XCTAssertTrue(controls.accuracyEnabled.wrappedValue)
    }
  }

  func testValueBindingsKeepModesAndZeroAcrossReload() throws {
    try withSettings { settings, defaults in
      let controls = PracticeThresholdPreferences(settings: settings)
      controls.wpmEnabled.wrappedValue = true
      controls.accuracyEnabled.wrappedValue = true
      controls.wpm.wrappedValue = 0
      controls.accuracy.wrappedValue = 0
      controls.burstMode.wrappedValue = .flex
      controls.burst.wrappedValue = 0
      let reopened = PracticeThresholdPreferences(settings: AppSettings(defaults: defaults))
      XCTAssertTrue(reopened.wpmEnabled.wrappedValue)
      XCTAssertTrue(reopened.accuracyEnabled.wrappedValue)
      XCTAssertEqual(reopened.burstMode.wrappedValue, .flex)
      XCTAssertEqual(reopened.burst.wrappedValue, 0)
      controls.burstMode.wrappedValue = .fixed
      XCTAssertEqual(controls.burstMode.wrappedValue, .fixed)
      XCTAssertEqual(controls.burst.wrappedValue, 0)
      controls.wpmEnabled.wrappedValue = false
      controls.wpm.wrappedValue = 22.5
      XCTAssertFalse(controls.wpmEnabled.wrappedValue)
      XCTAssertEqual(controls.wpm.wrappedValue, 22.5)
    }
  }

  func testBurstOffAndOnRetainMemory() throws {
    try withSettings { settings, _ in
      let controls = PracticeThresholdPreferences(settings: settings)
      controls.burstMode.wrappedValue = .fixed
      controls.burst.wrappedValue = 60.2
      controls.burstMode.wrappedValue = .off
      XCTAssertEqual(controls.burst.wrappedValue, 60.2)
      controls.burstMode.wrappedValue = .flex
      XCTAssertEqual(controls.burst.wrappedValue, 60.2)
    }
  }

  func testFutureStorageRejectsAllBindingsWithoutFallbackOrSuccess() throws {
    try withSettings { settings, defaults in
      let before = settings.snapshot
      let future = Data("{\"version\":5}".utf8)
      defaults.set(future, forKey: "appSettings.v4")
      var results: [Bool] = []
      for candidate in [settings, AppSettings(defaults: defaults)] {
        let controls = PracticeThresholdPreferences(
          settings: candidate, onResult: { results.append($0) })
        controls.wpmEnabled.wrappedValue = true
        controls.accuracyEnabled.wrappedValue = true
        controls.wpm.wrappedValue = 35
        controls.accuracy.wrappedValue = 96
        controls.burstMode.wrappedValue = .fixed
        controls.burst.wrappedValue = 60
      }
      XCTAssertEqual(results, Array(repeating: false, count: 12))
      XCTAssertEqual(settings.snapshot, before)
      XCTAssertEqual(defaults.data(forKey: "appSettings.v4"), future)
      XCTAssertNil(defaults.object(forKey: "appSettings.v1"))
    }
  }

  func testLockAndPreflightPreventChanges() throws {
    try withSettings { settings, defaults in
      let before = defaults.data(forKey: "appSettings.v4")
      var results: [Bool] = []
      let preflight = PracticeThresholdPreferences(
        settings: settings, acceptsChange: { false }, onResult: { results.append($0) })
      preflight.wpmEnabled.wrappedValue = true
      XCTAssertTrue(results.isEmpty)
      let owner = UUID()
      settings.setNoQuitConfigurationLock(true, for: owner)
      defer { settings.setNoQuitConfigurationLock(false, for: owner) }
      let controls = PracticeThresholdPreferences(
        settings: settings, onResult: { results.append($0) })
      controls.wpmEnabled.wrappedValue = true
      controls.burst.wrappedValue = 50
      XCTAssertEqual(results, [false, false])
      XCTAssertEqual(defaults.data(forKey: "appSettings.v4"), before)
    }
  }

  func testLegacyControlsDoNotUpgradeAndKeepOldEnableDefaults() throws {
    try withSettings(source: false) { settings, defaults in
      let controls = PracticeThresholdPreferences(settings: settings)
      controls.wpmEnabled.wrappedValue = true
      controls.accuracyEnabled.wrappedValue = true
      XCTAssertEqual(controls.wpm.wrappedValue, 60)
      XCTAssertEqual(controls.accuracy.wrappedValue, 95)
      controls.wpm.wrappedValue = 0
      XCTAssertFalse(controls.wpmEnabled.wrappedValue)
      XCTAssertNil(defaults.object(forKey: "appSettings.v4"))
    }
  }

  func testInvalidValuesDoNotNormalizeIntoSuccessfulChanges() throws {
    for source in [true, false] {
      try withSettings(source: source) { settings, _ in
        let before = settings.snapshot
        var results: [Bool] = []
        let controls = PracticeThresholdPreferences(
          settings: settings, onResult: { results.append($0) })
        controls.wpm.wrappedValue = .nan
        controls.accuracy.wrappedValue = 101
        controls.burst.wrappedValue = -1
        XCTAssertEqual(results, [false, false, false])
        XCTAssertEqual(settings.snapshot, before)
      }
    }
  }

  func testProductionPageUsesSourceAwareBindings() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let view = try String(
      contentsOf: root.appendingPathComponent("Sources/Typebar/PreferencesView.swift"),
      encoding: .utf8)
    for name in ["accuracyEnabled", "wpmEnabled", "accuracy", "wpm", "burstMode", "burst"] {
      XCTAssertTrue(view.contains("thresholdPreferences.\(name)"))
    }
    XCTAssertFalse(view.contains("restartingConfigurationBinding($settings.minimum"))
    XCTAssertFalse(view.contains("if settings.minimumAccuracy > 0"))
    XCTAssertFalse(view.contains("if settings.minimumWpm > 0"))
    XCTAssertTrue(view.contains("acceptsChange: { acceptsRestartingConfigurationChange() }"))
  }
}
