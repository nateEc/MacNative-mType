import XCTest
import SwiftData
@testable import Typebar

final class SessionElapsedClockTests: XCTestCase {
  private final class Clock {
    var seconds: Double = 0
    var source: SessionElapsedClock { .init { self.seconds } }
  }
  private let start = Date(timeIntervalSinceReferenceDate: 913_000_000.875)

  func testCountdownAndLiveSpeedIgnoreCalendarJumps() throws {
    let clock = Clock()
    var session = TypingSession(configuration: .timed(seconds: 15), prompt: "ab cd ef gh ij").withElapsedClock(clock.source)
    session.insert("a", at: start)
    clock.seconds = 1
    let forward = start.addingTimeInterval(3_600)
    let back = start.addingTimeInterval(-3_600)
    XCTAssertEqual(session.remainingSeconds(at: forward), 14)
    XCTAssertEqual(session.remainingSeconds(at: back), 14)
    XCTAssertEqual(session.wpm(at: forward), 12)
    XCTAssertEqual(session.wpm(at: back), 12)
    session.tick(at: forward)
    XCTAssertFalse(session.isFinished)
    clock.seconds = 15
    session.tick(at: back)
    XCTAssertTrue(session.isFinished)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.startedAt, start)
    XCTAssertEqual(result.finishedAt, back)
    XCTAssertEqual(result.elapsedTime?.seconds, 15)
  }

  func testWordsFreezeRawDurationAndPreserveCalendarDatesAndReplayOffsets() throws {
    let clock = Clock()
    var session = TypingSession(configuration: .words(1), prompt: "ab").withElapsedClock(clock.source)
    session.insert("a", at: start)
    clock.seconds = 16.125
    session.insert("b", at: start.addingTimeInterval(-3_600))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.elapsedTime?.seconds, 16.125)
    XCTAssertEqual(result.elapsedDuration, 16.13)
    XCTAssertEqual(result.replayEvents.map(\.offset), [0, 16.125])
    XCTAssertEqual(result.wpm, 1)
    XCTAssertEqual(result.finishedAt, start.addingTimeInterval(-3_600))
    clock.seconds = 400
    XCTAssertEqual(session.result()?.capturedDuration, 16.125)
  }

  func testPhysicalAndZenTerminalTimesUseMeasuredCoordinatesWithPreStartPress() throws {
    let clock = Clock()
    var session = TypingSession(configuration: .init(mode: .zen, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init()), prompt: "").withElapsedClock(clock.source)
    session.recordPhysicalKeyEvent(keyCode: 0, isKeyDown: true, isRepeat: false, at: start)
    clock.seconds = 0.1
    session.insert("a", at: start.addingTimeInterval(3_600))
    clock.seconds = 0.2
    session.recordPhysicalKeyEvent(keyCode: 0, isKeyDown: false, isRepeat: false, at: start.addingTimeInterval(-3_600))
    clock.seconds = 15.225
    session.recordPhysicalKeyEvent(keyCode: 11, isKeyDown: true, isRepeat: false, at: start)
    session.insert("b", at: start)
    clock.seconds = 16.225
    session.finishZen(at: start.addingTimeInterval(-3_600))
    let value = try XCTUnwrap(session.result())
    XCTAssertEqual(try XCTUnwrap(value.elapsedTime).seconds, 16.125, accuracy: 0.000001)
    XCTAssertEqual(value.terminalTiming?.endMilliseconds, 16_125)
    XCTAssertEqual(value.terminalTiming?.lastKeypressMilliseconds, 15_125)
    XCTAssertEqual(value.keyDurationSamples.first ?? -1, 0.2, accuracy: 0.000001)
    XCTAssertEqual(value.keySpacingSamples.first ?? -1, 15.125, accuracy: 0.000001,
      "The pinned source clamps the preceding pre-start down to zero")
    XCTAssertEqual(value.elapsedDuration, 15.13)
    XCTAssertEqual(value.replayEvents.last?.offset ?? -1, 15.125, accuracy: 0.000001)
  }

  func testWeakSpotBurstAndDeletionOffsetsUseOneMeasurementDomain() throws {
    let clock = Clock()
    var session = TypingSession(configuration: .words(2, rules: .init(freedomMode: true)), prompt: "ab cd")
      .withElapsedClock(clock.source)
    session.insert("a", at: start)
    clock.seconds = 0.5; session.insert("b", at: start.addingTimeInterval(-3_600))
    clock.seconds = 1; session.deleteBackward(at: start.addingTimeInterval(3_600))
    clock.seconds = 1.5; session.insert("b ", at: start)
    XCTAssertEqual(session.recentWordBursts, [24])
    clock.seconds = 2; session.insert("cd", at: start.addingTimeInterval(-3_600))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.replayEvents.map(\.offset), [0, 0.5, 1, 1.5, 1.5, 2, 2])
    XCTAssertEqual(result.capturedDuration, 2)
    XCTAssertEqual(session.liveWeakSpotInputSamples.map(\.interval), [0.5, 1, 0, 0.5, 0])
  }

  func testBailoutAbandonAndTimerFailureFreezeTheirOwnRawTime() throws {
    for terminal in 0..<3 {
      let clock = Clock()
      var session = TypingSession(configuration: .timed(seconds: 60), prompt: "a b c").withElapsedClock(clock.source)
      session.insert("a", at: start); clock.seconds = 16.125
      let end = start.addingTimeInterval(-3_600)
      switch terminal {
      case 0: session.bailOut(at: end)
      case 1: session.abandon(at: end)
      default: session.failForTimerHealth(at: end)
      }
      let result = try XCTUnwrap(session.result())
      XCTAssertEqual(result.elapsedTime?.seconds, 16.125)
      XCTAssertEqual(result.finishedAt, end)
      clock.seconds = 50
      XCTAssertEqual(session.result()?.capturedDuration, 16.125)
    }
  }

  func testShortTimedCalendarMismatchIsIneligible() throws {
    let clock = Clock()
    var session = TypingSession(configuration: .timed(seconds: 15), prompt: "a b c").withElapsedClock(clock.source)
    session.insert("a", at: start)
    clock.seconds = 14.9; session.insert(" b", at: start)
    clock.seconds = 15; session.tick(at: start.addingTimeInterval(3_600))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(ResultEligibilityPolicy.assessment(for: result, samePromptRepeat: false), .ineligible(.inconsistentDuration))
    XCTAssertEqual(result.accuracy, 100, "Date qualification is the only failing condition")
  }

  func testFirstAdmittedInputOwnsOriginAndCompositionMayStartWithoutText() throws {
    let clock = Clock(); clock.seconds = 500
    var session = TypingSession(configuration: .words(1), prompt: "ab").withElapsedClock(clock.source)
    session.insertBatch(" ", at: start)
    XCTAssertFalse(session.hasStarted)
    clock.seconds = 600; session.beginComposition(at: start)
    XCTAssertTrue(session.hasStarted); XCTAssertEqual(session.typed, "")
    clock.seconds = 601; session.insertBatch("ab", at: start.addingTimeInterval(-3_600))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.capturedDuration, 1)
    XCTAssertEqual(result.replayEvents.map(\.offset), [1, 1])
  }

  func testBatchCapturesExactlyOneSampleForItsUnitsAndNestedCallbacks() throws {
    var reads = 0
    let clock = SessionElapsedClock { defer { reads += 1 }; return Double(reads) }
    var session = TypingSession(configuration: .words(2, language: .codeSwift), prompt: "ab \t\tcd").withElapsedClock(clock)
    session.insertBatch("ab ", at: start)
    XCTAssertEqual(reads, 1)
    XCTAssertEqual(session.typed, "ab \t\t")
    session.insertBatch("cd", at: start.addingTimeInterval(-3_600))
    XCTAssertEqual(reads, 2)
    let value = try XCTUnwrap(session.result())
    XCTAssertEqual(reads, 2, "Frozen result construction must not resample")
    XCTAssertEqual(value.replayEvents.map(\.offset), [0, 0, 0, 0, 0, 1, 1])
    XCTAssertEqual(value.capturedDuration, 1)
  }

  func testDeferredAutomaticInputRetainsSourceOffsetButFreezesExecutionTimeAndDate() throws {
    let clock = Clock()
    var session = TypingSession(configuration: .words(1, language: .codeSwift), prompt: "\t\t").withElapsedClock(clock.source)
    session.insertBatch("\t", at: start, defersAutomaticInput: true)
    XCTAssertTrue(session.hasPendingAutomaticInput)
    clock.seconds = 16.125
    let end = start.addingTimeInterval(-3_600)
    _ = session.processNextAutomaticInput(for: session.automaticInputAttemptID, executedAt: end)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.replayEvents.map(\.offset), [0, 0])
    XCTAssertEqual(result.replayEvents.map(\.automatic), [false, true])
    XCTAssertEqual(result.finishedAt, end)
    XCTAssertEqual(result.capturedDuration, 16.125)
  }

  func testRepeatStartsFreshAndPaceRefreshCannotReplaceTheMeasurementClock() throws {
    let clock = Clock(), replacement = Clock()
    var session = TypingSession(configuration: .words(1), prompt: "ab").withElapsedClock(clock.source)
    clock.seconds = 100; session.insert("a", at: start)
    replacement.seconds = 9_999
    session = session.withElapsedClock(replacement.source)
    session.configurePace(wpm: 60)
    clock.seconds = 101; session.insert("b", at: start)
    XCTAssertEqual(session.result()?.capturedDuration, 1)
    var repeated = session.repeatedAttempt()
    XCTAssertFalse(repeated.hasStarted)
    XCTAssertEqual(repeated.processNextAutomaticInput(for: session.automaticInputAttemptID), [])
    clock.seconds = 500; repeated.insert("a", at: start)
    clock.seconds = 502; repeated.insert("b", at: start.addingTimeInterval(-3_600))
    XCTAssertEqual(repeated.result()?.capturedDuration, 2)
  }

  func testClockCannotBeAttachedAfterLegacyPhysicalObservationOrInput() throws {
    for physical in [false, true] {
      let clock = Clock()
      var session = TypingSession(configuration: .words(1), prompt: "ab")
      if physical { session.recordPhysicalKeyEvent(keyCode: 0, isKeyDown: true, isRepeat: false, at: start) }
      else { session.insert("a", at: start) }
      session = session.withElapsedClock(clock.source)
      if physical { session.insert("a", at: start) }
      clock.seconds = 900; session.insert("b", at: start.addingTimeInterval(2))
      XCTAssertNil(session.result()?.elapsedTime)
      XCTAssertEqual(session.result()?.capturedDuration, 2)
    }
  }

  func testInactivityAndRestartAccountingMatchAConsistentDateControl() throws {
    let clock = Clock()
    let configuration = TestConfiguration.words(10)
    var measured = TypingSession(configuration: configuration, prompt: "ab cd ef").withElapsedClock(clock.source)
    var control = TypingSession(configuration: configuration, prompt: "ab cd ef")
    measured.insertBatch("ab ", at: start); control.insertBatch("ab ", at: start)
    clock.seconds = 2
    measured.insertBatch("cd", at: start.addingTimeInterval(-3_600)); control.insertBatch("cd", at: start.addingTimeInterval(2))
    clock.seconds = 6
    XCTAssertEqual(measured.activeEngagedDuration(at: start.addingTimeInterval(3_600)), control.activeEngagedDuration(at: start.addingTimeInterval(6)))
    measured.bailOut(at: start.addingTimeInterval(-3_600)); control.bailOut(at: start.addingTimeInterval(6))
    XCTAssertEqual(measured.afkDuration, control.afkDuration)
    XCTAssertEqual(measured.result()?.engagedDuration, control.result()?.engagedDuration)
  }

  func testNewScalarRoundingAndArchiveDoNotPersistClockCoordinates() throws {
    for mode in [TestMode.quote, .custom] {
      let clock = Clock()
      let config = TestConfiguration(mode: mode, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init())
      var session = TypingSession(configuration: config, prompt: "ab").withElapsedClock(clock.source)
      session.insert("a", at: start); clock.seconds = 0.995
      session.insert("b", at: start.addingTimeInterval(0.995))
      let value = try XCTUnwrap(session.result())
      XCTAssertEqual(value.capturedDuration, 0.995)
      XCTAssertEqual(value.elapsedDuration, mode == .custom ? 0.995 : 1)
      XCTAssertEqual(ResultEligibilityPolicy.assessment(for: value, samePromptRepeat: false).isEligible, mode == .quote)
      XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: value).portableResult), value)
      let data = try TypebarDataTransfer.exportArchive(settings: .init(), results: [value], presets: [], at: start)
      XCTAssertEqual(try TypebarDataTransfer.importArchive(from: data).results, [value])
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
      XCTAssertEqual(json["startedAtReferenceTime"] as? Double, start.timeIntervalSinceReferenceDate)
      for key in ["clockOrigin", "activeTimingDate", "measuredStartedAt", "uptime", "elapsedClock"] { XCTAssertNil(json[key]) }
    }
  }

  func testUnicodeUnitsAndBurstKeepTheSameTimingAsAConsistentDateControl() throws {
    let clock = Clock()
    var measured = TypingSession(configuration: .words(2), prompt: "🙂 x").withElapsedClock(clock.source)
    var control = TypingSession(configuration: .words(2), prompt: "🙂 x")
    measured.insertBatch("🙂 ", at: start); control.insertBatch("🙂 ", at: start)
    clock.seconds = 1
    measured.insert("x", at: start.addingTimeInterval(-3_600)); control.insert("x", at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(measured.result()), baseline = try XCTUnwrap(control.result())
    XCTAssertEqual(result.replayEvents, baseline.replayEvents)
    XCTAssertEqual(result.wpm, baseline.wpm)
    XCTAssertEqual(measured.recentWordBursts, control.recentWordBursts)
    XCTAssertEqual(measured.liveWeakSpotInputSamples, control.liveWeakSpotInputSamples)
  }

  func testTimerGridAndHealthUseMeasuredElapsedNotCalendarJumps() {
    let clock = Clock()
    var session = TypingSession(configuration: .timed(seconds: 15), prompt: "ab cd").withElapsedClock(clock.source)
    session.insert("a", at: start); clock.seconds = 1.01
    for date in [start.addingTimeInterval(-3_600), start.addingTimeInterval(3_600)] {
      let elapsed = session.elapsedSeconds(at: date)
      XCTAssertEqual(ClockTickPolicy.dueSeconds(after: 0, elapsed: elapsed), [1])
      var health = TimerHealthState()
      health.observe(drift: elapsed - 1, configuration: session.configuration)
      XCTAssertFalse(health.shouldFail)
    }
    clock.seconds = 3.6
    let elapsed = session.elapsedSeconds(at: start)
    XCTAssertEqual(ClockTickPolicy.dueSeconds(after: 1, elapsed: elapsed), [2, 3])
    var health = TimerHealthState(); health.observe(drift: elapsed - 2, configuration: session.configuration)
    XCTAssertTrue(health.shouldFail, "Real run-loop delay must still invalidate short tests")
  }

  func testLocalDateQualificationUsesScalarBoundaryAndSignedCalendarGap() throws {
    for (raw, wall, eligible) in [(15.0, 15.09, true), (15.0, 15.11, false),
      (15.0, 14.89, false), (120.004, -3_600.0, false), (120.005, -3_600.0, true)] {
      let clock = Clock()
      var session = TypingSession(configuration: .timed(seconds: 15), prompt: "a b c").withElapsedClock(clock.source)
      session.insert("a", at: start); clock.seconds = raw - 0.01
      session.insertBatch(" b", at: start.addingTimeInterval(wall))
      // Activity after the last whole second is not an AFK interval for
      // ordinary time mode. Keep this fixture about date qualification.
      clock.seconds = raw
      session.tick(at: start.addingTimeInterval(wall))
      let value = try XCTUnwrap(session.result())
      XCTAssertEqual(value.outcome, .completed)
      XCTAssertEqual(ResultEligibilityPolicy.assessment(for: value, samePromptRepeat: false).isEligible, eligible)
    }
  }

  func testBailoutAndLegacyResultsDoNotAcquireTheNewDateQualification() throws {
    let clock = Clock()
    var measured = TypingSession(configuration: .timed(seconds: 60), prompt: "a b c").withElapsedClock(clock.source)
    measured.insert("a", at: start); clock.seconds = 15
    measured.insertBatch(" b", at: start.addingTimeInterval(-3_600))
    clock.seconds = 16.125; measured.bailOut(at: start.addingTimeInterval(-3_600))
    let bailout = try XCTUnwrap(measured.result())
    XCTAssertEqual(bailout.capturedDuration, 16.125)
    XCTAssertEqual(ResultEligibilityPolicy.assessment(for: bailout, samePromptRepeat: false), .eligible)
    var legacy = TypingSession(configuration: .timed(seconds: 15), prompt: "a b c")
    legacy.insert("a", at: start)
    legacy.insertBatch(" b", at: start.addingTimeInterval(3_600))
    legacy.tick(at: start.addingTimeInterval(3_600))
    let old = try XCTUnwrap(legacy.result())
    XCTAssertNil(old.elapsedTime)
    XCTAssertEqual(ResultEligibilityPolicy.assessment(for: old, samePromptRepeat: false), .eligible)
  }

  func testLiveMinimumSpeedFailsOnMeasuredTimeAndFreezesFailedResult() throws {
    let clock = Clock()
    var session = TypingSession(configuration: .words(6, rules: .init(minimumWpm: 5)),
      prompt: "aaaa aaaa aaaa aaaa aaaa aaaa").withElapsedClock(clock.source)
    session.insertBatch("aaaa aaaa aaaa ", at: start); clock.seconds = 60
    session.enforceLivePracticeThresholds(at: start.addingTimeInterval(-3_600))
    XCTAssertEqual(session.outcome, .active)
    session.insertBatch("aaaa ", at: start.addingTimeInterval(3_600))
    session.enforceLivePracticeThresholds(at: start.addingTimeInterval(-3_600))
    XCTAssertEqual(session.outcome, .failed); XCTAssertEqual(session.failureReason, .minimumWpm)
    XCTAssertEqual(session.result()?.capturedDuration, 60)
    clock.seconds = 900; XCTAssertEqual(session.result()?.capturedDuration, 60)
  }

  func testInfiniteChallengeFinishUsesMeasurementWithoutForgingCalendarDate() throws {
    let clock = Clock()
    let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "accuracy-ten-minutes"))
    var session = TypingSession(configuration: challenge.preset.configuration.with(challengeID: challenge.id),
      prompt: "ab cd").withElapsedClock(clock.source)
    session.finishInfiniteChallenge(at: start); XCTAssertFalse(session.isFinished)
    session.insert("a", at: start); clock.seconds = 599
    session.insert("b", at: start.addingTimeInterval(-3_600))
    clock.seconds = 600; session.finishInfiniteChallenge(at: start.addingTimeInterval(-3_600))
    let value = try XCTUnwrap(session.result())
    XCTAssertEqual(value.outcome, .completed); XCTAssertEqual(value.capturedDuration, 600)
    XCTAssertEqual(value.finishedAt, start.addingTimeInterval(-3_600))
  }

  @MainActor func testProducedResultFlowsThroughMemoryStoreArchiveAndNegotiatedPublication() async throws {
    let clock = Clock()
    var session = TypingSession(configuration: .init(mode: .quote, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init()), prompt: "abc").withElapsedClock(clock.source)
    session.recordPhysicalKeyEvent(keyCode: 0, isKeyDown: true, isRepeat: false, at: start)
    session.insert("a", at: start); clock.seconds = 0.1
    session.recordPhysicalKeyEvent(keyCode: 0, isKeyDown: false, isRepeat: false, at: start)
    clock.seconds = 15
    session.recordPhysicalKeyEvent(keyCode: 11, isKeyDown: true, isRepeat: false, at: start.addingTimeInterval(-3_600))
    session.insert("b", at: start.addingTimeInterval(-3_600))
    clock.seconds = 15.1
    session.recordPhysicalKeyEvent(keyCode: 11, isKeyDown: false, isRepeat: false, at: start.addingTimeInterval(-3_600))
    clock.seconds = 16.125
    session.recordPhysicalKeyEvent(keyCode: 8, isKeyDown: true, isRepeat: false, at: start.addingTimeInterval(-3_600))
    session.insert("c", at: start.addingTimeInterval(-3_600))
    let value = try XCTUnwrap(session.result())
    XCTAssertEqual(value.outcome, .completed, "Activity in the retained final intervals is required before saving")
    XCTAssertEqual(ResultEligibilityPolicy.assessment(for: value, samePromptRepeat: false), .eligible)
    let container = try ModelContainer(for: TestResultRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    container.mainContext.insert(TestResultRecord(result: value)); try container.mainContext.save()
    let record = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).first)
    XCTAssertEqual(record.portableResult, value); XCTAssertEqual(ResultMetric(record: record).elapsedSeconds, 16.13)
    let archive = try TypebarDataTransfer.exportArchive(settings: .init(), results: [try XCTUnwrap(record.portableResult)], presets: [], at: start)
    let restored = try XCTUnwrap(TypebarDataTransfer.importArchive(from: archive).results.first)
    let capabilities = RemoteServiceCapabilities(apiVersion: "v1", service: "typebar",
      capabilities: ["resultElapsedTime": "available", "resultTimingEvidence": "available",
        "resultPracticeTiming": "available", "resultSpeedPrecision": "available", "resultInputMetricsV2": "available"])
    let wire = try await ResultConsistencyPublication.prepare(result: restored, capabilities: capabilities)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(wire)) as? [String: Any])
    XCTAssertEqual(json["elapsedTime"] as? NSDictionary, ["version": 1, "seconds": 16.125] as NSDictionary)
    XCTAssertEqual(json["finishedAtReferenceTime"] as? Double, start.addingTimeInterval(-3_600).timeIntervalSinceReferenceDate)
    XCTAssertNotNil(json["timingEvidence"])
    XCTAssertEqual(wire.speedPrecision?.wpm, ResultTerminalTiming.round(restored.preciseWpm))
    XCTAssertNotNil(wire.inputMetrics)
    for key in ["prompt", "replayEvents", "clockOrigin", "measuredStartedAt"] { XCTAssertNil(json[key]) }
  }
}
