import XCTest
import SwiftData
@testable import Typebar

final class VersionedInputMetricsTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 910_800_000)
  private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
  }
  private func expanded(_ basis: String = "koreanJamo", retained: Int = 5) -> [String: Any] {
    ["version": 2, "correctAttempts": 1, "totalAttempts": 1,
      "creditedUnits": retained, "retainedUnits": retained,
      "retainedInputUnits": 1, "scoringUnitBasis": basis]
  }

  func testTerminalSpaceProducesExplicitVersionTwoWithoutChangingReplayOrAttempts() throws {
    var input = TypingSession(configuration: .words(1), prompt: "ab")
    input.insertBatch("a", at: start)
    input.insertBatch("b ", at: start.addingTimeInterval(2))
    let saved = try XCTUnwrap(input.result())
    let metrics = try object(try XCTUnwrap(saved.inputMetrics))
    XCTAssertEqual(metrics["version"] as? Int, 2)
    XCTAssertEqual(metrics["retainedInputUnits"] as? Int, 2)
    XCTAssertEqual(metrics["scoringUnitBasis"] as? String, "utf16")
    XCTAssertEqual(metrics["totalAttempts"] as? Int, 3)
    XCTAssertEqual(metrics["correctAttempts"] as? Int, 2)
    XCTAssertEqual(metrics["retainedUnits"] as? Int, 2)
    XCTAssertEqual(saved.typedCharacterCount, 3)
    XCTAssertEqual(saved.wpm, 12)
    XCTAssertEqual(saved.rawWpm, 12)
    XCTAssertEqual(saved.preciseAccuracy, 66.67)
    XCTAssertEqual(TypingReplay.typedText(events: saved.replayEvents, through: 2), "ab ")
  }

  func testExpandedUnitsRoundTripWithTheirExplicitBasis() throws {
    let metrics = try JSONDecoder().decode(ResultInputMetrics.self,
      from: JSONSerialization.data(withJSONObject: expanded()))
    XCTAssertEqual(try object(metrics)["scoringUnitBasis"] as? String, "koreanJamo")
    XCTAssertEqual(try object(metrics)["retainedInputUnits"] as? Int, 1)
    XCTAssertEqual(metrics.retainedUnits, 5)
    XCTAssertEqual(metrics.totalAttempts, 1)
  }

  func testMalformedVersionTwoAndDisguisedVersionOneAreRejectedLocally() throws {
    var invalid: [[String: Any]] = []
    for key in ["scoringUnitBasis", "retainedInputUnits"] {
      var value = expanded(); value.removeValue(forKey: key); invalid.append(value)
    }
    var disguised = expanded(); disguised["version"] = 1; invalid.append(disguised)
    var unknown = expanded(); unknown["version"] = 3; invalid.append(unknown)
    invalid.append(expanded("other"))
    invalid.append(expanded("utf16"))
    invalid.append(expanded(retained: 6))
    var tooFew = expanded(); tooFew["retainedInputUnits"] = 6; invalid.append(tooFew)
    var overflow = expanded(); overflow["retainedInputUnits"] = Int.max; invalid.append(overflow)
    var multiplicationOverflow = expanded()
    multiplicationOverflow["totalAttempts"] = Int.max
    multiplicationOverflow["retainedInputUnits"] = Int.max
    multiplicationOverflow["retainedUnits"] = Int.max
    invalid.append(multiplicationOverflow)
    for (key, bad) in [("totalAttempts",-1), ("correctAttempts",-1), ("correctAttempts",2),
      ("retainedInputUnits",-1), ("creditedUnits",-1), ("creditedUnits",6), ("retainedUnits",-1)] {
      var value = expanded(); value[key] = bad; invalid.append(value)
    }
    for value in invalid {
      XCTAssertThrowsError(try JSONDecoder().decode(ResultInputMetrics.self,
        from: JSONSerialization.data(withJSONObject: value)), "\(value)")
    }
  }

  func testUntrimmedProducerAndGenuineVersionOneKeepTheOriginalWireShape() throws {
    var input = TypingSession(configuration: .words(1), prompt: "ab")
    input.insertBatch("a", at: start); input.insertBatch("b", at: start.addingTimeInterval(2))
    let metrics = try XCTUnwrap(input.result()?.inputMetrics)
    XCTAssertEqual(try object(metrics) as? [String: Int], ["version": 1,
      "correctAttempts": 2, "totalAttempts": 2, "creditedUnits": 2, "retainedUnits": 2])
    let restored = try JSONDecoder().decode(ResultInputMetrics.self, from: JSONEncoder().encode(metrics))
    XCTAssertEqual(restored, metrics)
    let saved = try XCTUnwrap(input.result())
    XCTAssertEqual(RemoteResultSubmission(result: saved, includesInputMetrics: true,
      includesInputMetricsV2: true).inputMetrics, metrics)
    let v2Only = try XCTUnwrap(RemoteResultSubmission(result: saved, includesInputMetricsV2: true).inputMetrics)
    XCTAssertEqual(v2Only.version, 2)
    XCTAssertEqual(v2Only.retainedInputUnits, 2)
    XCTAssertEqual(v2Only.scoringUnitBasis, .utf16)
    XCTAssertEqual(v2Only.correctAttempts, metrics.correctAttempts)
    XCTAssertEqual(v2Only.totalAttempts, metrics.totalAttempts)
  }

  private func trimmed() throws -> CompletedTestResult {
    var input = TypingSession(configuration: .words(1), prompt: "ab")
    input.insertBatch("a", at: start); input.insertBatch("b ", at: start.addingTimeInterval(2))
    return try XCTUnwrap(input.result())
  }

  func testExactNewCapabilityAndExplicitNegotiationDoNotLeakRawInput() throws {
    let saved = try trimmed()
    for (api, service, state, expected) in [("v1","typebar","available",true),
      ("v2","typebar","available",false), ("v1","other","available",false),
      ("v1","typebar","partial",false), ("v1","typebar","",false)] {
      let capabilities = RemoteServiceCapabilities(apiVersion: api, service: service,
        capabilities: ["resultInputMetricsV2": state])
      XCTAssertEqual(capabilities.supportsResultInputMetricsV2, expected)
    }
    let body = try object(RemoteResultSubmission(result: saved, includesInputMetricsV2: true))
    XCTAssertEqual(body["inputMetrics"] as? NSDictionary, try object(try XCTUnwrap(saved.inputMetrics)) as NSDictionary)
    let encoded = String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self)
    for forbidden in ["prompt", "replayEvents", "keyCode", "inputField"] {
      XCTAssertFalse(encoded.contains(forbidden))
    }
    XCTAssertNil(try object(RemoteResultSubmission(result: saved, includesInputMetrics: true))["inputMetrics"])
    XCTAssertNil(try object(RemoteResultSubmission(result: saved))["inputMetrics"])
  }

  func testOldOrUnavailableServiceFailsExplicitlyBeforePostingVersionTwo() throws {
    let saved = try trimmed()
    let old = RemoteServiceCapabilities(apiVersion: "v1", service: "typebar",
      capabilities: ["resultInputMetrics": "available"])
    for capabilities: RemoteServiceCapabilities? in [nil, old,
      .init(apiVersion: "v2", service: "typebar", capabilities: ["resultInputMetricsV2": "available"]),
      .init(apiVersion: "v1", service: "typebar", capabilities: ["resultInputMetricsV2": "partial"])] {
      XCTAssertThrowsError(try ResultInputMetricsPublicationPolicy.validate(saved, capabilities: capabilities))
    }
    XCTAssertNoThrow(try ResultInputMetricsPublicationPolicy.validate(saved,
      capabilities: .init(apiVersion: "v1", service: "typebar", capabilities: ["resultInputMetricsV2": "available"])))
  }

  @MainActor func testFormalPortableAndInMemoryEntityPreserveNewAnonymousCounters() throws {
    let saved = try trimmed()
    let formal = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [saved], presets: [], at: start))
    XCTAssertEqual(formal.version, TypebarArchive.currentVersion)
    XCTAssertEqual(formal.results.first, saved)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: saved).portableResult), saved)
    let container = try ModelContainer(for: TestResultRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    container.mainContext.insert(TestResultRecord(result: saved)); try container.mainContext.save()
    XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).first?.portableResult, saved)
  }

  func testVersionTwoArchiveCannotMasqueradeAsOneThroughTwenty() throws {
    let saved = try trimmed()
    let data = try TypebarDataTransfer.exportArchive(settings: .init(), results: [saved], presets: [], at: start)
    var value = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    for version in 1...20 {
      XCTAssertEqual(TypebarArchive(version: version, exportedAt: start,
        settings: .init(), results: [saved], presets: []).version, 21)
      value["version"] = version
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: value))) {
        XCTAssertEqual($0 as? DataTransferError, .unsupportedVersion(version))
      }
    }
  }

  func testGenuineTrimmedVersionOneArchiveRemainsTwentyButCanNegotiateVersionTwoWire() throws {
    // Independent owned old producer fixture, not a new session with keys stripped.
    let old = CompletedTestResult(id: UUID(), configuration: .words(1), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(2), typedCharacterCount: 3,
      correctCharacterCount: 2, errorCount: 0, wpm: 12, rawWpm: 12, accuracy: 67,
      preciseAccuracy: 66.67, inputMetrics: .init(version: 1, correctAttempts: 2,
        totalAttempts: 3, creditedUnits: 2, retainedUnits: 2))
    let archive = TypebarArchive(version: 20, exportedAt: start, settings: .init(), results: [old], presets: [])
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    let restored = try TypebarDataTransfer.importArchive(from: encoder.encode(archive))
    XCTAssertEqual(restored.version, 20); XCTAssertEqual(restored.results[0], old)
    XCTAssertEqual(old.inputMetrics?.version, 1)
    XCTAssertThrowsError(try ResultInputMetricsPublicationPolicy.validate(old, capabilities: nil))
    let body = try object(RemoteResultSubmission(result: old, includesInputMetricsV2: true))
    let metrics = try XCTUnwrap(body["inputMetrics"] as? [String: Any])
    XCTAssertEqual(metrics["version"] as? Int, 2)
    XCTAssertEqual(metrics["scoringUnitBasis"] as? String, "utf16")
    XCTAssertEqual(metrics["totalAttempts"] as? Int, 3)
    XCTAssertEqual(body["wpm"] as? Int, old.wpm)
    XCTAssertEqual(body["rawWpm"] as? Int, old.rawWpm)
    XCTAssertEqual(body["accuracy"] as? Int, old.accuracy)
    XCTAssertEqual(old.inputMetrics?.version, 1)
  }
}
