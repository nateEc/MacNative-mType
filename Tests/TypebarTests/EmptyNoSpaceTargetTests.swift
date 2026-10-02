import Foundation
import XCTest
@testable import Typebar

final class EmptyNoSpaceTargetTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 870_100_000)
  private func attempt(_ source: String, completion: CustomTextCompletion = .finish,
    rules: InputRules = .init(), difficulty: Difficulty = .normal, pipe: Bool = false,
    limit: Int = 3) -> TypingSession {
    TestSessionFactory.make(configuration: .init(mode: .custom,
      duration: completion == .time ? 10 : nil,
      wordLimit: completion == .words ? limit : nil, difficulty: difficulty, rules: rules,
      customTextCompletion: completion, customTextSectionLimit: limit,
      customTextOrdering: .inOrder, customTextPipeDelimiter: pipe, modifiers: [.morseStream]),
      customText: source)
  }

  func testCapturedBatchRetainsEmptyWordWithoutInventingAGlyph() {
    let batch = TestModifierPolicy.transformedBatch("e 中 t", modifiers: [.morseStream])
    XCTAssertEqual(batch.text, "./-/")
    XCTAssertEqual(batch.noSpaceTargetWords, ["./", "", "-/"])
    XCTAssertEqual(batch.noSpaceWordLengths, [2, 0, 2])
  }

  func testLeadingEmptyWordCannotBeSkippedOrScoreFutureLetters() {
    var session = attempt("中 e")
    XCTAssertEqual(session.prompt, "./")
    XCTAssertEqual(session.completedWordCount, 0)
    XCTAssertNil(session.nextExpectedCharacter)
    session.insertBatch("./", at: start)
    XCTAssertEqual(session.typed, "./")
    XCTAssertEqual(session.outcome, .active)
    XCTAssertEqual(session.completedWordCount, 0)
    XCTAssertEqual(session.wpm(at: start.addingTimeInterval(1)), 0)
    XCTAssertEqual(session.errors, 2)
    XCTAssertEqual(session.wordReviews.map(\.target), [""])
    XCTAssertEqual(session.wordReviews.map(\.typed), ["./"])
  }

  func testInteriorEmptyWordOwnsExtrasAndCannotCompleteTheFiniteQueue() {
    var session = attempt("e 中 t")
    session.insertBatch("./", at: start)
    XCTAssertEqual(session.completedWordCount, 1)
    XCTAssertNil(session.nextExpectedCharacter)
    session.insertBatch("-/", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .active)
    XCTAssertEqual(session.completedWordCount, 1)
    XCTAssertEqual(session.errors, 2)
    XCTAssertEqual(session.wordReviews.map(\.target), ["./", ""])
    XCTAssertEqual(session.wordReviews.map(\.typed), ["./", "-/"])
    XCTAssertEqual(session.wpm(at: start.addingTimeInterval(1)), 24)
  }

  func testTrailingEmptyWordAndAllEmptyPromptStayActiveUntilBailout() {
    for source in ["e 中", "中 Ａ"] {
      var session = attempt(source)
      session.insertBatch("./", at: start)
      XCTAssertEqual(session.outcome, .active, source)
      XCTAssertNil(session.nextExpectedCharacter)
      session.bailOut(at: start.addingTimeInterval(1))
      XCTAssertEqual(session.outcome, .bailedOut)
      let repeated = session.repeatedAttempt()
      XCTAssertEqual(repeated.prompt, session.prompt)
      XCTAssertEqual(repeated.completedWordCount, 0)
      XCTAssertEqual(repeated.typed, "")
    }
  }

  func testEmptyFieldAcceptsOnlyTwentyUTF16UnitsAndRejectsSeparators() {
    var session = attempt("中 e")
    session.insertBatch(" \u{3000}\n", at: start)
    XCTAssertFalse(session.hasStarted)
    session.insertBatch(String(repeating: ".", count: 25), at: start)
    XCTAssertEqual(session.typed, String(repeating: ".", count: 20))
    XCTAssertEqual(session.errors, 20)
    XCTAssertEqual(session.completedWordCount, 0)
  }

  func testTimedEmptyFieldFinishesOnlyOnTheClock() throws {
    var session = attempt("中 e", completion: .time)
    let opening = session.prompt
    session.insertBatch("./", at: start)
    XCTAssertEqual(session.outcome, .active)
    XCTAssertEqual(session.completedWordCount, 0)
    XCTAssertEqual(session.prompt, opening)
    for second in 1...9 { session.insert(".", at: start.addingTimeInterval(Double(second))) }
    session.tick(at: start.addingTimeInterval(10))
    XCTAssertEqual(session.outcome, .completed)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.correctCharacterCount, 0)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 10), "./" + String(repeating: ".", count: 9))
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
  }

  func testEmptySectionsAreNotCreditedAtADuplicateCharacterEnd() {
    for (source, pipe) in [("e 中 t", false), ("e | 中 | t", true), ("e 中 | t", true)] {
      var session = attempt(source, completion: .sections, pipe: pipe, limit: pipe ? 2 : 3)
      session.insertBatch("./", at: start)
      XCTAssertEqual(session.sectionProgress?.completed, source == "e 中 | t" ? 0 : 1, source)
      session.insertBatch("-/", at: start.addingTimeInterval(1))
      XCTAssertEqual(session.sectionProgress?.completed, source == "e 中 | t" ? 0 : 1, source)
      XCTAssertEqual(session.outcome, .active, source)
    }
  }

  func testSoftDeleteOnErrorDoesNotDeleteThePreviousCommittedWord() {
    for mode in [DeleteOnErrorMode.letter, .word] {
      var session = attempt("e 中 t", rules: .init(deleteOnErrorMode: mode))
      session.insertBatch("./", at: start)
      session.insert("-", at: start.addingTimeInterval(1))
      XCTAssertEqual(session.typed, "./", mode.rawValue)
      XCTAssertEqual(session.completedWordCount, 1)
      XCTAssertEqual(session.wordReviews.map(\.target), ["./", ""])
      XCTAssertEqual(session.wordReviews.last?.hasInputError, true)
    }
  }

  func testHardDeleteOnErrorReopensThePreviousWord() {
    for (mode, restored) in [(DeleteOnErrorMode.letterHard, "."), (.wordHard, "")] {
      var session = attempt("e 中 t", rules: .init(deleteOnErrorMode: mode))
      session.insertBatch("./", at: start)
      session.insert("-", at: start.addingTimeInterval(1))
      XCTAssertEqual(session.typed, restored, mode.rawValue)
      XCTAssertEqual(session.completedWordCount, 0)
      XCTAssertEqual(session.outcome, .active)
    }
  }

  func testLetterStopRejectsButWordStopRetainsUncommittableErrors() {
    for (mode, retained) in [(StopOnErrorMode.letter, "./"), (.word, "./-")] {
      var session = attempt("e 中 t", rules: .init(stopOnErrorMode: mode))
      session.insertBatch("./", at: start)
      session.insert("-", at: start.addingTimeInterval(1))
      XCTAssertEqual(session.typed, retained, mode.rawValue)
      XCTAssertEqual(session.completedWordCount, 1)
      XCTAssertEqual(session.wordReviews.map(\.target), ["./", ""])
    }
  }

  func testMasterFailsOnEmptyFieldErrorButExpertDoesNotCommitIt() {
    for difficulty in [Difficulty.master, .expert] {
      var session = attempt("e 中 t", difficulty: difficulty)
      session.insertBatch("./", at: start)
      session.insert("-", at: start.addingTimeInterval(1))
      XCTAssertEqual(session.outcome, difficulty == .master ? .failed : .active)
      XCTAssertEqual(session.completedWordCount, 1)
    }
  }

  func testManualDeletionClearsOnlyTheEmptyFieldThenRespectsPriorWordProtection() {
    var session = attempt("e 中 t")
    session.insertBatch("./--", at: start)
    session.deleteWordBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "./")
    session.deleteBackward(at: start.addingTimeInterval(2))
    XCTAssertEqual(session.typed, "./")
    var free = attempt("e 中 t", rules: .init(freedomMode: true))
    free.insertBatch("./--", at: start)
    free.deleteWordBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(free.typed, "./")
    free.deleteBackward(at: start.addingTimeInterval(2))
    XCTAssertEqual(free.typed, ".")
    XCTAssertEqual(free.nextExpectedCharacter, "/")
    free.insert("/", at: start.addingTimeInterval(3))
    XCTAssertNil(free.nextExpectedCharacter)
  }

  func testInputHistoryNeverAssignsEmptyFieldExtrasToTheFutureWord() {
    var session = attempt("e 中 t")
    session.insertBatch("./", at: start)
    XCTAssertEqual(session.savedTextProgressWordCount, 1)
    session.insertBatch("-/", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.savedTextProgressWordCount, 2)
    session.deleteWordBackward(at: start.addingTimeInterval(2))
    XCTAssertEqual(session.savedTextProgressWordCount, 2)
    XCTAssertEqual(session.typed, "./")
  }

  func testEmptyTargetInNextHundredWordChunkDoesNotDisappear() {
    let prefix = Array(repeating: "e", count: 100).joined(separator: " ")
    var session = attempt(prefix + " 中 t", completion: .words, limit: 102)
    session.insertBatch(String(repeating: "./", count: 100), at: start)
    XCTAssertEqual(session.completedWordCount, 100)
    XCTAssertEqual(session.outcome, .active)
    XCTAssertNil(session.nextExpectedCharacter)
    let reached = session.prompt
    session.insertBatch("-/", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.completedWordCount, 100)
    XCTAssertEqual(session.outcome, .active)
    XCTAssertEqual(session.prompt, reached)
    XCTAssertEqual(session.wordReviews.last?.target, "")
    XCTAssertEqual(session.wordReviews.last?.typed, "-/")
  }

  func testSeveralEmptyTargetsStopAtTheFirstAndDoNotInventVisitedHistory() {
    var session = attempt("e 中 Ａ t")
    session.insertBatch("./--", at: start)
    XCTAssertEqual(session.completedWordCount, 1)
    XCTAssertEqual(session.wordReviews.map(\.target), ["./", ""])
    XCTAssertEqual(session.savedTextProgressWordCount, 2)
    XCTAssertEqual(session.outcome, .active)
  }

  func testAllEmptyInitialChunkDoesNotAutoPrefetchPastItsHundredCandidates() {
    let source = Array(repeating: "中", count: 100).joined(separator: " ") + " e"
    var session = attempt(source, completion: .words, limit: 101)
    XCTAssertEqual(session.prompt, "")
    session.insert(".", at: start)
    XCTAssertEqual(session.prompt, "")
    XCTAssertEqual(session.completedWordCount, 0)
    XCTAssertEqual(session.savedTextProgressWordCount, 1)
    XCTAssertEqual(session.wordReviews.map(\.typed), ["."])
    XCTAssertEqual(session.outcome, .active)
    XCTAssertEqual(session.repeatedAttempt().prompt, "")
  }

  func testDeletedEmptyFieldAttemptStillBelongsToThatWordAndReplays() throws {
    var session = attempt("e 中 t", rules: .init(deleteOnErrorMode: .word))
    session.insertBatch("./", at: start)
    session.insert("-", at: start.addingTimeInterval(1))
    session.bailOut(at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 2), "./")
    XCTAssertEqual(session.wordReviews.last, .init(index: 1, target: "", typed: "", hasInputError: true))
    XCTAssertEqual(session.savedTextProgressWordCount, 2)
    XCTAssertEqual(result.correctCharacterCount, 2)
    XCTAssertEqual(result.errorCount, 0)
    XCTAssertLessThan(result.accuracy, 100)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
  }

  func testCompositionCannotConfirmAnEmptyWordUsingLaterVisibleTargets() {
    var session = attempt("e 中 t")
    session.insertBatch("./", at: start)
    XCTAssertFalse(session.shouldFinishWithComposition("-/", at: start.addingTimeInterval(1)))
    XCTAssertEqual(session.completedWordCount, 1)
    XCTAssertEqual(session.typed, "./")
  }

  func testWrongPreviousWordMayBeReopenedButEmptyExtrasNeverEarnWordCredit() {
    var session = attempt("e 中 t")
    session.insertBatch("--", at: start)
    XCTAssertEqual(session.completedWordCount, 1)
    session.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "-")
    session.insert("/", at: start.addingTimeInterval(2))
    session.insertBatch("-/", at: start.addingTimeInterval(3))
    XCTAssertEqual(session.wpm(at: start.addingTimeInterval(4)), 0)
    XCTAssertEqual(session.completedWordCount, 1)
    XCTAssertEqual(session.wordReviews.map(\.typed), ["-/", "-/"])
  }

  func testEmptyWordOwnsPresentationErrorsWhileLaterWordsStayFuture() {
    var session = attempt("e 中 t")
    session.insertBatch("./--", at: start)
    let words = session.promptWordPresentations
    XCTAssertEqual(words.map(\.phase), [.committed, .active, .future])
    XCTAssertEqual(words.map(\.hasInputError), [false, true, false])
    XCTAssertEqual(words[1].range, 2..<2)
    XCTAssertEqual(words[1].extraGlyphIndices, [4, 5])
    XCTAssertFalse(session.promptGlyphs.contains { $0.state == .current })
    XCTAssertEqual(session.promptGlyphs[2].state, .pending)
  }

  func testLeadingEmptyWordIsActiveAndFollowingEmptyWordIsNotCommitted() {
    let session = attempt("中 Ａ e")
    XCTAssertEqual(session.promptWordPresentations.map(\.phase), [.active, .future, .future])
    XCTAssertFalse(session.promptGlyphs.contains { $0.state == .current })
    XCTAssertEqual(session.promptWordPresentations.map(\.range), [0..<0, 0..<0, 0..<2])
  }
}
