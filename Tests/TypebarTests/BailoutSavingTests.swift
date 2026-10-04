import XCTest
import SwiftData
@testable import Typebar

final class BailoutSavingTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_800_000_000)
  private var zen: TestConfiguration {
    .init(mode: .zen, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init())
  }

  private func result(
    configuration: TestConfiguration? = nil, outcome: TestOutcome = .bailedOut,
    seconds: Double = 15, wpm: Int = 60, raw: Int = 60, accuracy: Int = 100,
    preciseAccuracy: Double? = nil, tags: [String] = []
  ) -> CompletedTestResult {
    .init(id: UUID(), configuration: configuration ?? zen, outcome: outcome,
      startedAt: start, finishedAt: start.addingTimeInterval(seconds),
      typedCharacterCount: 75, correctCharacterCount: 75, errorCount: 0,
      wpm: wpm, rawWpm: raw, accuracy: accuracy, preciseAccuracy: preciseAccuracy,
      tags: tags, prompt: "a b")
  }

  private func eligibility(_ result: CompletedTestResult, repeated: Bool = false,
    optOut: Bool = false) -> ResultEligibility {
    ResultEligibilityPolicy.assessment(for: result, samePromptRepeat: repeated,
      allowsReducedAccuracyThreshold: optOut)
  }

  private func saves(_ result: CompletedTestResult, enabled: Bool = true,
    repeated: Bool = false, optOut: Bool = false) -> Bool {
    ResultSavingPolicy.shouldPersist(outcome: result.outcome, enabled: enabled,
      eligibility: eligibility(result, repeated: repeated, optOut: optOut))
  }

  private func physicalBailout(last: Double = 15) throws -> CompletedTestResult {
    var value = TestSessionFactory.make(configuration: zen)
    value.recordPhysicalKeyEvent(keyCode: 0, isKeyDown: true, isRepeat: false, at: start)
    value.insertBatch("a", at: start)
    value.recordPhysicalKeyEvent(keyCode: 11, isKeyDown: true, isRepeat: false,
      at: start.addingTimeInterval(last))
    value.insertBatch("b", at: start.addingTimeInterval(last))
    value.bailOut(at: start.addingTimeInterval(16))
    return try XCTUnwrap(value.result())
  }

  // Promoted from the previously unregistered diagnostic: real native input,
  // real terminal clock and the qualification-aware local saving entry point.
  func testValidPhysicalBailoutIsEligibleForSavedHistory() throws {
    let saved = try physicalBailout()
    XCTAssertEqual(saved.outcome, .bailedOut)
    XCTAssertEqual(saved.elapsedDuration, 15)
    XCTAssertEqual(saved.wallClockDuration, 16)
    XCTAssertTrue(saves(saved))
  }

  func testBailoutCannotUseWallClockToRescueAnIneligibleTrimmedDuration() throws {
    let saved = try physicalBailout(last: 14.994)
    XCTAssertEqual(saved.wallClockDuration, 16)
    XCTAssertEqual(saved.elapsedDuration, 14.99)
    XCTAssertEqual(eligibility(saved), .ineligible(.tooShort))
    XCTAssertFalse(saves(saved))
    XCTAssertEqual(saved.outcome, .bailedOut, "Invalid saving eligibility does not hide the result")
  }

  func testBailoutDoesNotBypassMeasuredOrConfiguredMinimums() {
    for seconds in [0.0, 0.99, 14.99] {
      XCTAssertEqual(eligibility(result(seconds: seconds)), .ineligible(.tooShort))
      XCTAssertFalse(saves(result(seconds: seconds)))
    }
    for configuration in [TestConfiguration.timed(seconds: 14), .words(9)] {
      XCTAssertEqual(eligibility(result(configuration: configuration)), .ineligible(.tooShort))
      XCTAssertFalse(saves(result(configuration: configuration)))
    }
    for configuration in [TestConfiguration.timed(seconds: 0), .words(0)] {
      XCTAssertEqual(eligibility(result(configuration: configuration, seconds: 14.99)), .ineligible(.tooShort))
      XCTAssertTrue(saves(result(configuration: configuration, seconds: 15)))
    }
    let quote = TestConfiguration(mode: .quote, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init())
    XCTAssertEqual(eligibility(result(configuration: quote, seconds: 0.99)), .ineligible(.tooShort))
    XCTAssertTrue(saves(result(configuration: quote, seconds: 1)))
  }

  func testFiniteBailoutUsesFrontendQualificationNotBackendFifteenSecondMinimum() {
    for configuration in [TestConfiguration.timed(seconds: 15), .words(10),
      .init(mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init())] {
      XCTAssertEqual(eligibility(result(configuration: configuration, seconds: 14.5)), .eligible)
      XCTAssertTrue(saves(result(configuration: configuration, seconds: 14.5)))
      XCTAssertFalse(saves(result(configuration: configuration, seconds: 0.99)))
    }
  }

  func testCustomCompletionLimitsAreCheckedEvenForBailout() {
    for (completion, limit, expected): (CustomTextCompletion, Int, Bool) in [
      (.words,9,false), (.words,10,true), (.sections,9,false), (.sections,10,true),
      (.time,14,false), (.time,15,true), (.finish,1,true),
      (.words,0,false), (.sections,0,false), (.time,0,false)
    ] {
      let config = TestConfiguration(mode: .custom,
        duration: completion == .time ? Double(limit) : nil,
        wordLimit: completion == .words ? limit : nil, difficulty: .normal, rules: .init(),
        customTextCompletion: completion,
        customTextSectionLimit: completion == .sections ? limit : nil)
      XCTAssertEqual(saves(result(configuration: config, seconds: 14.5)), expected,
        "\(completion) \(limit)")
    }
  }

  func testBailoutRespectsAccuracyIncludingLeaderboardOptOutAndRounding() {
    for (accuracy,optOut,expected): (Double,Bool,Bool) in [
      (74.99,false,false), (75,false,true), (49.99,true,false), (50,true,true),
      (74.995,false,true), (49.995,true,true)
    ] {
      XCTAssertEqual(saves(result(accuracy: Int(accuracy.rounded()), preciseAccuracy: accuracy),
        optOut: optOut), expected)
    }
  }

  func testFrontendSpeedBooleanConditionDoesNotBecomeAUniversalCap() {
    for outcome in [TestOutcome.completed, .bailedOut] {
      XCTAssertTrue(saves(result(configuration: .words(25), outcome: outcome, wpm: 500, raw: 500)))
      XCTAssertTrue(saves(result(configuration: .words(0), outcome: outcome, wpm: 500, raw: 500)))
      XCTAssertTrue(saves(result(configuration: .words(10), outcome: outcome, wpm: 420, raw: 420)))
      XCTAssertEqual(eligibility(result(configuration: .words(10), outcome: outcome, wpm: 421)), .ineligible(.typingSpeed))
      XCTAssertEqual(eligibility(result(configuration: .words(10), outcome: outcome, raw: 421)), .ineligible(.rawTypingSpeed))
      XCTAssertEqual(eligibility(result(outcome: outcome, wpm: 351)), .ineligible(.typingSpeed))
      XCTAssertEqual(eligibility(result(outcome: outcome, raw: 351)), .ineligible(.rawTypingSpeed))
      XCTAssertEqual(eligibility(result(configuration: .words(25), outcome: outcome, wpm: -1)), .ineligible(.typingSpeed))
    }
  }

  func testRepeatedBailoutIsInvalidExceptQuoteAndCarriesIncompletePractice() {
    let attempt = result()
    XCTAssertEqual(eligibility(attempt, repeated: true), .ineligible(.samePromptRepeat))
    XCTAssertFalse(saves(attempt, repeated: true))
    let quote = TestConfiguration(mode: .quote, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init())
    XCTAssertTrue(saves(result(configuration: quote), repeated: true))
    var ledger = PriorAttemptLedger()
    ledger.recordTerminalAttempt(engagedDuration: 12, outcome: .bailedOut,
      eligibility: .ineligible(.samePromptRepeat), savingEnabled: true)
    XCTAssertEqual(ledger.restartCount, 1)
    XCTAssertEqual(ledger.priorAttemptEngagedDuration, 12)
    ledger.recordTerminalAttempt(engagedDuration: 15, outcome: .bailedOut,
      eligibility: .ineligible(.tooShort), savingEnabled: true)
    ledger.recordTerminalAttempt(engagedDuration: 15, outcome: .bailedOut,
      eligibility: .ineligible(.samePromptRepeat), savingEnabled: false)
    XCTAssertEqual(ledger.restartCount, 1)
    ledger.recordTerminalAttempt(engagedDuration: 4, outcome: .bailedOut,
      eligibility: .ineligible(.tooShort), savingEnabled: true, samePromptRepeat: true)
    XCTAssertEqual(ledger.restartCount, 2, "Repeated attempts carry time even when too-short takes priority")
    XCTAssertEqual(ledger.priorAttemptEngagedDuration, 16)
  }

  func testSavingStillRequiresAnEligibleTerminalOutcomeAndUserPreference() {
    XCTAssertFalse(saves(result(), enabled: false))
    XCTAssertFalse(ResultSavingPolicy.shouldPersist(outcome: .bailedOut, enabled: true),
      "An outcome alone cannot prove a bailout is eligible")
    for outcome in [TestOutcome.active,.failed,.abandoned,.invalidAFK] {
      XCTAssertFalse(ResultSavingPolicy.shouldPersist(outcome: outcome, enabled: true, eligibility: .eligible))
    }
    XCTAssertFalse(ResultSavingPolicy.shouldPersist(outcome: .bailedOut, enabled: true,
      eligibility: .ineligible(.accuracy)))
  }

  func testSignedOutClaimRequiresSuccessfulLocalSaveButIncludesBailout() {
    XCTAssertTrue(SignedOutResultClaimPolicy.shouldRecord(outcome: .bailedOut,
      localSaveState: .saved, isAuthenticatedForResultPublishing: false))
    for state in [LocalResultSaveState.notRequested,.failed("磁盘不可写")] {
      XCTAssertFalse(SignedOutResultClaimPolicy.shouldRecord(outcome: .bailedOut,
        localSaveState: state, isAuthenticatedForResultPublishing: false))
    }
    XCTAssertFalse(SignedOutResultClaimPolicy.shouldRecord(outcome: .bailedOut,
      localSaveState: .saved, isAuthenticatedForResultPublishing: true))
  }

  func testSavedBailoutStatusIsTruthfulAndStillNotCompleted() {
    XCTAssertEqual(TestOutcome.bailedOut.statusText(saveState: .saved), "本次已中止 · 已保存到本机")
    XCTAssertEqual(TestOutcome.bailedOut.statusText(saveState: .notRequested), "本次已中止 · 未保存")
    XCTAssertEqual(TestOutcome.bailedOut.statusText(saveState: .failed("失败")), "本次已中止 · 未保存")
  }

  func testBailoutIsNotAChallengePassEvenWhenEveryMetricMeetsRequirements() throws {
    let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "clean-twenty-five"))
    let attempt = result(configuration: challenge.preset.configuration.with(challengeID: challenge.id))
    XCTAssertFalse(ChallengeEvaluator.evaluate(attempt, challenge: challenge).passed)
    XCTAssertFalse(ChallengeEvaluator.evaluate(attempt, challenge: challenge).failedRequirements.isEmpty)
    XCTAssertTrue(ChallengeEvaluator.evaluate(result(configuration: attempt.configuration,
      outcome: .completed), challenge: challenge).passed)
  }

  func testBailoutCannotCreatePBFeedbackOrTableRows() {
    let attempt = result(configuration: .words(25), wpm: 300, tags: ["owned"])
    let completed = result(configuration: .words(25), outcome: .completed, wpm: 60, tags: ["owned"])
    XCTAssertNil(ResultPersonalBestPolicy.feedback(for: attempt, previousResults: [completed]))
    XCTAssertTrue(TagPersonalBestPolicy.feedback(for: attempt, previousResults: [completed]).isEmpty)
    XCTAssertEqual(LocalPersonalBestTablePolicy.rows(results: [attempt,completed]).map(\.wpm), [60])
    XCTAssertEqual(ResultPersonalBestPolicy.feedback(for: completed, previousResults: [attempt])?.previousBestWpm, nil)
    XCTAssertEqual(TagPersonalBestPolicy.feedback(for: completed, previousResults: [attempt]).first?.previousBestWpm, nil)
  }

  @MainActor func testSavedBailoutRoundTripsThroughInMemoryHistoryArchiveAndCSVWithoutReclassifying() throws {
    let attempt = result(configuration: .words(25), tags: ["owned"])
    let container = try ModelContainer(for: TestResultRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    container.mainContext.insert(TestResultRecord(result: attempt))
    try container.mainContext.save()
    let stored = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).first)
    XCTAssertEqual(stored.portableResult, attempt)
    let archive = TypebarArchive(exportedAt: start, settings: .init(), results: [attempt], presets: [])
    let restored = try JSONDecoder().decode(TypebarArchive.self, from: JSONEncoder().encode(archive))
    XCTAssertEqual(restored.results, [attempt])
    XCTAssertTrue(ResultCSVExport.csvString(for: restored.results).contains("bailedOut"))
    XCTAssertEqual(stored.wpm, 60)
    XCTAssertNil(stored.terminalTimingData, "Do not fabricate evidence for an older result")
  }

  @MainActor func testNewBailoutHistoryRetainsMeasuredClockRealDatesAndPortableEvidence() throws {
    let attempt = try physicalBailout()
    XCTAssertTrue(saves(attempt))
    let container = try ModelContainer(for: TestResultRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    container.mainContext.insert(TestResultRecord(result: attempt))
    try container.mainContext.save()
    let record = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).first)
    XCTAssertEqual(record.portableResult, attempt)
    XCTAssertEqual(record.elapsedDuration, 15)
    XCTAssertEqual(record.finishedAt, start.addingTimeInterval(16))
    let archive = TypebarArchive(exportedAt: start, settings: .init(), results: [attempt], presets: [])
    XCTAssertEqual(archive.version, TypebarArchive.currentVersion)
    let restored = try JSONDecoder().decode(TypebarArchive.self, from: JSONEncoder().encode(archive))
    XCTAssertEqual(restored.results.first?.terminalTiming, attempt.terminalTiming)
    XCTAssertEqual(restored.results.first?.outcome, .bailedOut)
  }

  func testPracticeAggregationIncludesSavedBailoutExactlyOnce() {
    let attempt = result()
    let metric = ResultMetric(record: TestResultRecord(result: attempt))
    let saved = TodayPracticeAggregation.summary(persisted: [metric], currentProcess: [], now: start)
    let live = TodayPracticeAggregation.summary(persisted: [metric],
      currentProcess: [.init(result: attempt)], now: start)
    XCTAssertEqual(saved.completedTests, 1)
    XCTAssertEqual(live.completedTests, 1)
    XCTAssertEqual(saved.typingSeconds, attempt.engagedDuration)
    XCTAssertEqual(live.typingSeconds, attempt.engagedDuration)
  }

  func testCurrentPBExcludesBailoutButRecentAverageStillIncludesIt() throws {
    let configuration = TestConfiguration.words(25)
    let samples = [RecentAverageSample(result: result(configuration: configuration, wpm: 300)),
      RecentAverageSample(result: result(configuration: configuration, outcome: .completed, wpm: 60))]
    XCTAssertEqual(CurrentPersonalBestPolicy.personalBest(currentConfiguration: configuration,
      currentPrompt: "a b", samples: samples)?.wpm, 60)
    XCTAssertNil(CurrentPersonalBestPolicy.personalBest(currentConfiguration: configuration,
      currentPrompt: "a b", samples: [samples[0]]))
    let average = try XCTUnwrap(RecentTestAveragePolicy.average(currentConfiguration: configuration,
      currentPrompt: "a b", samples: samples))
    XCTAssertEqual(average.count, 2)
    XCTAssertEqual(average.wpm, 180)
  }

  func testHistoryPBIDsNeverPromoteBailoutButPracticeMetricsRetainIt() {
    let attempt = result(configuration: .words(25), wpm: 300)
    let completed = result(configuration: .words(25), outcome: .completed, wpm: 60)
    let metrics = [attempt,completed].map { ResultMetric(record: TestResultRecord(result: $0)) }
    XCTAssertEqual(ResultStatistics.personalBestIDs(metrics: metrics), [completed.id])
    XCTAssertTrue(ResultStatistics.personalBestIDs(metrics: [metrics[0]]).isEmpty)
    let stats = ResultStatistics(metrics: metrics)
    XCTAssertEqual(stats.completedTests, 2, "Reference result totals include saved BailOut")
    XCTAssertEqual(stats.averageWPM, 180)
    XCTAssertEqual(stats.totalTypingSeconds, 30)
  }

  func testHistoryEnvelopeIncludesBailoutPointsWithoutRaisingOrInventingPB() {
    let outcomes: [(TestOutcome,Int)] = [(.bailedOut,300),(.completed,90),
      (.bailedOut,400),(.completed,60),(.bailedOut,500)]
    let metrics = outcomes.map { ResultMetric(record: TestResultRecord(result:
      result(configuration: .words(25), outcome: $0.0, wpm: $0.1))) }
    XCTAssertEqual(HistoryChartPolicy.personalBestEnvelope(metrics: metrics), [90,90,60,60,nil])
    XCTAssertEqual(HistoryChartPolicy.personalBestEnvelope(metrics: [metrics[0]]), [nil])
    XCTAssertTrue(HistoryChartPolicy.personalBestEnvelope(metrics: []).isEmpty)
  }

  @MainActor func testUnsupportedBailoutPublicationIsBlockedEvenWithoutTerminalEvidence() async throws {
    for configuration in [zen, .words(25), .timed(seconds: 60)] {
      for capabilities in [nil, RemoteServiceCapabilities(apiVersion: "v1", service: "typebar",
        capabilities: ["resultTerminalTiming":"available", "resultConsistency":"available"])] {
        do {
          _ = try await ResultConsistencyPublication.prepare(result: result(configuration: configuration),
            capabilities: capabilities)
          XCTFail("A bailout must never become an ordinary completed wire result")
        } catch let error as RemoteAccountError {
          XCTAssertTrue(error.localizedDescription.contains("BailOut"))
          XCTAssertFalse(ResultPublicationRetryPolicy.shouldQueue(error))
        }
      }
    }
    do {
      _ = try await ResultConsistencyPublication.prepare(result: physicalBailout(),
        capabilities: .init(apiVersion: "v1", service: "typebar",
          capabilities: ["resultTerminalTiming":"available", "resultConsistency":"available"]),
        calculation: { _ in XCTFail("Unsupported outcome must fail before expensive background work"); return nil })
      XCTFail("Zen timing support is not BailOut support")
    } catch let error as RemoteAccountError {
      XCTAssertTrue(error.localizedDescription.contains("BailOut"))
      XCTAssertFalse(ResultPublicationRetryPolicy.shouldQueue(error))
    }
  }
}
