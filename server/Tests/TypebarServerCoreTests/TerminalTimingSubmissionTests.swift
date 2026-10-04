import XCTVapor
import XCTest
@testable import TypebarServerCore

final class TerminalTimingSubmissionTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 41_000)

  private func request(timing: [String: Any]?, wall: Double = 16, speed: Int = 32,
    mode: String = "zen", end: Date? = nil, encoder: JSONEncoder = JSONEncoder()) throws -> ResultSubmissionRequest {
    let finish = end ?? now
    let base = ResultSubmissionRequest(id: UUID(), mode: mode, language: "english",
      durationSeconds: mode == "time" ? 16 : nil, wordLimit: nil,
      wpm: speed, rawWpm: speed, accuracy: 100, errorCount: 0, eventCount: 40,
      startedAt: finish.addingTimeInterval(-wall), finishedAt: finish)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(base)) as? [String: Any])
    object["terminalTiming"] = timing
    let decoder = JSONDecoder()
    if case .iso8601 = encoder.dateEncodingStrategy { decoder.dateDecodingStrategy = .iso8601 }
    return try decoder.decode(ResultSubmissionRequest.self, from: JSONSerialization.data(withJSONObject: object))
  }

  private func timing(end: Double = 16_000, last: Double? = 15_000, version: Int = 1) -> [String: Any] {
    var value: [String: Any] = ["version": version, "endMilliseconds": end]
    value["lastKeypressMilliseconds"] = last
    return value
  }

  private func account(file: URL? = nil) async throws -> (AuthStore, String) {
    let store = try AuthStore(fileURL: file, bcryptCost: 4, minimumLeaderboardTypingSeconds: 0)
    let user = try await store.register(.init(email: "terminal-clock@example.com",
      password: "a secure password", displayName: "Terminal Clock"), now: now)
    return (store, user.accessToken)
  }

  func testMeasuredDenominatorIsAcceptedWithoutChangingRealDates() async throws {
    let (store, token) = try await account()
    let input = try request(timing: timing())
    let receipt = try await store.submitResult(input, accessToken: token, now: now)
    XCTAssertTrue(receipt.accepted)
    let page = try await store.results(.init(), credential: .accessToken(token), now: now)
    XCTAssertEqual(page.results.first?.startedAt, input.startedAt)
    XCTAssertEqual(page.results.first?.finishedAt, input.finishedAt)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(page.results[0])) as? [String: Any])
    XCTAssertEqual(object["terminalTiming"] as? NSDictionary, timing() as NSDictionary)
  }

  func testLegacyAbsentMetadataKeepsTheWallClockDenominator() async throws {
    let (store, token) = try await account()
    let receipt = try await store.submitResult(request(timing: nil, speed: 30), accessToken: token, now: now)
    XCTAssertTrue(receipt.accepted)
  }

  func testStrictSevenSecondThresholdAndNoPhysicalKeyBranch() async throws {
    let (store, token) = try await account()
    for (metadata, wall, speed) in [(timing(end: 22_000), 22.0, 22),
      (timing(end: 21_999.99), 21.99999, 32), (timing(last: nil), 16.0, 30),
      (timing(last: -1), 16.0, 30)] {
      let receipt = try await store.submitResult(request(timing: metadata, wall: wall, speed: speed),
        accessToken: token, now: now)
      XCTAssertTrue(receipt.accepted)
    }
  }

  func testMalformedEvidenceWrongModeAndTooShortZenCannotBeIgnored() async throws {
    let (store, token) = try await account()
    let cases: [([String: Any], String)] = [
      (timing(version: 2), "zen"), (timing(end: -1), "zen"),
      (timing(end: 18_000), "zen"), (timing(last: 16_001), "zen"),
      (timing(last: 14_994), "zen"),
      (timing(end: Double.greatestFiniteMagnitude), "zen"), (timing(), "time")]
    for (metadata, mode) in cases {
      do {
        _ = try await store.submitResult(request(timing: metadata, speed: 30, mode: mode), accessToken: token, now: now)
        XCTFail("Invalid evidence must fail explicitly: \(metadata), \(mode)")
      } catch let error as ResultStoreError { XCTAssertEqual(error, .invalidResult) }
    }
  }

  func testMixedPersistenceRetainsExactEvidenceAndIdempotency() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-terminal-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: file) }
    let (store, token) = try await account(file: file)
    let input = try request(timing: timing(end: 16_875, last: 15_125), wall: 16.875)
    let receipt = try await store.submitResult(input, accessToken: token, now: now)
    _ = try await store.submitResult(request(timing: nil, speed: 30), accessToken: token, now: now)
    let reloaded = try AuthStore(fileURL: file, bcryptCost: 4, minimumLeaderboardTypingSeconds: 0)
    let repeated = try await reloaded.submitResult(input, accessToken: token, now: now)
    XCTAssertEqual(repeated, receipt)
    let page = try await reloaded.results(.init(), credential: .accessToken(token), now: now)
    XCTAssertEqual(page.total, 2)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(page.results.first { $0.id == input.id })) as? [String: Any])
    XCTAssertEqual(object["terminalTiming"] as? NSDictionary, timing(end: 16_875, last: 15_125) as NSDictionary)
    let stats = await reloaded.publicPracticeStats()
    XCTAssertEqual(stats.totalTypingSeconds, 31)
    var stored = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    var records = try XCTUnwrap(stored["results"] as? [[String: Any]])
    let index = try XCTUnwrap(records.firstIndex { ($0["id"] as? String)?.lowercased() == input.id.uuidString.lowercased() })
    records[index]["terminalTiming"] = timing(version: 2)
    stored["results"] = records
    try JSONSerialization.data(withJSONObject: stored).write(to: file, options: .atomic)
    XCTAssertThrowsError(try AuthStore(fileURL: file, bcryptCost: 4), "Corrupt evidence must not reload as a legacy score")
  }

  func testInputMetricsAndPracticeTimeAreValidatedAgainstTheMeasuredClock() async throws {
    let (store, token) = try await account()
    for engaged in [2_000, 16_000] {
      let input = ResultSubmissionRequest(id: UUID(), mode: "zen", language: "english",
        durationSeconds: nil, wordLimit: nil, wpm: 32, rawWpm: 32, accuracy: 100,
        errorCount: 0, eventCount: 40,
        practiceTiming: .init(version: 1, terminalEngagedMilliseconds: engaged, priorAttemptEngagedMilliseconds: 0),
        inputMetrics: .init(version: 2, correctAttempts: 40, totalAttempts: 40, creditedUnits: 40,
          retainedUnits: 40, retainedInputUnits: 40, scoringUnitBasis: .utf16),
        terminalTiming: .init(version: 1, endMilliseconds: 16_000, lastKeypressMilliseconds: 15_000),
        startedAt: now.addingTimeInterval(-16), finishedAt: now)
      do {
        let receipt = try await store.submitResult(input, accessToken: token, now: now)
        XCTAssertEqual(engaged, 2_000, "Engaged time cannot exceed the measured terminal duration")
        XCTAssertTrue(receipt.accepted)
      } catch let error as ResultStoreError {
        XCTAssertEqual(engaged, 16_000); XCTAssertEqual(error, .invalidResult)
      }
    }
  }

  func testExactCapabilityAndNativeWholeSecondHTTPDates() async throws {
    let app = try await Application.make(.testing)
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let liveNow = Date.now
    let user = try await store.register(.init(email: "terminal-http@example.com",
      password: "a secure password", displayName: "Terminal HTTP"), now: liveNow)
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    let input = try request(timing: timing(end: 16_875, last: 15_125), wall: 16.875,
      end: liveNow, encoder: encoder)
    do {
      try configure(app, authStore: store)
      try await app.test(.GET, "v1/capabilities") { response async throws in
        XCTAssertEqual(try response.content.decode(ServiceCapabilitiesResponse.self).capabilities["resultTerminalTiming"], .available)
      }
      try await app.test(.POST, "v1/results", beforeRequest: { outgoing async throws in
        outgoing.headers.add(name: "Authorization", value: "Bearer \(user.accessToken)")
        try outgoing.content.encode(input)
      }, afterResponse: { response async throws in
        XCTAssertEqual(response.status, .ok)
        XCTAssertTrue(try response.content.decode(ResultSubmissionResponse.self).accepted)
      })
      try await app.test(.GET, "v1/results", beforeRequest: { outgoing async in
        outgoing.headers.add(name: "Authorization", value: "Bearer \(user.accessToken)")
      }, afterResponse: { response async throws in
        XCTAssertEqual(response.status, .ok)
        let history = try response.content.decode(ResultListResponse.self)
        XCTAssertEqual(history.results.first?.terminalTiming?.measuredSeconds, 15.13)
      })
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }
}
