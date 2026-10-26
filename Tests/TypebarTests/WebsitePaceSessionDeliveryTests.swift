import XCTest
@testable import Typebar

final class WebsitePaceSessionDeliveryTests: XCTestCase {
  func testActualSessionReadAndGeneralTickDoNotDeliverPaceCallback() throws {
    let clock = PaceCaretTestClock()
    var session = TypingSession(configuration: .words(100), prompt: "ab cd efg")
    session.configurePace(wpm: 300, clock: clock.source)
    session.insertBatch("a", at: .now)
    let request = try XCTUnwrap(session.paceCaretFrame())
    clock.time = 0.5
    XCTAssertEqual(session.paceCaretFrame(), request)
    XCTAssertFalse(session.tick())
    XCTAssertEqual(session.paceCaretFrame(), request)
    session.insertBatch("x ", at: .now)
    XCTAssertEqual(session.paceCaretFrame(), request, "A wrong word records correction without delivering a timer")
  }

  func testActualInputAndCallbackDeliveryAgainstPinnedRequests() throws {
    let scenarios = try WebsitePaceTimerStateTests.source().scenarios.filter { $0.rawWords == ["ab ", "cd ", "efg"] }
    XCTAssertEqual(scenarios.count, 8)
    for scenario in scenarios {
      let clock = PaceCaretTestClock()
      var session = TypingSession(configuration: .words(100), prompt: "ab cd efg")
      let wpm = scenario.speed == "Infinity" ? Double.infinity : try XCTUnwrap(Double(scenario.speed))
      session.configurePace(wpm: wpm, clock: clock.source)
      var committed = false
      for event in scenario.events.prefix(5) {
        clock.time = event.now / 1000
        switch event.kind {
        case "start": session.beginComposition(at: .now)
        case "deliver": session.deliverPaceCaretTimer(try XCTUnwrap(session.paceCaretPendingTicket))
        case "read":
          let before = session.paceCaretFrame()
          _ = session.tick()
          XCTAssertEqual(session.paceCaretFrame(), before, "Publishing status cannot deliver another callback")
        case "commit":
          if !committed { session.insertBatch("ax ", at: .now); committed = true }
        default: XCTFail("Unexpected source action")
        }
        let expected = try XCTUnwrap(event.request), frame = try XCTUnwrap(session.paceCaretFrame())
        XCTAssertEqual(frame.target, .init(word: expected.word, letter: expected.letter), scenario.speed)
        XCTAssertEqual(frame.stepDuration * 1000, expected.durationMilliseconds, accuracy: 1e-7, scenario.speed)
      }
      XCTAssertEqual(session.typed, "ax ")
    }
  }

  func testSessionCopyResetAndFinishedAttemptsRejectOldDeliveries() throws {
    let clock = PaceCaretTestClock()
    var session = TypingSession(configuration: .words(100), prompt: "ab cd efg")
    session.configurePace(wpm: 60, clock: clock.source)
    session.insertBatch("a", at: .now)
    let snapshot = session, ticket = try XCTUnwrap(session.paceCaretPendingTicket)
    clock.time = 0.225
    XCTAssertTrue(session.deliverPaceCaretTimer(ticket))
    XCTAssertEqual(session.paceCaretFrame()?.target, .init(word: 0, letter: 2))
    XCTAssertEqual(snapshot.paceCaretFrame()?.target, .init(word: 0, letter: 1))
    XCTAssertFalse(session.deliverPaceCaretTimer(ticket))
    XCTAssertEqual(try XCTUnwrap(session.paceCaretFrame()).stepDuration, 0.175, accuracy: 1e-8)
    let pending = try XCTUnwrap(session.paceCaretPendingTicket)
    session.configurePace(wpm: 120, clock: clock.source)
    XCTAssertFalse(session.deliverPaceCaretTimer(pending))
    XCTAssertNil(session.paceCaretPendingTicket)
    var repeatAttempt = snapshot.repeatedAttempt()
    repeatAttempt.configurePace(wpm: 60, clock: clock.source)
    repeatAttempt.insertBatch("a", at: .now)
    XCTAssertFalse(repeatAttempt.deliverPaceCaretTimer(ticket))
    repeatAttempt.abandon()
    XCTAssertNil(repeatAttempt.paceCaretPendingTicket)
    XCTAssertNil(repeatAttempt.paceCaretFrame())
  }
}
