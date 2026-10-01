import XCTVapor
import XCTest
@testable import TypebarServerCore

final class InputMetricsSubmissionTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 39_000)

  func testCorrectedResultUsesAttemptsInsteadOfResidualErrors() async throws {
    let (store, token) = try await account()
    let request = try result(accuracy: 75, wpm: 2, raw: 2, events: 3, errors: 0,
      metrics: metrics(correct: 3, total: 4, credited: 3, retained: 3))
    let receipt = try await store.submitResult(request, accessToken: token, now: now)
    XCTAssertTrue(receipt.accepted)
    let page = try await store.results(.init(), credential: .accessToken(token), now: now)
    XCTAssertEqual(try object(try XCTUnwrap(page.results.first))["preciseAccuracy"] as? Double, 75)
  }

  func testUnicodeAccuracyAndWrongWholeWordCreditAreIndependent() async throws {
    let (store, token) = try await account()
    let request = try result(accuracy: 67, wpm: 0, raw: 2, events: 2, errors: 1,
      metrics: metrics(correct: 2, total: 3, credited: 0, retained: 3))
    _ = try await store.submitResult(request, accessToken: token, now: now)
    let page = try await store.results(.init(), credential: .accessToken(token), now: now)
    XCTAssertEqual(try object(try XCTUnwrap(page.results.first))["preciseAccuracy"] as? Double, 66.67)
  }

  func testEveryWrongWordCanLoseCreditWithoutLosingAllCorrectAttempts() async throws {
    let (store, token) = try await account()
    let request = try result(accuracy: 83, wpm: 0, raw: 80, events: 100, errors: 17,
      metrics: metrics(correct: 83, total: 100, credited: 0, retained: 100))
    let receipt = try await store.submitResult(request, accessToken: token, now: now)
    XCTAssertTrue(receipt.accepted)
  }

  func testUnknownAndInconsistentMetricsCannotBypassLegacyValidation() async throws {
    let (store, token) = try await account()
    var invalid = [metrics(correct: 3, total: 3, credited: 3, retained: 3)]
    invalid[0]["version"] = 2
    invalid.append(metrics(correct: 4, total: 3, credited: 3, retained: 3))
    invalid.append(metrics(correct: -1, total: 3, credited: 3, retained: 3))
    invalid.append(metrics(correct: 3, total: 2, credited: 3, retained: 3))
    invalid.append(metrics(correct: 3, total: 3, credited: 4, retained: 3))
    invalid.append(metrics(correct: 3, total: 3, credited: 3, retained: 2))
    invalid.append(metrics(correct: 2_000_000, total: 2_000_000, credited: 3, retained: 3))
    invalid.append(metrics(correct: Int.max, total: Int.max, credited: 3, retained: 3))
    invalid.append(metrics(correct: 2, total: 3, credited: 3, retained: 3))
    invalid.append(metrics(correct: 3, total: 3, credited: 0, retained: 3))
    invalid.append(metrics(correct: 20, total: 20, credited: 3, retained: 20))
    for value in invalid {
      do {
        _ = try await store.submitResult(try result(accuracy: 100, wpm: 2, raw: 2,
          events: 3, errors: 0, metrics: value), accessToken: token, now: now)
        XCTFail("Invalid input metrics must not be silently ignored: \(value)")
      } catch let error as ResultStoreError { XCTAssertEqual(error, .invalidResult) }
    }
  }

  func testLegacyIntegerRequestRemainsValidAndDoesNotInventPrecision() async throws {
    let (store, token) = try await account()
    _ = try await store.submitResult(try result(accuracy: 100, wpm: 2, raw: 2,
      events: 3, errors: 0, metrics: nil), accessToken: token, now: now)
    let page = try await store.results(.init(), credential: .accessToken(token), now: now)
    XCTAssertNil(try object(try XCTUnwrap(page.results.first))["preciseAccuracy"])
  }

  private func account() async throws -> (AuthStore, String) {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4, minimumLeaderboardTypingSeconds: 0)
    let session = try await store.register(.init(email: "metrics@example.com", password: "a secure password",
      displayName: "Metrics"), now: now)
    return (store, session.accessToken)
  }

  func testRoundedHundredIsNotPerfectForExperience() throws {
    let request = try result(accuracy: 100, wpm: 80, raw: 80, events: 100, errors: 0,
      metrics: metrics(correct: 249, total: 250, credited: 100, retained: 100))
    XCTAssertEqual(TypebarExperiencePolicy.points(for: request), 15)
  }

  func testLeaderboardTieUsesPreciseAccuracyAndExposesItWithoutCounters() async throws {
    let (store, lowerToken) = try await account()
    let higher = try await store.register(.init(email: "higher@example.com", password: "a secure password",
      displayName: "Higher"), now: now)
    _ = try await store.submitResult(try result(accuracy: 100, wpm: 80, raw: 80, events: 100, errors: 0,
      metrics: metrics(correct: 249, total: 250, credited: 100, retained: 100)),
      accessToken: lowerToken, now: now)
    var olderJSON = try object(try result(accuracy: 100, wpm: 80, raw: 80, events: 100, errors: 0,
      metrics: metrics(correct: 250, total: 250, credited: 100, retained: 100)))
    olderJSON["startedAt"] = now.addingTimeInterval(-16).timeIntervalSinceReferenceDate
    olderJSON["finishedAt"] = now.addingTimeInterval(-1).timeIntervalSinceReferenceDate
    let older = try JSONDecoder().decode(ResultSubmissionRequest.self,
      from: JSONSerialization.data(withJSONObject: olderJSON))
    _ = try await store.submitResult(older, accessToken: higher.accessToken, now: now)
    let board = try await store.leaderboard(.init(mode: "time", language: "english", period: "all"), now: now)
    XCTAssertEqual(board.entries.first?.userID, higher.user.id)
    let lower = try XCTUnwrap(board.entries.first(where: { $0.userID != higher.user.id }))
    let json = try object(lower)
    XCTAssertEqual(json["accuracy"] as? Int, 100)
    XCTAssertEqual(json["preciseAccuracy"] as? Double, 99.6)
    XCTAssertNil(json["inputMetrics"])
    XCTAssertNil(json["correctAttempts"])
  }

  func testMixedVersionPersistenceAndIdempotencyPreservePrecision() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-input-metrics-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: file) }
    let store = try AuthStore(fileURL: file, bcryptCost: 4, minimumLeaderboardTypingSeconds: 0)
    let session = try await store.register(.init(email: "persist@example.com", password: "a secure password",
      displayName: "Persist"), now: now)
    let precise = try result(accuracy: 67, wpm: 0, raw: 2, events: 2, errors: 1,
      metrics: metrics(correct: 2, total: 3, credited: 0, retained: 3))
    let first = try await store.submitResult(precise, accessToken: session.accessToken, now: now)
    let repeatReceipt = try await store.submitResult(precise, accessToken: session.accessToken, now: now)
    XCTAssertEqual(first, repeatReceipt)
    _ = try await store.submitResult(try result(accuracy: 100, wpm: 2, raw: 2, events: 3, errors: 0,
      metrics: nil), accessToken: session.accessToken, now: now)
    let reloaded = try AuthStore(fileURL: file, bcryptCost: 4, minimumLeaderboardTypingSeconds: 0)
    let page = try await reloaded.results(.init(), credential: .accessToken(session.accessToken), now: now)
    XCTAssertEqual(page.total, 2)
    let newJSON = try object(try XCTUnwrap(page.results.first(where: { $0.id == precise.id })))
    XCTAssertEqual(newJSON["preciseAccuracy"] as? Double, 66.67)
    XCTAssertNil(newJSON["inputMetrics"])
    let oldJSON = try object(try XCTUnwrap(page.results.first(where: { $0.id != precise.id })))
    XCTAssertNil(oldJSON["preciseAccuracy"])
  }

  private func metrics(correct: Int, total: Int, credited: Int, retained: Int) -> [String: Int] {
    ["version": 1, "correctAttempts": correct, "totalAttempts": total,
      "creditedUnits": credited, "retainedUnits": retained]
  }

  func testRoundedHundredDoesNotUnlockPerfectMinuteButProfileKeepsPrecision() async throws {
    let (store, token) = try await account()
    var json = try object(try result(accuracy: 100, wpm: 20, raw: 20, events: 100, errors: 0,
      metrics: metrics(correct: 249, total: 250, credited: 100, retained: 100)))
    json["durationSeconds"] = 60
    json["startedAt"] = now.addingTimeInterval(-60).timeIntervalSinceReferenceDate
    let request = try JSONDecoder().decode(ResultSubmissionRequest.self,
      from: JSONSerialization.data(withJSONObject: json))
    _ = try await store.submitResult(request, accessToken: token, now: now)
    let user = try await store.authenticatedUser(for: token, now: now)
    XCTAssertFalse(user.availableBadges.map(\.id).contains("perfect-minute"))
    let profile = try await store.publicProfile(id: user.id, now: now)
    let best = try XCTUnwrap(profile.personalBests.first)
    XCTAssertEqual(try object(best)["preciseAccuracy"] as? Double, 99.6)
    XCTAssertEqual(best.accuracy, 100)
  }

  func testCapabilityAndAuthenticatedHTTPRouteCarryTheNewContract() async throws {
    let app = try await Application.make(.testing)
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let liveNow = Date.now
    let session = try await store.register(.init(email: "route-metrics@example.com", password: "a secure password",
      displayName: "Route Metrics"), now: liveNow)
    let request = ResultSubmissionRequest(id: UUID(), mode: "time", language: "english",
      durationSeconds: 15, wordLimit: nil, wpm: 0, rawWpm: 2, accuracy: 67,
      errorCount: 1, eventCount: 2,
      inputMetrics: .init(version: 1, correctAttempts: 2, totalAttempts: 3, creditedUnits: 0, retainedUnits: 3),
      startedAt: liveNow.addingTimeInterval(-15), finishedAt: liveNow)
    do {
      try configure(app, authStore: store)
      try await app.test(.GET, "v1/capabilities") { response async in
        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(try? response.content.decode(ServiceCapabilitiesResponse.self).capabilities["resultInputMetrics"], .available)
      }
      try await app.test(.POST, "v1/results") { response async in
        XCTAssertEqual(response.status, .unauthorized)
      }
      try await app.test(.POST, "v1/results", beforeRequest: { outgoing async throws in
        outgoing.headers.add(name: "Authorization", value: "Bearer \(session.accessToken)")
        try outgoing.content.encode(request)
      }, afterResponse: { response async throws in
        XCTAssertEqual(response.status, .ok)
        XCTAssertTrue(try response.content.decode(ResultSubmissionResponse.self).accepted)
      })
      try await app.test(.GET, "v1/results", beforeRequest: { outgoing async in
        outgoing.headers.add(name: "Authorization", value: "Bearer \(session.accessToken)")
      }, afterResponse: { response async throws in
        XCTAssertEqual(response.status, .ok)
        let page = try response.content.decode(ResultListResponse.self)
        XCTAssertEqual(page.results.first?.preciseAccuracy, 66.67)
      })
      try await app.asyncShutdown()
    } catch {
      try? await app.asyncShutdown()
      throw error
    }
  }

  func testNewEmptyAttemptAccuracyIsZeroWhileLegacyEmptyAccuracyStaysHundred() async throws {
    let (store, token) = try await account()
    _ = try await store.submitResult(try result(accuracy: 0, wpm: 0, raw: 0, events: 0, errors: 0,
      metrics: metrics(correct: 0, total: 0, credited: 0, retained: 0)), accessToken: token, now: now)
    _ = try await store.submitResult(try result(accuracy: 100, wpm: 0, raw: 0, events: 0, errors: 0,
      metrics: nil), accessToken: token, now: now)
    let page = try await store.results(.init(), credential: .accessToken(token), now: now)
    XCTAssertEqual(Set(page.results.map(\.accuracy)), [0, 100])
  }

  func testLegacyExtremeCountsAreRejectedBeforeFloatingPointIntegerConversion() async throws {
    let (store, token) = try await account()
    var json = try object(try result(accuracy: 100, wpm: 0, raw: 0,
      events: Int.max, errors: 0, metrics: nil))
    json["durationSeconds"] = 5
    json["startedAt"] = now.addingTimeInterval(-5).timeIntervalSinceReferenceDate
    let request = try JSONDecoder().decode(ResultSubmissionRequest.self,
      from: JSONSerialization.data(withJSONObject: json))
    do {
      _ = try await store.submitResult(request, accessToken: token, now: now)
      XCTFail("An extreme legacy count must be rejected")
    } catch let error as ResultStoreError { XCTAssertEqual(error, .invalidResult) }
  }

  private func result(accuracy: Int, wpm: Int, raw: Int, events: Int, errors: Int,
    metrics: [String: Int]?) throws -> ResultSubmissionRequest {
    let original = ResultSubmissionRequest(id: UUID(), mode: "time", language: "english",
      durationSeconds: 15, wordLimit: nil, wpm: wpm, rawWpm: raw, accuracy: accuracy,
      errorCount: errors, eventCount: events,
      startedAt: now.addingTimeInterval(-15), finishedAt: now)
    var json = try object(original)
    json["inputMetrics"] = metrics
    return try JSONDecoder().decode(ResultSubmissionRequest.self,
      from: JSONSerialization.data(withJSONObject: json))
  }

  private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
  }
}
