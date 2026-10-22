import XCTest
@testable import Typebar

@MainActor
final class ThresholdAppSettingsTests: XCTestCase {
  private func snapshot() throws -> AppSettingsSnapshot {
    var raw = PracticeThresholdConfiguration()
    try raw.apply(.minimumWpm(mode: .off, customValue: 37))
    try raw.apply(.minimumWordBurst(mode: .flex, customValue: 0))
    return PracticeThresholdSource(configuration: raw).applying(to: .init(fontSize: 31))
  }
  private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let suite = "typebar.threshold-app-settings.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(defaults)
  }

  func testExistingSourceProfileLoadsAndPersistsWithoutTouchingOldKeys() throws {
    try withDefaults { defaults in
      let legacy = try JSONEncoder().encode(AppSettingsSnapshot(fontSize: 22))
      for key in ["appSettings.v1", "appSettings.v2", "appSettings.v3"] { defaults.set(legacy, forKey: key) }
      let expected = try snapshot()
      XCTAssertTrue(ThresholdSettingsStore(defaults: defaults).save(expected))
      let settings = AppSettings(defaults: defaults)
      XCTAssertEqual(settings.snapshot, expected)
      XCTAssertEqual(settings.inputRules.thresholdSource, expected.thresholdSource)
      settings.fontSize = 34
      XCTAssertEqual(AppSettings(defaults: defaults).fontSize, 34)
      XCTAssertEqual(AppSettings(defaults: defaults).snapshot.thresholdSource, expected.thresholdSource)
      for key in ["appSettings.v1", "appSettings.v2", "appSettings.v3"] { XCTAssertEqual(defaults.data(forKey: key), legacy) }
    }
  }

  func testLegacyNumericOffWritesRetainSourceMemory() throws {
    try withDefaults { defaults in
      XCTAssertTrue(try ThresholdSettingsStore(defaults: defaults).save(snapshot()))
      let settings = AppSettings(defaults: defaults)
      settings.minimumWpm = 22.5
      settings.minimumWpm = 0
      XCTAssertEqual(settings.snapshot.thresholdSource?.configuration.minimumWpmCustomValue, 22.5)
      XCTAssertEqual(settings.snapshot.thresholdSource?.configuration.minimumWpmMode, .off)
      settings.minimumWordBurstMode = .fixed
      XCTAssertEqual(settings.snapshot.thresholdSource?.configuration.minimumWordBurstMode, .fixed)
      XCTAssertEqual(settings.minimumWordBurstWpm, 0)
    }
  }

  func testUnreadableNewProfileCannotCauseLegacyFallbackWrites() throws {
    try withDefaults { defaults in
      let legacy = try JSONEncoder().encode(AppSettingsSnapshot(fontSize: 22))
      defaults.set(legacy, forKey: "appSettings.v1")
      let future = Data("{\"version\":5}".utf8)
      defaults.set(future, forKey: "appSettings.v4")
      let settings = AppSettings(defaults: defaults)
      settings.fontSize = 34
      XCTAssertEqual(defaults.data(forKey: "appSettings.v1"), legacy)
      XCTAssertEqual(defaults.data(forKey: "appSettings.v4"), future)
    }
  }

  func testAtomicSourceAPIKeepsCustomAndFixedZeroAcrossNewReaders() throws {
    try withDefaults { defaults in
      XCTAssertTrue(try ThresholdSettingsStore(defaults: defaults).save(snapshot()))
      let settings = AppSettings(defaults: defaults)
      XCTAssertTrue(settings.updateThresholdConfiguration(.minimumWpm(mode: .custom, customValue: 0)))
      XCTAssertTrue(settings.updateThresholdConfiguration(.minimumWordBurst(mode: .fixed, customValue: 0)))
      let reopened = AppSettings(defaults: defaults)
      XCTAssertEqual(reopened.thresholdConfiguration?.minimumWpmMode, .custom)
      XCTAssertEqual(reopened.thresholdConfiguration?.minimumWpmCustomValue, 0)
      XCTAssertEqual(reopened.thresholdConfiguration?.minimumWordBurstMode, .fixed)
      XCTAssertEqual(reopened.thresholdConfiguration?.minimumWordBurstCustomValue, 0)
      XCTAssertEqual(reopened.inputRules.thresholdSource, reopened.snapshot.thresholdSource)
      XCTAssertEqual(reopened.minimumWordBurstMode, .off)
      XCTAssertEqual(reopened.minimumWordBurstWpm, 0)
    }
  }

  func testInvalidAndLockedUpdatesChangeNeitherMemoryNorStoredBytes() throws {
    try withDefaults { defaults in
      XCTAssertTrue(try ThresholdSettingsStore(defaults: defaults).save(snapshot()))
      let settings = AppSettings(defaults: defaults)
      let before = settings.snapshot
      let bytes = defaults.data(forKey: "appSettings.v4")
      XCTAssertFalse(settings.updateThresholdConfiguration(.minimumAccuracy(mode: .custom, customValue: 101)))
      XCTAssertFalse(settings.updateThresholdConfiguration(.minimumWpm(mode: .custom, customValue: .nan)))
      let owner = UUID()
      settings.setNoQuitConfigurationLock(true, for: owner)
      defer { settings.setNoQuitConfigurationLock(false, for: owner) }
      XCTAssertFalse(settings.updateThresholdConfiguration(.minimumWpm(mode: .custom, customValue: 44)))
      settings.minimumWpm = 44
      XCTAssertEqual(settings.snapshot, before)
      XCTAssertEqual(defaults.data(forKey: "appSettings.v4"), bytes)
    }
  }

  func testLiveFutureProfilePreventsCanonicalAndLegacyAdapterWrites() throws {
    try withDefaults { defaults in
      let legacy = try JSONEncoder().encode(AppSettingsSnapshot(fontSize: 22))
      defaults.set(legacy, forKey: "appSettings.v1")
      XCTAssertTrue(try ThresholdSettingsStore(defaults: defaults).save(snapshot()))
      let settings = AppSettings(defaults: defaults)
      let before = settings.thresholdConfiguration
      let future = Data("{\"version\":5}".utf8)
      defaults.set(future, forKey: "appSettings.v4")
      XCTAssertEqual(settings.thresholdProfileRead, .unavailable)
      XCTAssertFalse(settings.updateThresholdConfiguration(.minimumWpm(mode: .custom, customValue: 44)))
      settings.minimumWpm = 44
      settings.fontSize = 34
      XCTAssertEqual(settings.thresholdConfiguration, before)
      XCTAssertEqual(settings.minimumWpm, 0)
      XCTAssertEqual(defaults.data(forKey: "appSettings.v4"), future)
      XCTAssertEqual(defaults.data(forKey: "appSettings.v1"), legacy)
    }
  }

  func testLegacyApplyAndJSONRefuseSourceTargetsWhileShareHonorsCallbackRejection() throws {
    try withDefaults { defaults in
      let settings = AppSettings(defaults: defaults)
      XCTAssertFalse(settings.updateThresholdConfiguration(.minimumWpm(mode: .custom, customValue: 44)))
      settings.apply(try snapshot())
      XCTAssertFalse(settings.hasThresholdProfile)
      XCTAssertTrue(try ThresholdSettingsStore(defaults: defaults).save(snapshot()))
      let sourceSettings = AppSettings(defaults: defaults)
      let before = sourceSettings.snapshot
      sourceSettings.apply(AppSettingsSnapshot(fontSize: 42))
      XCTAssertEqual(sourceSettings.snapshot, before)
      let legacyJSON = try SettingsJSONCommandCodec.export(settings: .init(fontSize: 42), configuration: .words(25),
        layoutFluidLayouts: [], testParameterMemory: .defaults)
      XCTAssertThrowsError(try SettingsJSONCommandImport.apply(legacyJSON, to: sourceSettings)) {
        XCTAssertEqual($0 as? SettingsJSONCommandError, .thresholdSourceNotReady)
      }
      let current = SavedTestPreset(configuration: .words(17, rules: sourceSettings.inputRules), settingsSnapshot: sourceSettings.snapshot)
      let center = LocalNoticeCenter(); defer { center.clearAll() }
      var calls = 0
      let outcome = TestConfigurationShareActions.apply(try TestConfigurationShare.link(for: .init(configuration: .words(25))),
        current: current, challenges: [], notices: center, applyPreset: { _ in calls += 1; return nil },
        loadChallenge: { _ in .applied })
      XCTAssertEqual(outcome.outcome, .rejected)
      XCTAssertEqual(calls, 1)
      XCTAssertEqual(sourceSettings.snapshot, before)
    }
  }
}
