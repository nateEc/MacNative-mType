import XCTest
@testable import Typebar

final class BailoutPublicationTests: XCTestCase {
  private func result(_ configuration: TestConfiguration = .timed(seconds: 60),
    outcome: TestOutcome = .bailedOut) -> CompletedTestResult {
    let start = Date(timeIntervalSince1970: 100)
    return .init(id: UUID(), configuration: configuration, outcome: outcome,
      startedAt: start, finishedAt: start.addingTimeInterval(16),
      terminalTiming: outcome == .bailedOut ? .init(version: 1, endMilliseconds: 16_000,
        lastKeypressMilliseconds: 15_000) : nil,
      typedCharacterCount: 100, correctCharacterCount: 100, errorCount: 0,
      wpm: 80, rawWpm: 80, accuracy: 100, prompt: "private custom prompt")
  }

  private func capabilities(version: String = "v1", service: String = "typebar",
    status: String = "available", timing: Bool = true) -> RemoteServiceCapabilities {
    var fields = ["resultBailout": status]
    if timing { fields["resultTerminalTiming"] = "available" }
    return .init(apiVersion: version, service: service, capabilities: fields)
  }

  private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
  }

  @MainActor func testSupportedBailoutPublishesExplicitStateWithoutPromptOrReplay() async throws {
    let wire = try await ResultConsistencyPublication.prepare(result: result(), capabilities: capabilities())
    let json = try object(wire)
    XCTAssertEqual(json["bailedOut"] as? Bool, true)
    XCTAssertEqual(json["durationSeconds"] as? Int, 60)
    XCTAssertNotNil(json["terminalTiming"])
    XCTAssertNil(json["customLimit"])
    for field in ["prompt", "replayEvents", "typed", "inputText", "keyCode"] { XCTAssertNil(json[field]) }
  }

  @MainActor func testIndependentExactCapabilityIsRequiredBeforeAnyMetricWork() async {
    for unsupported in [nil, capabilities(version: "v2"), capabilities(service: "other"),
      capabilities(status: "partial"), capabilities(status: "planned"), capabilities(timing: false)] {
      do {
        _ = try await ResultConsistencyPublication.prepare(result: result(), capabilities: unsupported) { _ in
          XCTFail("Unsupported BailOut must fail before expensive metric work"); return 0
        }
        XCTFail("Unsupported server must not receive a completed-looking BailOut")
      } catch { XCTAssertTrue(error is RemoteAccountError) }
    }
  }

  func testCompletedWireKeepsMissingOptionalBailoutFields() throws {
    let json = try object(RemoteResultSubmission(result: result(outcome: .completed)))
    XCTAssertNil(json["bailedOut"])
    XCTAssertNil(json["customLimit"])
  }

  @MainActor func testRetryKeepsIDOutcomeAndScopeWithoutCachingPayload() async throws {
    let suite = "TypebarTests.BailoutRetry.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let pending = PendingResultPublicationStore(defaults: defaults)
    let scope = ResultPublicationScope(endpoint: "http://127.0.0.1:8080", userID: UUID())
    let other = ResultPublicationScope(endpoint: "http://127.0.0.1:8080", userID: UUID())
    let attempt = result()
    XCTAssertTrue(ResultPublicationRetryPolicy.shouldQueue(RemoteAccountError.serverResponse(statusCode: 503, message: "temporary")))
    pending.enqueue(attempt.id, for: scope); pending.enqueue(attempt.id, for: scope)
    let reloaded = PendingResultPublicationStore(defaults: defaults)
    XCTAssertEqual(reloaded.resultIDs(for: scope), [attempt.id])
    XCTAssertTrue(reloaded.resultIDs(for: other).isEmpty)
    let retry = try await ResultConsistencyPublication.prepare(result: attempt, capabilities: capabilities())
    XCTAssertEqual(retry.id, attempt.id)
    XCTAssertEqual(try object(retry)["bailedOut"] as? Bool, true)
    XCTAssertFalse(ResultPublicationRetryPolicy.shouldQueue(RemoteAccountError.serverResponse(statusCode: 400, message: "too short")))
    XCTAssertFalse(ResultPublicationRetryPolicy.shouldQueue(RemoteAccountError.serverMessage("unsupported BailOut")))
    reloaded.remove(attempt.id, for: other)
    XCTAssertEqual(reloaded.resultIDs(for: scope), [attempt.id])
    reloaded.remove(attempt.id, for: scope)
    XCTAssertTrue(reloaded.resultIDs(for: scope).isEmpty)
  }

  @MainActor func testTemporaryCapabilityLookupFailureIsRetryableNotUnsupportedBailout() async throws {
    for failure: Error in [URLError(.notConnectedToInternet), RemoteAccountError.serverResponse(statusCode: 503, message: "temporary")] {
      do {
        _ = try await RemoteResultBailoutPolicy.capabilities(for: .bailedOut) { throw failure }
        XCTFail("Temporary failure must propagate, not erase the pending BailOut")
      } catch { XCTAssertTrue(ResultPublicationRetryPolicy.shouldQueue(error)) }
    }
    let missing = try await RemoteResultBailoutPolicy.capabilities(for: .bailedOut) {
      throw RemoteAccountError.serverResponse(statusCode: 404, message: "legacy")
    }
    XCTAssertNil(missing)
    let completed = try await RemoteResultBailoutPolicy.capabilities(for: .completed) {
      throw RemoteAccountError.serverResponse(statusCode: 503, message: "legacy completed fallback unchanged")
    }
    XCTAssertNil(completed)
  }

  @MainActor func testCustomCompletionMapsOnlyAnonymousLimitNotPrivateText() async throws {
    for (completion, mode, value): (CustomTextCompletion, String, Int) in [(.finish, "none", 0),
      (.time, "time", 60), (.words, "word", 25), (.sections, "section", 10)] {
      let configuration = TestConfiguration(mode: .custom, duration: completion == .time ? 60 : nil,
        wordLimit: completion == .words ? 25 : nil, difficulty: .normal, rules: .init(),
        customTextCompletion: completion, customTextSectionLimit: completion == .sections ? 10 : nil)
      let wire = try await ResultConsistencyPublication.prepare(result: result(configuration), capabilities: capabilities())
      XCTAssertEqual(try object(wire)["customLimit"] as? NSDictionary, ["mode": mode, "value": value] as NSDictionary)
      XCTAssertFalse(String(decoding: try JSONEncoder().encode(wire), as: UTF8.self).contains("private custom prompt"))
    }
  }

  private func history(mode: String = "time", measured: Double = 15, flag: Bool? = true,
    custom: [String: Any]? = nil, timing: Bool = true) throws -> RemoteAccountResult {
    let wall = mode == "quote" ? measured + 1 : 16
    var json: [String: Any] = ["id": UUID().uuidString, "mode": mode, "language": "english",
      "wpm": 80, "rawWpm": 80, "accuracy": 100, "errorCount": 0, "eventCount": 100,
      "startedAt": 100, "finishedAt": 100 + wall]
    if mode == "time" { json["durationSeconds"] = 60 }
    if mode == "words" { json["wordLimit"] = 25 }
    json["bailedOut"] = flag; json["customLimit"] = custom
    if timing { json["terminalTiming"] = ["version": 1, "endMilliseconds": wall * 1_000,
      "lastKeypressMilliseconds": measured * 1_000] }
    return try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: json))
  }

  func testHistoryAndCSVRetainExplicitBailoutAndCustomRawDuration() throws {
    let value = try history(mode: "custom", measured: 15.12789, custom: ["mode": "none", "value": 0])
    XCTAssertEqual(value.elapsedDuration, 15.12789, accuracy: 0.0000001)
    XCTAssertEqual(try object(value)["bailedOut"] as? Bool, true)
    let row = RemoteResultCSVExport.csvString(for: [value]).components(separatedBy: "\r\n")[1].components(separatedBy: ",")
    let fields = Dictionary(uniqueKeysWithValues: zip(RemoteResultCSVExport.columns, row))
    XCTAssertEqual(fields["bailed_out"], "true")
    XCTAssertEqual(fields["custom_limit_mode"], "none")
    XCTAssertEqual(fields["custom_limit_value"], "0")
    XCTAssertEqual(fields["elapsed_seconds"], "15.13")
    XCTAssertEqual(fields["wall_clock_seconds"], "16.00")
  }

  func testInvalidHistoryContextCannotSilentlyBecomeLegacyCompleted() throws {
    for mode in ["time", "words", "custom", "zen"] {
      XCTAssertThrowsError(try history(mode: mode, measured: 14.99,
        custom: mode == "custom" ? ["mode": "none", "value": 0] : nil))
    }
    XCTAssertThrowsError(try history(flag: nil))
    XCTAssertThrowsError(try history(flag: false))
    XCTAssertThrowsError(try history(mode: "custom"))
    XCTAssertThrowsError(try history(mode: "custom", custom: ["mode": "word", "value": -1]))
    XCTAssertThrowsError(try history(custom: ["mode": "none", "value": 0]))
    let quote = try history(mode: "quote", measured: 1)
    XCTAssertEqual(quote.elapsedDuration, 1)
    let legacy = try history(flag: nil, timing: false)
    XCTAssertEqual(legacy.elapsedDuration, 16)
    XCTAssertNil(try object(legacy)["bailedOut"])
  }
}
