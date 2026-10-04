import XCTVapor
import XCTest
@testable import TypebarServerCore

final class ElapsedTimeSubmissionTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 41_000.875)

  private func object<T: Encodable>(_ value: T, iso: Bool = false) throws -> [String: Any] {
    let encoder = JSONEncoder()
    if iso { encoder.dateEncodingStrategy = .iso8601 }
    return try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(value)) as? [String: Any])
  }

  private func payload(wall: Double = -3_600, seconds: Any = 16.125, version: Int = 1,
    mode: String = "words", bailout: Bool = false, end: Date? = nil, iso: Bool = false) throws -> [String: Any] {
    let finish = end ?? now, start = finish.addingTimeInterval(-wall)
    let base = ResultSubmissionRequest(id: UUID(), mode: mode, language: "english",
      durationSeconds: mode == "time" ? 16 : nil, wordLimit: mode == "words" ? 25 : nil,
      wpm: bailout || mode == "zen" ? 32 : 30, rawWpm: bailout || mode == "zen" ? 32 : 30,
      accuracy: 100, errorCount: 0, eventCount: 40, startedAt: start, finishedAt: finish)
    var json = try object(base, iso: iso)
    json["elapsedTime"] = ["version": version, "seconds": seconds]
    json["startedAtReferenceTime"] = start.timeIntervalSinceReferenceDate
    json["finishedAtReferenceTime"] = finish.timeIntervalSinceReferenceDate
    if bailout { json["bailedOut"] = true }
    if bailout || mode == "zen" {
      json["terminalTiming"] = ["version": 1, "endMilliseconds": 16_125, "lastKeypressMilliseconds": 15_000]
    }
    return json
  }

  private func decode(_ json: [String: Any], iso: Bool = false) throws -> ResultSubmissionRequest {
    let decoder = JSONDecoder()
    if iso { decoder.dateDecodingStrategy = .iso8601 }
    decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity",
      negativeInfinity: "-Infinity", nan: "NaN")
    return try decoder.decode(ResultSubmissionRequest.self, from: JSONSerialization.data(withJSONObject: json))
  }

  private func account(file: URL? = nil) async throws -> (AuthStore, String) {
    let store = try AuthStore(fileURL: file, bcryptCost: 4, minimumLeaderboardTypingSeconds: 0)
    let user = try await store.register(.init(email: "elapsed@example.com", password: "a secure password",
      displayName: "Elapsed Time"), now: now)
    return (store, user.accessToken)
  }

  private func rejects(_ request: ResultSubmissionRequest, store: AuthStore, token: String) async throws {
    do {
      _ = try await store.submitResult(request, accessToken: token, now: now)
      XCTFail("Invalid independent timing must not be accepted")
    } catch let error as ResultStoreError { XCTAssertEqual(error, .invalidResult) }
  }

  func testIndependentWordsDurationSurvivesCalendarRollbackAndForwardJump() async throws {
    let (store, token) = try await account()
    for wall in [-3_600.0, 3_600] {
      let input = try decode(payload(wall: wall))
      let receipt = try await store.submitResult(input, accessToken: token, now: now)
      XCTAssertTrue(receipt.accepted)
      let history = try await store.results(.init(), credential: .accessToken(token), now: now)
      let value = try XCTUnwrap(history.results.first { $0.id == input.id })
      XCTAssertEqual(value.startedAt, input.startedAt)
      XCTAssertEqual(value.finishedAt, input.finishedAt)
      XCTAssertEqual(try object(value)["elapsedTime"] as? NSDictionary, ["version": 1, "seconds": 16.125] as NSDictionary)
    }
    let stats = await store.publicPracticeStats()
    XCTAssertEqual(stats.totalTypingSeconds, 32, "Public totals round the sum; per-record precision remains in history")
  }

  func testShortTimedQualificationCannotBeRescuedByIndependentTime() async throws {
    let (store, token) = try await account()
    for wall in [-3_600.0, 3_600, 16.24] {
      try await rejects(decode(payload(wall: wall, mode: "time")), store: store, token: token)
    }
    let receipt = try await store.submitResult(decode(payload(wall: 16.2, mode: "time")), accessToken: token, now: now)
    XCTAssertTrue(receipt.accepted)
  }

  func testZenAndBailoutTerminalEvidenceBindStrictlyToRawElapsedTime() async throws {
    let (store, token) = try await account()
    for (mode, bailout) in [("zen", false), ("time", true)] {
      let input = try decode(payload(mode: mode, bailout: bailout))
      let receipt = try await store.submitResult(input, accessToken: token, now: now)
      XCTAssertTrue(receipt.accepted)
      if bailout { XCTAssertEqual(receipt.experienceGained, 18); XCTAssertFalse(receipt.leaderboardEligible) }
      var wrong = try payload(wall: 16, mode: mode, bailout: bailout)
      wrong["terminalTiming"] = ["version": 1, "endMilliseconds": 16_625, "lastKeypressMilliseconds": 15_000]
      try await rejects(decode(wrong), store: store, token: token)
    }
  }

  func testMalformedElapsedTimeAndPrecisionCannotBeIgnoredByTheCodec() throws {
    for seconds: Any in [0, -1, 3_601, "NaN", "Infinity", "bad"] {
      XCTAssertThrowsError(try decode(payload(wall: 16, seconds: seconds)))
    }
    XCTAssertThrowsError(try decode(payload(wall: 16, version: 2)))
    for key in ["startedAtReferenceTime", "finishedAtReferenceTime"] {
      var json = try payload(wall: 16); json.removeValue(forKey: key)
      XCTAssertThrowsError(try decode(json))
      json[key] = 3
      XCTAssertThrowsError(try decode(json))
    }
  }

  func testISOWireRetainsPreciseDatesForTheOneTenthSecondCheck() async throws {
    let (store, token) = try await account()
    let input = try decode(payload(wall: 16.2, mode: "time", iso: true), iso: true)
    XCTAssertEqual(input.finishedAt, now)
    XCTAssertEqual(input.finishedAt.timeIntervalSince(input.startedAt), 16.2, accuracy: 0.000001)
    let receipt = try await store.submitResult(input, accessToken: token, now: now)
    XCTAssertTrue(receipt.accepted)
  }

  func testRoundedQuoteMinimumAllowsSubsecondRawEvidenceButNotCustom() async throws {
    let (store, token) = try await account()
    for bailout in [false, true] {
      var json = try payload(wall: 0.995, seconds: 0.995, mode: "quote", bailout: bailout)
      json["eventCount"] = 1; json["wpm"] = 12; json["rawWpm"] = 12
      if bailout { json["terminalTiming"] = ["version": 1, "endMilliseconds": 995, "lastKeypressMilliseconds": 995] }
      let receipt = try await store.submitResult(decode(json), accessToken: token, now: now)
      XCTAssertTrue(receipt.accepted)
    }
    for mode in ["custom", "quote"] {
      var json = try payload(wall: 0.994, seconds: 0.994, mode: mode)
      json["eventCount"] = 1; json["wpm"] = 12; json["rawWpm"] = 12
      try await rejects(decode(json), store: store, token: token)
    }
    var custom = try payload(wall: 0.995, seconds: 0.995, mode: "custom")
    custom["eventCount"] = 1; custom["wpm"] = 12; custom["rawWpm"] = 12
    try await rejects(decode(custom), store: store, token: token)
  }

  func testShortTimeQualificationThresholdUsesRoundedScalarAt120Seconds() async throws {
    let (store, token) = try await account()
    for (seconds, accepted) in [(120.004, false), (120.005, true)] {
      var json = try payload(seconds: seconds, mode: "time")
      json["durationSeconds"] = 121; json["eventCount"] = 100; json["wpm"] = 10; json["rawWpm"] = 10
      if accepted {
        let receipt = try await store.submitResult(decode(json), accessToken: token, now: now)
        XCTAssertTrue(receipt.accepted)
      } else { try await rejects(decode(json), store: store, token: token) }
    }
  }

  func testReloadKeepsExactEvidenceDatesAndDuplicateReceiptWithoutBackfillingLegacy() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-elapsed-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("owned.json")
    let (store, token) = try await account(file: file)
    let input = try decode(payload())
    let originalReceipt = try await store.submitResult(input, accessToken: token, now: now)
    let old = ResultSubmissionRequest(id: UUID(), mode: "words", language: "english", durationSeconds: nil,
      wordLimit: 25, wpm: 30, rawWpm: 30, accuracy: 100, errorCount: 0, eventCount: 40,
      startedAt: now.addingTimeInterval(-16), finishedAt: now)
    _ = try await store.submitResult(old, accessToken: token, now: now)
    let reloaded = try AuthStore(fileURL: file, bcryptCost: 4, minimumLeaderboardTypingSeconds: 0)
    let duplicate = try await reloaded.submitResult(input, accessToken: token, now: now)
    XCTAssertEqual(duplicate.id, originalReceipt.id)
    XCTAssertEqual(duplicate.experienceGained, originalReceipt.experienceGained)
    XCTAssertEqual(duplicate.totalExperience, 38, "Receipt totals reflect both saved results, not the first receipt snapshot")
    var changed = try object(input)
    changed["elapsedTime"] = ["version": 1, "seconds": 16.2]
    let changedReceipt = try await reloaded.submitResult(decode(changed), accessToken: token, now: now)
    XCTAssertEqual(changedReceipt, duplicate, "A duplicate cannot overwrite accepted measurement or add XP")
    let page = try await reloaded.results(.init(), credential: .accessToken(token), now: now)
    XCTAssertEqual(page.total, 2)
    let saved = try XCTUnwrap(page.results.first { $0.id == input.id })
    XCTAssertEqual(saved.startedAt, input.startedAt)
    XCTAssertEqual(saved.finishedAt, input.finishedAt)
    XCTAssertNotNil(try object(saved)["elapsedTime"])
    XCTAssertEqual(saved.elapsedTime?.seconds, 16.125)
    XCTAssertNil(try object(try XCTUnwrap(page.results.first { $0.id == old.id }))["elapsedTime"])
    let stats = await reloaded.publicPracticeStats()
    XCTAssertEqual(stats.totalTypingSeconds, 32)
  }

  func testPersistedExplicitCorruptionCannotReloadAsLegacyTiming() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-elapsed-corruption-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("owned.json")
    let (store, token) = try await account(file: file)
    _ = try await store.submitResult(decode(payload(mode: "zen")), accessToken: token, now: now)
    let original = try Data(contentsOf: file)
    for mutation in 0..<5 {
      var json = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
      var records = try XCTUnwrap(json["results"] as? [[String: Any]])
      switch mutation {
      case 0: records[0]["elapsedTime"] = ["version": 2, "seconds": 16.125]
      case 1: records[0].removeValue(forKey: "startedAtReferenceTime")
      case 2: records[0]["finishedAtReferenceTime"] = 3
      case 3: records[0]["terminalTiming"] = ["version": 1, "endMilliseconds": 16_625, "lastKeypressMilliseconds": 15_000]
      default: records[0]["elapsedTime"] = ["version": 1, "seconds": 0.5]
      }
      json["results"] = records
      try JSONSerialization.data(withJSONObject: json).write(to: file, options: .atomic)
      XCTAssertThrowsError(try AuthStore(fileURL: file, bcryptCost: 4), "Mutation \(mutation) cannot become legacy absence")
    }
    try original.write(to: file, options: .atomic)
    let recovered = try AuthStore(fileURL: file, bcryptCost: 4)
    let history = try await recovered.results(.init(), credential: .accessToken(token), now: now)
    XCTAssertEqual(history.results.first?.elapsedTime?.seconds, 16.125)
  }

  func testPhysicalEvidenceUsesRawButPracticeTimeAndScoreUseTrimmedMeasurement() async throws {
    let (store, token) = try await account()
    for (engaged, speed, accepted) in [(2_000, 32, true), (16_000, 32, false), (2_000, 30, false)] {
      var json = try payload(mode: "zen")
      json["wpm"] = speed; json["rawWpm"] = speed
      json["practiceTiming"] = ["version": 1, "terminalEngagedMilliseconds": engaged, "priorAttemptEngagedMilliseconds": 0]
      json["timingEvidence"] = ["version": 1, "keyDurationMilliseconds": [16_100], "keySpacingMilliseconds": [], "keyOverlapMilliseconds": 0]
      if accepted {
        let receipt = try await store.submitResult(decode(json), accessToken: token, now: now)
        XCTAssertTrue(receipt.accepted)
      } else { try await rejects(decode(json), store: store, token: token) }
    }
    var legacy = try payload(); legacy.removeValue(forKey: "elapsedTime")
    legacy.removeValue(forKey: "startedAtReferenceTime"); legacy.removeValue(forKey: "finishedAtReferenceTime")
    try await rejects(decode(legacy), store: store, token: token)
  }

  func testExactCapabilityAndISOHTTPRoundTripRetainIndependentTimingAndRealDates() async throws {
    let app = try await Application.make(.testing)
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let liveNow = Date.now
    let user = try await store.register(.init(email: "elapsed-http@example.com",
      password: "a secure password", displayName: "Elapsed HTTP"), now: liveNow)
    let input = try decode(payload(end: liveNow, iso: true), iso: true)
    do {
      try configure(app, authStore: store)
      try await app.test(.GET, "v1/capabilities") { response async throws in
        let value = try response.content.decode(ServiceCapabilitiesResponse.self)
        XCTAssertEqual(value.apiVersion, "v1"); XCTAssertEqual(value.service, "typebar")
        XCTAssertEqual(value.capabilities["resultElapsedTime"], .available)
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
        XCTAssertEqual(history.results.first?.elapsedTime?.seconds, 16.125)
        XCTAssertEqual(history.results.first?.startedAt, input.startedAt)
        XCTAssertEqual(history.results.first?.finishedAt, liveNow)
        XCTAssertFalse(response.body.string.contains("prompt")); XCTAssertFalse(response.body.string.contains("keyCode"))
      })
      let inconsistent = try decode(payload(wall: -3_600, mode: "time", end: liveNow, iso: true), iso: true)
      try await app.test(.POST, "v1/results", beforeRequest: { outgoing async throws in
        outgoing.headers.add(name: "Authorization", value: "Bearer \(user.accessToken)")
        try outgoing.content.encode(inconsistent)
      }, afterResponse: { response async in XCTAssertEqual(response.status, .badRequest) })
      var malformed = try payload(end: liveNow, iso: true); malformed.removeValue(forKey: "finishedAtReferenceTime")
      let body = try JSONSerialization.data(withJSONObject: malformed)
      try await app.test(.POST, "v1/results", beforeRequest: { outgoing async in
        outgoing.headers.add(name: "Authorization", value: "Bearer \(user.accessToken)")
        outgoing.headers.contentType = .json; outgoing.body = ByteBuffer(data: body)
      }, afterResponse: { response async in XCTAssertEqual(response.status, .badRequest) })
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }
}
