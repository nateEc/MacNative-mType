import XCTest
@testable import Typebar

final class PersonalBestSpeedPrecisionTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 100)

  private func result(_ speed: Double, configuration: TestConfiguration = .timed(seconds: 15),
    age: Double = 0, accuracy: Double = 98, raw: Double = 70.25,
    outcome: TestOutcome = .completed, tags: [String] = ["focus"]
  ) -> CompletedTestResult {
    .init(id: UUID(), configuration: configuration, outcome: outcome,
      startedAt: start.addingTimeInterval(age), finishedAt: start.addingTimeInterval(age + 15),
      typedCharacterCount: 75, correctCharacterCount: 74, errorCount: 1,
      wpm: Int(speed.rounded()), rawWpm: Int(raw.rounded()), accuracy: Int(accuracy.rounded()),
      preciseWpm: speed, preciseRawWpm: raw, preciseAccuracy: accuracy, tags: tags, prompt: "owned text")
  }

  func testTableSelectsFractionalImprovementDespiteIdenticalRoundedSpeeds() throws {
    let old = result(60.41)
    let new = result(60.49, age: 1)
    let row = try XCTUnwrap(LocalPersonalBestTablePolicy.rows(results: [old, new]).first)
    XCTAssertEqual(row.id, new.id)
    XCTAssertEqual(Double(row.wpm), 60.49)
    XCTAssertEqual(Double(row.rawWpm), 70.25)
  }

  func testTableDoesNotPromoteLowerFractionalSpeedWithHigherAccuracyOrRaw() throws {
    let best = result(60.49, accuracy: 90, raw: 65.21)
    let slower = result(60.41, age: -1, accuracy: 100, raw: 99.99)
    let row = try XCTUnwrap(LocalPersonalBestTablePolicy.rows(results: [slower, best]).first)
    XCTAssertEqual(row.id, best.id)
    XCTAssertEqual(Double(row.wpm), 60.49)
    XCTAssertEqual(row.accuracy, 90)
    XCTAssertEqual(Double(row.rawWpm), 65.21)
  }

  func testEqualFractionalSpeedKeepsExistingHistoryTiePolicyWithoutMetricTieBreak() throws {
    let first = result(60.49, accuracy: 90, raw: 61.11)
    let later = result(60.49, age: 1, accuracy: 100, raw: 99.99)
    for records in [[first, later], [later, first]] {
      let row = try XCTUnwrap(LocalPersonalBestTablePolicy.rows(results: records).first)
      XCTAssertEqual(row.id, first.id)
      XCTAssertEqual(row.accuracy, 90)
      XCTAssertEqual(Double(row.rawWpm), 61.11)
    }
  }

  func testPracticeNoticeAndPaceChooseTheSamePrecisePB() throws {
    let old = result(60.41)
    let best = result(60.49, age: 1, accuracy: 91.25, tags: ["other"])
    let records = [old, best]
    let pb = try XCTUnwrap(CurrentPersonalBestPolicy.personalBest(
      currentConfiguration: best.configuration, currentPrompt: "different time prompt",
      samples: records.map(RecentAverageSample.init(result:))))
    XCTAssertEqual(Double(pb.wpm), 60.49)
    XCTAssertEqual(pb.accuracy, 91.25)
    XCTAssertEqual(PaceGuidePolicy.targetWpm(mode: .personalBest, customWpm: 100,
      configuration: best.configuration, samples: records.map(PaceGuideSample.init(result:))), Double(pb.wpm))
  }

  func testCompletedFeedbackRecognizesSubIntegerImprovement() throws {
    let feedback = try XCTUnwrap(ResultPersonalBestPolicy.feedback(for: result(60.49, age: 1),
      previousResults: [result(60.41)]))
    XCTAssertTrue(feedback.isNewPersonalBest)
    XCTAssertFalse(feedback.showsPreviousBestLine)
    XCTAssertEqual(Double(try XCTUnwrap(feedback.previousBestWpm)), 60.41)
    XCTAssertEqual(Double(feedback.currentWpm), 60.49)
    XCTAssertEqual(Double(try XCTUnwrap(feedback.improvement)), 0.08, accuracy: 0.000_001)
  }

  func testCompletedFeedbackDoesNotReplaceEqualOrFasterPrecisePB() throws {
    for speed in [60.49, 60.48] {
      let feedback = try XCTUnwrap(ResultPersonalBestPolicy.feedback(for: result(speed, age: 1, accuracy: 100),
        previousResults: [result(60.49, accuracy: 90)]))
      XCTAssertFalse(feedback.isNewPersonalBest)
      XCTAssertTrue(feedback.showsPreviousBestLine)
      XCTAssertNil(feedback.improvement)
      XCTAssertEqual(Double(try XCTUnwrap(feedback.previousBestWpm)), 60.49)
    }
  }

  func testTagFeedbackUsesPreciseSpeedAndKeepsSeparateTagBest() throws {
    let prior = [result(60.41), result(60.49, tags: ["other"])]
    let feedback = try XCTUnwrap(TagPersonalBestPolicy.feedback(for: result(60.49, age: 1),
      previousResults: prior).first)
    XCTAssertTrue(feedback.isNewPersonalBest)
    XCTAssertEqual(Double(try XCTUnwrap(feedback.previousBestWpm)), 60.41)
    XCTAssertEqual(Double(try XCTUnwrap(feedback.improvement)), 0.08, accuracy: 0.000_001)
  }

  func testTagCustomAndZenShareMode2DespiteDifferentNativeCompletionLimits() throws {
    for mode in [TestMode.custom, .zen] {
      let short = TestConfiguration(mode: mode, duration: 15, wordLimit: 10,
        difficulty: .normal, rules: .init())
      let long = TestConfiguration(mode: mode, duration: 60, wordLimit: 50,
        difficulty: .normal, rules: .init())
      let feedback = try XCTUnwrap(TagPersonalBestPolicy.feedback(for: result(60.49, configuration: long),
        previousResults: [result(60.41, configuration: short)]).first)
      XCTAssertEqual(Double(try XCTUnwrap(feedback.previousBestWpm)), 60.41)
      XCTAssertTrue(feedback.isNewPersonalBest)
    }
  }

  func testTimeAndWordsGroupOnlyByTheirActiveModeParameter() throws {
    let original = TestConfiguration.timed(seconds: 15)
    var inert = original
    inert.wordLimit = 99
    let feedback = try XCTUnwrap(TagPersonalBestPolicy.feedback(for: result(60.49, configuration: inert),
      previousResults: [result(60.41, configuration: original)]).first)
    XCTAssertEqual(Double(try XCTUnwrap(feedback.previousBestWpm)), 60.41)
    var words = TestConfiguration.words(25)
    words.duration = 99
    let wordFeedback = try XCTUnwrap(TagPersonalBestPolicy.feedback(for: result(60.49, configuration: words),
      previousResults: [result(60.41, configuration: .words(25))]).first)
    XCTAssertEqual(Double(try XCTUnwrap(wordFeedback.previousBestWpm)), 60.41)
  }

  func testFivePBOptionsRemainIndependentAndEligibleVisualModifiersDoNotSplitThem() {
    let baseline = TestConfiguration.timed(seconds: 15)
    var punctuation = baseline; punctuation.contentOptions.includePunctuation = true
    var numbers = baseline; numbers.contentOptions.includeNumbers = true
    var language = baseline; language.language = .spanish
    var difficulty = baseline; difficulty.difficulty = .expert
    let variants = [punctuation, numbers, language, difficulty, baseline.with(modifiers: [.lazyLatin])]
    for variant in variants {
      XCTAssertNil(ResultPersonalBestPolicy.feedback(for: result(60.49),
        previousResults: [result(90.49, configuration: variant)])?.previousBestWpm)
      XCTAssertNil(TagPersonalBestPolicy.feedback(for: result(60.49),
        previousResults: [result(90.49, configuration: variant)]).first?.previousBestWpm)
    }
    let previous = result(60.41, configuration: baseline.with(modifiers: [.mirrorVisual]))
    XCTAssertEqual(Double(ResultPersonalBestPolicy.feedback(for: result(60.49),
      previousResults: [previous])?.previousBestWpm ?? 0), 60.41)
  }

  func testEligibilityAndSelfExclusionAreAppliedBeforePreciseSelection() throws {
    let current = result(60.49)
    let disallowed = result(90.49, configuration: current.configuration.with(modifiers: [.zipf]))
    let bailout = result(95.49, outcome: .bailedOut)
    let stopped = result(99.49, configuration: .timed(seconds: 15,
      rules: .init(stopOnErrorMode: .letter)), accuracy: 99.99)
    let feedback = try XCTUnwrap(ResultPersonalBestPolicy.feedback(for: current,
      previousResults: [current, disallowed, bailout, stopped, result(60.41)]))
    XCTAssertTrue(feedback.isNewPersonalBest)
    XCTAssertEqual(Double(try XCTUnwrap(feedback.previousBestWpm)), 60.41)
  }

  func testLegacyIntegerFallbackAndPrecisionRoundTripDoNotRewriteStoredScores() throws {
    let original = result(60.49)
    let decoded = try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(original))
    XCTAssertEqual(decoded, original)
    let record = TestResultRecord(result: decoded)
    XCTAssertEqual(record.wpm, 60)
    XCTAssertEqual(record.preciseWpm, 60.49)
    record.preciseWpm = nil
    record.preciseRawWpm = nil
    let legacy = try XCTUnwrap(record.portableResult)
    XCTAssertEqual(LocalPersonalBestTablePolicy.rows(results: [legacy]).first.map { Double($0.wpm) }, 60)
    XCTAssertNil(record.preciseWpm)
    XCTAssertEqual(record.wpm, 60)
  }

  func testFeedbackPresentationConvertsBeforeFormattingForEverySpeedUnit() {
    let expected: [(TypingSpeedUnit, String)] = [(.wpm, "+0.08 WPM"), (.cpm, "+0.40 CPM"),
      (.wps, "+0.00 WPS"), (.cps, "+0.01 CPS"), (.wph, "+4.80 WPH")]
    for (unit, text) in expected {
      XCTAssertEqual(PersonalBestFeedbackPresentation.text(previousBestWpm: 60.41,
        currentWpm: 60.49, speedUnit: unit), text)
    }
  }

  func testFirstTagPBAndEqualOrLowerSpeedHaveExplicitPresentation() {
    XCTAssertEqual(PersonalBestFeedbackPresentation.text(previousBestWpm: nil,
      currentWpm: 60.49, speedUnit: .wpm), "首次 PB · 60.49 WPM")
    for speed in [60.49, 60.41] {
      XCTAssertEqual(PersonalBestFeedbackPresentation.text(previousBestWpm: 60.49,
        currentWpm: speed, speedUnit: .cpm), "PB 302.45 CPM")
    }
  }

  func testSampleBadPrecisionUsesTheExistingResultFallbackWithoutChangingAverage() throws {
    for precision in [Double.nan, .infinity, -1] {
      let sample = RecentAverageSample(configuration: .timed(seconds: 15), prompt: "owned",
        finishedAt: start, wpm: 60, accuracy: 98, preciseWpm: precision)
      XCTAssertEqual(sample.preciseWpm, 60)
      XCTAssertEqual(sample.wpm, 60)
      XCTAssertEqual(CurrentPersonalBestPolicy.personalBest(currentConfiguration: sample.configuration,
        currentPrompt: "owned", samples: [sample])?.wpm, 60)
      XCTAssertEqual(RecentTestAveragePolicy.average(currentConfiguration: sample.configuration,
        currentPrompt: "owned", samples: [sample])?.wpm, 60)
    }
  }
}
