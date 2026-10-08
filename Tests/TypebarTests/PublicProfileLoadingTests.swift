import Foundation
import XCTest
@testable import Typebar

final class PublicProfileLoadingTests: XCTestCase {
  func testSearchSelectionDoesNotPresentLightweightSummaryAsFullProfile() throws {
    let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Sources/Typebar/NavigationCommands.swift")
    let text = try String(contentsOf: source, encoding: .utf8)
    XCTAssertFalse(text.contains("PublicProfileView(profile: profile, account: account, settings: settings)"),
      "Search summaries omit activity and all-time ranks; selection must request the full profile")
    XCTAssertTrue(text.contains("PublicProfileLoadingView(profileID: profile.id, account: account, settings: settings)"))
  }

  private func profile(id: UUID, detailed: Bool = true) throws -> RemotePublicProfile {
    var value: [String: Any] = ["id": id.uuidString, "displayName": "Owned profile", "joinedAt": 0,
      "completedResultCount": 2, "bestWPM": 60]
    if detailed {
      value["activity"] = ["lastDay": 100, "testsByDays": [1, 1], "dayBoundaryOffsetHours": 0]
      value["allTimeLbs"] = ["time": ["15": ["english": ["rank": 2, "count": 3]]]]
    }
    return try JSONDecoder().decode(RemotePublicProfile.self, from: JSONSerialization.data(withJSONObject: value))
  }

  @MainActor private func session(_ body: (AccountSession) async throws -> Void) async throws {
    let suite = "TypebarTests.public-profile-load.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try await body(AccountSession(defaults: defaults))
  }

  @MainActor func testAnonymousReadLoadsFullActivityAndRanksWithoutMutatingAccountCaches() async throws {
    try await session { account in
      let id = UUID(), summary = try self.profile(id: id, detailed: false)
      XCTAssertNil(summary.activity); XCTAssertNil(summary.allTimeLbs)
      let full = try self.profile(id: id), state = PublicProfileLoadState()
      let request = PublicProfileLoadID(profileID: id, account: account, retryRevision: UUID())
      let tagRevision = account.accountTagRevision
      await state.load(request: request) {
        try await account.loadPublicProfile(id: id) { full }
      }
      XCTAssertEqual(state.profile?.activity?.testsByDays, [1, 1])
      XCTAssertEqual(state.profile?.allTimeLbs?.time["15"]?["english"]?.rank, 2)
      XCTAssertNil(state.message); XCTAssertNil(account.currentUser)
      XCTAssertTrue(account.remoteResults.isEmpty); XCTAssertNil(account.accountTagHistoryCache)
      XCTAssertEqual(account.accountTagRevision, tagRevision); XCTAssertNil(account.lastAccountResult)
      XCTAssertFalse(account.isWorking); XCTAssertNil(account.statusMessage)
    }
  }

  @MainActor func testWrongProfileIdentityIsRejectedByAccountReaderAndSheetState() async throws {
    try await session { account in
      let id = UUID(), wrong = try self.profile(id: UUID())
      do {
        _ = try await account.loadPublicProfile(id: id) { wrong }
        XCTFail("A response for a different user must not render")
      } catch let error as RemoteAccountError {
        guard case .unexpectedResponse = error else { return XCTFail("\(error)") }
      }
      let state = PublicProfileLoadState()
      await state.load(request: .init(profileID: id, account: account, retryRevision: UUID())) { wrong }
      XCTAssertNil(state.profile); XCTAssertNotNil(state.message)
    }
  }

  @MainActor func testServerRoundTripRejectsLateAnonymousReadAndChangesViewTaskIdentity() async throws {
    try await session { account in
      let id = UUID(), full = try self.profile(id: id), retry = UUID(), endpoint = account.endpoint
      let identity = PublicProfileLoadID(profileID: id, account: account, retryRevision: retry)
      do {
        _ = try await account.loadPublicProfile(id: id) {
          XCTAssertTrue(account.updateEndpoint("https://other-owned.invalid"))
          XCTAssertTrue(account.updateEndpoint(endpoint))
          return full
        }
        XCTFail("Endpoint ABA must invalidate outstanding public reads")
      } catch let error as RemoteAccountError {
        guard case .accountScopeChanged = error else { return XCTFail("\(error)") }
      }
      XCTAssertNil(account.currentUser)
      XCTAssertNotEqual(identity, .init(profileID: id, account: account, retryRevision: retry))
      let fresh = try await account.loadPublicProfile(id: id) { full }
      XCTAssertEqual(fresh.id, id)
    }
  }

  @MainActor func testLogoutLoginRoundTripInvalidatesReadButSameUserRefreshDoesNot() async throws {
    try await session { account in
      let id = UUID(), full = try self.profile(id: id), retry = UUID()
      let user = RemoteAccountUser(id: UUID(), email: "owned@example.invalid", displayName: "Owned", totalExperience: 500)
      account.currentUser = user
      let identity = PublicProfileLoadID(profileID: id, account: account, retryRevision: retry)
      let refreshed = try await account.loadPublicProfile(id: id) { account.currentUser = user; return full }
      XCTAssertEqual(refreshed.id, id)
      XCTAssertEqual(identity, .init(profileID: id, account: account, retryRevision: retry))
      do {
        _ = try await account.loadPublicProfile(id: id) {
          account.currentUser = nil; account.currentUser = user; return full
        }
        XCTFail("Logout/login ABA must invalidate outstanding reads")
      } catch let error as RemoteAccountError {
        guard case .accountScopeChanged = error else { return XCTFail("\(error)") }
      }
      XCTAssertNotEqual(identity, .init(profileID: id, account: account, retryRevision: retry))
      XCTAssertEqual(account.currentUser?.totalExperience, 500)
    }
  }

  @MainActor func testFailureIsNotAnEmptyOrSummarySuccessAndRetryLoadsDetailedProfile() async throws {
    try await session { account in
      let id = UUID(), full = try self.profile(id: id), state = PublicProfileLoadState()
      let first = PublicProfileLoadID(profileID: id, account: account, retryRevision: UUID())
      await state.load(request: first) { throw URLError(.notConnectedToInternet) }
      XCTAssertNil(state.profile); XCTAssertTrue(state.message?.contains("重试") == true)
      let retry = PublicProfileLoadID(profileID: id, account: account, retryRevision: UUID())
      XCTAssertNotEqual(first, retry)
      await state.load(request: retry) { try await account.loadPublicProfile(id: id) { full } }
      XCTAssertEqual(state.request, retry); XCTAssertNotNil(state.profile?.activity)
      XCTAssertNotNil(state.profile?.allTimeLbs); XCTAssertNil(state.message)
    }
  }

  @MainActor func testOlderSuccessOrFailureCannotReplaceNewerSelectionEvenWithoutTransportCancellation() async throws {
    try await session { account in
      for failOld in [false, true] {
        let old = try self.profile(id: UUID()), new = try self.profile(id: UUID())
        let state = PublicProfileLoadState()
        let first = PublicProfileLoadID(profileID: old.id, account: account, retryRevision: UUID())
        let second = PublicProfileLoadID(profileID: new.id, account: account, retryRevision: UUID())
        var pending: CheckedContinuation<RemotePublicProfile, Error>?
        let (started, signal) = AsyncStream<Void>.makeStream()
        let oldTask = Task { @MainActor in
          await state.load(request: first) {
            try await withCheckedThrowingContinuation {
              pending = $0; signal.yield(); signal.finish()
            }
          }
        }
        for await _ in started { break }
        XCTAssertNil(state.profile); XCTAssertNil(state.message)
        await state.load(request: second) { new }
        if failOld { pending?.resume(throwing: URLError(.timedOut)) }
        else { pending?.resume(returning: old) }
        await oldTask.value
        XCTAssertEqual(state.request, second); XCTAssertEqual(state.profile?.id, new.id)
        XCTAssertNil(state.message)
      }
    }
  }

  @MainActor func testCancelledReadAndSheetDoNotPublishEvenIfTransportIgnoresCancellation() async throws {
    try await session { account in
      let id = UUID(), full = try self.profile(id: id)
      let task = Task { @MainActor in
        try await account.loadPublicProfile(id: id) {
          withUnsafeCurrentTask { $0?.cancel() }; return full
        }
      }
      do { _ = try await task.value; XCTFail("Cancelled public read cannot return a profile") }
      catch is CancellationError { }
      let state = PublicProfileLoadState()
      let request = PublicProfileLoadID(profileID: id, account: account, retryRevision: UUID())
      await Task { @MainActor in
        await state.load(request: request) {
          withUnsafeCurrentTask { $0?.cancel() }; return full
        }
      }.value
      XCTAssertNil(state.profile); XCTAssertNil(state.message)
      var calls = 0
      await Task { @MainActor in
        withUnsafeCurrentTask { $0?.cancel() }
        await state.load(request: request) { calls += 1; return full }
      }.value
      XCTAssertEqual(calls, 0)
    }
  }
}
