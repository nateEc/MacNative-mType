import Foundation
import XCTest
import XCTVapor
@testable import TypebarServerCore

final class LeaderboardMinimumSpeedTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private let password = "a secure password"
  private func store(file: URL? = nil, capacity: Int = 100) throws -> AuthStore {
    try AuthStore(fileURL: file, bcryptCost: 4, rankingEnvironment: .development,
      dailyLeaderboardConfiguration: .init(enabled: true, expirationTimeInDays: 2,
        maxResults: capacity, validModeRules: DailyLeaderboardConfiguration.typebarDefault.validModeRules))
  }
  private func account(_ store: AuthStore, _ name: String) async throws -> AuthSessionResponse {
    try await store.register(.init(email: name.lowercased() + "@example.com", password: password,
      displayName: name), now: now)
  }
  private func input(_ speed: Int, words: Int = 25) -> ResultSubmissionRequest {
    .init(id: UUID(), mode: "words", language: "english", durationSeconds: nil, wordLimit: words,
      wpm: speed, rawWpm: speed, accuracy: 100, errorCount: 0, eventCount: 75,
      startedAt: now.addingTimeInterval(-900 / Double(speed)), finishedAt: now)
  }
  private func query(_ period: String = "day", offset: Int = 0, words: Int = 25) -> LeaderboardQuery {
    .init(mode: "words", language: "english", period: period, wordLimit: words, limit: 1, offset: offset)
  }
  private func minimum(_ page: LeaderboardResponse) throws -> Double? {
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(page)) as? [String: Any])
    return json["minWpm"] as? Double
  }
  func testMinimumUsesWholePartitionNotCurrentOrOutOfRangePage() async throws {
    let store = try store()
    for (name, speed) in [("High", 80), ("Middle", 60), ("Low", 40)] {
      let owner = try await account(store, name)
      _ = try await store.submitResult(input(speed), accessToken: owner.accessToken, now: now)
    }
    for offset in [0, 1, 2, 999] {
      let page = try await store.leaderboard(query(offset: offset), now: now)
      XCTAssertEqual(try minimum(page), 40)
    }
    let yesterday = try await store.leaderboard(query("yesterday"), now: now.addingTimeInterval(86_400))
    XCTAssertEqual(try minimum(yesterday), 40)
    let today = try await store.leaderboard(query(), now: now.addingTimeInterval(86_400))
    XCTAssertEqual(try minimum(today), 0)
  }
  func testFriendMinimumIsScopedEvenWhenGlobalTailIsSlower() async throws {
    let store = try store(), owner = try await account(store, "Owner")
    let friend = try await account(store, "Friend"), outsider = try await account(store, "Outsider")
    _ = try await store.sendConnection(.init(recipientID: friend.user.id), accessToken: owner.accessToken, now: now)
    _ = try await store.acceptConnection(requesterID: owner.user.id, accessToken: friend.accessToken, now: now)
    for (account, speed) in [(owner, 80), (friend, 60), (outsider, 40)] {
      _ = try await store.submitResult(input(speed), accessToken: account.accessToken, now: now)
    }
    let global = try await store.leaderboard(query(), now: now)
    XCTAssertEqual(try minimum(global), 40)
    for offset in [0, 999] {
      let page = try await store.friendLeaderboard(query(offset: offset), accessToken: owner.accessToken, now: now)
      XCTAssertEqual(try minimum(page), 60)
    }
    let emptyOwner = try await account(store, "Empty")
    let empty = try await store.friendLeaderboard(query(), accessToken: emptyOwner.accessToken, now: now)
    XCTAssertEqual(try minimum(empty), 0)
  }
  func testParameterBucketsAndHistoricalFallbackDoNotInventADailyMinimum() async throws {
    let store = try store(), owner = try await account(store, "Parameters")
    _ = try await store.submitResult(input(80), accessToken: owner.accessToken, now: now)
    _ = try await store.submitResult(input(20, words: 10), accessToken: owner.accessToken, now: now)
    let first = try await store.leaderboard(query(), now: now)
    let other = try await store.leaderboard(query(words: 10), now: now)
    XCTAssertEqual(try minimum(first), 80); XCTAssertEqual(try minimum(other), 20)
    for period in ["all", "week"] {
      let page = try await store.leaderboard(query(period), now: now)
      XCTAssertNil(try minimum(page))
    }
    let legacy = try AuthStore(fileURL: nil, bcryptCost: 4, rankingEnvironment: .development)
    let oldOwner = try await account(legacy, "Legacy")
    _ = try await legacy.submitResult(input(40), accessToken: oldOwner.accessToken, now: now)
    let page = try await legacy.leaderboard(query(), now: now)
    XCTAssertEqual(page.entries.first?.wpm, 40); XCTAssertNil(try minimum(page))
  }
  func testCacheTailSurvivesHistoryDeletionReloadAndReadWithoutFileWrites() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-minimum-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("state.json"), first = try store(file: file)
    let owner = try await account(first, "Stored")
    _ = try await first.submitResult(input(60), accessToken: owner.accessToken, now: now)
    _ = try await first.deleteResults(.init(currentPassword: password), accessToken: owner.accessToken, now: now)
    let bytes = try Data(contentsOf: file), loaded = try store(file: file)
    let page = try await loaded.leaderboard(query(offset: 999), now: now)
    XCTAssertEqual(try minimum(page), 60)
    XCTAssertEqual(try Data(contentsOf: file), bytes)
    let expired = try await loaded.leaderboard(query(), now: now.addingTimeInterval(3 * 86_400))
    XCTAssertEqual(try minimum(expired), 0)
    XCTAssertEqual(try Data(contentsOf: file), bytes)
  }
  func testEvictionAndPrivacyPurgeChangeTheLiveTailNotSubmissionAcceptance() async throws {
    let store = try store(capacity: 2), high = try await account(store, "High")
    let middle = try await account(store, "Middle"), low = try await account(store, "Low")
    for (account, speed) in [(high, 80), (middle, 60), (low, 40)] {
      let receipt = try await store.submitResult(input(speed), accessToken: account.accessToken, now: now)
      XCTAssertGreaterThan(receipt.totalExperience, 0)
    }
    let full = try await store.leaderboard(query(), now: now)
    XCTAssertEqual(try minimum(full), 60)
    _ = try await store.updateProfile(.init(leaderboardOptedOut: true), accessToken: middle.accessToken, now: now)
    let purged = try await store.leaderboard(query(), now: now)
    XCTAssertEqual(try minimum(purged), 80)
  }
  func testHTTPResponsesCarryDailyTailButOmitItFromAllTime() async throws {
    let date = Date.now, store = try store()
    let owner = try await store.register(.init(email: "http-minimum@example.com", password: password,
      displayName: "HTTP Minimum"), now: date)
    let value = ResultSubmissionRequest(id: UUID(), mode: "words", language: "english",
      durationSeconds: nil, wordLimit: 25, wpm: 60, rawWpm: 60, accuracy: 100,
      errorCount: 0, eventCount: 75, startedAt: date.addingTimeInterval(-15), finishedAt: date)
    _ = try await store.submitResult(value, accessToken: owner.accessToken, now: date)
    let app = try await Application.make(.testing)
    do {
      try configure(app, authStore: store)
      for suffix in ["", "/friends"] {
        try await app.test(.GET, "v1/leaderboards\(suffix)?period=day&mode=words&wordLimit=25&offset=999",
          beforeRequest: { request in request.headers.bearerAuthorization = .init(token: owner.accessToken) }) { response async throws in
          XCTAssertEqual(response.status, .ok)
          XCTAssertEqual(try minimum(response.content.decode(LeaderboardResponse.self)), 60)
        }
      }
      try await app.test(.GET, "v1/leaderboards?period=all") { response async throws in
        XCTAssertEqual(response.status, .ok)
        XCTAssertNil(try minimum(response.content.decode(LeaderboardResponse.self)))
      }
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }
}
