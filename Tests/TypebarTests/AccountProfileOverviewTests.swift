import Foundation
import XCTest
@testable import Typebar

final class AccountProfileOverviewTests: XCTestCase {
  func testAccountOverviewIsIntegratedBeforeFilteredHistoryControls() throws {
    let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Sources/Typebar/AccountHistoryView.swift")
    let text = try String(contentsOf: source, encoding: .utf8)
    guard let overview = text.range(of: "AccountProfileOverviewView("),
      let filters = text.range(of: "          presetControls") else {
      return XCTFail("The account page needs an independent owner overview, not only filtered results")
    }
    XCTAssertLessThan(overview.lowerBound, filters.lowerBound)
  }

  private func profile(id: UUID) throws -> RemotePublicProfile {
    try JSONDecoder().decode(RemotePublicProfile.self, from: JSONSerialization.data(withJSONObject: [
      "id": id.uuidString, "displayName": "Owned overview", "joinedAt": 0,
      "completedResultCount": 30, "startedTestCount": 42, "totalTypingSeconds": 600,
      "bestWPM": 60, "profileDetails": ["showActivity": false],
      "activity": ["lastDay": 100, "testsByDays": [15, 15]],
      "allTimeLbs": ["time": ["15": ["english": ["rank": 2, "count": 3]]]]
    ]))
  }

  @MainActor private func session(_ body: (AccountSession) async throws -> Void) async throws {
    let suite = "TypebarTests.owner-overview.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let account = AccountSession(defaults: defaults)
    account.currentUser = .init(id: UUID(), email: "owned@example.invalid", displayName: "Owner", totalExperience: 500)
    try await body(account)
  }

  @MainActor func testOwnerSnapshotKeepsHiddenActivityAndLifetimeIndependentOfEmptyHistory() async throws {
    try await session { account in
      let scope = try XCTUnwrap(account.resultPublicationScope), profile = try self.profile(id: scope.userID)
      let tagRevision = account.accountTagRevision, stateRevision = account.accountPersonalBestSessionRevision
      let read = try await account.loadAccountProfileOverview(scope: scope) { profile }
      XCTAssertFalse(read.profileDetails.showActivity); XCTAssertNotNil(read.activity)
      XCTAssertEqual(read.completedResultCount, 30); XCTAssertEqual(read.startedTestCount, 42)
      XCTAssertEqual(read.totalTypingSeconds, 600); XCTAssertEqual(PublicProfileLeaderboardPolicy.cards(read).count, 1)
      XCTAssertTrue(account.accountHistoryLoadedResults.isEmpty); XCTAssertTrue(account.remoteResults.isEmpty)
      XCTAssertEqual(account.currentUser?.totalExperience, 500); XCTAssertNil(account.lastAccountResult)
      XCTAssertEqual(account.accountTagRevision, tagRevision); XCTAssertNil(account.accountTagHistoryCache)
      XCTAssertEqual(account.accountPersonalBestSessionRevision, stateRevision)
      XCTAssertNil(account.statusMessage); XCTAssertFalse(account.isWorking)
    }
  }

  @MainActor func testWrongOwnerAndExpiredScopeAreRejectedBeforeCredentialedLoad() async throws {
    try await session { account in
      let scope = try XCTUnwrap(account.resultPublicationScope), wrong = try self.profile(id: UUID())
      do {
        _ = try await account.loadAccountProfileOverview(scope: scope) { wrong }
        XCTFail("Another user's overview must not display")
      } catch let error as RemoteAccountError {
        guard case .unexpectedResponse = error else { return XCTFail("\(error)") }
      }
      account.currentUser = nil
      var calls = 0
      do {
        _ = try await account.loadAccountProfileOverview(scope: scope) { calls += 1; return wrong }
        XCTFail("A signed-out request must not read credentials or request a snapshot")
      } catch let error as RemoteAccountError {
        guard case .accountScopeChanged = error else { return XCTFail("\(error)") }
      }
      XCTAssertEqual(calls, 0)
    }
  }

  @MainActor func testOwnerSessionAndServerRoundTripsRejectLateReadsAndChangeActualTaskIdentity() async throws {
    try await session { account in
      let scope = try XCTUnwrap(account.resultPublicationScope), user = try XCTUnwrap(account.currentUser)
      let profile = try self.profile(id: user.id), revision = UUID(), endpoint = account.endpoint
      for changeServer in [false, true] {
        let identity = AccountProfileOverviewLoadID(account: account, revision: revision)
        do {
          _ = try await account.loadAccountProfileOverview(scope: scope) {
            if changeServer {
              XCTAssertTrue(account.updateEndpoint("https://other-owned.invalid"))
              XCTAssertTrue(account.updateEndpoint(endpoint))
            } else { account.currentUser = nil }
            account.currentUser = user; return profile
          }
          XCTFail("ABA must invalidate the outstanding owner snapshot")
        } catch let error as RemoteAccountError {
          guard case .accountScopeChanged = error else { return XCTFail("\(error)") }
        }
        XCTAssertNotEqual(identity, .init(account: account, revision: revision))
      }
      let fresh = try await account.loadAccountProfileOverview(scope: scope) { profile }
      XCTAssertEqual(fresh.id, user.id)
    }
  }

  @MainActor func testCancelledOrFailedOwnerReadDoesNotFallbackToPublicDataAndCanRetry() async throws {
    try await session { account in
      let scope = try XCTUnwrap(account.resultPublicationScope), profile = try self.profile(id: scope.userID)
      let task = Task { @MainActor in
        try await account.loadAccountProfileOverview(scope: scope) {
          withUnsafeCurrentTask { $0?.cancel() }; return profile
        }
      }
      do { _ = try await task.value; XCTFail("Cancelled snapshot cannot display") } catch is CancellationError { }
      do {
        _ = try await account.loadAccountProfileOverview(scope: scope) { throw URLError(.notConnectedToInternet) }
        XCTFail("Network failure must not turn into an empty/public overview")
      } catch let error as URLError { XCTAssertEqual(error.code, .notConnectedToInternet) }
      let retried = try await account.loadAccountProfileOverview(scope: scope) { profile }
      XCTAssertNotNil(retried.activity); XCTAssertEqual(retried.completedResultCount, 30)
    }
  }

  @MainActor func testActualOverviewTaskIdentityRefreshesOnOwnMetadataButNotIdenticalUserRefresh() async throws {
    try await session { account in
      let user = try XCTUnwrap(account.currentUser), revision = UUID()
      let identity = AccountProfileOverviewLoadID(account: account, revision: revision)
      account.currentUser = user
      XCTAssertEqual(identity, .init(account: account, revision: revision))
      account.currentUser = .init(id: user.id, email: user.email, displayName: "Updated owner",
        totalExperience: user.totalExperience, profileDetails: .init(bio: "Updated bio", showActivity: false))
      XCTAssertEqual(account.resultPublicationScope, identity.scope)
      XCTAssertNotEqual(identity, .init(account: account, revision: revision))
      XCTAssertNotEqual(AccountProfileOverviewLoadID(account: account, revision: UUID()),
        AccountProfileOverviewLoadID(account: account, revision: revision))
    }
  }

  func testLifetimeTimeRoundsSecondsWithoutTruncatingMinutesAndKeepsLargeHours() {
    for (seconds, expected) in [(0.0, "00:00:00"), (59.49, "00:00:59"), (59.5, "00:01:00"),
      (3599.5, "01:00:00"), (360_000.0, "100:00:00")] {
      XCTAssertEqual(AccountProfileLifetimePresentation.duration(seconds), expected)
    }
    for seconds in [-1.0, Double.nan, Double.infinity, 9_007_199_254_740_992] {
      XCTAssertEqual(AccountProfileLifetimePresentation.duration(seconds), "未知")
    }
  }

  func testOwnerLifetimeFormattingMatchesCompletePinnedProfileFunctions() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Readiness supplies pinned reference")
    }
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Scripts/check-source-account-history-graphs.mjs")
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = .init(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", script.path, reference, "--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile(), diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0, String(decoding: diagnostics, as: UTF8.self))
    struct Fixture: Decodable {
      struct Ratio: Decodable { let started: Int; let completed: Int; let completedPercentage: String; let restartRatio: String }
      struct Duration: Decodable { let seconds: Double; let text: String }
      let profileRatios: [Ratio]; let profileDurations: [Duration]
    }
    let fixtures = try JSONDecoder().decode([Fixture].self, from: data)
    let ratios = fixtures.flatMap(\.profileRatios), durations = fixtures.flatMap(\.profileDurations)
    XCTAssertEqual(ratios.count, 14); XCTAssertEqual(durations.count, 8)
    for ratio in ratios {
      var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile(id: UUID()))) as? [String: Any])
      object["completedResultCount"] = ratio.completed; object["startedTestCount"] = ratio.started
      let profile = try JSONDecoder().decode(RemotePublicProfile.self, from: JSONSerialization.data(withJSONObject: object))
      XCTAssertEqual(AccountProfileLifetimePresentation.completion(profile), ratio.completedPercentage.isEmpty ? "未知" : ratio.completedPercentage + "%")
      XCTAssertEqual(AccountProfileLifetimePresentation.restartRatio(profile), ratio.restartRatio.isEmpty ? "未知" : ratio.restartRatio)
    }
    for duration in durations { XCTAssertEqual(AccountProfileLifetimePresentation.duration(duration.seconds), duration.text) }
  }
}
