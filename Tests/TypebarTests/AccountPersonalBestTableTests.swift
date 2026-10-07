import Foundation
import XCTest
@testable import Typebar

final class AccountPersonalBestTableTests: XCTestCase {
  private func best(_ parameter: String = "15", speed: Double = 60.49,
    language: String = "english", id: UUID = UUID()) -> [String: Any] {
    ["id": id.uuidString, "mode": "time", "mode2": parameter, "durationSeconds": Int(parameter)!,
      "language": language, "wpm": Int(speed.rounded()), "rawWpm": 120, "preciseWpm": speed,
      "preciseRawWpm": 120.0, "accuracy": 98, "preciseAccuracy": 98.25, "consistency": 80.5,
      "finishedAt": 115, "acceptedAtMilliseconds": 1_800_000_000_875, "personalBestOrigin": "accepted",
      "personalBestConfiguration": ["version": 1, "difficulty": "expert", "punctuation": false,
        "numbers": true, "lazyMode": false]]
  }
  private func payload(_ rows: [[String: Any]], userID: UUID = UUID()) -> [String: Any] {
    ["id": userID.uuidString, "displayName": "Owned", "joinedAt": 0, "completedResultCount": 0,
      "bestWPM": 0, "personalBests": [], "personalBestLedgerVersion": 1,
      "personalBestHistoryComplete": true, "personalBestSnapshots": rows]
  }
  private func decode(_ root: [String: Any]) throws -> RemotePublicProfile {
    try JSONDecoder().decode(RemotePublicProfile.self, from: JSONSerialization.data(withJSONObject: root))
  }
  @MainActor private func session(_ body: (AccountSession) async throws -> Void) async throws {
    let suite = "TypebarTests.account-pb.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let account = AccountSession(defaults: defaults)
    account.currentUser = .init(id: UUID(), email: "owned@example.invalid", displayName: "Owned", totalExperience: 500)
    try await body(account)
  }

  func testGroupsUseParameterOrderFractionalSpeedAndStableTiesWithoutDroppingConfigurations() throws {
    let input = [best("30", speed: 90), best("15", speed: 60.49),
      best("15", speed: 80, language: "french"), best("15", speed: 80, language: "german"), best("5")]
    let profile = try decode(payload(input)), rows = AccountPersonalBestTablePolicy.rows(profile, mode: .time)
    XCTAssertEqual(rows.map(\.best.id.uuidString), [input[4], input[2], input[3], input[1], input[0]].map { $0["id"] as! String })
    XCTAssertEqual(rows.map(\.isGroupStart), [true, true, false, false, true])
    XCTAssertEqual(Set(rows.map(\.id)).count, 5)
    XCTAssertEqual(rows[3].best.preciseRawWpm, 120)
    XCTAssertEqual(rows[3].best.preciseAccuracy, 98.25)
    XCTAssertEqual(rows[3].best.personalBestConfiguration?.numbers, true)
    XCTAssertEqual(rows[3].best.recordedAt.timeIntervalSince1970, 1_800_000_000.875)
    XCTAssertTrue(AccountPersonalBestTablePolicy.rows(profile, mode: .words).isEmpty)
    XCTAssertEqual(profile.personalBestSnapshots?.map(\.id.uuidString), input.map { $0["id"] as! String })
  }

  func testKnownEmptyLedgerDoesNotResurrectStandardSummaryAndOldCoverageIsExplicit() throws {
    var root = payload([]); root["personalBests"] = [best()]
    let empty = try decode(root)
    XCTAssertTrue(AccountPersonalBestTablePolicy.rows(empty, mode: .time).isEmpty)
    XCTAssertTrue(AccountPersonalBestTablePolicy.coverageNotice(empty).contains("独立"))
    for key in ["personalBestLedgerVersion", "personalBestHistoryComplete", "personalBestSnapshots"] { root.removeValue(forKey: key) }
    var old = best(); old.removeValue(forKey: "personalBestConfiguration"); old.removeValue(forKey: "rawWpm")
    old.removeValue(forKey: "preciseRawWpm"); old.removeValue(forKey: "acceptedAtMilliseconds")
    root["personalBests"] = [old]
    let legacy = try decode(root), row = try XCTUnwrap(AccountPersonalBestTablePolicy.rows(legacy, mode: .time).first)
    XCTAssertEqual(row.best.groupingLabel, "选项未知"); XCTAssertNil(row.best.rawSpeedText)
    XCTAssertEqual(row.best.recordedAt, row.best.finishedAt)
    XCTAssertTrue(AccountPersonalBestTablePolicy.coverageNotice(legacy).contains("不是完整"))
    root = payload([best()]); root["personalBestHistoryComplete"] = false
    XCTAssertTrue(AccountPersonalBestTablePolicy.coverageNotice(try decode(root)).contains("无法补回"))
  }

  func testLegacySummaryUsesExplicitParameterWithoutInventingUnknownConfiguration() throws {
    var input = [best("30"), best("15"), best("15", speed: 80, language: "french")]
    for index in input.indices { input[index].removeValue(forKey: "mode2") }
    var unknown = best(); unknown.removeValue(forKey: "mode2"); unknown.removeValue(forKey: "durationSeconds")
    unknown.removeValue(forKey: "personalBestConfiguration"); input.insert(unknown, at: 0)
    var root = payload([]); root["personalBests"] = input
    for key in ["personalBestLedgerVersion", "personalBestHistoryComplete", "personalBestSnapshots"] { root.removeValue(forKey: key) }
    let rows = AccountPersonalBestTablePolicy.rows(try decode(root), mode: .time)
    XCTAssertEqual(rows.map(\.best.id.uuidString), [input[3], input[2], input[1], input[0]].map { $0["id"] as! String })
    XCTAssertEqual(rows.map(\.isGroupStart), [true, false, true, true])
    XCTAssertEqual(rows.last?.best.configurationLabel, "时间未知")
    XCTAssertEqual(rows.last?.best.groupingLabel, "选项未知")
  }

  @MainActor func testScopedReadDoesNotMutateResultTagExperienceOrLastResultCaches() async throws {
    try await session { account in
      let scope = try XCTUnwrap(account.resultPublicationScope), profile = try self.decode(self.payload([self.best()], userID: scope.userID))
      let revision = account.accountTagRevision, user = account.currentUser
      let result = try await account.loadAccountPersonalBestProfile(scope: scope) { profile }
      XCTAssertEqual(result.id, scope.userID); XCTAssertEqual(result.displayPersonalBests.count, 1)
      XCTAssertTrue(account.remoteResults.isEmpty); XCTAssertNil(account.accountTagHistoryCache)
      XCTAssertEqual(account.accountTagRevision, revision); XCTAssertEqual(account.currentUser?.totalExperience, user?.totalExperience)
      XCTAssertNil(account.lastAccountResult); XCTAssertFalse(account.isWorking)
    }
  }

  @MainActor func testSameAccountRoundTripRejectsLateProfileAndNewReadCanSucceed() async throws {
    try await session { account in
      let scope = try XCTUnwrap(account.resultPublicationScope), user = try XCTUnwrap(account.currentUser)
      let profile = try self.decode(self.payload([self.best()], userID: scope.userID))
      do {
        _ = try await account.loadAccountPersonalBestProfile(scope: scope) {
          await Task.yield(); account.currentUser = nil; account.currentUser = user
          return profile
        }
        XCTFail("Old same-account response must not be displayed")
      } catch let error as RemoteAccountError { guard case .accountScopeChanged = error else { return XCTFail("\(error)") } }
      let fresh = try await account.loadAccountPersonalBestProfile(scope: scope) { profile }
      XCTAssertEqual(fresh.id, user.id)
    }
  }

  @MainActor func testActualViewTaskIdentityChangesOnSameAccountRoundTripButNotProfileRefresh() async throws {
    try await session { account in
      let user = try XCTUnwrap(account.currentUser), revision = UUID()
      let before = AccountPersonalBestTableLoadID(account: account, revision: revision)
      account.currentUser = user
      XCTAssertEqual(before, AccountPersonalBestTableLoadID(account: account, revision: revision))
      account.currentUser = nil; account.currentUser = user
      XCTAssertNotEqual(before, AccountPersonalBestTableLoadID(account: account, revision: revision),
        "Coalesced logout/login must invalidate the cached profile and restart the actual view task")
    }
  }

  @MainActor func testWrongIdentityAndExpiredScopeAreRejectedWithoutReadingCredentials() async throws {
    try await session { account in
      let scope = try XCTUnwrap(account.resultPublicationScope), wrong = try self.decode(self.payload([self.best()]))
      do {
        _ = try await account.loadAccountPersonalBestProfile(scope: scope) { wrong }
        XCTFail("Wrong profile must not render")
      } catch let error as RemoteAccountError { guard case .unexpectedResponse = error else { return XCTFail("\(error)") } }
      account.currentUser = nil
      var calls = 0
      do {
        _ = try await account.loadAccountPersonalBestProfile(scope: scope) { calls += 1; return wrong }
        XCTFail("Expired scope must not start a request")
      } catch { }
      XCTAssertEqual(calls, 0)
    }
  }

  @MainActor func testServerRoundTripInvalidatesActualViewIdentityAndOutstandingRead() async throws {
    try await session { account in
      let scope = try XCTUnwrap(account.resultPublicationScope), user = try XCTUnwrap(account.currentUser)
      let profile = try self.decode(self.payload([self.best()], userID: user.id)), revision = UUID()
      let identity = AccountPersonalBestTableLoadID(account: account, revision: revision), endpoint = account.endpoint
      do {
        _ = try await account.loadAccountPersonalBestProfile(scope: scope) {
          XCTAssertTrue(account.updateEndpoint("https://other-owned.invalid"))
          XCTAssertTrue(account.updateEndpoint(endpoint)); account.currentUser = user
          return profile
        }
        XCTFail("Server ABA must not return an old profile")
      } catch let error as RemoteAccountError { guard case .accountScopeChanged = error else { return XCTFail("\(error)") } }
      XCTAssertEqual(account.resultPublicationScope, scope)
      XCTAssertNotEqual(identity, AccountPersonalBestTableLoadID(account: account, revision: revision))
    }
  }

  @MainActor func testFailurePreservesOtherCachesAndCanBeRetried() async throws {
    try await session { account in
      let scope = try XCTUnwrap(account.resultPublicationScope), revision = account.accountTagRevision
      do {
        _ = try await account.loadAccountPersonalBestProfile(scope: scope) { throw URLError(.notConnectedToInternet) }
        XCTFail("Failure cannot produce a successful empty ledger")
      } catch let error as URLError { XCTAssertEqual(error.code, .notConnectedToInternet) }
      XCTAssertEqual(account.accountTagRevision, revision); XCTAssertEqual(account.currentUser?.totalExperience, 500)
      XCTAssertFalse(account.isWorking); XCTAssertNil(account.statusMessage)
      let profile = try self.decode(self.payload([], userID: scope.userID))
      let retried = try await account.loadAccountPersonalBestProfile(scope: scope) { profile }
      XCTAssertTrue(retried.displayPersonalBests.isEmpty)
    }
  }

  @MainActor func testCancelledReadDoesNotReturnAProfileEvenIfLoaderIgnoresCancellation() async throws {
    try await session { account in
      let scope = try XCTUnwrap(account.resultPublicationScope), profile = try self.decode(self.payload([self.best()], userID: scope.userID))
      let task = Task { @MainActor in
        try await account.loadAccountPersonalBestProfile(scope: scope) {
          withUnsafeCurrentTask { $0?.cancel() }
          return profile
        }
      }
      do { _ = try await task.value; XCTFail("Cancelled read cannot render") } catch is CancellationError { }
    }
  }

  func testCompletePinnedBuildRowsAgainstAllNativeModeProjections() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else { throw XCTSkip("Readiness supplies the pinned reference") }
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Scripts/check-source-account-personal-bests.mjs")
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = .init(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", script.path, reference, "--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile(), diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0, String(decoding: diagnostics, as: UTF8.self))
    struct Fixture: Decodable {
      struct Expected: Decodable { let id: UUID; let isGroupStart: Bool }
      let mode: TestMode; let profile: RemotePublicProfile; let expected: [Expected]
    }
    struct Document: Decodable { let referenceCommit: String; let fixtures: [Fixture] }
    let document = try JSONDecoder().decode(Document.self, from: data)
    XCTAssertEqual(document.referenceCommit, "91bd24bb8513785c7364cbea29296ff7adafac41"); XCTAssertEqual(document.fixtures.count, 24)
    for fixture in document.fixtures {
      let rows = AccountPersonalBestTablePolicy.rows(fixture.profile, mode: fixture.mode)
      XCTAssertEqual(rows.map(\.best.id), fixture.expected.map(\.id))
      XCTAssertEqual(rows.map(\.isGroupStart), fixture.expected.map(\.isGroupStart))
    }
  }
}
