import XCTest
@testable import Typebar

final class ResultFinishPriorityTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_800_000_000)

  private func result(outcome: TestOutcome = .completed,
    configuration: TestConfiguration = .timed(seconds: 15), seconds: Double = 15,
    calendarSeconds: Double? = nil, measured: Bool = true, wpm: Double = 60,
    raw: Double = 60, accuracy: Double = 100) -> CompletedTestResult {
    .init(id: UUID(), configuration: configuration, outcome: outcome, startedAt: start,
      finishedAt: start.addingTimeInterval(calendarSeconds ?? seconds),
      elapsedTime: measured ? .init(seconds: seconds) : nil,
      typedCharacterCount: 75, correctCharacterCount: 75, errorCount: 0,
      wpm: Int(wpm), rawWpm: Int(raw), accuracy: Int(accuracy),
      preciseWpm: wpm, preciseRawWpm: raw, preciseAccuracy: accuracy)
  }

  private func assessment(_ value: CompletedTestResult, repeated: Bool = false) -> ResultEligibility {
    ResultEligibilityPolicy.assessment(for: value, samePromptRepeat: repeated)
  }

  func testDateMismatchPrecedesFailureAndOtherQualifications() {
    for outcome in [TestOutcome.completed, .failed, .invalidAFK] {
      let value = result(outcome: outcome, configuration: .timed(seconds: 10), seconds: 10,
        calendarSeconds: -3_600, wpm: 500, raw: 500, accuracy: 50)
      XCTAssertEqual(assessment(value, repeated: true), .ineligible(.inconsistentDuration))
      XCTAssertFalse(ResultSavingPolicy.shouldPersist(outcome: outcome, enabled: true,
        eligibility: assessment(value, repeated: true)))
    }
  }

  func testActualTimedIdleSessionReportsCalendarMismatchFirst() throws {
    var seconds = 0.0
    var session = TypingSession(configuration: .timed(seconds: 15), prompt: "a b")
      .withElapsedClock(.init { seconds })
    session.insert("a", at: start)
    seconds = 15; session.tick(at: start.addingTimeInterval(-3_600))
    XCTAssertEqual(session.outcome, .invalidAFK)
    let value = try XCTUnwrap(session.result())
    XCTAssertEqual(assessment(value, repeated: true), .ineligible(.inconsistentDuration))
    XCTAssertEqual(value.outcome, .invalidAFK, "Qualification does not rewrite the captured outcome")
    XCTAssertEqual(value.elapsedTime?.seconds, 15)
  }

  func testActualTimerFailureReportsCalendarMismatchBeforeFailure() throws {
    var seconds = 0.0
    var session = TypingSession(configuration: .timed(seconds: 15), prompt: "a b")
      .withElapsedClock(.init { seconds })
    session.insert("a", at: start)
    seconds = 10; session.failForTimerHealth(at: start.addingTimeInterval(3_600))
    let value = try XCTUnwrap(session.result())
    XCTAssertEqual(value.outcome, .failed)
    XCTAssertEqual(session.failureReason, .timerHealth)
    XCTAssertEqual(assessment(value), .ineligible(.inconsistentDuration))
  }

  func testFailurePrecedesShortRepeatSpeedAndAccuracyChecks() {
    for configuration in [TestConfiguration.timed(seconds: 10), .words(9),
      .init(mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init())] {
      let value = result(outcome: .failed, configuration: configuration, seconds: 0.5,
        wpm: 500, raw: 500, accuracy: 50)
      guard case .ineligible(let reason) = assessment(value, repeated: true) else {
        return XCTFail("A failed test must be rejected at the failure branch")
      }
      XCTAssertEqual(reason.resultSummary, "本次测试失败")
    }
  }

  func testTooShortPrecedesIdleAndRepeatedQualifications() {
    for configuration in [TestConfiguration.timed(seconds: 10), .words(9),
      .init(mode: .zen, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init())] {
      let value = result(outcome: .invalidAFK, configuration: configuration, seconds: 10,
        wpm: 500, raw: 500, accuracy: 50)
      XCTAssertEqual(assessment(value, repeated: true), .ineligible(.tooShort))
    }
  }

  func testIdlePrecedesRepeatSpeedAndAccuracyChecks() {
    let value = result(outcome: .invalidAFK, wpm: 500, raw: 500, accuracy: 50)
    guard case .ineligible(let reason) = assessment(value, repeated: true) else {
      return XCTFail("Idle must remain an explicit qualification failure")
    }
    XCTAssertEqual(reason.resultSummary, "结束前持续闲置")
  }

  func testRepeatPrecedesSpeedAndSpeedPrecedesRawAndAccuracy() {
    let value = result(wpm: 500, raw: 500, accuracy: 50)
    XCTAssertEqual(assessment(value, repeated: true), .ineligible(.samePromptRepeat))
    XCTAssertEqual(assessment(value), .ineligible(.typingSpeed))
    XCTAssertEqual(assessment(result(wpm: 60, raw: 500, accuracy: 50)), .ineligible(.rawTypingSpeed))
    XCTAssertEqual(assessment(result(accuracy: 50)), .ineligible(.accuracy))
  }

  func testBailoutStillSkipsDateAndIdleButNotOtherQualifications() {
    let value = result(outcome: .bailedOut, calendarSeconds: -3_600)
    XCTAssertEqual(assessment(value), .eligible)
    XCTAssertTrue(ResultSavingPolicy.shouldPersist(outcome: value.outcome, enabled: true,
      eligibility: assessment(value)))
    XCTAssertEqual(assessment(value, repeated: true), .ineligible(.samePromptRepeat))
    XCTAssertEqual(assessment(result(outcome: .bailedOut, seconds: 0.5, calendarSeconds: 3_600)),
      .ineligible(.tooShort))
  }

  func testLongTimedAndNonTimedFailuresDoNotUseDateMismatchBranch() {
    for configuration in [TestConfiguration.timed(seconds: 150), .words(10),
      .init(mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init())] {
      let value = result(outcome: .failed, configuration: configuration, seconds: 150,
        calendarSeconds: -3_600)
      guard case .ineligible(let reason) = assessment(value) else {
        return XCTFail("A failed terminal result cannot be eligible")
      }
      XCTAssertEqual(reason.resultSummary, "本次测试失败")
    }
  }

  func testFailedAndRepeatedIdleAttemptsStillCarryPracticeRegardlessOfPrimaryReason() {
    for (outcome, repeated) in [(TestOutcome.failed, false), (.failed, true), (.invalidAFK, true)] {
      var ledger = PriorAttemptLedger()
      let value = result(outcome: outcome, calendarSeconds: -3_600)
      ledger.recordTerminalAttempt(engagedDuration: 4.5, outcome: outcome,
        eligibility: assessment(value, repeated: repeated), savingEnabled: true,
        samePromptRepeat: repeated)
      XCTAssertEqual(ledger.restartCount, 1)
      XCTAssertEqual(ledger.priorAttemptEngagedDuration, 4.5)
    }
    for saving in [false, true] {
      var ledger = PriorAttemptLedger()
      ledger.recordTerminalAttempt(engagedDuration: 4.5, outcome: .invalidAFK,
        eligibility: assessment(result(outcome: .invalidAFK)), savingEnabled: saving)
      XCTAssertEqual(ledger.restartCount, 0, "Non-repeated idle results do not carry incomplete practice")
    }
  }

  func testLegacyDateOnlyResultIsNotRetrofittedWithCalendarQualificationOrNewData() throws {
    let value = result(configuration: .timed(seconds: 15), seconds: 15,
      calendarSeconds: 16.125, measured: false)
    let encoded = try JSONEncoder().encode(value)
    XCTAssertEqual(assessment(value), .eligible)
    let restored = try JSONDecoder().decode(CompletedTestResult.self, from: encoded)
    XCTAssertEqual(restored, value)
    XCTAssertNil(restored.elapsedTime)
    XCTAssertEqual(restored.elapsedDuration, 16.125)
    XCTAssertEqual(restored.preciseWpm, 60)
  }

  func testFailureAndInvalidityRemainDistinctForResultFeedback() {
    XCTAssertNil(assessment(result(outcome: .failed)).invalidReason)
    XCTAssertFalse(assessment(result(outcome: .failed)).isEligible)
    for outcome in [TestOutcome.completed, .failed, .invalidAFK] {
      let value = result(outcome: outcome, calendarSeconds: -3_600)
      XCTAssertEqual(assessment(value).invalidReason, .inconsistentDuration)
      XCTAssertEqual(outcome.statusText(saveState: .notRequested, eligibility: assessment(value)),
        "本次结果无效（测试时长与日期不一致） · 未保存为完成成绩")
    }
    XCTAssertEqual(TestOutcome.failed.statusText(saveState: .notRequested,
      eligibility: assessment(result(outcome: .failed))), "本次失败 · 未保存为完成成绩")
    XCTAssertEqual(TestOutcome.invalidAFK.statusText(saveState: .notRequested,
      eligibility: assessment(result(outcome: .invalidAFK))), "本次因闲置无效 · 未保存为完成成绩")
  }

  func testRepeatedIdleCarryIsDisabledWhenResultSavingIsOff() {
    var ledger = PriorAttemptLedger()
    ledger.recordTerminalAttempt(engagedDuration: 4.5, outcome: .invalidAFK,
      eligibility: assessment(result(outcome: .invalidAFK), repeated: true), savingEnabled: false,
      samePromptRepeat: true)
    XCTAssertEqual(ledger, .init())
    ledger.recordTerminalAttempt(engagedDuration: 4.5, outcome: .invalidAFK,
      eligibility: assessment(result(outcome: .invalidAFK), repeated: true), savingEnabled: true,
      samePromptRepeat: true)
    ledger.clearAfterPersistingResult()
    XCTAssertEqual(ledger, .init())
  }

  func testQuoteRepeatExceptionDoesNotOverrideEarlierInvalidityOrFailure() {
    let quote = TestConfiguration(mode: .quote, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init())
    XCTAssertEqual(assessment(result(configuration: quote), repeated: true), .eligible)
    XCTAssertEqual(assessment(result(outcome: .invalidAFK, configuration: quote), repeated: true).invalidReason,
      .inactivity)
    XCTAssertEqual(assessment(result(outcome: .failed, configuration: quote), repeated: true),
      .ineligible(.testFailed))
  }

  func testTerminalQualificationNeverAdmitsFailedOrIdleResultsToPersistence() {
    for outcome in [TestOutcome.failed, .invalidAFK] {
      for repeated in [false, true] {
        for calendar in [-3_600.0, 15.0] {
          let value = result(outcome: outcome, calendarSeconds: calendar)
          let decision = assessment(value, repeated: repeated)
          XCTAssertFalse(decision.isEligible)
          XCTAssertFalse(ResultSavingPolicy.shouldPersist(outcome: outcome, enabled: true, eligibility: decision))
          XCTAssertFalse(ResultSavingPolicy.shouldPersist(outcome: outcome, enabled: false, eligibility: decision))
        }
      }
    }
  }

  func testFailedTimeBoundaryUsesRoundedScalarBeforeOneHundredTwentySecondGate() {
    let configuration = TestConfiguration.timed(seconds: 120)
    XCTAssertEqual(assessment(result(outcome: .failed, configuration: configuration,
      seconds: 120.004, calendarSeconds: -3_600)), .ineligible(.inconsistentDuration))
    XCTAssertEqual(assessment(result(outcome: .failed, configuration: configuration,
      seconds: 120.005, calendarSeconds: -3_600)), .ineligible(.testFailed))
  }
}
