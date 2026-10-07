import Foundation
import XCTest
@testable import Typebar

final class AccountHistoryResultInformationTests: XCTestCase {
  private let first = UUID(), second = UUID()

  private func payload() -> [String: Any] {
    ["id": UUID().uuidString, "mode": "time", "mode2": "15", "durationSeconds": 15,
      "language": "english", "wpm": 60, "rawWpm": 60, "accuracy": 100, "consistency": 80,
      "errorCount": 9, "eventCount": 75, "tags": ["independent text"], "startedAt": 100, "finishedAt": 115,
      "restartCount": 0, "blindMode": true, "accountTagIDs": [first.uuidString],
      "personalBestConfiguration": ["version": 1, "difficulty": "expert", "punctuation": true,
        "numbers": false, "lazyMode": true],
      "practiceTiming": ["version": 1, "terminalEngagedMilliseconds": 15_000, "priorAttemptEngagedMilliseconds": 0],
      "experienceEvidence": ["version": 1, "characterCounts": [60, 3, 4, 8], "scoringUnitBasis": "utf16",
        "durationSeconds": 15.0, "afkSeconds": 0.0, "punctuation": true, "numbers": false,
        "modifiers": ["mirrorVisual"]]]
  }
  private func decode(_ object: [String: Any]) throws -> RemoteAccountResult {
    try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: object))
  }
  func testFullRecordedInformationUsesFourCountersRatherThanVisibleErrorsOrAttempts() throws {
    let row = try decode(payload()), before = try JSONEncoder().encode(row)
    let info = AccountHistoryResultInformation(row)
    XCTAssertEqual(info.characterCounts, "60/3/4/8")
    XCTAssertEqual(info.characterCountsDescription, "正确词信用 60，错误 3，额外 4，遗漏 8")
    XCTAssertEqual(info.scoringUnitBasis, "UTF-16 单位"); XCTAssertEqual(info.difficulty, Difficulty.expert.displayName)
    XCTAssertEqual(info.punctuation, "开启"); XCTAssertEqual(info.numbers, "关闭")
    XCTAssertEqual(info.blindMode, "开启"); XCTAssertEqual(info.lazyMode, "开启")
    XCTAssertEqual(info.modifiers, TestModifier.mirrorVisual.displayName)
    XCTAssertEqual(try JSONDecoder().decode(RemoteAccountResult.self, from: before), row)
  }
  func testLegacyUnknownDoesNotBecomeZeroNormalFalseOrNoModifiers() throws {
    var object = payload()
    for key in ["personalBestConfiguration", "experienceEvidence", "blindMode"] { object.removeValue(forKey: key) }
    let info = AccountHistoryResultInformation(try decode(object))
    for value in [info.characterCounts, info.scoringUnitBasis, info.difficulty, info.punctuation,
      info.numbers, info.blindMode, info.lazyMode, info.modifiers] { XCTAssertEqual(value, "未知") }
    XCTAssertEqual(info.characterCountsDescription, "字符计数未知")
  }
  func testKnownZeroFalseEmptyAndKoreanUnitsRemainDistinctFromUnknown() throws {
    var object = payload(), evidence = try XCTUnwrap(object["experienceEvidence"] as? [String: Any])
    evidence["characterCounts"] = [0, 0, 0, 0]; evidence["scoringUnitBasis"] = "koreanJamo"; evidence["modifiers"] = []
    object["experienceEvidence"] = evidence; object["blindMode"] = false
    let info = AccountHistoryResultInformation(try decode(object))
    XCTAssertEqual(info.characterCounts, "0/0/0/0"); XCTAssertEqual(info.scoringUnitBasis, "韩语拆音单位")
    XCTAssertEqual(info.blindMode, "关闭"); XCTAssertEqual(info.modifiers, "无修饰器")
  }
  func testPartialSavedControlsDoNotInventDifficultyOrLazyMode() throws {
    var object = payload(); object.removeValue(forKey: "personalBestConfiguration")
    let info = AccountHistoryResultInformation(try decode(object))
    XCTAssertEqual(info.punctuation, "开启"); XCTAssertEqual(info.numbers, "关闭")
    XCTAssertEqual(info.difficulty, "未知"); XCTAssertEqual(info.lazyMode, "未知")
    object.removeValue(forKey: "experienceEvidence")
    object["language"] = "mixedLanguages"
    object["rankingEvidence"] = ["version": 1, "stopOnLetter": false, "modifiers": ["polyglot", "symbolStream"]]
    let rankingOnly = AccountHistoryResultInformation(try decode(object))
    XCTAssertEqual(rankingOnly.modifiers, "Polyglot 多语混排、\(TestModifier.symbolStream.displayName)")
    XCTAssertEqual(rankingOnly.characterCounts, "未知"); XCTAssertEqual(rankingOnly.punctuation, "未知")
  }
  func testEveryDifficultyAndIndependentFalseControlsUseSavedValues() throws {
    for difficulty in Difficulty.allCases {
      var object = payload()
      object.removeValue(forKey: "experienceEvidence")
      object["personalBestConfiguration"] = ["version": 1, "difficulty": difficulty.rawValue,
        "punctuation": false, "numbers": true, "lazyMode": false]
      let info = AccountHistoryResultInformation(try decode(object))
      XCTAssertEqual(info.difficulty, difficulty.displayName)
      XCTAssertEqual(info.punctuation, "关闭"); XCTAssertEqual(info.numbers, "开启")
      XCTAssertEqual(info.lazyMode, "关闭"); XCTAssertEqual(info.blindMode, "开启")
      XCTAssertEqual(info.modifiers, "未知")
    }
  }
  func testUnknownTagAssociationPresentationIsNotEmptySelection() {
    let unknown = AccountTagAssociationPresentation(ids: nil, knownIDs: [first, second])
    XCTAssertEqual(unknown.summary, "关联未知"); XCTAssertEqual(unknown.emptyMessage, "账户标签关联未知")
    XCTAssertEqual(unknown.displayedIDs, [])
    let empty = AccountTagAssociationPresentation(ids: [], knownIDs: [first, second])
    XCTAssertEqual(empty.summary, "0 个"); XCTAssertEqual(empty.emptyMessage, "无账户标签")
    let known = AccountTagAssociationPresentation(ids: [second, first], knownIDs: [first, second])
    XCTAssertEqual(known.summary, "2 个"); XCTAssertNil(known.emptyMessage)
    XCTAssertEqual(known.displayedIDs, [second, first])
  }

  @MainActor private func session(rows: [RemoteAccountResult]) throws -> (AccountSession, UserDefaults, String) {
    let suite = "TypebarTests.history-information.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defaults.set("http://127.0.0.1:1", forKey: "remoteAccount.endpoint.v1")
    let account = AccountSession(defaults: defaults)
    account.currentUser = .init(id: UUID(), email: "owned@example.invalid", displayName: "Owned", totalExperience: 500)
    let directory = try JSONDecoder().decode(RemoteAccountTagList.self, from: JSONSerialization.data(withJSONObject:
      ["version": 1, "tags": [first, second].map { ["id": $0.uuidString, "name": "desk",
        "personalBestLedgerVersion": 1, "personalBests": []] }]))
    try account.applyAccountTagDirectory(directory, read: account.beginAccountTagDirectoryRead())
    try account.applyAccountTagHistory(rows, read: account.beginAccountTagHistoryRead())
    return (account, defaults, suite)
  }
  @MainActor func testHistoryRowBeyondRecentTwentyCanDraftAndApplyConfirmedEditWithoutResultPageFeedback() async throws {
    let rows = try (0..<25).map { index in
      var object = payload(); let start = 100 + (25 - index) * 20
      object["startedAt"] = start; object["finishedAt"] = start + 15
      return try decode(object)
    }
    let (account, defaults, suite) = try session(rows: rows); defer { defaults.removePersistentDomain(forName: suite) }
    let row = rows[24], scope = try XCTUnwrap(account.resultPublicationScope)
    XCTAssertFalse(account.remoteResults.contains { $0.id == row.id })
    let lastResult = account.lastAccountResult, feedback = account.lastAccountResultEditFeedback
    XCTAssertEqual(lastResult?.id, rows[0].id); XCTAssertNotEqual(lastResult?.id, row.id)
    let original = try XCTUnwrap(account.editableAccountTagResult(id: row.id))
    var draft = try account.accountTagResultEditDraft(id: row.id)
    draft.set(first, enabled: false); draft.set(second, enabled: true)
    XCTAssertEqual(account.editableAccountTagResult(id: row.id), original)
    try account.validateAccountTagResultEditDraft(draft)
    var edited = original; edited.accountTagIDs = draft.selectedIDs
    var wire = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(edited)) as? [String: Any])
    wire["tagPbs"] = [second.uuidString]
    let response = try JSONDecoder().decode(RemoteAccountTagEditResponse.self, from: JSONSerialization.data(withJSONObject: wire))
    try account.applyAccountTagEditResponse(response, requestedIDs: draft.selectedIDs, scope: scope, at: 123)
    let updated = try XCTUnwrap(account.editableAccountTagResult(id: row.id))
    XCTAssertEqual(updated.accountTagIDs, [second]); XCTAssertEqual(updated.tags, original.tags)
    XCTAssertEqual(AccountHistoryResultInformation(updated), AccountHistoryResultInformation(original))
    XCTAssertEqual(account.lastAccountResult, lastResult); XCTAssertEqual(account.lastAccountResultEditFeedback, feedback)
    XCTAssertEqual(account.currentUser?.totalExperience, 500)
    XCTAssertThrowsError(try account.validateAccountTagResultEditDraft(draft))
    let unchanged = try account.accountTagResultEditDraft(id: row.id)
    let disposition = try await account.saveAccountTagResultEdit(unchanged)
    XCTAssertEqual(disposition, .unchanged, "An unchanged history edit needs no credentials or request")
    let filter = ResultHistoryFilter(accountTagFilter: .init(scope: scope, knownIDs: [first, second],
      selectedIDs: [second], includesNoTags: false))
    XCTAssertEqual(AccountHistoryQuery.matching(account.accountHistoryLoadedResults, scope: scope, filter: filter).map(\.id), [row.id])
  }
  @MainActor func testHistoryDraftCannotSurviveSameAccountRoundTrip() throws {
    let row = try decode(payload()), (account, defaults, suite) = try session(rows: [row])
    defer { defaults.removePersistentDomain(forName: suite) }
    let draft = try account.accountTagResultEditDraft(id: row.id), user = account.currentUser
    account.currentUser = nil; account.currentUser = user
    XCTAssertThrowsError(try account.validateAccountTagResultEditDraft(draft))
    XCTAssertNil(account.editableAccountTagResult(id: row.id))
  }
  @MainActor func testUnknownHistoryAssociationRequiresExplicitChangeBeforeConfirmation() async throws {
    var object = payload(); object.removeValue(forKey: "accountTagIDs")
    let row = try decode(object), (account, defaults, suite) = try session(rows: [row])
    defer { defaults.removePersistentDomain(forName: suite) }
    var draft = try account.accountTagResultEditDraft(id: row.id)
    XCTAssertEqual(draft.selectedIDs, []); XCTAssertFalse(draft.isChanged)
    let disposition = try await account.saveAccountTagResultEdit(draft)
    XCTAssertEqual(disposition, .unchanged)
    XCTAssertNil(account.editableAccountTagResult(id: row.id)?.accountTagIDs, "Do not backfill an empty association")
    draft.set(second, enabled: true)
    XCTAssertTrue(draft.isChanged); try account.validateAccountTagResultEditDraft(draft)
    XCTAssertNil(account.editableAccountTagResult(id: row.id)?.accountTagIDs)
    var edited = row; edited.accountTagIDs = draft.selectedIDs
    var wire = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(edited)) as? [String: Any])
    wire["tagPbs"] = [] as [String]
    let response = try JSONDecoder().decode(RemoteAccountTagEditResponse.self, from: JSONSerialization.data(withJSONObject: wire))
    try account.applyAccountTagEditResponse(response, requestedIDs: draft.selectedIDs, scope: draft.scope, at: 123)
    let confirmed = try XCTUnwrap(account.editableAccountTagResult(id: row.id))
    XCTAssertEqual(confirmed.accountTagIDs, [second]); XCTAssertEqual(confirmed.tags, row.tags)
    XCTAssertEqual(AccountHistoryResultInformation(confirmed), AccountHistoryResultInformation(row))
    XCTAssertEqual(account.currentUser?.totalExperience, 500)
    let presentation = AccountTagAssociationPresentation(ids: confirmed.accountTagIDs, knownIDs: [first, second])
    XCTAssertEqual(presentation.summary, "1 个"); XCTAssertEqual(presentation.displayedIDs, [second])
  }

  func testCharacterInformationAgainstCompletePinnedTableCallbackAndCSVControls() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Readiness supplies the pinned reference")
    }
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Scripts/check-source-account-history-stats.mjs")
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = .init(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", script.path, reference, "--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors; try process.run()
    let bytes = output.fileHandleForReading.readDataToEndOfFile(), diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0, String(decoding: diagnostics, as: UTF8.self))
    struct Fixture: Decodable {
      let wire: RemoteAccountResult; let columns: [String]; let cells: [String]; let tableCharacters: String
    }
    struct Document: Decodable { let referenceCommit: String; let csvFixtures: [Fixture] }
    let document = try JSONDecoder().decode(Document.self, from: bytes)
    XCTAssertEqual(document.referenceCommit, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(document.csvFixtures.count, 20)
    for fixture in document.csvFixtures {
      let info = AccountHistoryResultInformation(fixture.wire)
      let source = Dictionary(uniqueKeysWithValues: zip(fixture.columns, fixture.cells))
      XCTAssertEqual(info.characterCounts, fixture.tableCharacters)
      XCTAssertEqual(info.characterCounts, try XCTUnwrap(source["charStats"]).replacingOccurrences(of: ";", with: "/"))
      XCTAssertEqual(info.difficulty, try XCTUnwrap(Difficulty(rawValue: XCTUnwrap(source["difficulty"]))).displayName)
      for (key, value) in [("punctuation", info.punctuation), ("numbers", info.numbers),
        ("blindMode", info.blindMode), ("lazyMode", info.lazyMode)] {
        XCTAssertEqual(value, source[key] == "true" ? "开启" : "关闭", key)
      }
      let modifier = source["funbox"] == "memory" ? TestModifier.memory : .mirrorVisual
      XCTAssertEqual(info.modifiers, modifier.displayName)
      XCTAssertEqual(info.scoringUnitBasis, fixture.wire.experienceEvidence?.scoringUnitBasis == .utf16
        ? "UTF-16 单位" : "韩语拆音单位")
    }
  }
}
