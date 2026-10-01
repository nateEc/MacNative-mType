import XCTest
@testable import Typebar

final class PipeGeneratedQueueCompletionTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 810_000_000)
  private func session(_ source: String, limit: Int = 1, rules: InputRules = .init(),
    completion: CustomTextCompletion = .words) -> TypingSession {
    TestSessionFactory.make(configuration: .init(mode: .custom, duration: nil,
      wordLimit: completion == .words ? limit : nil, difficulty: .normal, rules: rules,
      customTextCompletion: completion,
      customTextSectionLimit: completion == .sections ? limit : nil,
      customTextOrdering: .inOrder, customTextPipeDelimiter: true), customText: source)
  }

  func testWholeInitialQueueMustBeTypedBeforeCompletionAndSurvivesPortableRepeat() throws {
    var attempt = session("ash bay | elm fog", limit: 3)
    XCTAssertEqual(attempt.prompt, "ash bay elm fog ash bay")
    attempt.insertBatch("ash bay elm", at: start)
    XCTAssertEqual(attempt.outcome, .active, "设置词数不是预生成队列的最后一个词")
    attempt.insertBatch(" fog ash bay", at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.completedWordCount, 6)
    XCTAssertEqual(attempt.errors, 0)
    let result = try XCTUnwrap(attempt.result())
    XCTAssertEqual(result.configuration.wordLimit, 3, "不改写保存的用户设置")
    XCTAssertEqual(attempt.wordReviews.count, 6)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 1), attempt.prompt)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from:
      TypebarDataTransfer.exportArchive(settings: .init(), results: [result], presets: [], at: start)).results, [result])
    var repeated = attempt.repeatedAttempt()
    XCTAssertEqual(repeated.prompt, attempt.prompt)
    repeated.insertBatch("ash bay elm", at: start)
    XCTAssertFalse(repeated.isFinished)
    repeated.insertBatch(" fog ash bay", at: start.addingTimeInterval(1))
    XCTAssertEqual(repeated.outcome, .completed)
  }

  func testQuickEndUsesTheFinalGeneratedWordInsteadOfTheConfiguredBudget() {
    var attempt = session("seed ab | c", rules: .init(quickEnd: true))
    attempt.insertBatch("seed", at: start)
    XCTAssertFalse(attempt.isFinished)
    attempt.insertBatch(" 🙂", at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.typed, "seed 🙂")
    XCTAssertEqual(attempt.errors, 1)
    XCTAssertEqual(attempt.completedWordCount, 2)
  }

  func testWordStopStillRequiresCorrectionOfTheFinalGeneratedWord() {
    var attempt = session("ash bay | c", rules: .init(stopOnErrorMode: .word, quickEnd: true))
    attempt.insertBatch("ash bx ", at: start)
    XCTAssertFalse(attempt.isFinished)
    attempt.deleteBackward(at: start.addingTimeInterval(1))
    attempt.deleteBackward(at: start.addingTimeInterval(1))
    attempt.insert("ay", at: start.addingTimeInterval(2))
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.errors, 0)
    XCTAssertEqual(attempt.wordReviews.map(\.hasInputError), [false, true])
  }

  func testInteriorBlankSlotBelongsToTheWholeGeneratedQueue() {
    var attempt = session("ash\n\n bay | c")
    XCTAssertEqual(attempt.prompt, "ash\n\nbay")
    attempt.insertBatch("ash\n", at: start)
    XCTAssertFalse(attempt.isFinished)
    attempt.insert("\n", at: start.addingTimeInterval(1))
    XCTAssertFalse(attempt.isFinished)
    attempt.insert("bay", at: start.addingTimeInterval(2))
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.completedWordCount, 3)
    XCTAssertEqual(attempt.wordReviews.map(\.target), ["ash", "", "bay"])
    XCTAssertEqual(attempt.errors, 0)
  }

  func testFinalBlankSlotRetainsItsCommitAndCannotBeSkipped() {
    for completion in [CustomTextCompletion.words, .sections, .finish] {
      // Finish consumes both sections; the other modes consume the first.
      let source = completion == .finish ? "ash | bay\n\n" : "ash\n\n | bay"
      var attempt = session(source, completion: completion)
      let prefix = completion == .finish ? "ash bay\n" : "ash\n"
      XCTAssertEqual(attempt.prompt, prefix + "\n", completion.rawValue)
      attempt.insertBatch(prefix, at: start)
      XCTAssertFalse(attempt.isFinished, completion.rawValue)
      attempt.insert("\n", at: start.addingTimeInterval(1))
      XCTAssertEqual(attempt.outcome, .completed, completion.rawValue)
      XCTAssertEqual(attempt.wordReviews.last?.target, "", completion.rawValue)
      XCTAssertTrue(attempt.wordReviews.last?.isCorrect == true, completion.rawValue)
      XCTAssertEqual(attempt.errors, 0, completion.rawValue)
    }
  }

  func testAnAllBlankFirstSectionIsNotAnEmptyPrompt() {
    var attempt = session("\n | bay")
    XCTAssertEqual(attempt.prompt, "\n")
    XCTAssertFalse(attempt.isFinished)
    attempt.insert("\n", at: start)
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.completedWordCount, 1)
    XCTAssertEqual(attempt.wordReviews.map(\.target), [""])
  }

  func testBlankAtTheHundredWordChunkEdgeContinuesToTheActualFinalWord() {
    let words = (0..<99).map { "unit\($0)" }
    let opening = words.joined(separator: " ") + "\n\n"
    var attempt = session(opening + " bay | c", limit: 101)
    XCTAssertEqual(attempt.prompt, opening)
    attempt.insertBatch(opening, at: start)
    XCTAssertFalse(attempt.isFinished)
    XCTAssertEqual(attempt.completedWordCount, 100)
    attempt.insert("bay", at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.prompt, opening + "bay", "续批在下一次输入前生成")
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.completedWordCount, 101)
    XCTAssertEqual(attempt.wordReviews.map(\.target), words + ["", "bay"])
    XCTAssertEqual(attempt.errors, 0)
    var repeated = attempt.repeatedAttempt()
    XCTAssertEqual(repeated.prompt, opening)
    repeated.insertBatch(opening + "bay", at: start)
    XCTAssertEqual(repeated.outcome, .completed)
  }

  func testInitialPrefetchHardCapRatherThanBudgetIsTheFinalQueue() {
    let words = (0..<120).map { "unit\($0)" }
    var attempt = session(words.joined(separator: " ") + " | bay", limit: 3)
    XCTAssertEqual(attempt.prompt, words.prefix(100).joined(separator: " "))
    attempt.insertBatch(words.prefix(3).joined(separator: " "), at: start)
    XCTAssertFalse(attempt.isFinished)
    attempt.insertBatch(" " + words.dropFirst(3).prefix(97).joined(separator: " "), at: start)
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.completedWordCount, 100)
    XCTAssertEqual(attempt.errors, 0)
  }

  func testInfinitePipeWordModeDoesNotFinishOnBlankSlots() {
    var attempt = session("ash\n\n bay | c", limit: 0)
    attempt.insertBatch("ash\n\nbay c ", at: start)
    XCTAssertEqual(attempt.outcome, .active)
    XCTAssertEqual(attempt.completedWordCount, 4)
    XCTAssertEqual(attempt.errors, 0)
    attempt.bailOut(at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.outcome, .bailedOut)
  }
}
