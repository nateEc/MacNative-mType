import XCTest
@testable import Typebar

final class PaceResultSelectionTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private let configuration = TestConfiguration.timed(seconds: 30, language: .english)

  private func sample(speed: Int, outcome: TestOutcome = .completed,
    configuration: TestConfiguration? = nil, age: Double = 0, tags: [String] = []) -> PaceGuideSample {
    .init(configuration: configuration ?? self.configuration, outcome: outcome,
      finishedAt: now.addingTimeInterval(-age), wpm: speed, tags: tags)
  }

  private func target(_ mode: PaceGuideMode, _ samples: [PaceGuideSample],
    configuration: TestConfiguration? = nil, tags: [String] = []) -> Double? {
    PaceGuidePolicy.targetWpm(mode: mode, customWpm: 100,
      configuration: configuration ?? self.configuration, samples: samples,
      activeTags: tags, now: now)
  }

  func testFinishUpdatesLastBeforeSavingQualificationAndForBailout() {
    for outcome in [TestOutcome.completed, .bailedOut, .invalidAFK, .failed] {
      XCTAssertEqual(LastTestPacePolicy.updatedWpm(previousWpm: 80, candidateWpm: 90,
        outcome: outcome, isPaceRepeat: false), 90)
      XCTAssertEqual(LastTestPacePolicy.updatedWpm(previousWpm: 80, candidateWpm: 0,
        outcome: outcome, isPaceRepeat: false), 0)
    }
    for outcome in [TestOutcome.active, .abandoned] {
      XCTAssertEqual(LastTestPacePolicy.updatedWpm(previousWpm: 80, candidateWpm: 90,
        outcome: outcome, isPaceRepeat: false), 80)
    }
  }

  func testRepeatKeepsFastestFinishIncludingAnUnsavedBailout() {
    XCTAssertEqual(LastTestPacePolicy.updatedWpm(previousWpm: 80, candidateWpm: 120,
      outcome: .bailedOut, isPaceRepeat: true), 120)
    XCTAssertEqual(LastTestPacePolicy.updatedWpm(previousWpm: 80, candidateWpm: 60,
      outcome: .invalidAFK, isPaceRepeat: true), 80)
  }

  func testLastTargetDoesNotClampStoredSpeedToCustomEditorRange() {
    for speed in [1, 9, 350, 420] {
      XCTAssertEqual(PaceGuidePolicy.targetWpm(mode: .lastTest, customWpm: 100,
        configuration: configuration, samples: [], lastTestWpm: Double(speed)), Double(speed))
    }
  }

  func testRecentAverageIncludesSavedBailoutBeforeTakingTen() {
    let records = (0..<10).map { sample(speed: 50, age: Double($0 + 1)) }
    let bailout = sample(speed: 150, outcome: .bailedOut)
    XCTAssertEqual(target(.recentAverage, records + [bailout]), 60)
    XCTAssertEqual(target(.recentAverage, [bailout]), 150)
    XCTAssertEqual(target(.recentAverage, [bailout, sample(speed: 400, outcome: .failed)]), 150)
  }

  func testRollingDayIncludesBailoutAndExactBoundaryNotCalendarDay() {
    let records = [sample(speed: 120, outcome: .bailedOut, age: 86_400),
      sample(speed: 140, outcome: .bailedOut, age: 86_400.01), sample(speed: 60)]
    XCTAssertEqual(target(.dailyBest, records), 120)
  }

  func testNativeAverageSupplementIncludesSavedBailoutButNotAbandoned() {
    XCTAssertEqual(target(.average, [sample(speed: 60), sample(speed: 120, outcome: .bailedOut),
      sample(speed: 900, outcome: .abandoned)]), 90)
    XCTAssertEqual(target(.dailyAverage, [sample(speed: 60), sample(speed: 120, outcome: .bailedOut)]), 90)
  }

  func testPBUsesExactModeParameterAndContentSettings() {
    let records = [sample(speed: 60), sample(speed: 300, configuration: .timed(seconds: 60)),
      sample(speed: 240, configuration: .timed(seconds: 30,
        contentOptions: .init(includePunctuation: true)))]
    XCTAssertEqual(target(.personalBest, records), 60)
    XCTAssertEqual(target(.activeTagPersonalBest, records.map {
      .init(configuration: $0.configuration, outcome: $0.outcome, finishedAt: $0.finishedAt,
        wpm: $0.wpm, tags: ["focus"])
    }, tags: ["focus"]), 60)
  }

  func testPBGetterUsesEligibleCompletedHistoryButAveragesKeepNonPBResults() {
    let modified = TestConfiguration.timed(seconds: 30).with(modifiers: [.binaryStream])
    let records = [sample(speed: 60), sample(speed: 240, configuration: modified),
      sample(speed: 300, outcome: .bailedOut)]
    XCTAssertEqual(target(.personalBest, records), 60)
    XCTAssertEqual(target(.recentAverage, records), 200)
    XCTAssertNil(target(.personalBest, records, configuration: modified))
  }

  func testActiveTagFiltersApplyBeforeAverageLimitAndRollingBest() {
    let records = [sample(speed: 60, tags: ["focus"]),
      sample(speed: 120, outcome: .bailedOut, tags: ["focus"]),
      sample(speed: 300, outcome: .bailedOut, tags: ["other"])]
    XCTAssertEqual(target(.recentAverage, records, tags: ["focus"]), 90)
    XCTAssertEqual(target(.dailyBest, records, tags: ["focus"]), 120)
    XCTAssertEqual(target(.activeTagPersonalBest, records, tags: ["focus"]), 60)
  }

  func testPrecisionSurvivesLastAndPBButAggregatesRoundOnlyAfterSelection() {
    let fractional = PaceGuideSample(configuration: configuration, outcome: .completed,
      finishedAt: now, wpm: 60, preciseWpm: 60.49)
    XCTAssertEqual(target(.personalBest, [fractional]), 60.49)
    XCTAssertEqual(target(.activeTagPersonalBest, [.init(configuration: configuration,
      outcome: .completed, finishedAt: now, wpm: 60, tags: ["focus"], preciseWpm: 60.49)],
      tags: ["focus"]), 60.49)
    XCTAssertEqual(LastTestPacePolicy.updatedWpm(previousWpm: 60.48, candidateWpm: 60.49,
      outcome: .bailedOut, isPaceRepeat: true), 60.49)
    let second = PaceGuideSample(configuration: configuration, outcome: .bailedOut,
      finishedAt: now, wpm: 61, preciseWpm: 60.50)
    XCTAssertEqual(target(.recentAverage, [fractional, second]), 60)
    XCTAssertEqual(target(.dailyBest, [fractional, second]), 61)
  }

  func testCurrentFunboxBlocksOrdinaryPBButNotExistingTagPB() {
    let modified = configuration.with(modifiers: [.binaryStream])
    let records = [sample(speed: 60, tags: ["focus"]),
      sample(speed: 240, configuration: modified, tags: ["focus"])]
    XCTAssertNil(target(.personalBest, records, configuration: modified))
    XCTAssertEqual(target(.activeTagPersonalBest, records, configuration: modified,
      tags: ["focus"]), 60)
  }

  func testPBDisqualifiesStopOnErrorHistoryWithLessThanPerfectPrecision() {
    var stopped = configuration
    stopped.rules.stopOnError = true
    let records = [sample(speed: 60), PaceGuideSample(configuration: stopped,
      outcome: .completed, finishedAt: now, wpm: 120, accuracy: 99.99)]
    XCTAssertEqual(target(.personalBest, records), 60)
    XCTAssertEqual(target(.recentAverage, records), 90)
  }

  func testTargetsRejectDisabledOrNonFiniteSpeedsAndProjectionDoesNotTrap() {
    for speed in [0, 0.99, -1, Double.nan, Double.infinity] {
      XCTAssertNil(PaceGuidePolicy.validTarget(speed))
    }
    XCTAssertEqual(PaceGuidePolicy.validTarget(1.25), 1.25)
    let catalog = PaceCaretCatalog(prompt: String(repeating: "a", count: 100))
    let date = Date(timeIntervalSinceReferenceDate: 0)
    var pace = PaceCaretProgress(wpm: 60.5, catalog: catalog)!
    pace.start(at: date, blind: false)
    XCTAssertEqual(pace.frame(at: date.addingTimeInterval(12), blind: false)?.target.letter, 61)
    var huge = PaceCaretProgress(wpm: .greatestFiniteMagnitude, catalog: catalog)!
    huge.start(at: date, blind: false)
    XCTAssertNil(huge.frame(at: date.addingTimeInterval(.greatestFiniteMagnitude), blind: false))
    XCTAssertEqual(pace.frame(at: Date(timeIntervalSinceReferenceDate: .nan), blind: false)?.target.letter, 1)
    XCTAssertNil(PaceCaretProgress(wpm: .infinity, catalog: catalog))
  }

  func testRepeatRawNaNComparisonMatchesSetterAndMissingPreviousUsesZero() {
    XCTAssertNil(LastTestPacePolicy.updatedWpm(previousWpm: nil, candidateWpm: 0,
      outcome: .completed, isPaceRepeat: true))
    let previous = LastTestPacePolicy.updatedWpm(previousWpm: 60, candidateWpm: .nan,
      outcome: .failed, isPaceRepeat: false)
    XCTAssertTrue(previous?.isNaN == true)
    XCTAssertTrue(LastTestPacePolicy.updatedWpm(previousWpm: previous, candidateWpm: 120,
      outcome: .completed, isPaceRepeat: true)?.isNaN == true)
  }

  func testActualResultAdapterKeepsSavedPrecisionAndLegacyFallbackWithoutRescoring() {
    func result(precision: Double?) -> CompletedTestResult {
      .init(id: UUID(), configuration: configuration, outcome: .bailedOut,
        startedAt: now.addingTimeInterval(-15), finishedAt: now,
        typedCharacterCount: 75, correctCharacterCount: 75, errorCount: 0,
        wpm: 60, rawWpm: 60, accuracy: 100, preciseWpm: precision,
        tags: ["focus"], prompt: "owned")
    }
    let stored = result(precision: 60.49)
    let adapted = PaceGuideSample(result: stored)
    XCTAssertEqual(adapted.preciseWpm, 60.49)
    XCTAssertEqual(adapted.accuracy, stored.preciseAccuracy)
    XCTAssertEqual(adapted.outcome, .bailedOut)
    XCTAssertEqual(adapted.tags, ["focus"])
    XCTAssertEqual(adapted.prompt, "owned")
    XCTAssertEqual(PaceGuideSample(result: result(precision: nil)).preciseWpm, 60)
    XCTAssertEqual(stored.wpm, 60)
  }

  func testExactDifficultyLazyNumbersLanguageAndWordLimitAreFilteredBeforeLimit() {
    let wordConfiguration = TestConfiguration.words(10, language: .english)
    var hard = configuration
    hard.difficulty = .expert
    let mismatches = [hard, configuration.with(modifiers: [.lazyLatin]),
      .timed(seconds: 30, contentOptions: .init(includeNumbers: true)),
      .timed(seconds: 30, language: .simplifiedChinese), wordConfiguration]
    let records = [sample(speed: 60, age: 100)] + mismatches.flatMap { config in
      (0..<10).map { sample(speed: 300, configuration: config, age: Double($0)) }
    }
    XCTAssertEqual(target(.recentAverage, records), 60)
    XCTAssertEqual(target(.dailyBest, records), 60)
    XCTAssertEqual(target(.personalBest, records), 60)
    XCTAssertEqual(target(.personalBest, [sample(speed: 60, configuration: wordConfiguration),
      sample(speed: 300, configuration: .words(25))], configuration: wordConfiguration), 60)
  }
}
