import XCTest
@testable import Typebar

final class RetainedLeadingSeparatorTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 820_000_000)
  private func quote(_ source: String = "ab\n\ncd", difficulty: Difficulty = .normal,
    rules: InputRules = .init(strictSpace: true)) -> TypingSession {
    TestSessionFactory.make(configuration: .init(mode: .quote, duration: nil, wordLimit: nil,
      difficulty: difficulty, rules: rules),
      quote: .init(id: "owned-retained-leading", title: "Owned probe", text: source,
        language: .english, length: .short))
  }

  private func lastReplayEvent(_ attempt: TypingSession) throws -> TypingReplayEvent {
    var snapshot = attempt
    if !snapshot.isFinished { snapshot.bailOut(at: start.addingTimeInterval(4)) }
    return try XCTUnwrap(XCTUnwrap(snapshot.result()).replayEvents.last)
  }

  func testCorrectBlankNewlineIsRetainedWithoutNavigationInEveryStrictDifficulty() throws {
    for difficulty in Difficulty.allCases {
      var attempt = quote(difficulty: difficulty,
        rules: .init(strictSpace: difficulty == .normal))
      attempt.insert("ab\n", at: start)
      attempt.insert("\n", at: start.addingTimeInterval(1))
      XCTAssertEqual(attempt.typed, "ab\n\n", difficulty.rawValue)
      XCTAssertEqual(attempt.nextExpectedCharacter, "\n", difficulty.rawValue)
      XCTAssertEqual(attempt.completedWordCount, 1, difficulty.rawValue)
      XCTAssertEqual(attempt.outcome, .active, difficulty.rawValue)
      XCTAssertEqual(attempt.errors, 0, difficulty.rawValue)
      XCTAssertEqual(attempt.lastInputWasCorrect, true, difficulty.rawValue)
      XCTAssertEqual(try lastReplayEvent(attempt).commitsWord, false, difficulty.rawValue)
    }
  }

  func testStrictNormalSecondNewlineCommitsAnIncorrectBlankWithoutSkippingTheFinalWord() {
    var attempt = quote()
    attempt.insert("ab\n\n", at: start)
    attempt.insert("\n", at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.completedWordCount, 2)
    XCTAssertEqual(attempt.nextExpectedCharacter, "c")
    XCTAssertEqual(attempt.errors, 1)
    XCTAssertEqual(attempt.lastInputWasCorrect, false)
    attempt.insert("cd", at: start.addingTimeInterval(2))
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.wordReviews.map(\.target), ["ab", "", "cd"])
    XCTAssertEqual(attempt.wordReviews.map(\.typed), ["ab", "\n", "cd"])
    XCTAssertEqual(attempt.wordReviews.map(\.isCorrect), [true, false, true])
    XCTAssertEqual(attempt.missedWordErrorCountsByWord, [0, 1, 0])
  }

  func testExpertAndMasterFailOnTheSecondBlankNewlineNotTheFirstCorrectOne() throws {
    for difficulty in [Difficulty.expert, .master] {
      var attempt = quote(difficulty: difficulty, rules: .init())
      attempt.insert("ab\n\n", at: start)
      XCTAssertEqual(attempt.outcome, .active)
      attempt.insert("\n", at: start.addingTimeInterval(1))
      XCTAssertEqual(attempt.outcome, .failed)
      XCTAssertEqual(attempt.errors, 1)
      XCTAssertEqual(attempt.wordReviews.map(\.typed), ["ab", "\n"])
      XCTAssertEqual(attempt.wordReviews.map(\.isCorrect), [true, false])
      let result = try XCTUnwrap(attempt.result())
      XCTAssertEqual(result.inputMetrics?.totalAttempts, 5)
      XCTAssertEqual(result.inputMetrics?.correctAttempts, 4)
    }
  }

  func testDeletionRemovesTheRetainedBlankWithoutReopeningThePreviousWord() throws {
    var attempt = quote()
    attempt.insert("ab\n\n", at: start)
    attempt.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.typed, "ab\n")
    XCTAssertEqual(attempt.nextExpectedCharacter, "\n")
    XCTAssertEqual(attempt.completedWordCount, 1)
    attempt.insert("\n", at: start.addingTimeInterval(2))
    XCTAssertEqual(attempt.nextExpectedCharacter, "\n")
    attempt.bailOut(at: start.addingTimeInterval(3))
    let result = try XCTUnwrap(attempt.result())
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 5)
    XCTAssertEqual(result.inputMetrics?.correctAttempts, 5)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 3), attempt.typed)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from:
      TypebarDataTransfer.exportArchive(settings: .init(), results: [result], presets: [], at: start)).results, [result])
    var repeated = attempt.repeatedAttempt()
    repeated.insert("ab\n\n", at: start)
    XCTAssertEqual(repeated.nextExpectedCharacter, "\n")
    XCTAssertEqual(try lastReplayEvent(repeated).commitsWord, false)
  }

  func testWrongPlatformSpaceInABlankRemainsOnThatSlotAndLaterCommitIsAlsoWrong() throws {
    var attempt = quote()
    attempt.insert("ab\n", at: start)
    attempt.insert("\u{3000}", at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.typed, "ab\n ")
    XCTAssertEqual(attempt.nextExpectedCharacter, "\n")
    XCTAssertEqual(attempt.completedWordCount, 1)
    XCTAssertEqual(attempt.errors, 1)
    XCTAssertEqual(try lastReplayEvent(attempt).commitsWord, false)
    attempt.insert("\ncd", at: start.addingTimeInterval(2))
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.errors, 2)
    XCTAssertEqual(attempt.wordReviews.map(\.typed), ["ab", " ", "cd"])
  }

  func testLeadingSpaceInsideANonemptyWordDoesNotCommitItAndDeletionRestoresTheTarget() throws {
    var attempt = quote("ab cd")
    attempt.insert(" ", at: start)
    XCTAssertEqual(attempt.completedWordCount, 0)
    XCTAssertEqual(try lastReplayEvent(attempt).commitsWord, false)
    XCTAssertEqual(attempt.nextExpectedCharacter, "b")
    attempt.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.typed, "")
    XCTAssertEqual(attempt.nextExpectedCharacter, "a")
    attempt.insert("ab cd", at: start.addingTimeInterval(2))
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.errors, 0)
  }

  func testExpertLeadingWrongSpaceDoesNotFailUntilTheNonemptyWordIsCommitted() {
    var attempt = quote("ab cd", difficulty: .expert, rules: .init())
    attempt.insert(" ", at: start)
    XCTAssertEqual(attempt.outcome, .active)
    XCTAssertEqual(attempt.completedWordCount, 0)
    attempt.insert("b", at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.lastInputWasCorrect, true)
    attempt.insert(" ", at: start.addingTimeInterval(2))
    XCTAssertEqual(attempt.outcome, .failed)
    XCTAssertEqual(attempt.wordReviews.map(\.typed), [" b"])
  }

  func testCorrectRetainedBlankCanBeDeletedUnderEveryErrorRecoveryRule() {
    for rules in [InputRules(strictSpace: true, stopOnErrorMode: .word),
      .init(strictSpace: true, stopOnErrorMode: .letter),
      .init(strictSpace: true, deleteOnErrorMode: .letter),
      .init(strictSpace: true, deleteOnErrorMode: .word),
      .init(strictSpace: true, deleteOnErrorMode: .letterHard),
      .init(strictSpace: true, deleteOnErrorMode: .wordHard)] {
      var attempt = quote(rules: rules)
      attempt.insert("ab\n\n", at: start)
      XCTAssertEqual(attempt.typed, "ab\n\n")
      XCTAssertEqual(attempt.nextExpectedCharacter, "\n")
      XCTAssertEqual(attempt.errors, 0)
      attempt.deleteBackward(at: start.addingTimeInterval(1))
      XCTAssertEqual(attempt.typed, "ab\n")
    }
  }

  func testASeparatorWhichDoesNotNavigateCannotFailOnAnEarlierWordsBurst() {
    var attempt = quote(rules: .init(strictSpace: true,
      minimumWordBurstWpm: 100, minimumWordBurstMode: .fixed))
    attempt.insert("a", at: start)
    attempt.insert("b", at: start.addingTimeInterval(1))
    attempt.insertBatch("\n\n", at: start.addingTimeInterval(2))
    XCTAssertEqual(attempt.outcome, .active, "批次最后的保留 LF 没有 increase word index")
    XCTAssertEqual(attempt.completedWordCount, 1)
    XCTAssertEqual(attempt.nextExpectedCharacter, "\n")
  }

  func testFinalBlankCanFinishWithCorrectInputEvenWhenStrictNavigationRetainsIt() throws {
    for difficulty in Difficulty.allCases {
      for completion in [CustomTextCompletion.words, .sections, .finish] {
        var attempt = TestSessionFactory.make(configuration: .init(mode: .custom,
          duration: nil, wordLimit: completion == .words ? 1 : nil,
          difficulty: difficulty, rules: .init(strictSpace: true),
          customTextCompletion: completion, customTextSectionLimit: completion == .sections ? 1 : nil,
          customTextOrdering: .inOrder, customTextPipeDelimiter: true),
          customText: completion == .finish ? "ab | \n" : "\n | bay")
        let target = completion == .finish ? "ab \n" : "\n"
        XCTAssertEqual(attempt.prompt, target)
        attempt.insert(target, at: start)
        XCTAssertEqual(attempt.outcome, .completed, difficulty.rawValue)
        XCTAssertEqual(attempt.errors, 0, difficulty.rawValue)
        XCTAssertEqual(attempt.completedWordCount, completion == .finish ? 2 : 1)
        XCTAssertEqual(try lastReplayEvent(attempt).commitsWord, false, difficulty.rawValue)
        XCTAssertEqual(try XCTUnwrap(attempt.result()).correctCharacterCount, target.count)
      }
    }
  }

  func testFinalBlankQuickEndUsesOneUTF16UnitWithoutNavigation() {
    for input in [" ", "x", "🙂"] {
      var attempt = TestSessionFactory.make(configuration: .init(mode: .custom,
        duration: nil, wordLimit: 1, difficulty: .normal,
        rules: .init(strictSpace: true, quickEnd: true), customTextCompletion: .words,
        customTextOrdering: .inOrder, customTextPipeDelimiter: true), customText: "\n | bay")
      attempt.insertBatch(input, at: start)
      XCTAssertEqual(attempt.outcome, input.utf16.count == 1 ? .completed : .active, input)
      XCTAssertEqual(attempt.errors, 1, input)
      XCTAssertFalse(attempt.wordReviews.allSatisfy(\.isCorrect), input)
      if attempt.isFinished { XCTAssertEqual(attempt.completedWordCount, 1, input) }
    }
  }

  func testCorrectRetainedBlankIsNotReportedAsAnIncorrectWordInResultHistory() {
    for difficulty in Difficulty.allCases {
      for completion in [CustomTextCompletion.words, .sections, .finish] {
        var attempt = TestSessionFactory.make(configuration: .init(mode: .custom,
          duration: nil, wordLimit: completion == .words ? 1 : nil,
          difficulty: difficulty, rules: .init(strictSpace: true),
          customTextCompletion: completion, customTextSectionLimit: completion == .sections ? 1 : nil,
          customTextOrdering: .inOrder, customTextPipeDelimiter: true),
          customText: completion == .finish ? "ab | \n" : "\n | bay")
        attempt.insert(attempt.prompt, at: start)
        XCTAssertEqual(attempt.outcome, .completed)
        XCTAssertEqual(attempt.wordReviews.map(\.typed), attempt.wordReviews.map(\.target))
        XCTAssertTrue(attempt.wordReviews.allSatisfy(\.isCorrect))
        XCTAssertEqual(attempt.errors, 0)
      }
      var interrupted = quote(difficulty: difficulty)
      interrupted.insert("ab\n\n", at: start)
      interrupted.bailOut(at: start.addingTimeInterval(1))
      XCTAssertEqual(interrupted.wordReviews.map(\.typed), ["ab", ""])
      XCTAssertTrue(interrupted.wordReviews.allSatisfy(\.isCorrect))
    }
  }

  func testStrictDifficultyDoesNotRetainAOneLetterNoSpaceCommit() {
    for difficulty in Difficulty.allCases {
      var attempt = TestSessionFactory.make(configuration: .init(mode: .custom,
        duration: nil, wordLimit: nil, difficulty: difficulty, rules: .init(strictSpace: true),
        modifiers: [.noSpaces]), customText: "a b")
      attempt.insert("a", at: start)
      XCTAssertEqual(attempt.completedWordCount, 1)
      XCTAssertEqual(attempt.outcome, .active)
      attempt.insert("b", at: start.addingTimeInterval(1))
      XCTAssertEqual(attempt.outcome, .completed)
      XCTAssertEqual(attempt.completedWordCount, 2)
      XCTAssertEqual(attempt.errors, 0)
    }
  }

  func testRetainedLeadingSpaceKeepsTheLocalUTF16PositionForAUnicodeWord() {
    var attempt = quote("🦉a map")
    attempt.insert(" a ", at: start)
    XCTAssertEqual(attempt.completedWordCount, 1)
    XCTAssertEqual(attempt.errors, 3, "第二字形相同不意味着词内 UTF-16 位置正确")
    XCTAssertEqual(attempt.preciseAccuracy, 0)
    attempt.insert("map", at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.wordReviews.map(\.typed), [" a", "map"])
  }

  func testCorrectRetainedNewlineRendersOnItsTargetNotAsAnExtraError() {
    var attempt = quote()
    attempt.insert("ab\n\n", at: start)
    XCTAssertEqual(attempt.promptGlyphs.count, 6)
    XCTAssertEqual(attempt.promptGlyphs[3].state, .correct)
    XCTAssertEqual(attempt.promptWordPresentations.map(\.phase), [.committed, .active, .future])
    XCTAssertEqual(attempt.promptWordPresentations.map(\.extraGlyphIndices), [[], [], []])
    XCTAssertTrue(attempt.promptWordPresentations.allSatisfy { !$0.hasInputError })
  }

  func testTheSecondBlankNewlineIsAnExtraOfTheSameWordNotAnErrorOnItsFirstCorrectLF() {
    var attempt = quote()
    attempt.insert("ab\n\n", at: start)
    attempt.insert("\n", at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.promptGlyphs.count, 7)
    XCTAssertEqual(attempt.promptGlyphs[3].state, .correct)
    XCTAssertEqual(attempt.promptGlyphs[6].state, .extra)
    XCTAssertEqual(attempt.promptWordPresentations.map(\.extraGlyphIndices), [[], [6], []])
    XCTAssertEqual(attempt.promptWordPresentations.map(\.hasInputError), [false, true, false])
    XCTAssertEqual(attempt.promptWordPresentations.map(\.phase), [.committed, .committed, .active])
  }

  func testStoppedSpaceStaysExtraWhileTheVisibleLFCanMatchItsTarget() {
    for separator in [" ", "\n"] {
      var attempt = quote("ab" + separator + "cd", rules: .init(stopOnErrorMode: .word))
      attempt.insert("xb" + separator, at: start)
      XCTAssertEqual(attempt.completedWordCount, 0)
      XCTAssertEqual(attempt.nextExpectedCharacter, Character(separator))
      XCTAssertEqual(attempt.promptGlyphs.count, separator == " " ? 6 : 5)
      XCTAssertEqual(attempt.promptGlyphs[2].state, separator == " " ? .current : .correct)
      XCTAssertEqual(attempt.promptWordPresentations.map(\.extraGlyphIndices),
        separator == " " ? [[5], []] : [[], []])
      if separator == " " { XCTAssertEqual(attempt.promptGlyphs.last?.state, .extra) }
    }
  }
}
