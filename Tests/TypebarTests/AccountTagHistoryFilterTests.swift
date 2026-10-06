import Foundation
import XCTest
@testable import Typebar

final class AccountTagHistoryFilterTests: XCTestCase {
  private let a = UUID(), b = UUID(), c = UUID()
  private let scope = ResultPublicationScope(endpoint: "https://owned.invalid", userID: UUID())
  func testCurrentSettingsAccountNoneDoesNotMeanNoLocalTextLabels() {
    let id = UUID()
    let scope = ResultPublicationScope(endpoint: "https://owned.invalid", userID: UUID())
    let entry = ResultHistoryEntry(id: id, mode: .time, language: .english, tags: ["desk"],
      difficulty: .normal, includesPunctuation: false, includesNumbers: false,
      duration: 15, modifiers: [], accountTags: .init(scope: scope, tagIDs: []))
    let filter = ResultHistoryFilter.currentSettings(.timed(seconds: 15), accountTagFilter:
      .init(scope: scope, knownIDs: [], selectedIDs: [], includesNoTags: true))
    XCTAssertEqual(filter.matchingIDs(entries: [entry], personalBestIDs: []), [id],
      "An authenticated account-none filter must not inspect unrelated local text labels")
  }

  func testForeignCompletionWithCollidingUUIDCannotAdoptCurrentCanonicalTags() {
    let id = UUID(), foreign = ResultPublicationScope(endpoint: "https://other.invalid", userID: scope.userID)
    let snapshot = ResultAccountTagSnapshot(scope: foreign, tagIDs: [a])
    let canonical: [UUID: ResultHistoryAccountTagMetadata] = [id: .init(scope: scope, tagIDs: [a])]
    XCTAssertNil(AccountTagHistoryFilterPolicy.metadata(id: id, snapshot: snapshot,
      scope: scope, knownIDs: [a], canonical: canonical))
  }

  private func directory(_ ids: [UUID]) throws -> RemoteAccountTagList {
    try JSONDecoder().decode(RemoteAccountTagList.self, from: JSONSerialization.data(withJSONObject:
      ["version": 1, "tags": ids.map { ["id": $0.uuidString, "name": "desk",
        "personalBestLedgerVersion": 1, "personalBests": []] as [String: Any] }]))
  }
  private func row(_ ids: [UUID]?) throws -> RemoteAccountResult {
    var json: [String: Any] = ["id": UUID().uuidString, "mode": "time", "mode2": "15", "durationSeconds": 15,
      "language": "english", "wpm": 80, "rawWpm": 90, "accuracy": 98, "consistency": 75,
      "errorCount": 2, "eventCount": 100, "tags": ["desk"], "startedAt": 100, "finishedAt": 115,
      "personalBestConfiguration": ["version": 1, "difficulty": "normal", "punctuation": false,
        "numbers": false, "lazyMode": false]]
    if let ids { json["accountTagIDs"] = ids.map(\.uuidString) }
    return try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: json))
  }
  @MainActor func testIncompleteHistoryCannotUndoConfirmedLastResultTagEdit() throws {
    let suite = "TypebarTests.account-filter.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let account = AccountSession(defaults: defaults)
    account.currentUser = .init(id: scope.userID, email: "owned@example.invalid", displayName: "Owned", totalExperience: 0)
    try account.applyAccountTagDirectory(directory([a,b]), read: account.beginAccountTagDirectoryRead())
    let current = try row([a]), actualScope = try XCTUnwrap(account.resultPublicationScope)
    let read = try XCTUnwrap(account.beginLastAccountResultRead(id: current.id, finishedAt: current.finishedAt, scope: actualScope))
    try account.applyLastAccountResult(current, read: read)
    try account.applyAccountTagHistory([current], read: account.beginAccountTagHistoryRead())
    _ = account.beginAcceptedAccountTagHistoryInsertion(id: UUID(), scope: actualScope)
    XCTAssertFalse(account.isAccountTagHistoryReady)
    var edited = current; edited.accountTagIDs = [b]
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(edited)) as? [String: Any])
    json["tagPbs"] = []
    let response = try JSONDecoder().decode(RemoteAccountTagEditResponse.self, from: JSONSerialization.data(withJSONObject: json))
    try account.applyAccountTagEditResponse(response, requestedIDs: [b], scope: actualScope, at: 123, fromResultPage: true)
    XCTAssertEqual(account.accountTagHistoryCache?.results.first?.accountTagIDs, [a])
    XCTAssertEqual(account.historyAccountTagMetadata[current.id]?.tagIDs, [b])
    account.currentUser = nil
    XCTAssertTrue(account.historyAccountTagMetadata.isEmpty)
  }

  func testAnyStableIDMatchesWithoutConflatingNamesOrUnknownWithNone() {
    let filter = ResultHistoryAccountTagFilter(scope: scope, knownIDs: [a,b,c], selectedIDs: [a,b], includesNoTags: false)
    for ids: [UUID] in [[a],[b],[a,b],[a,c]] { XCTAssertTrue(filter.matches(.init(scope: scope, tagIDs: ids))) }
    for ids: [UUID] in [[],[c]] { XCTAssertFalse(filter.matches(.init(scope: scope, tagIDs: ids))) }
    XCTAssertFalse(filter.matches(nil)); XCTAssertFalse(filter.matches(.init(scope: scope, tagIDs: nil)))
    let none = ResultHistoryAccountTagFilter(scope: scope, knownIDs: [a,b,c], selectedIDs: [], includesNoTags: true)
    XCTAssertTrue(none.matches(.init(scope: scope, tagIDs: [])))
    XCTAssertFalse(none.matches(.init(scope: scope, tagIDs: nil)))
    XCTAssertFalse(none.matches(.init(scope: scope, tagIDs: [a,a])))
    let foreign = ResultPublicationScope(endpoint: "https://other.invalid", userID: scope.userID)
    XCTAssertFalse(filter.matches(.init(scope: foreign, tagIDs: [a])))
  }

  func testCurrentSettingsActiveIDsIgnoreLocalTextAndRetainOtherConfigurationFilters() {
    let config = TestConfiguration.timed(seconds: 15)
    let accountFilter = ResultHistoryAccountTagFilter(scope: scope, knownIDs: [a,b], selectedIDs: [b], includesNoTags: false)
    let filter = ResultHistoryFilter.currentSettings(config, accountTagFilter: accountFilter)
    let one = UUID(), two = UUID(), three = UUID()
    let entries = [
      ResultHistoryEntry(id: one, mode: .time, language: .english, tags: ["unrelated"],
        difficulty: .normal, includesPunctuation: false, includesNumbers: false, duration: 15, modifiers: [],
        accountTags: .init(scope: scope, tagIDs: [b])),
      ResultHistoryEntry(id: two, mode: .time, language: .english, tags: ["desk"],
        difficulty: .normal, includesPunctuation: false, includesNumbers: false, duration: 15, modifiers: [],
        accountTags: .init(scope: scope, tagIDs: [a])),
      ResultHistoryEntry(id: three, mode: .time, language: .english, tags: [],
        difficulty: .expert, includesPunctuation: false, includesNumbers: false, duration: 15, modifiers: [],
        accountTags: .init(scope: scope, tagIDs: [b]))]
    XCTAssertEqual(filter.matchingIDs(entries: entries, personalBestIDs: []), [one])
    XCTAssertTrue(filter.effectiveTagFilter.isUnrestricted)
    XCTAssertEqual(ResultHistoryFilterSummaryPolicy.items(for: filter).last?.category, "账户标签")
  }

  func testCanonicalUnknownAndEmptyAreAuthoritativeWithoutMutatingCapture() {
    let id = UUID(), snapshot = ResultAccountTagSnapshot(scope: scope, tagIDs: [a])
    for ids: [UUID]? in [nil,[],[b]] {
      let row = ResultHistoryAccountTagMetadata(scope: scope, tagIDs: ids)
      XCTAssertEqual(AccountTagHistoryFilterPolicy.metadata(id: id, snapshot: snapshot,
        scope: scope, knownIDs: [a,b], canonical: [id: row]), row)
      XCTAssertEqual(snapshot.tagIDs,[a])
    }
    XCTAssertNil(AccountTagHistoryFilterPolicy.metadata(id: id, snapshot: nil, scope: scope, knownIDs: [a], canonical: [:]))
    XCTAssertNil(AccountTagHistoryFilterPolicy.metadata(id: id, snapshot: .unavailable, scope: scope,
      knownIDs: [a], canonical: [id: .init(scope: scope, tagIDs: [])]))
    XCTAssertNil(AccountTagHistoryFilterPolicy.metadata(id: id, snapshot: snapshot, scope: nil, knownIDs: [a], canonical: [:]))
  }

  func testCapturedIDsArePrunedByKnownDirectoryButOlderUnknownIsNotEmpty() {
    let snapshot = ResultAccountTagSnapshot(scope: scope, tagIDs: [a,b])
    XCTAssertEqual(AccountTagHistoryFilterPolicy.metadata(id: UUID(), snapshot: snapshot,
      scope: scope, knownIDs: [b], canonical: [:])?.tagIDs, [b])
    XCTAssertEqual(AccountTagHistoryFilterPolicy.metadata(id: UUID(), snapshot: snapshot,
      scope: scope, knownIDs: [], canonical: [:])?.tagIDs, [])
    let signedOut = ResultAccountTagSnapshot(scope: nil, tagIDs: [])
    XCTAssertNil(AccountTagHistoryFilterPolicy.metadata(id: UUID(), snapshot: signedOut,
      scope: scope, knownIDs: [], canonical: [:]))
    let id = UUID(), accepted = ResultHistoryAccountTagMetadata(scope: scope, tagIDs: [])
    XCTAssertEqual(AccountTagHistoryFilterPolicy.metadata(id: id, snapshot: nil,
      scope: scope, knownIDs: [], canonical: [id: accepted]), accepted)
    XCTAssertEqual(snapshot.tagIDs,[a,b])
  }

  @MainActor func testExplicitBrokenDiskSnapshotCannotBecomeLegacyUnknownWithCanonicalMetadata() throws {
    let result = CompletedTestResult(id: UUID(), configuration: .timed(seconds: 15), outcome: .completed, startedAt: .distantPast,
      finishedAt: .distantPast.addingTimeInterval(15), typedCharacterCount: 100, correctCharacterCount: 98,
      errorCount: 2, wpm: 80, rawWpm: 90, accuracy: 98)
    let record = TestResultRecord(result: result)
    let accepted = ResultHistoryAccountTagMetadata(scope: scope, tagIDs: [a])
    record.accountTagSnapshotData = Data("broken explicit bytes".utf8)
    XCTAssertNil(record.accountTagSnapshot, "Legacy reader collapses broken bytes; the history adapter must not")
    let snapshot = AccountTagHistoryFilterPolicy.snapshot(from: record.accountTagSnapshotData)
    XCTAssertEqual(snapshot,.unavailable)
    XCTAssertNil(AccountTagHistoryFilterPolicy.metadata(id: record.id, snapshot: snapshot,
      scope: scope, knownIDs: [a], canonical: [record.id: accepted]))
    XCTAssertEqual(record.accountTagSnapshotData,Data("broken explicit bytes".utf8))
    for bytes in [Data("{}".utf8),Data("null".utf8),Data()] {
      XCTAssertEqual(AccountTagHistoryFilterPolicy.snapshot(from: bytes),.unavailable)
    }
    XCTAssertNil(AccountTagHistoryFilterPolicy.snapshot(from: nil))
    XCTAssertEqual(AccountTagHistoryFilterPolicy.metadata(id: record.id, snapshot: nil,
      scope: scope, knownIDs: [a], canonical: [record.id: accepted]),accepted)
    let valid = ResultAccountTagSnapshot(scope: scope, tagIDs: [a])
    XCTAssertEqual(AccountTagHistoryFilterPolicy.snapshot(from: try JSONEncoder().encode(valid)),valid)
  }

  func testDirectoryAdditionsDefaultOnAndRenamesCannotAlterSelection() {
    var filter = ResultHistoryAccountTagFilter(scope: scope, knownIDs: [a,b], selectedIDs: [a], includesNoTags: false)
    filter.reconcile(scope: scope, knownIDs: [a,b]); XCTAssertEqual(filter.selectedIDs,[a])
    filter.reconcile(scope: scope, knownIDs: [b,c]); XCTAssertEqual(filter.selectedIDs,[c])
    XCTAssertEqual(filter.knownIDs,[b,c]); XCTAssertFalse(filter.includesNoTags)
    let before = filter, foreign = ResultPublicationScope(endpoint: "https://other.invalid", userID: scope.userID)
    filter.reconcile(scope: foreign, knownIDs: [a]); XCTAssertEqual(filter,before)
    filter.reconcile(scope: scope, knownIDs: []); XCTAssertTrue(filter.selectedIDs.isEmpty)
    XCTAssertEqual(filter.selectionSummary,"无匹配账户标签")
  }

  func testOldTextPresetsKeepTheirOwnNamespaceAndCanBeCombinedWithAccountIDs() throws {
    let legacy = try JSONDecoder().decode(ResultHistoryFilter.self, from: Data(#"{"tag":"desk"}"#.utf8))
    XCTAssertNil(legacy.accountTagFilter)
    let id = UUID(), entry = ResultHistoryEntry(id: id, mode: .time, language: .english, tags: ["desk"],
      accountTags: .init(scope: scope, tagIDs: [b]))
    XCTAssertEqual(legacy.matchingIDs(entries: [entry], personalBestIDs: []),[id])
    var combined = legacy
    combined.accountTagFilter = .init(scope: scope, knownIDs: [a,b], selectedIDs: [a], includesNoTags: false)
    XCTAssertTrue(combined.matchingIDs(entries: [entry], personalBestIDs: []).isEmpty)
    combined.accountTagFilter?.selectedIDs = [b]
    XCTAssertEqual(combined.matchingIDs(entries: [entry], personalBestIDs: []),[id])
    XCTAssertEqual(try JSONDecoder().decode(ResultHistoryFilter.self, from: JSONEncoder().encode(combined)),combined)
  }

  func testAccountPresetRoundTripAndMalformedIdentitiesFailClosed() throws {
    let filter = ResultHistoryAccountTagFilter(scope: scope, knownIDs: [a,b], selectedIDs: [b], includesNoTags: true)
    let bytes = try JSONEncoder().encode(filter)
    XCTAssertEqual(try JSONDecoder().decode(ResultHistoryAccountTagFilter.self, from: bytes),filter)
    let original = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    for (key,value): (String,Any) in [("version",2),("knownIDs",[a.uuidString,a.uuidString]),
      ("selectedIDs",[c.uuidString]),("selectedIDs",[b.uuidString,b.uuidString]),("scope",NSNull()),
      ("includesNoTags",NSNull()),("knownIDs",(0..<16).map { _ in UUID().uuidString })] {
      var malformed = original; malformed[key] = value
      XCTAssertThrowsError(try JSONDecoder().decode(ResultHistoryAccountTagFilter.self,
        from: JSONSerialization.data(withJSONObject: malformed)), key)
    }
    var bad = filter; bad.selectedIDs = [c]
    XCTAssertThrowsError(try JSONEncoder().encode(bad))
  }

  private func preset() -> NamedResultFilterPreset {
    .init(id: UUID(), name: "Owned filter", filter: .init(accountTagFilter:
      .init(scope: scope, knownIDs: [a,b], selectedIDs: [b], includesNoTags: false)), createdAt: Date(timeIntervalSince1970: 1_800_000_000))
  }
  func testArchivePromotesStableIDPresetsAndRejectsOldVersionBeforeTombstones() throws {
    let preset = preset()
    let archive = TypebarArchive(version: 4, exportedAt: .now, settings: .init(), results: [], presets: [], resultFilterPresets: [preset])
    XCTAssertEqual(archive.version,31); XCTAssertEqual(archive.resultFilterPresets,[preset])
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    let bytes = try encoder.encode(archive)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from: bytes).resultFilterPresets,[preset])
    var root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    root["version"] = 30; root["deletedResultFilterPresetIDs"] = [preset.id.uuidString]
    XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: root)))
    let deleted = TypebarArchive(version: 1, exportedAt: .now, settings: .init(), results: [], presets: [],
      resultFilterPresets: [preset], deletedResultFilterPresetIDs: [preset.id])
    XCTAssertEqual(deleted.version,31); XCTAssertTrue(deleted.resultFilterPresets.isEmpty)
    XCTAssertEqual(deleted.deletedResultFilterPresetIDs,[preset.id])
  }
  @MainActor func testPersistedFilterPayloadAndArchiveMergeRetainScopeAndStableIDs() throws {
    let preset = preset(), record = try XCTUnwrap(ResultFilterPresetRecord(portablePreset: preset))
    XCTAssertEqual(record.filter,preset.filter); XCTAssertEqual(record.portablePreset,preset)
    let local = TypebarArchive(version: 4, exportedAt: .now, settings: .init(), results: [], presets: [])
    let remote = TypebarArchive(version: 4, exportedAt: .now, settings: .init(), results: [], presets: [], resultFilterPresets: [preset])
    let merged = try TypebarArchiveConflictMerge.merge(local: local, remote: remote)
    XCTAssertEqual(merged.version,31); XCTAssertEqual(merged.resultFilterPresets,[preset])
    let plain = TypebarArchive(version: 4, exportedAt: .now, settings: .init(), results: [], presets: [],
      resultFilterPresets: [.init(id: UUID(), name: "Legacy", filter: .init(tag: "desk"), createdAt: .now)])
    XCTAssertEqual(plain.version,4)
  }

  @MainActor func testReadyHistoryOverridesOlderLastProjectionAndDirectoryRenamesKeepIDs() throws {
    let suite = "TypebarTests.account-filter-ready.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let account = AccountSession(defaults: defaults)
    account.currentUser = .init(id: scope.userID, email: "owned@example.invalid", displayName: "Owned", totalExperience: 0)
    try account.applyAccountTagDirectory(directory([a,b]), read: account.beginAccountTagDirectoryRead())
    let current = try row([a]), actualScope = try XCTUnwrap(account.resultPublicationScope)
    try account.applyLastAccountResult(current, read: XCTUnwrap(account.beginLastAccountResultRead(id: current.id,
      finishedAt: current.finishedAt, scope: actualScope)))
    try account.applyAccountTagHistory([current], read: account.beginAccountTagHistoryRead())
    var edited = current; edited.accountTagIDs = [b]
    try account.applyAccountTagHistoryEdit(edited, scope: actualScope, at: 123)
    XCTAssertEqual(account.lastAccountResult?.accountTagIDs,[a])
    XCTAssertEqual(account.historyAccountTagMetadata[current.id]?.tagIDs,[b])
    try account.applyAccountTagDirectory(directory([b]), read: account.beginAccountTagDirectoryRead())
    XCTAssertEqual(account.historyAccountTagMetadata[current.id]?.tagIDs,[b])
    XCTAssertTrue(account.updateEndpoint("https://other.invalid"))
    XCTAssertTrue(account.historyAccountTagMetadata.isEmpty)
  }

  func testStableIDFilteringAgainstCompletePinnedFunctions() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Readiness supplies the pinned reference")
    }
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Scripts/check-source-account-tag-filter.mjs")
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node",script.path,reference,"--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors
    try process.run()
    let bytes = output.fileHandleForReading.readDataToEndOfFile()
    let error = errors.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus,0,String(decoding: error,as: UTF8.self))
    struct Query: Decodable { let selectedIDs: Set<UUID>; let includesNoTags: Bool; let tagIDs: [UUID]; let matches: Bool }
    struct Directory: Decodable {
      let knownIDs: Set<UUID>; let selectedIDs: Set<UUID>; let includesNoTags: Bool
      let nextKnownIDs: Set<UUID>; let expectedIDs: Set<UUID>
    }
    struct Current: Decodable { let mode: TestMode; let activeIDs: Set<UUID>; let selectedIDs: Set<UUID>; let includesNoTags: Bool }
    struct Normalization: Decodable { let knownIDs: Set<UUID>; let tagIDs: [UUID]; let expectedIDs: [UUID] }
    struct Document: Decodable {
      let referenceCommit: String; let ids: Set<UUID>; let queryFixtures: [Query]; let directoryFixtures: [Directory]
      let currentFixtures: [Current]; let normalizationFixtures: [Normalization]
    }
    let document = try JSONDecoder().decode(Document.self,from: bytes)
    XCTAssertEqual(document.referenceCommit,"91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(document.queryFixtures.count,128); XCTAssertEqual(document.directoryFixtures.count,432)
    XCTAssertEqual(document.currentFixtures.count,40); XCTAssertEqual(document.normalizationFixtures.count,64)
    for row in document.queryFixtures {
      let filter = ResultHistoryAccountTagFilter(scope: scope, knownIDs: document.ids,
        selectedIDs: row.selectedIDs, includesNoTags: row.includesNoTags)
      XCTAssertEqual(filter.matches(.init(scope: scope, tagIDs: row.tagIDs)),row.matches)
    }
    for row in document.directoryFixtures {
      var filter = ResultHistoryAccountTagFilter(scope: scope, knownIDs: row.knownIDs,
        selectedIDs: row.selectedIDs, includesNoTags: row.includesNoTags)
      filter.reconcile(scope: scope, knownIDs: row.nextKnownIDs)
      XCTAssertEqual(filter.selectedIDs,row.expectedIDs); XCTAssertEqual(filter.includesNoTags,row.includesNoTags)
    }
    for row in document.currentFixtures {
      let selection = ResultHistoryAccountTagFilter(scope: scope, knownIDs: document.ids,
        selectedIDs: row.activeIDs, includesNoTags: row.activeIDs.isEmpty)
      var config = TestConfiguration.timed(seconds: 15); config.mode = row.mode
      let filter = try XCTUnwrap(ResultHistoryFilter.currentSettings(config, accountTagFilter: selection).accountTagFilter)
      XCTAssertEqual(filter.selectedIDs,row.selectedIDs); XCTAssertEqual(filter.includesNoTags,row.includesNoTags)
    }
    for row in document.normalizationFixtures {
      let snapshot = ResultAccountTagSnapshot(scope: scope, tagIDs: row.tagIDs)
      XCTAssertEqual(AccountTagHistoryFilterPolicy.metadata(id: UUID(), snapshot: snapshot,
        scope: scope, knownIDs: row.knownIDs, canonical: [:])?.tagIDs,row.expectedIDs)
      XCTAssertEqual(snapshot.tagIDs,row.tagIDs)
    }
  }
}
