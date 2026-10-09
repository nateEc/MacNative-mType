import XCTest
@testable import Typebar

final class TimerDeliveryDiagnosticsTests: XCTestCase {
  func testProductionClockRejectsTerminalSessionBeforeTimingAndDeliveryEffects() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    let begin = try XCTUnwrap(source.range(of: "private func advanceClock(at now:"))
    let end = try XCTUnwrap(source.range(of: "private var header:", range: begin.upperBound..<source.endIndex))
    let entry = String(source[begin.lowerBound..<end.lowerBound])
    let gate = try XCTUnwrap(entry.range(of: "guard !session.isFinished else { return }"))
    for operation in ["let elapsed =", "timerHealth.observe(", "TimerDeliveryDiagnostics.record(",
      "TypingFeedbackSound.shared.playTimeWarning(", "session.enforceLivePracticeThresholds(", "session.tick("] {
      XCTAssertLessThan(gate.lowerBound, try XCTUnwrap(entry.range(of: operation)).lowerBound)
    }
    // Native Caps Lock / live-rule / font monitoring must still run, including
    // while a terminal result is visible. Only attempt delivery is gated.
    XCTAssertLessThan(try XCTUnwrap(entry.range(of: "verifyChallengeFontAvailability()")).lowerBound,
      gate.lowerBound)
  }

  func testRequiresBothQAStoreAndExplicitOptIn() {
    for qa in [false, true] {
      for flag in [nil, "0", "1", "true"] as [String?] {
        let environment = flag.map { ["TYPEBAR_QA_TIMER_DIAGNOSTICS": $0] } ?? [:]
        XCTAssertEqual(TimerDeliveryDiagnostics.isEnabled(
          info: [QAStoreMode.inMemoryInfoKey: qa], environment: environment), qa && flag == "1")
      }
    }
    XCTAssertFalse(TimerDeliveryDiagnostics.isEnabled(info: [:],
      environment: ["TYPEBAR_QA_TIMER_DIAGNOSTICS": "1"]))
  }

  func testFixedNumericRecordDistinguishesDeliveryAndPreflightWithoutInputData() {
    XCTAssertEqual(TimerDeliveryDiagnostics.record(deliveryGap: 1.7, preflight: 0.03,
      elapsed: 2.65, previousSecond: 1, firstDueSecond: 2, severeCount: 1, failed: true),
      "typebar-timer deliveryGap=1.700000 preflight=0.030000 elapsed=2.650000 previous=1 due=2 drift=0.650000 severe=1 failed=1\n")
  }
}
