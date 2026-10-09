import XCTest
@testable import Typebar

final class TimerDeliveryDiagnosticsTests: XCTestCase {
  func testPhaseRecordsUseFixedLabelsAndOnlyRelativeTimeAndState() {
    for phase in TimerDeliveryDiagnostics.Phase.allCases {
      XCTAssertEqual(TimerDeliveryDiagnostics.phaseRecord(phase: phase, offset: 12.345,
        duration: 0.03, hasStarted: true, isFinished: false),
        "typebar-phase phase=\(phase.rawValue) offset=12.345000 duration=0.030000 started=1 finished=0\n")
    }
    XCTAssertEqual(TimerDeliveryDiagnostics.phaseRecord(phase: .clockStopped, offset: 0,
      duration: 0, hasStarted: false, isFinished: true),
      "typebar-phase phase=clock-stopped offset=0.000000 duration=0.000000 started=0 finished=1\n")
  }

  func testPhaseWriterUsesExistingDoubleOptInBeforeSamplingOrWriting() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TimerDeliveryDiagnostics.swift"), encoding: .utf8)
    let begin = try XCTUnwrap(source.range(of: "static func trace("))
    let writer = String(source[begin.lowerBound...])
    let guardRange = try XCTUnwrap(writer.range(of: "guard enabled else { return }"))
    XCTAssertLessThan(guardRange.lowerBound,
      try XCTUnwrap(writer.range(of: "ProcessInfo.processInfo.systemUptime")).lowerBound)
    XCTAssertLessThan(guardRange.lowerBound,
      try XCTUnwrap(writer.range(of: "FileHandle.standardError.write")).lowerBound)
    XCTAssertTrue(source.contains("enum Phase: String, CaseIterable"))
  }

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
