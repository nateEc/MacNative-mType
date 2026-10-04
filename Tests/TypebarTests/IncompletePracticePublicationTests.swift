import Foundation
import XCTest
@testable import Typebar

final class IncompletePracticePublicationTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 900_000_000)
  private func result(evidence: ResultIncompletePractice? = .empty, count: Int = 0,
    seconds: Double = 0) -> CompletedTestResult {
    .init(id: UUID(), configuration: .words(25), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(15),
      typedCharacterCount: 75, correctCharacterCount: 75, errorCount: 0,
      wpm: 60, rawWpm: 60, accuracy: 100, restartCount: count,
      priorAttemptEngagedDuration: seconds, incompletePractice: evidence,
      prompt: "private owned prompt", replayEvents: [.init(offset: 1, kind: .insert, text: "private")])
  }
  private func capabilities(new: String? = "available", practice: String = "available",
    api: String = "v1", service: String = "typebar") -> RemoteServiceCapabilities {
    var fields = ["resultPracticeTiming": practice]
    fields["resultIncompletePractice"] = new
    return .init(apiVersion: api, service: service, capabilities: fields)
  }
  private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
  }

  @MainActor func testNegotiatedSubmissionKeepsExplicitEmptyHistory() async throws {
    let wire = try await ResultConsistencyPublication.prepare(result: result(), capabilities: capabilities())
    XCTAssertEqual(try object(wire)["incompletePractice"] as? NSDictionary,
      ["version": 1, "attempts": []] as NSDictionary)
  }

  @MainActor func testOldCapabilityCannotSilentlyDropNewEvidence() async {
    do {
      _ = try await ResultConsistencyPublication.prepare(result: result(), capabilities: capabilities(new: nil))
      XCTFail("New evidence requires explicit support before POST")
    } catch { XCTAssertTrue(error is RemoteAccountError) }
  }

  @MainActor func testBothExactCapabilitiesAreRequiredBeforeMetricWork() async {
    for cap in [nil, capabilities(new: "partial"), capabilities(new: "planned"),
      capabilities(practice: "planned"), capabilities(api: "v2"), capabilities(service: "other")] {
      do {
        _ = try await ResultConsistencyPublication.prepare(result: result(), capabilities: cap) { _ in
          XCTFail("Unsupported evidence must not start work"); return 0
        }
        XCTFail("Both exact capabilities are required")
      } catch { XCTAssertTrue(error is RemoteAccountError) }
    }
  }

  @MainActor func testAnonymousWireAndRemoteHistoryRetainFractionsAndOrder() async throws {
    let snapshot = ResultIncompletePractice(attempts: [.init(accuracy: 66.67, seconds: 1.01),
      .init(accuracy: 0, seconds: 2)])
    let value = result(evidence: snapshot, count: 2, seconds: 3.005)
    let wire = try await ResultConsistencyPublication.prepare(result: value, capabilities: capabilities())
    let json = try object(wire)
    XCTAssertEqual(json["restartCount"] as? Int, 2)
    XCTAssertEqual((json["practiceTiming"] as? [String: Int])?["priorAttemptEngagedMilliseconds"], 3_005)
    let bytes = try JSONEncoder().encode(wire)
    let history = try JSONDecoder().decode(RemoteAccountResult.self, from: bytes)
    XCTAssertEqual(history.incompletePractice, snapshot)
    XCTAssertEqual(history.restartCount, 2)
    for key in ["prompt", "replayEvents", "keyCode", "inputText", "experienceGained", "totalExperience"] {
      XCTAssertNil(json[key])
    }
    XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("private"))
  }

  @MainActor func testLegacyAbsenceKeepsOldFallbackAndHistoryMissing() async throws {
    let wire = try await ResultConsistencyPublication.prepare(result: result(evidence: nil), capabilities: nil)
    XCTAssertNil(try object(wire)["incompletePractice"])
    let history = try JSONDecoder().decode(RemoteAccountResult.self, from: JSONEncoder().encode(wire))
    XCTAssertNil(history.incompletePractice)
  }

  @MainActor func testInvalidNativeBindingAndUnsupportedVersionCannotPublish() async {
    for (snapshot, count, seconds) in [(ResultIncompletePractice.empty, 1, 0.0),
      (.init(version: 2, attempts: []), 0, 0),
      (.init(attempts: [.init(accuracy: .nan, seconds: 1)]), 1, 1),
      (.init(attempts: [.init(accuracy: 50, seconds: 1)]), 1, 2)] {
      do {
        _ = try await ResultConsistencyPublication.prepare(result: result(evidence: snapshot,
          count: count, seconds: seconds), capabilities: capabilities())
        XCTFail("Invalid evidence must remain local")
      } catch { XCTAssertTrue(error is RemoteAccountError) }
    }
  }

  @MainActor func testExistingServiceBoundsAndIndependentRoundingArePreserved() async throws {
    for count in [1, 1_000] {
      let attempts = Array(repeating: ResultIncompletePractice.Attempt(accuracy: 0, seconds: 0.01), count: count)
      let raw = Double(count) * 0.00549
      let wire = try await ResultConsistencyPublication.prepare(result: result(evidence: .init(attempts: attempts),
        count: count, seconds: raw), capabilities: capabilities())
      XCTAssertEqual(wire.incompletePractice?.attempts.count, count)
    }
    for (count, seconds) in [(1_001, 0.0), (1, 3_601.0)] {
      do {
        _ = try await ResultConsistencyPublication.prepare(result: result(evidence: .init(attempts:
          Array(repeating: .init(accuracy: 50, seconds: seconds), count: count)),
          count: count, seconds: Double(count) * seconds), capabilities: capabilities())
        XCTFail("Existing service practice-time bounds still apply")
      } catch { XCTAssertTrue(error is RemoteAccountError) }
    }
  }

  func testMalformedRemoteHistoryNeverDowngradesToUnknown() throws {
    let wire = RemoteResultSubmission(result: result(), includesPracticeTiming: true)
    let base = try object(wire)
    for key in ["restartCount", "practiceTiming", "incompletePractice"] {
      var json = base; json[key] = NSNull()
      XCTAssertThrowsError(try JSONDecoder().decode(RemoteAccountResult.self,
        from: JSONSerialization.data(withJSONObject: json)))
      if key != "incompletePractice" {
        json.removeValue(forKey: key)
        XCTAssertThrowsError(try JSONDecoder().decode(RemoteAccountResult.self,
          from: JSONSerialization.data(withJSONObject: json)))
      }
    }
    var json = base; json["incompletePractice"] = ["version": 2, "attempts": []]
    XCTAssertThrowsError(try JSONDecoder().decode(RemoteAccountResult.self,
      from: JSONSerialization.data(withJSONObject: json)))
    json = base; json["practiceTiming"] = ["version": 1, "terminalEngagedMilliseconds": 16_000,
      "priorAttemptEngagedMilliseconds": 0]
    XCTAssertThrowsError(try JSONDecoder().decode(RemoteAccountResult.self,
      from: JSONSerialization.data(withJSONObject: json)))
  }

  @MainActor func testTemporaryCapabilityFailuresRemainRetryableAndCancellationPropagates() async throws {
    for failure: Error in [URLError(.notConnectedToInternet),
      RemoteAccountError.serverResponse(statusCode: 503, message: "temporary"), CancellationError()] {
      do {
        _ = try await RemoteResultBailoutPolicy.capabilities(for: .completed, requiresIncompletePractice: true) { throw failure }
        XCTFail("Do not downgrade new evidence after a transient failure")
      } catch { XCTAssertTrue(error is CancellationError || ResultPublicationRetryPolicy.shouldQueue(error)) }
    }
    let missing = try await RemoteResultBailoutPolicy.capabilities(for: .completed, requiresIncompletePractice: true) {
      throw RemoteAccountError.serverResponse(statusCode: 404, message: "old service")
    }
    XCTAssertNil(missing)
  }

  @MainActor func testUnrepresentableCarriedMillisecondsFailWithoutAnIntegerTrap() async {
    for seconds in [Double(Int.max) / 1_000, 1e20] {
      let value = result(evidence: .init(attempts: [.init(accuracy: 50, seconds: seconds)]), count: 1, seconds: seconds)
      XCTAssertNil(RemoteResultPracticeTiming(result: value))
      do {
        _ = try await ResultConsistencyPublication.prepare(result: value, capabilities: capabilities())
        XCTFail("Huge local evidence must be refused without a trapping cast")
      } catch { XCTAssertTrue(error is RemoteAccountError) }
    }
  }
}
