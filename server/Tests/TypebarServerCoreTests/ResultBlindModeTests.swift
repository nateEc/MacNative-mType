import Foundation
import XCTest
import XCTVapor
@testable import TypebarServerCore

final class ResultBlindModeTests: XCTestCase {
  private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
  }
  private func request(at now: Date, blind: Any? = true) throws -> ResultSubmissionRequest {
    let input = ResultSubmissionRequest(id: UUID(), mode: "time", language: "english", durationSeconds: 15,
      wordLimit: nil, wpm: 60, rawWpm: 60, accuracy: 100, errorCount: 0, eventCount: 75,
      startedAt: now.addingTimeInterval(-15), finishedAt: now)
    var wire = try object(input); wire["blindMode"] = blind
    return try JSONDecoder().decode(ResultSubmissionRequest.self, from: JSONSerialization.data(withJSONObject: wire))
  }

  func testExplicitBooleanAndMissingLegacyValuesRoundTripButMalformedPresenceFails() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    for blind: Bool? in [true, false, nil] {
      let input = try request(at: now, blind: blind), wire = try object(input)
      XCTAssertEqual(wire["blindMode"] as? Bool, blind)
      let response = try JSONDecoder().decode(AccountResultResponse.self, from: JSONSerialization.data(withJSONObject: wire))
      XCTAssertEqual(try object(response)["blindMode"] as? Bool, blind)
    }
    for invalid: Any in [NSNull(), "false", 0, []] {
      XCTAssertThrowsError(try request(at: now, blind: invalid))
      var wire = try object(request(at: now)); wire["blindMode"] = invalid
      XCTAssertThrowsError(try JSONDecoder().decode(AccountResultResponse.self, from: JSONSerialization.data(withJSONObject: wire)))
    }
  }

  func testColdReadRetryAndUnrelatedEditsPreserveEachOwnersOriginalBlindState() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-blind-history-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = Date(timeIntervalSince1970: 1_800_000_000), file = directory.appendingPathComponent("store.json")
    let initial = try AuthStore(fileURL: file, bcryptCost: 4, rankingEnvironment: .development)
    let owner = try await initial.register(.init(email: "owner@example.invalid", password: "a secure password", displayName: "Owner"), now: now)
    let other = try await initial.register(.init(email: "other@example.invalid", password: "a secure password", displayName: "Other"), now: now)
    var expected: [UUID: Bool] = [:], first: ResultSubmissionRequest?
    for blind: Bool? in [true, false, nil] {
      let input = try request(at: now, blind: blind)
      _ = try await initial.submitResult(input, accessToken: owner.accessToken, now: now)
      expected[input.id] = blind
      if first == nil { first = input }
    }
    let original = try XCTUnwrap(first)
    var wire = try object(original); wire["blindMode"] = false
    let changed = try JSONDecoder().decode(ResultSubmissionRequest.self, from: JSONSerialization.data(withJSONObject: wire))
    _ = try await initial.submitResult(changed, accessToken: owner.accessToken, now: now)
    _ = try await initial.submitResult(changed, accessToken: other.accessToken, now: now)
    let bytes = try Data(contentsOf: file), loaded = try AuthStore(fileURL: file, bcryptCost: 4, rankingEnvironment: .development)
    XCTAssertEqual(try Data(contentsOf: file), bytes, "Opening must not backfill or rewrite legacy metadata")
    let page = try await loaded.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    XCTAssertEqual(page.results.count, 3)
    for row in page.results { XCTAssertEqual(try object(row)["blindMode"] as? Bool, expected[row.id]) }
    let otherPage = try await loaded.results(.init(), credential: .accessToken(other.accessToken), now: now)
    XCTAssertEqual(try object(XCTUnwrap(otherPage.results.first))["blindMode"] as? Bool, false)
    let edit = try await loaded.updateResultTags(id: original.id, request: .init(tags: ["desk"]), accessToken: owner.accessToken, now: now)
    XCTAssertEqual(try object(edit)["blindMode"] as? Bool, true)
    let tag = try await loaded.createAccountTag(.init(name: "Study"), accessToken: owner.accessToken, now: now)
    let association = try await loaded.updateAccountResultTagIDs(id: original.id, request: .init(tagIDs: [tag.id]), accessToken: owner.accessToken, now: now)
    XCTAssertEqual(try object(association.result)["blindMode"] as? Bool, true)
    let reopened = try AuthStore(fileURL: file, bcryptCost: 4, rankingEnvironment: .development)
    let preserved = try await reopened.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    XCTAssertEqual(try object(XCTUnwrap(preserved.results.first(where: { $0.id == original.id })))["blindMode"] as? Bool, true)
  }

  func testCorruptStoredBlindStateFailsClosedWithoutChangingBytes() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-blind-corrupt-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = Date(timeIntervalSince1970: 1_800_000_000), file = directory.appendingPathComponent("store.json")
    let initial = try AuthStore(fileURL: file, bcryptCost: 4, rankingEnvironment: .development)
    let owner = try await initial.register(.init(email: "owner@example.invalid", password: "a secure password", displayName: "Owner"), now: now)
    _ = try await initial.submitResult(request(at: now), accessToken: owner.accessToken, now: now)
    let original = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    for invalid: Any in [NSNull(), "true", 1, []] {
      var state = original, rows = try XCTUnwrap(state["results"] as? [[String: Any]])
      rows[0]["blindMode"] = invalid; state["results"] = rows
      let bytes = try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]); try bytes.write(to: file, options: .atomic)
      XCTAssertThrowsError(try AuthStore(fileURL: file, bcryptCost: 4))
      XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
  }

  func testBlindFlagIsMetadataNotAnExperienceOrLeaderboardAwardInput() async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var receipts: [ResultSubmissionResponse] = []
    for blind in [true, false] {
      let store = try AuthStore(fileURL: nil, bcryptCost: 4, rankingEnvironment: .development)
      let owner = try await store.register(.init(email: "owner@example.invalid", password: "a secure password", displayName: "Owner"), now: now)
      receipts.append(try await store.submitResult(request(at: now, blind: blind), accessToken: owner.accessToken, now: now))
    }
    XCTAssertEqual(receipts[0].experienceGained, receipts[1].experienceGained)
    XCTAssertEqual(receipts[0].totalExperience, receipts[1].totalExperience)
    XCTAssertEqual(receipts[0].leaderboardEligible, receipts[1].leaderboardEligible)
    XCTAssertEqual(receipts[0].dailyLeaderboardRank, receipts[1].dailyLeaderboardRank)
  }
  func testHTTPAdvertisesAndRetainsBlindModeWithoutCrossAccountDisclosure() async throws {
    let now = Date.now, store = try AuthStore(fileURL: nil, bcryptCost: 4, rankingEnvironment: .development)
    let owner = try await store.register(.init(email: "blindowner@example.invalid", password: "a secure password", displayName: "Owner"), now: now)
    let other = try await store.register(.init(email: "blindother@example.invalid", password: "a secure password", displayName: "Other"), now: now)
    let input = try request(at: now), app = try await Application.make(.testing)
    do {
      try configure(app, authStore: store)
      try await app.test(.GET, "v1/capabilities") { response async throws in
        XCTAssertEqual(try response.content.decode(ServiceCapabilitiesResponse.self).capabilities["resultBlindMode"], .available)
      }
      try await app.test(.POST, "v1/results", beforeRequest: { request async throws in
        request.headers.bearerAuthorization = .init(token: owner.accessToken); try request.content.encode(input)
      }, afterResponse: { response async in XCTAssertEqual(response.status, .ok) })
      try await app.test(.GET, "v1/results", beforeRequest: { request async in
        request.headers.bearerAuthorization = .init(token: owner.accessToken)
      }, afterResponse: { response async throws in
        let page = try response.content.decode(ResultListResponse.self)
        XCTAssertEqual(try self.object(XCTUnwrap(page.results.first))["blindMode"] as? Bool, true)
      })
      try await app.test(.GET, "v1/results/\(input.id)", beforeRequest: { request async in
        request.headers.bearerAuthorization = .init(token: owner.accessToken)
      }, afterResponse: { response async throws in
        XCTAssertEqual(try self.object(response.content.decode(AccountResultResponse.self))["blindMode"] as? Bool, true)
      })
      try await app.test(.GET, "v1/results/\(input.id)", beforeRequest: { request async in
        request.headers.bearerAuthorization = .init(token: other.accessToken)
      }, afterResponse: { response async in XCTAssertEqual(response.status, .notFound) })
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }
}
