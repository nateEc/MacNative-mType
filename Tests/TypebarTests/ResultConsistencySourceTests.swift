import XCTest
@testable import Typebar

final class ResultConsistencySourceTests: XCTestCase {
  private func result(
    events: [TypingReplayEvent], duration: Double,
    configuration: TestConfiguration = .words(1), keySpacing: [Double] = []
  ) -> CompletedTestResult {
    let start = Date(timeIntervalSince1970: 100)
    return .init(id: UUID(), configuration: configuration, outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(duration),
      typedCharacterCount: 2, correctCharacterCount: 2, errorCount: 0,
      wpm: 45, rawWpm: 56, accuracy: 88, keySpacingSamples: keySpacing,
      prompt: "ab", replayEvents: events)
  }

  private func csvFields(_ result: CompletedTestResult) -> [String: String] {
    let row = ResultCSVExport.csvString(for: [result]).components(separatedBy: "\r\n")[1]
    return Dictionary(uniqueKeysWithValues: zip(ResultCSVExport.columns, row.components(separatedBy: ",")))
  }

  func testZeroTimeFirstInputBelongsToTheFirstWindow() {
    let metric = ResultConsistencyPolicy.metrics(events: [
      .init(offset: 0, kind: .insert, text: "a"),
      .init(offset: 1.2, kind: .insert, text: "b"),
      .init(offset: 2.2, kind: .insert, text: "c"),
    ], duration: 3)
    XCTAssertEqual(metric.typing, 100)
    XCTAssertEqual(metric.key, 0, "Text events are not physical keydown evidence")
  }

  func testUnicodeAndNativeBatchStorageDoNotChangeTheInputUnitCadence() {
    XCTAssertEqual(ResultConsistencyPolicy.metrics(events: [
      .init(offset: 0.2, kind: .insert, text: "🦊"),
      .init(offset: 1.2, kind: .insert, text: "ab"),
    ], duration: 2).typing, 100)
    XCTAssertEqual(ResultConsistencyPolicy.metrics(events: [
      .init(offset: 0.2, kind: .insert, text: "e\u{301}"),
      .init(offset: 1.2, kind: .insert, text: "ab"),
    ], duration: 2).typing, 100)
  }

  func testDeletionDoesNotRemoveEarlierActivityAndAutomaticInputStillCounts() {
    let metric = ResultConsistencyPolicy.metrics(events: [
      .init(offset: 0.2, kind: .insert, text: "x", forceError: true),
      .init(offset: 0.3, kind: .delete, text: "", automatic: true),
      .init(offset: 1.2, kind: .insert, text: "a", automatic: true),
    ], duration: 2)
    XCTAssertEqual(metric.typing, 100)
    XCTAssertEqual(metric.key, 0)
  }

  func testBatchAndSeparateEventsWithTheSameWindowActivityAgree() {
    let separate = ResultConsistencyPolicy.metrics(events: [
      .init(offset: 0.2, kind: .insert, text: "a"),
      .init(offset: 0.3, kind: .insert, text: "b"),
      .init(offset: 1.2, kind: .insert, text: "c"),
      .init(offset: 1.3, kind: .insert, text: "d"),
    ], duration: 2)
    let batch = ResultConsistencyPolicy.metrics(events: [
      .init(offset: 0.2, kind: .insert, text: "ab"),
      .init(offset: 1.2, kind: .insert, text: "cd"),
    ], duration: 2)
    XCTAssertEqual(separate, batch)
    XCTAssertEqual(batch, .init(typing: 100, key: 0))
  }

  func testInvalidAndLateEventsDoNotContaminateTheSamples() {
    XCTAssertEqual(ResultConsistencyPolicy.metrics(events: [
      .init(offset: 1.2, kind: .insert, text: "b"),
      .init(offset: .nan, kind: .insert, text: "x"),
      .init(offset: -1, kind: .insert, text: "x"),
      .init(offset: .infinity, kind: .insert, text: "x"),
      .init(offset: 2.001, kind: .insert, text: "x"),
      .init(offset: 0, kind: .insert, text: "a"),
    ], duration: 2).typing, 100)
  }

  func testHundredthsClassifyTheHalfSecondTailAndCarryCanDiscardIt() {
    let base: [TypingReplayEvent] = (0..<4).map {
      .init(offset: Double($0) + 0.2, kind: .insert, text: "a")
    }
    XCTAssertEqual(ResultConsistencyPolicy.metrics(events: base + [
      .init(offset: 4.497, kind: .insert, text: "a"),
    ], duration: 4.497).typing, 66.67)
    XCTAssertEqual(ResultConsistencyPolicy.metrics(events: base + [
      .init(offset: 4.997, kind: .insert, text: "aa"),
    ], duration: 4.997).typing, 100)
  }

  func testLongPracticeIsNotLimitedToTheResultChartHorizon() {
    let events: [TypingReplayEvent] = (0..<150).map {
      .init(offset: $0 == 0 ? 0 : Double($0) + 0.2, kind: .insert, text: "a")
    }
    XCTAssertEqual(ResultConsistencyPolicy.metrics(events: events, duration: 150).typing, 100)
  }

  func testDeleteOnlyReplayCannotInventPhysicalKeyConsistency() {
    let events: [TypingReplayEvent] = (0..<3).map {
      .init(offset: Double($0) + 0.2, kind: .delete, text: "")
    }
    XCTAssertEqual(ResultConsistencyPolicy.metrics(events: events, duration: 3),
      .init(typing: 0, key: 0))
  }

  func testTimedConfigurationFlowsIntoHistoryCSVAndNewSubmission() {
    let result = result(events: [
      .init(offset: 0.2, kind: .insert, text: "a"),
      .init(offset: 1.25, kind: .insert, text: "b"),
    ], duration: 1.5, configuration: .timed(seconds: 2))
    XCTAssertEqual(ResultMetric(record: TestResultRecord(result: result)).consistency, 100)
    XCTAssertEqual(csvFields(result)["typing_consistency_percent"], "100.00")
    XCTAssertEqual(RemoteResultSubmission(result: result).consistency, 100)
    XCTAssertEqual(result.wpm, 45)
    XCTAssertEqual(result.rawWpm, 56)
    XCTAssertEqual(result.accuracy, 88)
  }

  func testPhysicalKeySpacingWorksWithoutAnyTextReplay() {
    let result = result(events: [], duration: 2, keySpacing: [0.1, 0.1, 0.9])
    let fields = csvFields(result)
    XCTAssertEqual(fields["typing_consistency_percent"], "0.00")
    XCTAssertEqual(fields["key_consistency_percent"], "100.00")
  }

  func testUnevenPhysicalSpacingWinsOverApparentlySteadyTextReplay() {
    let events: [TypingReplayEvent] = (0..<3).map {
      .init(offset: Double($0) + 0.2, kind: .insert, text: "a")
    }
    let result = result(events: events, duration: 3, keySpacing: [0.1, 0.3, 0.9])
    XCTAssertEqual(csvFields(result)["typing_consistency_percent"], "100.00")
    XCTAssertEqual(csvFields(result)["key_consistency_percent"], "50.10")
  }

  func testLastPhysicalSpacingIsDiscardedAndZeroSamplesAreNotMissingData() {
    for last in [0.9, 9.0] {
      XCTAssertEqual(csvFields(result(events: [], duration: 2,
        keySpacing: [0.1, 0.3, last]))["key_consistency_percent"], "50.10")
    }
    XCTAssertEqual(csvFields(result(events: [], duration: 2,
      keySpacing: [0, 0.2, 0.9]))["key_consistency_percent"], "8.90")
    XCTAssertEqual(csvFields(result(events: [], duration: 2,
      keySpacing: [0, 0, 0.9]))["key_consistency_percent"], "0.00")
  }

  func testLegacyRecordWithoutPhysicalEvidenceIsNeutralDespiteRegularTextEvents() throws {
    let events: [TypingReplayEvent] = (0..<3).map {
      .init(offset: Double($0) + 0.2, kind: .insert, text: "a")
    }
    let original = result(events: events, duration: 3)
    let decoded = try JSONDecoder().decode(CompletedTestResult.self,
      from: JSONEncoder().encode(original))
    XCTAssertEqual(decoded, original)
    XCTAssertEqual(csvFields(decoded)["key_consistency_percent"], "0.00")
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: decoded).portableResult), decoded)
  }

  func testCompletedNativePhysicalPressesDriveKeyConsistencyInsteadOfTextOffsets() throws {
    let start = Date(timeIntervalSince1970: 100)
    var session = TypingSession(configuration: .timed(seconds: 1), prompt: "amber")
    for (index, offset) in [0.0, 0.1, 0.4, 0.9].enumerated() {
      let at = start.addingTimeInterval(offset)
      session.recordPhysicalKeyEvent(keyCode: UInt16(index), isKeyDown: true, isRepeat: false, at: at)
      if index == 0 { session.insert("a", at: at) }
      session.recordPhysicalKeyEvent(keyCode: UInt16(index), isKeyDown: false, isRepeat: false,
        at: at.addingTimeInterval(0.02))
    }
    session.tick(at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.outcome, .completed)
    XCTAssertEqual(result.keySpacingSamples.count, 3)
    XCTAssertEqual(csvFields(result)["typing_consistency_percent"], "100.00")
    XCTAssertEqual(csvFields(result)["key_consistency_percent"], "50.10")
    XCTAssertEqual(try JSONDecoder().decode(CompletedTestResult.self,
      from: JSONEncoder().encode(result)), result)
  }

  func testNonFiniteAndNegativeDurationsAreNeutral() {
    for duration in [Double.nan, .infinity, -.infinity, -1, 0] {
      XCTAssertEqual(ResultConsistencyPolicy.metrics(events: [], duration: duration),
        .init(typing: 0, key: 0))
    }
  }

  func testPersonalBestRowAndChallengeEvaluationCarryTheSamplingConfiguration() throws {
    let configuration = TestConfiguration.timed(seconds: 2)
    let result = result(events: [
      .init(offset: 0.2, kind: .insert, text: "a"),
      .init(offset: 1.25, kind: .insert, text: "b"),
    ], duration: 1.5, configuration: configuration)
    let row = try XCTUnwrap(LocalPersonalBestTablePolicy.rows(results: [result]).first)
    XCTAssertEqual(row.id, result.id)
    XCTAssertEqual(row.wpm, result.preciseWpm)
    XCTAssertEqual(row.consistency, 100)
    let challenge = TypebarChallenge(id: "native-consistency-test", title: "节奏测试",
      description: "自有规则夹具", preset: .init(configuration: configuration, quoteID: nil, customText: nil),
      requirements: .init(consistency: .minimum(90)))
    let evaluation = ChallengeEvaluator.evaluate(result, challenge: challenge)
    XCTAssertTrue(evaluation.passed, "\(evaluation.failedRequirements)")
    XCTAssertEqual(evaluation.failedRequirements, [])
  }

  func testShortFiniteAndTimedModesShareTheChartSamplingGate() {
    let events: [TypingReplayEvent] = [.init(offset: 0, kind: .insert, text: "a")]
    let configurations: [(TestConfiguration, Double)] = [
      (.words(1), 100),
      (.timed(seconds: 30), 0),
      (.words(0), 0),
      (.init(mode: .custom, duration: 30, wordLimit: nil, difficulty: .normal,
        rules: .init(), customTextCompletion: .time), 0),
      (.init(mode: .custom, duration: nil, wordLimit: 0, difficulty: .normal,
        rules: .init(), customTextCompletion: .words), 0),
    ]
    for (configuration, expected) in configurations {
      XCTAssertEqual(ResultConsistencyPolicy.metrics(events: events, duration: 0.497,
        configuration: configuration).typing, expected)
      XCTAssertEqual(ResultPerformanceTrace.points(prompt: "a", events: events, duration: 0.497,
        configuration: configuration).count, expected == 100 ? 1 : 0)
    }
  }

  func testSparseWindowsRetainZeroPopulationAndAcceptVeryLargeFiniteDurations() {
    XCTAssertEqual(ResultConsistencyPolicy.metrics(events: [
      .init(offset: 0, kind: .insert, text: "a"),
      .init(offset: 2.2, kind: .insert, text: "b"),
    ], duration: 3).typing, 30.36)
    XCTAssertEqual(ResultConsistencyPolicy.metrics(events: [
      .init(offset: 0, kind: .insert, text: "a"),
      .init(offset: 1.2, kind: .insert, text: "b"),
      .init(offset: 2.2, kind: .insert, text: "cd"),
    ], duration: 3).typing, 64.65)
    let began = ProcessInfo.processInfo.systemUptime
    for duration in [1e20, Double.greatestFiniteMagnitude] {
      XCTAssertEqual(ResultConsistencyPolicy.metrics(events: [
        .init(offset: 0, kind: .insert, text: "a"),
      ], duration: duration).typing, 0)
    }
    XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - began, 1)
  }

  func testPhysicalSpacingScaleCannotOverflowOrUnderflowTheVariance() {
    for scale in [1e-300, 1, 1e200] {
      XCTAssertEqual(ResultConsistencyPolicy.metrics(events: [], duration: 1,
        keySpacingSamples: [scale, 3 * scale, 9 * scale]).key, 50.1)
    }
  }
}
