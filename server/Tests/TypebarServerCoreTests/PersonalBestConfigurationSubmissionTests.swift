import Foundation
import XCTest
import XCTVapor
@testable import TypebarServerCore

final class PersonalBestConfigurationSubmissionTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private var controls: [String: Any] {
    ["version": 1, "difficulty": "master", "punctuation": false, "numbers": false, "lazyMode": true]
  }
  private func payload(id: UUID = UUID()) throws -> [String: Any] {
    let request = ResultSubmissionRequest(id: id, mode: "words", language: "english", durationSeconds: nil,
      wordLimit: 25, wpm: 60, rawWpm: 60, accuracy: 100, errorCount: 0, eventCount: 75,
      startedAt: now.addingTimeInterval(-15), finishedAt: now)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
  }
  private func decode(_ payload: [String: Any]) throws -> ResultSubmissionRequest {
    try JSONDecoder().decode(ResultSubmissionRequest.self, from: JSONSerialization.data(withJSONObject: payload))
  }
  private func directory() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-pb-config-\(UUID())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
    return dir
  }
  private func account(_ store: AuthStore, date: Date? = nil) async throws -> AuthSessionResponse {
    try await store.register(.init(email: "pb@example.com", password: "a secure password", displayName: "PB"), now: date ?? now)
  }
  func testExplicitMalformedConfigurationIsNotSilentlyIgnored() throws {
    for value: Any in [NSNull(), ["version": 2, "difficulty": "master", "punctuation": false,
      "numbers": false, "lazyMode": true], ["version": 1, "difficulty": "master"]] {
      var data = try payload(); data["personalBestConfiguration"] = value
      XCTAssertThrowsError(try decode(data))
    }
  }
  func testAllMandatoryFieldsAndTypesAreRequired() throws {
    for key in controls.keys {
      for value: Any? in [nil, NSNull(), "unsupported"] {
        var report = controls; report[key] = value
        var data = try payload(); data["personalBestConfiguration"] = report
        XCTAssertThrowsError(try decode(data))
      }
    }
  }

  func testKnownFalseAndAbsentLegacyAreDistinctAndLoadNeverRewrites() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("store.json"), store = try AuthStore(fileURL: file, bcryptCost: 4)
    let owner = try await account(store)
    let legacy = try decode(payload())
    var data = try payload(); data["personalBestConfiguration"] = ["version": 1, "difficulty": "normal",
      "punctuation": false, "numbers": false, "lazyMode": false]
    let known = try decode(data)
    for input in [legacy, known] { _ = try await store.submitResult(input, accessToken: owner.accessToken, now: now) }
    let bytes = try Data(contentsOf: file), loaded = try AuthStore(fileURL: file, bcryptCost: 4)
    for input in [legacy, known] {
      let entry = try await loaded.result(id: input.id, credential: .accessToken(owner.accessToken), now: now)
      XCTAssertEqual(entry.personalBestConfiguration, input.personalBestConfiguration)
    }
    XCTAssertNil(legacy.personalBestConfiguration); XCTAssertEqual(known.personalBestConfiguration?.lazyMode, false)
    XCTAssertEqual(try Data(contentsOf: file), bytes)
  }

  func testFiveModesAndEveryDifficultyStoreExplicitControls() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4), owner = try await account(store)
    for mode in ["time", "words", "quote", "custom", "zen"] {
      for difficulty in ["normal", "expert", "master"] {
        var data = try payload(), report = controls; report["difficulty"] = difficulty
        data["mode"] = mode; data["durationSeconds"] = mode == "time" ? 15 : nil
        data["wordLimit"] = mode == "words" ? 25 : nil; data["personalBestConfiguration"] = report
        let input = try decode(data)
        _ = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
        let entry = try await store.result(id: input.id, credential: .accessToken(owner.accessToken), now: now)
        XCTAssertEqual(entry.personalBestConfiguration, input.personalBestConfiguration)
      }
    }
  }

  func testXPFlagConflictAndInvalidProgrammaticConfigurationCannotMutateState() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4), owner = try await account(store)
    let experience = ResultExperienceEvidence(characterCounts: [75,0,0,0], scoringUnitBasis: .utf16,
      durationSeconds: 15, afkSeconds: 0, punctuation: false, numbers: false, modifiers: [])
    for report in [ResultPersonalBestConfiguration(difficulty: "bad", punctuation: false, numbers: false, lazyMode: false),
      .init(difficulty: "normal", punctuation: true, numbers: false, lazyMode: false),
      .init(difficulty: "normal", punctuation: false, numbers: true, lazyMode: false)] {
      let input = ResultSubmissionRequest(id: UUID(), mode: "words", language: "english", durationSeconds: nil,
        wordLimit: 25, wpm: 60, rawWpm: 60, accuracy: 100, errorCount: 0, eventCount: 75,
        experienceEvidence: experience, personalBestConfiguration: report,
        practiceTiming: .init(version: 1, terminalEngagedMilliseconds: 15_000, priorAttemptEngagedMilliseconds: 0),
        inputMetrics: .init(version: 1, correctAttempts: 75, totalAttempts: 75, creditedUnits: 75, retainedUnits: 75),
        startedAt: now.addingTimeInterval(-15), finishedAt: now)
      XCTAssertThrowsError(try JSONDecoder().decode(ResultSubmissionRequest.self, from: JSONEncoder().encode(input)))
      do { _ = try await store.submitResult(input, accessToken: owner.accessToken, now: now); XCTFail("Must reject before mutation") }
      catch let error as ResultStoreError { XCTAssertEqual(error, .invalidResult) }
    }
    let page = try await store.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    XCTAssertEqual(page.total, 0)
    let stats = await store.publicPracticeStats(); XCTAssertEqual(stats.startedTestCount, 0)
  }

  func testCorruptStoredAndImmutableCopiesRejectWithoutWriting() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("store.json"), store = try AuthStore(fileURL: file, bcryptCost: 4)
    let owner = try await account(store)
    var data = try payload(); data["personalBestConfiguration"] = controls
    _ = try await store.submitResult(decode(data), accessToken: owner.accessToken, now: now)
    let original = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    var changed = controls; changed["difficulty"] = "normal"
    for collection in ["results", "experienceAwards"] {
      for value: Any? in [nil, NSNull(), ["version": 2], changed] {
        var state = original, entries = try XCTUnwrap(state[collection] as? [[String: Any]])
        entries[0]["personalBestConfiguration"] = value; state[collection] = entries
        let bytes = try JSONSerialization.data(withJSONObject: state); try bytes.write(to: file)
        XCTAssertThrowsError(try AuthStore(fileURL: file, bcryptCost: 4))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
      }
    }
  }

  func testPersistenceFailureRollsBackThenRetryCapturesOnce() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("store.json"), backup = dir.appendingPathComponent("backup.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4), owner = try await account(store)
    var data = try payload(); data["personalBestConfiguration"] = controls; let input = try decode(data)
    try FileManager.default.moveItem(at: file, to: backup)
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
    do { _ = try await store.submitResult(input, accessToken: owner.accessToken, now: now); XCTFail("Real atomic save must fail") }
    catch { }
    let empty = try await store.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    XCTAssertEqual(empty.total, 0)
    try FileManager.default.removeItem(at: file); try FileManager.default.moveItem(at: backup, to: file)
    let instant = now
    async let first = store.submitResult(input, accessToken: owner.accessToken, now: instant)
    async let second = store.submitResult(input, accessToken: owner.accessToken, now: instant)
    _ = try await [first, second]
    let loaded = try AuthStore(fileURL: file, bcryptCost: 4)
    let page = try await loaded.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    XCTAssertEqual(page.total, 1); XCTAssertEqual(page.results.first?.personalBestConfiguration, input.personalBestConfiguration)
    let state = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    XCTAssertEqual((state["experienceAwards"] as? [[String: Any]])?.count, 1)
  }

  func testActualHTTPNegotiationSubmissionHistoryAndOwnerIsolation() async throws {
    let date = Date.now, store = try AuthStore(fileURL: nil, bcryptCost: 4), owner = try await account(store, date: date)
    let other = try await store.register(.init(email: "other-pb@example.com", password: "a secure password", displayName: "Other"), now: date)
    let report = ResultPersonalBestConfiguration(difficulty: "expert", punctuation: false, numbers: false, lazyMode: true)
    let input = ResultSubmissionRequest(id: UUID(), mode: "words", language: "english", durationSeconds: nil,
      wordLimit: 25, wpm: 60, rawWpm: 60, accuracy: 100, errorCount: 0, eventCount: 75,
      personalBestConfiguration: report, startedAt: date.addingTimeInterval(-15), finishedAt: date)
    let app = try await Application.make(.testing)
    do {
      try configure(app, authStore: store)
      try await app.test(.GET, "v1/capabilities") { response async throws in
        XCTAssertEqual(try response.content.decode(ServiceCapabilitiesResponse.self).capabilities["resultPersonalBestConfiguration"], .available)
      }
      try await app.test(.POST, "v1/results", beforeRequest: { outgoing async throws in
        outgoing.headers.bearerAuthorization = .init(token: owner.accessToken); try outgoing.content.encode(input)
      }, afterResponse: { response async throws in XCTAssertEqual(response.status, .ok) })
      for path in ["v1/results", "v1/results/\(input.id)"] {
        try await app.test(.GET, path, beforeRequest: { outgoing async in
          outgoing.headers.bearerAuthorization = .init(token: owner.accessToken)
        }, afterResponse: { response async throws in
          XCTAssertEqual(response.status, .ok)
          let result = path == "v1/results" ? try response.content.decode(ResultListResponse.self).results.first
            : try response.content.decode(AccountResultResponse.self)
          XCTAssertEqual(result?.personalBestConfiguration, report)
        })
      }
      try await app.test(.GET, "v1/results/\(input.id)", beforeRequest: { outgoing async in
        outgoing.headers.bearerAuthorization = .init(token: other.accessToken)
      }, afterResponse: { response async in XCTAssertEqual(response.status, .notFound) })
      var bad = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
      bad["personalBestConfiguration"] = NSNull(); let body = try JSONSerialization.data(withJSONObject: bad)
      try await app.test(.POST, "v1/results", beforeRequest: { outgoing async in
        outgoing.headers.bearerAuthorization = .init(token: owner.accessToken)
        outgoing.headers.contentType = .json; outgoing.body = ByteBuffer(data: body)
      }, afterResponse: { response async in XCTAssertEqual(response.status, .badRequest) })
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }

  func testRewardInputAndCapturedConfigurationStayBoundAfterHistoryDeletion() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("store.json"), store = try AuthStore(fileURL: file, bcryptCost: 4)
    let owner = try await account(store)
    let report = ResultPersonalBestConfiguration(difficulty: "master", punctuation: true, numbers: true, lazyMode: true)
    let experience = ResultExperienceEvidence(characterCounts: [75,0,0,0], scoringUnitBasis: .utf16,
      durationSeconds: 15, afkSeconds: 0, punctuation: true, numbers: true, modifiers: [])
    let input = ResultSubmissionRequest(id: UUID(), mode: "words", language: "english", durationSeconds: nil,
      wordLimit: 25, wpm: 60, rawWpm: 60, accuracy: 100, errorCount: 0, eventCount: 75,
      experienceEvidence: experience, personalBestConfiguration: report,
      practiceTiming: .init(version: 1, terminalEngagedMilliseconds: 15_000, priorAttemptEngagedMilliseconds: 0),
      inputMetrics: .init(version: 1, correctAttempts: 75, totalAttempts: 75, creditedUnits: 75, retainedUnits: 75),
      startedAt: now.addingTimeInterval(-15), finishedAt: now)
    _ = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    let saved = try await store.result(id: input.id, credential: .accessToken(owner.accessToken), now: now)
    let decoded = try JSONDecoder().decode(AccountResultResponse.self, from: JSONEncoder().encode(saved))
    XCTAssertEqual(decoded.personalBestConfiguration, report)
    _ = try await store.deleteResults(.init(currentPassword: "a secure password"), accessToken: owner.accessToken, now: now)
    let bytes = try Data(contentsOf: file)
    _ = try AuthStore(fileURL: file, bcryptCost: 4)
    XCTAssertEqual(try Data(contentsOf: file), bytes)
    let original = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    for flag in ["punctuation", "numbers"] {
      var state = original, awards = try XCTUnwrap(state["experienceAwards"] as? [[String: Any]])
      var controls = try XCTUnwrap(awards[0]["personalBestConfiguration"] as? [String: Any])
      controls[flag] = false; awards[0]["personalBestConfiguration"] = controls; state["experienceAwards"] = awards
      let corrupt = try JSONSerialization.data(withJSONObject: state); try corrupt.write(to: file)
      XCTAssertThrowsError(try AuthStore(fileURL: file, bcryptCost: 4))
      XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }
  }
  func testHistoryAndFirstAcceptanceEvidenceKeepKnownControlsAcrossDeletionRetryAndReload() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-pb-config-\(UUID())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("store.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4, rankingEnvironment: .development)
    let owner = try await store.register(.init(email: "pb@example.com", password: "a secure password", displayName: "PB"), now: now)
    var data = try payload(); data["personalBestConfiguration"] = controls
    let input = try decode(data)
    _ = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    let loaded = try AuthStore(fileURL: file, bcryptCost: 4, rankingEnvironment: .development)
    let history = try await loaded.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    let entry = try XCTUnwrap(history.results.first)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
    XCTAssertEqual(json["personalBestConfiguration"] as? NSDictionary, controls as NSDictionary)
    _ = try await loaded.deleteResults(.init(currentPassword: "a secure password"), accessToken: owner.accessToken, now: now)
    let bytes = try Data(contentsOf: file)
    var replacement = controls; replacement["difficulty"] = "normal"; replacement["lazyMode"] = false
    data["personalBestConfiguration"] = replacement
    _ = try await loaded.submitResult(decode(data), accessToken: owner.accessToken, now: now)
    XCTAssertEqual(try Data(contentsOf: file), bytes, "A duplicate cannot replace immutable evidence or recreate deleted history")
    let state = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    let awards = try XCTUnwrap(state["experienceAwards"] as? [[String: Any]])
    XCTAssertEqual(awards.first?["personalBestConfiguration"] as? NSDictionary, controls as NSDictionary)
    _ = try AuthStore(fileURL: file, bcryptCost: 4, rankingEnvironment: .development)
  }
}
