import SwiftData
import XCTest
@testable import Typebar

@MainActor final class WebsiteThresholdArchiveTests: XCTestCase {
  private let date = Date(timeIntervalSinceReferenceDate: 1234.125)

  private func completed(json: String? = nil, enriched: Bool = false) throws -> CompletedTestResult {
    var configuration = enriched
      ? TestConfiguration(mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init())
      : TestConfiguration.words(2)
    if let json {
      let draft = try WebsiteConfigNativeProfile.prepareDraft(json, pointsPerRem: 16, context: .init())
      configuration = draft.inputRules.applying(to: configuration)
    }
    var session = TypingSession(configuration: configuration, prompt: enriched ? "e\u{301}b cd" : "ab cd")
    if enriched {
      session.insertBatch("e\u{301}", at: date)
      session.recordPhysicalKeyEvent(keyCode: 0, isKeyDown: true, isRepeat: false, at: date)
      session.recordPhysicalKeyEvent(keyCode: 1, isKeyDown: true, isRepeat: false, at: date.addingTimeInterval(0.05))
      session.recordPhysicalKeyEvent(keyCode: 0, isKeyDown: false, isRepeat: false, at: date.addingTimeInterval(0.125))
      session.recordPhysicalKeyEvent(keyCode: 1, isKeyDown: false, isRepeat: false, at: date.addingTimeInterval(0.25))
      session.insertBatch("b ", at: date.addingTimeInterval(0.5))
    } else { session.insertBatch("ab ", at: date) }
    session.insertBatch("cd", at: date.addingTimeInterval(1.25))
    var result = try XCTUnwrap(session.result(at: date.addingTimeInterval(1.25),
      tags: enriched ? ["owned archive"] : [], restartCount: enriched ? 2 : 0,
      priorAttemptEngagedDuration: enriched ? 3.25 : 0,
      quoteSource: enriched ? .init(kind: .typebar, title: "Owned archive quote", quoteID: "owned-archive-quote", actualLength: .short) : nil))
    if enriched {
      result.accountTagSnapshot = .init(scope: .init(endpoint: "https://owned.invalid", userID: UUID()), tagIDs: [UUID()])
    }
    let stored = TestResultRecord(result: result)
    XCTAssertFalse(stored.configurationData.isEmpty)
    return try XCTUnwrap(stored.portableResult)
  }

  func testActualStoredWebsiteResultsExportImportAndRestoreWithoutLosingInfiniteMemories() throws {
    let legacy = try completed()
    for (speedMode, burstMode) in [("off", "off"), ("off", "fixed"), ("off", "flex"),
      ("custom", "off"), ("custom", "fixed"), ("custom", "flex")] {
      for (speed, burst) in [("1e999", "-0"), ("1.7976931348623157e308", "1e999"), ("1e999", "1e999")] {
        let website = try completed(json: "{\"minWpm\":\"\(speedMode)\",\"minWpmCustomSpeed\":\(speed),\"minBurst\":\"\(burstMode)\",\"minBurstCustomSpeed\":\(burst)}")
        let expected = [legacy, website]
        var bytes: Data?
        XCTAssertNoThrow(bytes = try TypebarDataTransfer.exportArchive(settings: .init(), results: expected,
          presets: [], at: date.addingTimeInterval(2.5)), "A valid stored result must not block the whole archive")
        guard let bytes else { continue }
        let archive = try TypebarDataTransfer.importArchive(from: bytes)
        XCTAssertEqual(archive.results, expected)
        let suite = "typebar.website-result-archive.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults), before = settings.snapshot
        let container = try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self,
          LocalPersonalBestLedgerRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let summary = try LocalArchiveImport.apply(archive, settings: settings, results: [], presets: [],
          savedTexts: [], modelContext: container.mainContext)
        XCTAssertEqual(summary.insertedResults, expected.count)
        let restored = try container.mainContext.fetch(FetchDescriptor<TestResultRecord>())
        for result in expected {
          let actual = try XCTUnwrap(restored.first { $0.id == result.id }?.portableResult)
          XCTAssertEqual(actual, result)
          XCTAssertEqual(actual.startedAt, result.startedAt)
          if let source = result.configuration.rules.thresholdSource {
            let memory = try XCTUnwrap(actual.configuration.rules.thresholdSource).configuration
            XCTAssertEqual(memory.minimumWpmCustomValue.bitPattern, source.configuration.minimumWpmCustomValue.bitPattern)
            XCTAssertEqual(memory.minimumWordBurstCustomValue.bitPattern, source.configuration.minimumWordBurstCustomValue.bitPattern)
          }
        }
        XCTAssertEqual(settings.snapshot, before)
        XCTAssertFalse(settings.hasThresholdProfile)
      }
    }
  }

  private func object(_ data: Data) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }
  private func archiveData() throws -> Data {
    try TypebarDataTransfer.exportArchive(settings: .init(),
      results: [completed(), completed(json: #"{"minWpmCustomSpeed":1e999,"minBurstCustomSpeed":1e999}"#)],
      presets: [], at: date)
  }
  private func replacingPayload(_ original: [String: Any], _ payload: [String: Any]) throws -> Data {
    var root = original
    root["websiteResultsData"] = try JSONSerialization.data(withJSONObject: payload).base64EncodedString()
    return try JSONSerialization.data(withJSONObject: root)
  }

  func testVersionBoundaryAndLegacyResultEncodingRemainStrict() throws {
    let bytes = try archiveData(), root = try object(bytes)
    XCTAssertEqual(root["version"] as? Int, TypebarArchive.currentVersion)
    XCTAssertNotNil(root["websiteResultsData"])
    XCTAssertNil(root["thresholdResultsData"])
    XCTAssertNil(root["results"])
    let result = try completed(json: #"{"minWpmCustomSpeed":1e999}"#)
    let encoder = JSONEncoder(); encoder.userInfo[PracticeThresholdSource.codingCapability] = true
    XCTAssertThrowsError(try encoder.encode(result))
    for version in [34, 35] {
      XCTAssertThrowsError(try encoder.encode(TypebarArchive(version: version, exportedAt: date,
        settings: .init(), results: [result], presets: [])))
      var downgraded = root; downgraded["version"] = version
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: downgraded)))
      let finite = try completed(json: #"{"minWpmCustomSpeed":73.5}"#)
      var old = try object(TypebarDataTransfer.exportArchive(settings: .init(), results: [finite], presets: [], at: date))
      XCTAssertNil(old["websiteResultsData"])
      old["version"] = version
      XCTAssertEqual(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: old)).results, [finite])
    }
    for (key, value): (String, Any) in [("thresholdResultsData", Data("[]".utf8).base64EncodedString()),
      ("results", []), ("websiteResultsData", NSNull()), ("version", TypebarArchive.currentVersion + 1)] {
      var invalid = root; invalid[key] = value
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: invalid)), key)
    }
    var missing = root; missing.removeValue(forKey: "websiteResultsData")
    XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: missing)))
  }

  func testCapturedQuoteTimingReplayAndAccountMetadataSurviveTheArchiveCarrier() throws {
    let result = try completed(json: #"{"minWpmCustomSpeed":1e999,"minBurstCustomSpeed":1e999}"#, enriched: true)
    XCTAssertEqual(result.quoteSource?.quoteID, "owned-archive-quote")
    XCTAssertEqual(result.quoteSource?.actualLength, .short)
    XCTAssertEqual(result.accountTagSnapshot?.tagIDs.count, 1)
    XCTAssertFalse(result.keyDurationSamples.isEmpty)
    XCTAssertFalse(result.keySpacingSamples.isEmpty)
    XCTAssertGreaterThan(result.keyOverlapDuration, 0)
    XCTAssertFalse(result.replayEvents.isEmpty)
    XCTAssertEqual(result.tags, ["owned archive"])
    XCTAssertEqual(result.restartCount, 2)
    XCTAssertEqual(result.priorAttemptEngagedDuration, 3.25)
    let bytes = try TypebarDataTransfer.exportArchive(settings: .init(), results: [result], presets: [], at: date)
    let restored = try XCTUnwrap(TypebarDataTransfer.importArchive(from: bytes).results.first)
    XCTAssertEqual(restored, result)
    XCTAssertEqual(restored.accountTagSnapshot, result.accountTagSnapshot)
    XCTAssertEqual(restored.quoteSource, result.quoteSource)
    XCTAssertEqual(restored.keyDurationSamples, result.keyDurationSamples)
    XCTAssertEqual(restored.keySpacingSamples, result.keySpacingSamples)
    XCTAssertEqual(restored.keyOverlapDuration, result.keyOverlapDuration)
    XCTAssertTrue(restored.prompt.utf8.elementsEqual(result.prompt.utf8))
    XCTAssertEqual(restored.replayEvents.map { Array($0.text.utf16) }, result.replayEvents.map { Array($0.text.utf16) })
  }

  func testNewResultArchiveDoesNotAdmitUnrelatedNonfiniteOrConflictingRules() throws {
    let result = try completed(json: #"{"minWpmCustomSpeed":1e999}"#)
    for field in ["duration", "source projection"] {
      var configuration = result.configuration
      if field == "duration" { configuration.duration = .infinity }
      else { configuration.rules.minimumWpm = 42 }
      let invalid = CompletedTestResult(id: result.id, configuration: configuration, outcome: .completed,
        startedAt: date, finishedAt: date.addingTimeInterval(1), typedCharacterCount: 5,
        correctCharacterCount: 5, errorCount: 0, wpm: 60, rawWpm: 60, accuracy: 100)
      XCTAssertThrowsError(try TypebarDataTransfer.exportArchive(settings: .init(), results: [invalid], presets: [], at: date), field)
    }
  }

  func testDiskReopenAndRepeatedRestoreKeepOriginalAndWebsiteRecords() throws {
    let expected = [try completed(), try completed(
      json: #"{"minWpmCustomSpeed":1e999,"minBurstCustomSpeed":1e999}"#, enriched: true)]
    let archiveBytes = try TypebarDataTransfer.exportArchive(settings: .init(), results: expected, presets: [], at: date)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-website-archive-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let backup = directory.appendingPathComponent("backup.json"), store = directory.appendingPathComponent("results.store")
    try archiveBytes.write(to: backup, options: .atomic)
    let suite = "typebar.website-archive-disk.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults), before = settings.snapshot
    func open() throws -> ModelContainer {
      try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self, LocalPersonalBestLedgerRecord.self,
        configurations: ModelConfiguration(url: store, cloudKitDatabase: .none))
    }
    var originalConfigurationBytes: [UUID: Data] = [:]
    try autoreleasepool {
      let container = try open()
      let archive = try TypebarDataTransfer.importArchive(from: Data(contentsOf: backup))
      let summary = try LocalArchiveImport.apply(archive, settings: settings, results: [], presets: [],
        savedTexts: [], modelContext: container.mainContext)
      XCTAssertEqual(summary.insertedResults, 2)
      let rows = try container.mainContext.fetch(FetchDescriptor<TestResultRecord>())
      originalConfigurationBytes = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.configurationData) })
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: store.path))
    try autoreleasepool {
      let container = try open()
      let rows = try container.mainContext.fetch(FetchDescriptor<TestResultRecord>())
      let results = try rows.map { try XCTUnwrap($0.portableResult) }
      XCTAssertEqual(Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) }),
        Dictionary(uniqueKeysWithValues: expected.map { ($0.id, $0) }))
      XCTAssertEqual(Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.configurationData) }), originalConfigurationBytes)
      let exportedAgain = try TypebarDataTransfer.exportArchive(settings: settings.snapshot, results: results, presets: [], at: date)
      let archive = try TypebarDataTransfer.importArchive(from: exportedAgain)
      XCTAssertEqual(archive.results, results)
      let summary = try LocalArchiveImport.apply(archive, settings: settings, results: rows, presets: [],
        savedTexts: [], modelContext: container.mainContext)
      XCTAssertEqual(summary.insertedResults, 0)
      let final = try container.mainContext.fetch(FetchDescriptor<TestResultRecord>())
      XCTAssertEqual(final.count, expected.count)
      XCTAssertEqual(Dictionary(uniqueKeysWithValues: final.map { ($0.id, $0.configurationData) }), originalConfigurationBytes)
    }
    XCTAssertEqual(settings.snapshot, before)
    XCTAssertFalse(settings.hasThresholdProfile)
  }

  func testMalformedAndConflictingConfigurationsAreRejectedBeforeTombstones() throws {
    let root = try object(archiveData())
    let payload = try object(XCTUnwrap(Data(base64Encoded: XCTUnwrap(root["websiteResultsData"] as? String))))
    let records = try XCTUnwrap(payload["records"] as? [[String: Any]])
    XCTAssertEqual(records.count, 2)
    let original = records[1]
    let config = try object(XCTUnwrap(Data(base64Encoded: XCTUnwrap(original["configurationData"] as? String))))
    var invalidPayloads: [[String: Any]] = []
    for (key, value): (String, Any) in [("kind", "foreign"), ("version", 2), ("records", [])] {
      var invalid = payload; invalid[key] = value; invalidPayloads.append(invalid)
    }
    var missing = payload; missing.removeValue(forKey: "records"); invalidPayloads.append(missing)
    func withRecord(_ value: [String: Any]) -> [String: Any] {
      var invalid = payload, changed = records; changed[1] = value; invalid["records"] = changed; return invalid
    }
    for key in ["configurationData", "finiteResult"] {
      var invalid = original; invalid.removeValue(forKey: key); invalidPayloads.append(withRecord(invalid))
      invalid = original; invalid[key] = NSNull(); invalidPayloads.append(withRecord(invalid))
    }
    var broken = original; broken["configurationData"] = Data("{".utf8).base64EncodedString()
    invalidPayloads.append(withRecord(broken))
    for (key, value): (String, Any) in [("kind", "foreign"), ("version", 1), ("version", 3),
      ("infiniteSpeedMemory", ["minimumWpm": false, "minimumWordBurst": false])] {
      var invalidConfig = config, invalid = original; invalidConfig[key] = value
      invalid["configurationData"] = try JSONSerialization.data(withJSONObject: invalidConfig).base64EncodedString()
      invalidPayloads.append(withRecord(invalid))
    }
    var mismatch = original
    var finite = try XCTUnwrap(mismatch["finiteResult"] as? [String: Any])
    var carrier = try XCTUnwrap(finite["configuration"] as? [String: Any])
    carrier["language"] = TypingLanguage.spanish.rawValue
    finite["configuration"] = carrier; mismatch["finiteResult"] = finite
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    decoder.userInfo[PracticeThresholdSource.codingCapability] = true
    XCTAssertNoThrow(try decoder.decode(CompletedTestResult.self, from: JSONSerialization.data(withJSONObject: finite)),
      "The finite result is valid on its own; its conflict with configurationData must be rejected")
    invalidPayloads.append(withRecord(mismatch))
    var allFinite = original
    let carrierConfiguration = try XCTUnwrap((original["finiteResult"] as? [String: Any])?["configuration"] as? [String: Any])
    allFinite["configurationData"] = try JSONSerialization.data(withJSONObject: [
      "kind": "typebar.result-configuration", "version": 1, "configuration": carrierConfiguration]).base64EncodedString()
    invalidPayloads.append(withRecord(allFinite))
    var tombstoned = root
    tombstoned["deletedResultIDs"] = [try XCTUnwrap(finite["id"] as? String)]
    for (index, invalid) in invalidPayloads.enumerated() {
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: replacingPayload(root, invalid)), "payload \(index)")
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: replacingPayload(tombstoned, invalid)), "tombstoned payload \(index)")
    }
  }
}
