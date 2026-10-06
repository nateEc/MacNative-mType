import Foundation
import SwiftData
import XCTest
@testable import Typebar

@MainActor
final class PersonalBestArchiveTests: XCTestCase {
  private let key = "localPersonalBestLedgerData"
  private func result(_ speed: Double = 60.25, tags: [String] = ["focus"], id: UUID = UUID(),
    raw: Double = 70.5, accuracy: Double = 98.25) -> CompletedTestResult {
    let start = Date(timeIntervalSince1970: 100.875)
    return .init(id: id, configuration: .timed(seconds: 15), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(15.625),
      typedCharacterCount: 75, correctCharacterCount: 74, errorCount: 1,
      wpm: Int(speed.rounded()), rawWpm: 70, accuracy: 98,
      preciseWpm: speed, preciseRawWpm: raw, preciseAccuracy: accuracy,
      tags: tags, prompt: "owned private prompt")
  }
  private func book(_ candidate: CompletedTestResult) throws -> LocalPersonalBestLedger {
    var value = LocalPersonalBestLedger()
    try value.accept(candidate, at: Date(timeIntervalSince1970: 500.125))
    return value
  }
  private func payload(_ ledger: LocalPersonalBestLedger, version: Int) throws -> Data {
    let old = try TypebarDataTransfer.exportArchive(settings: .init(), results: [], presets: [])
    var root = try XCTUnwrap(JSONSerialization.jsonObject(with: old) as? [String: Any])
    root["version"] = version
    root[key] = try JSONEncoder().encode(ledger).base64EncodedString()
    return try JSONSerialization.data(withJSONObject: root)
  }
  func testOlderVersionCannotHideNewLedgerField() throws {
    for version in [1, 27] {
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: payload(book(result()), version: version)))
    }
  }
  func testLedgerOnlyArchiveRoundtripRetainsSnapshotAndMillisecondDate() throws {
    let original = try book(result())
    let archive = try TypebarDataTransfer.importArchive(from: payload(original, version: 28))
    let encoded = try JSONEncoder().encode(archive)
    let root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let bytes = try XCTUnwrap(Data(base64Encoded: XCTUnwrap(root[key] as? String)))
    XCTAssertEqual(try JSONDecoder().decode(LocalPersonalBestLedger.self, from: bytes), original)
    XCTAssertTrue(archive.results.isEmpty)
  }
  func testLedgerOnlyImportPopulatesRealStoreWithoutCreatingHistory() throws {
    let store = try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self,
      SavedCustomTextRecord.self, ResultFilterPresetRecord.self, LocalPersonalBestLedgerRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    defer { withExtendedLifetime(store) {} }
    store.mainContext.autosaveEnabled = false
    let suite = "TypebarTests.pb-archive.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let original = try book(result())
    let archive = try TypebarDataTransfer.importArchive(from: payload(original, version: 28))
    _ = try LocalArchiveImport.apply(archive, settings: AppSettings(defaults: defaults),
      results: [], presets: [], savedTexts: [], modelContext: store.mainContext)
    XCTAssertEqual(try store.mainContext.fetchCount(FetchDescriptor<TestResultRecord>()), 0)
    XCTAssertEqual(try store.mainContext.fetch(FetchDescriptor<LocalPersonalBestLedgerRecord>()).first?.decodedLedger(), original)
  }

  private func archive(_ ledger: LocalPersonalBestLedger?, results: [CompletedTestResult] = [],
    deleted: [UUID] = []) -> TypebarArchive {
    .init(exportedAt: .now, settings: .init(), results: results, deletedResultIDs: deleted,
      presets: [], localPersonalBestLedger: ledger)
  }
  private func container(_ url: URL? = nil, allowsSave: Bool = true) throws -> ModelContainer {
    let config = url.map { ModelConfiguration(url: $0, allowsSave: allowsSave, cloudKitDatabase: .none) }
      ?? ModelConfiguration(isStoredInMemoryOnly: true)
    let store = try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self,
      SavedCustomTextRecord.self, ResultFilterPresetRecord.self, LocalPersonalBestLedgerRecord.self,
      configurations: config)
    store.mainContext.autosaveEnabled = false
    return store
  }
  private func apply(_ archive: TypebarArchive, in context: ModelContext) throws {
    let suite = "TypebarTests.pb-archive-import.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    _ = try LocalArchiveImport.apply(archive, settings: AppSettings(defaults: defaults),
      results: context.fetch(FetchDescriptor<TestResultRecord>()), presets: [], savedTexts: [],
      resultTombstoneStore: ResultTombstoneStore(defaults: defaults),
      presetTombstoneStore: PresetTombstoneStore(defaults: defaults),
      savedTextTombstoneStore: SavedTextTombstoneStore(defaults: defaults),
      customizationTombstoneStore: CustomizationTombstoneStore(defaults: defaults),
      tombstoneStore: ResultFilterPresetTombstoneStore(defaults: defaults), source: .cloudSync,
      modelContext: context)
  }
  func testActualExportRetainsLedgerUnderEveryDateEncoder() throws {
    let original = try book(result())
    let data = try TypebarDataTransfer.exportArchive(settings: .init(), results: [], presets: [],
      localPersonalBestLedger: original)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from: data).localPersonalBestLedger, original)
    let document = TypebarArchiveDocument(archive: archive(original))
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from: document.archiveData()).localPersonalBestLedger, original)
    for strategy: JSONEncoder.DateEncodingStrategy in [.iso8601, .secondsSince1970, .millisecondsSince1970] {
      let encoder = JSONEncoder(); encoder.dateEncodingStrategy = strategy
      let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(archive(original))) as? [String: Any])
      let bytes = try XCTUnwrap(Data(base64Encoded: XCTUnwrap(object[key] as? String)))
      XCTAssertEqual(try JSONDecoder().decode(LocalPersonalBestLedger.self, from: bytes), original)
      XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("private prompt"))
    }
  }
  func testLedgerPromotesOldRequestedFormatWithoutDroppingTombstones() throws {
    let candidate = result(), original = try book(candidate)
    let value = TypebarArchive(version: 1, exportedAt: .now, settings: .init(),
      results: [candidate], deletedResultIDs: [candidate.id], presets: [], localPersonalBestLedger: original)
    XCTAssertEqual(value.version, 28); XCTAssertTrue(value.results.isEmpty)
    XCTAssertEqual(value.deletedResultIDs, [candidate.id]); XCTAssertEqual(value.localPersonalBestLedger, original)
  }
  func testMalformedWireAndUnsupportedLedgerAreRejected() throws {
    let original = try book(result())
    let root = try XCTUnwrap(JSONSerialization.jsonObject(with: payload(original, version: 28)) as? [String: Any])
    for invalid: Any in [NSNull(), "not-base64!", Data("{}".utf8).base64EncodedString(), 123, true] {
      var object = root; object[key] = invalid
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: object)))
    }
    var wrong = original; wrong.version = 2
    var duplicate = original; duplicate.entries += original.entries
    for invalid in [wrong, duplicate] {
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: payload(invalid, version: 28)))
      XCTAssertThrowsError(try TypebarDataTransfer.exportArchive(settings: .init(), results: [], presets: [],
        localPersonalBestLedger: invalid))
      XCTAssertThrowsError(try TypebarArchiveConflictMerge.merge(local: archive(original), remote: archive(invalid)))
    }
    var old = root; old["version"] = 27; old[key] = NSNull()
    XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: old)))
  }
  func testKnownEmptyBookDoesNotAwardImportedHistoryOrRetroactiveTags() throws {
    let store = try container(); defer { withExtendedLifetime(store) {} }
    try apply(archive(.init(), results: [result(99)]), in: store.mainContext)
    XCTAssertEqual(try store.mainContext.fetchCount(FetchDescriptor<TestResultRecord>()), 1)
    XCTAssertEqual(try LocalPersonalBestStore.exportLedger(in: store.mainContext), .init())
    let candidate = result(), original = try book(candidate)
    let edited = result(tags: ["later-tag"], id: candidate.id)
    try apply(archive(original, results: [edited]), in: store.mainContext)
    XCTAssertEqual(try LocalPersonalBestStore.exportLedger(in: store.mainContext), original)
  }
  func testMissingLegacyLedgerRecoversOnlyIncompleteUndatedHistory() throws {
    let store = try container(); defer { withExtendedLifetime(store) {} }
    let candidate = result()
    try apply(archive(nil, results: [candidate]), in: store.mainContext)
    let recovered = try LocalPersonalBestStore.exportLedger(in: store.mainContext)
    XCTAssertFalse(recovered.historyComplete)
    XCTAssertEqual(recovered.entries.first?.origin, .importedHistory)
    XCTAssertNil(recovered.entries.first?.recordedAt)
  }
  func testOfflineUnionKeepsWholeWinnerAndIndependentTagPBs() throws {
    let slower = result(60, tags: ["slow-tag"], raw: 100, accuracy: 100),
      faster = result(80, tags: ["fast-tag"], raw: 85.125, accuracy: 97.875)
    let left = try book(slower), right = try book(faster)
    let merged = try left.merged(with: right)
    XCTAssertEqual(merged.entries, right.entries)
    XCTAssertEqual(Set(merged.tagEntries.map(\.tag)), ["slow-tag", "fast-tag"])
    XCTAssertEqual(merged, try right.merged(with: left))
    XCTAssertEqual(merged, try merged.merged(with: left))
    XCTAssertEqual(merged.entries.first?.row.rawWpm, faster.preciseRawWpm)
  }
  func testOfflineTiePrefersEarlierKnownClockThenStableUUID() throws {
    let first = result(), second = result()
    let left = try book(first)
    var right = LocalPersonalBestLedger()
    try right.accept(second, at: Date(timeIntervalSince1970: 501.125))
    XCTAssertEqual(try left.merged(with: right).entries, left.entries)
    XCTAssertEqual(try right.merged(with: left).entries, left.entries)
    var unknown = LocalPersonalBestLedger()
    try unknown.accept(second, at: nil, origin: .legacyHistory)
    XCTAssertEqual(try unknown.merged(with: left).entries, left.entries)
    XCTAssertFalse(try unknown.merged(with: left).historyComplete)
    let equalClock = try book(second)
    let stable = first.id.uuidString < second.id.uuidString ? left : equalClock
    XCTAssertEqual(try left.merged(with: equalClock).entries, stable.entries)
  }
  func testMixedLegacyAndKnownEmptyArchiveDoesNotDropLegacyBaseline() throws {
    let candidate = result()
    let mixed = try TypebarArchiveConflictMerge.merge(local: archive(.init()), remote: archive(nil, results: [candidate]))
    let recovered = try XCTUnwrap(mixed.localPersonalBestLedger)
    XCTAssertEqual(recovered.entries.first?.row.id, candidate.id)
    XCTAssertFalse(recovered.historyComplete); XCTAssertNil(recovered.entries.first?.recordedAt)
    let known = try TypebarArchiveConflictMerge.merge(local: archive(.init()), remote: archive(.init(), results: [candidate]))
    XCTAssertEqual(known.localPersonalBestLedger, .init())
  }
  func testConflictingIdentityFailsBeforeHistoryOrLedgerMutation() throws {
    let candidate = result(), original = try book(candidate)
    let different = result(90, id: candidate.id)
    let conflicting = try book(different)
    XCTAssertThrowsError(try original.merged(with: conflicting))
    let store = try container(); defer { withExtendedLifetime(store) {} }
    try apply(archive(original), in: store.mainContext)
    XCTAssertThrowsError(try apply(archive(conflicting, results: [different]), in: store.mainContext))
    XCTAssertEqual(try LocalPersonalBestStore.exportLedger(in: store.mainContext), original)
    XCTAssertEqual(try store.mainContext.fetchCount(FetchDescriptor<TestResultRecord>()), 0)
  }
  func testMissingOrCorruptStoreRefusesExportInsteadOfProducingPartialBackup() throws {
    let store = try container(); defer { withExtendedLifetime(store) {} }
    XCTAssertThrowsError(try LocalPersonalBestStore.exportLedger(in: store.mainContext))
    try LocalPersonalBestStore.initialize(in: store.mainContext)
    let record = try XCTUnwrap(store.mainContext.fetch(FetchDescriptor<LocalPersonalBestLedgerRecord>()).first)
    record.ledgerData = Data("invalid".utf8)
    XCTAssertThrowsError(try LocalPersonalBestStore.exportLedger(in: store.mainContext))
  }
  func testLedgerOnlyExportImportColdReloadAndRealSaveFailure() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-pb-archive-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("store.sqlite")
    let candidate = result(), original = try book(candidate)
    let bytes = try TypebarDataTransfer.exportArchive(settings: .init(), results: [],
      deletedResultIDs: [candidate.id], presets: [], localPersonalBestLedger: original)
    try autoreleasepool {
      let store = try container(url); defer { withExtendedLifetime(store) {} }
      try apply(TypebarDataTransfer.importArchive(from: bytes), in: store.mainContext)
    }
    try autoreleasepool {
      let store = try container(url, allowsSave: false); defer { withExtendedLifetime(store) {} }
      XCTAssertThrowsError(try apply(archive(book(result(90)), results: [result(90)]), in: store.mainContext))
      XCTAssertEqual(try LocalPersonalBestStore.exportLedger(in: store.mainContext), original)
      XCTAssertEqual(try store.mainContext.fetchCount(FetchDescriptor<TestResultRecord>()), 0)
    }
    try autoreleasepool {
      let store = try container(url); defer { withExtendedLifetime(store) {} }
      XCTAssertEqual(try LocalPersonalBestStore.exportLedger(in: store.mainContext), original)
      XCTAssertEqual(try store.mainContext.fetchCount(FetchDescriptor<TestResultRecord>()), 0)
    }
  }
}
