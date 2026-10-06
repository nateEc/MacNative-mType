import Foundation
import SwiftData
import XCTest
@testable import Typebar

@MainActor
final class DiskModelMigrationTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 913_000_000.875)
  private let resultID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
  private let presetID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
  private let textID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
  private let filterID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!

  func testCurrentProjectionMatchesEveryProductionStoredDescriptor() throws {
    try withDirectory { root in
      let receipt = root.appendingPathComponent("schema.json")
      try runWriter("current", ["schema", receipt.path], root: root)
      let actual = schemaDescription(Schema([TestResultRecord.self, TestPresetRecord.self,
        SavedCustomTextRecord.self, ResultFilterPresetRecord.self, LocalPersonalBestLedgerRecord.self]))
      XCTAssertEqual(try object(receipt)["schema"] as? NSDictionary, actual as NSDictionary)
      XCTAssertEqual(actual.count, 5)
    }
  }

  func testInitialDiskSchemaUpgradesWithoutRescoringOrLosingOtherEntities() throws {
    try exerciseUpgrade("initial")
  }

  func testScopedAccountFilterColdReloadPreservesLegacyFilterAndCompletionBytes() throws {
    try withDirectory { root in
      let fixture = try createLegacy("before-account-tags", root: root)
      let rows = try XCTUnwrap(fixture.receipt["rows"] as? [String: [[String: Any]]])
      let scope = ResultPublicationScope(endpoint: "https://owned.invalid", userID: UUID()), tagID = UUID()
      let preset = NamedResultFilterPreset(id: UUID(), name: "Owned account filter",
        filter: .init(accountTagFilter: .init(scope: scope, knownIDs: [tagID], selectedIDs: [tagID], includesNoTags: false)),
        createdAt: start)
      var saved: Data?
      try autoreleasepool {
        let container = try open(fixture.store)
        try assertLegacy(container.mainContext, expected: rows, version: "before-account-tags")
        let record = try XCTUnwrap(ResultFilterPresetRecord(portablePreset: preset)); saved = record.filterData
        container.mainContext.insert(record); try container.mainContext.save()
      }
      let receipt = root.appendingPathComponent("cold-account-filter.json")
      try runWriter("current", ["inspect", fixture.store.path, "-", receipt.path], root: root)
      let cold = try XCTUnwrap(try object(receipt)["rows"] as? [String: [[String: Any]]])
      let filters = try XCTUnwrap(cold["ResultFilterPresetRecord"])
      XCTAssertEqual(filters.count,2)
      XCTAssertEqual(filters.first { $0["id"] as? String == preset.id.uuidString }?["filterData"] as? String,
        try XCTUnwrap(saved).base64EncodedString())
      XCTAssertEqual(filters.first { $0["id"] as? String == filterID.uuidString }?["filterData"] as? String,
        rows["ResultFilterPresetRecord"]?.first?["filterData"] as? String)
      try autoreleasepool {
        let container = try open(fixture.store)
        let stored = try container.mainContext.fetch(FetchDescriptor<ResultFilterPresetRecord>())
        XCTAssertEqual(stored.first { $0.id == preset.id }?.portablePreset,preset)
        let result = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).first)
        try assertStored(result, expected: XCTUnwrap(rows["TestResultRecord"]?.first))
        let ledger = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<LocalPersonalBestLedgerRecord>()).first)
        XCTAssertEqual(ledger.ledgerData.base64EncodedString(), rows["LocalPersonalBestLedgerRecord"]?.first?["ledgerData"] as? String)
      }
    }
  }

  func testPreviousFourEntityStoreAddsIndependentPBAndColdReloadKeepsItAfterDeletion() throws {
    try withDirectory { root in
      let fixture = try createLegacy("before-local-pb", root: root)
      let rows = try XCTUnwrap(fixture.receipt["rows"] as? [String: [[String: Any]]])
      var snapshot: LocalPersonalBestLedger?
      try autoreleasepool {
        let store = try open(fixture.store)
        defer { withExtendedLifetime(store) {} }
        let context = store.mainContext
        try assertLegacy(context, expected: rows, version: "before-local-pb")
        try LocalPersonalBestStore.initialize(in: context)
        snapshot = try XCTUnwrap(context.fetch(FetchDescriptor<LocalPersonalBestLedgerRecord>()).first).decodedLedger()
        XCTAssertEqual(snapshot?.entries.first?.row.id, resultID)
        XCTAssertEqual(snapshot?.entries.first?.row.wpm, 17.25)
        XCTAssertEqual(snapshot?.entries.first?.row.rawWpm, 29.125)
        XCTAssertFalse(try XCTUnwrap(snapshot).historyComplete)
        XCTAssertNil(snapshot?.entries.first?.recordedAt)
        try context.delete(model: TestResultRecord.self); try context.save()
      }
      let receipt = root.appendingPathComponent("cold-pb.json")
      try runWriter("current", ["inspect", fixture.store.path, "-", receipt.path], root: root)
      let cold = try XCTUnwrap(try object(receipt)["rows"] as? [String: [[String: Any]]])
      XCTAssertEqual(cold["TestResultRecord"]?.count, 0)
      XCTAssertEqual(cold["LocalPersonalBestLedgerRecord"]?.count, 1)
      try autoreleasepool {
        let store = try open(fixture.store)
        defer { withExtendedLifetime(store) {} }
        let context = store.mainContext
        try LocalPersonalBestStore.initialize(in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LocalPersonalBestLedgerRecord>()).first?.decodedLedger(), snapshot)
        try assertOtherEntities(context, expected: rows, version: "before-local-pb")
      }
    }
  }

  func testSelectedQuoteClassificationColdReloadKeepsSnapshotAndLegacyBytes() throws {
    try withDirectory { root in
      let fixture = try createLegacy("before-account-tags", root: root)
      let rows = try XCTUnwrap(fixture.receipt["rows"] as? [String: [[String: Any]]])
      let source = try XCTUnwrap(ResultQuoteSource(kind: .community, title: "Owned quote", actualLength: .extended))
      let candidate = CompletedTestResult(id: UUID(), configuration: .init(mode: .quote, duration: nil, wordLimit: nil,
        difficulty: .normal, rules: .init()), outcome: .completed, startedAt: start,
        finishedAt: start.addingTimeInterval(15), typedCharacterCount: 75, correctCharacterCount: 75,
        errorCount: 0, wpm: 60, rawWpm: 60, accuracy: 100, quoteSource: source, prompt: "partial", replayEvents: [])
      var saved: Data?
      try autoreleasepool {
        let container = try open(fixture.store)
        try assertLegacy(container.mainContext, expected: rows, version: "before-account-tags")
        let fresh = TestResultRecord(result: candidate); saved = fresh.quoteSourceData
        container.mainContext.insert(fresh); try container.mainContext.save()
      }
      let receipt = root.appendingPathComponent("cold-quote-length.json")
      try runWriter("current", ["inspect", fixture.store.path, "-", receipt.path], root: root)
      let cold = try XCTUnwrap(try object(receipt)["rows"] as? [String: [[String: Any]]])
      XCTAssertEqual(cold["TestResultRecord"]?.first { $0["id"] as? String == candidate.id.uuidString }?["quoteSourceData"] as? String,
        try XCTUnwrap(saved).base64EncodedString())
      try autoreleasepool {
        let container = try open(fixture.store)
        let records = try container.mainContext.fetch(FetchDescriptor<TestResultRecord>())
        XCTAssertEqual(records.first { $0.id == candidate.id }?.portableResult, candidate)
        let old = try XCTUnwrap(records.first { $0.id == resultID })
        try assertStored(old, expected: XCTUnwrap(rows["TestResultRecord"]?.first))
        XCTAssertNil(old.quoteSource?.actualLength)
        try assertOtherEntities(container.mainContext, expected: rows, version: "before-account-tags")
      }
    }
  }

  func testCorruptQuoteClassificationRemainsExplicitAfterColdReadAndUnrelatedSave() throws {
    try withDirectory { root in
      let file = root.appendingPathComponent("store.sqlite")
      let bytes = Data(#"{"kind":"community","title":"Owned","actualLength":"all"}"#.utf8)
      try autoreleasepool {
        let container = try open(file), record = TestResultRecord(result: newResult())
        record.quoteSourceData = bytes
        container.mainContext.insert(record); try container.mainContext.save()
      }
      for _ in 0..<2 {
        try autoreleasepool {
          let container = try open(file)
          let row = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).first)
          XCTAssertEqual(row.quoteSourceData, bytes); XCTAssertNil(row.portableResult)
          row.addTag("owned"); try container.mainContext.save()
        }
      }
    }
  }

  func testPreElapsedDiskSchemaRetainsOldBlobsAndPersistsIndependentNewTime() throws {
    try exerciseUpgrade("before-elapsed")
  }

  func testPreviousFiveEntityStoreAddsTagSnapshotWithoutBackfillingOldResults() throws {
    try withDirectory { root in
      let fixture = try createLegacy("before-account-tags", root: root)
      let rows = try XCTUnwrap(fixture.receipt["rows"] as? [String: [[String: Any]]])
      var candidate = newResult()
      candidate.accountTagSnapshot = .init(
        scope: .init(endpoint: "https://owned.example", userID: UUID()), tagIDs: [UUID()])
      var saved: Data?
      try autoreleasepool {
        let container = try open(fixture.store); defer { withExtendedLifetime(container) {} }
        try assertLegacy(container.mainContext, expected: rows, version: "before-account-tags")
        let old = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).first)
        XCTAssertNil(old.accountTagSnapshotData)
        XCTAssertNil(old.portableResult?.accountTagSnapshot)
        let book = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<LocalPersonalBestLedgerRecord>()).first)
        XCTAssertEqual(book.ledgerData.base64EncodedString(), rows["LocalPersonalBestLedgerRecord"]?.first?["ledgerData"] as? String)
        let fresh = TestResultRecord(result: candidate); saved = fresh.accountTagSnapshotData
        container.mainContext.insert(fresh); try container.mainContext.save()
      }
      let receipt = root.appendingPathComponent("cold-tags.json")
      try runWriter("current", ["inspect", fixture.store.path, "-", receipt.path], root: root)
      let cold = try XCTUnwrap(try object(receipt)["rows"] as? [String: [[String: Any]]])
      let fresh = try XCTUnwrap(cold["TestResultRecord"]?.first { $0["id"] as? String == candidate.id.uuidString })
      XCTAssertEqual(fresh["accountTagSnapshotData"] as? String, try XCTUnwrap(saved).base64EncodedString())
      try autoreleasepool {
        let container = try open(fixture.store); defer { withExtendedLifetime(container) {} }
        let records = try container.mainContext.fetch(FetchDescriptor<TestResultRecord>())
        let old = try XCTUnwrap(records.first { $0.id == resultID })
        try assertStored(old, expected: XCTUnwrap(rows["TestResultRecord"]?.first))
        XCTAssertNil(old.accountTagSnapshotData)
        XCTAssertEqual(records.first { $0.id == candidate.id }?.portableResult, candidate)
        try assertOtherEntities(container.mainContext, expected: rows, version: "before-account-tags")
        let book = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<LocalPersonalBestLedgerRecord>()).first)
        XCTAssertEqual(book.ledgerData.base64EncodedString(), rows["LocalPersonalBestLedgerRecord"]?.first?["ledgerData"] as? String)
      }
    }
  }

  func testBrokenTagSnapshotStaysExplicitAfterColdReloadAndUnrelatedLabelSave() throws {
    try withDirectory { root in
      let url = root.appendingPathComponent("store.sqlite"), bytes = Data("{\"version\":2}".utf8)
      let candidate = newResult()
      try autoreleasepool {
        let container = try open(url); defer { withExtendedLifetime(container) {} }
        let record = TestResultRecord(result: candidate); record.accountTagSnapshotData = bytes
        container.mainContext.insert(record); try container.mainContext.save()
      }
      for _ in 0..<2 {
        try autoreleasepool {
          let container = try open(url); defer { withExtendedLifetime(container) {} }
          let record = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).first)
          XCTAssertEqual(record.accountTagSnapshotData, bytes)
          XCTAssertNil(record.accountTagSnapshot); XCTAssertNil(record.portableResult)
          XCTAssertEqual(record.wpm, candidate.wpm)
          record.addTag("owned"); try container.mainContext.save()
        }
      }
    }
  }

  func testPreviousDiskSchemaAddsIncompleteEvidenceWithoutBackfillingOldAccuracy() throws {
    try withDirectory { root in
      let timing = ResultElapsedTime(seconds: 16.125)
      let fixture = try createLegacy("before-incomplete", root: root,
        overrides: ["elapsedTimeData": try blob(timing)])
      let oldValues = try XCTUnwrap((fixture.receipt["rows"] as? [String: [[String: Any]]])?["TestResultRecord"]?.first)
      let candidate = newResult()
      var saved: Data?
      try autoreleasepool {
        let container = try open(fixture.store)
        let old = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).first)
        try assertStored(old, expected: oldValues)
        XCTAssertNil(old.incompletePracticeData)
        let value = try XCTUnwrap(old.portableResult)
        XCTAssertNil(value.incompletePractice)
        XCTAssertEqual(value.restartCount, 3)
        XCTAssertEqual(value.priorAttemptEngagedDuration, 5.25)
        XCTAssertEqual(value.wpm, 17); XCTAssertEqual(value.preciseAccuracy, 77.5)
        XCTAssertEqual(value.elapsedTime, timing)
        let fresh = TestResultRecord(result: candidate)
        saved = fresh.incompletePracticeData
        container.mainContext.insert(fresh)
        try container.mainContext.save()
      }
      let receipt = root.appendingPathComponent("cold-incomplete.json")
      try runWriter("current", ["inspect", fixture.store.path, "-", receipt.path], root: root)
      let rows = try XCTUnwrap(try object(receipt)["rows"] as? [String: [[String: Any]]])
      let fresh = try XCTUnwrap(rows["TestResultRecord"]?.first { $0["id"] as? String == candidate.id.uuidString })
      XCTAssertEqual(fresh["incompletePracticeData"] as? String, try XCTUnwrap(saved).base64EncodedString())
      try autoreleasepool {
        let container = try open(fixture.store)
        let records = try container.mainContext.fetch(FetchDescriptor<TestResultRecord>())
        let old = try XCTUnwrap(records.first { $0.id == resultID })
        try assertStored(old, expected: oldValues)
        XCTAssertNil(old.incompletePracticeData)
        XCTAssertEqual(records.first { $0.id == candidate.id }?.portableResult, candidate)
        try assertOtherEntities(container.mainContext, expected: try XCTUnwrap(fixture.receipt["rows"] as? [String: [[String: Any]]]),
          version: "before-incomplete")
      }
    }
  }

  func testBrokenIncompleteEvidenceRemainsExplicitAcrossDiskReloadAndTagSave() throws {
    try withDirectory { root in
      let store = root.appendingPathComponent("store.sqlite")
      let candidate = newResult(), bytes = Data("{\"version\":2,\"attempts\":[]}".utf8)
      try autoreleasepool {
        let container = try open(store), record = TestResultRecord(result: candidate)
        record.incompletePracticeData = bytes
        container.mainContext.insert(record); try container.mainContext.save()
      }
      for _ in 0..<2 {
        try autoreleasepool {
          let container = try open(store)
          let record = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).first)
          XCTAssertEqual(record.incompletePracticeData, bytes)
          XCTAssertNil(record.incompletePractice); XCTAssertNil(record.portableResult)
          XCTAssertEqual(record.wpm, candidate.wpm)
          record.addTag("owned"); try container.mainContext.save()
        }
      }
    }
  }

  func testHistoricalTerminalEvidenceAndFractionalScoresAreNotBackfilledOrRescored() throws {
    try withDirectory { root in
      let configuration = TestConfiguration(mode: .zen, duration: nil, wordLimit: nil,
        difficulty: .normal, rules: .init())
      let timing = ResultTerminalTiming(version: 1, endMilliseconds: 16_125, lastKeypressMilliseconds: 15_000)
      let fixture = try createLegacy("before-elapsed", root: root,
        overrides: ["configurationData": try blob(configuration), "terminalTimingData": try blob(timing)])
      let values = try XCTUnwrap((fixture.receipt["rows"] as? [String: [[String: Any]]])?["TestResultRecord"]?.first)
      for _ in 0..<2 {
        try autoreleasepool {
          let container = try open(fixture.store)
          let record = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).first)
          try assertStored(record, expected: values)
          let result = try XCTUnwrap(record.portableResult)
          XCTAssertEqual(result.terminalTiming, timing); XCTAssertNil(result.elapsedTime)
          XCTAssertEqual(result.capturedDuration, 16.125); XCTAssertEqual(result.elapsedDuration, 15)
          XCTAssertEqual(result.wpm, 17); XCTAssertEqual(result.preciseWpm, 17.25)
          try container.mainContext.save()
        }
      }
    }
  }

  func testOpaqueBrokenHistoricalBlobsSurviveMigrationAndAnUnrelatedTagSave() throws {
    try withDirectory { root in
      let fields = ["configurationData", "terminalTimingData", "inputMetricsData", "characterStatsData",
        "quoteSourceData", "replayEventsData", "targetWordDirectoryData", "challengePresentationData"]
      let opaque = Dictionary(uniqueKeysWithValues: fields.map {
        ($0, Data(("owned opaque " + $0).utf8).base64EncodedString() as Any)
      })
      let fixture = try createLegacy("before-elapsed", root: root, overrides: opaque)
      var expected = try XCTUnwrap((fixture.receipt["rows"] as? [String: [[String: Any]]])?["TestResultRecord"]?.first)
      try autoreleasepool {
        let container = try open(fixture.store)
        let record = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).first)
        try assertStored(record, expected: expected); XCTAssertNil(record.portableResult)
        record.addTag("迁移验证")
        expected["tagsData"] = record.tagsData.base64EncodedString()
        try container.mainContext.save()
      }
      try autoreleasepool {
        let container = try open(fixture.store)
        let record = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).first)
        try assertStored(record, expected: expected)
        XCTAssertNil(record.elapsedTimeData); XCTAssertNil(record.portableResult)
        XCTAssertTrue(record.tags.contains("迁移验证"))
      }
    }
  }

  func testClosedPreUpgradeBackupRemainsReadableByItsOwnHistoricalSchema() throws {
    try withDirectory { root in
      let fixture = try createLegacy("before-elapsed", root: root)
      let backup = root.appendingPathComponent("backup")
      // The writer process has exited. Copy the entire owned directory,
      // including SQLite sidecars, before any new schema opens the source.
      try FileManager.default.copyItem(at: fixture.directory, to: backup)
      try autoreleasepool {
        let container = try open(fixture.store)
        container.mainContext.insert(TestResultRecord(result: newResult()))
        try container.mainContext.save()
      }
      let restored = root.appendingPathComponent("restored")
      try FileManager.default.copyItem(at: backup, to: restored)
      let receipt = root.appendingPathComponent("restored.json")
      try runWriter("before-elapsed", ["inspect", restored.appendingPathComponent("store.sqlite").path,
        "-", receipt.path], root: root)
      let after = try object(receipt)
      XCTAssertEqual(after["schema"] as? NSDictionary, fixture.receipt["schema"] as? NSDictionary)
      XCTAssertEqual(after["rows"] as? NSDictionary, fixture.receipt["rows"] as? NSDictionary)
      XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("store.sqlite")),
        try Data(contentsOf: restored.appendingPathComponent("store.sqlite")),
        "Recovery reads the unchanged old snapshot, not the upgraded database")
    }
  }

  func testInvalidDiskStoreStartupReportsFailureWithoutReplacingItsBytes() throws {
    try withDirectory { root in
      let store = root.appendingPathComponent("store.sqlite")
      let bytes = Data("owned invalid database; must not be deleted or replaced".utf8)
      try bytes.write(to: store)
      let result = DataStoreStartupPolicy.attempt(storeURL: store) { try open(store) }
      switch result {
      case .success: XCTFail("An invalid store cannot become an empty successful store")
      case .failure(let failure):
        XCTAssertEqual(failure.storeURL, store)
        XCTAssertFalse(failure.technicalDetails.isEmpty)
      }
      XCTAssertEqual(try Data(contentsOf: store), bytes)
    }
  }

  private func exerciseUpgrade(_ version: String) throws {
    try withDirectory { root in
      let fixture = try createLegacy(version, root: root)
      XCTAssertEqual(try Data(contentsOf: fixture.store).prefix(16), Data("SQLite format 3\0".utf8))
      let oldRows = try XCTUnwrap(fixture.receipt["rows"] as? [String: [[String: Any]]])
      let oldValues = try XCTUnwrap(oldRows["TestResultRecord"]?.first)
      let candidate = newResult()
      var savedElapsedBytes: Data?
      weak var released: ModelContainer?
      try autoreleasepool {
        let container = try open(fixture.store); released = container
        XCTAssertNil(container.migrationPlan, "Verify the existing automatic migration path")
        XCTAssertFalse(try XCTUnwrap(container.configurations.first).isStoredInMemoryOnly)
        try assertLegacy(container.mainContext, expected: oldRows, version: version)
        let record = TestResultRecord(result: candidate)
        savedElapsedBytes = record.elapsedTimeData
        container.mainContext.insert(record)
        try container.mainContext.save()
        XCTAssertEqual(record.portableResult, candidate)
      }
      XCTAssertNil(released, "Do not retain the first container across the reopen")
      let coldReceipt = root.appendingPathComponent("cold-current.json")
      try runWriter("current", ["inspect", fixture.store.path, "-", coldReceipt.path], root: root)
      let coldRows = try XCTUnwrap(try object(coldReceipt)["rows"] as? [String: [[String: Any]]])
      let coldNew = try XCTUnwrap(coldRows["TestResultRecord"]?.first { $0["id"] as? String == candidate.id.uuidString })
      XCTAssertEqual(coldNew["elapsedTimeData"] as? String, try XCTUnwrap(savedElapsedBytes).base64EncodedString(),
        "A separate schema-checked headless process must see the saved raw time")
      XCTAssertEqual(coldNew["finishedAt"] as? Double, candidate.finishedAt.timeIntervalSinceReferenceDate)
      try autoreleasepool {
        let container = try open(fixture.store)
        let records = try container.mainContext.fetch(FetchDescriptor<TestResultRecord>())
        XCTAssertEqual(records.count, 2)
        let old = try XCTUnwrap(records.first { $0.id == resultID })
        try assertStored(old, expected: oldValues)
        XCTAssertNil(old.elapsedTimeData)
        let fresh = try XCTUnwrap(records.first { $0.id == candidate.id })
        XCTAssertEqual(fresh.portableResult, candidate)
        XCTAssertEqual(fresh.elapsedDuration, 16.13)
        XCTAssertEqual(fresh.finishedAt, start.addingTimeInterval(-3_600))
        // A damaged explicit blob must stay damaged on disk, not become a
        // legacy date-only result on the next launch.
        fresh.elapsedTimeData = Data("{}".utf8)
        try container.mainContext.save()
      }
      try autoreleasepool {
        let container = try open(fixture.store)
        let records = try container.mainContext.fetch(FetchDescriptor<TestResultRecord>())
        let damaged = try XCTUnwrap(records.first { $0.id == candidate.id })
        XCTAssertEqual(damaged.elapsedTimeData, Data("{}".utf8))
        XCTAssertNil(damaged.portableResult); XCTAssertEqual(damaged.capturedDuration, 0)
        let old = try XCTUnwrap(records.first { $0.id == resultID })
        try assertStored(old, expected: oldValues); XCTAssertNil(old.elapsedTimeData)
        try assertOtherEntities(container.mainContext, expected: oldRows, version: version)
      }
    }
  }

  private func open(_ store: URL) throws -> ModelContainer {
    let container = try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self,
      SavedCustomTextRecord.self, ResultFilterPresetRecord.self, LocalPersonalBestLedgerRecord.self,
      configurations: ModelConfiguration(url: store, cloudKitDatabase: .none))
    container.mainContext.autosaveEnabled = false
    return container
  }

  private func newResult() -> CompletedTestResult {
    // A raw storage fixture (long idle), not proof of qualification or GUI save.
    var seconds = 0.0
    var session = TypingSession(configuration: .init(mode: .quote, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init()), prompt: "ab").withElapsedClock(.init { seconds })
    session.insert("a", at: start); seconds = 16.125
    session.insert("b", at: start.addingTimeInterval(-3_600))
    return session.result(incompletePractice: .empty)!
  }

  private func createLegacy(_ version: String, root: URL, overrides: [String: Any] = [:]) throws ->
    (directory: URL, store: URL, receipt: [String: Any]) {
    let directory = root.appendingPathComponent("old")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    let payload = root.appendingPathComponent("payload.json")
    let configuration = TestConfiguration.words(25)
    var row: [String: Any] = ["id": resultID.uuidString, "configurationData": try blob(configuration),
      "outcome": "completed", "startedAt": start.timeIntervalSinceReferenceDate,
      "finishedAt": start.addingTimeInterval(16.125).timeIntervalSinceReferenceDate,
      "afkDuration": 2.0, "typedCharacterCount": 5, "correctCharacterCount": 4,
      "errorCount": 1, "wpm": 17, "rawWpm": 29, "accuracy": 77,
      "preciseWpm": 17.25, "preciseRawWpm": 29.125, "preciseAccuracy": 77.5,
      "storedRestartCount": 3, "storedPriorAttemptEngagedDuration": 5.25,
      "tagsData": try blob(["Alpha", "练习"]), "prompt": "owned ab cd 🙂",
      "keyDurationSamplesData": try blob([0.125, 0.5]), "keySpacingSamplesData": try blob([0.25]),
      "keyOverlapDuration": 0.125,
      "replayEventsData": try blob([TypingReplayEvent(offset: 0, kind: .insert, text: "a"),
        TypingReplayEvent(offset: 1.125, kind: .insert, text: "b")])]
    row.merge(overrides) { _, new in new }
    var rows: [String: [[String: Any]]] = [
      "TestResultRecord": [row],
      "TestPresetRecord": [["id": presetID.uuidString, "name": "旧预设",
        "definitionData": try blob(SavedTestPreset(configuration: configuration)),
        "createdAt": start.timeIntervalSinceReferenceDate]],
      "SavedCustomTextRecord": [["id": textID.uuidString, "title": "旧长文本", "text": "ab cd 🙂",
        "longProgress": 3, "createdAt": start.timeIntervalSinceReferenceDate]],
      "ResultFilterPresetRecord": [["id": filterID.uuidString, "name": "旧筛选",
        "filterData": try blob(ResultHistoryFilter()), "createdAt": start.timeIntervalSinceReferenceDate]]]
    if version == "before-account-tags" {
      let book = try LocalPersonalBestLedgerRecord(ledger: LocalPersonalBestLedger())
      rows["LocalPersonalBestLedgerRecord"] = [["id": book.id.uuidString,
        "ledgerData": book.ledgerData.base64EncodedString()]]
    }
    try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]).write(to: payload)
    let store = directory.appendingPathComponent("store.sqlite")
    let receipt = root.appendingPathComponent("old.json")
    try runWriter(version, ["create", store.path, payload.path, receipt.path], root: root)
    return (directory, store, try object(receipt))
  }

  private func assertLegacy(_ context: ModelContext, expected: [String: [[String: Any]]], version: String) throws {
    let record = try XCTUnwrap(context.fetch(FetchDescriptor<TestResultRecord>()).first)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<TestResultRecord>()), 1)
    try assertStored(record, expected: XCTUnwrap(expected["TestResultRecord"]?.first))
    XCTAssertNil(record.elapsedTimeData); XCTAssertNil(record.terminalTimingData)
    XCTAssertNil(record.incompletePracticeData)
    let value = try XCTUnwrap(record.portableResult)
    XCTAssertEqual(value.wpm, 17); XCTAssertEqual(value.rawWpm, 29); XCTAssertEqual(value.accuracy, 77)
    XCTAssertEqual(value.elapsedDuration, 16.125, "Legacy fractional duration must not be newly rounded")
    XCTAssertNil(value.elapsedTime)
    XCTAssertNil(value.incompletePractice)
    XCTAssertEqual(value.afkDuration, version == "initial" ? 0 : 2)
    XCTAssertEqual(value.preciseWpm, version == "initial" ? 17 : 17.25)
    try assertOtherEntities(context, expected: expected, version: version)
  }

  private func assertOtherEntities(_ context: ModelContext, expected: [String: [[String: Any]]], version: String) throws {
    let presets = try context.fetch(FetchDescriptor<TestPresetRecord>())
    let texts = try context.fetch(FetchDescriptor<SavedCustomTextRecord>())
    let filters = try context.fetch(FetchDescriptor<ResultFilterPresetRecord>())
    XCTAssertEqual(presets.count, 1); XCTAssertEqual(texts.count, 1); XCTAssertEqual(filters.count, 1)
    let preset = try XCTUnwrap(presets.first), text = try XCTUnwrap(texts.first), filter = try XCTUnwrap(filters.first)
    XCTAssertEqual(preset.id, presetID); XCTAssertEqual(preset.name, "旧预设")
    XCTAssertEqual(preset.definitionData.base64EncodedString(), expected["TestPresetRecord"]?.first?["definitionData"] as? String)
    XCTAssertEqual(preset.createdAt, start); XCTAssertNotNil(preset.definition)
    XCTAssertEqual(text.id, textID); XCTAssertEqual(text.title, "旧长文本")
    XCTAssertEqual(text.text, "ab cd 🙂"); XCTAssertEqual(text.createdAt, start)
    XCTAssertEqual(text.longProgress, version == "initial" ? nil : 3)
    XCTAssertEqual(filter.id, filterID); XCTAssertEqual(filter.name, "旧筛选")
    XCTAssertEqual(filter.filterData.base64EncodedString(), expected["ResultFilterPresetRecord"]?.first?["filterData"] as? String)
    XCTAssertEqual(filter.createdAt, start); XCTAssertNotNil(filter.portablePreset)
  }

  private func assertStored(_ row: TestResultRecord, expected: [String: Any]) throws {
    let values: [String: Any] = [
      "id": row.id.uuidString, "configurationData": row.configurationData.base64EncodedString(),
      "outcome": row.outcome, "startedAt": row.startedAt.timeIntervalSinceReferenceDate,
      "finishedAt": row.finishedAt.timeIntervalSinceReferenceDate, "afkDuration": row.afkDuration,
      "typedCharacterCount": row.typedCharacterCount, "correctCharacterCount": row.correctCharacterCount,
      "errorCount": row.errorCount, "wpm": row.wpm, "rawWpm": row.rawWpm, "accuracy": row.accuracy,
      "preciseWpm": row.preciseWpm.map { $0 as Any } ?? NSNull(),
      "preciseRawWpm": row.preciseRawWpm.map { $0 as Any } ?? NSNull(),
      "preciseAccuracy": row.preciseAccuracy.map { $0 as Any } ?? NSNull(),
      "storedRestartCount": row.storedRestartCount.map { $0 as Any } ?? NSNull(),
      "storedPriorAttemptEngagedDuration": row.storedPriorAttemptEngagedDuration.map { $0 as Any } ?? NSNull(),
      "keyOverlapDuration": row.keyOverlapDuration.map { $0 as Any } ?? NSNull(),
      "tagsData": row.tagsData.base64EncodedString(), "prompt": row.prompt,
      "terminalTimingData": encoded(row.terminalTimingData), "elapsedTimeData": encoded(row.elapsedTimeData),
      "incompletePracticeData": encoded(row.incompletePracticeData),
      "accountTagSnapshotData": encoded(row.accountTagSnapshotData),
      "inputMetricsData": encoded(row.inputMetricsData), "characterStatsData": encoded(row.characterStatsData),
      "keyDurationSamplesData": encoded(row.keyDurationSamplesData), "keySpacingSamplesData": encoded(row.keySpacingSamplesData),
      "quoteSourceData": encoded(row.quoteSourceData), "replayEventsData": encoded(row.replayEventsData),
      "targetWordDirectoryData": encoded(row.targetWordDirectoryData), "challengePresentationData": encoded(row.challengePresentationData)]
    for (key, value) in expected {
      XCTAssertEqual(NSDictionary(dictionary: ["value": try XCTUnwrap(values[key])]),
        NSDictionary(dictionary: ["value": value]), "Stored field changed: \(key)")
    }
  }

  private func encoded(_ data: Data?) -> Any { data.map { $0.base64EncodedString() as Any } ?? NSNull() }
  private func blob<T: Encodable>(_ value: T) throws -> String { try JSONEncoder().encode(value).base64EncodedString() }
  private func object(_ file: URL) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
  }

  private func withDirectory(_ action: (URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-disk-migration-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    try action(root)
  }

  private func runWriter(_ version: String, _ arguments: [String], root: URL) throws {
    guard let path = ProcessInfo.processInfo.environment["TYPEBAR_DISK_FIXTURE_ROOT"] else {
      throw XCTSkip("Prepare historical disk writers serially before testing; use native readiness gate")
    }
    let writer = URL(fileURLWithPath: path).appendingPathComponent(version + "-fixture-writer")
    XCTAssertTrue(FileManager.default.isExecutableFile(atPath: writer.path))
    let log = root.appendingPathComponent(UUID().uuidString + ".log")
    XCTAssertTrue(FileManager.default.createFile(atPath: log.path, contents: nil))
    let output = try FileHandle(forWritingTo: log); defer { try? output.close() }
    let process = Process(); process.executableURL = writer; process.arguments = arguments
    process.standardOutput = output; process.standardError = output
    try process.run(); process.waitUntilExit()
    let diagnostic = String(decoding: try Data(contentsOf: log), as: UTF8.self)
    XCTAssertEqual(process.terminationStatus, 0, diagnostic)
    XCTAssertFalse(process.isRunning)
  }

  private func schemaDescription(_ schema: Schema) -> [String: Any] {
    Dictionary(uniqueKeysWithValues: schema.entities.map { entity in
      XCTAssertTrue(entity.relationships.isEmpty)
      let fields: [[String: Any]] = entity.properties.sorted { $0.name < $1.name }.map { property in
        let attribute = property as? Schema.Attribute
        return ["name": property.name, "originalName": property.originalName,
          "type": String(reflecting: property.valueType), "optional": property.isOptional,
          "unique": property.isUnique, "transient": property.isTransient,
          "default": attribute?.defaultValue.map { String(describing: $0) } ?? "<nil>",
          "hashModifier": attribute?.hashModifier ?? "<nil>"]
      }
      return (entity.name, ["properties": fields,
        "unique": entity.uniquenessConstraints.map { $0.sorted() }.sorted { $0.joined() < $1.joined() }] as [String: Any])
    })
  }
}
