import XCTest
@testable import Typebar

final class RawUnitTraceTests: XCTestCase {
  private func insertion(_ units: [UInt16], at offset: Double = 0,
    correct: [Bool]? = nil, stopped: Bool = false) -> TypingReplayEvent {
    .init(offset: offset, kind: .insert, units: units, inputStopped: stopped ? true : nil,
      inputCorrectness: correct)
  }

  func testSeparatePairGetsTheSameSpeedCreditAsTheAcceptedEmoji() {
    let events = [insertion([55357], correct: [true]), insertion([56898], correct: [true])]
    let point = ResultPerformanceTrace.point(prompt: "🙂x", events: events, elapsed: 1)
    XCTAssertEqual(point.wpm, 24)
    XCTAssertEqual(point.rawWpm, 24)
    XCTAssertEqual(point.errorCount, 0)
  }

  func testStoppedLowLeavesOnlyTheCorrectHighSurrogateCreditAndCountsItsAttempt() {
    let events = [insertion([55357], correct: [true]), insertion([56899], at: 0.5, correct: [false], stopped: true)]
    let point = ResultPerformanceTrace.point(prompt: "🙂x", events: events, elapsed: 1)
    XCTAssertEqual(point.wpm, 12)
    XCTAssertEqual(point.rawWpm, 12)
    XCTAssertEqual(point.burstWpm, 24)
    XCTAssertEqual(point.errorCount, 1)
  }

  func testUnitDeleteRetainsHighCreditAndDoesNotEraseHistoricalAttempts() {
    let events = [insertion([55357], correct: [true]), insertion([56898], correct: [true]),
      TypingReplayEvent(offset: 0.5, kind: .delete, units: [])]
    let point = ResultPerformanceTrace.point(prompt: "🙂x", events: events, elapsed: 1)
    XCTAssertEqual(point.wpm, 12)
    XCTAssertEqual(point.rawWpm, 12)
    XCTAssertEqual(point.burstWpm, 24)
  }

  func testSafeReplacementTextCannotEarnLiteralReplacementWordCredit() {
    let events = [insertion([55357], correct: [false]), insertion([120], correct: [true])]
    let point = ResultPerformanceTrace.point(prompt: "�x", events: events, elapsed: 1)
    XCTAssertEqual(point.wpm, 0)
    XCTAssertEqual(point.rawWpm, 24)
    XCTAssertEqual(point.errorCount, 1)
  }

  func testRecordedRawJudgmentOwnsIntervalErrorsInsteadOfDisplayReplacement() {
    let events = [insertion([55357], correct: [false]), insertion([56898], correct: [true])]
    XCTAssertEqual(ResultPerformanceTrace.point(prompt: "🙂x", events: events, elapsed: 1).errorCount, 1)
  }

  func testMixedLegacyPrefixAndRawPairKeepTheirOwnDeletionContracts() {
    var events = [TypingReplayEvent(offset: 0, kind: .insert, text: "seed "),
      insertion([55357], at: 1, correct: [true]), insertion([56898], at: 1, correct: [true])]
    XCTAssertEqual(ResultPerformanceTrace.point(prompt: "seed 🙂x", events: events, elapsed: 2).wpm, 42)
    events.append(.init(offset: 2.5, kind: .delete, text: ""))
    let point = ResultPerformanceTrace.point(prompt: "seed 🙂x", events: events, elapsed: 3)
    XCTAssertEqual(point.wpm, 20, "Legacy deletion removes the full joined emoji")
    XCTAssertEqual(point.rawWpm, 20)
  }

  func testTargetSeparatorAndMarkFusionDoesNotMergeChartFields() {
    let events = Array("ab \u{301}c".utf16).map { insertion([$0], correct: [true]) }
    let point = ResultPerformanceTrace.point(prompt: "ab \u{301}cx", events: events, elapsed: 1)
    XCTAssertEqual(point.wpm, 60)
    XCTAssertEqual(point.rawWpm, 60)
    XCTAssertEqual(point.errorCount, 0)
  }

  func testRawSampledTailMatchesSinglePointWithoutChangingLegacyProjection() {
    let events = [insertion([55357], correct: [true]), insertion([56898], correct: [true]), insertion([120], at: 0.5, correct: [true])]
    let point = ResultPerformanceTrace.point(prompt: "🙂x", events: events, elapsed: 0.5)
    XCTAssertEqual(point.wpm, 72)
    XCTAssertEqual(ResultPerformanceTrace.points(prompt: "🙂x", events: events, duration: 0.5).last, point)
    let legacy = [TypingReplayEvent(offset: 0, kind: .insert, text: "🙂x"), .init(offset: 0.5, kind: .delete, text: "")]
    XCTAssertEqual(ResultPerformanceTrace.point(prompt: "🙂x", events: legacy, elapsed: 1).wpm, 24)
  }
}
