import Foundation
import XCTest
@testable import Typebar

final class AccountTagHistoryCacheTests: XCTestCase {
  private let first = UUID(), second = UUID(), unchanged = UUID()
  private let scope = ResultPublicationScope(endpoint: "https://owned.invalid", userID: UUID())
  private func result(_ ids: [UUID]?, speed: Double = 80.49, raw: Int = 90,
    accuracy: Int = 98, consistency: Double = 80, mode: String = "time", mode2: String = "15",
    difficulty: String = "normal", language: String = "english", known: Bool = true) throws -> RemoteAccountResult {
    var root: [String: Any] = ["id": UUID().uuidString, "mode": mode, "mode2": mode2,
      "language": language, "wpm": Int(speed.rounded()), "rawWpm": raw, "accuracy": accuracy,
      "consistency": consistency, "errorCount": 1, "eventCount": 75, "tags": ["owned local label"],
      "startedAt": 100, "finishedAt": 115]
    if mode == "time" { root["durationSeconds"] = Int(mode2) }
    if mode == "words" { root["wordLimit"] = Int(mode2) }
    if let ids { root["accountTagIDs"] = ids.map(\.uuidString) }
    if known { root["personalBestConfiguration"] = ["version": 1, "difficulty": difficulty,
      "punctuation": false, "numbers": false, "lazyMode": false] }
    if speed != Double(Int(speed.rounded())) {
      root["speedPrecision"] = ["version": 1, "wpm": speed, "rawWpm": Double(raw)]
      root["startedAtReferenceTime"] = 100.0; root["finishedAtReferenceTime"] = 115.0
    }
    return try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: root))
  }
  func testRemovedBestFallsToLowerCachedRowAndNewTagGetsFullFractionalSnapshot() throws {
    let high = try result([first, unchanged]), low = try result([first], speed: 60.41, raw: 70, accuracy: 90, consistency: 50)
    var cache = try AccountTagHistoryCache(scope: scope, results: [high, low], knownIDs: [first, second, unchanged])
    try cache.edit(id: high.id, tagIDs: [second, unchanged], knownIDs: [first, second, unchanged], at: 1_800_000_000_875)
    let old = try XCTUnwrap(cache.personalBests.first { $0.tagID == first })
    XCTAssertEqual(old.wpm, 60.41); XCTAssertEqual(old.rawWpm, 70)
    XCTAssertEqual(old.accuracy, 90); XCTAssertEqual(old.consistency, 50)
    let added = try XCTUnwrap(cache.personalBests.first { $0.tagID == second })
    XCTAssertEqual(added.wpm, 80.49); XCTAssertEqual(added.rebuiltAtMilliseconds, 1_800_000_000_875)
    XCTAssertFalse(cache.personalBests.contains { $0.tagID == unchanged })
    XCTAssertEqual(cache.results.first?.tags, ["owned local label"])
  }
  func testEmptyRebuildIsAnExplicitZeroAndEqualSpeedKeepsFirstCompleteMetrics() throws {
    let one = try result([first], speed: 80, raw: 100, accuracy: 90, consistency: 40)
    let two = try result([first], speed: 80, raw: 95, accuracy: 99, consistency: 90)
    let edited = try result([second], speed: 60)
    var cache = try AccountTagHistoryCache(scope: scope, results: [one, two, edited], knownIDs: [first, second])
    try cache.edit(id: edited.id, tagIDs: [first], knownIDs: [first, second], at: 123)
    let zero = try XCTUnwrap(cache.personalBests.first { $0.tagID == second })
    XCTAssertEqual(zero.wpm, 0); XCTAssertEqual(zero.rawWpm, 0)
    let tie = try XCTUnwrap(cache.personalBests.first { $0.tagID == first })
    XCTAssertEqual(tie.rawWpm, 100); XCTAssertEqual(tie.accuracy, 90); XCTAssertEqual(tie.consistency, 40)
  }
  func testDeletionNormalizesCacheOnlyAndClearPBDoesNotRemoveAssociations() throws {
    let row = try result([first, second]), unknown = try result(nil, known: false)
    var cache = try AccountTagHistoryCache(scope: scope, results: [row, unknown], knownIDs: [first, second])
    cache.removeTag(first, clearOnly: true)
    XCTAssertEqual(cache.results[0].accountTagIDs, [first, second])
    cache.removeTag(first, clearOnly: false)
    XCTAssertEqual(cache.results[0].accountTagIDs, [second]); XCTAssertNil(cache.results[1].accountTagIDs)
    XCTAssertEqual(row.accountTagIDs, [first, second])
    XCTAssertEqual(try AccountTagHistoryCache(scope: scope, results: [row], knownIDs: [second]).results[0].accountTagIDs, [second])
  }
  func testOtherGroupsAndUnknownOptionsCannotLeakIntoRebuiltTarget() throws {
    let original = try result([first], speed: 60)
    let unrelated = try result([first], speed: 90, mode2: "30")
    let unknown = try result([first], speed: 100, raw: 110, known: false)
    var cache = try AccountTagHistoryCache(scope: scope, results: [original, unrelated, unknown], knownIDs: [first])
    try cache.edit(id: original.id, tagIDs: [], knownIDs: [first], at: 123)
    XCTAssertEqual(cache.personalBests.first?.wpm, 0)
    let before = cache.personalBests
    try cache.edit(id: unknown.id, tagIDs: [], knownIDs: [first], at: 124)
    XCTAssertEqual(cache.personalBests, before)
  }
  func testInvalidEditAndDuplicateHistoryDoNotReplaceCachedState() throws {
    let row = try result([first])
    var cache = try AccountTagHistoryCache(scope: scope, results: [row], knownIDs: [first])
    XCTAssertThrowsError(try cache.edit(id: row.id, tagIDs: [second], knownIDs: [first], at: 123))
    XCTAssertThrowsError(try cache.edit(id: row.id, tagIDs: [], knownIDs: [first], at: -1))
    XCTAssertEqual(cache.results, [row]); XCTAssertTrue(cache.personalBests.isEmpty)
    XCTAssertThrowsError(try AccountTagHistoryCache(scope: scope, results: [row, row], knownIDs: [first]))
  }
  func testPaceReadsLowerAndExplicitZeroCacheInsteadOfFallingBackToServiceAward() throws {
    let high = try result([first]), low = try result([first], speed: 60.41, raw: 70)
    let best: [String: Any] = ["id": high.id.uuidString, "mode": "time", "mode2": "15",
      "durationSeconds": 15, "language": "english", "wpm": 80, "preciseWpm": 80.49,
      "rawWpm": 90, "preciseRawWpm": 90.0, "accuracy": 98, "consistency": 80,
      "finishedAt": 115, "acceptedAtMilliseconds": 123, "personalBestOrigin": "accepted",
      "personalBestConfiguration": ["version": 1, "difficulty": "normal", "punctuation": false,
        "numbers": false, "lazyMode": false]]
    let root: [String: Any] = ["version": 1, "tags": [["id": first.uuidString, "name": "desk",
      "personalBestLedgerVersion": 1, "personalBests": [best]]]]
    let tags = try JSONDecoder().decode(RemoteAccountTagList.self,
      from: JSONSerialization.data(withJSONObject: root)).tags
    var cache = try AccountTagHistoryCache(scope: scope, results: [high, low], knownIDs: [first])
    try cache.edit(id: high.id, tagIDs: [], knownIDs: [first], at: 456)
    func pace() -> Double? {
      AccountTagPacePolicy.targetWpm(configuration: .timed(seconds: 15), tags: tags,
        selectedIDs: [first], historyPersonalBests: cache.personalBests)
    }
    XCTAssertEqual(pace(), 60.41)
    try cache.edit(id: low.id, tagIDs: [], knownIDs: [first], at: 789)
    XCTAssertNil(pace(), "A known zero must disable pace, not resurrect the accepted service PB")
    XCTAssertEqual(tags.first?.personalBests.first?.effectiveWpm, 80.49)
  }

  private func directory(name: String = "desk") throws -> RemoteAccountTagList {
    try JSONDecoder().decode(RemoteAccountTagList.self, from: JSONSerialization.data(withJSONObject:
      ["version": 1, "tags": [first, second, unchanged].map { ["id": $0.uuidString, "name": name,
        "personalBestLedgerVersion": 1, "personalBests": []] }]))
  }
  @MainActor private func ownedAccount() throws -> (AccountSession, UserDefaults, String) {
    let suite = "TypebarTests.tag-history.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let account = AccountSession(defaults: defaults)
    account.currentUser = .init(id: scope.userID, email: "owned@example.invalid", displayName: "Owned", totalExperience: 0)
    try account.applyAccountTagDirectory(directory(), read: account.beginAccountTagDirectoryRead())
    return (account, defaults, suite)
  }
  @MainActor func testActualSessionUsesRowsBeyondTwentyAndHistoryRefreshDoesNotEraseClientPB() throws {
    let (account, defaults, suite) = try ownedAccount(); defer { defaults.removePersistentDomain(forName: suite) }
    let high = try result([first]), low = try result([first], speed: 60.41, raw: 70)
    let rows = [high] + (try (0..<20).map { _ in try result([]) }) + [low]
    try account.applyAccountTagHistory(rows, read: account.beginAccountTagHistoryRead())
    XCTAssertEqual(account.remoteResults.count, 20); XCTAssertEqual(account.accountTagHistoryCache?.results.count, 22)
    var edited = high; edited.accountTagIDs = [second]
    try account.applyAccountTagHistoryEdit(edited, scope: try XCTUnwrap(account.resultPublicationScope), at: 123)
    XCTAssertEqual(account.accountTagHistoryPersonalBests.first { $0.tagID == first }?.wpm, 60.41)
    var updated = rows; updated[0] = edited
    try account.applyAccountTagHistory(updated, read: account.beginAccountTagHistoryRead())
    XCTAssertEqual(account.accountTagHistoryPersonalBests.first { $0.tagID == first }?.wpm, 60.41)
    try account.applyAccountTagDirectory(directory(name: "renamed"), read: account.beginAccountTagDirectoryRead())
    XCTAssertEqual(account.accountTagHistoryPersonalBests.first { $0.tagID == first }?.wpm, 60.41)
    XCTAssertEqual(account.accountTags.first?.name, "renamed")
  }
  @MainActor func testOlderReadCannotUndoEditOrReviveHistoryAfterAccountRoundTrip() throws {
    let (account, defaults, suite) = try ownedAccount(); defer { defaults.removePersistentDomain(forName: suite) }
    let row = try result([first])
    let old = try account.beginAccountTagHistoryRead(), new = try account.beginAccountTagHistoryRead()
    try account.applyAccountTagHistory([row], read: new)
    XCTAssertThrowsError(try account.applyAccountTagHistory([], read: old))
    var edited = row; edited.accountTagIDs = []
    try account.applyAccountTagHistoryEdit(edited, scope: try XCTUnwrap(account.resultPublicationScope), at: 123)
    XCTAssertThrowsError(try account.applyAccountTagHistory([row], read: new))
    let user = account.currentUser
    account.currentUser = nil; account.currentUser = user
    XCTAssertNil(account.accountTagHistoryCache); XCTAssertTrue(account.accountTagHistoryPersonalBests.isEmpty)
    XCTAssertThrowsError(try account.applyAccountTagHistory([row], read: new))
  }
  @MainActor func testMalformedRefreshAndChangedScoreCannotCorruptReadyCache() throws {
    let (account, defaults, suite) = try ownedAccount(); defer { defaults.removePersistentDomain(forName: suite) }
    let row = try result([first])
    try account.applyAccountTagHistory([row], read: account.beginAccountTagHistoryRead())
    XCTAssertThrowsError(try account.applyAccountTagHistory([row, row], read: account.beginAccountTagHistoryRead()))
    XCTAssertEqual(account.accountTagHistoryCache?.results, [row])
    var other = try result([second], speed: 80, raw: 10)
    XCTAssertThrowsError(try account.applyAccountTagHistory([other], read: account.beginAccountTagHistoryRead()))
    other.accountTagIDs = []
    XCTAssertThrowsError(try account.applyAccountTagHistoryEdit(other, scope: try XCTUnwrap(account.resultPublicationScope), at: 123))
    XCTAssertEqual(account.accountTagHistoryCache?.results, [row])
  }
  @MainActor func testUnknownDirectoryKeepsLegacyHistoryVisibleWithoutMakingTagPBs() throws {
    let suite = "TypebarTests.tag-history-legacy.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let account = AccountSession(defaults: defaults)
    account.currentUser = .init(id: scope.userID, email: "owned@example.invalid", displayName: "Owned", totalExperience: 0)
    let row = try result(nil, known: false)
    try account.applyAccountTagHistory([row], read: account.beginAccountTagHistoryRead())
    XCTAssertEqual(account.remoteResults, [row]); XCTAssertNil(account.accountTagHistoryCache)
    XCTAssertTrue(account.accountTagHistoryPersonalBests.isEmpty)
  }
  func testDirectoryChangesAndClearHistoryRespectSeparateCachedPBAndAssociationLifetimes() throws {
    let row = try result([first, second])
    var cache = try AccountTagHistoryCache(scope: scope, results: [row], knownIDs: [first, second], directory: directory().tags)
    try cache.edit(id: row.id, tagIDs: [second], knownIDs: [first, second], at: 123)
    cache.clearResults(); XCTAssertTrue(cache.results.isEmpty)
    XCTAssertEqual(cache.personalBests.first?.wpm, 0)
    let subset = try JSONDecoder().decode(RemoteAccountTagList.self, from: JSONSerialization.data(withJSONObject:
      ["version": 1, "tags": [["id": second.uuidString, "name": "desk", "personalBestLedgerVersion": 1, "personalBests": []]]]))
    cache.adoptDirectory(subset.tags)
    XCTAssertTrue(cache.personalBests.isEmpty)
  }
  func testQuoteCannotCreateCachePBAndNewServiceAwardOnlyReplacesItsChangedGroup() throws {
    let quoted = try result([first], mode: "quote", mode2: "typebar:owned")
    var quotes = try AccountTagHistoryCache(scope: scope, results: [quoted], knownIDs: [first])
    try quotes.edit(id: quoted.id, tagIDs: [], knownIDs: [first], at: 123)
    XCTAssertTrue(quotes.personalBests.isEmpty)
    let row = try result([first, second])
    var cache = try AccountTagHistoryCache(scope: scope, results: [row], knownIDs: [first, second], directory: directory().tags)
    try cache.edit(id: row.id, tagIDs: [], knownIDs: [first, second], at: 123)
    let json: [String: Any] = ["version": 1, "tags": [["id": first.uuidString, "name": "desk",
      "personalBestLedgerVersion": 1, "personalBests": [["id": row.id.uuidString,
        "mode": "time", "mode2": "15", "durationSeconds": 15, "language": "english",
        "wpm": 90, "rawWpm": 100, "accuracy": 98, "consistency": 80, "finishedAt": 115,
        "acceptedAtMilliseconds": 124, "personalBestOrigin": "accepted",
        "personalBestConfiguration": ["version": 1, "difficulty": "normal", "punctuation": false,
          "numbers": false, "lazyMode": false]]]],
      ["id": second.uuidString, "name": "desk", "personalBestLedgerVersion": 1, "personalBests": []]]]
    let updated = try JSONDecoder().decode(RemoteAccountTagList.self, from: JSONSerialization.data(withJSONObject: json))
    cache.adoptDirectory(updated.tags)
    XCTAssertNil(cache.personalBests.first { $0.tagID == first })
    XCTAssertEqual(cache.personalBests.first { $0.tagID == second }?.wpm, 0)
  }
  func testCachedReconciliationAndPaceAgainstActualPinnedHistoryEditAction() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Readiness supplies the pinned reference")
    }
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Scripts/check-source-account-tag-history.mjs")
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", script.path, reference, "--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors
    try process.run()
    let bytes = output.fileHandleForReading.readDataToEndOfFile()
    let error = errors.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0, String(decoding: error, as: UTF8.self))
    struct Expected: Decodable {
      let tagID: UUID; let wpm: Double; let rawWpm: Double; let accuracy: Double
      let consistency: Double; let rebuiltAtMilliseconds: Int64
    }
    struct Fixture: Decodable {
      let mode: TestMode; let parameter: Int; let difficulty: Difficulty; let language: TypingLanguage
      let punctuation: Bool; let numbers: Bool; let lazyMode: Bool
      let directory: RemoteAccountTagList; let results: [RemoteAccountResult]
      let editedID: UUID; let newIDs: [UUID]; let at: Int64; let expected: [Expected]; let pace: [Double]
    }
    struct Document: Decodable { let referenceCommit: String; let initialResultLimit: Int; let fixtures: [Fixture] }
    let document = try JSONDecoder().decode(Document.self, from: bytes)
    XCTAssertEqual(document.referenceCommit, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(AccountTagHistoryLoadingPolicy.initialResultLimit, document.initialResultLimit)
    XCTAssertEqual(document.fixtures.count, 1440)
    for fixture in document.fixtures {
      let ids = Set(fixture.directory.tags.map(\.id))
      var cache = try AccountTagHistoryCache(scope: scope, results: fixture.results, knownIDs: ids,
        directory: fixture.directory.tags)
      try cache.edit(id: fixture.editedID, tagIDs: fixture.newIDs, knownIDs: ids, at: fixture.at)
      XCTAssertEqual(cache.personalBests.count, fixture.expected.count)
      for expected in fixture.expected {
        let native = try XCTUnwrap(cache.personalBests.first { $0.tagID == expected.tagID })
        XCTAssertEqual(native.wpm, expected.wpm); XCTAssertEqual(native.rawWpm, expected.rawWpm)
        XCTAssertEqual(native.accuracy, expected.accuracy); XCTAssertEqual(native.consistency, expected.consistency)
        XCTAssertEqual(native.rebuiltAtMilliseconds, expected.rebuiltAtMilliseconds)
      }
      let config = TestConfiguration(mode: fixture.mode,
        duration: fixture.mode == .time ? Double(fixture.parameter) : nil,
        wordLimit: fixture.mode == .words ? fixture.parameter : nil, difficulty: fixture.difficulty,
        rules: .init(), language: fixture.language, modifiers: fixture.lazyMode ? [.lazyLatin] : [],
        contentOptions: .init(includePunctuation: fixture.punctuation, includeNumbers: fixture.numbers))
      for (index, tag) in fixture.directory.tags.enumerated() {
        XCTAssertEqual(AccountTagPacePolicy.targetWpm(configuration: config, tags: fixture.directory.tags,
          selectedIDs: [tag.id], historyPersonalBests: cache.personalBests),
          fixture.pace[index] >= 1 ? fixture.pace[index] : nil)
      }
    }
  }
  func testNewAcceptedResultIsDeduplicatedAndParticipatesInNextRebuildWithoutReorderingTies() throws {
    let old = try result([first], speed: 60, raw: 70, accuracy: 90, consistency: 40)
    let new = try result([first], speed: 80, raw: 95, accuracy: 99, consistency: 90)
    var cache = try AccountTagHistoryCache(scope: scope, results: [old], knownIDs: [first])
    try cache.insertAcceptedResult(new, knownIDs: [first]); try cache.insertAcceptedResult(new, knownIDs: [first])
    XCTAssertEqual(cache.results.map(\.id), [old.id, new.id])
    try cache.edit(id: old.id, tagIDs: [], knownIDs: [first], at: 123)
    XCTAssertEqual(cache.personalBests.first?.wpm, 80); XCTAssertEqual(cache.personalBests.first?.consistency, 90)
    cache.markIncomplete(); XCTAssertFalse(cache.isComplete)
    XCTAssertThrowsError(try cache.edit(id: new.id, tagIDs: [], knownIDs: [first], at: 124))
    try cache.replaceResults([new], knownIDs: [first]); XCTAssertTrue(cache.isComplete)
    XCTAssertEqual(cache.personalBests.first?.wpm, 80)
  }
  @MainActor func testAcceptedResultInsertionInvalidatesAnEarlierReadAndMissingReadyCacheStopsBeforeRequest() async throws {
    let (account, defaults, suite) = try ownedAccount(); defer { defaults.removePersistentDomain(forName: suite) }
    let row = try result([first]), new = try result([first], speed: 100, raw: 110)
    try account.applyAccountTagHistory([row], read: account.beginAccountTagHistoryRead())
    let delayed = try account.beginAccountTagHistoryRead()
    let insertion = try XCTUnwrap(account.beginAcceptedAccountTagHistoryInsertion(id: new.id,
      scope: try XCTUnwrap(account.resultPublicationScope)))
    XCTAssertFalse(account.isAccountTagHistoryReady)
    try account.applyAcceptedAccountTagHistoryResult(new, read: insertion)
    XCTAssertTrue(account.isAccountTagHistoryReady)
    XCTAssertThrowsError(try account.applyAccountTagHistory([row], read: delayed))
    XCTAssertEqual(account.accountTagHistoryCache?.results.count, 2)
    account.invalidateAccountTagHistory()
    do { try await account.updateRemoteAccountResultTagIDs(id: row.id, tagIDs: []); XCTFail("No unknown-history write") }
    catch { XCTAssertTrue(error.localizedDescription.contains("未发送")) }
  }
  @MainActor func testDelayedAcceptedReadCannotResurrectHistoryAfterSameAccountRoundTrip() throws {
    let (account, defaults, suite) = try ownedAccount(); defer { defaults.removePersistentDomain(forName: suite) }
    let row = try result([first]), accepted = try result([first], speed: 100, raw: 110)
    try account.applyAccountTagHistory([row], read: account.beginAccountTagHistoryRead())
    let insertion = try XCTUnwrap(account.beginAcceptedAccountTagHistoryInsertion(id: accepted.id,
      scope: try XCTUnwrap(account.resultPublicationScope)))
    let user = account.currentUser; account.currentUser = nil; account.currentUser = user
    try account.applyAccountTagDirectory(directory(), read: account.beginAccountTagDirectoryRead())
    try account.applyAccountTagHistory([], read: account.beginAccountTagHistoryRead())
    XCTAssertThrowsError(try account.applyAcceptedAccountTagHistoryResult(accepted, read: insertion))
    XCTAssertTrue(account.accountTagHistoryCache?.results.isEmpty == true)
  }
  func testMultipleOutstandingAcceptedRowsCannotPrematurelyMakeCacheComplete() throws {
    let one = try result([first]), two = try result([first])
    var cache = try AccountTagHistoryCache(scope: scope, results: [], knownIDs: [first])
    cache.noteAccepted(one.id); cache.noteAccepted(two.id)
    try cache.insertAcceptedResult(two, knownIDs: [first]); XCTAssertFalse(cache.isComplete)
    try cache.insertAcceptedResult(one, knownIDs: [first]); XCTAssertTrue(cache.isComplete)
  }
  @MainActor func testConfirmedHistoryDeletionKeepsCachePBAndRejectsStaleOwner() throws {
    let (account, defaults, suite) = try ownedAccount(); defer { defaults.removePersistentDomain(forName: suite) }
    let row = try result([first])
    try account.applyAccountTagHistory([row], read: account.beginAccountTagHistoryRead())
    var edited = row; edited.accountTagIDs = []
    try account.applyAccountTagHistoryEdit(edited, scope: try XCTUnwrap(account.resultPublicationScope), at: 123)
    let clear = try account.beginAccountTagHistoryRead()
    try account.applyConfirmedAccountHistoryDeletion(read: clear)
    XCTAssertTrue(account.accountTagHistoryCache?.results.isEmpty == true)
    XCTAssertEqual(account.accountTagHistoryPersonalBests.first?.wpm, 0)
    XCTAssertTrue(account.isAccountTagHistoryReady)
    XCTAssertThrowsError(try account.applyAccountTagHistory([row], read: clear))
    let old = try account.beginAccountTagHistoryRead(), user = account.currentUser
    account.currentUser = nil; account.currentUser = user
    try account.applyAccountTagDirectory(directory(), read: account.beginAccountTagDirectoryRead())
    try account.applyAccountTagHistory([row], read: account.beginAccountTagHistoryRead())
    XCTAssertThrowsError(try account.applyConfirmedAccountHistoryDeletion(read: old))
    XCTAssertEqual(account.remoteResults, [row])
  }
  @MainActor func testExplicitClearRemovesRebuiltPBWhenAcceptedDirectoryWasAlreadyEmpty() throws {
    let (account, defaults, suite) = try ownedAccount(); defer { defaults.removePersistentDomain(forName: suite) }
    let row = try result([first])
    try account.applyAccountTagHistory([row], read: account.beginAccountTagHistoryRead())
    var edited = row; edited.accountTagIDs = [second]
    let scope = try XCTUnwrap(account.resultPublicationScope)
    try account.applyAccountTagHistoryEdit(edited, scope: scope, at: 123)
    XCTAssertEqual(account.accountTagHistoryPersonalBests.first { $0.tagID == second }?.wpm, 80.49)
    XCTAssertTrue(account.accountTags.allSatisfy { $0.personalBests.isEmpty })
    try account.applyConfirmedAccountTagDeletion(id: second, personalBestsOnly: true, scope: scope)
    try account.applyAccountTagDirectory(directory(), read: account.beginAccountTagDirectoryRead())
    XCTAssertNil(account.accountTagHistoryPersonalBests.first { $0.tagID == second })
    XCTAssertEqual(account.remoteResults.first?.accountTagIDs, [second])
    try account.applyConfirmedAccountTagDeletion(id: second, personalBestsOnly: false, scope: scope)
    XCTAssertEqual(account.remoteResults.first?.accountTagIDs, [])
    let foreign = ResultPublicationScope(endpoint: "https://foreign.invalid", userID: UUID())
    XCTAssertThrowsError(try account.applyConfirmedAccountTagDeletion(id: first, personalBestsOnly: true, scope: foreign))
  }
  func testSourceInitialWindowDoesNotUseOlderCandidatesOrAcceptAnIncompleteBatch() throws {
    let high = try result([first]), low = try result([first], speed: 60.41, raw: 70)
    let fillers = try (0..<998).map { _ in try result([]) }
    let oldOutsideCache = try result([first], speed: 100, raw: 110)
    let initial = [high, low] + fillers
    let selected = try AccountTagHistoryLoadingPolicy.initialResults(.init(results: initial, total: 1001))
    XCTAssertEqual(selected.count, 1000)
    var cache = try AccountTagHistoryCache(scope: scope, results: selected, knownIDs: [first])
    try cache.edit(id: high.id, tagIDs: [], knownIDs: [first], at: 123)
    XCTAssertEqual(cache.personalBests.first?.wpm, 60.41)
    XCTAssertThrowsError(try AccountTagHistoryLoadingPolicy.initialResults(.init(results: initial + [oldOutsideCache], total: 1001)))
    XCTAssertThrowsError(try AccountTagHistoryLoadingPolicy.initialResults(.init(results: Array(initial.prefix(20)), total: 1001)))
    XCTAssertThrowsError(try AccountTagHistoryLoadingPolicy.initialResults(.init(results: [], total: -1)))
    XCTAssertTrue(try AccountTagHistoryLoadingPolicy.initialResults(.init(results: [], total: 0)).isEmpty)
  }
}
