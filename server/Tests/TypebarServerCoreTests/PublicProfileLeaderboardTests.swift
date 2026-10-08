import Foundation
import XCTest
import XCTVapor
@testable import TypebarServerCore

final class PublicProfileLeaderboardTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private func account(_ store: AuthStore, _ name: String) async throws -> AuthSessionResponse {
    try await store.register(.init(email: "\(name)@example.com", password: "a secure password",
      displayName: name), now: now)
  }
  private func submit(_ store: AuthStore, _ account: AuthSessionResponse, seconds: Int, speed: Int,
    language: String = "english", lazy: Bool = false) async throws {
    let units = speed * seconds / 12
    let request = ResultSubmissionRequest(id: UUID(), mode: "time", language: language, durationSeconds: seconds, wordLimit: nil,
      wpm: speed, rawWpm: speed, accuracy: 100, consistency: 80, errorCount: 0, eventCount: units,
      personalBestConfiguration: .init(difficulty: "normal", punctuation: false, numbers: false, lazyMode: lazy),
      startedAt: now.addingTimeInterval(-Double(seconds)), finishedAt: now)
    _ = try await store.submitResult(request, accessToken: account.accessToken, now: now)
  }
  private func json(_ profile: PublicProfileResponse) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
  }
  private func rank(_ json: [String: Any], _ seconds: String) -> [String: Int]? {
    let all = json["allTimeLbs"] as? [String: Any], time = all?["time"] as? [String: Any]
    return (time?[seconds] as? [String: Any])?["english"] as? [String: Int]
  }

  func testDetailedProfileUsesWholeIndependentEnglishBoardsNotHistoryOrPageSize() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4, rankingEnvironment: .development)
    let owner = try await account(store, "Owner"), other = try await account(store, "Other")
    try await submit(store, owner, seconds: 15, speed: 60)
    try await submit(store, other, seconds: 15, speed: 120)
    try await submit(store, owner, seconds: 60, speed: 120)
    try await submit(store, other, seconds: 60, speed: 60)
    _ = try await store.deleteResults(.init(currentPassword: "a secure password"), accessToken: owner.accessToken, now: now)
    let profile = try await store.publicProfile(id: owner.user.id, now: now), encoded = try json(profile)
    XCTAssertEqual(rank(encoded, "15"), ["rank": 2, "count": 2])
    XCTAssertEqual(rank(encoded, "60"), ["rank": 1, "count": 2])
    for seconds in [15, 60] {
      let board = try await store.leaderboard(.init(mode: "time", language: "english", period: "all",
        durationSeconds: seconds, limit: 1), now: now)
      XCTAssertEqual(board.total, 2); XCTAssertEqual(board.entries.count, 1)
    }
    let light = try await store.searchPublicProfiles(query: "Owner", limit: 10)
    XCTAssertNil(try json(XCTUnwrap(light.profiles.first))["allTimeLbs"], "Search must stay lightweight")
  }

  func testOptOutAndSuspensionSuppressRanksAndOptOutRemainsPublic() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4, rankingEnvironment: .development)
    let owner = try await account(store, "Owner")
    try await submit(store, owner, seconds: 15, speed: 60)
    _ = try await store.updateProfile(.init(leaderboardOptedOut: true), accessToken: owner.accessToken, now: now)
    let hidden = try await store.publicProfile(id: owner.user.id, now: now), encoded = try json(hidden)
    XCTAssertEqual(encoded["leaderboardOptedOut"] as? Bool, true)
    XCTAssertNil(encoded["allTimeLbs"])
    _ = try await store.updateProfile(.init(leaderboardOptedOut: false), accessToken: owner.accessToken, now: now)
    let notRestored = try await store.publicProfile(id: owner.user.id, now: now)
    XCTAssertNil(rank(try json(notRestored), "15"), "Opting in must not resurrect a cleared leaderboard PB")
    try await submit(store, owner, seconds: 15, speed: 120)
    let restored = try await store.publicProfile(id: owner.user.id, now: now)
    XCTAssertEqual(rank(try json(restored), "15"), ["rank": 1, "count": 1])
    _ = try await store.setAccountSuspended(userID: owner.user.id, suspended: true, now: now)
    let suspended = try await store.publicProfile(id: owner.user.id, now: now)
    XCTAssertNil(try json(suspended)["allTimeLbs"])
  }

  func testOtherOwnersEligibilityChangesBothRankAndPopulation() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4, rankingEnvironment: .development)
    let owner = try await account(store, "Owner"), faster = try await account(store, "Faster"), fastest = try await account(store, "Fastest")
    for (user, speed) in [(owner, 60), (faster, 120), (fastest, 180)] {
      try await submit(store, user, seconds: 15, speed: speed)
    }
    let first = try await store.publicProfile(id: owner.user.id, now: now)
    XCTAssertEqual(rank(try json(first), "15"), ["rank": 3, "count": 3])
    _ = try await store.updateProfile(.init(leaderboardOptedOut: true), accessToken: fastest.accessToken, now: now)
    let second = try await store.publicProfile(id: owner.user.id, now: now)
    XCTAssertEqual(rank(try json(second), "15"), ["rank": 2, "count": 2])
    _ = try await store.setLeaderboardRestricted(userID: faster.user.id, restricted: true)
    let third = try await store.publicProfile(id: owner.user.id, now: now)
    XCTAssertEqual(rank(try json(third), "15"), ["rank": 1, "count": 1])
  }

  func testUnrankedPersonalBestsDoNotBecomeEnglishLeaderboardPositions() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4, rankingEnvironment: .development)
    let owner = try await account(store, "OnlyPB")
    try await submit(store, owner, seconds: 30, speed: 60)
    try await submit(store, owner, seconds: 15, speed: 60, language: "german")
    try await submit(store, owner, seconds: 15, speed: 120, lazy: true)
    let profile = try await store.publicProfile(id: owner.user.id, now: now), encoded = try json(profile)
    XCTAssertEqual(profile.personalBestSnapshots?.count, 3)
    XCTAssertNotNil(encoded["allTimeLbs"])
    XCTAssertNil(rank(encoded, "15")); XCTAssertNil(rank(encoded, "60"))
  }

  func testStrictPracticeMinimumMatchesExistingLeaderboardEligibility() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4, minimumLeaderboardTypingSeconds: 60, rankingEnvironment: .production)
    let owner = try await account(store, "Boundary")
    try await submit(store, owner, seconds: 60, speed: 60)
    let atMinimum = try await store.publicProfile(id: owner.user.id, now: now)
    XCTAssertNil(rank(try json(atMinimum), "60"))
    try await submit(store, owner, seconds: 15, speed: 60)
    let eligible = try await store.publicProfile(id: owner.user.id, now: now)
    XCTAssertEqual(rank(try json(eligible), "15"), ["rank": 1, "count": 1])
    XCTAssertEqual(rank(try json(eligible), "60"), ["rank": 1, "count": 1])
  }

  func testActualPublicHTTPReturnsOnlyRankingSummaryWithoutCredentials() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4, rankingEnvironment: .development)
    let owner = try await account(store, "HTTP")
    try await submit(store, owner, seconds: 15, speed: 60)
    let app = try await Application.make(.testing)
    do {
      try configure(app, authStore: store)
      try await app.test(.GET, "v1/profiles/\(owner.user.id)") { response async throws in
        XCTAssertEqual(response.status, .ok)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
        XCTAssertEqual(self.rank(body, "15"), ["rank": 1, "count": 1])
        XCTAssertEqual(body["leaderboardOptedOut"] as? Bool, false)
        for key in ["email", "accessToken", "passwordHash", "rankingEvidence", "eventCount", "replayEvents"] {
          XCTAssertNil(body[key])
        }
      }
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }
}
