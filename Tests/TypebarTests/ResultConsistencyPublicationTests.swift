import XCTest
@testable import Typebar

private actor ConsistencyPublicationGate {
  private var entered = false
  private var waiter: CheckedContinuation<Void, Never>?
  private var observer: CheckedContinuation<Void, Never>?
  private(set) var cancelled = false
  func pause() async {
    entered = true; observer?.resume(); observer = nil
    await withCheckedContinuation { waiter = $0 }
    cancelled = Task.isCancelled
  }
  func waitForEntry() async {
    if entered { return }
    await withCheckedContinuation { observer = $0 }
  }
  func open() { waiter?.resume(); waiter = nil }
}

final class ResultConsistencyPublicationTests: XCTestCase {
  private func result(fields: Bool = true, spacing: [Double] = [0.1, 0.2, 0.9]) -> CompletedTestResult {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, units: [120], inputField: fields ? .init(index: 0, units: [120]) : nil),
      .init(offset: 0.5, kind: .delete, units: [], inputField: fields ? .init(index: 0, units: []) : nil),
      .init(offset: 1.2, kind: .insert, units: [97], inputField: fields ? .init(index: 0, units: [97]) : nil)]
    let start = Date(timeIntervalSince1970: 100)
    return .init(id: UUID(), configuration: .words(1), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(2),
      typedCharacterCount: 1, correctCharacterCount: 1, errorCount: 0, wpm: 6, rawWpm: 6,
      accuracy: 100, keySpacingSamples: spacing, prompt: "ab", replayEvents: events)
  }

  private func capabilities(version: String = "v1", service: String = "typebar", status: String = "available") -> RemoteServiceCapabilities {
    .init(apiVersion: version, service: service, capabilities: ["resultConsistency": status])
  }

  private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
  }

  @MainActor func testNegotiatedSubmissionSeparatesAllThreeMetricsWithoutTextOrReplay() async throws {
    let value = result()
    let wire = try await ResultConsistencyPublication.prepare(result: value, capabilities: capabilities())
    let json = try object(wire)
    let metrics = try XCTUnwrap(json["resultConsistency"] as? [String: Double])
    XCTAssertEqual(metrics, ["version": 1, "keyConsistency": 66.67, "wpmConsistency": 8.90])
    XCTAssertEqual(json["consistency"] as? Double, 100)
    for key in ["prompt", "replayEvents", "keySpacingSamples", "keyCode", "targetWordDirectory"] {
      XCTAssertNil(json[key]); XCTAssertNil(metrics[key])
    }
  }

  @MainActor func testOnlyExactAdvertisedCapabilityMayChangeTheLegacyWire() async throws {
    for capabilities in [nil, capabilities(version: "v2"), capabilities(service: "other"),
      capabilities(status: "partial"), capabilities(status: "planned"), capabilities(status: "")] {
      let wire = try await ResultConsistencyPublication.prepare(result: result(), capabilities: capabilities) { _ in
        XCTFail("Unsupported service must not start WPM work"); return 44
      }
      XCTAssertNil(try object(wire)["resultConsistency"])
    }
  }

  @MainActor func testMissingFieldEvidenceOmitsWPMWithoutInventingZeroOrLosingPhysicalMetric() async throws {
    let wire = try await ResultConsistencyPublication.prepare(result: result(fields: false), capabilities: capabilities())
    let metrics = try XCTUnwrap(try object(wire)["resultConsistency"] as? [String: Double])
    XCTAssertEqual(metrics["keyConsistency"], 66.67)
    XCTAssertNil(metrics["wpmConsistency"])
  }

  @MainActor func testEmptyPhysicalSpacingUsesTheExistingSourceEmptyStatistic() async throws {
    let wire = try await ResultConsistencyPublication.prepare(result: result(spacing: []), capabilities: capabilities())
    let metrics = try XCTUnwrap(try object(wire)["resultConsistency"] as? [String: Double])
    XCTAssertEqual(metrics["keyConsistency"], 0)
    XCTAssertEqual(metrics["wpmConsistency"], 8.9)
  }

  @MainActor func testCancellationAfterWorkStartsDoesNotProduceASubmittablePayload() async throws {
    let gate = ConsistencyPublicationGate(), value = result(), capability = capabilities()
    let task = Task {
      try await ResultConsistencyPublication.prepare(result: value, capabilities: capability) { _ in
        await gate.pause(); return 88
      }
    }
    await gate.waitForEntry(); task.cancel(); await gate.open()
    do { _ = try await task.value; XCTFail("Cancelled preparation must not return a request") }
    catch is CancellationError {}
    let cancelled = await gate.cancelled
    XCTAssertTrue(cancelled)
  }

  @MainActor func testCancellationBeforePreparationDoesNotStartCalculation() async throws {
    let gate = ConsistencyPublicationGate(), value = result(), capability = capabilities()
    let task = Task {
      await gate.pause()
      return try await ResultConsistencyPublication.prepare(result: value, capabilities: capability) { _ in
        XCTFail("A cancelled publication cannot start calculation"); return 88
      }
    }
    await gate.waitForEntry(); task.cancel(); await gate.open()
    do { _ = try await task.value; XCTFail("Cancelled preparation must throw") }
    catch is CancellationError {}
  }

  func testInvalidHistoryPhysicalMetricsAreRejectedNotRoundedOrClamped() throws {
    let decoder = JSONDecoder()
    decoder.nonConformingFloatDecodingStrategy = .convertFromString(
      positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
    for physical: Any in [-1, 101, "NaN", "Infinity", "-Infinity", "invalid"] {
      let json: [String: Any] = ["id": UUID().uuidString, "mode": "time", "language": "english",
        "wpm": 80, "rawWpm": 80, "accuracy": 100, "consistency": 71.5, "keyConsistency": physical,
        "errorCount": 0, "eventCount": 100, "tags": [], "startedAt": 100, "finishedAt": 115]
      XCTAssertThrowsError(try decoder.decode(RemoteAccountResult.self,
        from: JSONSerialization.data(withJSONObject: json)))
    }
  }

  func testRemoteHistoryAndCSVKeepAnOptionalPhysicalMetricAndNoWPMField() throws {
    var json: [String: Any] = ["id": UUID().uuidString, "mode": "time", "language": "english",
      "durationSeconds": 15, "wpm": 80, "rawWpm": 80, "accuracy": 100, "consistency": 71.5,
      "errorCount": 0, "eventCount": 100, "tags": [], "startedAt": 100, "finishedAt": 115]
    for physical: Double? in [nil, 66.67] {
      json["keyConsistency"] = physical
      let remote = try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: json))
      XCTAssertEqual(try object(remote)["keyConsistency"] as? Double, physical)
      let csv = RemoteResultCSVExport.csvString(for: [remote]).components(separatedBy: "\r\n")
      let row = csv[1].components(separatedBy: ",")
      XCTAssertEqual(row.count, RemoteResultCSVExport.columns.count)
      let fields = Dictionary(uniqueKeysWithValues: zip(RemoteResultCSVExport.columns, row))
      XCTAssertEqual(fields["key_consistency_percent"], physical == nil ? "" : "66.67")
      XCTAssertEqual(fields["consistency_percent"], "71.50")
      XCTAssertTrue(RemoteResultCSVExport.columns.contains("key_consistency_percent"))
      XCTAssertNil(fields["wpm_consistency_percent"])
    }
  }
}
