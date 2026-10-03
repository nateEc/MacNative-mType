import XCTVapor
import XCTest
@testable import TypebarServerCore

final class VersionedInputMetricsSubmissionTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 41_000)
  private func metrics(basis: String = "utf16", correct: Int = 2, total: Int = 3,
    rawInput: Int = 2, retained: Int = 2) -> [String: Any] {
    ["version": 2, "correctAttempts": correct, "totalAttempts": total,
      "creditedUnits": retained, "retainedUnits": retained,
      "retainedInputUnits": rawInput, "scoringUnitBasis": basis]
  }
  private func request(_ value: [String: Any]?, events: Int = 3, accuracy: Int = 67,
    speed: Int = 2) throws -> ResultSubmissionRequest {
    let base = ResultSubmissionRequest(id: UUID(), mode: "time", language: "english",
      durationSeconds: 15, wordLimit: nil, wpm: speed, rawWpm: speed,
      accuracy: accuracy, errorCount: 0, eventCount: events,
      startedAt: now.addingTimeInterval(-15), finishedAt: now)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as? [String: Any])
    object["inputMetrics"] = value
    return try JSONDecoder().decode(ResultSubmissionRequest.self,
      from: JSONSerialization.data(withJSONObject: object))
  }
  private func account() async throws -> (AuthStore, String) {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4, minimumLeaderboardTypingSeconds: 0)
    let user = try await store.register(.init(email: "units-v2@example.com", password: "a secure password",
      displayName: "Units V2"), now: now)
    return (store, user.accessToken)
  }

  func testTrimmedSpaceResultIsAcceptedWithoutInventingAnotherAttempt() async throws {
    let (store, token) = try await account()
    let receipt = try await store.submitResult(try request(metrics()), accessToken: token, now: now)
    XCTAssertTrue(receipt.accepted)
    let page = try await store.results(.init(), credential: .accessToken(token), now: now)
    XCTAssertEqual(page.results.first?.preciseAccuracy, 66.67)
  }

  func testFiveKoreanUnitsFromOneInputAttemptAreAccepted() async throws {
    let (store, token) = try await account()
    let value = metrics(basis: "koreanJamo", correct: 1, total: 1, rawInput: 1, retained: 5)
    let receipt = try await store.submitResult(try request(value, events: 1, accuracy: 100, speed: 4),
      accessToken: token, now: now)
    XCTAssertTrue(receipt.accepted)
  }

  func testMalformedBasisBoundsAndAttemptCountsCannotBypassValidation() async throws {
    let (store, token) = try await account()
    var invalid: [[String: Any]] = []
    for key in ["scoringUnitBasis", "retainedInputUnits"] {
      var value = metrics(); value.removeValue(forKey: key); invalid.append(value)
    }
    for (key, bad): (String, Any) in [("version",1), ("version",3), ("scoringUnitBasis","other"),
      ("retainedInputUnits",-1), ("retainedInputUnits",4), ("retainedInputUnits",Int.max),
      ("totalAttempts",-1), ("totalAttempts",2), ("totalAttempts",1_800_001), ("totalAttempts",Int.max),
      ("correctAttempts",4), ("correctAttempts",-1), ("creditedUnits",3), ("retainedUnits",3),
      ("retainedUnits",Int.max)] {
      var value = metrics(); value[key] = bad; invalid.append(value)
    }
    invalid.append(metrics(basis: "koreanJamo", correct: 1, total: 1, rawInput: 1, retained: 6))
    for value in invalid {
      do {
        _ = try await store.submitResult(try request(value), accessToken: token, now: now)
        XCTFail("Malformed v2 metrics must not be ignored: \(value)")
      } catch let error as ResultStoreError {
        XCTAssertEqual(error, .invalidResult)
      } catch is DecodingError {
        // Unknown enum values are rejected before the request reaches the store.
      }
    }
  }

  func testLegacyVersionOneStillUsesItsOriginalConsistencyRule() async throws {
    let (store, token) = try await account()
    let old: [String: Any] = ["version": 1, "correctAttempts": 2, "totalAttempts": 3,
      "creditedUnits": 2, "retainedUnits": 2]
    do {
      _ = try await store.submitResult(try request(old), accessToken: token, now: now)
      XCTFail("v1 must not silently acquire the v2 native-event contract")
    } catch let error as ResultStoreError { XCTAssertEqual(error, .invalidResult) }
  }

  func testCapacityIsCheckedBeforeKoreanExpansionOrFloatingPointConversion() {
    XCTAssertTrue(ResultInputMetrics(version: 2, correctAttempts: 0, totalAttempts: 1_800_000,
      creditedUnits: 0, retainedUnits: 9_000_000, retainedInputUnits: 1_800_000, scoringUnitBasis: .koreanJamo).isValid)
    for (total, input, retained) in [(Int.max,Int.max,Int.max), (1,Int.max,Int.max),
      (1,1,Int.max), (1_800_001,1,1)] {
      XCTAssertFalse(ResultInputMetrics(version: 2, correctAttempts: 0, totalAttempts: total,
        creditedUnits: 0, retainedUnits: retained, retainedInputUnits: input, scoringUnitBasis: .koreanJamo).isValid)
    }
  }

  func testMixedPrivatePersistenceAndIdempotencyDoNotPublishAnonymousCounters() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-units-v2-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: file) }
    let store = try AuthStore(fileURL: file, bcryptCost: 4, minimumLeaderboardTypingSeconds: 0)
    let user = try await store.register(.init(email: "persist-units-v2@example.com", password: "a secure password",
      displayName: "Persist V2"), now: now)
    let trimmed = try request(metrics())
    let first = try await store.submitResult(trimmed, accessToken: user.accessToken, now: now)
    let repeated = try await store.submitResult(trimmed, accessToken: user.accessToken, now: now)
    XCTAssertEqual(repeated, first)
    _ = try await store.submitResult(try request(["version": 1, "correctAttempts": 3, "totalAttempts": 4,
      "creditedUnits": 3, "retainedUnits": 3], accuracy: 75), accessToken: user.accessToken, now: now)
    _ = try await store.submitResult(try request(nil, accuracy: 100), accessToken: user.accessToken, now: now)
    let reloaded = try AuthStore(fileURL: file, bcryptCost: 4, minimumLeaderboardTypingSeconds: 0)
    let page = try await reloaded.results(.init(), credential: .accessToken(user.accessToken), now: now)
    XCTAssertEqual(page.total, 3)
    XCTAssertEqual(page.results.first(where: { $0.id == trimmed.id })?.preciseAccuracy, 66.67)
    let serialized = String(decoding: try JSONEncoder().encode(page), as: UTF8.self)
    for forbidden in ["inputMetrics", "retainedInputUnits", "scoringUnitBasis", "totalAttempts"] {
      XCTAssertFalse(serialized.contains(forbidden))
    }
    let privateData = String(decoding: try Data(contentsOf: file), as: UTF8.self)
    XCTAssertTrue(privateData.contains("scoringUnitBasis"))
    XCTAssertTrue(privateData.contains("utf16"))
  }

  func testExactCapabilityAndAuthenticatedHTTPRouteAcceptV2AndRejectInvalidBasis() async throws {
    let app = try await Application.make(.testing)
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let liveNow = Date.now
    let user = try await store.register(.init(email: "route-units-v2@example.com", password: "a secure password",
      displayName: "Route V2"), now: liveNow)
    let valid = ResultSubmissionRequest(id: UUID(), mode: "time", language: "english",
      durationSeconds: 15, wordLimit: nil, wpm: 2, rawWpm: 2, accuracy: 67, errorCount: 0, eventCount: 3,
      inputMetrics: .init(version: 2, correctAttempts: 2, totalAttempts: 3, creditedUnits: 2,
        retainedUnits: 2, retainedInputUnits: 2, scoringUnitBasis: .utf16),
      startedAt: liveNow.addingTimeInterval(-15), finishedAt: liveNow)
    do {
      try configure(app, authStore: store)
      try await app.test(.GET, "v1/capabilities") { response async throws in
        let body = try response.content.decode(ServiceCapabilitiesResponse.self)
        XCTAssertEqual(body.apiVersion, "v1"); XCTAssertEqual(body.service, "typebar")
        XCTAssertEqual(body.capabilities["resultInputMetricsV2"], .available)
        XCTAssertEqual(body.capabilities["resultInputMetrics"], .available)
      }
      try await app.test(.POST, "v1/results") { response async in
        XCTAssertEqual(response.status, .unauthorized)
      }
      try await app.test(.POST, "v1/results", beforeRequest: { outgoing async throws in
        outgoing.headers.add(name: "Authorization", value: "Bearer \(user.accessToken)")
        try outgoing.content.encode(valid)
      }, afterResponse: { response async throws in
        XCTAssertEqual(response.status, .ok)
        XCTAssertTrue(try response.content.decode(ResultSubmissionResponse.self).accepted)
      })
      var bad = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any])
      var invalidMetrics = metrics(); invalidMetrics["scoringUnitBasis"] = "other"
      bad["id"] = UUID().uuidString; bad["inputMetrics"] = invalidMetrics
      let invalidBody = try JSONSerialization.data(withJSONObject: bad)
      try await app.test(.POST, "v1/results", beforeRequest: { outgoing async in
        outgoing.headers.add(name: "Authorization", value: "Bearer \(user.accessToken)")
        outgoing.headers.contentType = .json
        outgoing.body = .init(data: invalidBody)
      }, afterResponse: { response async in
        XCTAssertEqual(response.status, .badRequest)
      })
      try await app.asyncShutdown()
    } catch {
      try? await app.asyncShutdown(); throw error
    }
  }
}
