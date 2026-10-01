import XCTest
@testable import Typebar

final class InactivityBoundaryTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_700_000_000)

  func testUntimedIntervalsClassifyTheTailUsingRoundedHundredths() {
    let cases: [(Double, [Int])] = [
      (4.493, [1, 0, 0, 0]),
      (4.497, [1, 0, 0, 0, 1]),
      (4.6, [1, 0, 0, 0, 1]),
      (4.993, [1, 0, 0, 0, 1]),
      (4.997, [1, 0, 0, 0]),
      (5, [1, 0, 0, 0, 1]),
      (5.497, [1, 0, 0, 0, 0, 1]),
    ]
    for (duration, expected) in cases {
      let end = start.addingTimeInterval(duration)
      XCTAssertEqual(
        TestInactivityPolicy.intervalCounts(
          activityDates: [start, end], startedAt: start, endedAt: end,
          includesFractionalTail: true), expected, "duration: \(duration)")
    }
  }

  func testRoundedTailDoesNotExtendTheRawEventBoundary() {
    let end = start.addingTimeInterval(4.497)
    XCTAssertEqual(
      TestInactivityPolicy.intervalCounts(
        activityDates: [start, end, start.addingTimeInterval(4.498)],
        startedAt: start, endedAt: end, includesFractionalTail: true),
      [1, 0, 0, 0, 1])
    XCTAssertEqual(
      TestInactivityPolicy.inactiveDuration(
        activityDates: [start, end], startedAt: start, endedAt: end,
        includesFractionalTail: true), 3)
  }

  func testRecentWordCompletionInRoundedHalfSecondTailIsNotInvalidAFK() throws {
    var session = TypingSession(configuration: .words(1), prompt: "am")
    session.insertBatch("a", at: start)
    let end = start.addingTimeInterval(10.497)
    session.insertBatch("m", at: end)
    XCTAssertEqual(session.outcome, .completed)
    let result = try XCTUnwrap(session.result(at: end))
    XCTAssertEqual(result.afkDuration, 9)
    XCTAssertEqual(result.engagedDuration, 1.497, accuracy: 0.000_001)
    XCTAssertEqual(
      TypingReplay.typedText(events: result.replayEvents, through: result.elapsedDuration), "am")
  }

  func testNearWholeSecondCompletionPreservesTheReferenceDiscardedTail() throws {
    // The fixed reference drops a tail that rounds into the next whole second.
    // Preserve this edge rather than weakening AFK checks to fit a GUI sample.
    var session = TypingSession(configuration: .words(1), prompt: "am")
    session.insertBatch("a", at: start)
    let end = start.addingTimeInterval(10.997)
    session.insertBatch("m", at: end)
    XCTAssertEqual(session.outcome, .invalidAFK)
    XCTAssertEqual(try XCTUnwrap(session.result(at: end)).afkDuration, 9)
    XCTAssertFalse(ResultSavingPolicy.shouldPersist(outcome: session.outcome, enabled: true))
  }

  func testTimedIntervalsDoNotGainAFractionalTailFromRounding() {
    for duration in [4.493, 4.497, 4.6, 4.993, 4.997] {
      let end = start.addingTimeInterval(duration)
      XCTAssertEqual(
        TestInactivityPolicy.intervalCounts(
          activityDates: [start, end], startedAt: start, endedAt: end,
          includesFractionalTail: false), [1, 0, 0, 0])
    }
  }
}
