import Foundation
import XCTest
@testable import Typebar

final class ExperienceEvidencePublicationTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 900_000_000)
  private func result() -> CompletedTestResult {
    .init(id: UUID(), configuration: .words(25, contentOptions:
      .init(includePunctuation: true, includeNumbers: true)).with(modifiers: [.mirrorVisual]),
      outcome: .completed, startedAt: start, finishedAt: start.addingTimeInterval(15),
      afkDuration: 2.25, typedCharacterCount: 75, correctCharacterCount: 75,
      errorCount: 0, wpm: 60, rawWpm: 60, accuracy: 100,
      inputMetrics: .init(version: 1, correctAttempts: 75, totalAttempts: 75,
        creditedUnits: 75, retainedUnits: 75),
      characterStats: .init(matched: 75, incorrect: 0, extra: 0, missed: 0,
        sourceUnits: .classify(input: Array(repeating: 97, count: 75),
          target: Array(repeating: 97, count: 75), creditsPartial: false)),
      prompt: "private prompt", replayEvents: [.init(offset: 1, kind: .insert, text: "private")])
  }
  private var capabilities: RemoteServiceCapabilities {
    .init(apiVersion: "v1", service: "typebar", capabilities: [
      "resultExperienceEvidence": "available", "resultInputMetrics": "available",
      "resultInputMetricsV2": "available", "resultPracticeTiming": "available",
      "resultBailout": "available", "resultTerminalTiming": "available"])
  }
  private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
  }
  @MainActor func testNegotiatedWireKeepsCompleteAnonymousTerminalEvidence() async throws {
    let wire = try await ResultConsistencyPublication.prepare(result: result(), capabilities: capabilities)
    XCTAssertEqual(try object(wire)["experienceEvidence"] as? NSDictionary,
      ["version": 1, "characterCounts": [75, 0, 0, 0], "scoringUnitBasis": "utf16",
        "durationSeconds": 15.0, "afkSeconds": 2.25, "punctuation": true, "numbers": true,
        "modifiers": ["mirrorVisual"]] as NSDictionary)
  }
  @MainActor func testEvidenceCapabilityCannotDiscardItsRequiredInputCounters() async {
    do {
      _ = try await ResultConsistencyPublication.prepare(result: result(), capabilities:
        .init(apiVersion: "v1", service: "typebar", capabilities: ["resultExperienceEvidence": "available"]))
      XCTFail("A negotiated complete report needs the matching counter contract")
    } catch { XCTAssertTrue(error is RemoteAccountError) }
  }

  @MainActor func testPreRewardCapabilityIsAdditiveAndExact() async throws {
    for (api, service, status) in [("v1", "typebar", "planned"), ("v1", "typebar", "partial"),
      ("v2", "typebar", "available"), ("v1", "other", "available"), ("v1", "typebar", "")] {
      let wire = try await ResultConsistencyPublication.prepare(result: result(), capabilities:
        .init(apiVersion: api, service: service, capabilities: ["resultExperienceEvidence": status]))
      XCTAssertNil(wire.experienceEvidence, "Do not imply the service has switched XP rules")
    }
  }

  @MainActor func testMissingUnitOrAttemptHistoryIsNotReconstructed() async throws {
    for key in ["sourceUnits", "inputMetrics"] {
      var json = try object(result())
      if key == "inputMetrics" { json.removeValue(forKey: key) }
      else {
        var stats = try XCTUnwrap(json["characterStats"] as? [String: Any])
        stats.removeValue(forKey: key); json["characterStats"] = stats
      }
      let legacy = try JSONDecoder().decode(CompletedTestResult.self,
        from: JSONSerialization.data(withJSONObject: json))
      let wire = try await ResultConsistencyPublication.prepare(result: legacy, capabilities: capabilities)
      XCTAssertNil(wire.experienceEvidence)
    }
  }

  @MainActor func testActualCorrectionUnicodeTrimAndKoreanKeepSourceUnits() async throws {
    var corrected = TypingSession(configuration: .timed(seconds: 15), prompt: "abc")
    corrected.insert("ax", at: start); corrected.deleteBackward(at: start.addingTimeInterval(1))
    corrected.insert("bc", at: start.addingTimeInterval(14)); corrected.tick(at: start.addingTimeInterval(15))
    var emoji = TypingSession(configuration: .timed(seconds: 15), prompt: "🦊a")
    emoji.insert("🦊x", at: start); emoji.tick(at: start.addingTimeInterval(15))
    var trimmed = TypingSession(configuration: .words(1), prompt: "ab")
    trimmed.insertBatch("a", at: start); trimmed.insertBatch("b ", at: start.addingTimeInterval(2))
    var korean = TypingSession(configuration: .words(0), prompt: "괅 ")
    korean.insertBatch("괅", at: start); korean.bailOut(at: start.addingTimeInterval(2))
    for (session, expected, basis) in [(corrected, [3,0,0,0], "utf16"),
      (emoji, [0,1,0,0], "utf16"), (trimmed, [2,0,0,0], "utf16"), (korean, [5,0,0,0], "koreanJamo")] {
      let saved = try XCTUnwrap(session.result())
      let wire = try await ResultConsistencyPublication.prepare(result: saved, capabilities: capabilities)
      let evidence = try XCTUnwrap(wire.experienceEvidence)
      XCTAssertEqual(evidence.characterCounts, expected)
      XCTAssertEqual(evidence.scoringUnitBasis.rawValue, basis)
      XCTAssertEqual(evidence.afkSeconds, saved.afkDuration)
      XCTAssertEqual(evidence.durationSeconds, saved.elapsedDuration)
      XCTAssertEqual(evidence.characterCounts[0], wire.inputMetrics?.creditedUnits)
    }
    XCTAssertEqual(corrected.result()?.inputMetrics?.totalAttempts, 4)
    XCTAssertEqual(corrected.result()?.preciseAccuracy, 75)
    XCTAssertEqual(emoji.result()?.typedCharacterCount, 2)
  }

  @MainActor func testActualClassifierPreservesOverlappingPrefixSpaceDiagnostics() async throws {
    let units = ResultUnitCharacterStats.classify(input: Array("ab ".utf16),
      target: Array("ab cd".utf16), creditsPartial: true)
    XCTAssertEqual(units.correctWord, 3); XCTAssertEqual(units.allCorrect, 2); XCTAssertEqual(units.extra, 1)
    let saved = CompletedTestResult(id: UUID(), configuration: .timed(seconds: 15), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(15), typedCharacterCount: 3,
      correctCharacterCount: 3, errorCount: 0, wpm: 2, rawWpm: 2, accuracy: 100,
      inputMetrics: .init(version: 1, correctAttempts: 3, totalAttempts: 3, creditedUnits: 3, retainedUnits: 3),
      characterStats: .init(matched: 3, incorrect: 0, extra: 0, missed: 0, sourceUnits: units))
    let wire = try await ResultConsistencyPublication.prepare(result: saved, capabilities: capabilities)
    XCTAssertEqual(wire.experienceEvidence?.characterCounts, [3,0,1,0])
  }

  @MainActor func testExplicitCounterAndAFKConflictsFailBeforeMetrics() async throws {
    for mutation in 0..<4 {
      var json = try object(result())
      if mutation == 0 { json["afkDuration"] = 16.0 }
      else {
        var metrics = try XCTUnwrap(json["inputMetrics"] as? [String: Any])
        if mutation == 1 { metrics["creditedUnits"] = 74 }
        if mutation == 2 { metrics["retainedUnits"] = 76 }
        if mutation == 3 { metrics["totalAttempts"] = 74 }
        json["inputMetrics"] = metrics
      }
      let saved = try JSONDecoder().decode(CompletedTestResult.self,
        from: JSONSerialization.data(withJSONObject: json))
      do {
        _ = try await ResultConsistencyPublication.prepare(result: saved, capabilities: capabilities) { _ in
          XCTFail("Invalid report must not start metric work"); return 0
        }
        XCTFail("Explicit conflicting evidence cannot turn into absence")
      } catch { XCTAssertTrue(error is RemoteAccountError) }
    }
  }

  @MainActor func testPrivateHistoryRetainsMetadataAndRejectsBadExplicitFields() async throws {
    let wire = try await ResultConsistencyPublication.prepare(result: result(), capabilities: capabilities)
    let bytes = try JSONEncoder().encode(wire), base = try object(wire)
    let history = try JSONDecoder().decode(RemoteAccountResult.self, from: bytes)
    XCTAssertEqual(history.experienceEvidence, wire.experienceEvidence)
    for forbidden in ["private", "prompt", "replayEvents", "keyCode", "experienceGained", "difficultyLevel"] {
      XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains(forbidden))
    }
    for mutation in 0..<5 {
      var json = base
      switch mutation {
      case 0: json["experienceEvidence"] = NSNull()
      case 1: json.removeValue(forKey: "restartCount")
      case 2: json.removeValue(forKey: "practiceTiming")
      case 3:
        var evidence = try XCTUnwrap(json["experienceEvidence"] as? [String: Any])
        evidence["version"] = 2; json["experienceEvidence"] = evidence
      default:
        var evidence = try XCTUnwrap(json["experienceEvidence"] as? [String: Any])
        evidence["durationSeconds"] = 14; json["experienceEvidence"] = evidence
      }
      XCTAssertThrowsError(try JSONDecoder().decode(RemoteAccountResult.self,
        from: JSONSerialization.data(withJSONObject: json)))
    }
  }

  func testModifierCatalogIsExplicitAndDoesNotTreatLazyInputAsFunbox() throws {
    XCTAssertEqual(RemoteExperienceEvidence.knownModifiers.count, 51)
    XCTAssertFalse(RemoteExperienceEvidence.knownModifiers.contains("lazyLatin"))
    for name in RemoteExperienceEvidence.knownModifiers {
      let evidence = RemoteExperienceEvidence(characterCounts: [0,0,0,0], scoringUnitBasis: .utf16,
        durationSeconds: 1, afkSeconds: 0, punctuation: false, numbers: false, modifiers: [name])
      XCTAssertTrue(evidence.isValid)
      XCTAssertEqual(try JSONDecoder().decode(RemoteExperienceEvidence.self,
        from: JSONEncoder().encode(evidence)), evidence)
    }
    for modifiers in [["unknown"], ["mirrorVisual", "mirrorVisual"], ["lazyLatin"]] {
      XCTAssertFalse(RemoteExperienceEvidence(characterCounts: [0,0,0,0], scoringUnitBasis: .utf16,
        durationSeconds: 1, afkSeconds: 0, punctuation: false, numbers: false, modifiers: modifiers).isValid)
    }
  }

  @MainActor func testExistingPortableAndArchiveSnapshotsProjectIdenticalEvidence() async throws {
    let saved = result()
    let record = try XCTUnwrap(TestResultRecord(result: saved).portableResult)
    let data = try TypebarDataTransfer.exportArchive(settings: .init(), results: [saved], presets: [], at: start)
    let archive = try TypebarDataTransfer.importArchive(from: data)
    XCTAssertEqual(archive.version, TypebarArchive.currentVersion, "Export uses the current format without changing experience evidence")
    let expected = try await ResultConsistencyPublication.prepare(result: saved, capabilities: capabilities).experienceEvidence
    for value in [record, try XCTUnwrap(archive.results.first)] {
      let wire = try await ResultConsistencyPublication.prepare(result: value, capabilities: capabilities)
      XCTAssertEqual(wire.experienceEvidence, expected)
    }
  }
}
