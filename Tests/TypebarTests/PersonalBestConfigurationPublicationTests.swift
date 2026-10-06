import Foundation
import XCTest
@testable import Typebar

final class PersonalBestConfigurationPublicationTests: XCTestCase {
  private func result(_ difficulty: Difficulty = .normal, lazy: Bool = false,
    mode: TestMode = .words, punctuation: Bool = false, numbers: Bool = false) -> CompletedTestResult {
    var configuration = TestConfiguration(mode: mode, duration: mode == .time ? 15 : nil,
      wordLimit: mode == .words ? 25 : nil, difficulty: difficulty, rules: .init())
    configuration.difficulty = difficulty
    configuration.modifiers = lazy ? [.lazyLatin] : []
    configuration.contentOptions = .init(includePunctuation: punctuation, includeNumbers: numbers)
    let start = Date(timeIntervalSinceReferenceDate: 900_000_000)
    return .init(id: UUID(), configuration: configuration, outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(15), typedCharacterCount: 75,
      correctCharacterCount: 75, errorCount: 0, wpm: 60, rawWpm: 60, accuracy: 100,
      prompt: "private text", replayEvents: [])
  }
  private var capabilities: RemoteServiceCapabilities {
    .init(apiVersion: "v1", service: "typebar", capabilities: ["resultPersonalBestConfiguration":"available"])
  }
  private func json<T: Encodable>(_ value: T) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
  }
  @MainActor func testSavedConfigurationSurvivesPortableRestoreAndPublication() async throws {
    let saved = result(.master, lazy: true, punctuation: true, numbers: true)
    let restored = try XCTUnwrap(TestResultRecord(result: saved).portableResult)
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [saved], presets: [], at: saved.finishedAt))
    XCTAssertEqual(archive.version, TypebarArchive.currentVersion)
    for input in [saved, restored, try XCTUnwrap(archive.results.first)] {
      let wire = try await ResultConsistencyPublication.prepare(result: input, capabilities: capabilities)
      let data = try json(wire)
      let configuration = try XCTUnwrap(data["personalBestConfiguration"] as? [String: Any])
      XCTAssertEqual(configuration["difficulty"] as? String, "master")
      XCTAssertEqual(configuration["lazyMode"] as? Bool, true)
      XCTAssertEqual(configuration["punctuation"] as? Bool, true)
      XCTAssertEqual(configuration["numbers"] as? Bool, true)
      XCTAssertFalse(String(describing: data).contains("private text"))
    }
  }
  @MainActor func testUnsupportedServiceRefusesNondefaultControlsBeforeMetrics() async throws {
    for saved in [result(.expert), result(lazy: true), result(punctuation: true), result(numbers: true)] {
      do {
        _ = try await ResultConsistencyPublication.prepare(result: saved, capabilities:
          .init(apiVersion: "v1", service: "typebar", capabilities: ["resultConsistency":"available"])) { _ in
          XCTFail("Do not compute metrics for an unsupported configuration"); return 0
        }
        XCTFail("Nondefault PB controls must not silently disappear")
      } catch { XCTAssertTrue(error is RemoteAccountError) }
    }
    let legacy = try await ResultConsistencyPublication.prepare(result: result(), capabilities: nil)
    XCTAssertNil(try json(legacy)["personalBestConfiguration"])
  }

  @MainActor func testOnlyExactCapabilityCanCaptureConfiguration() async throws {
    for capability in [nil, RemoteServiceCapabilities(apiVersion: "v2", service: "typebar",
      capabilities: ["resultPersonalBestConfiguration":"available"]),
      .init(apiVersion: "v1", service: "other", capabilities: ["resultPersonalBestConfiguration":"available"]),
      .init(apiVersion: "v1", service: "typebar", capabilities: ["resultPersonalBestConfiguration":"partial"]),
      .init(apiVersion: "v1", service: "typebar", capabilities: ["resultPersonalBestConfiguration":"planned"])] {
      let wire = try await ResultConsistencyPublication.prepare(result: result(), capabilities: capability)
      XCTAssertNil(wire.personalBestConfiguration)
      do { _ = try await ResultConsistencyPublication.prepare(result: result(.master), capabilities: capability)
        XCTFail("Cannot silently downgrade nondefault controls")
      } catch { XCTAssertTrue(error is RemoteAccountError) }
    }
  }

  @MainActor func testAllModesDifficultiesAndBooleanVariantsHaveExplicitSavedControls() async throws {
    for mode in [TestMode.time, .words, .quote, .custom, .zen] {
      for difficulty in [Difficulty.normal, .expert, .master] {
        for bits in 0..<8 {
          let saved = result(difficulty, lazy: bits & 1 != 0, mode: mode,
            punctuation: bits & 2 != 0, numbers: bits & 4 != 0)
          let wire = try await ResultConsistencyPublication.prepare(result: saved, capabilities: capabilities)
          let expected = RemotePersonalBestConfiguration(difficulty: difficulty.rawValue,
            punctuation: bits & 2 != 0, numbers: bits & 4 != 0, lazyMode: bits & 1 != 0)
          XCTAssertEqual(wire.personalBestConfiguration, expected)
          XCTAssertEqual(try JSONDecoder().decode(RemoteAccountResult.self,
            from: JSONEncoder().encode(wire)).personalBestConfiguration, expected)
        }
      }
    }
  }

  @MainActor func testCSVPreservesKnownFalseAndUnknownWithoutChangingExistingColumns() async throws {
    let wire = try await ResultConsistencyPublication.prepare(result: result(), capabilities: capabilities)
    let known = try JSONDecoder().decode(RemoteAccountResult.self, from: JSONEncoder().encode(wire))
    let unknown = try JSONDecoder().decode(RemoteAccountResult.self,
      from: JSONEncoder().encode(RemoteResultSubmission(result: result())))
    let lines = RemoteResultCSVExport.csvString(for: [known, unknown]).components(separatedBy: "\r\n")
    XCTAssertEqual(RemoteResultCSVExport.columns.count, 29)
    XCTAssertTrue(lines[0].hasSuffix("personal_best_configuration_version,difficulty,punctuation,numbers,lazy_mode"))
    XCTAssertTrue(lines[1].hasSuffix(",1,normal,false,false,false"))
    XCTAssertTrue(lines[2].hasSuffix(",,,,,"))
    for forbidden in ["prompt", "replay", "token", "password"] { XCTAssertFalse(lines.joined().contains(forbidden)) }
  }

  func testEveryMandatoryFieldAndXPContentBindingIsStrict() throws {
    let base = try json(RemoteResultSubmission(result: result()))
    let good: [String: Any] = ["version": 1, "difficulty": "normal", "punctuation": false, "numbers": false, "lazyMode": false]
    for key in good.keys {
      for value: Any? in [nil, NSNull(), "unsupported"] {
        var controls = good; controls[key] = value
        var data = base; data["personalBestConfiguration"] = controls
        XCTAssertThrowsError(try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: data)))
      }
    }
    for flag in ["punctuation", "numbers"] {
      var data = base; data["personalBestConfiguration"] = good
      var experience: [String: Any] = ["version": 1, "characterCounts": [75,0,0,0], "scoringUnitBasis": "utf16",
        "durationSeconds": 15, "afkSeconds": 0, "punctuation": false, "numbers": false, "modifiers": []]
      experience[flag] = true; data["experienceEvidence"] = experience
      data["practiceTiming"] = ["version": 1, "terminalEngagedMilliseconds": 15_000, "priorAttemptEngagedMilliseconds": 0]
      XCTAssertThrowsError(try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: data)))
    }
  }

  @MainActor func testCancelledPreparationCannotReturnConfigurationForSubmission() async throws {
    let saved = result(.master), capability = capabilities
    let task = Task { try await ResultConsistencyPublication.prepare(result: saved, capabilities: capability) }
    task.cancel()
    do { _ = try await task.value; XCTFail("Cancelled work cannot return a request") }
    catch is CancellationError {}
  }
  func testHistoryRejectsExplicitMalformedConfigurationButAllowsUnknownLegacy() throws {
    let base = try json(RemoteResultSubmission(result: result()))
    for value: Any in [NSNull(), ["version": 2, "difficulty": "normal", "lazyMode": false,
      "punctuation": false, "numbers": false], ["version": 1, "difficulty": "normal"]] {
      var payload = base; payload["personalBestConfiguration"] = value
      XCTAssertThrowsError(try JSONDecoder().decode(RemoteAccountResult.self,
        from: JSONSerialization.data(withJSONObject: payload)))
    }
    var payload = base
    payload["personalBestConfiguration"] = ["version": 1, "difficulty": "normal", "lazyMode": false,
      "punctuation": false, "numbers": false]
    let history = try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: payload))
    XCTAssertNotNil(try json(history)["personalBestConfiguration"])
    XCTAssertNil(try json(JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: base)))["personalBestConfiguration"])
  }
}
