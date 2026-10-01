import XCTest
@testable import Typebar

final class LocalAccuracyPrecisionTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 100)

  private func result(accuracy: Int = 67, precise: Double? = 66.67,
    offset: Double = 0, wpm: Int = 40, rules: InputRules = .init(), tags: [String] = []) -> CompletedTestResult {
    .init(id: UUID(), configuration: .timed(seconds: 15, rules: rules), outcome: .completed,
      startedAt: start.addingTimeInterval(offset), finishedAt: start.addingTimeInterval(offset + 15),
      typedCharacterCount: 3, correctCharacterCount: 2, errorCount: 1,
      wpm: wpm, rawWpm: 50, accuracy: accuracy, preciseAccuracy: precise, tags: tags, prompt: "abc")
  }

  func testHistoryMetricsKeepStoredPrecisionAndLegacyFallbackWithoutMutatingRecords() {
    let record = TestResultRecord(result: result())
    XCTAssertEqual(Double(ResultMetric(record: record).accuracy), 66.67, accuracy: 0.000_001)
    XCTAssertEqual(record.accuracy, 67)
    XCTAssertEqual(record.preciseAccuracy, 66.67)
    record.preciseAccuracy = nil
    XCTAssertEqual(Double(ResultMetric(record: record).accuracy), 67)
    XCTAssertNil(record.preciseAccuracy)
  }

  func testAccuracySortUsesPrecisionBeforeDateTieBreaker() {
    let lower = ResultMetric(record: TestResultRecord(result: result(precise: 66.51, offset: 1)))
    let higher = ResultMetric(record: TestResultRecord(result: result(precise: 67.49)))
    XCTAssertEqual(ResultHistorySortPolicy.sorted([lower, higher], by: .accuracy,
      direction: .descending).map(\.id), [higher.id, lower.id])
    XCTAssertEqual(ResultHistorySortPolicy.sorted([higher, lower], by: .accuracy,
      direction: .ascending).map(\.id), [lower.id, higher.id])
  }

  func testSummaryDailyAndRunningAveragesDoNotRoundInputOrIntermediateValues() throws {
    let metrics = [66.67, 99.6].map {
      ResultMetric(record: TestResultRecord(result: result(accuracy: Int($0.rounded()), precise: $0)))
    }
    let summary = ResultStatistics(metrics: metrics)
    XCTAssertEqual(Double(summary.averageAccuracy), 83.135, accuracy: 0.000_001)
    XCTAssertEqual(Double(summary.averageAccuracyLast10), 83.135, accuracy: 0.000_001)
    XCTAssertEqual(Double(summary.bestAccuracy), 99.6)
    let daily = try XCTUnwrap(ActivityAggregation.daily(metrics: metrics).first)
    XCTAssertEqual(daily.averageAccuracy, 83.135, accuracy: 0.000_001)
    let moving = HistoryChartPolicy.movingAverage(values: metrics.map { Double($0.accuracy) }, windowSize: 10)
    XCTAssertEqual(try XCTUnwrap(moving.first), 83.135, accuracy: 0.000_001)
  }

  func testSummaryLastTenDoesNotIncludeOlderOutlier() {
    let metrics = (0..<11).map { offset in
      ResultMetric(record: TestResultRecord(result: result(accuracy: offset == 10 ? 0 : 67,
        precise: offset == 10 ? 0 : 66.67)))
    }
    XCTAssertEqual(Double(ResultStatistics(metrics: metrics).averageAccuracyLast10), 66.67, accuracy: 0.000_001)
    XCTAssertEqual(Double(ResultStatistics(metrics: []).averageAccuracy), 0)
  }

  func testCurrentSettingsAverageKeepsFractionEvenForLegacyIntegerSamples() throws {
    let configuration = TestConfiguration.words(25)
    let samples = [85, 86].map {
      RecentAverageSample(configuration: configuration, prompt: "abc", finishedAt: start,
        wpm: 40, accuracy: $0)
    }
    let average = try XCTUnwrap(RecentTestAveragePolicy.average(currentConfiguration: configuration,
      currentPrompt: "abc", samples: samples))
    XCTAssertEqual(Double(average.accuracy), 85.5)
  }

  func testRoundedPerfectStopOnLetterCannotReceiveLocalOrTagPB() {
    let stopped = result(accuracy: 100, precise: 99.6, rules: .init(stopOnErrorMode: .letter), tags: ["focus"])
    XCTAssertNil(ResultPersonalBestPolicy.feedback(for: stopped, previousResults: []))
    XCTAssertTrue(TagPersonalBestPolicy.feedback(for: stopped, previousResults: []).isEmpty)
    XCTAssertTrue(LocalPersonalBestTablePolicy.rows(results: [stopped]).isEmpty)
    let perfect = result(accuracy: 100, precise: 100, rules: .init(stopOnErrorMode: .letter), tags: ["focus"])
    XCTAssertNotNil(ResultPersonalBestPolicy.feedback(for: perfect, previousResults: []))
    XCTAssertEqual(TagPersonalBestPolicy.feedback(for: perfect, previousResults: []).count, 1)
    XCTAssertEqual(LocalPersonalBestTablePolicy.rows(results: [perfect]).count, 1)
  }

  func testPBRowRetainsAccuracyWithoutIntroducingAccuracyTieBreak() throws {
    let older = result(precise: 66.67)
    let newer = result(precise: 67.49, offset: 1)
    let row = try XCTUnwrap(LocalPersonalBestTablePolicy.rows(results: [newer, older]).first)
    XCTAssertEqual(row.id, older.id, "The reference PB tie remains first achieved WPM, not accuracy")
    XCTAssertEqual(Double(row.accuracy), 66.67, accuracy: 0.000_001)
  }

  func testShareTextDoesNotReportRoundedPerfectAccuracyAndKeepsLegacyIntegers() {
    XCTAssertTrue(ResultShareText.make(for: result()).contains("66.67% 准确率"))
    XCTAssertTrue(ResultShareText.make(for: result(accuracy: 100, precise: 99.6)).contains("99.60% 准确率"))
    XCTAssertTrue(ResultShareText.make(for: result(accuracy: 91, precise: nil)).contains("91% 准确率"))
  }

  func testActualRejectedAttemptCannotCreateRoundedPerfectPB() throws {
    var session = TypingSession(configuration: .timed(seconds: 15, rules: .init(stopOnErrorMode: .letter)),
      prompt: String(repeating: "a", count: 249))
    session.insert("x", at: start)
    for index in 1...249 {
      session.insert("a", at: start.addingTimeInterval(Double(index) * 15 / 250))
    }
    session.tick(at: start.addingTimeInterval(15))
    let completed = try XCTUnwrap(session.result())
    XCTAssertEqual(completed.outcome, .completed)
    XCTAssertEqual(completed.accuracy, 100)
    XCTAssertEqual(completed.preciseAccuracy, 99.6)
    XCTAssertEqual(completed.inputMetrics?.totalAttempts, 250)
    XCTAssertNil(ResultPersonalBestPolicy.feedback(for: completed, previousResults: []))
    XCTAssertTrue(LocalPersonalBestTablePolicy.rows(results: [completed]).isEmpty)
  }

  func testCurrentSettingsConsumersKeepDecimalSamplesAndPBFiltering() throws {
    let configuration = TestConfiguration.timed(seconds: 15, rules: .init(stopOnErrorMode: .letter))
    let samples = [
      RecentAverageSample(configuration: configuration, prompt: "abc", finishedAt: start,
        wpm: 90, accuracy: 100, preciseAccuracy: 99.6),
      RecentAverageSample(configuration: configuration, prompt: "abc", finishedAt: start,
        wpm: 40, accuracy: 100, preciseAccuracy: 100),
    ]
    let average = try XCTUnwrap(RecentTestAveragePolicy.average(currentConfiguration: configuration,
      currentPrompt: "abc", samples: samples))
    XCTAssertEqual(average.accuracy, 99.8, accuracy: 0.000_001)
    XCTAssertEqual(CurrentPersonalBestPolicy.personalBest(currentConfiguration: configuration,
      currentPrompt: "abc", samples: samples), .init(wpm: 40, accuracy: 100))
    XCTAssertEqual(ResultMetricPresentation.accuracy(average.accuracy, alwaysShowDecimalPlaces: false), "99%")
    XCTAssertEqual(ResultMetricPresentation.accuracy(average.accuracy, alwaysShowDecimalPlaces: true), "99.80%")
  }

  func testCorruptOptionalPrecisionUsesExistingNormalizationWithoutWritingHistory() {
    let record = TestResultRecord(result: result())
    for (value, expected) in [(Double.nan, 67.0), (.infinity, 67), (-1, 0), (101, 100)] {
      record.preciseAccuracy = value
      XCTAssertEqual(ResultMetric(record: record).accuracy, expected)
      if value.isNaN { XCTAssertTrue(record.preciseAccuracy?.isNaN == true) }
      else { XCTAssertEqual(record.preciseAccuracy, value) }
    }
  }

  func testOwnedOfflineAchievementUsesExactThresholdNotRoundedAccuracy() throws {
    for (precision, expected) in [(97.6, false), (98.0, true)] {
      let metric = ResultMetric(record: TestResultRecord(result: result(accuracy: 98, precise: precision)))
      let achievement = try XCTUnwrap(TypebarAchievementPolicy.achievements(metrics: [metric])
        .first { $0.id == "clear-key" })
      XCTAssertEqual(achievement.isUnlocked, expected)
    }
  }

  func testPriorRoundedPerfectResultDoesNotInflateCurrentOrTagPBLine() {
    let invalidPrior = result(accuracy: 100, precise: 99.6, wpm: 90,
      rules: .init(stopOnErrorMode: .letter), tags: ["focus"])
    let validPrior = result(wpm: 30, tags: ["focus"])
    let current = result(offset: 1, tags: ["focus"])
    XCTAssertEqual(ResultPersonalBestPolicy.feedback(for: current, previousResults: [invalidPrior, validPrior])?
      .previousBestWpm, 30)
    XCTAssertEqual(TagPersonalBestPolicy.feedback(for: current, previousResults: [invalidPrior, validPrior])
      .first?.previousBestWpm, 30)
  }
}
