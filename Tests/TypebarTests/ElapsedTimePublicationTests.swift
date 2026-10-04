import XCTest
@testable import Typebar

final class ElapsedTimePublicationTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 100.875)

  private func result(mode: TestMode = .words, wall: Double = -3_600,
    seconds: Double = 16.125, terminal: ResultTerminalTiming? = nil,
    outcome: TestOutcome = .completed) -> CompletedTestResult {
    let configuration = TestConfiguration(mode: mode, duration: mode == .time ? 16 : nil,
      wordLimit: mode == .words ? 25 : nil, difficulty: .normal, rules: .init())
    return .init(id: UUID(), configuration: configuration, outcome: outcome,
      startedAt: start, finishedAt: start.addingTimeInterval(wall), afkDuration: 2,
      terminalTiming: terminal, elapsedTime: .init(seconds: seconds),
      typedCharacterCount: 40, correctCharacterCount: 40, errorCount: 0,
      wpm: 30, rawWpm: 30, accuracy: 100, keyDurationSamples: [0.1],
      prompt: "private owned prompt", replayEvents: [.init(offset: 15, kind: .insert, text: "private")])
  }

  private func capabilities(version: String = "v1", service: String = "typebar",
    status: String = "available") -> RemoteServiceCapabilities {
    .init(apiVersion: version, service: service, capabilities: ["resultElapsedTime": status,
      "resultTerminalTiming": "available", "resultBailout": "available",
      "resultTimingEvidence": "available", "resultPracticeTiming": "available"])
  }

  private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
  }

  @MainActor func testNegotiatedWireRetainsRawElapsedTimeAndDatePrecisionButNotPrivateText() async throws {
    let value = result()
    let wire = try await ResultConsistencyPublication.prepare(result: value, capabilities: capabilities())
    let json = try object(wire)
    XCTAssertEqual(json["elapsedTime"] as? NSDictionary, ["version": 1, "seconds": 16.125] as NSDictionary)
    XCTAssertEqual(json["startedAtReferenceTime"] as? Double, value.startedAt.timeIntervalSinceReferenceDate)
    XCTAssertEqual(json["finishedAtReferenceTime"] as? Double, value.finishedAt.timeIntervalSinceReferenceDate)
    XCTAssertNotNil(json["timingEvidence"], "Physical samples bind to raw duration, not a zero calendar gap")
    XCTAssertEqual((json["practiceTiming"] as? [String: Int])?["terminalEngagedMilliseconds"], 14_130)
    for key in ["prompt", "replayEvents", "inputText", "keyCode", "clockOrigin", "uptime"] {
      XCTAssertNil(json[key])
    }
  }

  @MainActor func testExactElapsedCapabilityIsRequiredBeforeMetricWork() async {
    for capability in [nil, capabilities(version: "v2"), capabilities(service: "other"),
      capabilities(status: "partial"), capabilities(status: "planned")] {
      do {
        _ = try await ResultConsistencyPublication.prepare(result: result(), capabilities: capability) { _ in
          XCTFail("Unsupported elapsed-time capability cannot start work"); return 0
        }
        XCTFail("Do not downgrade independent duration")
      } catch { XCTAssertTrue(error is RemoteAccountError) }
    }
  }

  func testRawChartBoundaryAndRoundedScalarDurationRemainDistinct() {
    let words = result()
    XCTAssertEqual(words.capturedDuration, 16.125)
    XCTAssertEqual(words.chartDuration, 16.125)
    XCTAssertEqual(words.elapsedDuration, 16.13)
    let custom = result(mode: .custom)
    XCTAssertEqual(custom.elapsedDuration, 16.125)
  }

  @MainActor func testTemporaryCapabilityFailureAndCancellationCannotDowngradeNewCompletedResult() async throws {
    for failure: Error in [URLError(.notConnectedToInternet),
      RemoteAccountError.serverResponse(statusCode: 503, message: "temporary")] {
      do {
        _ = try await RemoteResultBailoutPolicy.capabilities(for: .completed, requiresElapsedTime: true) { throw failure }
        XCTFail("Independent timing must remain retryable, not become unsupported legacy")
      } catch { XCTAssertTrue(ResultPublicationRetryPolicy.shouldQueue(error)) }
    }
    do {
      _ = try await RemoteResultBailoutPolicy.capabilities(for: .completed, requiresElapsedTime: true) { throw CancellationError() }
      XCTFail("Cancellation must propagate")
    } catch { XCTAssertTrue(error is CancellationError) }
    let missing = try await RemoteResultBailoutPolicy.capabilities(for: .completed, requiresElapsedTime: true) {
      throw RemoteAccountError.serverResponse(statusCode: 404, message: "legacy")
    }
    XCTAssertNil(missing)
    let legacy = try await RemoteResultBailoutPolicy.capabilities(for: .completed) {
      throw RemoteAccountError.serverResponse(statusCode: 503, message: "legacy fallback")
    }
    XCTAssertNil(legacy)
  }

  func testServiceMinimumAndShortTimeThresholdUseRoundedScalarNotRawSeconds() {
    let fractional = ResultElapsedTime(seconds: 0.995)
    XCTAssertTrue(fractional.isServiceCompatible(mode: .quote, bailedOut: false, calendarSeconds: 0.995))
    XCTAssertFalse(fractional.isServiceCompatible(mode: .custom, bailedOut: false, calendarSeconds: 0.995))
    XCTAssertFalse(ResultElapsedTime(seconds: 0.994).isServiceCompatible(mode: .quote,
      bailedOut: false, calendarSeconds: 0.994))
    XCTAssertFalse(ResultElapsedTime(seconds: 120.004).isServiceCompatible(mode: .time,
      bailedOut: false, calendarSeconds: -3_600))
    XCTAssertTrue(ResultElapsedTime(seconds: 120.005).isServiceCompatible(mode: .time,
      bailedOut: false, calendarSeconds: -3_600))
  }

  @MainActor func testShortTimedDateMismatchCannotPublishButBailoutStillUsesItsOwnRules() async throws {
    for wall in [-3_600.0, 3_600, 16.24] {
      do {
        _ = try await ResultConsistencyPublication.prepare(result: result(mode: .time, wall: wall), capabilities: capabilities())
        XCTFail("Ordinary short timed date mismatch must be refused")
      } catch { XCTAssertTrue(error is RemoteAccountError) }
    }
    _ = try await ResultConsistencyPublication.prepare(result: result(mode: .time, wall: 16.2), capabilities: capabilities())
    let timing = ResultTerminalTiming(version: 1, endMilliseconds: 16_125, lastKeypressMilliseconds: 15_000)
    let wire = try await ResultConsistencyPublication.prepare(result: result(mode: .time,
      terminal: timing, outcome: .bailedOut), capabilities: capabilities())
    XCTAssertEqual(try object(wire)["bailedOut"] as? Bool, true)
    XCTAssertEqual(try object(wire)["elapsedTime"] as? NSDictionary, ["version": 1, "seconds": 16.125] as NSDictionary)
  }

  private func history(wall: Double = -3_600, seconds: Any = 16.125,
    mode: String = "words", version: Int = 1) -> [String: Any] {
    let end = start.addingTimeInterval(wall)
    return ["id": UUID().uuidString, "mode": mode, "language": "english",
      "wordLimit": 25, "durationSeconds": 16, "wpm": 30, "rawWpm": 30, "accuracy": 100,
      "errorCount": 0, "eventCount": 40, "tags": [],
      "startedAt": start.timeIntervalSinceReferenceDate, "finishedAt": end.timeIntervalSinceReferenceDate,
      "startedAtReferenceTime": start.timeIntervalSinceReferenceDate,
      "finishedAtReferenceTime": end.timeIntervalSinceReferenceDate,
      "elapsedTime": ["version": version, "seconds": seconds]]
  }

  private func decode(_ json: [String: Any]) throws -> RemoteAccountResult {
    let decoder = JSONDecoder()
    decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity",
      negativeInfinity: "-Infinity", nan: "NaN")
    return try decoder.decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: json))
  }

  func testHistoryAndCSVDoNotReplaceIndependentTimeWithDateGap() throws {
    let remote = try decode(history())
    XCTAssertEqual(remote.elapsedDuration, 16.13)
    XCTAssertEqual(remote.startedAt, start)
    XCTAssertEqual(remote.finishedAt, start.addingTimeInterval(-3_600))
    XCTAssertNotNil(try object(remote)["elapsedTime"])
    let row = RemoteResultCSVExport.csvString(for: [remote]).components(separatedBy: "\r\n")[1].components(separatedBy: ",")
    let fields = Dictionary(uniqueKeysWithValues: zip(RemoteResultCSVExport.columns, row))
    XCTAssertEqual(fields["elapsed_seconds"], "16.13")
    XCTAssertEqual(fields["wall_clock_seconds"], "0.00")
  }

  func testRemoteHistoryRetainsRoundedSubsecondQuoteAndRejectsWrongRawTerminalBoundary() throws {
    var quote = history(wall: 0.995, seconds: 0.995, mode: "quote")
    quote["eventCount"] = 1; quote["wpm"] = 12; quote["rawWpm"] = 12
    quote["bailedOut"] = true
    quote["terminalTiming"] = ["version": 1, "endMilliseconds": 995, "lastKeypressMilliseconds": 995]
    XCTAssertEqual(try decode(quote).elapsedDuration, 1)
    var zen = history(mode: "zen")
    zen["terminalTiming"] = ["version": 1, "endMilliseconds": 16_125, "lastKeypressMilliseconds": 15_000]
    XCTAssertEqual(try decode(zen).elapsedDuration, 15)
    zen["terminalTiming"] = ["version": 1, "endMilliseconds": 16_625, "lastKeypressMilliseconds": 15_000]
    XCTAssertThrowsError(try decode(zen), "New precision cannot inherit the legacy one-second ISO tolerance")
  }

  func testMalformedRemoteElapsedTimeAndMissingOrConflictingDatePrecisionReject() throws {
    for seconds: Any in [-1, 0, 3_601, "NaN", "Infinity", "bad"] {
      XCTAssertThrowsError(try decode(history(wall: 16, seconds: seconds)))
    }
    XCTAssertThrowsError(try decode(history(wall: 16, version: 2)))
    for key in ["startedAtReferenceTime", "finishedAtReferenceTime"] {
      var json = history(wall: 16); json.removeValue(forKey: key)
      XCTAssertThrowsError(try decode(json))
      json[key] = 3
      XCTAssertThrowsError(try decode(json))
    }
    XCTAssertThrowsError(try decode(history(mode: "time")))
    XCTAssertThrowsError(try decode(history(mode: "unknown")))
  }

  func testLegacyWireStillOmitsIndependentTimingAndDatePrecision() throws {
    let value = CompletedTestResult(id: UUID(), configuration: .words(25), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(16.125), typedCharacterCount: 40,
      correctCharacterCount: 40, errorCount: 0, wpm: 30, rawWpm: 30, accuracy: 100)
    let json = try object(RemoteResultSubmission(result: value))
    for key in ["elapsedTime", "startedAtReferenceTime", "finishedAtReferenceTime"] { XCTAssertNil(json[key]) }
    XCTAssertEqual(value.elapsedDuration, 16.125)
  }
}
