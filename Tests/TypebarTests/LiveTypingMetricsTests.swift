import AppKit
import XCTest
@testable import Typebar

final class LiveTypingMetricsTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 100)

  private func snapshot(_ session: TypingSession, unit: TypingSpeedUnit = .wpm) -> LiveTypingMetrics {
    .init(session: session, at: start.addingTimeInterval(10), unit: unit)
  }

  func testLiveAccuracyFloorsInsteadOfRoundingToNearestPercent() {
    var session = TypingSession(configuration: .timed(seconds: 15), prompt: "🦊ab")
    session.insert("🦊x", at: start)
    XCTAssertEqual(snapshot(session).accuracy, "66%")
    XCTAssertEqual(session.preciseAccuracy, 200.0 / 3, accuracy: 0.000_001)
    XCTAssertEqual(session.accuracy, 67, "Legacy stored/wire integer remains unchanged")
  }

  func testNearPerfectLiveAccuracyDoesNotRoundToPerfect() {
    var session = TypingSession(configuration: .timed(seconds: 15, rules: .init(stopOnErrorMode: .letter)),
      prompt: String(repeating: "a", count: 249))
    session.insert("x", at: start)
    session.insert(String(repeating: "a", count: 249), at: start)
    XCTAssertEqual(session.preciseAccuracy, 99.6)
    XCTAssertEqual(session.accuracy, 100)
    XCTAssertEqual(snapshot(session).accuracy, "99%")
  }

  func testBlindLiveMetricsConcealErrorsWithoutChangingScoring() {
    var session = TypingSession(configuration: .timed(seconds: 15, rules: .init(blindMode: true)), prompt: "abc")
    session.insert("ax", at: start)
    XCTAssertEqual(snapshot(session).accuracy, "100%")
    XCTAssertEqual(snapshot(session).speed, snapshot(session).rawSpeed)
    XCTAssertEqual(snapshot(session).speed, "2")
    XCTAssertEqual(session.preciseAccuracy, 50)
    XCTAssertEqual(session.errors, 1)
    XCTAssertNil(snapshot(session).errorCount)
  }

  func testBlindRawSubstitutionHappensBeforeUnitConversion() {
    var session = TypingSession(configuration: .timed(seconds: 15, rules: .init(blindMode: true)), prompt: "🦊ab")
    session.insert("🦊x", at: start)
    for unit in TypingSpeedUnit.allCases {
      XCTAssertEqual(snapshot(session, unit: unit).speed,
        unit.formatted(wpm: session.rawWpm(at: start.addingTimeInterval(10))))
    }
    XCTAssertEqual(snapshot(session, unit: .cpm).speed, "20")
  }

  func testDeleteDoesNotRestoreAccuracyButCorrectionCountsAsNewAttempt() {
    var session = TypingSession(configuration: .timed(seconds: 15), prompt: "abc")
    session.insert("ax", at: start)
    session.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(snapshot(session).accuracy, "50%")
    session.insert("b", at: start.addingTimeInterval(2))
    XCTAssertEqual(snapshot(session).accuracy, "66%")
    XCTAssertEqual(session.errors, 0)
  }

  func testIdleAndZenRemainFullAccuracyWithoutInventingAttempts() {
    let idle = TypingSession(configuration: .words(2), prompt: "abc bay")
    XCTAssertEqual(snapshot(idle).accuracy, "100%")
    XCTAssertEqual(snapshot(idle).speed, "0")
    var zen = TypingSession(configuration: .init(mode: .zen, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init()), prompt: "")
    zen.insert("🦊x", at: start)
    XCTAssertEqual(snapshot(zen).accuracy, "100%")
    XCTAssertEqual(zen.preciseAccuracy, 100)
  }

  private func roundingBoundarySession(retainLastInput: Bool = false, minimumAccuracy: Double = 0) -> TypingSession {
    var session = TypingSession(configuration: .timed(seconds: 15,
      rules: .init(stopOnErrorMode: .letter, minimumAccuracy: minimumAccuracy)),
      prompt: "ab")
    for index in 0..<5_000 {
      session.insert("a", at: start)
      if !retainLastInput || index < 4_999 { session.deleteBackward(at: start) }
    }
    for _ in 0..<5_001 { session.insert("x", at: start) }
    return session
  }

  func testInputUpdateRoundsToHundredthsButRealSecondUsesUnroundedAccuracy() {
    var session = roundingBoundarySession()
    XCTAssertEqual(session.preciseAccuracy, 500_000.0 / 10_001, accuracy: 0.000_001)
    XCTAssertEqual(snapshot(session).accuracy, "50%", "Input publishes two decimals before flooring")
    session.enforceLivePracticeThresholds(at: start.addingTimeInterval(1))
    XCTAssertEqual(snapshot(session).accuracy, "49%", "The real timer publishes unrounded cache accuracy")
    session.beginComposition(at: start.addingTimeInterval(1.1))
    XCTAssertEqual(snapshot(session).accuracy, "50%", "Candidate UI refresh rounds, without counting marked text")
    XCTAssertEqual(session.preciseAccuracy, 500_000.0 / 10_001, accuracy: 0.000_001)
  }

  func testCandidateContinuationRefreshesDisplayWithoutAttemptsOrReplay() throws {
    var session = roundingBoundarySession()
    session.beginComposition(at: start.addingTimeInterval(0.5))
    session.enforceLivePracticeThresholds(at: start.addingTimeInterval(1))
    XCTAssertEqual(snapshot(session).accuracy, "49%")
    session.refreshLiveAccuracyAfterComposition(hadMarkedText: true, hasMarkedText: true)
    XCTAssertEqual(snapshot(session).accuracy, "50%")
    XCTAssertTrue(session.typed.isEmpty)
    XCTAssertEqual(session.preciseAccuracy, 500_000.0 / 10_001, accuracy: 0.000_001)
    session.bailOut(at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.inputMetrics?.correctAttempts, 5_000)
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 10_001)
    XCTAssertEqual(result.replayEvents.count, 10_000)
    XCTAssertEqual(result.preciseAccuracy, 50)
  }

  func testRejectedPreInputAndEmptyDeleteDoNotOverrideTimerDisplay() {
    var session = roundingBoundarySession()
    session.enforceLivePracticeThresholds(at: start.addingTimeInterval(1))
    session.insert("\n", at: start.addingTimeInterval(1.1))
    session.deleteBackward(at: start.addingTimeInterval(1.2))
    session.deleteWordBackward(at: start.addingTimeInterval(1.3))
    session.tick(at: start.addingTimeInterval(1.4))
    XCTAssertEqual(snapshot(session).accuracy, "49%")
    XCTAssertEqual(session.preciseAccuracy, 500_000.0 / 10_001, accuracy: 0.000_001)
  }

  func testAcceptedCharacterAndWordDeletionRefreshAccuracyWithoutCorrectingHistory() {
    for deletesWord in [false, true] {
      var session = roundingBoundarySession(retainLastInput: true)
      session.enforceLivePracticeThresholds(at: start.addingTimeInterval(1))
      XCTAssertEqual(snapshot(session).accuracy, "49%")
      if deletesWord { session.deleteWordBackward(at: start.addingTimeInterval(1.1)) }
      else { session.deleteBackward(at: start.addingTimeInterval(1.1)) }
      XCTAssertEqual(snapshot(session).accuracy, "50%")
      XCTAssertTrue(session.typed.isEmpty)
      XCTAssertEqual(session.preciseAccuracy, 500_000.0 / 10_001, accuracy: 0.000_001)
    }
  }

  func testRoundedLiveDisplayCannotPreventMinimumAccuracyFailure() throws {
    var session = roundingBoundarySession(minimumAccuracy: 49.997)
    XCTAssertEqual(snapshot(session).accuracy, "50%")
    session.enforceLivePracticeThresholds(at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .failed)
    XCTAssertEqual(session.failureReason, .minimumAccuracy)
    XCTAssertEqual(try XCTUnwrap(session.result()).preciseAccuracy, 50)
  }

  func testRuntimeBlindToggleOnlyChangesPresentationAndCanBeReversed() {
    var session = TypingSession(configuration: .timed(seconds: 15), prompt: "🦊ab")
    session.insert("🦊x", at: start)
    let masked = LiveTypingMetrics(session: session, at: start.addingTimeInterval(10), blindMode: true, unit: .cpm)
    XCTAssertEqual(masked.accuracy, "100%")
    XCTAssertEqual(masked.speed, masked.rawSpeed)
    XCTAssertNil(masked.errorCount)
    let restored = LiveTypingMetrics(session: session, at: start.addingTimeInterval(10), blindMode: false, unit: .cpm)
    XCTAssertEqual(restored.accuracy, "66%")
    XCTAssertEqual(restored.speed, "0")
    XCTAssertEqual(restored.errorCount, 1)
    XCTAssertEqual(session.typed, "🦊x")
    XCTAssertEqual(session.preciseAccuracy, 200.0 / 3, accuracy: 0.000_001)
    XCTAssertFalse(session.configuration.rules.blindMode)
  }

  @MainActor
  func testNativeMarkedTextRefreshAfterTimerDoesNotEnterScoringOrReplay() throws {
    var session = roundingBoundarySession()
    let input = TypingInputView(frame: .zero)
    var now = start.addingTimeInterval(0.5)
    var hasMarkedText = false
    input.onCompositionStarted = { session.beginComposition(at: now) }
    input.onCompositionChanged = { text in
      let hadMarkedText = hasMarkedText
      hasMarkedText = !text.isEmpty
      session.refreshLiveAccuracyAfterComposition(hadMarkedText: hadMarkedText, hasMarkedText: hasMarkedText)
    }
    input.onInsert = { text, forced in session.insertBatch(text, forceError: forced, at: now) }
    input.setMarkedText("候", selectedRange: .init(), replacementRange: .init())
    XCTAssertTrue(input.hasMarkedText())
    XCTAssertEqual(snapshot(session).accuracy, "50%")
    now = start.addingTimeInterval(1)
    session.enforceLivePracticeThresholds(at: now)
    XCTAssertEqual(snapshot(session).accuracy, "49%")
    input.setMarkedText("候选", selectedRange: .init(), replacementRange: .init())
    XCTAssertTrue(input.hasMarkedText())
    XCTAssertEqual(snapshot(session).accuracy, "50%")
    XCTAssertTrue(session.typed.isEmpty)
    input.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
    XCTAssertFalse(input.hasMarkedText())
    session.bailOut(at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 10_001)
    XCTAssertEqual(result.replayEvents.count, 10_000)
    XCTAssertFalse(result.replayEvents.contains { $0.text.contains("候") })
    XCTAssertEqual(result.preciseAccuracy, 50)
  }

  @MainActor
  func testOrdinaryRejectedTextCallbackDoesNotPretendToBeCompositionUpdate() {
    var session = roundingBoundarySession()
    session.enforceLivePracticeThresholds(at: start.addingTimeInterval(1))
    let input = TypingInputView(frame: .zero)
    input.onCompositionChanged = { text in
      session.refreshLiveAccuracyAfterComposition(hadMarkedText: false, hasMarkedText: !text.isEmpty)
    }
    input.onInsert = { text, forced in session.insertBatch(text, forceError: forced, at: self.start) }
    input.insertText("\n", replacementRange: .init())
    XCTAssertFalse(input.hasMarkedText())
    XCTAssertEqual(snapshot(session).accuracy, "49%")
    XCTAssertEqual(session.preciseAccuracy, 500_000.0 / 10_001, accuracy: 0.000_001)
  }
}
