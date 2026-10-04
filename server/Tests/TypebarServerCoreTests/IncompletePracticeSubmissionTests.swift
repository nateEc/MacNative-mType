import Foundation
import XCTest
import XCTVapor
@testable import TypebarServerCore

final class IncompletePracticeSubmissionTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 50_000)
  private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
  }
  private func payload(id: UUID = UUID()) throws -> [String: Any] {
    let base = ResultSubmissionRequest(id: id, mode: "words", language: "english",
      durationSeconds: nil, wordLimit: 25, wpm: 60, rawWpm: 60, accuracy: 100,
      errorCount: 0, eventCount: 75, restartCount: 2,
      practiceTiming: .init(version: 1, terminalEngagedMilliseconds: 15_000,
        priorAttemptEngagedMilliseconds: 3_005),
      startedAt: now.addingTimeInterval(-15), finishedAt: now)
    var json = try object(base)
    json["incompletePractice"] = ["version": 1,
      "attempts": [["accuracy": 66.67, "seconds": 1.01], ["accuracy": 0, "seconds": 2]]]
    return json
  }
  private func decode(_ json: [String: Any]) throws -> ResultSubmissionRequest {
    let decoder = JSONDecoder()
    decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity",
      negativeInfinity: "-Infinity", nan: "NaN")
    return try decoder.decode(ResultSubmissionRequest.self, from: JSONSerialization.data(withJSONObject: json))
  }
  private func account(file: URL? = nil) async throws -> (AuthStore, AuthSessionResponse) {
    let store = try AuthStore(fileURL: file, bcryptCost: 4, minimumLeaderboardTypingSeconds: 0)
    let owner = try await store.register(.init(email: "incomplete-submit@example.com",
      password: "a secure password", displayName: "Incomplete"), now: now)
    return (store, owner)
  }

  func testUnknownExplicitEvidenceCannotBeIgnoredByRequestDecoder() throws {
    var json = try payload()
    json["incompletePractice"] = ["version": 2, "attempts": []]
    XCTAssertThrowsError(try decode(json))
  }

  func testAcceptedHistoryRetainsEveryAttemptAccuracyAndFraction() async throws {
    let (store, owner) = try await account(), json = try payload()
    let request = try decode(json)
    let receipt = try await store.submitResult(request, accessToken: owner.accessToken, now: now)
    XCTAssertEqual(receipt.experienceGained, 18, "Transport expansion must not rescore existing account XP")
    let history = try await store.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    let saved = try XCTUnwrap(history.results.first)
    XCTAssertEqual(try object(saved)["incompletePractice"] as? NSDictionary,
      json["incompletePractice"] as? NSDictionary)
    XCTAssertEqual(try object(saved)["restartCount"] as? Int, 2)
  }

  func testMalformedExplicitShapesAndMissingCountCannotDowngrade() throws {
    for marker: Any in [NSNull(), [:], ["version": 1], ["version": 1, "attempts": NSNull()],
      ["version": 1, "attempts": [["accuracy": -1, "seconds": 1]]],
      ["version": 1, "attempts": [["accuracy": 101, "seconds": 1]]],
      ["version": 1, "attempts": [["accuracy": 0, "seconds": -1]]],
      ["version": 1, "attempts": [["accuracy": "NaN", "seconds": 1]]],
      ["version": 1, "attempts": [["accuracy": 0, "seconds": "Infinity"]]],
      ["version": 1, "attempts": [["seconds": 1]]]] {
      var json = try payload(); json["incompletePractice"] = marker
      XCTAssertThrowsError(try decode(json))
    }
    var json = try payload(); json.removeValue(forKey: "restartCount")
    XCTAssertThrowsError(try decode(json))
    json["restartCount"] = NSNull(); XCTAssertThrowsError(try decode(json))
  }

  func testSemanticBindingsAreRejectedBeforeStateChanges() async throws {
    let (store, owner) = try await account()
    for mutation in 0..<5 {
      var json = try payload()
      switch mutation {
      case 0: json.removeValue(forKey: "practiceTiming")
      case 1: json["restartCount"] = 1
      case 2: json["restartCount"] = -1
      case 3: json["practiceTiming"] = ["version": 1, "terminalEngagedMilliseconds": 15_000,
        "priorAttemptEngagedMilliseconds": 2_000]
      default: json["incompletePractice"] = ["version": 1, "attempts": []]
      }
      do {
        _ = try await store.submitResult(decode(json), accessToken: owner.accessToken, now: now)
        XCTFail("Inconsistent evidence must not be accepted")
      } catch let error as ResultStoreError { XCTAssertEqual(error, .invalidResult) }
    }
    let history = try await store.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    XCTAssertEqual(history.total, 0)
    let stats = await store.publicPracticeStats()
    XCTAssertEqual(stats.startedTestCount, 0)
  }

  func testExplicitEmptyZeroAndRoundingBoundariesKeepTheirMeaning() async throws {
    let (store, owner) = try await account()
    for count in [0, 1, 1_000] {
      var json = try payload(); json["restartCount"] = count
      json["incompletePractice"] = ["version": 1, "attempts":
        Array(repeating: ["accuracy": 0, "seconds": count == 0 ? 0.0 : 0.01], count: count)]
      json["practiceTiming"] = ["version": 1, "terminalEngagedMilliseconds": 15_000,
        "priorAttemptEngagedMilliseconds": Int((Double(count) * 0.00549 * 1_000).rounded())]
      let receipt = try await store.submitResult(decode(json), accessToken: owner.accessToken, now: now)
      XCTAssertEqual(receipt.experienceGained, 18)
    }
    let sum = try await store.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    XCTAssertEqual(sum.total, 3)
    var tooMany = try payload(); tooMany["restartCount"] = 1_001
    tooMany["incompletePractice"] = ["version": 1, "attempts":
      Array(repeating: ["accuracy": 0, "seconds": 0], count: 1_001)]
    XCTAssertThrowsError(try decode(tooMany))
    let evidence = ResultIncompletePractice(attempts: [.init(accuracy: 0, seconds: 0.01)])
    XCTAssertTrue(evidence.isValid(restartCount: 1, practiceTiming: .init(version: 1,
      terminalEngagedMilliseconds: 15_000, priorAttemptEngagedMilliseconds: 5)))
    XCTAssertFalse(evidence.isValid(restartCount: 1, practiceTiming: .init(version: 1,
      terminalEngagedMilliseconds: 15_000, priorAttemptEngagedMilliseconds: 4)))
  }

  func testDiskReloadDuplicateAndOldRecordDoNotLoseEvidenceOrRescore() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-incomplete-results-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: file) }
    let (store, owner) = try await account(file: file), json = try payload()
    let input = try decode(json)
    let receipt = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    var duplicate = json
    duplicate["incompletePractice"] = ["version": 1,
      "attempts": [["accuracy": 100, "seconds": 1.01], ["accuracy": 100, "seconds": 2]]]
    let repeated = try await store.submitResult(decode(duplicate), accessToken: owner.accessToken, now: now)
    XCTAssertEqual(repeated.totalExperience, receipt.totalExperience)
    var old = try payload(); old.removeValue(forKey: "incompletePractice")
    _ = try await store.submitResult(decode(old), accessToken: owner.accessToken, now: now)
    let reloaded = try AuthStore(fileURL: file, bcryptCost: 4, minimumLeaderboardTypingSeconds: 0)
    let history = try await reloaded.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    XCTAssertEqual(history.total, 2)
    let fresh = try XCTUnwrap(history.results.first { $0.id == input.id })
    XCTAssertEqual(try object(fresh)["incompletePractice"] as? NSDictionary, json["incompletePractice"] as? NSDictionary)
    let legacy = try XCTUnwrap(history.results.first { $0.id != input.id })
    XCTAssertNil(try object(legacy)["incompletePractice"])
    XCTAssertNil(try object(legacy)["restartCount"])
    let stats = await reloaded.publicPracticeStats()
    XCTAssertEqual(stats.startedTestCount, 6, "Two accepted requests have two restarts each; duplicate adds none")
  }

  func testCorruptStoredMarkersAndBindingsRefuseReloadWithoutChangingFile() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-incomplete-corrupt-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: file) }
    let (store, owner) = try await account(file: file)
    _ = try await store.submitResult(decode(payload()), accessToken: owner.accessToken, now: now)
    let original = try Data(contentsOf: file)
    for mutation in 0..<7 {
      var json = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
      var rows = try XCTUnwrap(json["results"] as? [[String: Any]])
      switch mutation {
      case 0: rows[0]["incompletePractice"] = NSNull()
      case 1: rows[0]["incompletePractice"] = ["version": 2, "attempts": []]
      case 2: rows[0].removeValue(forKey: "restartCount")
      case 3: rows[0].removeValue(forKey: "practiceTiming")
      case 4: rows[0]["restartCount"] = 1
      case 5: rows[0]["practiceTiming"] = ["version": 1, "terminalEngagedMilliseconds": 15_000,
        "priorAttemptEngagedMilliseconds": 1_000]
      default: rows[0]["practiceTiming"] = ["version": 1, "terminalEngagedMilliseconds": 16_000,
        "priorAttemptEngagedMilliseconds": 3_005]
      }
      json["results"] = rows
      let corrupted = try JSONSerialization.data(withJSONObject: json)
      try corrupted.write(to: file, options: .atomic)
      XCTAssertThrowsError(try AuthStore(fileURL: file, bcryptCost: 4))
      XCTAssertEqual(try Data(contentsOf: file), corrupted)
    }
    try original.write(to: file, options: .atomic)
    _ = try AuthStore(fileURL: file, bcryptCost: 4)
  }

  func testPersistenceFailureRollsBackNewEvidenceAndCanRetryOnce() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-incomplete-failure-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("store.json"), backup = directory.appendingPathComponent("backup.json")
    let (store, owner) = try await account(file: file), input = try decode(payload())
    try FileManager.default.moveItem(at: file, to: backup)
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
    do {
      _ = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
      XCTFail("Directory in place of store must cause persistence failure")
    } catch { }
    let empty = try await store.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    XCTAssertEqual(empty.total, 0)
    let emptyStats = await store.publicPracticeStats()
    XCTAssertEqual(emptyStats.startedTestCount, 0)
    try FileManager.default.removeItem(at: file)
    try FileManager.default.moveItem(at: backup, to: file)
    _ = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    let history = try await store.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    XCTAssertEqual(history.total, 1)
    XCTAssertEqual(history.results.first?.incompletePractice?.attempts.count, 2)
  }

  func testPrivateAttemptEvidenceIsScopedToTheAuthenticatedOwner() async throws {
    let (store, owner) = try await account(), input = try decode(payload())
    _ = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    let other = try await store.register(.init(email: "incomplete-other-owner@example.com",
      password: "a secure password", displayName: "Other"), now: now)
    let hidden = try await store.results(.init(), credential: .accessToken(other.accessToken), now: now)
    XCTAssertTrue(hidden.results.isEmpty)
    do {
      _ = try await store.result(id: input.id, credential: .accessToken(other.accessToken), now: now)
      XCTFail("Another account cannot read private attempt evidence by UUID")
    } catch let error as AuthStoreError { XCTAssertEqual(error, .resultNotFound) }
    let actual = try await store.result(id: input.id, credential: .accessToken(owner.accessToken), now: now)
    XCTAssertEqual(actual.incompletePractice, input.incompletePractice)
  }

  func testConcurrentDuplicateSubmissionsKeepOneAcceptedSnapshot() async throws {
    let (store, owner) = try await account(), input = try decode(payload())
    let instant = now
    async let first = store.submitResult(input, accessToken: owner.accessToken, now: instant)
    async let second = store.submitResult(input, accessToken: owner.accessToken, now: instant)
    let receipts = try await [first, second]
    XCTAssertTrue(receipts.allSatisfy(\.accepted))
    XCTAssertEqual(receipts[0].totalExperience, receipts[1].totalExperience)
    let history = try await store.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    XCTAssertEqual(history.total, 1)
    XCTAssertEqual(history.results.first?.incompletePractice, input.incompletePractice)
    let stats = await store.publicPracticeStats()
    XCTAssertEqual(stats.startedTestCount, 3)
  }

  func testActualHTTPRequiresAuthAndAdvertisesExactCapability() async throws {
    let app = try await Application.make(.testing), liveNow = Date.now
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let owner = try await store.register(.init(email: "incomplete-http@example.com",
      password: "a secure password", displayName: "HTTP"), now: liveNow)
    var json = try payload()
    json["startedAt"] = liveNow.addingTimeInterval(-15).timeIntervalSinceReferenceDate
    json["finishedAt"] = liveNow.timeIntervalSinceReferenceDate
    let input = try decode(json)
    do {
      try configure(app, authStore: store)
      try await app.test(.GET, "v1/capabilities") { response async throws in
        let capabilities = try response.content.decode(ServiceCapabilitiesResponse.self)
        XCTAssertEqual(capabilities.apiVersion, "v1"); XCTAssertEqual(capabilities.service, "typebar")
        XCTAssertEqual(capabilities.capabilities["resultIncompletePractice"], .available)
      }
      try await app.test(.POST, "v1/results", beforeRequest: { outgoing async throws in
        try outgoing.content.encode(input)
      }, afterResponse: { response async throws in XCTAssertEqual(response.status, .unauthorized) })
      try await app.test(.POST, "v1/results", beforeRequest: { outgoing async throws in
        outgoing.headers.bearerAuthorization = .init(token: owner.accessToken)
        try outgoing.content.encode(input)
      }, afterResponse: { response async throws in XCTAssertEqual(response.status, .ok) })
      try await app.test(.GET, "v1/results", beforeRequest: { outgoing async throws in
        outgoing.headers.bearerAuthorization = .init(token: owner.accessToken)
      }, afterResponse: { response async throws in
        let page = try response.content.decode(ResultListResponse.self)
        XCTAssertEqual(page.results.first?.incompletePractice, input.incompletePractice)
        XCTAssertEqual(page.results.first?.restartCount, 2)
      })
      var inconsistent = json; inconsistent["restartCount"] = 1
      let wrong = try decode(inconsistent)
      try await app.test(.POST, "v1/results", beforeRequest: { outgoing async throws in
        outgoing.headers.bearerAuthorization = .init(token: owner.accessToken)
        try outgoing.content.encode(wrong)
      }, afterResponse: { response async throws in XCTAssertEqual(response.status, .badRequest) })
      let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
      var malformed = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(input)) as? [String: Any])
      malformed["incompletePractice"] = NSNull()
      let badBody = try JSONSerialization.data(withJSONObject: malformed)
      try await app.test(.POST, "v1/results", beforeRequest: { outgoing async throws in
        outgoing.headers.bearerAuthorization = .init(token: owner.accessToken)
        outgoing.headers.contentType = .json; outgoing.body = ByteBuffer(data: badBody)
      }, afterResponse: { response async throws in XCTAssertEqual(response.status, .badRequest) })
      try await app.asyncShutdown()
    } catch {
      try await app.asyncShutdown(); throw error
    }
  }
}
