import Foundation
import XCTest
@testable import Typebar

final class AccountTagCompletionTests: XCTestCase {
  private let a = UUID(), b = UUID()
  @MainActor private func account() throws -> (AccountSession, UserDefaults, String) {
    let suite = "TypebarTests.tag-completion.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let account = AccountSession(defaults: defaults)
    account.currentUser = .init(id: UUID(), email: "owned@example.invalid", displayName: "Owned", totalExperience: 500)
    try account.applyAccountTagDirectory(directory(), read: account.beginAccountTagDirectoryRead())
    try account.setAccountTagPostingSelection([a,b])
    return (account,defaults,suite)
  }
  private func directory(speed: Double? = nil) throws -> RemoteAccountTagList {
    let best: [[String: Any]] = speed.map { [["id": UUID().uuidString, "mode": "time", "mode2": "15",
      "language": "english", "durationSeconds": 15, "wpm": Int($0.rounded()), "preciseWpm": $0,
      "rawWpm": 200, "preciseRawWpm": 200.0, "accuracy": 100, "preciseAccuracy": 99.5,
      "consistency": 75.0, "finishedAt": 100, "acceptedAtMilliseconds": 123,
      "personalBestOrigin": "accepted", "personalBestConfiguration": ["version": 1, "difficulty": "normal",
        "punctuation": false, "numbers": false, "lazyMode": false]]] } ?? []
    return try JSONDecoder().decode(RemoteAccountTagList.self, from: JSONSerialization.data(withJSONObject:
      ["version": 1, "tags": [a,b].map { ["id": $0.uuidString, "name": "desk",
        "personalBestLedgerVersion": 1, "personalBests": best] }]))
  }
  private func result(scope: ResultPublicationScope, speed: Double = 80.49,
    ids: [UUID]? = nil, configuration: TestConfiguration = .init(mode: .time, duration: 15, wordLimit: nil, difficulty: .normal, rules: .init()),
    outcome: TestOutcome = .completed, accuracy: Double = 98.25) -> CompletedTestResult {
    .init(id: UUID(), configuration: configuration, outcome: outcome,
      startedAt: .init(timeIntervalSince1970: 100), finishedAt: .init(timeIntervalSince1970: 115),
      typedCharacterCount: 100, correctCharacterCount: 98, errorCount: 2, wpm: Int(speed.rounded()),
      rawWpm: 96, accuracy: Int(accuracy.rounded()), preciseWpm: speed, preciseRawWpm: 95.75,
      preciseAccuracy: accuracy, tags: ["desk"], accountTagSnapshot: .init(scope: scope, tagIDs: ids ?? [a,b]))
  }
  @MainActor func testCompletionAwardsBeforeAnyAcceptedReadOrHistoryAndDoesNotMutateReceiptSelectionOrXP() throws {
    let (account,defaults,suite) = try account(); defer { defaults.removePersistentDomain(forName: suite) }
    let result = result(scope: try XCTUnwrap(account.resultPublicationScope)), before = result
    let feedback = account.recordAccountTagCompletion(result, eligibility: .eligible, at: 1_800_000_000_875)
    XCTAssertEqual(feedback?.editFeedback.crownedIDs, [a,b])
    XCTAssertEqual(account.accountTagHistoryPersonalBests.map(\.wpm), [80.49,80.49])
    XCTAssertNil(account.lastAccountResult); XCTAssertNil(account.accountTagHistoryCache)
    XCTAssertEqual(try account.accountTagPostingSelection(), [a,b]); XCTAssertEqual(account.currentUser?.totalExperience,500)
    XCTAssertEqual(result,before); XCTAssertTrue(account.accountTags.allSatisfy { $0.personalBests.isEmpty })
  }
  @MainActor func testEqualSpeedDoesNotReplaceCompleteSnapshotOrRepeatInitialCrowns() throws {
    let (account,defaults,suite) = try account(); defer { defaults.removePersistentDomain(forName: suite) }
    let first = result(scope: try XCTUnwrap(account.resultPublicationScope))
    _ = account.recordAccountTagCompletion(first, eligibility: .eligible, at: 123)
    let before = account.accountTagHistoryPersonalBests
    let equal = result(scope: try XCTUnwrap(account.resultPublicationScope))
    let feedback = account.recordAccountTagCompletion(equal, eligibility: .eligible, at: 124)
    XCTAssertEqual(feedback?.rows.map(\.previousBestWpm), [80.49,80.49])
    XCTAssertEqual(feedback?.rows.map(\.showsPreviousBestLine), [true,true])
    XCTAssertEqual(feedback?.editFeedback.crownedIDs, [])
    XCTAssertEqual(account.accountTagHistoryPersonalBests,before)
  }
  @MainActor func testKnownServiceBaselineIsUsedOnlyWithoutClientOverride() throws {
    let (account,defaults,suite) = try account(); defer { defaults.removePersistentDomain(forName: suite) }
    try account.applyAccountTagDirectory(directory(speed: 120.49), read: account.beginAccountTagDirectoryRead())
    let current = result(scope: try XCTUnwrap(account.resultPublicationScope))
    let feedback = try XCTUnwrap(account.recordAccountTagCompletion(current, eligibility: .eligible, at: 123))
    XCTAssertEqual(feedback.rows.map(\.previousBestWpm),[120.49,120.49])
    XCTAssertTrue(feedback.editFeedback.crownedIDs.isEmpty); XCTAssertTrue(feedback.rows.allSatisfy(\.showsPreviousBestLine))
    XCTAssertTrue(account.accountTagHistoryPersonalBests.isEmpty); XCTAssertNil(account.accountTagHistoryCache)
  }
  @MainActor func testFractionalImprovementWithinSameIntegerWritesWholeClientSnapshotAndDelta() throws {
    let (account,defaults,suite) = try account(); defer { defaults.removePersistentDomain(forName: suite) }
    let scope = try XCTUnwrap(account.resultPublicationScope)
    _ = account.recordAccountTagCompletion(result(scope: scope, speed: 80.41), eligibility: .eligible, at: 123)
    let current = result(scope: scope, speed: 80.49)
    let feedback = try XCTUnwrap(account.recordAccountTagCompletion(current, eligibility: .eligible, at: 124))
    XCTAssertEqual(current.wpm,80); XCTAssertEqual(feedback.editFeedback.crownedIDs,[a,b])
    XCTAssertEqual(feedback.rows.map(\.previousBestWpm),[80.41,80.41])
    XCTAssertTrue(feedback.rows.allSatisfy { $0.hint.hasPrefix("+0.08") && !$0.showsPreviousBestLine })
    let consistency = ResultConsistencyPolicy.metrics(events: current.replayEvents, duration: current.chartDuration,
      configuration: current.configuration, keySpacingSamples: current.keySpacingSamples).typing
    XCTAssertTrue(account.accountTagHistoryPersonalBests.allSatisfy { $0.wpm == 80.49 && $0.rawWpm == 95.75
      && $0.accuracy == 98.25 && $0.consistency == consistency && $0.rebuiltAtMilliseconds == 124 })
  }
  private func remote(_ result: CompletedTestResult, ids: [UUID]) throws -> RemoteAccountResult {
    try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject:
      ["id": result.id.uuidString, "mode": "time", "mode2": "15", "language": "english",
        "durationSeconds": 15, "wpm": result.wpm, "rawWpm": result.rawWpm, "accuracy": result.accuracy,
        "preciseAccuracy": result.preciseAccuracy, "consistency": 80.75, "errorCount": 2, "eventCount": 100,
        "tags": result.tags, "accountTagIDs": ids.map(\.uuidString), "startedAt": 100, "finishedAt": 115,
        "startedAtReferenceTime": 100.0, "finishedAtReferenceTime": 115.0,
        "speedPrecision": ["version": 1, "wpm": result.preciseWpm, "rawWpm": result.preciseRawWpm],
        "personalBestConfiguration": ["version": 1, "difficulty": "normal", "punctuation": false,
          "numbers": false, "lazyMode": false]]))
  }
  @MainActor func testReadyHistoryExplicitZeroBeatsServerBaselineAndNewWinnerIsNotMasked() throws {
    let (account,defaults,suite) = try account(); defer { defaults.removePersistentDomain(forName: suite) }
    try account.applyAccountTagDirectory(directory(speed: 120.49), read: account.beginAccountTagDirectoryRead())
    let scope = try XCTUnwrap(account.resultPublicationScope), earlier = result(scope: scope)
    let row = try remote(earlier, ids: [a,b])
    try account.applyAccountTagHistory([row], read: account.beginAccountTagHistoryRead())
    var unlinked = row; unlinked.accountTagIDs = []
    try account.applyAccountTagHistoryEdit(unlinked, scope: scope, at: 123)
    XCTAssertEqual(account.accountTagHistoryPersonalBests.map(\.wpm), [0,0])
    let pendingRead = try account.beginAccountTagHistoryRead()
    let current = result(scope: scope)
    let feedback = try XCTUnwrap(account.recordAccountTagCompletion(current, eligibility: .eligible, at: 124))
    XCTAssertEqual(feedback.rows.map(\.previousBestWpm), [0,0]); XCTAssertEqual(feedback.editFeedback.crownedIDs,[a,b])
    XCTAssertEqual(account.accountTagHistoryPersonalBests.map(\.wpm), [80.49,80.49])
    XCTAssertTrue(account.isAccountTagHistoryReady); XCTAssertEqual(account.accountTagHistoryCache?.results,[unlinked])
    XCTAssertThrowsError(try account.applyAccountTagHistory([row], read: pendingRead))
    account.invalidateAccountTagHistory(clearLastResult: false)
    XCTAssertEqual(account.accountTagHistoryPersonalBests.map(\.wpm), [80.49,80.49])
  }
  @MainActor func testCompletionBeforeAcceptanceRetainsCrownsThroughCanonicalReadAndLaterResultEdit() throws {
    let (account,defaults,suite) = try account(); defer { defaults.removePersistentDomain(forName: suite) }
    let scope = try XCTUnwrap(account.resultPublicationScope), current = result(scope: scope, ids: [a])
    _ = account.recordAccountTagCompletion(current, eligibility: .eligible, at: 123)
    let row = try remote(current, ids: [a])
    let read = try XCTUnwrap(account.beginLastAccountResultRead(id: row.id, finishedAt: row.finishedAt, scope: scope))
    try account.applyLastAccountResult(row, read: read)
    XCTAssertEqual(account.lastAccountResultEditFeedback?.crownedIDs,[a])
    var linked = row; linked.accountTagIDs = [b,a]
    var root = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(linked)) as? [String: Any])
    root["tagPbs"] = [b.uuidString]
    let edit = try JSONDecoder().decode(RemoteAccountTagEditResponse.self, from: JSONSerialization.data(withJSONObject: root))
    try account.applyAccountTagEditResponse(edit, requestedIDs: [b,a], scope: scope, at: 124, fromResultPage: true)
    XCTAssertEqual(account.lastAccountResultEditFeedback?.displayedIDs,[a,b])
    XCTAssertEqual(account.lastAccountResultEditFeedback?.crownedIDs,[a,b])
    XCTAssertEqual(account.lastAccountResultEditAwardIDs,[b], "Initial client award is not a server edit receipt")
    XCTAssertEqual(current.accountTagSnapshot?.tagIDs,[a]); XCTAssertEqual(try account.accountTagPostingSelection(),[a,b])
  }
  @MainActor func testOldAcceptedReadCannotAttachNewCompletionCrownsToAnotherUUID() throws {
    let (account,defaults,suite) = try account(); defer { defaults.removePersistentDomain(forName: suite) }
    let scope = try XCTUnwrap(account.resultPublicationScope), first = result(scope: scope, ids: [a])
    _ = account.recordAccountTagCompletion(first, eligibility: .eligible, at: 123)
    let row = try remote(first, ids: [a]), read = try XCTUnwrap(account.beginLastAccountResultRead(id: row.id, finishedAt: row.finishedAt, scope: scope))
    let second = result(scope: scope, ids: [b])
    let feedback = account.recordAccountTagCompletion(second, eligibility: .eligible, at: 124)
    try account.applyLastAccountResult(row, read: read)
    XCTAssertEqual(account.lastAccountResultEditFeedback?.crownedIDs,[])
    XCTAssertEqual(account.lastAccountTagCompletionFeedback,feedback); XCTAssertEqual(feedback?.resultID,second.id)
  }
  @MainActor func testRepeatedCompletionCallDoesNotRecomputeFeedbackOrRewriteClientClock() throws {
    let (account,defaults,suite) = try account(); defer { defaults.removePersistentDomain(forName: suite) }
    let current = result(scope: try XCTUnwrap(account.resultPublicationScope))
    let first = account.recordAccountTagCompletion(current, eligibility: .eligible, at: 123)
    let revision = account.accountTagRevision, book = account.accountTagHistoryPersonalBests
    XCTAssertEqual(account.recordAccountTagCompletion(current, eligibility: .eligible, at: 999),first)
    XCTAssertEqual(account.accountTagRevision,revision); XCTAssertEqual(account.accountTagHistoryPersonalBests,book)
    XCTAssertTrue(book.allSatisfy { $0.rawWpm == 95.75 && $0.accuracy == 98.25 && $0.rebuiltAtMilliseconds == 123 })
  }
  @MainActor func testAdmissionAndSavedEnabledAreIndependentAndIneligibleResultsKeepOnlyTagLabels() throws {
    let (account,defaults,suite) = try account(); defer { defaults.removePersistentDomain(forName: suite) }
    let scope = try XCTUnwrap(account.resultPublicationScope)
    var stop = InputRules(); stop.stopOnErrorMode = .letter
    for (configuration,outcome,accuracy,eligibility) in [
      (TestConfiguration.timed(seconds: 15).with(modifiers: [.accountingStream]),TestOutcome.completed,98.25,ResultEligibility.eligible),
      (.timed(seconds: 15, rules: stop),.completed,98.25,.eligible),
      (.timed(seconds: 15),.bailedOut,100,.eligible),
      (.timed(seconds: 15),.failed,100,.ineligible(.testFailed)),
      (.timed(seconds: 15),.completed,100,.ineligible(.samePromptRepeat)),
      (.timed(seconds: 15),.completed,100,.ineligible(.tooShort))] {
      let feedback = try XCTUnwrap(account.recordAccountTagCompletion(result(scope: scope, configuration: configuration,
        outcome: outcome, accuracy: accuracy), eligibility: eligibility, at: 123))
      XCTAssertEqual(feedback.rows.count,2); XCTAssertTrue(feedback.editFeedback.crownedIDs.isEmpty)
      XCTAssertTrue(feedback.rows.allSatisfy { !$0.showsPreviousBestLine }); XCTAssertTrue(account.accountTagHistoryPersonalBests.isEmpty)
    }
    let perfect = result(scope: scope, configuration: .timed(seconds: 15, rules: stop), accuracy: 100)
    XCTAssertFalse(ResultSavingPolicy.shouldPersist(outcome: perfect.outcome, enabled: false, eligibility: .eligible))
    XCTAssertEqual(account.recordAccountTagCompletion(perfect, eligibility: .eligible, at: 124)?.editFeedback.crownedIDs,[a,b])
  }
  @MainActor func testScopeInvalidSnapshotNoDirectoryAndInvalidClockNeverAdmitOrWrite() throws {
    let (account,defaults,suite) = try account(); defer { defaults.removePersistentDomain(forName: suite) }
    let scope = try XCTUnwrap(account.resultPublicationScope), current = result(scope: scope)
    let revision = account.accountTagRevision
    XCTAssertNil(account.recordAccountTagCompletion(current, eligibility: .eligible, at: -1))
    var bad = current; bad.accountTagSnapshot = .unavailable
    XCTAssertNil(account.recordAccountTagCompletion(bad, eligibility: .eligible, at: 123))
    bad.accountTagSnapshot = nil
    XCTAssertNil(account.recordAccountTagCompletion(bad, eligibility: .eligible, at: 123))
    XCTAssertEqual(account.accountTagRevision,revision); XCTAssertTrue(account.accountTagHistoryPersonalBests.isEmpty)
    let user = account.currentUser; account.currentUser = nil
    XCTAssertNil(account.recordAccountTagCompletion(current, eligibility: .eligible, at: 123))
    account.currentUser = user
    XCTAssertNil(account.recordAccountTagCompletion(current, eligibility: .eligible, at: 123), "Unknown directory must not be fabricated")
    try account.applyAccountTagDirectory(directory(), read: account.beginAccountTagDirectoryRead())
    XCTAssertNotNil(account.recordAccountTagCompletion(current, eligibility: .eligible, at: 123))
    account.currentUser = nil
    XCTAssertNil(account.lastAccountTagCompletionFeedback); XCTAssertTrue(account.accountTagHistoryPersonalBests.isEmpty)
  }
  @MainActor func testCurrentPostingSelectionAndTextLabelsDoNotReplaceCapturedStableIDs() throws {
    let (account,defaults,suite) = try account(); defer { defaults.removePersistentDomain(forName: suite) }
    let scope = try XCTUnwrap(account.resultPublicationScope), current = result(scope: scope, ids: [a,UUID()])
    try account.setAccountTagPostingSelection([b])
    let feedback = account.recordAccountTagCompletion(current, eligibility: .eligible, at: 123)
    XCTAssertEqual(feedback?.rows.map(\.id),[a]); XCTAssertEqual(feedback?.editFeedback.crownedIDs,[a])
    XCTAssertEqual(account.accountTagHistoryPersonalBests.map(\.tagID),[a])
    let empty = result(scope: scope, ids: [])
    XCTAssertEqual(account.recordAccountTagCompletion(empty, eligibility: .eligible, at: 124)?.rows,[])
  }
  func testInitialFeedbackMatchesPinnedFullFunctionsAcross6912Cases() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else { throw XCTSkip("Pinned reference required") }
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Scripts/check-source-account-tag-completion.mjs")
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env"); process.arguments = ["node",script.path,reference,"--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors; try process.run()
    let bytes = output.fileHandleForReading.readDataToEndOfFile(), diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); XCTAssertEqual(process.terminationStatus,0,String(decoding: diagnostics,as: UTF8.self))
    struct Row: Decodable { let id: UUID; let previousBestWpm: Double; let isNewPersonalBest: Bool; let showsPreviousBestLine: Bool }
    struct Fixture: Decodable {
      let mode: TestMode; let mode2: String; let difficulty: Difficulty; let punctuation: Bool; let numbers: Bool
      let lazyMode: Bool; let dontSave: Bool; let funboxes: [String]; let stopOnLetter: Bool
      let accuracy: Double; let bailedOut: Bool; let previous: Double; let rows: [Row]
      let modeAllowed: Bool; let numbersAllowed: Bool
    }
    struct Document: Decodable { let referenceCommit: String; let ids: [UUID]; let fixtures: [Fixture] }
    let document = try JSONDecoder().decode(Document.self,from: bytes)
    XCTAssertEqual(document.referenceCommit,"91bd24bb8513785c7364cbea29296ff7adafac41"); XCTAssertEqual(document.fixtures.count,6912)
    let tags = try JSONDecoder().decode(RemoteAccountTagList.self,from: JSONSerialization.data(withJSONObject:
      ["version":1,"tags":document.ids.map { ["id":$0.uuidString,"name":"desk","personalBestLedgerVersion":1,"personalBests":[]] }])).tags
    let scope = ResultPublicationScope(endpoint: "https://owned.invalid", userID: UUID())
    for fixture in document.fixtures {
      var rules = InputRules(); rules.stopOnErrorMode = fixture.stopOnLetter ? .letter : .off
      var modifiers: [TestModifier] = fixture.funboxes.map { $0 == "no_quit" ? .noQuit : .accountingStream }
      if fixture.lazyMode { modifiers.append(.lazyLatin) }
      let configuration = TestConfiguration(mode: fixture.mode,
        duration: fixture.mode == .time ? Double(fixture.mode2) : nil,
        wordLimit: fixture.mode == .words ? Int(fixture.mode2) : nil, difficulty: fixture.difficulty,
        rules: rules, modifiers: modifiers, contentOptions: .init(includePunctuation: fixture.punctuation,includeNumbers: fixture.numbers))
      if !fixture.modeAllowed {
        XCTAssertFalse(TestModifierPolicy.acceptsModeSelection(fixture.mode, modifiers: modifiers))
        continue
      }
      if !fixture.numbersAllowed {
        XCTAssertNotEqual(configuration.contentOptions.includeNumbers,fixture.numbers)
        continue
      }
      let result = result(scope: scope,ids: document.ids,configuration: configuration,
        outcome: fixture.bailedOut ? .bailedOut : .completed,accuracy: fixture.accuracy)
      let bests = AccountTagHistoryGroup(configuration).map { group in document.ids.enumerated().map {
        AccountTagHistoryPersonalBest(tagID: $0.element,group: group,wpm: $0.offset == 0 ? fixture.previous : 90.69,
          rawWpm: 120,accuracy: 99,consistency: 75,rebuiltAtMilliseconds: 123) } } ?? []
      let feedback = AccountTagCompletionPolicy.feedback(result,scope: scope,directory: tags,personalBests: bests,
        eligibility: fixture.dontSave ? .ineligible(.samePromptRepeat) : .eligible)
      XCTAssertEqual(feedback.rows.map(\.id),fixture.rows.map(\.id))
      XCTAssertEqual(feedback.rows.map(\.previousBestWpm),fixture.rows.map(\.previousBestWpm))
      let context = "\(fixture.mode) / \(fixture.mode2), \(fixture.funboxes), stop=\(fixture.stopOnLetter), acc=\(fixture.accuracy), bailout=\(fixture.bailedOut), dontSave=\(fixture.dontSave), previous=\(fixture.previous), effectiveModifiers=\(configuration.modifiers)"
      XCTAssertEqual(feedback.rows.map(\.isNewPersonalBest),fixture.rows.map(\.isNewPersonalBest),context)
      XCTAssertEqual(feedback.rows.map(\.showsPreviousBestLine),fixture.rows.map(\.showsPreviousBestLine),context)
    }
  }
}
