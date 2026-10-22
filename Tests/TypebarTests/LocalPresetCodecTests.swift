import XCTest
import SwiftData
@testable import Typebar

@MainActor
final class LocalPresetCodecTests: XCTestCase {
  private func sourcePreset() throws -> SavedTestPreset {
    var raw = PracticeThresholdConfiguration()
    try raw.apply(.minimumWpm(mode: .off, customValue: 37))
    try raw.apply(.minimumWordBurst(mode: .flex, customValue: 0))
    let source = PracticeThresholdSource(configuration: raw)
    var configuration = TestConfiguration.words(17)
    configuration.rules = source.applying(to: configuration.rules)
    return .init(configuration: configuration, activeResultTags: ["owned"],
      settingsSnapshot: source.applying(to: .init(fontSize: 31)), settingGroups: [.behavior])
  }

  func testSourcePresetUsesEnvelopeAndRoundTripsWithoutLegacyAcceptance() throws {
    let expected = try sourcePreset()
    let record = try TestPresetRecord(name: "source", definition: expected)
    XCTAssertEqual(record.definition, expected)
    XCTAssertEqual(record.applicableDefinition, expected)
    XCTAssertFalse(record.definitionData.isEmpty)
    XCTAssertThrowsError(try JSONDecoder().decode(SavedTestPreset.self, from: record.definitionData))
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: record.definitionData) as? [String: Any])
    XCTAssertEqual(json["kind"] as? String, "typebar.local-preset")
    XCTAssertEqual(json["version"] as? Int, 1)
    var updated = expected
    var raw = try XCTUnwrap(expected.configuration.rules.thresholdSource?.configuration)
    try raw.apply(.minimumWpm(mode: .custom, customValue: 22.5))
    let source = PracticeThresholdSource(configuration: raw)
    updated.configuration.rules = source.applying(to: updated.configuration.rules)
    updated.settingsSnapshot = source.applying(to: try XCTUnwrap(updated.settingsSnapshot))
    XCTAssertTrue(record.update(name: "updated", definition: updated))
    XCTAssertEqual(record.definition, updated)
    XCTAssertEqual(record.name, "updated")
  }

  func testLegacyBytesSurviveReadAndRenameWithoutEnvelopeUpgrade() throws {
    let expected = SavedTestPreset(configuration: .words(25), settingsSnapshot: .init(fontSize: 29))
    let bytes = try JSONEncoder().encode(expected)
    let record = try TestPresetRecord(name: "old", definition: expected)
    record.definitionData = bytes
    XCTAssertEqual(record.definition, expected)
    XCTAssertEqual(record.applicableDefinition, expected)
    record.update(name: "renamed")
    XCTAssertEqual(record.name, "renamed")
    XCTAssertEqual(record.definitionData, bytes)
    XCTAssertEqual(try JSONDecoder().decode(SavedTestPreset.self, from: record.definitionData), expected)
  }

  func testUnreadableRecordsCannotBeRenamedOrReplaced() throws {
    let legacy = SavedTestPreset(configuration: .words(25))
    let record = try TestPresetRecord(name: "protected", definition: legacy)
    for bytes in [Data(), Data("{".utf8),
      Data("{\"kind\":\"typebar.local-preset\",\"version\":2,\"definition\":{}}".utf8)] {
      record.definitionData = bytes
      XCTAssertNil(record.definition)
      record.update(name: "replacement", definition: legacy)
      XCTAssertEqual(record.definitionData, bytes)
      XCTAssertEqual(record.name, "protected")
    }
  }

  func testInvalidReplacementDoesNotRenameOrModifyExistingDefinition() throws {
    let record = try TestPresetRecord(name: "protected", definition: .init(configuration: .words(25)))
    let before = record.definitionData
    var invalid = try sourcePreset()
    invalid.configuration.rules.minimumWpm = 99
    record.update(name: "replacement", definition: invalid)
    XCTAssertEqual(record.name, "protected")
    XCTAssertEqual(record.definitionData, before)
    XCTAssertThrowsError(try TestPresetRecord(name: "invalid", definition: invalid))
  }

  func testBothSourceCarriersMustAgreeBeforeSaving() throws {
    var invalid = try sourcePreset()
    var other = try XCTUnwrap(invalid.settingsSnapshot?.thresholdSource?.configuration)
    try other.apply(.minimumWpm(mode: .off, customValue: 75))
    invalid.settingsSnapshot = PracticeThresholdSource(configuration: other).applying(to: .init())
    XCTAssertThrowsError(try TestPresetRecord(name: "conflict", definition: invalid))
    invalid = try sourcePreset()
    invalid.configuration.rules.thresholdSource = nil
    XCTAssertThrowsError(try TestPresetRecord(name: "snapshot-only", definition: invalid))
  }

  func testEnvelopeIsRequiredAndUnknownOrConflictingPayloadsAreRejected() throws {
    let expected = try sourcePreset()
    let encoder = JSONEncoder()
    encoder.userInfo[PracticeThresholdSource.codingCapability] = true
    XCTAssertThrowsError(try LocalPresetCodec.decode(encoder.encode(expected)))
    let record = try TestPresetRecord(name: "source", definition: expected)
    let root = try XCTUnwrap(JSONSerialization.jsonObject(with: record.definitionData) as? [String: Any])
    for (key, value): (String, Any) in [("kind", "foreign"), ("version", 2), ("definition", NSNull())] {
      var invalid = root
      invalid[key] = value
      XCTAssertThrowsError(try LocalPresetCodec.decode(JSONSerialization.data(withJSONObject: invalid)))
    }
    var invalid = root
    var definition = try XCTUnwrap(root["definition"] as? [String: Any])
    var configuration = try XCTUnwrap(definition["configuration"] as? [String: Any])
    var rules = try XCTUnwrap(configuration["rules"] as? [String: Any])
    rules["minimumWpm"] = 50
    configuration["rules"] = rules
    definition["configuration"] = configuration
    invalid["definition"] = definition
    XCTAssertThrowsError(try LocalPresetCodec.decode(JSONSerialization.data(withJSONObject: invalid)))
  }

  func testDiskStoreReopenPreservesBothFormatsAndDoesNotRewriteLegacyBytes() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar.local-preset.\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("presets.store")
    let expected = try sourcePreset()
    let legacy = SavedTestPreset(configuration: .words(25))
    let legacyBytes = try JSONEncoder().encode(legacy)
    func open() throws -> ModelContainer {
      let container = try ModelContainer(for: TestPresetRecord.self,
        configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
      container.mainContext.autosaveEnabled = false
      return container
    }
    do {
      let container = try open()
      container.mainContext.insert(try TestPresetRecord(name: "source", definition: expected))
      let old = try TestPresetRecord(name: "legacy", definition: legacy)
      old.definitionData = legacyBytes
      container.mainContext.insert(old)
      try container.mainContext.save()
    }
    let reopened = try open()
    let records = try reopened.mainContext.fetch(FetchDescriptor<TestPresetRecord>())
    XCTAssertEqual(records.count, 2)
    XCTAssertEqual(records.first(where: { $0.name == "source" })?.definition, expected)
    let old = try XCTUnwrap(records.first(where: { $0.name == "legacy" }))
    XCTAssertEqual(old.definition, legacy)
    XCTAssertTrue(old.update(name: "renamed"))
    try reopened.mainContext.save()
    XCTAssertEqual(old.definitionData, legacyBytes)
  }

  func testArchiveImportCannotUpsertOverAnUnreadableLocalPresetID() throws {
    let suite = "typebar.local-preset.import.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    let container = try ModelContainer(for: TestPresetRecord.self, TestResultRecord.self,
      LocalPersonalBestLedgerRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let legacy = SavedTestPreset(configuration: .words(25))
    let protected = try TestPresetRecord(name: "future", definition: legacy)
    let bytes = Data("{\"kind\":\"typebar.local-preset\",\"version\":2}".utf8)
    protected.definitionData = bytes
    let protectedID = protected.id
    container.mainContext.insert(protected)
    try container.mainContext.save()
    let archive = TypebarArchive(exportedAt: Date(timeIntervalSince1970: 1000),
      settings: settings.snapshot, results: [],
      presets: [.init(id: protectedID, name: "imported", definition: legacy)])
    let summary = try LocalArchiveImport.apply(archive, settings: settings, results: [],
      presets: [protected], savedTexts: [], presetTombstoneStore: PresetTombstoneStore(defaults: defaults),
      source: .localFile, modelContext: container.mainContext)
    XCTAssertEqual(summary.insertedPresets, 1)
    let records = try container.mainContext.fetch(FetchDescriptor<TestPresetRecord>())
    XCTAssertEqual(records.count, 2)
    let original = try XCTUnwrap(records.first { $0.id == protectedID })
    XCTAssertEqual(original.definitionData, bytes)
    XCTAssertEqual(original.name, "future")
    XCTAssertEqual(records.first { $0.id != protectedID }?.definition, legacy)
  }
}
