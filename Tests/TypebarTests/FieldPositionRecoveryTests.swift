import AppKit
import XCTest
@testable import Typebar

final class FieldPositionRecoveryTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 907_200_000)

  func testStoppedLetterAtReturnMarksTheReturnSlotRatherThanAnExtra() {
    var session = TypingSession(configuration: .words(2,
      rules: .init(stopOnErrorMode: .letter)), prompt: "ab\ncd")
    session.insertBatch("ab", at: start)
    session.insertBatch("x", at: start.addingTimeInterval(0.2))
    XCTAssertEqual(session.typed, "ab")
    XCTAssertEqual(session.promptGlyphs.count, 5)
    XCTAssertEqual(session.promptGlyphs[2].state, .incorrect)
    XCTAssertEqual(session.promptGlyphs[2].typedCharacter, "x")
    XCTAssertEqual(session.promptCaretGlyphIndex, 2)
    XCTAssertEqual(session.promptWordPresentations[0].extraGlyphIndices, [])
  }

  func testRepeatedRetainedReturnTriggersRuntimeLetterRecoveryWithoutCommitting() {
    var session = TypingSession(configuration: .words(2,
      rules: .init(stopOnErrorMode: .word)), prompt: "ab\ncd")
    session.insertBatch("ax\n", at: start)
    session.synchronizeLiveInputRules(.init(deleteOnErrorMode: .letter))
    XCTAssertEqual(session.insertBatch("\n", at: start.addingTimeInterval(0.2)), [false])
    XCTAssertEqual(session.typed, "ax")
    XCTAssertEqual(session.completedWordCount, 0)
    XCTAssertEqual(session.outcome, .active)
  }

  func testLetterRecoveryAlsoDeletesAPreviousUncommittedTab() {
    var session = TypingSession(configuration: .words(2,
      rules: .init(deleteOnErrorMode: .letter), language: .codeSwift), prompt: "a\tb tail")
    session.insertBatch("a\t", at: start)
    session.insertBatch("x", at: start.addingTimeInterval(0.2))
    XCTAssertEqual(session.typed, "a")
    XCTAssertEqual(session.nextExpectedCharacter, "\t")
    XCTAssertEqual(session.completedWordCount, 0)
  }

  func testRecoverySeparatorDoesNotInventACommitOrAnEmptyFutureHistoryField() throws {
    var session = TypingSession(configuration: .words(2,
      rules: .init(stopOnErrorMode: .word)), prompt: "ab\ncd")
    session.insertBatch("ax\n", at: start)
    session.synchronizeLiveInputRules(.init(deleteOnErrorMode: .letter))
    session.insertBatch("\n", at: start.addingTimeInterval(0.2))
    session.bailOut(at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.replayEvents[3].commitsWord, false)
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: result.replayEvents), ["ax"])
    XCTAssertEqual(result.replayEvents.suffix(2).map(\.automatic), [true, true])
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 1), "ax")
  }

  func testStoppedLetterAtAnEmptyReturnFieldDoesNotMarkTheLaterWord() {
    var session = TypingSession(configuration: .words(2,
      rules: .init(stopOnErrorMode: .letter)), prompt: "\ncd")
    session.insertBatch("x", at: start)
    XCTAssertEqual(session.promptGlyphs.count, 3)
    XCTAssertEqual(session.promptGlyphs[0].state, .incorrect)
    XCTAssertEqual(session.promptGlyphs[0].typedCharacter, "x")
    XCTAssertEqual(session.promptCaretGlyphIndex, 0)
    XCTAssertEqual(session.typed, "")
    XCTAssertEqual(session.completedWordCount, 0)
  }

  func testStrictSpaceAtAnEmptyReturnStillOccupiesItsVisibleReturnSlot() {
    for difficulty in [Difficulty.normal, .expert] {
      var session = TypingSession(configuration: .words(2, difficulty: difficulty,
        rules: .init(strictSpace: true, stopOnErrorMode: .letter)), prompt: "\ncd")
      session.insertBatch(" ", at: start)
      XCTAssertEqual(session.promptGlyphs.count, 3)
      XCTAssertEqual(session.promptGlyphs[0].state, .incorrect)
      XCTAssertEqual(session.promptGlyphs[0].typedCharacter, " ")
      XCTAssertEqual(session.promptCaretGlyphIndex, 0)
      XCTAssertEqual(session.typed, "")
      XCTAssertEqual(session.outcome, .active)
    }
  }

  func testSpaceCommitAndReturnDisplaySlotKeepDifferentStoppedOwnership() {
    for separator: Character in [" ", "\n"] {
      var session = TypingSession(configuration: .words(2,
        rules: .init(stopOnErrorMode: .letter)), prompt: "ab" + String(separator) + "cd")
      session.insertBatch("abx", at: start)
      XCTAssertEqual(session.promptGlyphs.count, separator == "\n" ? 5 : 6)
      XCTAssertEqual(session.promptGlyphs[2].state, separator == "\n" ? .incorrect : .current)
      XCTAssertEqual(session.typed, "ab")
    }
  }

  func testCorrectReturnClearsTheStoppedDisplayAndCommitsTheActualCorrectField() throws {
    var session = TypingSession(configuration: .words(2,
      rules: .init(stopOnErrorMode: .letter)), prompt: "ab\ncd")
    session.insertBatch("abx", at: start)
    session.insertBatch("\ncd", at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(session.typed, "ab\ncd")
    XCTAssertEqual(session.promptGlyphs.count, 5)
    XCTAssertTrue(session.promptGlyphs.allSatisfy { $0.state == .correct })
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 6)
    XCTAssertEqual(result.inputMetrics?.correctAttempts, 5)
    XCTAssertEqual(result.replayEvents.filter(\.isStoppedInsertion).map(\.text), ["x"])
  }

  func testBlindAndOppositeShiftDoNotCreateAStoppedReturnOverride() {
    for rules in [InputRules(stopOnErrorMode: .letter, blindMode: true),
      .init(stopOnErrorMode: .letter, oppositeShiftMode: .on)]
    {
      var session = TypingSession(configuration: .words(2, rules: rules), prompt: "ab\ncd")
      session.insertBatch("ab", at: start)
      session.insertBatch("x", forceError: rules.oppositeShiftMode != .off, at: start)
      XCTAssertEqual(session.promptGlyphs.count, 5)
      XCTAssertEqual(session.promptGlyphs[2].state, .current)
      XCTAssertNil(session.promptGlyphs[2].typedCharacter)
      XCTAssertEqual(session.typed, "ab")
    }
  }

  func testTerminalStoppedReturnStillRecordsItsAttemptWithoutACaret() throws {
    var session = TypingSession(configuration: .words(2, difficulty: .master,
      rules: .init(stopOnErrorMode: .letter)), prompt: "ab\ncd")
    session.insertBatch("ab", at: start)
    session.insertBatch("x", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .failed)
    XCTAssertNil(session.promptCaretGlyphIndex)
    XCTAssertEqual(session.promptGlyphs[2].state, .incorrect)
    XCTAssertEqual(try XCTUnwrap(session.result()).replayEvents.last?.inputStopped, true)
  }

  func testCorrectRetainedReturnIsJudgedCorrectBeforeRuntimeRecoveryIsEnabled() {
    var session = TypingSession(configuration: .words(2,
      rules: .init(stopOnErrorMode: .word)), prompt: "ab\ncd")
    session.insertBatch("ax", at: start)
    XCTAssertEqual(session.insertBatch("\n", at: start), [true])
    XCTAssertEqual(session.typed, "ax\n")
    XCTAssertEqual(session.completedWordCount, 0)
    XCTAssertEqual(session.promptGlyphs[2].state, .correct)
  }

  func testAllRuntimeRecoveryModesUseFieldPositionAndDoNotSubmitRepeatedReturn() {
    for mode in [DeleteOnErrorMode.letter, .letterHard, .word, .wordHard] {
      var session = TypingSession(configuration: .words(2,
        rules: .init(stopOnErrorMode: .word)), prompt: "ab\ncd")
      session.insertBatch("ax\n", at: start)
      session.synchronizeLiveInputRules(.init(deleteOnErrorMode: mode))
      XCTAssertEqual(session.insertBatch("\n", at: start), [false], mode.rawValue)
      XCTAssertEqual(session.typed, mode.clearsWholeWord ? "" : "ax", mode.rawValue)
      XCTAssertEqual(session.completedWordCount, 0)
      XCTAssertEqual(session.outcome, .active)
    }
  }

  func testRecoveryOfRetainedWhitespaceCannotCrossAnAlreadyCommittedWord() {
    for mode in [DeleteOnErrorMode.letter, .letterHard, .word, .wordHard] {
      var session = TypingSession(configuration: .words(3,
        rules: .init(stopOnErrorMode: .word)), prompt: "pre ab\ncd")
      session.insertBatch("pre ax\n", at: start)
      session.synchronizeLiveInputRules(.init(deleteOnErrorMode: mode))
      session.insertBatch("\n", at: start)
      XCTAssertEqual(session.typed, mode.clearsWholeWord ? "pre " : "pre ax")
      XCTAssertEqual(session.completedWordCount, 1)
    }
  }

  func testOrdinaryLetterRecoveryCannotDeleteAPreviousCommittedSeparator() {
    var session = TypingSession(configuration: .words(2,
      rules: .init(deleteOnErrorMode: .letter)), prompt: "pre ab")
    session.insertBatch("pre ", at: start)
    session.insertBatch("x", at: start)
    XCTAssertEqual(session.typed, "pre ")
    XCTAssertEqual(session.completedWordCount, 1)
    XCTAssertEqual(session.nextExpectedCharacter, "a")
  }

  func testLetterRecoveryDeletesRetainedSpaceAsFieldTextRatherThanAWordCommit() {
    var session = TypingSession(configuration: .words(2,
      rules: .init(stopOnErrorMode: .word)), prompt: "ab cd")
    session.insertBatch("ax ", at: start)
    session.synchronizeLiveInputRules(.init(deleteOnErrorMode: .letter))
    session.insertBatch("b", at: start)
    XCTAssertEqual(session.typed, "ax")
    XCTAssertEqual(session.completedWordCount, 0)
  }

  func testOnlyThePreviousRetainedReturnIsRemovedAndAttemptAccuracySurvives() throws {
    var session = TypingSession(configuration: .words(2,
      rules: .init(stopOnErrorMode: .word)), prompt: "ab\ncd")
    session.insertBatch("ax\n\n", at: start)
    session.synchronizeLiveInputRules(.init(deleteOnErrorMode: .letter))
    session.insertBatch("\n", at: start)
    XCTAssertEqual(session.typed, "ax\n")
    session.bailOut(at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 5)
    XCTAssertEqual(result.preciseAccuracy, 40)
    XCTAssertEqual(result.replayEvents.suffix(2).map(\.kind), [.delete, .delete])
  }

  func testManualCorrectionAfterRecoveryCanFinishWithoutLostWordBoundaries() throws {
    var session = TypingSession(configuration: .words(2,
      rules: .init(stopOnErrorMode: .word)), prompt: "ab\ncd")
    session.insertBatch("ax\n", at: start)
    session.synchronizeLiveInputRules(.init(deleteOnErrorMode: .letter))
    session.insertBatch("\n", at: start)
    session.deleteBackward(at: start)
    session.insertBatch("b\ncd", at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(session.typed, "ab\ncd")
    XCTAssertEqual(result.outcome, .completed)
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 8)
    XCTAssertEqual(result.preciseAccuracy, 75)
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: result.replayEvents), ["ab\n", "cd"])
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 1), session.typed)
  }

  @MainActor func testSharedNativeInsertionBridgeUsesTheSameRecoveryRules() {
    var session = TypingSession(configuration: .words(2,
      rules: .init(stopOnErrorMode: .word)), prompt: "ab\ncd")
    let input = TypingInputView(frame: .zero)
    input.acceptsNewlineInput = true
    input.onInsert = { text, forced in
      _ = TypingLiveInputFeedback.insertBatch(text, into: &session, forceError: forced, at: self.start)
    }
    input.insertText("ax\n", replacementRange: .init())
    session.synchronizeLiveInputRules(.init(deleteOnErrorMode: .letter))
    input.insertText("\n", replacementRange: .init())
    XCTAssertEqual(session.typed, "ax")
    XCTAssertEqual(session.completedWordCount, 0)
  }

  func testRecoveryNoCommitMarkerRoundTripsWithoutRewritingLegacyEvents() throws {
    var session = TypingSession(configuration: .words(2,
      rules: .init(stopOnErrorMode: .word)), prompt: "ab\ncd")
    session.insertBatch("ax\n", at: start)
    session.synchronizeLiveInputRules(.init(deleteOnErrorMode: .word))
    session.insertBatch("\n", at: start)
    session.bailOut(at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [], at: start))
    XCTAssertEqual(archive.version, TypebarArchive.currentVersion)
    XCTAssertEqual(archive.results, [result])
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
    let legacy = try JSONDecoder().decode(TypingReplayEvent.self,
      from: Data(#"{"offset":0,"kind":"insert","text":"\n"}"#.utf8))
    XCTAssertNil(legacy.commitsWord)
    XCTAssertEqual(TypingReplay.typedText(events: [legacy], through: 1), "\n")
    XCTAssertEqual(result.replayEvents[3].commitsWord, false)
  }
}
