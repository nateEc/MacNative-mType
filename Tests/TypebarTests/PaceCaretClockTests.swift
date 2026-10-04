import XCTest
@testable import Typebar

final class PaceCaretClockTests: XCTestCase {
  private let date = Date(timeIntervalSince1970: 1_800_000_000)

  func testWallClockJumpDoesNotExhaustTheLivePace() throws {
    let clock = PaceCaretTestClock()
    var session = TypingSession(configuration: .words(100), prompt: "ab cd efg")
    session.configurePace(wpm: 60, clock: clock.source)
    session.beginComposition(at: date)
    let initial = try XCTUnwrap(session.paceCaretFrame())
    clock.time = 0.1
    session.tick(at: date.addingTimeInterval(3_600))
    let jumped = try XCTUnwrap(session.paceCaretFrame())
    XCTAssertEqual(jumped.target, initial.target)
    XCTAssertEqual(jumped.fraction, 0.5, accuracy: 1e-8)
  }

  func testForwardDatedCommitDoesNotConsumeWallClockHoursOfPace() throws {
    let clock = PaceCaretTestClock()
    var session = TypingSession(configuration: .words(100), prompt: "ab cd efg")
    session.configurePace(wpm: 60, clock: clock.source)
    session.insertBatch("a", at: date)
    clock.time = 0.1
    session.insertBatch("b ", at: date.addingTimeInterval(3_600))
    XCTAssertEqual(session.typed, "ab ")
    let frame = try XCTUnwrap(session.paceCaretFrame())
    XCTAssertEqual(frame.target, .init(word: 0, letter: 1))
    XCTAssertEqual(frame.fraction, 0.5, accuracy: 1e-8)
  }
  func testBackwardWallClockDoesNotFreezeAdvancingPace() throws {
    let clock = PaceCaretTestClock()
    var session = TypingSession(configuration: .words(100), prompt: "ab cd efg")
    session.configurePace(wpm: 60, clock: clock.source)
    session.beginComposition(at: date)
    clock.time = 0.2
    session.tick(at: date.addingTimeInterval(-3_600))
    XCTAssertEqual(session.paceCaretFrame()?.target, .init(word: 0, letter: 2))
    clock.time = 0.3
    XCTAssertEqual(try XCTUnwrap(session.paceCaretFrame()).fraction, 0.5, accuracy: 1e-8)
  }

  func testClockOriginIsFirstAcceptedInputNotConfigurationTime() throws {
    let clock = PaceCaretTestClock()
    var session = TypingSession(configuration: .words(100), prompt: "ab cd efg")
    session.configurePace(wpm: 60, clock: clock.source)
    clock.time = 500
    session.insertBatch(" ", at: date)
    XCTAssertNil(session.paceCaretFrame())
    clock.time = 600
    session.insertBatch("a", at: date)
    let first = try XCTUnwrap(session.paceCaretFrame())
    XCTAssertEqual(first.target, .init(word: 0, letter: 1))
    XCTAssertEqual(first.fraction, 0)
    clock.time = 600.1
    XCTAssertEqual(try XCTUnwrap(session.paceCaretFrame()).fraction, 0.5, accuracy: 1e-8)
  }

  func testWrongCommitUsesClockDeadlineAndBlindRetainsPendingCorrection() {
    let clock = PaceCaretTestClock()
    var session = TypingSession(configuration: .words(100), prompt: "ab cd efg")
    session.configurePace(wpm: 60, clock: clock.source)
    session.insertBatch("ax ", at: date)
    var rules = session.configuration.rules
    rules.blindMode = true
    session.synchronizeLiveInputRules(rules)
    clock.time = 0.2
    session.tick(at: date.addingTimeInterval(3_600))
    XCTAssertEqual(session.paceCaretFrame()?.target, .init(word: 0, letter: 2))
    rules.blindMode = false
    session.synchronizeLiveInputRules(rules)
    clock.time = 0.4
    session.tick(at: date.addingTimeInterval(-3_600))
    XCTAssertEqual(session.paceCaretFrame()?.target, .init(word: 2, letter: 0))
  }

  func testResetAndRepeatUseNewClockWithoutRestartingTheActiveAttempt() {
    let old = PaceCaretTestClock(), fresh = PaceCaretTestClock()
    var session = TypingSession(configuration: .words(100), prompt: "ab cd efg")
    session.configurePace(wpm: 60, clock: old.source)
    session.insertBatch("a", at: date)
    old.time = 0.2
    XCTAssertEqual(session.paceCaretFrame()?.target, .init(word: 0, letter: 2))
    session.configurePace(wpm: 60, clock: fresh.source)
    fresh.time = 9_999
    old.time = 99_999
    session.tick(at: date)
    XCTAssertNil(session.paceCaretFrame())
    var repeated = session.repeatedAttempt()
    repeated.configurePace(wpm: 60, clock: fresh.source)
    repeated.insertBatch("a", at: date)
    XCTAssertEqual(repeated.paceCaretFrame()?.target, .init(word: 0, letter: 1))
  }

  func testClockSamplesAreNotAddedToSavedResultsOrReplay() throws {
    let clock = PaceCaretTestClock()
    var ordinary = TypingSession(configuration: .words(100), prompt: "ab cd efg")
    var paced = ordinary
    paced.configurePace(wpm: 60, clock: clock.source)
    ordinary.insertBatch("ab ", at: date)
    paced.insertBatch("ab ", at: date)
    clock.time = 123
    paced.tick(at: date.addingTimeInterval(1))
    ordinary.bailOut(at: date.addingTimeInterval(15))
    paced.bailOut(at: date.addingTimeInterval(15))
    let old = try XCTUnwrap(ordinary.result()), new = try XCTUnwrap(paced.result())
    XCTAssertEqual(new.startedAt, old.startedAt)
    XCTAssertEqual(new.finishedAt, old.finishedAt)
    XCTAssertEqual(new.replayEvents, old.replayEvents)
    XCTAssertEqual(new.characterStats, old.characterStats)
    XCTAssertEqual(new.preciseWpm, old.preciseWpm)
    XCTAssertEqual(new.preciseAccuracy, old.preciseAccuracy)
  }

  func testInvalidSampleDoesNotPoisonStartOrTheLastConsumedStep() throws {
    let clock = PaceCaretTestClock()
    var value = PaceCaretProgress(wpm: 60, catalog: .init(prompt: "ab cd efg"), clock: clock.source)!
    clock.time = .nan
    value.start(blind: false)
    XCTAssertNil(value.frame(blind: false))
    clock.time = 0
    value.start(blind: false)
    clock.time = 0.2
    value.advance(blind: false)
    for invalid in [Double.nan, .infinity, -.infinity] {
      clock.time = invalid
      let frame = try XCTUnwrap(value.frame(blind: false))
      XCTAssertEqual(frame.target, .init(word: 0, letter: 2))
      XCTAssertTrue(frame.fraction.isFinite)
    }
    clock.time = 0.4
    XCTAssertEqual(value.frame(blind: false)?.target, .init(word: 1, letter: 0))
  }

  func testRegressingInjectedClockCannotRewindConsumedSteps() {
    let clock = PaceCaretTestClock()
    var value = PaceCaretProgress(wpm: 60, catalog: .init(prompt: "ab cd efg"), clock: clock.source)!
    value.start(blind: false)
    clock.time = 0.4
    value.advance(blind: false)
    clock.time = 0.1
    XCTAssertEqual(value.frame(blind: false)?.target, .init(word: 1, letter: 0))
  }

  func testDisablingPaceReleasesTheOwnedClock() {
    var owned: PaceCaretTestClock? = PaceCaretTestClock()
    weak var weakClock = owned
    var session = TypingSession(configuration: .words(100), prompt: "ab cd efg")
    session.configurePace(wpm: 60, clock: owned!.source)
    owned = nil
    XCTAssertNotNil(weakClock)
    session.configurePace(wpm: nil)
    XCTAssertNil(weakClock)
  }

  func testSystemClockProducesFiniteNondecreasingLocalSamples() {
    let clock = PaceCaretClock.system
    var previous = clock.now()
    XCTAssertTrue(previous.isFinite)
    XCTAssertGreaterThanOrEqual(previous, 0)
    for _ in 0..<100 {
      let next = clock.now()
      XCTAssertTrue(next.isFinite)
      XCTAssertGreaterThanOrEqual(next, previous)
      previous = next
    }
  }

  func testDefaultSessionClockDoesNotUseTheEventDateAsItsOrigin() throws {
    var session = TypingSession(configuration: .words(100), prompt: "ab cd efg")
    session.configurePace(wpm: 1)
    session.beginComposition(at: Date(timeIntervalSince1970: 0))
    let frame = try XCTUnwrap(session.paceCaretFrame())
    XCTAssertEqual(session.startedAt, Date(timeIntervalSince1970: 0))
    XCTAssertEqual(frame.target, .init(word: 0, letter: 1))
    XCTAssertTrue(frame.fraction.isFinite)
    XCTAssertGreaterThanOrEqual(frame.fraction, 0)
  }
}
