import Foundation
import SwiftData
import XCTest
@testable import Typebar

final class ResultAccountTagSnapshotTests: XCTestCase {
  private let scope = ResultPublicationScope(endpoint: "https://owned.example", userID: UUID())
  private func result() -> CompletedTestResult {
    let start = Date(timeIntervalSinceReferenceDate: 900_000_000)
    return .init(id: UUID(), configuration: .words(25), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(15), typedCharacterCount: 75,
      correctCharacterCount: 75, errorCount: 0, wpm: 60, rawWpm: 60, accuracy: 100,
      prompt: "owned private text")
  }
  private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
  }
  private func snapshot(_ ids: [UUID]) throws -> [String: Any] {
    ["version": 1, "scope": try object(scope), "tagIDs": ids.map(\.uuidString)]
  }
  private func restored(_ marker: Any) throws -> CompletedTestResult {
    var json = try object(result()); json["accountTagSnapshot"] = marker
    return try JSONDecoder().decode(CompletedTestResult.self, from: JSONSerialization.data(withJSONObject: json))
  }
  @MainActor func testCompletionIdentitySurvivesLocalRecordAndArchiveInsteadOfReadingNewSelection() throws {
    let ids = [UUID(), UUID()], frozen = try snapshot(ids)
    let captured = try restored(frozen)
    let local = try XCTUnwrap(TestResultRecord(result: captured).portableResult)
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [local], presets: [], at: captured.finishedAt))
    for copy in [captured, local, try XCTUnwrap(archive.results.first)] {
      XCTAssertEqual(try object(copy)["accountTagSnapshot"] as? NSDictionary, frozen as NSDictionary)
    }
  }
  func testKnownEmptyIsNotUnknownAndMalformedExplicitEvidenceCannotDisappear() throws {
    XCTAssertNil(try object(result())["accountTagSnapshot"])
    let empty = try restored(snapshot([]))
    XCTAssertEqual(try object(empty)["accountTagSnapshot"] as? NSDictionary, try snapshot([]) as NSDictionary)
    let id = UUID()
    for marker: Any in [NSNull(), "bad", ["version": 2, "tagIDs": []],
      ["version": 1, "tagIDs": [id.uuidString]],
      ["version": 1, "scope": try object(scope), "tagIDs": [id.uuidString, id.uuidString]]] {
      XCTAssertThrowsError(try restored(marker))
    }
  }
  func testOldArchiveCannotCarryNewIdentityUnderAnOldVersion() throws {
    let captured = result()
    let bytes = try TypebarDataTransfer.exportArchive(settings: .init(), results: [captured], presets: [], at: captured.finishedAt)
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    var results = try XCTUnwrap(json["results"] as? [[String: Any]])
    results[0]["accountTagSnapshot"] = try snapshot([UUID()])
    json["results"] = results
    json["version"] = 28
    XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: json)))
  }
  func testRetryAndColdQueueRestoreKeepCompletionIDsAfterSelectionChanges() throws {
    let suite = "TypebarTests.tag-freeze.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let selection = RemoteAccountTagSelectionStore(defaults: defaults), initial = [UUID(), UUID()]
    try selection.set(initial, for: scope)
    let frozen = ResultAccountTagSnapshotPolicy.capture(scope: scope, selectedIDs: try selection.ids(for: scope))
    try selection.set([UUID()], for: scope)
    var completed = result(); completed.accountTagSnapshot = frozen
    let pointer = PendingResultPublicationStore(defaults: defaults)
    pointer.enqueue(completed.id, for: scope)
    let reloaded = try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(completed))
    let valid = RemoteServiceCapabilities(apiVersion: "v1", service: "typebar", capabilities: ["accountTags": "available"])
    XCTAssertEqual(PendingResultPublicationStore(defaults: defaults).resultIDs(for: scope), [completed.id])
    XCTAssertEqual(try ResultAccountTagSnapshotPolicy.prepare(reloaded.accountTagSnapshot, for: scope, capabilities: valid), initial)
    try selection.set([], for: scope)
    XCTAssertEqual(try ResultAccountTagSnapshotPolicy.prepare(reloaded.accountTagSnapshot, for: scope, capabilities: valid), initial)
    XCTAssertThrowsError(try ResultAccountTagSnapshotPolicy.prepare(reloaded.accountTagSnapshot, for: scope, capabilities: nil))
  }
  func testSnapshotPromotesOldRequestedArchiveVersionBeforeTombstones() throws {
    var captured = result(); captured.accountTagSnapshot = .init(scope: scope, tagIDs: [])
    let archive = TypebarArchive(version: 1, exportedAt: captured.finishedAt, settings: .init(),
      results: [captured], deletedResultIDs: [captured.id], presets: [])
    XCTAssertEqual(archive.version, 29)
    XCTAssertTrue(archive.results.isEmpty)
    XCTAssertEqual(archive.deletedResultIDs, [captured.id])
  }
  func testUnknownSignedOutEmptyAndScopedEmptyCannotBecomeTheNewAccountsSelection() throws {
    let other = ResultPublicationScope(endpoint: "https://owned.example", userID: UUID())
    let server = ResultPublicationScope(endpoint: "https://elsewhere.example", userID: scope.userID)
    let valid = RemoteServiceCapabilities(apiVersion: "v1", service: "typebar", capabilities: ["accountTags": "available"])
    XCTAssertNil(try ResultAccountTagSnapshotPolicy.prepare(nil, for: other, capabilities: valid))
    let signedOut = ResultAccountTagSnapshotPolicy.capture(scope: nil, selectedIDs: [])
    XCTAssertEqual(try ResultAccountTagSnapshotPolicy.prepare(signedOut, for: other, capabilities: valid), [])
    XCTAssertNil(try ResultAccountTagSnapshotPolicy.prepare(signedOut, for: other, capabilities: nil))
    for snapshot in [ResultAccountTagSnapshot(scope: scope, tagIDs: []), .init(scope: scope, tagIDs: [UUID()])] {
      XCTAssertThrowsError(try ResultAccountTagSnapshotPolicy.ids(snapshot, for: other))
      XCTAssertThrowsError(try ResultAccountTagSnapshotPolicy.ids(snapshot, for: server))
    }
  }
  @MainActor func testFailedCaptureStopsPersistenceAndMalformedBlobNeverBecomesLegacy() throws {
    let container = try ModelContainer(for: TestResultRecord.self, LocalPersonalBestLedgerRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    defer { withExtendedLifetime(container) {} }
    let id = UUID()
    var value = result()
    value.accountTagSnapshot = ResultAccountTagSnapshotPolicy.capture(scope: scope, selectedIDs: [id, id])
    XCTAssertThrowsError(try LocalPersonalBestStore.save(value, in: container.mainContext))
    XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<TestResultRecord>()), 0)
    XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<LocalPersonalBestLedgerRecord>()), 0)
    XCTAssertThrowsError(try JSONEncoder().encode(value))
    let record = TestResultRecord(result: result())
    record.accountTagSnapshotData = Data("invalid".utf8)
    XCTAssertNil(record.portableResult)
    let bytes = record.accountTagSnapshotData
    record.addTag("unrelated")
    XCTAssertEqual(record.accountTagSnapshotData, bytes)
    XCTAssertNil(record.portableResult)
    let unsafe = ResultPublicationScope(endpoint: "https://user:secret@owned.example", userID: UUID())
    XCTAssertThrowsError(try JSONEncoder().encode(ResultAccountTagSnapshot(scope: unsafe, tagIDs: [])))
  }
  private func archive(_ value: CompletedTestResult) -> TypebarArchive {
    .init(exportedAt: value.finishedAt, settings: .init(), results: [value], presets: [])
  }
  @MainActor func testMergeAndRealImportPromoteOnlyMatchingUnknownIdentity() throws {
    let legacy = result(); var known = legacy
    known.accountTagSnapshot = .init(scope: scope, tagIDs: [UUID()])
    var labeled = legacy; labeled.tags = ["local label"]
    let merge = try TypebarArchiveConflictMerge.merge(local: archive(labeled), remote: archive(known))
    XCTAssertEqual(merge.results.first?.tags, labeled.tags)
    XCTAssertEqual(merge.results.first?.accountTagSnapshot, known.accountTagSnapshot)
    XCTAssertEqual(try TypebarArchiveConflictMerge.merge(local: archive(known), remote: archive(legacy)).results.first, known)
    let container = try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self,
      SavedCustomTextRecord.self, ResultFilterPresetRecord.self, LocalPersonalBestLedgerRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    context.autosaveEnabled = false
    let record = try LocalPersonalBestStore.save(labeled, in: context)
    let suite = "TypebarTests.tag-import.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    _ = try LocalArchiveImport.apply(archive(known), settings: settings,
      results: [record], presets: [], savedTexts: [], modelContext: context)
    XCTAssertEqual(record.portableResult?.accountTagSnapshot, known.accountTagSnapshot)
    XCTAssertEqual(record.tags, labeled.tags)
    var conflict = known; conflict.accountTagSnapshot = .init(scope: scope, tagIDs: [UUID()])
    XCTAssertThrowsError(try TypebarArchiveConflictMerge.merge(local: archive(known), remote: archive(conflict)))
    XCTAssertThrowsError(try LocalArchiveImport.apply(archive(conflict), settings: settings,
      results: [record], presets: [], savedTexts: [], modelContext: context))
    XCTAssertEqual(record.portableResult?.accountTagSnapshot, known.accountTagSnapshot)
  }
  @MainActor func testReadOnlyImportFailureRestoresTheExistingUnknownBlob() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-tag-readonly-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("store.sqlite"), legacy = result()
    func open(_ allowsSave: Bool) throws -> ModelContainer {
      try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self,
        SavedCustomTextRecord.self, ResultFilterPresetRecord.self, LocalPersonalBestLedgerRecord.self,
        configurations: ModelConfiguration(url: url, allowsSave: allowsSave, cloudKitDatabase: .none))
    }
    try autoreleasepool {
      let container = try open(true); defer { withExtendedLifetime(container) {} }
      _ = try LocalPersonalBestStore.save(legacy, in: container.mainContext)
    }
    var known = legacy; known.accountTagSnapshot = .init(scope: scope, tagIDs: [UUID()])
    let suite = "TypebarTests.tag-readonly.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try autoreleasepool {
      let container = try open(false); defer { withExtendedLifetime(container) {} }
      let context = container.mainContext; context.autosaveEnabled = false
      let record = try XCTUnwrap(context.fetch(FetchDescriptor<TestResultRecord>()).first)
      XCTAssertThrowsError(try LocalArchiveImport.apply(archive(known), settings: AppSettings(defaults: defaults),
        results: [record], presets: [], savedTexts: [], modelContext: context))
      XCTAssertNil(record.accountTagSnapshotData)
      XCTAssertEqual(record.portableResult, legacy)
    }
    try autoreleasepool {
      let container = try open(true); defer { withExtendedLifetime(container) {} }
      XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).first?.portableResult, legacy)
    }
  }

  @MainActor func testRepeatedUUIDCannotHideConflictingSnapshotInArchiveMergeOrImport() throws {
    var first = result(); first.accountTagSnapshot = .init(scope: scope, tagIDs: [UUID()])
    var second = first; second.accountTagSnapshot = .init(scope: scope, tagIDs: [UUID()])
    let repeated = TypebarArchive(exportedAt: first.finishedAt, settings: .init(),
      results: [first, second], presets: [])
    XCTAssertThrowsError(try JSONEncoder().encode(repeated))
    let bytes = try TypebarDataTransfer.exportArchive(settings: .init(), results: [first], presets: [])
    var wire = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    let original = try XCTUnwrap((wire["results"] as? [[String: Any]])?.first)
    var conflict = original; conflict["accountTagSnapshot"] = try object(second.accountTagSnapshot!)
    wire["results"] = [original, conflict]
    XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: wire)))
    let empty = TypebarArchive(exportedAt: first.finishedAt, settings: .init(), results: [], presets: [])
    XCTAssertThrowsError(try TypebarArchiveConflictMerge.merge(local: empty, remote: repeated))
    var unknown = first; unknown.accountTagSnapshot = nil
    let oldDuplicates = TypebarArchive(exportedAt: first.finishedAt, settings: .init(), results: [unknown, unknown], presets: [])
    XCTAssertNoThrow(try JSONEncoder().encode(oldDuplicates))
    XCTAssertThrowsError(try TypebarArchiveConflictMerge.merge(local: oldDuplicates, remote: archive(first)))
    let container = try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self,
      SavedCustomTextRecord.self, ResultFilterPresetRecord.self, LocalPersonalBestLedgerRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    defer { withExtendedLifetime(container) {} }
    container.mainContext.autosaveEnabled = false
    let suite = "TypebarTests.tag-duplicates.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    XCTAssertThrowsError(try LocalArchiveImport.apply(repeated, settings: AppSettings(defaults: defaults),
      results: [], presets: [], savedTexts: [], modelContext: container.mainContext))
    XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<TestResultRecord>()), 0)
    XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<LocalPersonalBestLedgerRecord>()), 0)
  }
}
