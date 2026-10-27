import XCTest
@testable import Typebar

@MainActor final class InfiniteThresholdSettingsApplicationTests: XCTestCase {
  private func infinite(_ mode: PracticeThresholdConfiguration.Mode = .off,
    _ burstMode: MinimumWordBurstMode = .off) throws -> PracticeThresholdSource {
    .init(configuration: try .init(websiteMinimumWpmMode: mode, speed: .infinity,
      accuracyMode: .off, accuracy: 90, burstMode: burstMode, burst: .infinity))
  }

  func testStoreRoundTripsInfiniteMemoriesWithoutBroadeningOrdinaryJSON() throws {
    let suite = "typebar.infinite-settings.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let expected = try infinite().applying(to: AppSettingsSnapshot(fontSize: 31))
    let store = ThresholdSettingsStore(defaults: defaults)
    XCTAssertTrue(store.save(expected))
    XCTAssertEqual(store.read(), .available(expected))
    let bytes = try XCTUnwrap(defaults.data(forKey: ThresholdSettingsStore.storageKey))
    let root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    XCTAssertEqual(root["version"] as? Int, 5)
    XCTAssertThrowsError(try JSONEncoder().encode(expected))
  }

  func testActualPresetApplicationAndColdReloadKeepActiveAndOffInfiniteMemories() throws {
    for mode: PracticeThresholdConfiguration.Mode in [.off, .custom] {
      for burstMode: MinimumWordBurstMode in [.off, .fixed, .flex] {
        let suite = "typebar.infinite-settings-apply.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let baseline = PracticeThresholdSource(configuration: .init()).applying(to: AppSettingsSnapshot(fontSize: 31))
        XCTAssertTrue(ThresholdSettingsStore(defaults: defaults).save(baseline))
        let settings = AppSettings(defaults: defaults,
          feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
        let source = try infinite(mode, burstMode)
        var config = TestConfiguration.words(17); config.rules = source.applying(to: config.rules)
        let expected = source.applying(to: settings.snapshot)
        let preset = SavedTestPreset(configuration: config, settingsSnapshot: expected)
        XCTAssertTrue(settings.canApplySourceSnapshot(expected), "staging")
        XCTAssertTrue(PresetSettingsApplication.agreesWithSnapshot(preset), "agreement")
        XCTAssertNoThrow(try LocalPresetCodec.encode(preset))
        let prepared = try XCTUnwrap(PresetSourcePreparation.preparing(preset, to: settings,
          appliesGlobalSettings: true))
        XCTAssertTrue(PresetSettingsApplication.commit(original: preset, resolved: prepared.preset,
          configuration: prepared.preset.configuration, to: settings, appliesGlobalSettings: true,
          expectedSourceState: prepared.baseline))
        XCTAssertEqual(settings.snapshot, expected)
        let reopened = AppSettings(defaults: defaults,
          feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
        XCTAssertEqual(reopened.snapshot, expected)
        XCTAssertEqual(reopened.inputRules.thresholdSource, source)
        XCTAssertTrue(reopened.updateThresholdConfiguration(.minimumWpm(mode: .off, customValue: nil)))
        XCTAssertEqual(reopened.thresholdConfiguration?.minimumWpmCustomValue, .infinity)
        XCTAssertTrue(reopened.updateThresholdConfiguration(.minimumWpm(mode: nil, customValue: 31)))
        XCTAssertEqual(reopened.thresholdConfiguration?.minimumWordBurstCustomValue, .infinity)
        XCTAssertTrue(reopened.updateThresholdConfiguration(.minimumWordBurst(mode: nil, customValue: 19)))
        let bytes = try XCTUnwrap(defaults.data(forKey: ThresholdSettingsStore.storageKey))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(root["version"] as? Int, 4, "Fully finite preferences remain readable by v4")
      }
    }
  }

  func testAllSpeedModesAndMixedMemoriesRoundTripWithoutLosingFiniteBits() throws {
    let suite = "typebar.infinite-settings-modes.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = ThresholdSettingsStore(defaults: defaults)
    for mode: PracticeThresholdConfiguration.Mode in [.off, .custom] {
      for burstMode: MinimumWordBurstMode in [.off, .fixed, .flex] {
        for (speed, burst) in [(Double.infinity, -0.0), (.greatestFiniteMagnitude, .infinity), (.infinity, .infinity)] {
          let raw = try PracticeThresholdConfiguration(websiteMinimumWpmMode: mode, speed: speed,
            accuracyMode: .custom, accuracy: 0, burstMode: burstMode, burst: burst)
          let expected = PracticeThresholdSource(configuration: raw).applying(to: AppSettingsSnapshot(fontSize: 31))
          XCTAssertTrue(store.save(expected))
          guard case .available(let actual) = store.read() else { return XCTFail("Unavailable") }
          XCTAssertEqual(actual, expected)
          let restored = try XCTUnwrap(actual.thresholdSource?.configuration)
          XCTAssertEqual(restored.minimumWpmCustomValue.bitPattern, speed.bitPattern)
          XCTAssertEqual(restored.minimumWordBurstCustomValue.bitPattern, burst.bitPattern)
        }
      }
    }
  }

  func testMalformedTaggedDocumentsArePreservedAndCannotBeOverwritten() throws {
    let suite = "typebar.infinite-settings-invalid.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = ThresholdSettingsStore(defaults: defaults)
    let expected = try infinite(.custom, .flex).applying(to: AppSettingsSnapshot(fontSize: 31))
    XCTAssertTrue(store.save(expected))
    let bytes = try XCTUnwrap(defaults.data(forKey: ThresholdSettingsStore.storageKey))
    let root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    var invalids: [[String: Any]] = []
    for version in [4, 6] { var bad = root; bad["version"] = version; invalids.append(bad) }
    for tags: Any in [NSNull(), ["minimumWpm": false, "minimumWordBurst": false], ["minimumWpm": true]] {
      var bad = root; bad["infiniteSpeedMemory"] = tags; invalids.append(bad)
    }
    var missing = root; missing.removeValue(forKey: "infiniteSpeedMemory"); invalids.append(missing)
    let settings = try XCTUnwrap(root["settings"] as? [String: Any])
    var conflict = settings; conflict["minimumWpm"] = 99
    var bad = root; bad["settings"] = conflict; invalids.append(bad)
    var noSource = settings; noSource.removeValue(forKey: "thresholdSource")
    bad = root; bad["settings"] = noSource; invalids.append(bad)
    let finite = PracticeThresholdSource(configuration: .init()).applying(to: AppSettingsSnapshot(fontSize: 31))
    for invalid in invalids {
      let data = try JSONSerialization.data(withJSONObject: invalid)
      defaults.set(data, forKey: ThresholdSettingsStore.storageKey)
      XCTAssertEqual(store.read(), .unavailable)
      XCTAssertFalse(store.save(expected))
      XCTAssertFalse(store.save(finite))
      XCTAssertEqual(defaults.data(forKey: ThresholdSettingsStore.storageKey), data)
    }
    defaults.set(bytes, forKey: ThresholdSettingsStore.storageKey)
    for value in [Double.infinity, -.infinity, .nan] {
      var invalid = expected; invalid.soundVolume = value
      XCTAssertFalse(store.save(invalid))
      XCTAssertEqual(defaults.data(forKey: ThresholdSettingsStore.storageKey), bytes)
    }
  }

  func testLegacyPresetKeepsOffInfiniteMemoriesInExistingProfile() throws {
    let suite = "typebar.infinite-settings-legacy.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let baseline = try infinite().applying(to: AppSettingsSnapshot(fontSize: 31))
    XCTAssertTrue(ThresholdSettingsStore(defaults: defaults).save(baseline))
    let settings = AppSettings(defaults: defaults,
      feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
    let legacy = SavedTestPreset(configuration: .words(25))
    let prepared = try XCTUnwrap(PresetSourcePreparation.preparing(legacy, to: settings, appliesGlobalSettings: true))
    XCTAssertTrue(PresetSettingsApplication.commit(original: prepared.preset, resolved: prepared.preset,
      configuration: prepared.preset.configuration, to: settings, appliesGlobalSettings: true,
      expectedSourceState: prepared.baseline))
    XCTAssertEqual(settings.snapshot, baseline)
    XCTAssertNil(legacy.configuration.rules.thresholdSource)
    let reopened = AppSettings(defaults: defaults,
      feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
    XCTAssertEqual(reopened.snapshot, baseline)
  }
}
