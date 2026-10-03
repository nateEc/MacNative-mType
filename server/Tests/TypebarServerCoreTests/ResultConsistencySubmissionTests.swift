import XCTVapor
import XCTest
@testable import TypebarServerCore

final class ResultConsistencySubmissionTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 39_000)
  private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
  }
  private func request(metrics: [String: Double]?) throws -> ResultSubmissionRequest {
    let value = ResultSubmissionRequest(id: UUID(), mode: "time", language: "english",
      durationSeconds: 15, wordLimit: nil, wpm: 80, rawWpm: 80, accuracy: 100,
      consistency: 71.5, errorCount: 0, eventCount: 100,
      startedAt: now.addingTimeInterval(-15), finishedAt: now)
    var json = try object(value); json["resultConsistency"] = metrics
    return try JSONDecoder().decode(ResultSubmissionRequest.self, from: JSONSerialization.data(withJSONObject: json))
  }
  private func account(file: URL? = nil) async throws -> (AuthStore, String) {
    let store = try AuthStore(fileURL: file, bcryptCost: 4, minimumLeaderboardTypingSeconds: 0)
    let session = try await store.register(.init(email: "consistency@example.com", password: "a secure password",
      displayName: "Consistency"), now: now)
    return (store, session.accessToken)
  }

  func testPhysicalConsistencyIsPersistedButWPMConsistencyIsTransient() async throws {
    let (store, token) = try await account()
    let value = try request(metrics: ["version": 1, "keyConsistency": 66.67, "wpmConsistency": 8.90])
    _ = try await store.submitResult(value, accessToken: token, now: now)
    let page = try await store.results(.init(), credential: .accessToken(token), now: now)
    let json = try object(try XCTUnwrap(page.results.first))
    XCTAssertEqual(json["keyConsistency"] as? Double, 66.67)
    XCTAssertEqual(json["consistency"] as? Double, 71.5)
    XCTAssertNil(json["wpmConsistency"]); XCTAssertNil(json["resultConsistency"])
  }

  func testUnknownVersionAndOutOfRangeMetricsCannotBeSilentlyIgnored() async throws {
    let (store, token) = try await account()
    for metrics in [["version": 2.0, "keyConsistency": 80], ["version": 1, "keyConsistency": -1],
      ["version": 1, "keyConsistency": 101], ["version": 1, "keyConsistency": 80, "wpmConsistency": -1],
      ["version": 1, "keyConsistency": 80, "wpmConsistency": 101]] {
      do {
        _ = try await store.submitResult(try request(metrics: metrics), accessToken: token, now: now)
        XCTFail("Invalid result consistency must be rejected")
      } catch let error as ResultStoreError { XCTAssertEqual(error, .invalidResult) }
    }
  }

  func testLegacySubmissionKeepsMissingKeyConsistencyMissing() async throws {
    let (store, token) = try await account()
    _ = try await store.submitResult(try request(metrics: nil), accessToken: token, now: now)
    let page = try await store.results(.init(), credential: .accessToken(token), now: now)
    XCTAssertNil(try object(try XCTUnwrap(page.results.first))["keyConsistency"])
  }

  func testMixedPersistenceRestartAndIdempotencyDoNotSaveWPMOrRewriteFirstPhysicalValue() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-result-consistency-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: file) }
    let (store, token) = try await account(file: file)
    let first = try request(metrics: ["version": 1, "keyConsistency": 66.67, "wpmConsistency": 8.9])
    let receipt = try await store.submitResult(first, accessToken: token, now: now)
    var changed = try object(first)
    changed["resultConsistency"] = ["version": 1, "keyConsistency": 12, "wpmConsistency": 99]
    let retry = try JSONDecoder().decode(ResultSubmissionRequest.self, from: JSONSerialization.data(withJSONObject: changed))
    let duplicate = try await store.submitResult(retry, accessToken: token, now: now)
    XCTAssertEqual(duplicate, receipt)
    let old = try request(metrics: nil)
    _ = try await store.submitResult(old, accessToken: token, now: now)
    let state = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    let saved = try XCTUnwrap(state["results"] as? [[String: Any]])
    XCTAssertEqual(saved.count, 2)
    for row in saved { XCTAssertNil(row["wpmConsistency"]); XCTAssertNil(row["resultConsistency"]) }
    let reloaded = try AuthStore(fileURL: file, bcryptCost: 4, minimumLeaderboardTypingSeconds: 0)
    let page = try await reloaded.results(.init(), credential: .accessToken(token), now: now)
    XCTAssertEqual(page.total, 2)
    XCTAssertEqual(try object(try XCTUnwrap(page.results.first { $0.id == first.id }))["keyConsistency"] as? Double, 66.67)
    XCTAssertNil(try object(try XCTUnwrap(page.results.first { $0.id == old.id }))["keyConsistency"])
  }

  func testFiniteEndpointsAndAbsentTransientWPMRemainValid() async throws {
    let (store, token) = try await account()
    for physical in [0.0, 100] {
      let value = try request(metrics: ["version": 1, "keyConsistency": physical])
      _ = try await store.submitResult(value, accessToken: token, now: now)
    }
    let page = try await store.results(.init(), credential: .accessToken(token), now: now)
    XCTAssertEqual(Set(page.results.compactMap(\.keyConsistency)), [0, 100])
  }

  func testNonfiniteDirectMetricsAreRejectedBeforePersisting() async throws {
    let (store, token) = try await account()
    for number in [Double.nan, .infinity, -.infinity] {
      for physical in [true, false] {
        let value = ResultSubmissionRequest(id: UUID(), mode: "time", language: "english",
          durationSeconds: 15, wordLimit: nil, wpm: 80, rawWpm: 80, accuracy: 100,
          errorCount: 0, eventCount: 100, resultConsistency: .init(
            keyConsistency: physical ? number : 80, wpmConsistency: physical ? 80 : number),
          startedAt: now.addingTimeInterval(-15), finishedAt: now)
        do { _ = try await store.submitResult(value, accessToken: token, now: now); XCTFail("Nonfinite metric accepted") }
        catch let error as ResultStoreError { XCTAssertEqual(error, .invalidResult) }
      }
    }
    let page = try await store.results(.init(), credential: .accessToken(token), now: now)
    XCTAssertEqual(page.total, 0)
  }

  func testNegotiatedHTTPRouteRequiresAuthenticationAndReturnsOnlySavedPhysicalMetric() async throws {
    let app = try await Application.make(.testing), liveNow = Date.now
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let owner = try await store.register(.init(email: "route-consistency@example.com", password: "a secure password",
      displayName: "Consistency"), now: liveNow)
    let value = ResultSubmissionRequest(id: UUID(), mode: "time", language: "english",
      durationSeconds: 15, wordLimit: nil, wpm: 80, rawWpm: 80, accuracy: 100,
      consistency: 71.5, errorCount: 0, eventCount: 100,
      resultConsistency: .init(keyConsistency: 66.67, wpmConsistency: 8.9),
      startedAt: liveNow.addingTimeInterval(-15), finishedAt: liveNow)
    do {
      try configure(app, authStore: store)
      try await app.test(.GET, "v1/capabilities") { response async throws in
        let body = try response.content.decode(ServiceCapabilitiesResponse.self)
        XCTAssertEqual(body.capabilities["resultConsistency"], .available)
      }
      try await app.test(.POST, "v1/results") { response async in XCTAssertEqual(response.status, .unauthorized) }
      try await app.test(.GET, "v1/results") { response async in XCTAssertEqual(response.status, .unauthorized) }
      try await app.test(.POST, "v1/results", beforeRequest: { outgoing async throws in
        outgoing.headers.add(name: "Authorization", value: "Bearer \(owner.accessToken)")
        try outgoing.content.encode(value)
      }, afterResponse: { response async throws in
        XCTAssertEqual(response.status, .ok)
        XCTAssertTrue(try response.content.decode(ResultSubmissionResponse.self).accepted)
      })
      try await app.test(.GET, "v1/results", beforeRequest: { outgoing async in
        outgoing.headers.add(name: "Authorization", value: "Bearer \(owner.accessToken)")
      }, afterResponse: { response async throws in
        let page = try response.content.decode(ResultListResponse.self)
        XCTAssertEqual(page.results.first?.keyConsistency, 66.67)
        XCTAssertNil(try self.object(try XCTUnwrap(page.results.first))["wpmConsistency"])
      })
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }
}
