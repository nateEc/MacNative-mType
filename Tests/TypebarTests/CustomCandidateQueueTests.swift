import XCTest
@testable import Typebar

final class CustomCandidateQueueTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 840_000_000)
  private func config(_ completion: CustomTextCompletion = .words, limit: Int = 3,
    ordering: CustomTextOrdering = .inOrder, rules: InputRules = .init()) -> TestConfiguration {
    .init(mode: .custom, duration: completion == .time ? 120 : nil,
      wordLimit: completion == .words ? limit : nil, difficulty: .normal, rules: rules,
      customTextCompletion: completion, customTextOrdering: ordering, customTextPipeDelimiter: false)
  }

  func testNonPipeWordBudgetIncludesTheInteriorLFOnlyCandidate() throws {
    var attempt = TestSessionFactory.make(configuration: config(), customText: "ab\r\n \r cd")
    XCTAssertEqual(attempt.prompt, "ab\n\ncd")
    attempt.insertBatch("ab\n", at: start)
    XCTAssertEqual(attempt.outcome, .active)
    attempt.insert("\n", at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.completedWordCount, 2)
    XCTAssertEqual(attempt.outcome, .active)
    attempt.insert("cd", at: start.addingTimeInterval(2))
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.completedWordCount, 3)
    XCTAssertEqual(attempt.wordReviews.map(\.target), ["ab", "", "cd"])
    XCTAssertEqual(attempt.errors, 0)
    let result = try XCTUnwrap(attempt.result())
    XCTAssertEqual(result.configuration.wordLimit, 3)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 2), "ab\n\ncd")
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [], at: start)).results, [result])
  }

  func testTwoLFOnlyWordsRequireTwoInputsAndNeverSubstituteTheConfiguredBudgetWithNonemptyWords() {
    var attempt = TestSessionFactory.make(configuration: config(limit: 2), customText: "\n")
    XCTAssertEqual(attempt.prompt, "\n\n")
    attempt.insert("\n", at: start)
    XCTAssertEqual(attempt.outcome, .active)
    XCTAssertEqual(attempt.completedWordCount, 1)
    attempt.insert("\n", at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.completedWordCount, 2)
    XCTAssertEqual(attempt.errors, 0)
  }

  func testEveryOrderingCanContinueOneHundredPureLFWordsThenFinishItsActualTail() {
    for ordering in CustomTextOrdering.allCases {
      var attempt = TestSessionFactory.make(configuration: config(limit: 101, ordering: ordering), customText: "\r\n",
        nextRandomWordIndex: { 0 })
      let initial = String(repeating: "\n", count: 100)
      XCTAssertEqual(attempt.prompt, initial)
      attempt.insertBatch(initial, at: start)
      XCTAssertEqual(attempt.completedWordCount, 100)
      XCTAssertEqual(attempt.outcome, .active)
      attempt.insert("\n", at: start.addingTimeInterval(1))
      XCTAssertEqual(attempt.prompt, initial + "\n")
      XCTAssertEqual(attempt.outcome, .completed)
      XCTAssertEqual(attempt.completedWordCount, 101)
      XCTAssertEqual(attempt.errors, 0)
      XCTAssertEqual(attempt.repeatedAttempt().prompt, initial)
    }
  }

  func testTheHundredthBlankDoesNotPushTheFinalSourceWordOutsideItsBudget() {
    let words = (0..<99).map { "q\($0)" }
    let source = words.joined(separator: " ") + "\n\nend"
    let opening = words.joined(separator: " ") + "\n\n"
    var attempt = TestSessionFactory.make(configuration: config(limit: 101), customText: source)
    XCTAssertEqual(attempt.prompt, opening)
    attempt.insertBatch(opening, at: start)
    XCTAssertEqual(attempt.completedWordCount, 100)
    XCTAssertEqual(attempt.outcome, .active)
    attempt.insert("end", at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.prompt, opening + "end")
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.completedWordCount, 101)
    XCTAssertEqual(attempt.wordReviews.map(\.target), words + ["", "end"])
    XCTAssertEqual(attempt.errors, 0)
  }

  func testRandomDrawsRetainLFAndBlankCandidatesRatherThanFlatteningTheirWhitespace() {
    var draw = 0
    var attempt = TestSessionFactory.make(configuration: config(limit: 6, ordering: .random),
      customText: "ab\n\ncd ef", nextRandomWordIndex: { defer { draw += 1 }; return draw % 4 })
    let target = "ab\n\ncd ef ab\n\n"
    XCTAssertEqual(attempt.prompt, target)
    XCTAssertEqual(draw, 6)
    attempt.insertBatch(target, at: start)
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.completedWordCount, 6)
    XCTAssertEqual(attempt.errors, 0)
  }

  func testFinishNormalizesCandidateBoundariesWithoutTreatingTABAsAWordSeparator() {
    var attempt = TestSessionFactory.make(configuration: config(.finish),
      customText: "  cafe\u{0301}\u{00A0}tab\tword  tail  ")
    let target = "café tab\tword tail"
    XCTAssertEqual(attempt.prompt, target)
    attempt.insertBatch(target, at: start)
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.completedWordCount, 3)
    XCTAssertEqual(attempt.wordReviews.map(\.target), ["café", "tab\tword", "tail"])
    XCTAssertEqual(attempt.errors, 0)
  }

  func testFinishKeepsBothCRPreparedBlankSlotsAndTheFinalLFCommit() {
    var attempt = TestSessionFactory.make(configuration: config(.finish), customText: "ab \r \r\n")
    XCTAssertEqual(attempt.prompt, "ab\n\n")
    attempt.insert("ab\n", at: start)
    XCTAssertEqual(attempt.outcome, .active)
    attempt.insert("\n", at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.completedWordCount, 2)
    XCTAssertEqual(attempt.errors, 0)
  }

  func testOrdinaryFinishIsBoundedAndRepeatKeepsItsInitialCandidateCursor() {
    let words = (0..<120).map { "q\($0)" }
    let source = words.joined(separator: " ")
    let initial = words.prefix(100).joined(separator: " ") + " "
    var attempt = TestSessionFactory.make(configuration: config(.finish), customText: source)
    XCTAssertEqual(attempt.prompt, initial)
    var repeated = attempt.repeatedAttempt()
    attempt.insertBatch(source, at: start)
    repeated.insertBatch(source, at: start)
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.prompt, source)
    XCTAssertEqual(attempt.completedWordCount, 120)
    XCTAssertEqual(attempt.errors, 0)
    XCTAssertEqual(repeated.prompt, attempt.prompt)
    XCTAssertEqual(repeated.wordReviews, attempt.wordReviews)
  }

  func testTimedAndInfiniteNonPipeLFInputsKeepExtendingInsteadOfEndingOnTheirFirstTarget() throws {
    for completion in [CustomTextCompletion.time, .words] {
      var attempt = TestSessionFactory.make(configuration: config(completion, limit: 0), customText: "\n")
      XCTAssertEqual(attempt.prompt, String(repeating: "\n", count: 100))
      attempt.insertBatch(String(repeating: "\n", count: 205), at: start)
      XCTAssertEqual(attempt.completedWordCount, 205)
      XCTAssertEqual(attempt.outcome, .active)
      XCTAssertEqual(attempt.errors, 0)
      attempt.bailOut(at: start.addingTimeInterval(1))
      let result = try XCTUnwrap(attempt.result())
      XCTAssertEqual(result.outcome, .bailedOut)
      XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 1), attempt.typed)
    }
  }

  func testStrictFinalBlankCompletesWithoutInventingNavigationOrDroppingTheBudgetSlot() {
    var attempt = TestSessionFactory.make(configuration: config(limit: 2, rules: .init(strictSpace: true)), customText: "ab\n\ncd")
    XCTAssertEqual(attempt.prompt, "ab\n\n")
    attempt.insertBatch("ab\n\n", at: start)
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.completedWordCount, 2)
    XCTAssertEqual(attempt.errors, 0)
    XCTAssertTrue(attempt.wordReviews.allSatisfy(\.isCorrect))
  }

  func testAnExplicitShortBookChunkKeepsItsExactFormattingAndProgressBoundary() {
    let source = "amber  harbor\n"
    var attempt = TestSessionFactory.make(configuration: config(.finish), customText: source, finiteTextSource: source)
    XCTAssertEqual(attempt.prompt, source)
    attempt.insertBatch(source, at: start)
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.typed, source)
    XCTAssertEqual(LongSavedTextProgress.advancedOffset(in: source + "next", from: 0, typed: attempt.typed), source.count)
  }

  func testEveryCodeLanguageCountsTheSameNonPipeBlankCandidates() {
    let languages = TypingLanguage.allCases.filter(\.isCodeLanguage)
    XCTAssertEqual(languages.count, 70)
    for language in languages {
      var configuration = config()
      configuration.language = language
      var attempt = TestSessionFactory.make(configuration: configuration, customText: "ab\r\n\r\ncd")
      XCTAssertEqual(attempt.prompt, "ab\n\ncd", language.rawValue)
      attempt.insertBatch("ab\n\ncd", at: start)
      XCTAssertEqual(attempt.outcome, .completed, language.rawValue)
      XCTAssertEqual(attempt.completedWordCount, 3, language.rawValue)
      XCTAssertEqual(attempt.errors, 0, language.rawValue)
    }
  }

  func testTimedCursorCanCommitTwoWholeGeneratedBatchesAndExposeAThird() {
    var attempt = TestSessionFactory.make(configuration: config(.time, ordering: .random), customText: "ash bay elm fog")
    let initial = attempt.prompt
    XCTAssertTrue(initial.hasSuffix(" "))
    attempt.insertBatch(initial, at: start)
    XCTAssertEqual(attempt.errors, 0)
    XCTAssertEqual(attempt.completedWordCount, 100)
    let second = String(attempt.prompt.dropFirst(initial.count))
    XCTAssertTrue(second.hasSuffix(" "))
    attempt.insertBatch(second, at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.errors, 0)
    XCTAssertEqual(attempt.completedWordCount, 200)
    XCTAssertGreaterThan(attempt.prompt.count, initial.count + second.count)
    XCTAssertEqual(attempt.outcome, .active)
  }
}
