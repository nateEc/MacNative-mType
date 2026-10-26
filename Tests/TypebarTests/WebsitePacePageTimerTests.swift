import Foundation
import Observation
import XCTest
@testable import Typebar

@MainActor final class WebsitePacePageTimerTests: XCTestCase {
  final class Changes: @unchecked Sendable { var count = 0 }

  private func withSettings(_ body: (AppSettings) throws -> Void) throws {
    let suite = "typebar.pace-style-timer.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(AppSettings(defaults: defaults,
      feedbackSound: .init(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory()))
  }

  func testBoundStyleIsReadBeforeFirstInputWithoutWaitingForViewOnChange() throws {
    try withSettings { settings in
      let page = PracticePageSessionStore(), router = PreferenceConfigurationSaveRouter()
      page.attach(to: router); page.bindPaceStyleSettings(settings); defer { page.detach() }
      var state = page.state
      state.session = TypingSession(configuration: .words(100), prompt: "ab cd efg")
      state.session.configurePace(wpm: 300)
      page.replace(state)
      settings.paceCaretStyle = .off
      state = page.state; state.session.insertBatch("a", at: .now); page.replace(state)
      XCTAssertNotNil(page.state.session.paceCaretFrame())
      XCTAssertNil(page.state.session.paceCaretPresentationFrame())
      XCTAssertTrue(page.state.session.paceCaretIsVisible)
      settings.paceCaretStyle = .bar
      XCTAssertNil(page.state.session.paceCaretPresentationFrame(), "Showing cannot admit an earlier ignored request")
    }
  }

  func testActualTimerReadsTheBoundStyleAtDeliveryWithoutViewPublication() throws {
    try withSettings { settings in
      settings.paceCaretStyle = .bar
      let page = PracticePageSessionStore(), router = PreferenceConfigurationSaveRouter(), clock = PaceCaretTestClock()
      page.attach(to: router); page.bindPaceStyleSettings(settings); defer { page.detach() }
      var state = page.state
      state.session = TypingSession(configuration: .words(100), prompt: "ab cd efg")
      state.session.configurePace(wpm: 300, clock: clock.source)
      state.session.insertBatch("a", at: .now); page.replace(state)
      XCTAssertEqual(page.state.session.paceCaretPresentationFrame()?.sequence, 1)
      @MainActor func waitForSequence(_ sequence: Double) {
        let deadline = Date().addingTimeInterval(1)
        while (page.state.session.paceCaretFrame()?.sequence ?? 0) < sequence, Date() < deadline {
          RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        XCTAssertGreaterThanOrEqual(page.state.session.paceCaretFrame()?.sequence ?? 0, sequence)
      }
      settings.paceCaretStyle = .off; clock.time = 0.04
      waitForSequence(2)
      XCTAssertEqual(page.state.session.paceCaretPresentationFrame()?.sequence, 1)
      settings.paceCaretStyle = .bar
      XCTAssertEqual(page.state.session.paceCaretPresentationFrame()?.sequence, 1)
      clock.time = 0.08; waitForSequence(3)
      XCTAssertGreaterThanOrEqual(page.state.session.paceCaretPresentationFrame()?.sequence ?? 0, 3)
    }
  }

  func testActualTimerAdvancesWithoutPublishingEveryPaceRequest() throws {
    let router = PreferenceConfigurationSaveRouter(), page = PracticePageSessionStore()
    page.attach(to: router); defer { page.detach() }
    let clock = PaceCaretTestClock()
    var state = page.state
    state.session = TypingSession(configuration: .words(100), prompt: "ab cd efg")
    state.session.configurePace(wpm: 300, clock: clock.source)
    state.session.insertBatch("a", at: .now)
    page.replace(state)
    XCTAssertEqual(try XCTUnwrap(page.scheduledPaceTimerInterval), 0.04, accuracy: 1e-8)
    let changes = Changes()
    withObservationTracking { _ = page.state } onChange: {
      MainActor.assumeIsolated { changes.count += 1 }
    }
    clock.time = 0.04
    let limit = Date().addingTimeInterval(1)
    while page.state.session.paceCaretFrame()?.sequence == 1, Date() < limit {
      RunLoop.main.run(until: Date().addingTimeInterval(0.005))
    }
    XCTAssertGreaterThan(try XCTUnwrap(page.state.session.paceCaretFrame()).sequence, 1)
    XCTAssertEqual(changes.count, 0, "A 4ms pace loop must not invalidate the whole SwiftUI page")
    var input = page.state
    input.session.insertBatch("b", at: .now)
    page.replace(input)
    XCTAssertEqual(changes.count, 1, "Input and publication changes remain observable")
    page.detach()
    let detached = page.state.session.paceCaretFrame()
    XCTAssertNil(page.scheduledPaceTimerInterval)
    clock.time = 10
    RunLoop.main.run(until: Date().addingTimeInterval(0.06))
    XCTAssertEqual(page.state.session.paceCaretFrame(), detached)
  }

  func testReconfigurationAndCompletionCancelThePreviousTimer() throws {
    let page = PracticePageSessionStore(), router = PreferenceConfigurationSaveRouter()
    page.attach(to: router); defer { page.detach() }
    var state = page.state
    state.session = TypingSession(configuration: .words(100), prompt: "ab cd efg")
    state.session.configurePace(wpm: 300)
    state.session.insertBatch("a", at: .now)
    page.replace(state)
    XCTAssertNotNil(page.scheduledPaceTimerInterval)
    state = page.state
    state.session.configurePace(wpm: 120)
    page.replace(state)
    XCTAssertNil(page.scheduledPaceTimerInterval)
    XCTAssertNil(page.state.session.paceCaretFrame())
    state.session = state.session.repeatedAttempt()
    state.session.configurePace(wpm: 60)
    state.session.insertBatch("a", at: .now)
    page.replace(state)
    XCTAssertNotNil(page.scheduledPaceTimerInterval)
    state = page.state
    state.session.abandon()
    page.replace(state)
    XCTAssertNil(page.scheduledPaceTimerInterval)
  }

  func testChainedZeroDelayUsesTheDocumentedNestedTimerMinimum() throws {
    let clock = PaceCaretTestClock()
    var session = TypingSession(configuration: .words(100), prompt: String(repeating: "ab ", count: 20))
    session.configurePace(wpm: .infinity, clock: clock.source)
    session.insertBatch("a", at: .now)
    for sequence in 1...7 {
      XCTAssertEqual(session.paceCaretFrame()?.sequence, Double(sequence))
      XCTAssertEqual(try XCTUnwrap(session.paceCaretPendingDelay), sequence <= 6 ? 0 : 0.004, accuracy: 1e-9)
      if sequence < 7 { session.deliverPaceCaretTimer(try XCTUnwrap(session.paceCaretPendingTicket)) }
    }
    clock.time = 0.003
    XCTAssertEqual(try XCTUnwrap(session.paceCaretPendingDelay), 0.001, accuracy: 1e-9)
  }

  func testFractionalTimeoutConversionDoesNotChangeTheFrozenAnimationDuration() throws {
    let clock = PaceCaretTestClock()
    var session = TypingSession(configuration: .words(100), prompt: "ab cd efg")
    session.configurePace(wpm: 59.123456789, clock: clock.source)
    session.insertBatch("a", at: .now)
    let request = try XCTUnwrap(session.paceCaretFrame())
    XCTAssertEqual(try XCTUnwrap(session.paceCaretPendingDelay), floor(request.stepDuration * 1000) / 1000, accuracy: 1e-9)
    clock.time = 0.001
    XCTAssertEqual(session.paceCaretFrame(), request)
    XCTAssertEqual(try XCTUnwrap(session.paceCaretPendingDelay), (floor(request.stepDuration * 1000) - 1) / 1000, accuracy: 1e-9)
  }
}
