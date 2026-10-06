import Foundation
import XCTest
import XCTVapor
@testable import TypebarServerCore

final class ResultHistoryMetadataTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private func store(_ file: URL? = nil) throws -> AuthStore {
    try AuthStore(fileURL: file, bcryptCost: 4, rankingEnvironment: .development)
  }
  private func account(_ store: AuthStore, name: String = "Owner") async throws -> AuthSessionResponse {
    try await store.register(.init(email: "\(name.lowercased())@example.com", password: "a secure password", displayName: name), now: now)
  }
  private func json<T: Encodable>(_ value: T) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
  }
  private func request(speed: Int = 60, mode: String = "time", length: Any? = nil) throws -> ResultSubmissionRequest {
    let input = ResultSubmissionRequest(id: UUID(), mode: mode, language: "english",
      durationSeconds: mode == "time" ? 15 : nil, wordLimit: nil, wpm: speed, rawWpm: speed,
      accuracy: 100, errorCount: 0, eventCount: speed * 15 / 12,
      personalBestConfiguration: .init(difficulty: "normal", punctuation: false, numbers: false, lazyMode: false),
      startedAt: now.addingTimeInterval(-15), finishedAt: now)
    var object = try json(input); object["quoteLength"] = length
    return try JSONDecoder().decode(ResultSubmissionRequest.self, from: JSONSerialization.data(withJSONObject: object))
  }
  private func history(_ store: AuthStore, _ owner: AuthSessionResponse) async throws -> [[String: Any]] {
    let response = try await store.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    return try response.results.map(json)
  }

  func testHistoricalPBIsImmutableAcrossBetterScoresResetRetryAndColdReload() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-history-metadata-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("store.json"), initial = try store(file)
    let owner = try await account(initial), other = try await account(initial, name: "Other")
    let first = try request(), equal = try request(), better = try request(speed: 72)
    for input in [first, equal, better] { _ = try await initial.submitResult(input, accessToken: owner.accessToken, now: now) }
    _ = try await initial.submitResult(equal, accessToken: other.accessToken, now: now)
    func assertFlags(_ rows: [[String: Any]]) {
      let flags = Dictionary(uniqueKeysWithValues: rows.map { ($0["id"] as! String, $0["historicalPersonalBest"] as? Bool) })
      XCTAssertEqual(flags[first.id.uuidString]!, true)
      XCTAssertEqual(flags[equal.id.uuidString]!, false)
      XCTAssertEqual(flags[better.id.uuidString]!, true)
    }
    assertFlags(try await history(initial, owner))
    _ = try await initial.resetPersonalBests(.init(currentPassword: "a secure password"), accessToken: owner.accessToken, now: now)
    _ = try await initial.submitResult(first, accessToken: owner.accessToken, now: now)
    assertFlags(try await history(initial, owner))
    let loaded = try store(file)
    assertFlags(try await history(loaded, owner))
    let edited = try await loaded.updateResultTags(id: equal.id, request: .init(tags: ["desk"]), accessToken: owner.accessToken, now: now)
    XCTAssertEqual(try json(edited)["historicalPersonalBest"] as? Bool, false)
    let tag = try await loaded.createAccountTag(.init(name: "Study"), accessToken: owner.accessToken, now: now)
    let tagEdit = try await loaded.updateAccountResultTagIDs(id: first.id, request: .init(tagIDs: [tag.id]), accessToken: owner.accessToken, now: now)
    XCTAssertEqual(try json(tagEdit.result)["historicalPersonalBest"] as? Bool, true)
    let others = try await history(loaded, other)
    XCTAssertEqual(others.count, 1)
    XCTAssertEqual(others.first?["historicalPersonalBest"] as? Bool, true, "Identical result UUIDs must use each owner's receipt")
  }

  func testQuoteClassificationSurvivesRetryAndColdReadWithoutPromptStorage() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-history-quotes-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("store.json"), initial = try store(file), owner = try await account(initial)
    for length in ["short", "medium", "long", "extended"] {
      let input = try request(mode: "quote", length: length)
      _ = try await initial.submitResult(input, accessToken: owner.accessToken, now: now)
      var changed = try json(input); changed["quoteLength"] = "short"
      let retry = try JSONDecoder().decode(ResultSubmissionRequest.self, from: JSONSerialization.data(withJSONObject: changed))
      _ = try await initial.submitResult(retry, accessToken: owner.accessToken, now: now)
    }
    _ = try await initial.submitResult(request(mode: "quote"), accessToken: owner.accessToken, now: now)
    let rows = try await history(store(file), owner)
    XCTAssertEqual(Set(rows.compactMap { $0["quoteLength"] as? String }), Set(["short", "medium", "long", "extended"]))
    XCTAssertEqual(rows.filter { $0["quoteLength"] == nil }.count, 1)
    for row in rows { for key in ["prompt", "replayEvents", "accessToken"] { XCTAssertNil(row[key]) } }
  }

  func testLegacyReceiptAbsenceStaysUnknownAndOpeningDoesNotRewriteDisk() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-history-legacy-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("store.json"), initial = try store(file), owner = try await account(initial)
    _ = try await initial.submitResult(request(), accessToken: owner.accessToken, now: now)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    var awards = try XCTUnwrap(object["experienceAwards"] as? [[String: Any]])
    for index in awards.indices { awards[index].removeValue(forKey: "personalBestReceipt") }
    object["experienceAwards"] = awards
    try JSONSerialization.data(withJSONObject: object).write(to: file, options: .atomic)
    XCTAssertThrowsError(try store(file), "A modern accepted PB cannot lose its receipt and become legacy")
    object.removeValue(forKey: "personalBestLedger")
    object.removeValue(forKey: "personalBestLedgerManaged")
    let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    try bytes.write(to: file, options: .atomic)
    let rows = try await history(store(file), owner)
    XCTAssertEqual(rows.count, 1); XCTAssertNil(rows.first?["historicalPersonalBest"])
    XCTAssertEqual(try Data(contentsOf: file), bytes)
  }

  func testMalformedQuoteContextAndClientPBAssertionCannotAlterServiceOwnedHistory() async throws {
    for mode in ["time", "words", "custom", "zen"] {
      XCTAssertThrowsError(try request(mode: mode, length: "short"))
    }
    for invalid: Any in [NSNull(), "all", "unknown", 0, true] {
      XCTAssertThrowsError(try request(mode: "quote", length: invalid))
    }
    let initial = try store(), owner = try await account(initial)
    var object = try json(request()); object["historicalPersonalBest"] = false
    let forged = try JSONDecoder().decode(ResultSubmissionRequest.self, from: JSONSerialization.data(withJSONObject: object))
    _ = try await initial.submitResult(forged, accessToken: owner.accessToken, now: now)
    let rows = try await history(initial, owner)
    XCTAssertEqual(rows.first?["historicalPersonalBest"] as? Bool, true)
    let invalid = ResultSubmissionRequest(id: UUID(), mode: "time", language: "english", durationSeconds: 15,
      wordLimit: nil, wpm: 60, rawWpm: 60, accuracy: 100, errorCount: 0, eventCount: 75,
      quoteLength: .short, startedAt: now.addingTimeInterval(-15), finishedAt: now)
    do { _ = try await initial.submitResult(invalid, accessToken: owner.accessToken, now: now); XCTFail("Programmatic requests need the same context guard") }
    catch { XCTAssertTrue(error is ResultStoreError) }
    let after = try await history(initial, owner); XCTAssertEqual(after.count, 1)
  }

  func testColdReadRejectsCorruptQuoteMetadataWithoutRewritingFile() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-history-corrupt-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("store.json"), initial = try store(file), owner = try await account(initial)
    _ = try await initial.submitResult(request(mode: "quote", length: "long"), accessToken: owner.accessToken, now: now)
    let original = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    for invalid: Any in [NSNull(), "all", 0, "other"] {
      var object = original, rows = try XCTUnwrap(original["results"] as? [[String: Any]])
      rows[0]["quoteLength"] = invalid; object["results"] = rows
      let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
      try bytes.write(to: file, options: .atomic)
      XCTAssertThrowsError(try store(file)); XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
  }

  func testHTTPNegotiatesMetadataAndReadRoutesRemainAccountScoped() async throws {
    let live = Date.now, initial = try store()
    let owner = try await initial.register(.init(email: "httpowner@example.invalid", password: "a secure password", displayName: "Owner"), now: live)
    let other = try await initial.register(.init(email: "httpother@example.invalid", password: "a secure password", displayName: "Other"), now: live)
    let input = ResultSubmissionRequest(id: UUID(), mode: "quote", language: "english", durationSeconds: nil,
      wordLimit: nil, wpm: 60, rawWpm: 60, accuracy: 100, errorCount: 0, eventCount: 75,
      quoteLength: .extended, startedAt: live.addingTimeInterval(-15), finishedAt: live)
    let app = try await Application.make(.testing)
    do {
      try configure(app, authStore: initial)
      try await app.test(.POST, "v1/results", beforeRequest: { request async throws in
        request.headers.bearerAuthorization = .init(token: owner.accessToken)
        try request.content.encode(input)
      }, afterResponse: { response async in XCTAssertEqual(response.status, .ok) })
      try await app.test(.GET, "v1/capabilities") { response async throws in
        XCTAssertEqual(try response.content.decode(ServiceCapabilitiesResponse.self).capabilities["resultHistoryMetadata"], .available)
      }
      try await app.test(.GET, "v1/results/\(input.id)") { response async in XCTAssertEqual(response.status, .unauthorized) }
      try await app.test(.GET, "v1/results", beforeRequest: { request async in
        request.headers.bearerAuthorization = .init(token: owner.accessToken)
      }, afterResponse: { response async throws in
        let page = try response.content.decode(ResultListResponse.self)
        XCTAssertEqual(page.results.first?.quoteLength, .extended)
        XCTAssertEqual(page.results.first?.historicalPersonalBest, false)
      })
      for (token, expected) in [(owner.accessToken, HTTPResponseStatus.ok), (other.accessToken, .notFound)] {
        try await app.test(.GET, "v1/results/\(input.id)", beforeRequest: { request async in
          request.headers.bearerAuthorization = .init(token: token)
        }, afterResponse: { response async throws in
          XCTAssertEqual(response.status, expected)
          if expected == .ok {
            let result = try response.content.decode(AccountResultResponse.self)
            XCTAssertEqual(result.quoteLength, .extended); XCTAssertEqual(result.historicalPersonalBest, false)
          }
        })
      }
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }

  func testQuoteSnapshotArchiveRemainsOpaqueThroughSyncColdReadAndStaleConflict() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-history-sync-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("store.json"), initial = try store(file), owner = try await account(initial)
    let id = UUID(), payload = #"{"version":32,"results":[{"quoteSource":{"kind":"community","title":"Owned","actualLength":"long"}}]}"#
    let accepted = try await initial.pushSync(.init(changes: [.init(id: id, type: "typebar-archive", version: 2,
      payload: payload, isDeleted: false)]), accessToken: owner.accessToken, now: now)
    XCTAssertEqual(accepted.results.first?.status, .accepted)
    let loaded = try store(file)
    let stale = try await loaded.pushSync(.init(changes: [.init(id: id, type: "typebar-archive", version: 1,
      payload: #"{"version":31,"results":[]}"#, isDeleted: false)]), accessToken: owner.accessToken, now: now)
    XCTAssertEqual(stale.results.first?.status, .conflict)
    let pulled = try await loaded.pullSync(after: 0, accessToken: owner.accessToken, now: now)
    XCTAssertEqual(pulled.changes.first?.payload, payload)
    let rows = try await history(loaded, owner); XCTAssertTrue(rows.isEmpty)
  }
}
