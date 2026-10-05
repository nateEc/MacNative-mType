import Foundation
import XCTest
import XCTVapor
@testable import TypebarServerCore

final class ResultMode2Tests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private var configuration: DailyLeaderboardConfiguration {
    .init(enabled: true, expirationTimeInDays: 2, maxResults: 100,
      validModeRules: [.init(language: ".*", mode: ".*", mode2: ".*")],
      scheduleRewardsModeRules: [.init(language: ".*", mode: ".*", mode2: ".*")],
      xpRewardBrackets: [.init(minRank: 1, maxRank: 1, minReward: 100, maxReward: 100)])
  }
  private func request(mode: String = "quote", mode2: String? = nil, id: UUID = UUID(), at date: Date? = nil) -> ResultSubmissionRequest {
    let end = date ?? now
    return .init(id: id, mode: mode, language: "english", durationSeconds: mode == "time" ? 15 : nil,
      wordLimit: mode == "words" ? 25 : nil, wpm: 60, rawWpm: 60, accuracy: 100,
      errorCount: 0, eventCount: 75, startedAt: end.addingTimeInterval(-15), finishedAt: end, mode2: mode2)
  }
  private func directory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-mode2-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    return directory
  }
  private func store(_ file: URL? = nil) throws -> AuthStore {
    try AuthStore(fileURL: file, bcryptCost: 4, rankingEnvironment: .development, dailyLeaderboardConfiguration: configuration)
  }
  private func account(_ store: AuthStore, at date: Date? = nil) async throws -> AuthSessionResponse {
    try await store.register(.init(email: "mode2@example.com", password: "a secure password", displayName: "Mode Two"), now: date ?? now)
  }
  func testQuotesRemainSeparateAcrossReloadDeletionRetryAndRewardJobs() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("store.json"), first = try store(file), owner = try await account(first)
    let keys = ["typebar:owned-a", "typebar:utf8:e887aae69c892dc3bc", "community:" + UUID().uuidString.lowercased()]
    let inputs = keys.map { request(mode2: $0) }
    for input in inputs {
      let receipt = try await first.submitResult(input, accessToken: owner.accessToken, now: now)
      XCTAssertEqual(receipt.dailyLeaderboardRank, 1)
    }
    let bytes = try Data(contentsOf: file), loaded = try store(file)
    for (key, input) in zip(keys, inputs) {
      let query = LeaderboardQuery(mode: "quote", language: "english", period: "day", mode2: key)
      let page = try await loaded.leaderboard(query, now: now)
      XCTAssertEqual(page.entries.map(\.id), [input.id]); XCTAssertEqual(page.entries.first?.mode2, key)
      let rank = try await loaded.leaderboardRank(query, accessToken: owner.accessToken, now: now)
      let friend = try await loaded.friendLeaderboard(query, accessToken: owner.accessToken, now: now)
      XCTAssertEqual(rank.entry?.id, input.id); XCTAssertEqual(friend.entries.first?.mode2, key)
    }
    XCTAssertEqual(try Data(contentsOf: file), bytes, "Loading and querying must not rewrite old state")
    let history = try await loaded.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    XCTAssertEqual(Set(history.results.compactMap(\.mode2)), Set(keys))
    _ = try await loaded.deleteResults(.init(currentPassword: "a secure password"), accessToken: owner.accessToken, now: now)
    _ = try await loaded.submitResult(request(mode2: "typebar:replacement", id: inputs[0].id), accessToken: owner.accessToken, now: now)
    let replacement = try await loaded.leaderboard(.init(mode: "quote", period: "day", mode2: "typebar:replacement"), now: now)
    XCTAssertTrue(replacement.entries.isEmpty)
    let jobs = await loaded.dailyLeaderboardRewardJobs(); XCTAssertEqual(jobs.count, 3)
    let due = Date(timeIntervalSince1970: Double(jobs[0].nextAttempt) / 1_000)
    let done = try await loaded.processDueDailyLeaderboardRewards(now: due); XCTAssertEqual(done.count, 3)
    let reloaded = try store(file)
    let repeated = try await reloaded.processDueDailyLeaderboardRewards(now: due); XCTAssertTrue(repeated.isEmpty)
    let inbox = try await reloaded.rewardInbox(accessToken: owner.accessToken, now: due); XCTAssertEqual(inbox.inbox.count, 3)
  }
  func testLegacyMissingQuoteIdentityNeverGetsInferredOrBackfilled() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("store.json"), first = try store(file), owner = try await account(first)
    let unknown = request()
    let receipt = try await first.submitResult(unknown, accessToken: owner.accessToken, now: now)
    XCTAssertNil(receipt.dailyLeaderboardRank)
    let loaded = try store(file), bytes = try Data(contentsOf: file)
    _ = try await loaded.submitResult(request(mode2: "typebar:guessed", id: unknown.id), accessToken: owner.accessToken, now: now)
    XCTAssertEqual(try Data(contentsOf: file), bytes)
    let page = try await loaded.leaderboard(.init(mode: "quote", period: "day"), now: now); XCTAssertTrue(page.entries.isEmpty)
    let jobs = await loaded.dailyLeaderboardRewardJobs(); XCTAssertTrue(jobs.isEmpty)
  }
  func testInvalidSubmissionAndQueryIdentityCannotMutateState() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("store.json"), store = try store(file), owner = try await account(store)
    let bytes = try Data(contentsOf: file)
    for (mode, mode2) in [("quote", ""), ("quote", "typebar:a/b"), ("quote", "typebar:"),
      ("quote", "community:bad"), ("quote", "typebar:" + String(repeating: "a", count: 101)),
      ("custom", "zen"), ("zen", "custom"), ("time", "30"), ("words", "025")] {
      do { _ = try await store.submitResult(request(mode: mode, mode2: mode2), accessToken: owner.accessToken, now: now); XCTFail("Invalid \(mode)/\(mode2)") }
      catch { XCTAssertTrue(error is ResultStoreError) }
    }
    for query in [LeaderboardQuery(mode2: "typebar:a"), .init(mode: "quote", mode2: "typebar:a/b"),
      .init(mode: "time", durationSeconds: 15, mode2: "30"), .init(mode: "quote", wordLimit: 25, mode2: "typebar:a")] {
      do { _ = try await store.leaderboard(query, now: now); XCTFail("Invalid query") }
      catch { XCTAssertTrue(error is ResultStoreError) }
    }
    XCTAssertEqual(try Data(contentsOf: file), bytes)
  }
  func testQuoteRankMemoryIsAccountAndPartitionScopedAfterReload() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("store.json"), first = try store(file), owner = try await account(first)
    for key in ["typebar:a", "typebar:b"] {
      let receipt = try await first.recordLeaderboardRankMemory(.init(kind: "speed", scope: "global", period: "day",
        mode: "quote", language: "english", rank: 7, mode2: key), accessToken: owner.accessToken, now: now)
      XCTAssertNil(receipt.previousRank)
    }
    let loaded = try store(file)
    let receipt = try await loaded.recordLeaderboardRankMemory(.init(kind: "speed", scope: "global", period: "day",
      mode: "quote", language: "english", rank: 2, mode2: "typebar:a"), accessToken: owner.accessToken, now: now)
    XCTAssertEqual(receipt.previousRank, 7)
    let general = try await loaded.recordLeaderboardRankMemory(.init(kind: "speed", scope: "global", period: "day",
      mode: "quote", language: "english", rank: 1), accessToken: owner.accessToken, now: now)
    XCTAssertNil(general.previousRank)
  }
  func testExplicitNullWrongTypeAndCorruptStoredIdentityRejectWithoutWriting() async throws {
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request())) as? [String: Any])
    for value: Any in [NSNull(), 7, [:]] {
      var bad = json; bad["mode2"] = value
      XCTAssertThrowsError(try JSONDecoder().decode(ResultSubmissionRequest.self, from: JSONSerialization.data(withJSONObject: bad)))
    }
    let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("store.json"), first = try store(file), owner = try await account(first)
    _ = try await first.submitResult(request(mode2: "typebar:a"), accessToken: owner.accessToken, now: now)
    let original = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    for value: Any in [NSNull(), "typebar:a/b", "typebar:b"] {
      var bad = original, records = try XCTUnwrap(bad["results"] as? [[String: Any]])
      records[0]["mode2"] = value; bad["results"] = records
      let bytes = try JSONSerialization.data(withJSONObject: bad); try bytes.write(to: file)
      XCTAssertThrowsError(try store(file)); XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
  }
  func testHTTPQueryAndCapabilityReachTheActualRoutes() async throws {
    let date = Date.now, store = try store(), owner = try await account(store, at: date)
    let input = request(mode2: "typebar:a", at: date)
    _ = try await store.submitResult(input, accessToken: owner.accessToken, now: date)
    let app = try await Application.make(.testing)
    do {
      try configure(app, authStore: store)
      try await app.test(.GET, "v1/capabilities") { response async throws in
        XCTAssertEqual(try response.content.decode(ServiceCapabilitiesResponse.self).capabilities["resultMode2"], .available)
      }
      for key in ["typebar:a", "typebar:b"] {
        try await app.test(.GET, "v1/leaderboards?period=day&mode=quote&mode2=\(key)") { response async throws in
          XCTAssertEqual(response.status, .ok)
          let page = try response.content.decode(LeaderboardResponse.self)
          XCTAssertTrue(page.mode2FilterSupported)
          XCTAssertEqual(page.entries.map(\.id), key == "typebar:a" ? [input.id] : [])
        }
      }
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }

  func testCustomAndZenReachConfiguredDailyBucketsAndSettlement() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4, rankingEnvironment: .development,
      dailyLeaderboardConfiguration: configuration)
    let owner = try await store.register(.init(email: "mode2@example.com",
      password: "a secure password", displayName: "Mode Two"), now: now)
    for mode in ["custom", "zen"] {
      let request = ResultSubmissionRequest(id: UUID(), mode: mode, language: "english",
        durationSeconds: nil, wordLimit: nil, wpm: 60, rawWpm: 60, accuracy: 100,
        errorCount: 0, eventCount: 75, startedAt: now.addingTimeInterval(-15), finishedAt: now)
      let receipt = try await store.submitResult(request, accessToken: owner.accessToken, now: now)
      XCTAssertEqual(receipt.dailyLeaderboardRank, 1, mode)
      let page = try await store.leaderboard(.init(mode: mode, language: "english", period: "day"), now: now)
      XCTAssertEqual(page.entries.map(\.id), [request.id], mode)
    }
    let jobs = await store.dailyLeaderboardRewardJobs()
    XCTAssertEqual(Set(jobs.map { $0.modeRule.mode2 }), ["custom", "zen"])
    let due = Date(timeIntervalSince1970: Double(try DailyLeaderboardCache.key(at: now) + 86_460_000) / 1_000)
    let settled = try await store.processDueDailyLeaderboardRewards(now: due)
    XCTAssertEqual(settled.count, 2)
    let inbox = try await store.rewardInbox(accessToken: owner.accessToken, now: due)
    XCTAssertEqual(inbox.inbox.count, 2)
  }
}
