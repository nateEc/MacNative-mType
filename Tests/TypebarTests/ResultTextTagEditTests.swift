import Foundation
import XCTest
@testable import Typebar

final class ResultTextTagEditTests: XCTestCase {
  private let a = UUID(), b = UUID()
  private func row(ids: [UUID], labels: [String] = ["old"], fractional: Bool = false) throws -> RemoteAccountResult {
    var object: [String: Any] = ["id": UUID().uuidString, "mode": "time", "mode2": "15", "language": "english",
       "durationSeconds": 15, "wpm": 80, "rawWpm": 96, "accuracy": 98, "consistency": 80,
       "errorCount": 1, "eventCount": 75, "tags": labels, "accountTagIDs": ids.map(\.uuidString),
       "startedAt": 100, "finishedAt": 115,
       "personalBestConfiguration": ["version": 1, "difficulty": "normal", "punctuation": false,
         "numbers": false, "lazyMode": false]]
    if fractional {
      object["speedPrecision"] = ["version":1,"wpm":80.49,"rawWpm":95.75]
      object["preciseAccuracy"] = 98.25; object["consistency"] = 80.75
      object["startedAtReferenceTime"] = 100.0; object["finishedAtReferenceTime"] = 115.0
    }
    return try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: object))
  }
  private func replacing(_ row: RemoteAccountResult, field: String, value: Any) throws -> RemoteAccountResult {
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String: Any])
    object[field] = value
    return try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: object))
  }
  private func edit(_ row: RemoteAccountResult, ids: [UUID], awards: [UUID]) throws -> RemoteAccountTagEditResponse {
    var result = row; result.accountTagIDs = ids
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any])
    object["tagPbs"] = awards.map(\.uuidString)
    return try JSONDecoder().decode(RemoteAccountTagEditResponse.self, from: JSONSerialization.data(withJSONObject: object))
  }
  private func directory() throws -> RemoteAccountTagList {
    try JSONDecoder().decode(RemoteAccountTagList.self, from: JSONSerialization.data(withJSONObject:
      ["version": 1, "tags": [a,b].map { ["id": $0.uuidString, "name": "desk",
        "personalBestLedgerVersion": 1, "personalBests": []] }]))
  }
  @MainActor private func setup(ready: Bool, fractional: Bool = false) throws -> (AccountSession, UserDefaults, String, RemoteAccountResult) {
    let suite = "TypebarTests.text-tag-edit.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defaults.set("http://127.0.0.1:1", forKey: "remoteAccount.endpoint.v1")
    let account = AccountSession(defaults: defaults)
    account.currentUser = .init(id: UUID(), email: "owned@example.invalid", displayName: "Owned", totalExperience: 500)
    try account.applyAccountTagDirectory(directory(), read: account.beginAccountTagDirectoryRead())
    let result = try row(ids: [a], fractional: fractional), scope = try XCTUnwrap(account.resultPublicationScope)
    let read = try XCTUnwrap(account.beginLastAccountResultRead(id: result.id, finishedAt: result.finishedAt, scope: scope))
    try account.applyLastAccountResult(result, read: read)
    if ready { try account.applyAccountTagHistory([result], read: account.beginAccountTagHistoryRead()) }
    return (account, defaults, suite, result)
  }
  @MainActor func testReadyHistoryTextEditUpdatesAllMetadataBeforeStableIDEdit() throws {
    let (account, defaults, suite, original) = try setup(ready: true); defer { defaults.removePersistentDomain(forName: suite) }
    let response = try replacing(original, field: "tags", value: ["new"])
    let draft = try account.accountTagResultEditDraft(id: original.id)
    let read = try account.beginResultTextTagEdit(id: original.id)
    try account.applyConfirmedResultTextTagEdit(response, requestedTags: ["new"], read: read)
    account.finishResultTextTagEdit(read)
    XCTAssertEqual(account.remoteResults.first, response); XCTAssertEqual(account.lastAccountResult, response)
    XCTAssertEqual(account.accountTagHistoryCache?.results, [response])
    XCTAssertThrowsError(try account.validateAccountTagResultEditDraft(draft))
    try account.applyAccountTagEditResponse(edit(response, ids: [a,b], awards: [b]), requestedIDs: [a,b],
      scope: XCTUnwrap(account.resultPublicationScope), at: 123, fromResultPage: true)
    XCTAssertEqual(account.lastAccountResult?.tags, ["new"])
  }
  @MainActor func testUnreadyLastResultTextEditDoesNotLoadHistoryAndNextStableEditWorks() throws {
    let (account, defaults, suite, original) = try setup(ready: false); defer { defaults.removePersistentDomain(forName: suite) }
    let response = try replacing(original, field: "tags", value: ["new"])
    let read = try account.beginResultTextTagEdit(id: original.id)
    try account.applyConfirmedResultTextTagEdit(response, requestedTags: ["new"], read: read)
    account.finishResultTextTagEdit(read)
    XCTAssertEqual(account.lastAccountResult, response); XCTAssertNil(account.accountTagHistoryCache)
    XCTAssertTrue(account.remoteResults.isEmpty); XCTAssertFalse(account.isAccountTagHistoryReady)
    try account.applyAccountTagEditResponse(edit(response, ids: [b], awards: [b]), requestedIDs: [b],
      scope: XCTUnwrap(account.resultPublicationScope), at: 123, fromResultPage: true)
    XCTAssertEqual(account.lastAccountResult?.tags, ["new"])
  }
  @MainActor func testTextOnlyCommitKeepsPBsCrownsPostingSelectionXPAndCompletionUnchanged() throws {
    for ready in [false,true] {
      let (account, defaults, suite, original) = try setup(ready: ready); defer { defaults.removePersistentDomain(forName: suite) }
      let scope = try XCTUnwrap(account.resultPublicationScope)
      try account.setAccountTagPostingSelection([a])
      try account.applyAccountTagEditResponse(edit(original, ids: [a,b], awards: [b]), requestedIDs: [a,b],
        scope: scope, at: 123, fromResultPage: true)
      let linked = try XCTUnwrap(account.lastAccountResult), pb = account.accountTagHistoryPersonalBests
      let feedback = account.lastAccountResultEditFeedback, awards = account.lastAccountResultEditAwardIDs
      let before = try account.beginAccountTagHistoryRead()
      let read = try account.beginResultTextTagEdit(id: linked.id)
      try account.applyConfirmedResultTextTagEdit(replacing(linked, field: "tags", value: ["café","中文"]),
        requestedTags: [" café ","中文"], read: read)
      account.finishResultTextTagEdit(read)
      XCTAssertEqual(account.lastAccountResult?.tags, ["café","中文"])
      XCTAssertEqual(account.lastAccountResult?.accountTagIDs, [a,b])
      XCTAssertEqual(account.accountTagHistoryPersonalBests, pb); XCTAssertEqual(account.lastAccountResultEditFeedback, feedback)
      XCTAssertEqual(account.lastAccountResultEditAwardIDs, awards); XCTAssertEqual(try account.accountTagPostingSelection(), [a])
      XCTAssertEqual(account.currentUser?.totalExperience, 500); XCTAssertEqual(original.tags, ["old"])
      XCTAssertEqual(original.accountTagIDs, [a]); XCTAssertEqual(account.isAccountTagHistoryReady, ready)
      XCTAssertThrowsError(try account.applyAccountTagHistory([original], read: before))
    }
  }
  @MainActor func testFractionalMetadataAndCodingKeysStayUnchangedExceptTextTags() throws {
    for ready in [false,true] {
      let (account, defaults, suite, original) = try setup(ready: ready, fractional: true)
      defer { defaults.removePersistentDomain(forName: suite) }
      let originalBytes = try JSONEncoder().encode(original)
      var expected = original; expected.tags = ["new"]
      let read = try account.beginResultTextTagEdit(id: original.id)
      try account.applyConfirmedResultTextTagEdit(expected, requestedTags: ["new"], read: read)
      account.finishResultTextTagEdit(read)
      XCTAssertEqual(account.lastAccountResult, expected)
      XCTAssertEqual(account.lastAccountResult?.effectiveWpm,80.49); XCTAssertEqual(account.lastAccountResult?.effectiveRawWpm,95.75)
      XCTAssertEqual(account.lastAccountResult?.preciseAccuracy,98.25); XCTAssertEqual(account.lastAccountResult?.consistency,80.75)
      let oldObject = try XCTUnwrap(JSONSerialization.jsonObject(with: originalBytes) as? [String: Any])
      let newObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(expected)) as? [String: Any])
      XCTAssertEqual(Set(oldObject.keys),Set(newObject.keys))
      XCTAssertEqual(try JSONDecoder().decode(RemoteAccountResult.self,from: originalBytes),original)
      try account.applyAccountTagEditResponse(edit(expected, ids: [a,b], awards: [b]), requestedIDs: [a,b],
        scope: XCTUnwrap(account.resultPublicationScope), at: 123)
      XCTAssertEqual(account.accountTagHistoryPersonalBests.first { $0.tagID == b }?.wpm,80.49)
      XCTAssertEqual(account.accountTagHistoryPersonalBests.first { $0.tagID == b }?.rawWpm,95.75)
    }
  }
  @MainActor func testIncompleteCacheKeepsPendingAcceptedIDsAndPBOverrides() throws {
    let (account, defaults, suite, original) = try setup(ready: true); defer { defaults.removePersistentDomain(forName: suite) }
    let scope = try XCTUnwrap(account.resultPublicationScope)
    try account.applyAccountTagEditResponse(edit(original, ids: [a,b], awards: [b]), requestedIDs: [a,b], scope: scope, at: 123)
    let linked = try XCTUnwrap(account.lastAccountResult), pending = try row(ids: [a])
    let insertion = try XCTUnwrap(account.beginAcceptedAccountTagHistoryInsertion(id: pending.id, scope: scope))
    let pb = account.accountTagHistoryPersonalBests, read = try account.beginResultTextTagEdit(id: linked.id)
    try account.applyConfirmedResultTextTagEdit(replacing(linked, field: "tags", value: ["new"]), requestedTags: ["new"], read: read)
    account.finishResultTextTagEdit(read)
    XCTAssertFalse(account.isAccountTagHistoryReady); XCTAssertEqual(account.accountTagHistoryCache?.results.first?.tags, ["new"])
    XCTAssertEqual(account.accountTagHistoryPersonalBests, pb)
    XCTAssertThrowsError(try account.applyAcceptedAccountTagHistoryResult(pending, read: insertion))
    try account.applyAccountTagHistory([try XCTUnwrap(account.lastAccountResult),pending], read: account.beginAccountTagHistoryRead())
    XCTAssertTrue(account.isAccountTagHistoryReady)
  }
  @MainActor func testUnknownUnloadedTargetIsNotInsertedOrFabricatedAndOldServiceKeepsNilIDs() throws {
    let (account, defaults, suite, original) = try setup(ready: false); defer { defaults.removePersistentDomain(forName: suite) }
    XCTAssertThrowsError(try account.beginResultTextTagEdit(id: UUID())); XCTAssertFalse(account.isEditingAccountTags)
    account.invalidateAccountTagHistory(); account.invalidateAccountTagDirectory()
    var legacy = original; legacy.accountTagIDs = nil; account.remoteResults = [legacy]
    let response = try replacing(legacy, field: "tags", value: ["new"]), read = try account.beginResultTextTagEdit(id: legacy.id)
    try account.applyConfirmedResultTextTagEdit(response, requestedTags: ["new"], read: read)
    account.finishResultTextTagEdit(read)
    XCTAssertEqual(account.remoteResults, [response]); XCTAssertNil(account.remoteResults.first?.accountTagIDs)
    XCTAssertNil(account.lastAccountResult); XCTAssertNil(account.accountTagHistoryCache)
  }
  @MainActor func testBadSuccessfulResponseCannotPartiallyReplaceAnyMetadata() throws {
    let (account, defaults, suite, original) = try setup(ready: true); defer { defaults.removePersistentDomain(forName: suite) }
    let valid = try replacing(original, field: "tags", value: ["new"])
    for (field,value): (String,Any) in [("id",UUID().uuidString),("wpm",81),("accuracy",97),
      ("accountTagIDs",[b.uuidString]),("tags",["wrong"])] {
      let bad = try replacing(valid, field: field, value: value), read = try account.beginResultTextTagEdit(id: original.id)
      let revision = account.accountTagRevision
      XCTAssertThrowsError(try account.applyConfirmedResultTextTagEdit(bad, requestedTags: ["new"], read: read))
      account.finishResultTextTagEdit(read)
      XCTAssertEqual(account.remoteResults, [original]); XCTAssertEqual(account.lastAccountResult, original)
      XCTAssertEqual(account.accountTagHistoryCache?.results, [original]); XCTAssertEqual(account.accountTagRevision, revision)
      XCTAssertTrue(account.accountTagHistoryPersonalBests.isEmpty)
    }
  }
  @MainActor func testOldNonceDoesNotUnlockNewWriteAndOneConfirmedReadCannotReplay() throws {
    let (account, defaults, suite, original) = try setup(ready: true); defer { defaults.removePersistentDomain(forName: suite) }
    let first = try account.beginResultTextTagEdit(id: original.id)
    XCTAssertThrowsError(try account.beginResultTextTagEdit(id: original.id))
    XCTAssertThrowsError(try account.accountTagResultEditDraft(id: original.id))
    account.finishResultTextTagEdit(first)
    let second = try account.beginResultTextTagEdit(id: original.id)
    account.finishResultTextTagEdit(first); XCTAssertTrue(account.isEditingAccountTags)
    let response = try replacing(original, field: "tags", value: ["new"])
    XCTAssertThrowsError(try account.applyConfirmedResultTextTagEdit(response, requestedTags: ["new"], read: first))
    try account.applyConfirmedResultTextTagEdit(response, requestedTags: ["new"], read: second)
    XCTAssertThrowsError(try account.applyConfirmedResultTextTagEdit(response, requestedTags: ["new"], read: second))
    account.finishResultTextTagEdit(second); XCTAssertFalse(account.isEditingAccountTags)
  }
  @MainActor func testSameAccountRoundTripDirectoryChangeAndNewLastResultRejectOldConfirmation() throws {
    for change in ["account","directory","last"] {
      let (account, defaults, suite, original) = try setup(ready: true); defer { defaults.removePersistentDomain(forName: suite) }
      let read = try account.beginResultTextTagEdit(id: original.id), user = account.currentUser
      var replacementRead: ResultTextTagEditRead?
      if change == "account" {
        account.currentUser = nil; account.currentUser = user
        try account.applyAccountTagDirectory(directory(), read: account.beginAccountTagDirectoryRead())
        let last = try XCTUnwrap(account.beginLastAccountResultRead(id: original.id, finishedAt: original.finishedAt,
          scope: XCTUnwrap(account.resultPublicationScope)))
        try account.applyLastAccountResult(original, read: last)
        try account.applyAccountTagHistory([original], read: account.beginAccountTagHistoryRead())
        XCTAssertEqual(account.resultPublicationScope,read.scope); XCTAssertEqual(account.lastAccountResult,read.previous)
        replacementRead = try account.beginResultTextTagEdit(id: original.id)
      }
      else if change == "directory" {
        try account.applyAccountTagDirectory(directory(), read: account.beginAccountTagDirectoryRead())
      } else {
        _ = try account.beginLastAccountResultRead(id: UUID(), finishedAt: original.finishedAt,
          scope: XCTUnwrap(account.resultPublicationScope))
      }
      let before = account.lastAccountResult, rows = account.remoteResults, revision = account.accountTagRevision
      XCTAssertThrowsError(try account.applyConfirmedResultTextTagEdit(replacing(original, field: "tags", value: ["new"]),
        requestedTags: ["new"], read: read))
      account.finishResultTextTagEdit(read)
      XCTAssertEqual(account.lastAccountResult, before); XCTAssertEqual(account.remoteResults, rows)
      XCTAssertEqual(account.accountTagRevision, revision)
      if let replacementRead {
        XCTAssertTrue(account.isEditingAccountTags)
        try account.applyConfirmedResultTextTagEdit(replacing(original, field: "tags", value: ["fresh"]),
          requestedTags: ["fresh"], read: replacementRead)
        account.finishResultTextTagEdit(replacementRead)
        XCTAssertEqual(account.lastAccountResult?.tags,["fresh"])
      }
    }
  }
  func testInputValidationMatchesTextNamespaceWithoutSilentlyDroppingValues() throws {
    XCTAssertEqual(try RemoteResultTextTagEditPolicy.requestedTags([" café ","中文"]), ["café","中文"])
    XCTAssertEqual(try RemoteResultTextTagEditPolicy.requestedTags([]), [])
    for values in [[""],[" \n"],[String(repeating: "a",count:25)],Array(repeating: "a",count:6),["café","CAFE"]] {
      XCTAssertThrowsError(try RemoteResultTextTagEditPolicy.requestedTags(values))
    }
    let previous = try row(ids: [a,UUID()]), response = try replacing(previous, field: "tags", value: ["new"])
    let normalized = try RemoteResultTextTagEditPolicy.confirmedMetadata(response, previous: previous,
      requestedTags: ["new"], knownIDs: [a])
    XCTAssertEqual(normalized.accountTagIDs, [a])
    XCTAssertEqual(try RemoteResultTextTagEditPolicy.confirmedMetadata(response, previous: previous,
      requestedTags: ["new"], knownIDs: nil), response)
  }
  @MainActor func testOwnedTransportRunsOnceWithEntireCanonicalSelectionAndNoOptimisticMutation() async throws {
    let (account, defaults, suite, original) = try setup(ready: true); defer { defaults.removePersistentDomain(forName: suite) }
    var calls = 0
    try await account.editRemoteResultTextTags(id: original.id, tags: [" new ","中文"], expectedTextTags: ["old"]) { read,tags in
      calls += 1; XCTAssertEqual(read.previous,original); XCTAssertEqual(tags,["new","中文"])
      XCTAssertTrue(account.isEditingAccountTags); XCTAssertEqual(account.lastAccountResult, original)
      XCTAssertThrowsError(try account.beginAccountTagHistoryRead())
      return try self.replacing(original, field: "tags", value: tags)
    }
    XCTAssertEqual(calls, 1); XCTAssertEqual(account.lastAccountResult?.tags, ["new","中文"])
    XCTAssertFalse(account.isEditingAccountTags)
  }
  @MainActor func testOwnedTransportRejectedOrPreflightFailureKeepsDataAndReleasesLock() async throws {
    let (account, defaults, suite, original) = try setup(ready: true); defer { defaults.removePersistentDomain(forName: suite) }
    var calls = 0
    for (tags,expected): ([String],[String]) in [([""],["old"]),(["new"],["stale"])] {
      do { try await account.editRemoteResultTextTags(id: original.id, tags: tags, expectedTextTags: expected) { _,_ in
        calls += 1; return original
      }; XCTFail("Invalid preflight accepted") } catch {}
    }
    XCTAssertEqual(calls,0)
    do { try await account.editRemoteResultTextTags(id: original.id, tags: ["new"]) { _,_ in
      calls += 1; throw RemoteAccountError.serverMessage("owned rejection")
    }; XCTFail("Rejection ignored") } catch { XCTAssertEqual(error.localizedDescription, "owned rejection") }
    XCTAssertEqual(calls,1); XCTAssertEqual(account.lastAccountResult,original); XCTAssertEqual(account.remoteResults,[original])
    XCTAssertFalse(account.isEditingAccountTags)
  }
  @MainActor func testOwnedTransportConfirmedButStaleResponseIsExplicitAndDoesNotUndoNewSelection() async throws {
    let (account, defaults, suite, original) = try setup(ready: false); defer { defaults.removePersistentDomain(forName: suite) }
    do { try await account.editRemoteResultTextTags(id: original.id, tags: ["new"]) { _,tags in
      try account.setAccountTagPostingSelection([b])
      return try self.replacing(original, field: "tags", value: tags)
    }; XCTFail("Stale confirmation accepted") }
    catch { XCTAssertTrue(error.localizedDescription.contains("服务端已保存文字标签")) }
    XCTAssertEqual(try account.accountTagPostingSelection(), [b]); XCTAssertEqual(account.lastAccountResult, original)
    XCTAssertFalse(account.isEditingAccountTags)
  }
  @MainActor func testCancellationBeforeAndAfterOwnedTransportNeverPartiallyCommits() async throws {
    let (account, defaults, suite, original) = try setup(ready: true); defer { defaults.removePersistentDomain(forName: suite) }
    for afterRequest in [false,true] {
      let child = Task { @MainActor in
        var calls = 0
        if !afterRequest { withUnsafeCurrentTask { $0?.cancel() } }
        do { try await account.editRemoteResultTextTags(id: original.id, tags: ["new"]) { _,tags in
          calls += 1; withUnsafeCurrentTask { $0?.cancel() }
          return try self.replacing(original, field: "tags", value: tags)
        }; XCTFail("Cancelled edit committed") }
        catch { XCTAssertEqual(error.localizedDescription.contains("服务端已保存文字标签"), afterRequest) }
        XCTAssertEqual(calls,afterRequest ? 1 : 0)
      }
      await child.value
      XCTAssertEqual(account.lastAccountResult,original); XCTAssertEqual(account.remoteResults,[original])
      XCTAssertFalse(account.isEditingAccountTags)
    }
  }
}
