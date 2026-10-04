import XCTVapor
import XCTest
@testable import TypebarServerCore

final class BailoutSubmissionTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 41_000)

  private func account(file: URL? = nil) async throws -> (AuthStore, AuthSessionResponse) {
    let store = try AuthStore(fileURL: file, bcryptCost: 4, minimumLeaderboardTypingSeconds: 0)
    let user = try await store.register(.init(email: "bailout@example.com",
      password: "a secure password", displayName: "Bailout Tests"), now: now)
    return (store, user)
  }

  private func request(mode: String = "time", limit: Int = 60, measured: Double = 15,
    units: Int = 100, errors: Int = 0, bailedOut: Bool? = true,
    custom: [String: Any]? = nil, id: UUID = UUID()) throws -> ResultSubmissionRequest {
    let wall = measured + 1
    let speed = Int((Double(units - errors) / 5 / measured * 60).rounded())
    let base = ResultSubmissionRequest(id: id, mode: mode, language: "english",
      durationSeconds: mode == "time" ? limit : nil, wordLimit: mode == "words" ? limit : nil,
      wpm: speed, rawWpm: Int((Double(units) / 5 / measured * 60).rounded()),
      accuracy: Int((Double(units - errors) / Double(units) * 100).rounded()),
      errorCount: errors, eventCount: units,
      startedAt: now.addingTimeInterval(-wall), finishedAt: now)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as? [String: Any])
    object["bailedOut"] = bailedOut
    object["customLimit"] = custom
    object["terminalTiming"] = ["version": 1, "endMilliseconds": wall * 1_000,
      "lastKeypressMilliseconds": measured * 1_000]
    return try JSONDecoder().decode(ResultSubmissionRequest.self,
      from: JSONSerialization.data(withJSONObject: object))
  }

  private func rejects(_ input: ResultSubmissionRequest, store: AuthStore, token: String) async throws {
    do {
      _ = try await store.submitResult(input, accessToken: token, now: now)
      XCTFail("Invalid BailOut must not be saved: \(input.mode)")
    } catch let error as ResultStoreError { XCTAssertEqual(error, .invalidResult) }
  }

  func testTimeBailoutKeepsPracticeAndXPButCannotBecomePBOrSpeedRank() async throws {
    let (store, user) = try await account()
    let receipt = try await store.submitResult(request(), accessToken: user.accessToken, now: now)
    XCTAssertTrue(receipt.accepted)
    XCTAssertFalse(receipt.leaderboardEligible)
    XCTAssertNil(receipt.dailyLeaderboardRank)
    XCTAssertEqual(receipt.experienceGained, 18, "XP uses actual 15 s, not configured 60 s")
    XCTAssertNotNil(receipt.weeklyExperienceRank)
    let profile = try await store.publicProfile(id: user.user.id, now: now)
    XCTAssertEqual(profile.bestWPM, 0)
    XCTAssertTrue(profile.personalBests.isEmpty)
    XCTAssertEqual(profile.completedResultCount, 1)
    XCTAssertEqual(profile.totalTypingSeconds, 15)
    XCTAssertFalse(profile.earnedBadges.contains { $0.id == "first-finish" || $0.id == "swift-line" })
    for period in ["all", "day", "yesterday", "week"] {
      let board = try await store.leaderboard(.init(mode: nil, language: nil, period: period, limit: nil), now: now)
      XCTAssertTrue(board.entries.isEmpty)
    }
    let distribution = await store.publicEnglishMinuteSpeedDistribution()
    XCTAssertTrue(distribution.buckets.isEmpty)
    let totals = await store.publicPracticeStats()
    XCTAssertEqual(totals.completedResultCount, 1)
    XCTAssertEqual(totals.totalTypingSeconds, 15)
  }

  func testBackendMinimumsAreDistinctFromLocalSavingMinimums() async throws {
    let (store, user) = try await account()
    for mode in ["time", "words", "custom", "zen"] {
      try await rejects(request(mode: mode, limit: 10, measured: 14.99,
        custom: mode == "custom" ? ["mode": "none", "value": 0] : nil), store: store, token: user.accessToken)
      let receipt = try await store.submitResult(request(mode: mode, limit: mode == "time" ? 15 : 10,
        custom: mode == "custom" ? ["mode": "none", "value": 0] : nil), accessToken: user.accessToken, now: now)
      XCTAssertTrue(receipt.accepted)
      if mode == "zen" { XCTAssertEqual(receipt.experienceGained, 0) }
    }
    let quote = try await store.submitResult(request(mode: "quote", measured: 1, units: 1), accessToken: user.accessToken, now: now)
    XCTAssertTrue(quote.accepted)
    for (mode, limit) in [("time", 14), ("words", 9)] {
      try await rejects(request(mode: mode, limit: limit), store: store, token: user.accessToken)
    }
    for mode in ["time", "words"] {
      let unlimited = try await store.submitResult(request(mode: mode, limit: 0), accessToken: user.accessToken, now: now)
      XCTAssertTrue(unlimited.accepted)
    }
  }

  func testCustomLimitIsAnonymousRequiredAndModeBound() async throws {
    let (store, user) = try await account()
    for (mode, minimum) in [("word", 10), ("section", 10), ("time", 15), ("none", 0)] {
      let input = try request(mode: "custom", custom: ["mode": mode, "value": minimum])
      let receipt = try await store.submitResult(input, accessToken: user.accessToken, now: now)
      XCTAssertTrue(receipt.accepted)
      if minimum > 0 {
        try await rejects(request(mode: "custom", custom: ["mode": mode, "value": minimum - 1]), store: store, token: user.accessToken)
      }
    }
    for custom: [String: Any]? in [nil, ["mode": "words", "value": 10], ["mode": "none", "value": 1],
      ["mode": "word", "value": -1], ["mode": "word", "value": Int.max]] {
      try await rejects(request(mode: "custom", custom: custom), store: store, token: user.accessToken)
    }
    try await rejects(request(custom: ["mode": "none", "value": 0]), store: store, token: user.accessToken)
    try await rejects(request(bailedOut: nil), store: store, token: user.accessToken)
    try await rejects(request(bailedOut: false), store: store, token: user.accessToken)
  }

  func testCustomMinimumUsesUnroundedClock() async throws {
    let (store, user) = try await account()
    try await rejects(request(mode: "custom", measured: 14.999,
      custom: ["mode": "none", "value": 0]), store: store, token: user.accessToken)
    let receipt = try await store.submitResult(request(mode: "custom", measured: 15.001,
      custom: ["mode": "none", "value": 0]), accessToken: user.accessToken, now: now)
    XCTAssertTrue(receipt.accepted)
  }

  func testAccuracyUsesAuthenticatedOptOutAndSpeedCeilingIs420() async throws {
    let (store, user) = try await account()
    try await rejects(request(errors: 26), store: store, token: user.accessToken)
    _ = try await store.updateProfile(.init(leaderboardOptedOut: true), accessToken: user.accessToken, now: now)
    let low = try await store.submitResult(request(errors: 26), accessToken: user.accessToken, now: now)
    XCTAssertTrue(low.accepted)
    let ceiling = try await store.submitResult(request(units: 525), accessToken: user.accessToken, now: now)
    XCTAssertTrue(ceiling.accepted)
    try await rejects(request(units: 527), store: store, token: user.accessToken)
    try await rejects(request(units: 527, errors: 27), store: store, token: user.accessToken)
  }

  func testMixedPersistenceAndDuplicateCannotEraseBailoutSemantics() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-bailout-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: file) }
    let (store, user) = try await account(file: file)
    let input = try request(mode: "custom", measured: 15.125, custom: ["mode": "none", "value": 0])
    let receipt = try await store.submitResult(input, accessToken: user.accessToken, now: now)
    let completed = ResultSubmissionRequest(id: UUID(), mode: "time", language: "english",
      durationSeconds: 60, wordLimit: nil, wpm: 20, rawWpm: 20, accuracy: 100,
      errorCount: 0, eventCount: 100, startedAt: now.addingTimeInterval(-60), finishedAt: now)
    _ = try await store.submitResult(completed, accessToken: user.accessToken, now: now)
    let reloaded = try AuthStore(fileURL: file, bcryptCost: 4, minimumLeaderboardTypingSeconds: 0)
    let duplicate = try await reloaded.submitResult(input, accessToken: user.accessToken, now: now)
    XCTAssertEqual(duplicate, receiptWithTotal(receipt, total: 90))
    let history = try await reloaded.results(.init(), credential: .accessToken(user.accessToken), now: now)
    XCTAssertEqual(history.total, 2)
    let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(history)) as? [String: Any])
    let records = try XCTUnwrap(encoded["results"] as? [[String: Any]])
    let bailout = try XCTUnwrap(records.first { ($0["id"] as? String)?.lowercased() == input.id.uuidString.lowercased() })
    XCTAssertEqual(bailout["bailedOut"] as? Bool, true)
    XCTAssertEqual(bailout["customLimit"] as? NSDictionary, ["mode": "none", "value": 0] as NSDictionary)
    XCTAssertNil(records.first { ($0["id"] as? String)?.lowercased() == completed.id.uuidString.lowercased() }?["bailedOut"])
    let profile = try await reloaded.publicProfile(id: user.user.id, now: now)
    XCTAssertEqual(profile.bestWPM, 20)
    XCTAssertEqual(profile.personalBests.map(\.wpm), [20])
    let spoofedCompleted = ResultSubmissionRequest(id: input.id, mode: "time", language: "english",
      durationSeconds: 60, wordLimit: nil, wpm: 20, rawWpm: 20, accuracy: 100,
      errorCount: 0, eventCount: 100, startedAt: now.addingTimeInterval(-60), finishedAt: now)
    let originalReceipt = try await reloaded.submitResult(spoofedCompleted, accessToken: user.accessToken, now: now)
    XCTAssertFalse(originalReceipt.leaderboardEligible)
    XCTAssertNil(originalReceipt.dailyLeaderboardRank, "Even an existing completed rank cannot leak into BailOut receipt")
    XCTAssertEqual(originalReceipt.experienceGained, receipt.experienceGained)
    var stored = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    var rows = try XCTUnwrap(stored["results"] as? [[String: Any]])
    let index = try XCTUnwrap(rows.firstIndex { ($0["id"] as? String)?.lowercased() == input.id.uuidString.lowercased() })
    rows[index]["bailedOut"] = false
    stored["results"] = rows
    try JSONSerialization.data(withJSONObject: stored).write(to: file, options: .atomic)
    XCTAssertThrowsError(try AuthStore(fileURL: file, bcryptCost: 4), "Malformed explicit context cannot reload as completed")
  }

  private func receiptWithTotal(_ receipt: ResultSubmissionResponse, total: Int) -> ResultSubmissionResponse {
    .init(id: receipt.id, accepted: receipt.accepted, leaderboardEligible: receipt.leaderboardEligible,
      dailyLeaderboardRank: receipt.dailyLeaderboardRank, experienceGained: receipt.experienceGained,
      totalExperience: total, weeklyExperienceRank: receipt.weeklyExperienceRank)
  }

  func testFriendsSpeedBoardAndNewPBEpochExcludeBailoutButKeepPractice() async throws {
    let (store, user) = try await account()
    let friend = try await store.register(.init(email: "bailout-friend@example.com",
      password: "a secure password", displayName: "Bailout Friend"), now: now)
    _ = try await store.sendConnection(.init(recipientID: friend.user.id), accessToken: user.accessToken, now: now)
    _ = try await store.acceptConnection(requesterID: user.user.id, accessToken: friend.accessToken, now: now)
    _ = try await store.resetPersonalBests(.init(currentPassword: "a secure password"), accessToken: user.accessToken, now: now)
    _ = try await store.submitResult(request(), accessToken: user.accessToken, now: now.addingTimeInterval(1))
    _ = try await store.submitResult(request(), accessToken: friend.accessToken, now: now.addingTimeInterval(1))
    let board = try await store.friendLeaderboard(.init(mode: nil, language: nil, period: "all", limit: nil),
      accessToken: user.accessToken, now: now.addingTimeInterval(1))
    XCTAssertTrue(board.entries.isEmpty)
    let profile = try await store.publicProfile(id: user.user.id, now: now.addingTimeInterval(1))
    XCTAssertTrue(profile.personalBests.isEmpty)
    XCTAssertEqual(profile.completedResultCount, 1)
    XCTAssertEqual(profile.totalTypingSeconds, 15)
    XCTAssertEqual(profile.activity?.testsByDays.reduce(0, +), 1)
  }

  func testPreciseAccuracyCannotBeRescuedByRoundedIntegerWire() async throws {
    let (store, user) = try await account()
    for correct in [746, 749, 750] {
      let input = ResultSubmissionRequest(id: UUID(), mode: "time", language: "english",
        durationSeconds: 60, wordLimit: nil, wpm: 80, rawWpm: 80, accuracy: 75,
        errorCount: 0, eventCount: 100,
        inputMetrics: .init(version: 1, correctAttempts: correct, totalAttempts: 1_000,
          creditedUnits: 100, retainedUnits: 100),
        terminalTiming: .init(version: 1, endMilliseconds: 16_000, lastKeypressMilliseconds: 15_000),
        bailedOut: true, startedAt: now.addingTimeInterval(-16), finishedAt: now)
      if correct < 750 { try await rejects(input, store: store, token: user.accessToken) }
      else {
        let receipt = try await store.submitResult(input, accessToken: user.accessToken, now: now)
        XCTAssertTrue(receipt.accepted)
      }
    }
  }

  func testLegacyCountAccuracyUsesSourceTwoDecimalBoundaryNotRawRatio() async throws {
    let (store, user) = try await account()
    let accepted = try await store.submitResult(request(limit: 3_600, measured: 1_200,
      units: 40_000, errors: 10_001), accessToken: user.accessToken, now: now)
    XCTAssertTrue(accepted.accepted, "74.9975 rounds to source 75.00 before backend qualification")
    try await rejects(request(limit: 3_600, measured: 1_200, units: 40_000, errors: 10_003),
      store: store, token: user.accessToken)
  }

  func testHTTPAdvertisesExplicitCapabilityAndPersistsBailout() async throws {
    let app = try await Application.make(.testing)
    let (store, _) = try await account()
    do {
      try configure(app, authStore: store)
      try await app.test(.GET, "v1/capabilities") { response async throws in
        XCTAssertEqual(try response.content.decode(ServiceCapabilitiesResponse.self).capabilities["resultBailout"], .available)
      }
      // Store clock is fixed in the past; routes use real now, so construct current dates.
      let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
      var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(request())) as? [String: Any])
      let clock = ISO8601DateFormatter()
      object["startedAt"] = clock.string(from: Date.now.addingTimeInterval(-16))
      object["finishedAt"] = clock.string(from: Date.now)
      let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
      let input = try decoder.decode(ResultSubmissionRequest.self, from: JSONSerialization.data(withJSONObject: object))
      // A newly registered route account has a live access token.
      let live = try await store.register(.init(email: "live-bailout@example.com",
        password: "a secure password", displayName: "Live Bailout"))
      try await app.test(.POST, "v1/results", beforeRequest: { outgoing async throws in
        outgoing.headers.bearerAuthorization = .init(token: live.accessToken)
        try outgoing.content.encode(input)
      }, afterResponse: { response async throws in
        XCTAssertEqual(response.status, .ok)
        if response.status == .ok { XCTAssertFalse(try response.content.decode(ResultSubmissionResponse.self).leaderboardEligible) }
      })
      try await app.test(.GET, "v1/results", beforeRequest: { outgoing async in
        outgoing.headers.bearerAuthorization = .init(token: live.accessToken)
      }, afterResponse: { response async throws in
        XCTAssertEqual(response.status, .ok)
        let history = try response.content.decode(ResultListResponse.self)
        XCTAssertEqual(history.total, 1)
        XCTAssertEqual(history.results.first?.bailedOut, true)
        XCTAssertEqual(history.results.first?.terminalTiming?.duration(mode: "time"), 15)
      })
      object["id"] = UUID().uuidString
      object["terminalTiming"] = ["version": 1, "endMilliseconds": 16_000,
        "lastKeypressMilliseconds": 14_990]
      let tooShort = try decoder.decode(ResultSubmissionRequest.self, from: JSONSerialization.data(withJSONObject: object))
      try await app.test(.POST, "v1/results", beforeRequest: { outgoing async throws in
        outgoing.headers.bearerAuthorization = .init(token: live.accessToken)
        try outgoing.content.encode(tooShort)
      }, afterResponse: { response async in XCTAssertEqual(response.status, .badRequest) })
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }
}
