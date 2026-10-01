import XCTest
@testable import Typebar

final class InputMetricsPublicationTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 100)

  func testCorrectedTextKeepsHistoricalAttemptsSeparateFromRetainedUnits() throws {
    var session = TypingSession(configuration: .timed(seconds: 15), prompt: "abc")
    session.insert("ax", at: start)
    session.deleteBackward(at: start.addingTimeInterval(1))
    session.insert("bc", at: start.addingTimeInterval(14))
    session.tick(at: start.addingTimeInterval(15))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.accuracy, 75)
    XCTAssertEqual(result.errorCount, 0)
    try assertMetrics(result, correct: 3, total: 4, credited: 3, retained: 3)
  }

  func testUnicodeAndWrongWholeWordDoNotUseVisibleCountsAsSpeedCredit() throws {
    var session = TypingSession(configuration: .timed(seconds: 15), prompt: "🦊a")
    session.insert("🦊x", at: start.addingTimeInterval(14))
    session.tick(at: start.addingTimeInterval(29))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.preciseAccuracy, 66.67)
    XCTAssertEqual(result.typedCharacterCount, 2)
    try assertMetrics(result, correct: 2, total: 3, credited: 0, retained: 3)
  }

  func testWrongCommittedWordAndCurrentPrefixKeepSeparateCredit() throws {
    var session = TypingSession(configuration: .timed(seconds: 15), prompt: "ab bay")
    session.insert("ax bay", at: start)
    session.tick(at: start.addingTimeInterval(15))
    try assertMetrics(try XCTUnwrap(session.result()), correct: 5, total: 6, credited: 3, retained: 6)
  }

  func testStoppedInputIsCountedEvenThoughItHasNoReplayText() throws {
    var session = TypingSession(configuration: .words(2, rules: .init(stopOnErrorMode: .letter)),
      prompt: "a🦊b bay")
    session.insert("a", at: start)
    session.insert("e\u{301}", at: start.addingTimeInterval(1))
    session.bailOut(at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.replayEvents.map(\.text), ["a"])
    try assertMetrics(result, correct: 1, total: 3, credited: 1, retained: 1)
  }

  func testMetricsSurviveJSONAndPortableRecordButAreNotInventedForLegacyResults() throws {
    var session = TypingSession(configuration: .words(1), prompt: "🦊a")
    session.insert("🦊", at: start)
    session.insert("a", at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    let decoded = try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(result))
    try assertMetrics(decoded, correct: 3, total: 3, credited: 3, retained: 3)
    try assertMetrics(try XCTUnwrap(TestResultRecord(result: decoded).portableResult),
      correct: 3, total: 3, credited: 3, retained: 3)
    var legacy = try object(decoded)
    legacy.removeValue(forKey: "inputMetrics")
    let old = try JSONDecoder().decode(CompletedTestResult.self,
      from: JSONSerialization.data(withJSONObject: legacy))
    XCTAssertNil(try object(old)["inputMetrics"])
    XCTAssertNil(try object(try XCTUnwrap(TestResultRecord(result: old).portableResult))["inputMetrics"])
    XCTAssertEqual(old.preciseAccuracy, result.preciseAccuracy)
  }

  private func assertMetrics(_ result: CompletedTestResult, correct: Int, total: Int,
    credited: Int, retained: Int, file: StaticString = #filePath, line: UInt = #line) throws {
    let metrics = try XCTUnwrap(try object(result)["inputMetrics"] as? [String: Int], file: file, line: line)
    XCTAssertEqual(metrics, ["version": 1, "correctAttempts": correct, "totalAttempts": total,
      "creditedUnits": credited, "retainedUnits": retained], file: file, line: line)
  }

  func testCSVPreservesLocalAndRemoteAccuracyDecimals() throws {
    var session = TypingSession(configuration: .timed(seconds: 15), prompt: "🦊a")
    session.insert("🦊x", at: start)
    session.tick(at: start.addingTimeInterval(15))
    let result = try XCTUnwrap(session.result())
    let row = ResultCSVExport.csvString(for: [result]).components(separatedBy: "\r\n")[1]
    let fields = Dictionary(uniqueKeysWithValues: zip(ResultCSVExport.columns, row.components(separatedBy: ",")))
    XCTAssertEqual(fields["accuracy_percent"], "66.67")
    let remote = try JSONDecoder().decode(RemoteAccountResult.self, from: remoteJSON(precision: 66.67))
    XCTAssertEqual(try object(remote)["preciseAccuracy"] as? Double, 66.67)
    let remoteCSV = RemoteResultCSVExport.csvString(for: [remote])
    let remoteFields = Dictionary(uniqueKeysWithValues: zip(RemoteResultCSVExport.columns,
      remoteCSV.components(separatedBy: "\r\n")[1].components(separatedBy: ",")))
    XCTAssertEqual(remoteFields["accuracy_percent"], "66.67")
  }

  private func remoteJSON(precision: Double?) throws -> Data {
    var json: [String: Any] = ["id": UUID().uuidString, "mode": "time", "language": "english",
      "durationSeconds": 15, "wpm": 0, "rawWpm": 2, "accuracy": 67, "errorCount": 1,
      "eventCount": 2, "tags": [], "startedAt": 100, "finishedAt": 115]
    json["preciseAccuracy"] = precision
    return try JSONSerialization.data(withJSONObject: json)
  }

  func testInputMetricsRequireTheExactAdvertisedServiceCapability() {
    for (version, service, status, expected) in [
      ("v1", "typebar", "available", true), ("v2", "typebar", "available", false),
      ("v1", "other", "available", false), ("v1", "typebar", "partial", false),
      ("v1", "typebar", "", false),
    ] {
      XCTAssertEqual(RemoteServiceCapabilities(apiVersion: version, service: service,
        capabilities: ["resultInputMetrics": status]).supportsResultInputMetrics, expected)
    }
  }

  func testNegotiatedWireContainsOnlyAnonymousMetricsAndLegacyWireStaysUnchanged() throws {
    var session = TypingSession(configuration: .words(1), prompt: "🦊a")
    session.insert("🦊", at: start)
    session.insert("a", at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    let negotiated = RemoteResultSubmission(result: result, includesInputMetrics: true)
    XCTAssertEqual(try object(negotiated)["inputMetrics"] as? [String: Int],
      ["version": 1, "correctAttempts": 3, "totalAttempts": 3, "creditedUnits": 3, "retainedUnits": 3])
    let body = String(decoding: try JSONEncoder().encode(negotiated), as: UTF8.self)
    for forbidden in ["🦊", "prompt", "replayEvents", "keyCode"] { XCTAssertFalse(body.contains(forbidden)) }
    XCTAssertNil(try object(RemoteResultSubmission(result: result))["inputMetrics"])
    var oldJSON = try object(result)
    oldJSON.removeValue(forKey: "inputMetrics")
    let old = try JSONDecoder().decode(CompletedTestResult.self, from: JSONSerialization.data(withJSONObject: oldJSON))
    XCTAssertNil(try object(RemoteResultSubmission(result: old, includesInputMetrics: true))["inputMetrics"],
      "Never fabricate missing attempts from a legacy replay")
  }

  func testRemoteBestAndLeaderboardModelsKeepOptionalPrecisionAndLegacyFallback() throws {
    for precision: Double? in [66.67, nil] {
      var json = try XCTUnwrap(JSONSerialization.jsonObject(with: remoteJSON(precision: precision)) as? [String: Any])
      json["consistency"] = 0
      json["rank"] = 1
      json["userID"] = UUID().uuidString
      json["displayName"] = "Metrics"
      let data = try JSONSerialization.data(withJSONObject: json)
      let entry = try JSONDecoder().decode(RemoteLeaderboardEntry.self, from: data)
      let best = try JSONDecoder().decode(RemotePublicProfileBest.self, from: data)
      XCTAssertEqual(entry.preciseAccuracy, precision)
      XCTAssertEqual(best.preciseAccuracy, precision)
      XCTAssertEqual(entry.accuracy, 67)
      XCTAssertEqual(best.accuracy, 67)
      XCTAssertEqual(ResultMetricPresentation.accuracy(entry.preciseAccuracy ?? Double(entry.accuracy),
        alwaysShowDecimalPlaces: entry.preciseAccuracy != nil), precision == nil ? "67%" : "66.67%")
    }
  }

  private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
  }
}
