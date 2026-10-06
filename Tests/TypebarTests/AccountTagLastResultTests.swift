import Foundation
import XCTest
@testable import Typebar

final class AccountTagLastResultTests: XCTestCase {
  private let a = UUID(), b = UUID()
  private func row(ids: [UUID] = [], speed: Double = 80.49, finishedAt: Double = 115) throws -> RemoteAccountResult {
    try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject:
      ["id": UUID().uuidString, "mode": "time", "mode2": "15", "language": "english",
        "durationSeconds": 15, "wpm": Int(speed.rounded()), "rawWpm": 96, "accuracy": 98,
        "preciseAccuracy": 98.25, "consistency": 80.75, "errorCount": 1, "eventCount": 75,
        "tags": ["local text"], "accountTagIDs": ids.map(\.uuidString), "startedAt": 100, "finishedAt": finishedAt,
        "startedAtReferenceTime": 100.0, "finishedAtReferenceTime": finishedAt,
        "speedPrecision": ["version": 1, "wpm": speed, "rawWpm": 95.75],
        "personalBestConfiguration": ["version": 1, "difficulty": "normal", "punctuation": false,
          "numbers": false, "lazyMode": false]]))
  }
  func testLastResultCanBeEditedWithoutCreatingAReadyHistoryCache() throws {
    let last = try row(ids: [a])
    XCTAssertEqual(try RemoteAccountTagEditPolicy.editableResult(id: last.id, history: nil, lastResult: last), last)
    XCTAssertThrowsError(try RemoteAccountTagEditPolicy.editableResult(id: UUID(), history: nil, lastResult: last))
    XCTAssertThrowsError(try RemoteAccountTagEditPolicy.editableResult(id: last.id, history: nil, lastResult: nil))
  }
  func testIncompleteHistoryUsesOnlyLastResultAndReadyHistoryDoesNotPretendMissingRowsExist() throws {
    let last = try row(ids: [a]), older = try row(ids: [b])
    var history = try AccountTagHistoryCache(scope: .init(endpoint: "https://owned.invalid", userID: UUID()),
      results: [older], knownIDs: [a,b])
    XCTAssertThrowsError(try RemoteAccountTagEditPolicy.editableResult(id: last.id, history: history, lastResult: last))
    history.markIncomplete()
    XCTAssertEqual(try RemoteAccountTagEditPolicy.editableResult(id: last.id, history: history, lastResult: last), last)
    XCTAssertThrowsError(try RemoteAccountTagEditPolicy.editableResult(id: older.id, history: history, lastResult: last))
  }

  private func directory(name: String = "desk") throws -> RemoteAccountTagList {
    try JSONDecoder().decode(RemoteAccountTagList.self, from: JSONSerialization.data(withJSONObject:
      ["version": 1, "tags": [a,b].map { ["id": $0.uuidString, "name": name,
        "personalBestLedgerVersion": 1, "personalBests": []] }]))
  }
  @MainActor private func account() throws -> (AccountSession, UserDefaults, String) {
    let suite = "TypebarTests.last-result.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let session = AccountSession(defaults: defaults)
    session.currentUser = .init(id: UUID(), email: "owned@example.invalid", displayName: "Owned", totalExperience: 500)
    try session.applyAccountTagDirectory(directory(), read: session.beginAccountTagDirectoryRead())
    return (session, defaults, suite)
  }
  private func edit(_ result: RemoteAccountResult, ids: [UUID], awards: [UUID]) throws -> RemoteAccountTagEditResponse {
    var value = result; value.accountTagIDs = ids
    var root = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    root["tagPbs"] = awards.map(\.uuidString)
    return try JSONDecoder().decode(RemoteAccountTagEditResponse.self, from: JSONSerialization.data(withJSONObject: root))
  }
  @MainActor private func accept(_ row: RemoteAccountResult, in session: AccountSession) throws {
    let read = try XCTUnwrap(session.beginLastAccountResultRead(id: row.id, finishedAt: row.finishedAt,
      scope: XCTUnwrap(session.resultPublicationScope)))
    try session.applyLastAccountResult(row, read: read)
  }
  @MainActor func testSessionWritesOnlyReturnedAwardsAndDoesNotLoadOrRebuildHistory() throws {
    let (session, defaults, suite) = try account(); defer { defaults.removePersistentDomain(forName: suite) }
    let last = try row(ids: [a]); try accept(last, in: session)
    try session.setAccountTagPostingSelection([a])
    let scope = try XCTUnwrap(session.resultPublicationScope)
    let oldRead = try session.beginAccountTagHistoryRead()
    try session.applyAccountTagEditResponse(edit(last, ids: [a,b], awards: [b]), requestedIDs: [a,b], scope: scope, at: 1_800_000_000_875)
    XCTAssertNil(session.accountTagHistoryCache); XCTAssertFalse(session.isAccountTagHistoryReady)
    XCTAssertTrue(session.remoteResults.isEmpty); XCTAssertEqual(session.lastAccountResult?.accountTagIDs, [a,b])
    XCTAssertEqual(session.lastAccountResultEditAwardIDs, [b]); XCTAssertEqual(last.accountTagIDs, [a])
    let pb = try XCTUnwrap(session.accountTagHistoryPersonalBests.first)
    XCTAssertEqual(pb.tagID, b); XCTAssertEqual(pb.wpm, 80.49); XCTAssertEqual(pb.rawWpm, 95.75)
    XCTAssertEqual(pb.accuracy, 98.25); XCTAssertEqual(pb.consistency, 80.75)
    XCTAssertEqual(pb.rebuiltAtMilliseconds, 1_800_000_000_875)
    XCTAssertThrowsError(try session.applyAccountTagHistory([last], read: oldRead))
    try session.applyAccountTagEditResponse(edit(try XCTUnwrap(session.lastAccountResult), ids: [], awards: []),
      requestedIDs: [], scope: scope, at: 1_800_000_001_000)
    XCTAssertEqual(session.accountTagHistoryPersonalBests, [pb]); XCTAssertEqual(session.lastAccountResult?.accountTagIDs, [])
    XCTAssertTrue(session.lastAccountResultEditAwardIDs.isEmpty)
    XCTAssertEqual(try session.accountTagPostingSelection(), [a]); XCTAssertEqual(session.currentUser?.totalExperience, 500)
    XCTAssertTrue(session.accountTags.allSatisfy { $0.personalBests.isEmpty })
  }
  @MainActor func testInvalidConfirmedMetadataCannotAlterLastResultOrAwardBook() throws {
    let (session, defaults, suite) = try account(); defer { defaults.removePersistentDomain(forName: suite) }
    let last = try row(ids: [a]); try accept(last, in: session)
    let scope = try XCTUnwrap(session.resultPublicationScope)
    for response in [try edit(row(ids: [a]), ids: [b], awards: [b]),
      try edit(row(ids: [a], speed: 70), ids: [b], awards: [b]),
      try edit(last, ids: [UUID()], awards: [])] {
      XCTAssertThrowsError(try session.applyAccountTagEditResponse(response, requestedIDs: response.result.accountTagIDs ?? [], scope: scope, at: 123))
      XCTAssertEqual(session.lastAccountResult, last); XCTAssertTrue(session.accountTagHistoryPersonalBests.isEmpty)
    }
    XCTAssertThrowsError(try session.applyAccountTagEditResponse(edit(last, ids: [b], awards: [b]),
      requestedIDs: [b], scope: scope, at: -1))
    XCTAssertEqual(session.lastAccountResult, last)
  }
  @MainActor func testPendingReadLatestOrderingFailureAndSameAccountRoundTripDoNotReviveLastResult() throws {
    let (session, defaults, suite) = try account(); defer { defaults.removePersistentDomain(forName: suite) }
    let first = try row(), newer = try row(finishedAt: 120), scope = try XCTUnwrap(session.resultPublicationScope)
    let oldRead = try XCTUnwrap(session.beginLastAccountResultRead(id: first.id, finishedAt: first.finishedAt, scope: scope))
    let newRead = try XCTUnwrap(session.beginLastAccountResultRead(id: newer.id, finishedAt: newer.finishedAt, scope: scope))
    XCTAssertNil(session.beginLastAccountResultRead(id: first.id, finishedAt: first.finishedAt, scope: scope))
    XCTAssertThrowsError(try session.applyLastAccountResult(first, read: oldRead))
    try session.applyLastAccountResult(newer, read: newRead)
    session.failLastAccountResultRead(oldRead)
    XCTAssertEqual(session.lastAccountResult, newer)
    let pending = try XCTUnwrap(session.beginLastAccountResultRead(id: newer.id, finishedAt: newer.finishedAt, scope: scope))
    session.failLastAccountResultRead(pending)
    XCTAssertNil(session.lastAccountResult); XCTAssertThrowsError(try session.applyLastAccountResult(newer, read: pending))
    let fresh = try XCTUnwrap(session.beginLastAccountResultRead(id: newer.id, finishedAt: newer.finishedAt, scope: scope))
    let user = session.currentUser; session.currentUser = nil; session.currentUser = user
    XCTAssertThrowsError(try session.applyLastAccountResult(newer, read: fresh)); XCTAssertNil(session.lastAccountResult)
    XCTAssertTrue(session.accountTagHistoryPersonalBests.isEmpty)
  }
  @MainActor func testReadyAndIncompleteTransitionsKeepOneEffectivePBPerGroup() throws {
    let (session, defaults, suite) = try account(); defer { defaults.removePersistentDomain(forName: suite) }
    let last = try row(ids: [a]), scope = try XCTUnwrap(session.resultPublicationScope)
    try accept(last, in: session)
    try session.applyAccountTagEditResponse(edit(last, ids: [a,b], awards: [b]), requestedIDs: [a,b], scope: scope, at: 123)
    let linked = try XCTUnwrap(session.lastAccountResult)
    try session.applyAccountTagHistory([linked], read: session.beginAccountTagHistoryRead())
    XCTAssertEqual(session.accountTagHistoryPersonalBests.first?.wpm, 80.49)
    try session.applyAccountTagEditResponse(edit(linked, ids: [a], awards: []), requestedIDs: [a], scope: scope, at: 124)
    XCTAssertEqual(session.accountTagHistoryPersonalBests.first { $0.tagID == b }?.wpm, 0)
    session.invalidateAccountTagHistory(clearLastResult: false)
    XCTAssertEqual(session.accountTagHistoryPersonalBests.first { $0.tagID == b }?.wpm, 0,
      "Losing history must not resurrect a superseded last-result award")
    try session.applyAccountTagHistory([try XCTUnwrap(session.lastAccountResult)], read: session.beginAccountTagHistoryRead())
    let new = try row(ids: [a], finishedAt: 120)
    _ = try XCTUnwrap(session.beginAcceptedAccountTagHistoryInsertion(id: new.id, scope: scope))
    try accept(new, in: session); XCTAssertFalse(session.isAccountTagHistoryReady)
    try session.applyAccountTagEditResponse(edit(new, ids: [a,b], awards: [b]), requestedIDs: [a,b], scope: scope, at: 125)
    XCTAssertEqual(session.accountTagHistoryPersonalBests.filter { $0.tagID == b }.count, 1)
    XCTAssertEqual(session.accountTagHistoryPersonalBests.first { $0.tagID == b }?.wpm, 80.49)
    XCTAssertFalse(session.isAccountTagHistoryReady)
  }
  @MainActor func testHistoryDeletionRenameTagClearAndTagDeletionHaveSeparateLifetimes() throws {
    let (session, defaults, suite) = try account(); defer { defaults.removePersistentDomain(forName: suite) }
    let last = try row(ids: [a]), scope = try XCTUnwrap(session.resultPublicationScope)
    try accept(last, in: session)
    try session.applyAccountTagEditResponse(edit(last, ids: [a,b], awards: [b]), requestedIDs: [a,b], scope: scope, at: 123)
    try session.applyAccountTagDirectory(directory(name: "renamed"), read: session.beginAccountTagDirectoryRead())
    XCTAssertEqual(session.accountTagHistoryPersonalBests.first?.wpm, 80.49)
    try session.applyConfirmedAccountHistoryDeletion(read: session.beginAccountTagHistoryRead())
    XCTAssertNil(session.lastAccountResult); XCTAssertEqual(session.accountTagHistoryPersonalBests.first?.wpm, 80.49)
    try accept(last, in: session)
    try session.applyAccountTagEditResponse(edit(last, ids: [a,b], awards: [b]), requestedIDs: [a,b], scope: scope, at: 124)
    try session.applyConfirmedAccountTagDeletion(id: b, personalBestsOnly: true, scope: scope)
    XCTAssertTrue(session.accountTagHistoryPersonalBests.isEmpty); XCTAssertEqual(session.lastAccountResult?.accountTagIDs, [a,b])
    try session.applyConfirmedAccountTagDeletion(id: b, personalBestsOnly: false, scope: scope)
    XCTAssertEqual(session.lastAccountResult?.accountTagIDs, [a])
    let oldResponse = try edit(last, ids: [a,b], awards: [b])
    let user = session.currentUser; session.currentUser = nil; session.currentUser = user
    XCTAssertThrowsError(try session.applyAccountTagEditResponse(oldResponse, requestedIDs: [a,b], scope: scope, at: 125))
  }
  func testReturnedAwardsAgainstCompletePinnedUnreadyEditAndSaveFunctions() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else { throw XCTSkip("Pinned reference required") }
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Scripts/check-source-account-tag-last-result.mjs")
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", script.path, reference, "--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors; try process.run()
    let bytes = output.fileHandleForReading.readDataToEndOfFile(), diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0, String(decoding: diagnostics, as: UTF8.self))
    struct Best: Decodable { let tagID: UUID; let wpm: Double; let rawWpm: Double; let accuracy: Double; let consistency: Double; let at: Int64 }
    struct Fixture: Decodable { let result: RemoteAccountResult; let tagIDs: [UUID]; let awardIDs: [UUID]; let at: Int64; let expected: [Best] }
    struct Document: Decodable { let referenceCommit: String; let fixtures: [Fixture] }
    let document = try JSONDecoder().decode(Document.self, from: bytes)
    XCTAssertEqual(document.referenceCommit, "91bd24bb8513785c7364cbea29296ff7adafac41"); XCTAssertEqual(document.fixtures.count, 960)
    for fixture in document.fixtures {
      let tags = try JSONDecoder().decode(RemoteAccountTagList.self, from: JSONSerialization.data(withJSONObject:
        ["version": 1, "tags": fixture.tagIDs.map { ["id": $0.uuidString, "name": "desk", "personalBestLedgerVersion": 1, "personalBests": []] }])).tags
      var book = AccountTagLastResultAwards(scope: .init(endpoint: "https://owned.invalid", userID: UUID()), directory: tags)
      try book.save(fixture.awardIDs, from: fixture.result, at: fixture.at)
      XCTAssertEqual(book.personalBests.count, fixture.result.mode == "quote" ? 0 : fixture.awardIDs.count)
      for expected in fixture.expected where fixture.awardIDs.contains(expected.tagID) && fixture.result.mode != "quote" {
        let actual = try XCTUnwrap(book.personalBests.first { $0.tagID == expected.tagID })
        XCTAssertEqual(actual.wpm, expected.wpm); XCTAssertEqual(actual.rawWpm, expected.rawWpm)
        XCTAssertEqual(actual.accuracy, expected.accuracy); XCTAssertEqual(actual.consistency, expected.consistency)
        XCTAssertEqual(actual.rebuiltAtMilliseconds, expected.at)
      }
      let before = book.personalBests
      try book.save([], from: fixture.result, at: fixture.at + 1)
      XCTAssertEqual(book.personalBests, before)
    }
  }
  func testExplicitAwardReplacesHigherOrEqualLocalMetricsButQuoteAndEmptyAwardsDoNotWrite() throws {
    var book = AccountTagLastResultAwards(scope: .init(endpoint: "https://owned.invalid", userID: UUID()),
      directory: try directory().tags)
    try book.save([a,b], from: row(speed: 90.49), at: 100)
    try book.save([b], from: row(speed: 80.49), at: 101)
    XCTAssertEqual(book.personalBests.first { $0.tagID == a }?.wpm, 90.49)
    XCTAssertEqual(book.personalBests.first { $0.tagID == b }?.wpm, 80.49)
    try book.save([b], from: row(speed: 80.49), at: 102)
    XCTAssertEqual(book.personalBests.first { $0.tagID == b }?.rebuiltAtMilliseconds, 102)
    var root = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(row())) as? [String: Any])
    root["mode"] = "quote"; root["mode2"] = "typebar:owned"
    let quote = try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: root))
    let before = book.personalBests
    try book.save([a,b], from: quote, at: 103)
    try book.save([], from: row(), at: 104)
    XCTAssertEqual(book.personalBests, before)
  }
  @MainActor func testInitialHistorySeedsLatestLastResultButDoesNotReplaceExplicitAcceptedResult() throws {
    let (session, defaults, suite) = try account(); defer { defaults.removePersistentDomain(forName: suite) }
    let older = try row(finishedAt: 110), newer = try row(finishedAt: 120)
    try session.applyAccountTagHistory([newer,older], read: session.beginAccountTagHistoryRead())
    XCTAssertEqual(session.lastAccountResult, newer)
    session.invalidateAccountTagHistory()
    try accept(older, in: session)
    try session.applyAccountTagHistory([newer,older], read: session.beginAccountTagHistoryRead())
    XCTAssertEqual(session.lastAccountResult, older, "Pinned query seeds only an absent last result")
  }
}
