import XCTest
@testable import Typebar

final class ResultIntervalBurstTests: XCTestCase {
  func testChartBurstCountsInputWithinEachWindowAndFallsToZeroOnPause() {
    let points = ResultPerformanceTrace.points(
      prompt: "amber", events: [
        .init(offset: 0, kind: .insert, text: "a"),
        .init(offset: 1, kind: .insert, text: "m"),
        .init(offset: 2, kind: .insert, text: "x"),
        .init(offset: 2.1, kind: .delete, text: ""),
        .init(offset: 3, kind: .insert, text: "b"),
      ], duration: 4)
    XCTAssertEqual(points.map(\.elapsed), [1, 2, 3, 4])
    XCTAssertEqual(points.map(\.burstWpm), [24, 12, 12, 0])
    XCTAssertEqual(points.map(\.errorCount), [0, 1, 0, 0])
  }

  func testDeletingAllTextDoesNotEraseEarlierInputActivity() {
    let points = ResultPerformanceTrace.points(
      prompt: "ab", events: [
        .init(offset: 0.2, kind: .insert, text: "a"),
        .init(offset: 0.4, kind: .insert, text: "b"),
        .init(offset: 0.6, kind: .delete, text: ""),
        .init(offset: 0.7, kind: .delete, text: ""),
      ], duration: 1)
    XCTAssertEqual(points.map(\.burstWpm), [24])
    XCTAssertEqual(points.map(\.rawWpm), [0])
    XCTAssertEqual(points.map(\.wpm), [0])
  }

  func testZeroAndExactBoundaryInputsAreCountedOnceAndLateInputsAreExcluded() {
    let points = ResultPerformanceTrace.points(
      prompt: "abcde", events: [
        .init(offset: 0, kind: .insert, text: "a"),
        .init(offset: 1, kind: .insert, text: "b"),
        .init(offset: 1.001, kind: .insert, text: "c"),
        .init(offset: 2, kind: .insert, text: "d"),
        .init(offset: 2.001, kind: .insert, text: "e"),
      ], duration: 2)
    XCTAssertEqual(points.map(\.burstWpm), [24, 24])
    XCTAssertEqual(points.map(\.rawWpm), [24, 24])
  }

  func testUnicodeBatchAndAutomaticInsertionsCountWithoutVirtualWordSubmit() {
    // Source insertText processing emits one event per UTF-16 input unit,
    // including automatic text; the native replay may store a batch instead.
    let points = ResultPerformanceTrace.points(
      prompt: "🦊ae\u{301}\n", events: [
        .init(offset: 0, kind: .insert, text: "🦊a"),
        .init(offset: 0.25, kind: .insert, text: "e\u{301}", forceError: true),
        .init(offset: 0.5, kind: .insert, text: "\n", automatic: true),
      ], duration: 2)
    XCTAssertEqual(points.map(\.burstWpm), [72, 0])
    XCTAssertEqual(points.map(\.errorCount), [1, 1])
  }

  func testNoSpaceChartDoesNotRequireOrInventWordBoundaries() {
    let points = ResultPerformanceTrace.points(
      prompt: "abcd", events: [
        .init(offset: 0, kind: .insert, text: "ab"),
        .init(offset: 1.2, kind: .insert, text: "c"),
        .init(offset: 1.5, kind: .insert, text: "d"),
      ], duration: 3)
    XCTAssertEqual(points.map(\.burstWpm), [24, 24, 0])
  }

  func testSingleBatchHasMeasurableWindowBurstEvenWithoutWordKeyInterval() {
    let events: [TypingReplayEvent] = [.init(offset: 0.2, kind: .insert, text: "abcdef")]
    XCTAssertEqual(ResultPerformanceTrace.points(
      prompt: "abcdef", events: events, duration: 1).map(\.burstWpm), [72])
    XCTAssertEqual(ResultPerformanceTrace.point(
      prompt: "abcdef", events: events, elapsed: 0.5).burstWpm, 144)
  }

  func testInvalidAndReversedReplayTimestampsDoNotContaminateWindows() {
    let events: [TypingReplayEvent] = [
      .init(offset: 2, kind: .insert, text: "b"),
      .init(offset: -1, kind: .insert, text: "x"),
      .init(offset: .nan, kind: .insert, text: "x"),
      .init(offset: .infinity, kind: .insert, text: "x"),
      .init(offset: 0, kind: .insert, text: "a"),
    ]
    let points = ResultPerformanceTrace.points(prompt: "ab", events: events, duration: 3)
    XCTAssertEqual(points.map(\.burstWpm), [12, 12, 0])
    XCTAssertEqual(points.map(\.errorCount), [0, 0, 0])
    XCTAssertEqual(ResultPerformanceTrace.point(prompt: "ab", events: events, elapsed: 3).burstWpm, 0)
    XCTAssertEqual(ResultPerformanceTrace.points(
      prompt: "ab", events: [.init(offset: .nan, kind: .insert, text: "a")], duration: 1), [])
  }

  func testFiniteTailUsesRoundedHundredthsButKeepsTheRawCutoff() {
    let cases: [(Double, [Double], [Int])] = [
      (4.493, [1, 2, 3, 4], [12, 0, 0, 0]),
      (4.497, [1, 2, 3, 4, 4.497], [12, 0, 0, 0, 24]),
      (4.993, [1, 2, 3, 4, 4.993], [12, 0, 0, 0, 12]),
      (4.997, [1, 2, 3, 4], [12, 0, 0, 0]),
    ]
    for (duration, expectedTimes, expectedBursts) in cases {
      let points = ResultPerformanceTrace.points(
        prompt: "abc", events: [
          .init(offset: 0, kind: .insert, text: "a"),
          .init(offset: duration, kind: .insert, text: "b"),
          .init(offset: duration + 0.001, kind: .insert, text: "c"),
        ], duration: duration)
      XCTAssertEqual(points.map(\.elapsed), expectedTimes)
      XCTAssertEqual(points.map(\.burstWpm), expectedBursts)
    }
  }

  func testReplayPointUsesTheCurrentGridWindowInsteadOfTheActiveWord() {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "a"),
      .init(offset: 1, kind: .insert, text: "b"),
      .init(offset: 2, kind: .insert, text: "c"),
      .init(offset: 2.25, kind: .insert, text: "d"),
      .init(offset: 2.5, kind: .insert, text: "e"),
    ]
    XCTAssertEqual(ResultPerformanceTrace.point(prompt: "abcde", events: events, elapsed: 2).burstWpm, 12)
    XCTAssertEqual(ResultPerformanceTrace.point(prompt: "abcde", events: events, elapsed: 2.5).burstWpm, 48)
    XCTAssertEqual(ResultPerformanceTrace.point(prompt: "abcde", events: events, elapsed: 3.1).burstWpm, 0)
  }

  func testTimedAndInfiniteConfigurationsDoNotAppendAFractionalTail() {
    let configurations: [TestConfiguration] = [
      .timed(seconds: 30),
      .words(0),
      .init(mode: .custom, duration: 30, wordLimit: nil, difficulty: .normal,
        rules: .init(), customTextCompletion: .time),
      .init(mode: .custom, duration: nil, wordLimit: 0, difficulty: .normal,
        rules: .init(), customTextCompletion: .words),
    ]
    for configuration in configurations {
      let points = ResultPerformanceTrace.points(
        prompt: "ab", events: [
          .init(offset: 0, kind: .insert, text: "a"),
          .init(offset: 3.6, kind: .insert, text: "b"),
        ], duration: 3.6, configuration: configuration)
      XCTAssertEqual(points.map(\.elapsed), [1, 2, 3])
      XCTAssertEqual(points.map(\.burstWpm), [12, 0, 0])
    }
  }

  func testSubHalfSecondFiniteResultsHaveNoInventedSample() {
    let events: [TypingReplayEvent] = [.init(offset: 0, kind: .insert, text: "a")]
    XCTAssertEqual(ResultPerformanceTrace.points(prompt: "a", events: events, duration: 0.493), [])
    XCTAssertFalse(ResultPerformanceChartAvailability.isAvailable(
      prompt: "a", events: events, duration: 0.493, configuration: .words(1)))
    XCTAssertTrue(ResultPerformanceChartAvailability.isAvailable(
      prompt: "a", events: events, duration: 0.497, configuration: .words(1)))
    XCTAssertFalse(ResultPerformanceChartAvailability.isAvailable(
      prompt: "a", events: events, duration: 0.6, configuration: .timed(seconds: 1)))
  }

  func testLegacyReplayRoundTripPreservesSavedMetricsWhileDerivingIntervalBurst() throws {
    let start = Date(timeIntervalSince1970: 100)
    let legacyEvents = try JSONDecoder().decode([TypingReplayEvent].self, from: Data(
      #"[{"offset":0,"kind":"insert","text":"a"},{"offset":1,"kind":"insert","text":"b"}]"#.utf8))
    XCTAssertTrue(legacyEvents.allSatisfy { !$0.forceError && !$0.automatic })
    let original = CompletedTestResult(
      id: UUID(), configuration: .words(2), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(3),
      typedCharacterCount: 2, correctCharacterCount: 2, errorCount: 0,
      wpm: 8, rawWpm: 8, accuracy: 100, prompt: "ab", replayEvents: legacyEvents)
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let encoded = try encoder.encode(original)
    let decoded = try JSONDecoder().decode(CompletedTestResult.self, from: encoded)
    let points = ResultPerformanceTrace.points(
      prompt: decoded.prompt, events: decoded.replayEvents, duration: decoded.elapsedDuration,
      configuration: decoded.configuration)
    XCTAssertEqual(points.map(\.burstWpm), [24, 0, 0])
    XCTAssertEqual(decoded, original)
    XCTAssertEqual(try encoder.encode(decoded), encoded)
  }
}
