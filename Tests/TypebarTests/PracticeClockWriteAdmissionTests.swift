import XCTest
@testable import Typebar

final class PracticeClockWriteAdmissionTests: XCTestCase {
  func testUnstartedAttemptsIncludingConfiguredPaceDoNotNeedClockPublication() {
    for configuration in [TestConfiguration.words(2), .timed(seconds: 30), .timed(seconds: 0)] {
      var session = TypingSession(configuration: configuration, prompt: "ab cd")
      XCTAssertFalse(session.requiresClockTick)
      session.configurePace(wpm: 60)
      XCTAssertFalse(session.requiresClockTick)
    }
  }

  func testStartedFiniteTimerStillTicksAndCompletes() {
    let start = Date(timeIntervalSince1970: 1_000)
    var session = TypingSession(configuration: .timed(seconds: 1), prompt: "ab cd")
    session.insert("a", at: start)
    XCTAssertTrue(session.requiresClockTick)
    XCTAssertFalse(session.tick(at: start.addingTimeInterval(0.5)), "Waiting for a deadline is not a value change")
    XCTAssertTrue(session.tick(at: start.addingTimeInterval(1.1)))
    XCTAssertTrue(session.isFinished)
    XCTAssertFalse(session.requiresClockTick)
  }

  func testUntimedInputRemainsUsableWithoutTickAndActivePaceStillRequiresIt() {
    var session = TypingSession(configuration: .words(2), prompt: "ab cd")
    session.insert("a")
    XCTAssertFalse(session.requiresClockTick)
    session.insert("b ")
    XCTAssertEqual(session.typed, "ab ")
    var paced = TypingSession(configuration: .words(2), prompt: "ab cd")
    paced.configurePace(wpm: 60)
    paced.insert("a")
    XCTAssertTrue(paced.requiresClockTick)
    paced.abandon()
    XCTAssertFalse(paced.requiresClockTick)
  }

  func testStartedInfiniteTimerWithoutPaceHasNoClockDrivenTerminalCondition() {
    var session = TypingSession(configuration: .timed(seconds: 0), prompt: "ab cd")
    session.insert("a")
    XCTAssertFalse(session.requiresClockTick)
    session.tick(at: .distantFuture)
    XCTAssertFalse(session.isFinished)
  }

  func testPaceClockPublishesDeliveredRequestsWithoutAdvancingThem() {
    let clock = PaceCaretTestClock()
    var session = TypingSession(configuration: .words(2), prompt: "ab cd")
    session.configurePace(wpm: 60, clock: clock.source)
    XCTAssertFalse(session.tick())
    session.insert("a")
    XCTAssertFalse(session.tick())
    clock.time = 0.1
    XCTAssertFalse(session.tick(), "Elapsed time cannot deliver a pace callback")
    XCTAssertFalse(session.tick(), "An identical owned sample must not publish again")
    clock.time = 100
    XCTAssertFalse(session.tick())
    session.deliverPaceCaretTimer(session.paceCaretPendingTicket!)
    XCTAssertTrue(session.tick(), "A delivered request refreshes status without driving the caret")
    XCTAssertFalse(session.tick())
    for _ in 0..<10 {
      if let ticket = session.paceCaretPendingTicket { session.deliverPaceCaretTimer(ticket) }
    }
    XCTAssertNil(session.paceCaretFrame())
    XCTAssertTrue(session.tick(), "Exhaustion visibility is published once")
    clock.time = 101
    XCTAssertFalse(session.tick(), "An exhausted pace has no further clock mutation")
  }
}
