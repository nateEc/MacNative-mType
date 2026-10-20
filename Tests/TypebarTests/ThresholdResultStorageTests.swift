import XCTest
import SwiftData
@testable import Typebar

@MainActor
final class ThresholdResultStorageTests: XCTestCase {
  private func result(source: Bool, conflict: Bool = false) throws -> CompletedTestResult {
    var configuration = TestConfiguration.timed(seconds: 15)
    if source {
      var raw = PracticeThresholdConfiguration()
      try raw.apply(.minimumWpm(mode: .off, customValue: 37))
      try raw.apply(.minimumWordBurst(mode: .flex, customValue: 0))
      configuration.rules = PracticeThresholdSource(configuration: raw).applying(to: configuration.rules)
    }
    if conflict { configuration.rules.minimumWpm = 99 }
    let start = Date(timeIntervalSince1970: 1000)
    return .init(id: UUID(), configuration: configuration, outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(15), typedCharacterCount: 75,
      correctCharacterCount: 75, errorCount: 0, wpm: 60, rawWpm: 60, accuracy: 100,
      prompt: "ab cd x", replayEvents: [.init(offset: 0, kind: .insert, text: "ab ", inputField: .init(index: 0, value: "ab "))])
  }

  func testRecordPreservesSourceAndLegacyScoreWithoutBareCodecAcceptance() throws {
    let expected = try result(source: true)
    let record = TestResultRecord(result: expected)
    XCTAssertEqual(record.configuration, expected.configuration)
    XCTAssertEqual(record.portableResult, expected)
    XCTAssertFalse(record.configurationData.isEmpty)
    XCTAssertThrowsError(try JSONDecoder().decode(TestConfiguration.self, from: record.configurationData))
    let legacy = try result(source: false)
    let old = TestResultRecord(result: legacy)
    let bytes = old.configurationData
    XCTAssertEqual(try JSONDecoder().decode(TestConfiguration.self, from: bytes), legacy.configuration)
    XCTAssertEqual(old.portableResult, legacy)
    XCTAssertEqual(old.configurationData, bytes)
  }

  func testWorkerInputsRetainSameChartAndConsistencyAcrossSourceEnvelope() throws {
    let expected = try result(source: true)
    let record = TestResultRecord(result: expected)
    let direct = try ResultWPMConsistencyInput(prompt: expected.prompt, events: expected.replayEvents,
      duration: expected.chartDuration, configuration: expected.configuration,
      targetWordDirectory: expected.targetWordDirectory, sourceScoringBasis: expected.characterStats.sourceUnitBasis)
    let persisted = ResultWPMConsistencyInput(prompt: expected.prompt, duration: expected.chartDuration,
      configurationData: record.configurationData, replayEventsData: record.replayEventsData,
      targetWordDirectoryData: record.targetWordDirectoryData, sourceScoringBasis: expected.characterStats.sourceUnitBasis)
    XCTAssertNotNil(direct.calculate())
    XCTAssertEqual(persisted.calculate(), direct.calculate())
    XCTAssertNotNil(try AccountResultChartInput(expected).calculate())
  }

  func testArchiveSourceResultsCanRestoreAfterLocalStorageMigration() throws {
    let expected = try result(source: true)
    let data = try TypebarDataTransfer.exportArchive(settings: .init(), results: [expected], presets: [])
    let archive = try TypebarDataTransfer.importArchive(from: data)
    let suite = "typebar.threshold-result.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    let container = try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self,
      LocalPersonalBestLedgerRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let summary = try LocalArchiveImport.apply(archive, settings: settings, results: [], presets: [], savedTexts: [],
      modelContext: container.mainContext)
    XCTAssertEqual(summary.insertedResults, 1)
    let saved = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).first)
    XCTAssertEqual(saved.portableResult, expected)
  }

  func testUnknownOrBareSourceConfigurationIsUnreadableWithoutFallback() throws {
    let expected = try result(source: true)
    let record = TestResultRecord(result: expected)
    let root = try XCTUnwrap(JSONSerialization.jsonObject(with: record.configurationData) as? [String: Any])
    var future = root
    future["version"] = 2
    var foreign = root
    foreign["kind"] = "foreign"
    let encoder = JSONEncoder()
    encoder.userInfo[PracticeThresholdSource.codingCapability] = true
    for data in [try JSONSerialization.data(withJSONObject: future),
      try JSONSerialization.data(withJSONObject: foreign), try encoder.encode(expected.configuration), Data()] {
      record.configurationData = data
      XCTAssertNil(record.configuration)
      XCTAssertNil(record.portableResult)
      let input = ResultWPMConsistencyInput(prompt: expected.prompt, duration: 15,
        configurationData: data, replayEventsData: record.replayEventsData,
        targetWordDirectoryData: nil, sourceScoringBasis: nil)
      XCTAssertNil(input.calculate())
      XCTAssertEqual(record.configurationData, data)
    }
  }

  func testOfficialSaveAndImportRejectInvalidSourceBeforeChangingModelsOrSettings() throws {
    let invalid = try result(source: true, conflict: true)
    let container = try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self,
      LocalPersonalBestLedgerRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    XCTAssertThrowsError(try LocalPersonalBestStore.save(invalid, in: container.mainContext))
    XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).isEmpty)
    XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<LocalPersonalBestLedgerRecord>()).isEmpty)
    let suite = "typebar.threshold-result.invalid.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    let before = settings.snapshot
    let archive = TypebarArchive(exportedAt: Date(timeIntervalSince1970: 1000),
      settings: .init(fontSize: 42), results: [invalid], presets: [])
    XCTAssertThrowsError(try LocalArchiveImport.apply(archive, settings: settings,
      results: [], presets: [], savedTexts: [], modelContext: container.mainContext))
    XCTAssertEqual(settings.snapshot, before)
    XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).isEmpty)
    XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<LocalPersonalBestLedgerRecord>()).isEmpty)
  }

  func testPBBaselineInspectsOriginalFieldsInsideEnvelopeWithoutFillingMissingMetadata() throws {
    let expected = try result(source: true)
    for complete in [true, false] {
      let container = try ModelContainer(for: TestResultRecord.self, LocalPersonalBestLedgerRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
      let record = TestResultRecord(result: expected)
      if !complete {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: record.configurationData) as? [String: Any])
        var configuration = try XCTUnwrap(root["configuration"] as? [String: Any])
        configuration.removeValue(forKey: "language")
        root["configuration"] = configuration
        record.configurationData = try JSONSerialization.data(withJSONObject: root)
      }
      let before = record.configurationData
      container.mainContext.insert(record)
      try container.mainContext.save()
      try LocalPersonalBestStore.initialize(in: container.mainContext)
      let ledger = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<LocalPersonalBestLedgerRecord>()).first).decodedLedger()
      if complete {
        XCTAssertEqual(ledger.entries.first?.row.id, expected.id)
        XCTAssertEqual(ledger.entries.first?.row.wpm, expected.preciseWpm)
        XCTAssertEqual(ledger.entries.first?.origin, .legacyHistory)
      } else { XCTAssertTrue(ledger.entries.isEmpty) }
      XCTAssertEqual(record.configurationData, before)
    }
  }

  func testDiskReopenRetainsBothConfigurationFormatsAndScores() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar.threshold-results.\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("results.store")
    let expected = [try result(source: false), try result(source: true)]
    var bytes: [UUID: Data] = [:]
    func open() throws -> ModelContainer {
      let container = try ModelContainer(for: TestResultRecord.self,
        configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
      container.mainContext.autosaveEnabled = false
      return container
    }
    do {
      let container = try open()
      for result in expected {
        let record = TestResultRecord(result: result)
        bytes[record.id] = record.configurationData
        container.mainContext.insert(record)
      }
      try container.mainContext.save()
    }
    let container = try open()
    let records = try container.mainContext.fetch(FetchDescriptor<TestResultRecord>())
    XCTAssertEqual(records.count, 2)
    for result in expected {
      let record = try XCTUnwrap(records.first { $0.id == result.id })
      XCTAssertEqual(record.portableResult, result)
      XCTAssertEqual(record.configurationData, bytes[result.id])
    }
  }
}
