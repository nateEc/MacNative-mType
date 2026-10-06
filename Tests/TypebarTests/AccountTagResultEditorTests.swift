import Foundation
import XCTest
@testable import Typebar

final class AccountTagResultEditorTests: XCTestCase {
  private let a = UUID(), b = UUID(), c = UUID()
  private func row(ids: [UUID]) throws -> RemoteAccountResult {
    try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject:
      ["id": UUID().uuidString, "mode": "time", "mode2": "15", "language": "english",
       "durationSeconds": 15, "wpm": 80, "rawWpm": 96, "accuracy": 98, "consistency": 80,
       "errorCount": 1, "eventCount": 75, "tags": ["local"], "accountTagIDs": ids.map(\.uuidString),
       "startedAt": 100, "finishedAt": 115,
       "personalBestConfiguration": ["version": 1, "difficulty": "normal", "punctuation": false,
         "numbers": false, "lazyMode": false]]))
  }
  @MainActor private func session() throws -> (AccountSession, UserDefaults, String, RemoteAccountResult) {
    let suite = "TypebarTests.result-editor.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defaults.set("http://127.0.0.1:1", forKey: "remoteAccount.endpoint.v1")
    let account = AccountSession(defaults: defaults)
    account.currentUser = .init(id: UUID(), email: "owned@example.invalid", displayName: "Owned", totalExperience: 500)
    let directory = try JSONDecoder().decode(RemoteAccountTagList.self, from: JSONSerialization.data(withJSONObject:
      ["version": 1, "tags": [a,b,c].map { ["id": $0.uuidString, "name": "desk",
        "personalBestLedgerVersion": 1, "personalBests": []] }]))
    try account.applyAccountTagDirectory(directory, read: account.beginAccountTagDirectoryRead())
    let result = try row(ids: [a,b]), scope = try XCTUnwrap(account.resultPublicationScope)
    let read = try XCTUnwrap(account.beginLastAccountResultRead(id: result.id, finishedAt: result.finishedAt, scope: scope))
    try account.applyLastAccountResult(result, read: read)
    return (account, defaults, suite, result)
  }
  @MainActor func testUnchangedSaveNeedsNoCredentialsCapabilityOrRequest() async throws {
    let (account, defaults, suite, result) = try session(); defer { defaults.removePersistentDomain(forName: suite) }
    var draft = try account.accountTagResultEditDraft(id: result.id)
    draft.set(a, enabled: false); draft.set(a, enabled: true)
    XCTAssertEqual(draft.selectedIDs, [b,a]); XCTAssertFalse(draft.isChanged)
    let revision = account.accountTagRevision
    let disposition = try await account.saveAccountTagResultEdit(draft)
    XCTAssertEqual(disposition, .unchanged)
    XCTAssertEqual(account.accountTagRevision, revision); XCTAssertFalse(account.isEditingAccountTags)
    XCTAssertEqual(account.lastAccountResult, result); XCTAssertNil(account.accountTagHistoryCache)
  }
  func testRetainedCrownsAndDisplayOrderDoNotBecomeLatestAwards() {
    var feedback = AccountTagResultEditFeedback(ids: [a,b], crownedIDs: [a])
    feedback.apply(ids: [b,c,a], awards: [b,c])
    XCTAssertEqual(feedback.displayedIDs, [a,b,c]); XCTAssertEqual(feedback.crownedIDs, [a,c])
    feedback.apply(ids: [b,c], awards: []); XCTAssertEqual(feedback.crownedIDs, [c])
    feedback.apply(ids: [a,b,c], awards: []); XCTAssertEqual(feedback.displayedIDs, [b,c,a])
    XCTAssertEqual(feedback.crownedIDs, [c])
    feedback.apply(ids: [], awards: []); XCTAssertTrue(feedback.displayedIDs.isEmpty); XCTAssertTrue(feedback.crownedIDs.isEmpty)
  }
  @MainActor func testTogglesOnlyDraftAndCancelDiscardsWithoutMutatingCompletionSelectionOrXP() throws {
    let (account, defaults, suite, result) = try session(); defer { defaults.removePersistentDomain(forName: suite) }
    try account.setAccountTagPostingSelection([b])
    var draft = try account.accountTagResultEditDraft(id: result.id)
    draft.set(a, enabled: false); draft.set(c, enabled: true); draft.set(c, enabled: true); draft.set(UUID(), enabled: true)
    XCTAssertEqual(draft.selectedIDs, [b,c]); XCTAssertTrue(draft.isChanged)
    XCTAssertEqual(account.lastAccountResult, result); XCTAssertEqual(result.accountTagIDs, [a,b])
    XCTAssertEqual(try account.accountTagPostingSelection(), [b]); XCTAssertEqual(account.currentUser?.totalExperience, 500)
    XCTAssertFalse(account.isEditingAccountTags); XCTAssertTrue(account.accountTagHistoryPersonalBests.isEmpty)
    let reopened = try account.accountTagResultEditDraft(id: result.id)
    XCTAssertEqual(reopened.selectedIDs, [a,b]); XCTAssertFalse(reopened.isChanged)
    XCTAssertEqual(account.accountTags.filter { $0.name == "desk" }.count, 3)
  }
  @MainActor func testDirectorySelectionAndAssociationChangesInvalidateOldDrafts() throws {
    let (account, defaults, suite, result) = try session(); defer { defaults.removePersistentDomain(forName: suite) }
    let scope = try XCTUnwrap(account.resultPublicationScope)
    let initial = try account.accountTagResultEditDraft(id: result.id)
    try account.setAccountTagPostingSelection([c])
    XCTAssertThrowsError(try account.validateAccountTagResultEditDraft(initial))
    let next = try account.accountTagResultEditDraft(id: result.id)
    try account.applyConfirmedAccountTagDeletion(id: b, personalBestsOnly: false, scope: scope)
    XCTAssertThrowsError(try account.validateAccountTagResultEditDraft(next))
    let newer = try account.accountTagResultEditDraft(id: result.id)
    try account.applyAccountTagEditResponse(edit(try XCTUnwrap(account.lastAccountResult), ids: [c], awards: []),
      requestedIDs: [c], scope: scope, at: 123)
    XCTAssertThrowsError(try account.validateAccountTagResultEditDraft(newer))
    let latest = try account.accountTagResultEditDraft(id: result.id)
    let directory = try JSONDecoder().decode(RemoteAccountTagList.self, from: JSONSerialization.data(withJSONObject:
      ["version": 1, "tags": [a,b,c].map { ["id": $0.uuidString, "name": "renamed",
        "personalBestLedgerVersion": 1, "personalBests": []] }]))
    try account.applyAccountTagDirectory(directory, read: account.beginAccountTagDirectoryRead())
    XCTAssertThrowsError(try account.validateAccountTagResultEditDraft(latest))
  }
  @MainActor func testSameAccountRoundTripCannotReviveDraftEvenAfterSameResultReload() throws {
    let (account, defaults, suite, result) = try session(); defer { defaults.removePersistentDomain(forName: suite) }
    let draft = try account.accountTagResultEditDraft(id: result.id), user = account.currentUser
    let directory = try JSONDecoder().decode(RemoteAccountTagList.self, from: JSONSerialization.data(withJSONObject:
      ["version": 1, "tags": [a,b,c].map { ["id": $0.uuidString, "name": "desk",
        "personalBestLedgerVersion": 1, "personalBests": []] }]))
    account.currentUser = nil; account.currentUser = user
    try account.applyAccountTagDirectory(directory, read: account.beginAccountTagDirectoryRead())
    let scope = try XCTUnwrap(account.resultPublicationScope)
    let read = try XCTUnwrap(account.beginLastAccountResultRead(id: result.id, finishedAt: result.finishedAt, scope: scope))
    try account.applyLastAccountResult(result, read: read)
    XCTAssertEqual(account.lastAccountResult, result); XCTAssertEqual(account.resultPublicationScope, draft.scope)
    XCTAssertThrowsError(try account.validateAccountTagResultEditDraft(draft))
  }
  private func edit(_ result: RemoteAccountResult, ids: [UUID], awards: [UUID]) throws -> RemoteAccountTagEditResponse {
    var value = result; value.accountTagIDs = ids
    var root = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    root["tagPbs"] = awards.map(\.uuidString)
    return try JSONDecoder().decode(RemoteAccountTagEditResponse.self, from: JSONSerialization.data(withJSONObject: root))
  }
  @MainActor func testOnlyResultPageEditsMutateDisplayFeedbackAndLatestAwardsStaySeparate() throws {
    let (account, defaults, suite, result) = try session(); defer { defaults.removePersistentDomain(forName: suite) }
    let scope = try XCTUnwrap(account.resultPublicationScope)
    XCTAssertEqual(account.lastAccountResultEditFeedback?.displayedIDs, [a,b])
    try account.applyAccountTagEditResponse(edit(result, ids: [b,c,a], awards: [b,c]), requestedIDs: [b,c,a],
      scope: scope, at: 123, fromResultPage: true)
    XCTAssertEqual(account.lastAccountResultEditFeedback?.displayedIDs, [a,b,c])
    XCTAssertEqual(account.lastAccountResultEditFeedback?.crownedIDs, [c])
    try account.applyAccountTagEditResponse(edit(try XCTUnwrap(account.lastAccountResult), ids: [c,b], awards: []),
      requestedIDs: [c,b], scope: scope, at: 124, fromResultPage: true)
    XCTAssertEqual(account.lastAccountResultEditFeedback?.displayedIDs, [b,c])
    XCTAssertEqual(account.lastAccountResultEditFeedback?.crownedIDs, [c]); XCTAssertEqual(account.lastAccountResultEditAwardIDs, [])
    let before = account.lastAccountResultEditFeedback
    try account.applyAccountTagEditResponse(edit(try XCTUnwrap(account.lastAccountResult), ids: [a], awards: [a]),
      requestedIDs: [a], scope: scope, at: 125)
    XCTAssertEqual(account.lastAccountResultEditFeedback, before, "History edits do not run the result-page callback")
    try account.applyConfirmedAccountTagDeletion(id: c, personalBestsOnly: false, scope: scope)
    XCTAssertEqual(account.lastAccountResultEditFeedback?.displayedIDs, [b])
    XCTAssertEqual(account.lastAccountResultEditFeedback?.crownedIDs, [])
    account.invalidateAccountTagHistory(); XCTAssertNil(account.lastAccountResultEditFeedback)
  }
  @MainActor func testStaleSaveAndRevisionPreflightRejectBeforeCredentialsOrWrites() async throws {
    let (account, defaults, suite, result) = try session(); defer { defaults.removePersistentDomain(forName: suite) }
    var draft = try account.accountTagResultEditDraft(id: result.id); draft.set(c, enabled: true)
    try account.setAccountTagPostingSelection([c])
    do { _ = try await account.saveAccountTagResultEdit(draft); XCTFail("Stale draft accepted") }
    catch { XCTAssertEqual(error.localizedDescription, RemoteAccountError.accountScopeChanged.localizedDescription) }
    do { try await account.updateRemoteAccountResultTagIDs(id: result.id, tagIDs: [c], expectedRevision: draft.revision)
      XCTFail("Stale revision accepted") }
    catch { XCTAssertEqual(error.localizedDescription, RemoteAccountError.accountScopeChanged.localizedDescription) }
    XCTAssertEqual(account.lastAccountResult, result); XCTAssertFalse(account.isEditingAccountTags)
  }
  func testKnownFilteringAndDirectoryRetention() throws {
    let scope = ResultPublicationScope(endpoint: "https://owned.invalid", userID: UUID())
    let draft = AccountTagResultEditDraft(scope: scope, revision: 0, result: try row(ids: [a,b]), knownIDs: [a,c])
    XCTAssertEqual(draft.selectedIDs, [a]); XCTAssertTrue(draft.isChanged)
    var feedback = AccountTagResultEditFeedback(ids: [a,b,c], crownedIDs: [a,c])
    feedback.retain(knownIDs: [b,c]); XCTAssertEqual(feedback.displayedIDs, [b,c]); XCTAssertEqual(feedback.crownedIDs, [c])
  }
  func testAgainstPinnedCompleteCallbacksAndDisplayUpdater() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else { throw XCTSkip("Pinned reference required") }
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Scripts/check-source-account-tag-result-editor.mjs")
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env"); process.arguments = ["node",script.path,reference,"--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors; try process.run()
    let bytes = output.fileHandleForReading.readDataToEndOfFile(), diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0, String(decoding: diagnostics, as: UTF8.self))
    struct Draft: Decodable { let originalIDs: [UUID]; let selectedIDs: [UUID]; let changed: Bool }
    struct Feedback: Decodable {
      let initialIDs: [UUID]; let initialCrowns: [UUID]; let nextIDs: [UUID]; let awards: [UUID]
      let displayedIDs: [UUID]; let crownedIDs: [UUID]
    }
    struct Document: Decodable { let referenceCommit: String; let drafts: [Draft]; let feedback: [Feedback] }
    let document = try JSONDecoder().decode(Document.self, from: bytes)
    XCTAssertEqual(document.referenceCommit, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(document.drafts.count, 128); XCTAssertEqual(document.feedback.count, 1458)
    let ids = try ["11111111-1111-4111-8111-111111111111","22222222-2222-4222-8222-222222222222",
      "33333333-3333-4333-8333-333333333333"].map { try XCTUnwrap(UUID(uuidString: $0)) }
    for fixture in document.drafts {
      var draft = AccountTagResultEditDraft(scope: .init(endpoint: "https://owned.invalid", userID: UUID()),
        revision: 1, result: try row(ids: fixture.originalIDs), knownIDs: Set(ids))
      for id in ids where draft.selectedIDs.contains(id) != fixture.selectedIDs.contains(id) {
        draft.set(id, enabled: fixture.selectedIDs.contains(id))
      }
      XCTAssertEqual(draft.selectedIDs, fixture.selectedIDs); XCTAssertEqual(draft.isChanged, fixture.changed)
    }
    for fixture in document.feedback {
      var feedback = AccountTagResultEditFeedback(ids: fixture.initialIDs, crownedIDs: Set(fixture.initialCrowns))
      feedback.apply(ids: fixture.nextIDs, awards: fixture.awards)
      XCTAssertEqual(feedback.displayedIDs, fixture.displayedIDs); XCTAssertEqual(feedback.crownedIDs, Set(fixture.crownedIDs))
    }
  }
}
