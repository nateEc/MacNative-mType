import AppKit
import XCTest
@testable import Typebar

final class RecoveryDifficultyTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 907_200_000)
  private let modes: [DeleteOnErrorMode] = [.letter, .letterHard, .word, .wordHard]

  func testMasterStillFailsAfterEachRecoveryModeDeletesTheWrongAttempt() {
    for mode in modes {
      var input = TypingSession(configuration: .words(2, difficulty: .master,
        rules: .init(deleteOnErrorMode: mode)), prompt: "abc tail")
      input.insertBatch("ab", at: start)
      XCTAssertEqual(input.insertBatch("x", at: start.addingTimeInterval(1)), [false])
      XCTAssertEqual(input.typed, mode.clearsWholeWord ? "" : "a", mode.rawValue)
      XCTAssertEqual(input.outcome, .failed, mode.rawValue)
    }
  }

  func testExpertJudgesPrematureSeparatorBeforeRecoveryClearsItsField() {
    for mode in modes {
      var input = TypingSession(configuration: .words(2, difficulty: .expert,
        rules: .init(deleteOnErrorMode: mode)), prompt: "ab tail")
      input.insertBatch("a", at: start)
      XCTAssertEqual(input.insertBatch(" ", at: start.addingTimeInterval(1)), [false])
      XCTAssertEqual(input.typed, "", mode.rawValue)
      XCTAssertEqual(input.completedWordCount, 0)
      XCTAssertEqual(input.outcome, .failed, mode.rawValue)
    }
  }

  func testNoSpaceExpertJudgesWrongWordEndEvenThoughRecoveryRewindsIt() {
    for mode in modes {
      var input = TypingSession(configuration: .words(2, difficulty: .expert,
        rules: .init(deleteOnErrorMode: mode)).with(modifiers: [.noSpaces]),
        prompt: "abcd", noSpaceWordEndIndices: [2, 4], noSpaceTargetWords: ["ab", "cd"])
      input.insertBatch("a", at: start)
      XCTAssertEqual(input.insertBatch("x", at: start.addingTimeInterval(1)), [false])
      XCTAssertEqual(input.typed, "", mode.rawValue)
      XCTAssertEqual(input.completedWordCount, 0)
      XCTAssertEqual(input.outcome, .failed, mode.rawValue)
    }
  }

  func testMasterFirstKeyRecoveryStillProducesAFailedEmptyResult() throws {
    for mode in modes {
      var input = TypingSession(configuration: .words(2, difficulty: .master,
        rules: .init(deleteOnErrorMode: mode)), prompt: "ab tail")
      input.insertBatch("x", at: start)
      let result = try XCTUnwrap(input.result())
      XCTAssertEqual(result.outcome, .failed)
      XCTAssertEqual(result.finishedAt, start)
      XCTAssertEqual(result.typedCharacterCount, 0)
      XCTAssertEqual(result.inputMetrics?.totalAttempts, 1)
      XCTAssertEqual(result.inputMetrics?.correctAttempts, 0)
      XCTAssertEqual(result.replayEvents.map(\.kind), [.insert, .delete])
      XCTAssertEqual(result.replayEvents.map(\.automatic), [false, true])
      XCTAssertTrue(result.replayEvents.allSatisfy { !$0.isStoppedInsertion })
    }
  }

  func testHardRecoveryRewindsPreviousWordBeforePublishingMasterFailure() throws {
    for mode in modes {
      var input = TypingSession(configuration: .words(2, difficulty: .master,
        rules: .init(deleteOnErrorMode: mode)), prompt: "pre ab")
      input.insertBatch("pre ", at: start)
      input.insertBatch("x", at: start.addingTimeInterval(1))
      let result = try XCTUnwrap(input.result())
      let expected = mode == .letterHard ? "pre" : mode == .wordHard ? "" : "pre "
      XCTAssertEqual(input.typed, expected)
      XCTAssertEqual(result.outcome, .failed)
      XCTAssertEqual(result.finishedAt, start.addingTimeInterval(1))
      XCTAssertEqual(result.inputMetrics?.totalAttempts, 5)
      XCTAssertEqual(result.preciseAccuracy, 80)
      XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 1), expected)
      XCTAssertEqual(result.replayEvents.last?.automatic, true)
    }
  }

  func testCorrectMasterInputAndCommitStillFinishNormally() {
    for mode in modes {
      var input = TypingSession(configuration: .words(2, difficulty: .master,
        rules: .init(deleteOnErrorMode: mode)), prompt: "ab cd")
      XCTAssertEqual(input.insertBatch("ab ", at: start), [true])
      XCTAssertEqual(input.outcome, .active)
      XCTAssertEqual(input.completedWordCount, 1)
      input.insertBatch("cd", at: start.addingTimeInterval(1))
      XCTAssertEqual(input.outcome, .completed)
      XCTAssertEqual(input.typed, "ab cd")
    }
  }

  func testMasterIgnoresEarlierRecoveredMistakeWhenFinalBatchUnitIsCorrect() throws {
    for mode in modes {
      var input = TypingSession(configuration: .words(2, difficulty: .master,
        rules: .init(deleteOnErrorMode: mode)), prompt: "abc tail")
      XCTAssertEqual(input.insertBatch("xab", at: start), [true])
      XCTAssertEqual(input.typed, "ab")
      XCTAssertEqual(input.outcome, .active)
      input.bailOut(at: start.addingTimeInterval(1))
      let result = try XCTUnwrap(input.result())
      XCTAssertEqual(result.inputMetrics?.totalAttempts, 3)
      XCTAssertEqual(result.inputMetrics?.correctAttempts, 2)
      XCTAssertEqual(result.replayEvents.first?.text, "x")
      XCTAssertEqual(result.replayEvents[1].kind, .delete)
      XCTAssertEqual(result.replayEvents[1].automatic, true)
    }
  }

  func testMasterFailsOnFinalWrongBatchUnitAfterRecovery() throws {
    for mode in modes {
      var input = TypingSession(configuration: .words(2, difficulty: .master,
        rules: .init(deleteOnErrorMode: mode)), prompt: "abc tail")
      XCTAssertEqual(input.insertBatch("abx", at: start), [false])
      XCTAssertEqual(input.outcome, .failed)
      let result = try XCTUnwrap(input.result())
      XCTAssertEqual(result.inputMetrics?.totalAttempts, 3)
      XCTAssertEqual(result.inputMetrics?.correctAttempts, 2)
      XCTAssertEqual(result.replayEvents.filter { $0.kind == .insert }.map(\.text), ["a", "b", "x"])
    }
  }

  func testExpertInteriorRecoveredMistakeDoesNotFailWithoutACommitAttempt() {
    for mode in modes {
      var input = TypingSession(configuration: .words(2, difficulty: .expert,
        rules: .init(deleteOnErrorMode: mode)), prompt: "abc tail")
      input.insertBatch("ab", at: start)
      XCTAssertEqual(input.insertBatch("x", at: start), [false])
      XCTAssertEqual(input.typed, mode.clearsWholeWord ? "" : "a")
      XCTAssertEqual(input.outcome, .active)
    }
  }

  func testExpertEarlierRecoveredSeparatorDoesNotFailTheFinalNonCommitUnit() {
    for mode in modes {
      var input = TypingSession(configuration: .words(2, difficulty: .expert,
        rules: .init(deleteOnErrorMode: mode)), prompt: "ab tail")
      XCTAssertEqual(input.insertBatch("a b", at: start), [false])
      XCTAssertEqual(input.typed, "")
      XCTAssertEqual(input.outcome, .active)
      input.insertBatch("ab tail", at: start.addingTimeInterval(1))
      XCTAssertEqual(input.outcome, .completed)
    }
  }

  func testExpertCorrectCommitsStillAdvanceAndComplete() {
    for mode in modes {
      var input = TypingSession(configuration: .words(2, difficulty: .expert,
        rules: .init(deleteOnErrorMode: mode)), prompt: "ab cd")
      input.insertBatch("ab ", at: start)
      XCTAssertEqual(input.outcome, .active)
      XCTAssertEqual(input.completedWordCount, 1)
      input.insertBatch("cd", at: start.addingTimeInterval(1))
      XCTAssertEqual(input.outcome, .completed)
    }
  }

  func testExpertEmptySpaceAndReturnFieldsDoNotFailForLeadingWrongSpaces() {
    for mode in modes {
      for prompt in ["ab cd", "\ncd"] {
        var input = TypingSession(configuration: .words(2, difficulty: .expert,
          rules: .init(strictSpace: true, deleteOnErrorMode: mode)), prompt: prompt)
        XCTAssertEqual(input.insertBatch(" ", at: start), [false])
        XCTAssertEqual(input.typed, "")
        XCTAssertEqual(input.outcome, .active)
        XCTAssertEqual(input.completedWordCount, 0)
      }
    }
  }

  func testExpertPrematureReturnFailsEvenAfterRecoveryMakesTheFieldEmpty() {
    for mode in modes {
      var input = TypingSession(configuration: .words(2, difficulty: .expert,
        rules: .init(deleteOnErrorMode: mode)), prompt: "ab\ncd")
      input.insertBatch("a", at: start)
      XCTAssertEqual(input.insertBatch("\n", at: start), [false])
      XCTAssertEqual(input.typed, "")
      XCTAssertEqual(input.outcome, .failed)
      XCTAssertEqual(input.completedWordCount, 0)
    }
  }

  func testExpertRetainedLeadingSpaceCountsAsNonemptyBeforeRecovery() {
    for mode in modes {
      var input = TypingSession(configuration: .words(2, difficulty: .expert,
        rules: .init(strictSpace: true)), prompt: "ab cd")
      input.insertBatch(" ", at: start)
      XCTAssertEqual(input.outcome, .active)
      input.synchronizeLiveInputRules(.init(deleteOnErrorMode: mode))
      XCTAssertEqual(input.insertBatch(" ", at: start), [false])
      XCTAssertEqual(input.typed, "")
      XCTAssertEqual(input.outcome, .failed)
    }
  }

  func testNoSpaceExpertInteriorErrorDoesNotCommitOrFail() {
    for mode in modes {
      var input = TypingSession(configuration: .words(2, difficulty: .expert,
        rules: .init(deleteOnErrorMode: mode)).with(modifiers: [.noSpaces]),
        prompt: "abcde", noSpaceWordEndIndices: [3, 5], noSpaceTargetWords: ["abc", "de"])
      input.insertBatch("a", at: start)
      input.insertBatch("x", at: start)
      XCTAssertEqual(input.typed, "")
      XCTAssertEqual(input.outcome, .active)
      input.insertBatch("abc", at: start.addingTimeInterval(1))
      XCTAssertEqual(input.completedWordCount, 1)
      XCTAssertEqual(input.outcome, .active)
    }
  }

  func testNoSpaceExpertOneLetterWrongWordStillFailsOnEmptyInput() {
    for mode in modes {
      var input = TypingSession(configuration: .words(2, difficulty: .expert,
        rules: .init(deleteOnErrorMode: mode)).with(modifiers: [.noSpaces]),
        prompt: "ab", noSpaceWordEndIndices: [1, 2], noSpaceTargetWords: ["a", "b"])
      input.insertBatch("x", at: start)
      XCTAssertEqual(input.typed, "")
      XCTAssertEqual(input.outcome, .failed)
    }
  }

  func testNoSpaceMasterHardRecoveryReturnsBeforeFailingAtTheNewWordStart() {
    for mode in modes {
      var input = TypingSession(configuration: .words(2, difficulty: .master,
        rules: .init(deleteOnErrorMode: mode)).with(modifiers: [.noSpaces]),
        prompt: "abcd", noSpaceWordEndIndices: [2, 4], noSpaceTargetWords: ["ab", "cd"])
      input.insertBatch("ab", at: start)
      input.insertBatch("x", at: start.addingTimeInterval(1))
      XCTAssertEqual(input.typed, mode == .letterHard ? "a" : mode == .wordHard ? "" : "ab")
      XCTAssertEqual(input.outcome, .failed)
    }
  }

  func testAutomaticRecoveredMasterErrorUsesExecutionClockAndAutomaticLog() throws {
    var input = TypingSession(configuration: .words(2, difficulty: .master,
      rules: .init(deleteOnErrorMode: .letter), language: .codeSwift), prompt: "a \tb tail")
    input.insertBatch("a ", at: start, defersAutomaticInput: true)
    XCTAssertTrue(input.hasPendingAutomaticInput)
    input.insertBatch("\t", at: start.addingTimeInterval(1), defersAutomaticInput: true)
    XCTAssertEqual(input.outcome, .active)
    XCTAssertEqual(input.processNextAutomaticInput(for: input.automaticInputAttemptID,
      executedAt: start.addingTimeInterval(3)), [false])
    let result = try XCTUnwrap(input.result())
    XCTAssertEqual(input.typed, "a ")
    XCTAssertEqual(result.outcome, .failed)
    XCTAssertEqual(result.finishedAt, start.addingTimeInterval(3))
    // Saved tapes retain their existing chronological ordering, not callback
    // execution ordering when a delayed callback uses its original timestamp.
    XCTAssertEqual(result.replayEvents.map(\.automatic), [false, false, true, true, true, false])
    XCTAssertEqual(result.replayEvents.map(\.offset), [0, 0, 0, 0, 0, 1])
    XCTAssertEqual(result.replayEvents.filter(\.automatic).map(\.kind), [.insert, .delete, .delete])
    XCTAssertEqual(result.replayEvents.last?.text, "\t")
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 4)
    XCTAssertEqual(result.inputMetrics?.correctAttempts, 3)
    XCTAssertFalse(input.hasPendingAutomaticInput)
  }

  @MainActor func testNativeInsertionBridgeReportsRecoveryAndMasterFailure() {
    var input = TypingSession(configuration: .words(2, difficulty: .master,
      rules: .init(deleteOnErrorMode: .letter)), prompt: "ab tail")
    let view = TypingInputView(frame: .zero)
    var feedback: [Bool] = []
    view.onInsert = { text, forceError in
      feedback = TypingLiveInputFeedback.insertBatch(text, into: &input,
        forceError: forceError, at: self.start)
    }
    view.insertText("x", replacementRange: .init())
    XCTAssertEqual(feedback, [false])
    XCTAssertEqual(input.typed, "")
    XCTAssertEqual(input.outcome, .failed)
  }

  func testRecoveredFailedTapeRoundTripsUsingTheCurrentArchiveFormat() throws {
    var input = TypingSession(configuration: .words(2, difficulty: .expert,
      rules: .init(deleteOnErrorMode: .letter)), prompt: "ab tail")
    input.insertBatch("a", at: start)
    input.insertBatch(" ", at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(input.result())
    XCTAssertEqual(result.replayEvents[1].commitsWord, false)
    XCTAssertEqual(result.replayEvents[1].inputStopped, nil)
    XCTAssertEqual(result.preciseAccuracy, 50)
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: result.replayEvents), [""])
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 1), "")
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [], at: start))
    XCTAssertEqual(archive.version, TypebarArchive.currentVersion)
    XCTAssertEqual(archive.results, [result])
    let legacy = try JSONDecoder().decode(TypingReplayEvent.self,
      from: Data(#"{"offset":0,"kind":"insert","text":"a"}"#.utf8))
    XCTAssertNil(legacy.commitsWord)
    XCTAssertNil(legacy.inputStopped)
  }

  func testFailedRecoveryCannotBeReopenedByLaterInputOrDeletion() throws {
    var input = TypingSession(configuration: .words(2, difficulty: .master,
      rules: .init(deleteOnErrorMode: .word)), prompt: "ab tail")
    input.insertBatch("x", at: start)
    let before = try XCTUnwrap(input.result())
    XCTAssertEqual(input.insertBatch("ab tail", at: start.addingTimeInterval(1)), [])
    input.deleteBackward(at: start.addingTimeInterval(1))
    input.deleteWordBackward(at: start.addingTimeInterval(1))
    let after = try XCTUnwrap(input.result())
    XCTAssertEqual(after.outcome, .failed)
    XCTAssertEqual(after.finishedAt, before.finishedAt)
    XCTAssertEqual(after.replayEvents, before.replayEvents)
    XCTAssertEqual(after.inputMetrics, before.inputMetrics)
  }

  func testOrdinaryNoSpaceRecoveryCannotDeleteThePreviousCommittedWord() {
    for mode in [DeleteOnErrorMode.letter, .word] {
      for (first, prompt) in [("ab", "abcd"), ("晨光", "晨光窗边")] {
        var input = TypingSession(configuration: .words(2,
          rules: .init(deleteOnErrorMode: mode)).with(modifiers: [.noSpaces]),
          prompt: prompt, noSpaceWordEndIndices: [2, 4])
        input.insertBatch(first, at: start)
        input.insertBatch("x", at: start.addingTimeInterval(1))
        XCTAssertEqual(input.typed, first)
        XCTAssertEqual(input.completedWordCount, 1)
        XCTAssertEqual(input.outcome, .active)
      }
    }
  }
}
