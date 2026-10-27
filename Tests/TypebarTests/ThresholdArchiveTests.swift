import XCTest
import SwiftData
@testable import Typebar

final class ThresholdArchiveTests: XCTestCase {
  private let date = Date(timeIntervalSince1970: 1000)
  private func source() throws -> PracticeThresholdSource {
    var raw = PracticeThresholdConfiguration()
    try raw.apply(.minimumWpm(mode: .off, customValue: 37))
    try raw.apply(.minimumWordBurst(mode: .flex, customValue: 0))
    return .init(configuration: raw)
  }
  private func preset() throws -> SavedTestPreset {
    let source = try source()
    var configuration = TestConfiguration.words(17)
    configuration.rules = source.applying(to: configuration.rules)
    return .init(configuration: configuration,
      settingsSnapshot: source.applying(to: .init(fontSize: 31)), settingGroups: [.behavior])
  }
  private func object(_ data: Data) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }
  private func archiveData() throws -> Data {
    try TypebarDataTransfer.exportArchive(settings: source().applying(to: AppSettingsSnapshot()),
      results: [], presets: [.init(id: UUID(), name: "owned", definition: preset())], at: date)
  }

  func testNewArchiveRetainsSourceAndHasNoLossyLegacyPayloadAlongsideIt() throws {
    let data = try archiveData()
    let root = try object(data)
    XCTAssertEqual(root["version"] as? Int, TypebarArchive.currentVersion)
    XCTAssertNil(root["settings"])
    XCTAssertNil(root["results"])
    XCTAssertNil(root["presets"])
    for key in ["thresholdSettingsData", "thresholdResultsData", "thresholdPresetsData"] {
      XCTAssertNotNil(root[key] as? String)
    }
    let decoded = try TypebarDataTransfer.importArchive(from: data)
    XCTAssertEqual(decoded.settings, try source().applying(to: AppSettingsSnapshot()))
    XCTAssertEqual(decoded.presets.first?.definition, try preset())
  }

  func testExplicitLegacyArchiveStillRejectsSourceEvenWithInnerCapability() throws {
    let archive = TypebarArchive(version: 33, exportedAt: date,
      settings: try source().applying(to: AppSettingsSnapshot()), results: [], presets: [])
    let encoder = JSONEncoder()
    encoder.userInfo[PracticeThresholdSource.codingCapability] = true
    XCTAssertThrowsError(try encoder.encode(archive))
  }

  func testDowngradedFutureMixedMissingAndDamagedSourcePayloadsAreRejected() throws {
    let root = try object(archiveData())
    for version in [33, TypebarArchive.currentVersion + 1] {
      var invalid = root
      invalid["version"] = version
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: invalid)))
    }
    for key in ["thresholdSettingsData", "thresholdResultsData", "thresholdPresetsData"] {
      var invalid = root
      invalid.removeValue(forKey: key)
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: invalid)))
      invalid = root
      invalid[key] = Data("{".utf8).base64EncodedString()
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: invalid)))
    }
    var mixed = root
    mixed["settings"] = [:]
    XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: mixed)))
  }

  @MainActor
  func testSourceResultsRoundTripWithoutChangingLegacyScores() throws {
    var session = TypingSession(configuration: .words(1), prompt: "owned")
    session.insertBatch("ow", at: date)
    session.insertBatch("ned", at: date.addingTimeInterval(1))
    let legacy = try XCTUnwrap(session.result())
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    encoder.userInfo[PracticeThresholdSource.codingCapability] = true
    decoder.userInfo[PracticeThresholdSource.codingCapability] = true
    var raw = try object(encoder.encode(legacy))
    var configuration = try XCTUnwrap(raw["configuration"] as? [String: Any])
    configuration["rules"] = try object(encoder.encode(source().applying(to: legacy.configuration.rules)))
    raw["configuration"] = configuration
    raw["id"] = UUID().uuidString
    let withSource = try decoder.decode(CompletedTestResult.self, from: JSONSerialization.data(withJSONObject: raw))
    let data = try TypebarDataTransfer.exportArchive(settings: .init(), results: [legacy, withSource], presets: [], at: date)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from: data).results, [legacy, withSource])
    let suite = "typebar.threshold-archive-results.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    let before = settings.snapshot
    let container = try ModelContainer(for: TestPresetRecord.self, TestResultRecord.self,
      LocalPersonalBestLedgerRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let archive = try TypebarDataTransfer.importArchive(from: data)
    let summary = try LocalArchiveImport.apply(archive, settings: settings, results: [], presets: [], savedTexts: [],
      modelContext: container.mainContext)
    XCTAssertEqual(summary.insertedResults, 2)
    XCTAssertEqual(settings.snapshot, before)
    let saved = try container.mainContext.fetch(FetchDescriptor<TestResultRecord>())
    XCTAssertEqual(saved.first { $0.id == legacy.id }?.portableResult, legacy)
    XCTAssertEqual(saved.first { $0.id == withSource.id }?.portableResult, withSource)
  }

  @MainActor
  func testLegacyGlobalTargetCanExplicitlyRestoreFiniteSourceArchive() throws {
    let suite = "typebar.threshold-archive.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    let archive = TypebarArchive(version: 34, exportedAt: date,
      settings: try source().applying(to: .init(fontSize: 42)), results: [], presets: [])
    let container = try ModelContainer(for: TestPresetRecord.self, TestResultRecord.self,
      LocalPersonalBestLedgerRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    _ = try LocalArchiveImport.apply(archive, settings: settings, results: [], presets: [], savedTexts: [],
      resultTombstoneStore: .init(defaults: defaults), presetTombstoneStore: .init(defaults: defaults),
      savedTextTombstoneStore: .init(defaults: defaults), customizationTombstoneStore: .init(defaults: defaults),
      tombstoneStore: .init(defaults: defaults), modelContext: container.mainContext)
    XCTAssertEqual(settings.snapshot, archive.settings)
    XCTAssertEqual(AppSettings(defaults: defaults).snapshot, archive.settings)
    XCTAssertTrue(settings.hasThresholdProfile)
    XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<TestPresetRecord>()).isEmpty)
  }

  func testConflictingSourceIsRejectedBeforeTombstonesAndPlainFieldsCannotOptIn() throws {
    var root = try object(archiveData())
    let blob = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(root["thresholdPresetsData"] as? String)))
    var presets = try XCTUnwrap(JSONSerialization.jsonObject(with: blob) as? [[String: Any]])
    let id = try XCTUnwrap(presets[0]["id"] as? String)
    var definition = try XCTUnwrap(presets[0]["definition"] as? [String: Any])
    var snapshot = try XCTUnwrap(definition["settingsSnapshot"] as? [String: Any])
    var source = try XCTUnwrap(snapshot["thresholdSource"] as? [String: Any])
    var raw = try XCTUnwrap(source["configuration"] as? [String: Any])
    raw["minimumWpmCustomValue"] = 75
    source["configuration"] = raw
    snapshot["thresholdSource"] = source
    definition["settingsSnapshot"] = snapshot
    presets[0]["definition"] = definition
    root["thresholdPresetsData"] = try JSONSerialization.data(withJSONObject: presets).base64EncodedString()
    root["deletedPresetIDs"] = [id]
    XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: root)))

    let encoder = JSONEncoder()
    encoder.userInfo[PracticeThresholdSource.codingCapability] = true
    let decoder = JSONDecoder()
    decoder.userInfo[PracticeThresholdSource.codingCapability] = true
    let plain = TypebarArchive(version: 34, exportedAt: date, settings: .init(), results: [], presets: [])
    root = try object(encoder.encode(plain))
    root["settings"] = try object(encoder.encode(self.source().applying(to: AppSettingsSnapshot())))
    XCTAssertThrowsError(try decoder.decode(TypebarArchive.self, from: JSONSerialization.data(withJSONObject: root)))
  }

  @MainActor
  func testPresetOnlyArchiveRestoresWithoutImplicitlyUpgradingTheLegacyTarget() throws {
    let expected = try preset()
    let data = try TypebarDataTransfer.exportArchive(settings: .init(), results: [],
      presets: [.init(id: UUID(), name: "owned", definition: expected)], at: date)
    let archive = try TypebarDataTransfer.importArchive(from: data)
    let suite = "typebar.threshold-archive-presets.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    let container = try ModelContainer(for: TestPresetRecord.self, TestResultRecord.self,
      LocalPersonalBestLedgerRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let summary = try LocalArchiveImport.apply(archive, settings: settings, results: [], presets: [], savedTexts: [],
      presetTombstoneStore: PresetTombstoneStore(defaults: defaults), modelContext: container.mainContext)
    XCTAssertEqual(summary.insertedPresets, 1)
    let record = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TestPresetRecord>()).first)
    XCTAssertEqual(record.definition, expected)
    XCTAssertEqual(record.applicableDefinition, expected)
    let resolved = PresetApplicationPolicy.applying(
      current: .init(configuration: .words(3), settingsSnapshot: settings.snapshot), preset: expected)
    XCTAssertFalse(PresetSettingsApplication.commit(original: expected, resolved: resolved,
      configuration: resolved.configuration, to: settings, appliesGlobalSettings: true))
    XCTAssertNil(settings.thresholdConfiguration)
    XCTAssertThrowsError(try JSONDecoder().decode(SavedTestPreset.self, from: record.definitionData))
  }
}
