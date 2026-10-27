import SwiftData
import XCTest
@testable import Typebar

@MainActor final class WebsiteSettingsPresetArchiveTests: XCTestCase {
  private let date = Date(timeIntervalSinceReferenceDate: 1234.125)

  private func source(_ mode: PracticeThresholdConfiguration.Mode = .off,
    _ burstMode: MinimumWordBurstMode = .off, speed: Double = .infinity,
    burst: Double = .infinity) throws -> PracticeThresholdSource {
    .init(configuration: try .init(websiteMinimumWpmMode: mode, speed: speed,
      accuracyMode: .custom, accuracy: 0, burstMode: burstMode, burst: burst))
  }

  private func named(_ source: PracticeThresholdSource) -> NamedPreset {
    var config = TestConfiguration.words(17)
    config.rules = source.applying(to: config.rules)
    return .init(id: UUID(), name: "owned e\u{301}", definition: .init(configuration: config,
      activeResultTags: ["owned"], settingsSnapshot: source.applying(to: .init(fontSize: 31)),
      settingGroups: [.behavior, .appearance]))
  }

  func testSettingsAndPresetMemoriesSurviveEveryModeAndFiniteCompanion() throws {
    let ordinary = NamedPreset(id: UUID(), name: "ordinary", definition: .init(configuration: .words(25)))
    for mode: PracticeThresholdConfiguration.Mode in [.off, .custom] {
      for burstMode: MinimumWordBurstMode in [.off, .fixed, .flex] {
        for (speed, burst) in [(Double.infinity, -0.0), (.greatestFiniteMagnitude, .infinity), (.infinity, .infinity)] {
          let owner = try source(mode, burstMode, speed: speed, burst: burst)
          let snapshot = owner.applying(to: AppSettingsSnapshot(fontSize: 31))
          let presets = [ordinary, named(owner)]
          var bytes: Data?
          XCTAssertNoThrow(bytes = try TypebarDataTransfer.exportArchive(settings: snapshot,
            results: [], presets: presets, at: date))
          guard let bytes else { continue }
          let archive = try TypebarDataTransfer.importArchive(from: bytes)
          XCTAssertEqual(archive.settings, snapshot)
          XCTAssertEqual(archive.presets, presets)
          XCTAssertEqual(archive.exportedAt, date)
          let restored = try XCTUnwrap(archive.settings.thresholdSource?.configuration)
          XCTAssertEqual(restored.minimumWpmCustomValue.bitPattern, speed.bitPattern)
          XCTAssertEqual(restored.minimumWordBurstCustomValue.bitPattern, burst.bitPattern)
          let preset = try XCTUnwrap(archive.presets.last?.definition.configuration.rules.thresholdSource?.configuration)
          XCTAssertEqual(preset.minimumWpmCustomValue.bitPattern, speed.bitPattern)
          XCTAssertEqual(preset.minimumWordBurstCustomValue.bitPattern, burst.bitPattern)
        }
      }
    }
  }

  func testSettingsOnlyAndPresetOnlyArchivesDoNotRequireTheOtherInfiniteCarrier() throws {
    let owner = try source(.custom, .flex)
    let snapshot = owner.applying(to: AppSettingsSnapshot(fontSize: 31))
    for (settings, presets): (AppSettingsSnapshot, [NamedPreset]) in [(snapshot, []), (.init(), [named(owner)])] {
      var bytes: Data?
      XCTAssertNoThrow(bytes = try TypebarDataTransfer.exportArchive(settings: settings,
        results: [], presets: presets, at: date))
      guard let bytes else { continue }
      let archive = try TypebarDataTransfer.importArchive(from: bytes)
      XCTAssertEqual(archive.settings, settings)
      XCTAssertEqual(archive.presets, presets)
    }
  }

  private func object(_ data: Data) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  func testOldVersionsRemainFiniteAndRejectNewFieldsEvenWhenDowngraded() throws {
    let owner = try source(), snapshot = owner.applying(to: AppSettingsSnapshot(fontSize: 31))
    let presets = [named(owner)]
    let root = try object(TypebarDataTransfer.exportArchive(settings: snapshot, results: [], presets: presets, at: date))
    XCTAssertEqual(root["version"] as? Int, 37)
    XCTAssertNil(root["thresholdSettingsData"])
    XCTAssertNil(root["thresholdPresetsData"])
    let encoder = JSONEncoder(); encoder.userInfo[PracticeThresholdSource.codingCapability] = true
    XCTAssertThrowsError(try encoder.encode(snapshot))
    XCTAssertThrowsError(try encoder.encode(presets))
    let finite = try source(speed: 31, burst: 19)
    for version in [34, 35, 36] {
      XCTAssertThrowsError(try encoder.encode(TypebarArchive(version: version, exportedAt: date,
        settings: snapshot, results: [], presets: [])))
      XCTAssertThrowsError(try encoder.encode(TypebarArchive(version: version, exportedAt: date,
        settings: .init(), results: [], presets: presets)))
      var downgraded = root; downgraded["version"] = version
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: downgraded)))
      let old = TypebarArchive(version: version, exportedAt: date,
        settings: finite.applying(to: .init(fontSize: 31)), results: [], presets: [named(finite)])
      let data = try encoder.encode(old)
      XCTAssertEqual(try JSONDecoder().decode(TypebarArchive.self, from: data), old)
      let oldRoot = try object(data)
      XCTAssertNil(oldRoot["websiteSettingsData"])
      XCTAssertNil(oldRoot["websitePresetsData"])
    }
  }

  func testMalformedMixedFiniteAndTombstonedPayloadsCannotHideInvalidData() throws {
    let owner = try source(.custom, .flex)
    let expected = named(owner)
    let snapshot = owner.applying(to: AppSettingsSnapshot(fontSize: 31))
    let root = try object(TypebarDataTransfer.exportArchive(settings: snapshot, results: [], presets: [expected], at: date))
    var invalids: [[String: Any]] = []
    for key in ["settings", "presets", "results", "thresholdSettingsData", "thresholdPresetsData"] {
      var bad = root; bad[key] = NSNull(); invalids.append(bad)
    }
    for key in ["websiteSettingsData", "websitePresetsData"] {
      var bad = root; bad.removeValue(forKey: key); invalids.append(bad)
      for value: Any in [NSNull(), Data("{".utf8).base64EncodedString()] {
        bad = root; bad[key] = value; invalids.append(bad)
      }
    }
    let finite = try source(speed: 31, burst: 19)
    var bad = root
    bad["websiteSettingsData"] = try XCTUnwrap(ThresholdSettingsStore.encodeDocument(finite.applying(to: .init(fontSize: 31)))).base64EncodedString()
    invalids.append(bad)
    let payload = try object(XCTUnwrap(Data(base64Encoded: XCTUnwrap(root["websitePresetsData"] as? String))))
    for (key, value): (String, Any) in [("version", 2), ("kind", "foreign"), ("records", [])] {
      var changed = payload; changed[key] = value
      bad = root; bad["websitePresetsData"] = try JSONSerialization.data(withJSONObject: changed).base64EncodedString()
      invalids.append(bad)
    }
    let record = try XCTUnwrap((payload["records"] as? [[String: Any]])?.first)
    for bytes in [Data("{}".utf8), try LocalPresetCodec.encode(named(finite).definition)] {
      var changedRecord = record; changedRecord["definitionData"] = bytes.base64EncodedString()
      var changed = payload; changed["records"] = [changedRecord]
      bad = root; bad["websitePresetsData"] = try JSONSerialization.data(withJSONObject: changed).base64EncodedString()
      invalids.append(bad)
    }
    for invalid in invalids {
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: invalid)))
      var deleted = invalid; deleted["deletedPresetIDs"] = [try XCTUnwrap(expected.id).uuidString]
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: deleted)))
    }
    for value in [Double.infinity, -.infinity, .nan] {
      var invalid = snapshot; invalid.soundVolume = value
      XCTAssertThrowsError(try TypebarDataTransfer.exportArchive(settings: invalid, results: [], presets: [expected]))
      var definition = expected.definition
      var settings = try XCTUnwrap(definition.settingsSnapshot); settings.soundVolume = value
      definition.settingsSnapshot = settings
      XCTAssertThrowsError(try TypebarDataTransfer.exportArchive(settings: snapshot, results: [],
        presets: [.init(name: "invalid", definition: definition)]))
    }
  }

  func testFileRestoreColdSettingsSQLiteReopenAndRepeatedImportKeepAllCarriers() throws {
    let owner = try source(), snapshot = owner.applying(to: AppSettingsSnapshot(fontSize: 42))
    let expectedPreset = named(owner)
    var configuration = TestConfiguration.words(2); configuration.rules = owner.applying(to: configuration.rules)
    var session = TypingSession(configuration: configuration, prompt: "ab cd")
    session.insertBatch("ab ", at: date)
    session.insertBatch("cd", at: date.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result(at: date.addingTimeInterval(1)))
    let selection = ActiveTestSelectionDocument(preset: .init(configuration: expectedPreset.definition.configuration),
      testParameterMemory: .init(duration: 30, wordLimit: 17, customTextDuration: 30, customTextWordLimit: 25, customTextSectionLimit: 1))
    let bytes = try TypebarDataTransfer.exportArchive(settings: snapshot, results: [result], presets: [expectedPreset],
      activeTestSelection: selection, at: date)
    let root = try object(bytes)
    for key in ["websiteSettingsData", "websitePresetsData", "websiteResultsData", "activeTestSelection"] { XCTAssertNotNil(root[key]) }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-settings-preset-archive.\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("backup.json"), database = directory.appendingPathComponent("history.store")
    try bytes.write(to: file, options: .atomic)
    let suite = "typebar.settings-preset-archive.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let legacy = try JSONEncoder().encode(AppSettingsSnapshot(fontSize: 22))
    defaults.set(legacy, forKey: AppSettings.legacyStorageKey)
    func settings() -> AppSettings { .init(defaults: defaults,
      feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory()) }
    func open() throws -> ModelContainer {
      let container = try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self, SavedCustomTextRecord.self,
        ResultFilterPresetRecord.self, LocalPersonalBestLedgerRecord.self,
        configurations: ModelConfiguration(url: database, cloudKitDatabase: .none))
      container.mainContext.autosaveEnabled = false
      return container
    }
    func apply(_ archive: TypebarArchive, _ target: AppSettings, _ container: ModelContainer) throws -> ArchiveImportSummary {
      try LocalArchiveImport.apply(archive, settings: target,
        results: container.mainContext.fetch(FetchDescriptor<TestResultRecord>()),
        presets: container.mainContext.fetch(FetchDescriptor<TestPresetRecord>()), savedTexts: [],
        resultTombstoneStore: .init(defaults: defaults), presetTombstoneStore: .init(defaults: defaults),
        savedTextTombstoneStore: .init(defaults: defaults), customizationTombstoneStore: .init(defaults: defaults),
        tombstoneStore: .init(defaults: defaults), modelContext: container.mainContext)
    }
    var presetBytes = Data(), resultBytes = Data()
    try autoreleasepool {
      let target = settings(), container = try open()
      XCTAssertFalse(target.hasThresholdProfile)
      let archive = try TypebarDataTransfer.importArchive(from: Data(contentsOf: file))
      let summary = try apply(archive, target, container)
      XCTAssertEqual(summary.insertedResults, 1); XCTAssertEqual(summary.insertedPresets, 1)
      XCTAssertTrue(summary.restoredActiveTestSelection)
      XCTAssertEqual(target.snapshot, snapshot)
      XCTAssertEqual(target.activeTestSelection, selection)
      presetBytes = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TestPresetRecord>()).first?.definitionData)
      resultBytes = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).first?.configurationData)
    }
    try autoreleasepool {
      let target = settings(), container = try open()
      XCTAssertEqual(target.snapshot, snapshot)
      XCTAssertEqual(target.activeTestSelection, selection)
      let preset = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TestPresetRecord>()).first)
      let storedResult = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).first)
      XCTAssertEqual(preset.applicableDefinition, expectedPreset.definition)
      XCTAssertEqual(preset.definitionData, presetBytes)
      XCTAssertEqual(storedResult.portableResult, result)
      XCTAssertEqual(storedResult.configurationData, resultBytes)
      let data = try TypebarDataTransfer.exportArchive(settings: target.snapshot, results: [try XCTUnwrap(storedResult.portableResult)],
        presets: [.init(id: preset.id, name: preset.name, definition: try XCTUnwrap(preset.applicableDefinition))],
        activeTestSelection: target.activeTestSelection, at: date)
      let archive = try TypebarDataTransfer.importArchive(from: data)
      XCTAssertEqual(archive.presets, [expectedPreset]); XCTAssertEqual(archive.results, [result])
      let generation = target.activeTestSelectionGeneration
      let summary = try apply(archive, target, container)
      XCTAssertEqual(summary.insertedResults, 0); XCTAssertEqual(summary.insertedPresets, 0)
      XCTAssertFalse(summary.restoredActiveTestSelection)
      XCTAssertEqual(target.activeTestSelectionGeneration, generation)
      XCTAssertEqual(preset.definitionData, presetBytes); XCTAssertEqual(storedResult.configurationData, resultBytes)
    }
    XCTAssertEqual(defaults.data(forKey: AppSettings.legacyStorageKey), legacy)
  }
}
