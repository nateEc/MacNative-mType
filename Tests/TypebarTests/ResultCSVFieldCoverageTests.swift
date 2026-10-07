import Foundation
import XCTest
@testable import Typebar

final class ResultCSVFieldCoverageTests: XCTestCase {
  private func payload() -> [String: Any] {
    ["id": UUID().uuidString, "mode": "time", "mode2": "15", "durationSeconds": 15,
      "language": "english", "wpm": 60, "rawWpm": 60, "accuracy": 100, "consistency": 80,
      "errorCount": 0, "eventCount": 75, "tags": [], "startedAt": 100, "finishedAt": 115,
      "restartCount": 2, "blindMode": true,
      "practiceTiming": ["version": 1, "terminalEngagedMilliseconds": 12_750, "priorAttemptEngagedMilliseconds": 1_234],
      "experienceEvidence": ["version": 1, "characterCounts": [75, 0, 0, 0], "scoringUnitBasis": "utf16",
        "durationSeconds": 15.0, "afkSeconds": 2.25, "punctuation": false, "numbers": false, "modifiers": ["memory"]]]
  }
  private func decode(_ object: [String: Any]) throws -> RemoteAccountResult {
    try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: object))
  }
  private func records(_ text: String) -> [[String]] {
    let input = Array(text)
    var result: [[String]] = [], row: [String] = [], field = "", quoted = false, index = 0
    while index < input.count {
      let character = input[index]
      if character == "\"" {
        if quoted, index + 1 < input.count, input[index + 1] == "\"" { field.append("\""); index += 1 }
        else { quoted.toggle() }
      } else if character == ",", !quoted { row.append(field); field = "" }
      else if (character == "\r\n" || character == "\r" || character == "\n"), !quoted {
        row.append(field); result.append(row); row = []; field = ""
      } else { field.append(character) }
      index += 1
    }
    if !field.isEmpty || !row.isEmpty { row.append(field); result.append(row) }
    XCTAssertFalse(quoted)
    return result
  }
  private func fields(_ result: RemoteAccountResult) -> [String: String] {
    let rows = records(RemoteResultCSVExport.csvString(for: [result]))
    XCTAssertEqual(rows.count, 2); XCTAssertEqual(rows[0].count, 41); XCTAssertEqual(rows[1].count, 41)
    return Dictionary(uniqueKeysWithValues: zip(rows[0], rows[1]))
  }
  func testCSVRetainsRecordedCountsTimingControlsAndModeIdentity() throws {
    let result = try decode(payload())
    let fields = fields(result)
    for (key, expected) in ["mode2": "15", "restart_count": "2", "test_duration_seconds": "15.0",
      "afk_seconds": "2.25", "incomplete_test_seconds": "1.234", "character_stats": "75;0;0;0",
      "scoring_unit_basis": "utf16", "blind_mode": "true"] {
      XCTAssertEqual(fields[key], expected, key)
    }
    XCTAssertEqual(fields["funbox"], #"["memory"]"#)
  }
  func testMalformedExplicitBlindModeCannotBecomeUnknown() throws {
    for invalid: Any in [NSNull(), 0, "false", []] {
      var object = payload(); object["blindMode"] = invalid
      XCTAssertThrowsError(try decode(object))
    }
  }

  func testLegacyColumnsKeepExactOrderAndAbsentEvidenceStaysEmpty() throws {
    let legacy = "id,mode,duration_seconds,word_limit,language,wpm,raw_wpm,accuracy_percent,consistency_percent,errors,event_count,tags,terminal_engaged_seconds,prior_attempt_engaged_seconds,total_engaged_seconds,started_at,finished_at,key_consistency_percent,elapsed_seconds,wall_clock_seconds,terminal_timing_version,bailed_out,custom_limit_mode,custom_limit_value,personal_best_configuration_version,difficulty,punctuation,numbers,lazy_mode,account_tag_ids,historical_personal_best,quote_length"
    XCTAssertEqual(RemoteResultCSVExport.columns.prefix(32).joined(separator: ","), legacy)
    var object = payload()
    for key in ["mode2", "restartCount", "practiceTiming", "experienceEvidence", "blindMode"] { object.removeValue(forKey: key) }
    let old = try decode(object), csv = fields(old)
    for key in RemoteResultCSVExport.columns.suffix(9) { XCTAssertEqual(csv[key], "", key) }
    let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
    XCTAssertNil(encoded["blindMode"])
  }

  func testKnownEmptyModifiersFalseAndNativeExtensionsDoNotBecomeUnknown() throws {
    var object = payload(), evidence = try XCTUnwrap(object["experienceEvidence"] as? [String: Any])
    evidence["modifiers"] = []; evidence["afkSeconds"] = 0
    object["experienceEvidence"] = evidence; object["blindMode"] = false; object["restartCount"] = 0
    object["practiceTiming"] = ["version": 1, "terminalEngagedMilliseconds": 15_000, "priorAttemptEngagedMilliseconds": 0]
    let empty = fields(try decode(object))
    XCTAssertEqual(empty["funbox"], "[]"); XCTAssertEqual(empty["blind_mode"], "false")
    XCTAssertEqual(empty["afk_seconds"], "0.0"); XCTAssertEqual(empty["incomplete_test_seconds"], "0.0")
    evidence["modifiers"] = ["mirrorVisual", "symbolStream"]
    object["experienceEvidence"] = evidence; object["tags"] = ["desk, \"quote\"\r\nnext"]
    let extended = fields(try decode(object))
    XCTAssertEqual(extended["funbox"], #"["mirror","typebar:symbolStream"]"#)
    XCTAssertEqual(extended["tags"], "desk, \"quote\"\r\nnext")
  }

  @MainActor func testBlindModePublicationRequiresExactCapabilityAndKeepsFalseExplicit() async throws {
    func saved(_ blind: Bool) -> CompletedTestResult {
      var config = TestConfiguration.timed(seconds: 15); config.rules.blindMode = blind
      return .init(id: UUID(), configuration: config, outcome: .completed,
        startedAt: .init(timeIntervalSinceReferenceDate: 100), finishedAt: .init(timeIntervalSinceReferenceDate: 115),
        typedCharacterCount: 75, correctCharacterCount: 75, errorCount: 0, wpm: 60, rawWpm: 60,
        accuracy: 100, prompt: "private prompt", replayEvents: [])
    }
    let caps = RemoteServiceCapabilities(apiVersion: "v1", service: "typebar", capabilities: ["resultBlindMode": "available"])
    for blind in [true, false] {
      let wire = try await ResultConsistencyPublication.prepare(result: saved(blind), capabilities: caps)
      let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(wire)) as? [String: Any])
      XCTAssertEqual(object["blindMode"] as? Bool, blind)
      for key in ["prompt", "replayEvents", "token"] { XCTAssertNil(object[key]) }
    }
    for unsupported in [nil, RemoteServiceCapabilities(apiVersion: "v2", service: "typebar", capabilities: ["resultBlindMode": "available"]),
      .init(apiVersion: "v1", service: "other", capabilities: ["resultBlindMode": "available"]),
      .init(apiVersion: "v1", service: "typebar", capabilities: ["resultBlindMode": "partial"]),
      .init(apiVersion: "v1", service: "typebar", capabilities: ["resultBlindMode": "planned"])] {
      do { _ = try await ResultConsistencyPublication.prepare(result: saved(true), capabilities: unsupported); XCTFail("Do not silently drop blind mode") }
      catch { XCTAssertTrue(error.localizedDescription.contains("盲打")) }
      let legacy = try await ResultConsistencyPublication.prepare(result: saved(false), capabilities: unsupported)
      let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
      XCTAssertNil(object["blindMode"])
    }
  }

  func testExplicitMeasuredDurationKeepsFullPrecisionWithoutFabricatingAFKOrCounts() throws {
    var object = payload()
    object.removeValue(forKey: "experienceEvidence")
    object["mode"] = "custom"; object["mode2"] = "custom"; object.removeValue(forKey: "durationSeconds")
    object["finishedAt"] = 112.345678; object["startedAtReferenceTime"] = 100.0; object["finishedAtReferenceTime"] = 112.345678
    object["elapsedTime"] = ["version": 1, "seconds": 12.345678]
    let csv = fields(try decode(object))
    XCTAssertEqual(csv["test_duration_seconds"], "12.345678")
    for key in ["afk_seconds", "character_stats", "scoring_unit_basis", "funbox"] { XCTAssertEqual(csv[key], "") }
    object.removeValue(forKey: "elapsedTime")
    XCTAssertEqual(fields(try decode(object))["test_duration_seconds"], "", "Calendar dates alone cannot prove testDuration")
  }

  @MainActor func testActualBlindTypingCountersSurviveRestorePublicationAndCSV() async throws {
    var config = TestConfiguration.timed(seconds: 15); config.rules.blindMode = true
    let start = Date(timeIntervalSinceReferenceDate: 100)
    var session = TypingSession(configuration: config, prompt: "🦊a")
    session.insert("🦊x", at: start); session.tick(at: start.addingTimeInterval(15))
    let saved = try XCTUnwrap(session.result())
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [saved], presets: [], at: saved.finishedAt))
    let restored = try XCTUnwrap(archive.results.first)
    XCTAssertTrue(restored.configuration.rules.blindMode)
    let caps = RemoteServiceCapabilities(apiVersion: "v1", service: "typebar", capabilities:
      Dictionary(uniqueKeysWithValues: ["resultBlindMode", "resultInputMetrics", "resultInputMetricsV2",
        "resultPracticeTiming", "resultExperienceEvidence", "resultSpeedPrecision", "resultPersonalBestConfiguration",
        "resultRankingEvidence", "resultElapsedTime"].map { ($0, "available") }))
    let wire = try await ResultConsistencyPublication.prepare(result: restored, capabilities: caps)
    let row = try JSONDecoder().decode(RemoteAccountResult.self, from: JSONEncoder().encode(wire)), csv = fields(row)
    XCTAssertEqual(csv["character_stats"], "0;1;0;0"); XCTAssertEqual(csv["scoring_unit_basis"], "utf16")
    XCTAssertEqual(csv["blind_mode"], "true"); XCTAssertEqual(csv["funbox"], "[]")
    XCTAssertEqual(try XCTUnwrap(csv["afk_seconds"].flatMap(Double.init)), saved.afkDuration, accuracy: 1e-9)
    XCTAssertEqual(restored.preciseAccuracy, 66.67)
    XCTAssertEqual(wire.inputMetrics?.correctAttempts, 2)
    XCTAssertEqual(wire.inputMetrics?.totalAttempts, 3)
    // This is the submission projection, not an HTTP history response:
    // the service derives preciseAccuracy from these anonymous counters.
    XCTAssertNil(row.preciseAccuracy)
  }

  func testAllOriginalCSVFieldsAgainstCompletePinnedFormatter() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Readiness supplies the pinned reference")
    }
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Scripts/check-source-account-history-stats.mjs")
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = .init(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", script.path, reference, "--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors
    try process.run()
    let bytes = output.fileHandleForReading.readDataToEndOfFile(), diagnostic = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0, String(decoding: diagnostic, as: UTF8.self))
    struct Fixture: Decodable { let wire: RemoteAccountResult; let columns: [String]; let cells: [String]; let nativeMode2: String }
    struct Document: Decodable { let referenceCommit: String; let csvFixtures: [Fixture] }
    let document = try JSONDecoder().decode(Document.self, from: bytes)
    XCTAssertEqual(document.referenceCommit, "91bd24bb8513785c7364cbea29296ff7adafac41"); XCTAssertEqual(document.csvFixtures.count, 20)
    let mapping = ["_id": "id", "isPb": "historical_personal_best", "wpm": "wpm", "acc": "accuracy_percent",
      "rawWpm": "raw_wpm", "consistency": "consistency_percent", "charStats": "character_stats", "mode": "mode",
      "mode2": "mode2", "quoteLength": "quote_length", "restartCount": "restart_count", "testDuration": "test_duration_seconds",
      "afkDuration": "afk_seconds", "incompleteTestSeconds": "incomplete_test_seconds", "punctuation": "punctuation",
      "numbers": "numbers", "language": "language", "funbox": "funbox", "difficulty": "difficulty", "lazyMode": "lazy_mode",
      "blindMode": "blind_mode", "bailedOut": "bailed_out", "tags": "account_tag_ids", "timestamp": "finished_at"]
    XCTAssertEqual(mapping.count, 24)
    for fixture in document.csvFixtures {
      let native = fields(fixture.wire)
      XCTAssertEqual(Set(fixture.columns), Set(mapping.keys))
      for (key, expected) in zip(fixture.columns, fixture.cells) {
        let value = try XCTUnwrap(native[XCTUnwrap(mapping[key])])
        switch key {
        case "mode2":
          XCTAssertEqual(value, fixture.nativeMode2) // Owned quote namespace replaces upstream catalogue IDs.
          if fixture.wire.mode != "quote" { XCTAssertEqual(value, expected) }
        case "quoteLength": XCTAssertEqual(fixture.wire.quoteLength?.compatibilityValue ?? "-1", expected)
        case "funbox":
          XCTAssertEqual(try JSONDecoder().decode([String].self, from: Data(value.utf8)).joined(separator: ","), expected)
        case "timestamp":
          let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
          XCTAssertEqual(try XCTUnwrap(parser.date(from: value)).timeIntervalSince1970 * 1_000,
            try XCTUnwrap(Double(expected)), accuracy: 0.001)
        case "testDuration", "afkDuration", "incompleteTestSeconds":
          XCTAssertEqual(try XCTUnwrap(Double(value)), try XCTUnwrap(Double(expected)), accuracy: 1e-9)
        default: XCTAssertEqual(value, expected, key)
        }
      }
    }
  }
}
