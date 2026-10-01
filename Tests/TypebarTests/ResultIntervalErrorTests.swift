import XCTest
@testable import Typebar

final class ResultIntervalErrorTests: XCTestCase {
  func testCorrectionWithinOneWindowDoesNotEraseTheMistake() {
    let points = ResultPerformanceTrace.points(prompt: "ab", events: [
      .init(offset: 0, kind: .insert, text: "a"),
      .init(offset: 0.2, kind: .insert, text: "x"),
      .init(offset: 0.3, kind: .delete, text: ""),
      .init(offset: 0.4, kind: .insert, text: "b"),
    ], duration: 2)
    XCTAssertEqual(points.map(\.errorCount), [1, 0])
    XCTAssertEqual(points.map(\.wpm), [24, 12])
    XCTAssertEqual(points.map(\.rawWpm), [24, 12])
    XCTAssertEqual(points.map(\.burstWpm), [36, 0])
  }

  func testAnUncorrectedMistakeIsNotCountedAgainDuringPauses() {
    let events: [TypingReplayEvent] = [.init(offset: 0, kind: .insert, text: "x")]
    XCTAssertEqual(ResultPerformanceTrace.points(prompt: "ab", events: events,
      duration: 3).map(\.errorCount), [1, 0, 0])
    XCTAssertEqual(ResultPerformanceTrace.point(prompt: "ab", events: events,
      elapsed: 2).errorCount, 0)
  }

  func testDeletingAndRepeatingTheSameMistakeCountsEachAttempt() {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "x"),
      .init(offset: 0.2, kind: .delete, text: ""),
      .init(offset: 0.3, kind: .insert, text: "x"),
      .init(offset: 0.4, kind: .delete, text: ""),
    ]
    XCTAssertEqual(ResultPerformanceTrace.points(prompt: "a", events: events,
      duration: 1).map(\.errorCount), [2])
    XCTAssertEqual(ResultPerformanceTrace.point(prompt: "a", events: events,
      elapsed: 1).errorCount, 2)
  }

  func testZeroAndRightBoundaryErrorsAreCountedOnceAndLateErrorsAreExcluded() {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "a", forceError: true),
      .init(offset: 1, kind: .insert, text: "a", forceError: true),
      .init(offset: 1.001, kind: .insert, text: "a", forceError: true),
      .init(offset: 2, kind: .insert, text: "a", forceError: true),
      .init(offset: 2.001, kind: .insert, text: "a", forceError: true),
    ]
    XCTAssertEqual(ResultPerformanceTrace.points(prompt: "aaaaa", events: events,
      duration: 2).map(\.errorCount), [2, 2])
    XCTAssertEqual(ResultPerformanceTrace.point(prompt: "aaaaa", events: events,
      elapsed: 2).errorCount, 2)
  }

  func testUnicodeAndBatchErrorsUseIndividualUTF16InputUnits() {
    let forced: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "🦊e\u{301}", forceError: true),
    ]
    XCTAssertEqual(ResultPerformanceTrace.points(prompt: "🦊e\u{301}", events: forced,
      duration: 2).map(\.errorCount), [4, 0])
    // Both emoji share the leading surrogate; only the trailing unit differs.
    XCTAssertEqual(ResultPerformanceTrace.points(prompt: "🦁a", events: [
      .init(offset: 0, kind: .insert, text: "🦊a"),
    ], duration: 2).map(\.errorCount), [1, 0])
    XCTAssertEqual(ResultPerformanceTrace.points(prompt: "abcd", events: [
      .init(offset: 0, kind: .insert, text: "axyd"),
      .init(offset: 0.5, kind: .delete, text: ""),
      .init(offset: 0.6, kind: .delete, text: ""),
    ], duration: 2).map(\.errorCount), [2, 0])
  }

  func testAutomaticInsertionsStillCountButAutomaticDeletionsDoNotEraseErrors() {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "x", automatic: true),
      .init(offset: 0.1, kind: .delete, text: "", automatic: true),
      .init(offset: 0.2, kind: .insert, text: "a", automatic: true),
    ]
    XCTAssertEqual(ResultPerformanceTrace.points(prompt: "ab", events: events,
      duration: 2).map(\.errorCount), [1, 0])
  }

  func testEarlyWordCommitDoesNotMisclassifyTheNextWordAndDeleteRestoresItsPosition() {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "a "),
      .init(offset: 1.2, kind: .insert, text: "cd"),
      .init(offset: 1.3, kind: .delete, text: ""),
      .init(offset: 1.4, kind: .delete, text: ""),
      .init(offset: 1.5, kind: .delete, text: ""),
      .init(offset: 1.6, kind: .insert, text: "b cd"),
    ]
    XCTAssertEqual(ResultPerformanceTrace.points(prompt: "ab cd", events: Array(events.prefix(2)),
      duration: 2).map(\.errorCount), [1, 0])
    XCTAssertEqual(ResultPerformanceTrace.points(prompt: "ab cd", events: events,
      duration: 3).map(\.errorCount), [1, 0, 0])
  }

  func testInvalidTimesAreRejectedAndEqualTimeInsertionAndDeleteOrderIsPreserved() {
    let events: [TypingReplayEvent] = [
      .init(offset: 1.2, kind: .insert, text: "b"),
      .init(offset: .nan, kind: .insert, text: "x"),
      .init(offset: -1, kind: .insert, text: "x"),
      .init(offset: .infinity, kind: .insert, text: "x"),
      .init(offset: 0, kind: .insert, text: "x"),
      .init(offset: 0, kind: .delete, text: ""),
      .init(offset: 0, kind: .insert, text: "a"),
    ]
    XCTAssertEqual(ResultPerformanceTrace.points(prompt: "ab", events: events,
      duration: 2).map(\.errorCount), [1, 0])
  }

  func testFiniteTailCountsErrorsWithoutDividingByItsDurationAndTimedTailIsExcluded() {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "a"),
      .init(offset: 1.2, kind: .insert, text: "x"),
      .init(offset: 1.3, kind: .delete, text: ""),
      .init(offset: 1.4, kind: .insert, text: "x"),
      .init(offset: 1.501, kind: .insert, text: "x"),
    ]
    XCTAssertEqual(ResultPerformanceTrace.points(prompt: "ab", events: events,
      duration: 1.5, configuration: .words(1)).map(\.errorCount), [0, 2])
    XCTAssertEqual(ResultPerformanceTrace.points(prompt: "ab", events: events,
      duration: 1.5, configuration: .timed(seconds: 2)).map(\.errorCount), [0])
  }

  func testZenHasNoTargetErrorsEvenForForcedRejectedShiftSemantics() {
    let configuration = TestConfiguration(mode: .zen, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), language: .english)
    XCTAssertEqual(ResultPerformanceTrace.points(prompt: "user text", events: [
      .init(offset: 0, kind: .insert, text: "user", forceError: true),
      .init(offset: 1.2, kind: .insert, text: " text"),
    ], duration: 2, configuration: configuration).map(\.errorCount), [0, 0])
  }

  func testNewlineCommitsButTabRemainsWordContentAndExtraTextCountsAtInsertion() {
    XCTAssertEqual(ResultPerformanceTrace.points(prompt: "ab\n\tcd", events: [
      .init(offset: 0, kind: .insert, text: "a\n"),
      .init(offset: 1.2, kind: .insert, text: "\tcd"),
      .init(offset: 1.4, kind: .insert, text: "xx"),
      .init(offset: 1.5, kind: .delete, text: ""),
      .init(offset: 1.6, kind: .delete, text: ""),
    ], duration: 3).map(\.errorCount), [1, 2, 0])
  }

  func testCompletedReplayPreservesNormalizedCorrectInputAndLegacyJSON() throws {
    let start = Date(timeIntervalSince1970: 100)
    var session = TypingSession(configuration: .words(1), prompt: "’a")
    session.insert("'", at: start)
    session.insert("a", at: start.addingTimeInterval(1.8))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.outcome, .completed)
    XCTAssertEqual(result.errorCount, 0)
    XCTAssertEqual(result.accuracy, 100)
    let decoded = try JSONDecoder().decode(CompletedTestResult.self,
      from: JSONEncoder().encode(result))
    XCTAssertEqual(decoded, result)
    XCTAssertEqual(ResultPerformanceTrace.points(prompt: decoded.prompt, events: decoded.replayEvents,
      duration: decoded.elapsedDuration, configuration: decoded.configuration).map(\.errorCount), [0, 0])
    let legacy = try JSONDecoder().decode([TypingReplayEvent].self, from: Data(
      #"[{"offset":0,"kind":"insert","text":"x"},{"offset":0.1,"kind":"delete","text":""},{"offset":0.2,"kind":"insert","text":"a"}]"#.utf8))
    XCTAssertEqual(ResultPerformanceTrace.points(prompt: "ab", events: legacy,
      duration: 2).map(\.errorCount), [1, 0])
    XCTAssertEqual(TypingReplay.typedText(events: legacy, through: 2), "a")
  }

  func testSpaceNormalizationAndLanguageSpecificEquivalenceUseTheOriginalConfiguration() {
    for space in ["\u{00A0}", "\u{3000}", "\u{200B}"] {
      XCTAssertEqual(ResultPerformanceTrace.points(prompt: "a cd", events: [
        .init(offset: 0, kind: .insert, text: "a" + space),
        .init(offset: 1.2, kind: .insert, text: "cd"),
      ], duration: 2).map(\.errorCount), [0, 0])
    }
    let events: [TypingReplayEvent] = [.init(offset: 0, kind: .insert, text: "ea")]
    XCTAssertEqual(ResultPerformanceTrace.points(prompt: "ёa", events: events,
      duration: 2, configuration: .words(1, language: .russian375k)).map(\.errorCount), [0, 0])
    XCTAssertEqual(ResultPerformanceTrace.points(prompt: "ёa", events: events,
      duration: 2, configuration: .words(1)).map(\.errorCount), [1, 0])
    XCTAssertEqual(ResultPerformanceTrace.points(prompt: "ёa", events: events,
      duration: 2).map(\.errorCount), [1, 0])
  }

  func testNoSpaceErrorsDoNotInventWordSubmitUnitsOrRequireHiddenBoundaries() {
    let configuration = TestConfiguration.words(2).with(modifiers: [.noSpaces])
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "ax"),
      .init(offset: 0.2, kind: .delete, text: ""),
      .init(offset: 0.3, kind: .insert, text: "b"),
      .init(offset: 1.2, kind: .insert, text: "cd"),
    ]
    XCTAssertEqual(ResultPerformanceTrace.points(prompt: "abcd", events: events,
      duration: 3, configuration: configuration).map(\.errorCount), [1, 0, 0])
    XCTAssertEqual(ResultPerformanceTrace.point(prompt: "abcd", events: events,
      elapsed: 1.5, configuration: configuration).errorCount, 0)
  }

  func testCompletedCorrectionReplayChangesTheChartNotTheSavedScore() throws {
    let start = Date(timeIntervalSince1970: 100)
    var session = TypingSession(configuration: .words(1), prompt: "ab")
    session.insert("x", at: start)
    session.deleteBackward(at: start.addingTimeInterval(0.1))
    session.insert("a", at: start.addingTimeInterval(0.2))
    session.insert("b", at: start.addingTimeInterval(1.8))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.outcome, .completed)
    XCTAssertEqual(result.errorCount, 0)
    XCTAssertEqual(result.wpm, 13)
    XCTAssertEqual(result.rawWpm, 13)
    let decoded = try JSONDecoder().decode(CompletedTestResult.self,
      from: JSONEncoder().encode(result))
    XCTAssertEqual(decoded, result)
    let points = ResultPerformanceTrace.points(prompt: decoded.prompt, events: decoded.replayEvents,
      duration: decoded.elapsedDuration, configuration: decoded.configuration)
    XCTAssertEqual(points.map(\.errorCount), [1, 0])
    XCTAssertEqual(ResultBurstSmoothingPolicy.points(points, enabled: true).map(\.errorCount), [1, 0])
    XCTAssertEqual(TypingReplay.typedText(events: decoded.replayEvents,
      through: decoded.elapsedDuration), "ab")
  }
}
