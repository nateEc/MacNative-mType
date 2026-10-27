import SwiftData
import XCTest
@testable import Typebar

@MainActor final class WebsiteThresholdPresetTests: XCTestCase {
  private func preset(speedMode: PracticeThresholdConfiguration.Mode = .off,
    burstMode: MinimumWordBurstMode = .off, speed: Double = .infinity,
    burst: Double = .infinity, snapshot: Bool = true) throws -> SavedTestPreset {
    let raw = try PracticeThresholdConfiguration(websiteMinimumWpmMode: speedMode,
      speed: speed, accuracyMode: .off, accuracy: 90, burstMode: burstMode, burst: burst)
    let source = PracticeThresholdSource(configuration: raw)
    var configuration = TestConfiguration.words(17)
    configuration.rules = source.applying(to: configuration.rules)
    return .init(configuration: configuration, activeResultTags: ["owned"],
      settingsSnapshot: snapshot ? source.applying(to: .init(fontSize: 31)) : nil,
      settingGroups: snapshot ? [.behavior] : nil)
  }

  func testActualPresetRecordPreservesWebsiteMemoriesAndBothSourceCarriers() throws {
    for speedMode: PracticeThresholdConfiguration.Mode in [.off, .custom] {
      for burstMode: MinimumWordBurstMode in [.off, .fixed, .flex] {
        for (speed, burst) in [(Double.infinity, -0.0), (.greatestFiniteMagnitude, .infinity), (.infinity, .infinity)] {
          let expected = try preset(speedMode: speedMode, burstMode: burstMode, speed: speed, burst: burst)
          let record = try TestPresetRecord(name: "owned", definition: expected)
          let actual = try XCTUnwrap(record.applicableDefinition)
          XCTAssertEqual(actual, expected)
          let raw = try XCTUnwrap(actual.configuration.rules.thresholdSource?.configuration)
          XCTAssertEqual(raw.minimumWpmCustomValue.bitPattern, speed.bitPattern)
          XCTAssertEqual(raw.minimumWordBurstCustomValue.bitPattern, burst.bitPattern)
          let snapshot = try XCTUnwrap(actual.settingsSnapshot?.thresholdSource?.configuration)
          XCTAssertEqual(snapshot.minimumWpmCustomValue.bitPattern, speed.bitPattern)
          XCTAssertEqual(snapshot.minimumWordBurstCustomValue.bitPattern, burst.bitPattern)
          let bytes = record.definitionData
          XCTAssertTrue(record.update(name: "renamed"))
          XCTAssertEqual(record.definitionData, bytes)
          XCTAssertThrowsError(try JSONDecoder().decode(SavedTestPreset.self, from: bytes))
        }
      }
    }
  }

  func testNativeSharePreservesInfiniteMemoryAndStripsLocalScopeBeforeApplicationCallback() throws {
    let expected = try preset(speedMode: .custom, burstMode: .flex)
    let link = try TestConfigurationShare.link(for: expected)
    let actual = try TestConfigurationShare.preset(from: link)
    XCTAssertEqual(actual.configuration, expected.configuration)
    XCTAssertNil(actual.settingsSnapshot)
    XCTAssertNil(actual.settingGroups)
    XCTAssertNil(actual.activeResultTags)
    let center = LocalNoticeCenter()
    defer { center.clearAll() }
    var received: SavedTestPreset?
    let outcome = TestConfigurationShareActions.apply(link, current: try preset(speed: 31, burst: 19),
      challenges: [], notices: center, applyPreset: { received = $0; return $0 }, loadChallenge: { _ in .applied })
    XCTAssertEqual(outcome.outcome, .applied)
    XCTAssertEqual(received, actual)
  }

  func testDiskReopenAndUpdatingLegacyRecordPreserveInfiniteMemory() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar.website-preset.\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("preset.store")
    let expected = try preset()
    var bytes = Data()
    func open() throws -> ModelContainer {
      let container = try ModelContainer(for: TestPresetRecord.self,
        configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
      container.mainContext.autosaveEnabled = false
      return container
    }
    try autoreleasepool {
      let container = try open()
      let record = try TestPresetRecord(name: "old", definition: .init(configuration: .words(25)))
      container.mainContext.insert(record)
      XCTAssertTrue(record.update(name: "website", definition: expected))
      bytes = record.definitionData
      XCTAssertFalse(bytes.isEmpty)
      try container.mainContext.save()
    }
    let reopened = try open()
    let record = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<TestPresetRecord>()).first)
    XCTAssertEqual(record.definitionData, bytes)
    XCTAssertEqual(record.applicableDefinition, expected)
  }

  func testActiveSelectionUsesNestedPresetCodecWithoutGlobalSettingsOrTags() throws {
    let suite = "typebar.website-selection.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let expected = try preset(speedMode: .custom, burstMode: .flex)
    let document = ActiveTestSelectionDocument(preset: expected, quoteSource: .community,
      testParameterMemory: .defaults)
    XCTAssertTrue(ActiveTestSelectionStore(defaults: defaults).save(document))
    let loaded = try XCTUnwrap(ActiveTestSelectionStore(defaults: defaults).load())
    XCTAssertEqual(loaded.preset.configuration, expected.configuration)
    XCTAssertEqual(loaded.quoteSource, .community)
    XCTAssertNil(loaded.preset.settingsSnapshot)
    XCTAssertNil(loaded.preset.activeResultTags)
    XCTAssertNil(loaded.preset.settingGroups)
  }

  func testPresetRejectsMalformedMixedDowngradedAndConflictingCarriers() throws {
    let expected = try preset()
    let bytes = try LocalPresetCodec.encode(expected)
    let root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    XCTAssertEqual(root["version"] as? Int, 2)
    var invalids: [[String: Any]] = []
    for (key, value): (String, Any) in [("version", 1), ("version", 3), ("kind", "foreign"),
      ("configurationData", NSNull()), ("configurationData", Data("{}".utf8).base64EncodedString()),
      ("definition", NSNull())] {
      var invalid = root; invalid[key] = value; invalids.append(invalid)
    }
    var missing = root; missing.removeValue(forKey: "configurationData"); invalids.append(missing)
    var finite = root
    finite["configurationData"] = try LocalResultConfigurationCodec.encode(
      preset(speed: 100, burst: 100).configuration).base64EncodedString()
    invalids.append(finite)
    var conflict = root
    var definition = try XCTUnwrap(root["definition"] as? [String: Any])
    var configuration = try XCTUnwrap(definition["configuration"] as? [String: Any])
    configuration["language"] = "spanish"
    definition["configuration"] = configuration; conflict["definition"] = definition
    invalids.append(conflict)
    for invalid in invalids {
      XCTAssertThrowsError(try LocalPresetCodec.decode(JSONSerialization.data(withJSONObject: invalid)))
    }
    // A snapshot-only source must never manufacture a missing configuration owner.
    var bad = expected; bad.configuration.rules.thresholdSource = nil
    XCTAssertThrowsError(try LocalPresetCodec.encode(bad))
    bad = expected; bad.configuration.rules.minimumWpm = 99
    XCTAssertThrowsError(try LocalPresetCodec.encode(bad))
    bad = expected; bad.settingsSnapshot?.soundVolume = .infinity
    XCTAssertThrowsError(try LocalPresetCodec.encode(bad))
    bad = expected; bad.configuration.duration = .infinity
    XCTAssertThrowsError(try LocalPresetCodec.encode(bad))
  }

  func testExistingFiniteSettingsApplicationStillRejectsWithoutPublishingSuccessOrMutation() throws {
    let suite = "typebar.website-preset-admission.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let notices = LocalNoticeCenter()
    defer { defaults.removePersistentDomain(forName: suite); notices.clearAll() }
    let baseline = try XCTUnwrap(preset(speed: 31, burst: 19).settingsSnapshot)
    XCTAssertTrue(ThresholdSettingsStore(defaults: defaults).save(baseline))
    let settings = AppSettings(defaults: defaults,
      feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
    let before = settings.snapshot
    let stored = defaults.data(forKey: ThresholdSettingsStore.storageKey)
    let link = try TestConfigurationShare.link(for: preset(speedMode: .custom, burstMode: .flex))
    let result = TestConfigurationShareActions.apply(link, current: .init(configuration: .words(25, rules: settings.inputRules)),
      challenges: [], notices: notices, applyPreset: { value in
        guard PresetSettingsApplication.commit(original: value, resolved: value,
          configuration: value.configuration, to: settings, appliesGlobalSettings: true) else { return nil }
        return value
      }, loadChallenge: { _ in .rejected })
    XCTAssertEqual(result.outcome, .rejected)
    XCTAssertFalse(result.shouldDismiss)
    XCTAssertEqual(settings.snapshot, before)
    XCTAssertEqual(defaults.data(forKey: ThresholdSettingsStore.storageKey), stored)
    XCTAssertFalse(notices.history.contains { $0.level == .success })
  }

  private func link(_ object: [String: Any]) throws -> String {
    let token = try JSONSerialization.data(withJSONObject: object).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    return "typebar://test?preset=" + token
  }

  func testShareV4CannotBeDisguisedAsOlderVersionOrIncludePrivateMetadata() throws {
    let expected = try preset()
    var portable = expected
    portable.settingsSnapshot = nil; portable.settingGroups = nil; portable.activeResultTags = nil
    let bytes = try LocalPresetCodec.encode(portable)
    let root: [String: Any] = ["version": 4, "selectionData": bytes.base64EncodedString()]
    XCTAssertEqual(try TestConfigurationShare.preset(from: link(root)), portable)
    for version in [1, 2, 3, 5] {
      var invalid = root; invalid["version"] = version
      XCTAssertThrowsError(try TestConfigurationShare.preset(from: link(invalid)))
    }
    for selection in [expected, try preset(speed: 100, burst: 100, snapshot: false),
      SavedTestPreset(configuration: .words(25))] {
      var invalid = root
      invalid["selectionData"] = try LocalPresetCodec.encode(selection).base64EncodedString()
      XCTAssertThrowsError(try TestConfigurationShare.preset(from: link(invalid)))
    }
    var invalid = root; invalid["preset"] = NSNull()
    XCTAssertThrowsError(try TestConfigurationShare.preset(from: link(invalid)))
  }
}
