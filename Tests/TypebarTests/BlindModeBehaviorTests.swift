import AppKit
import XCTest
@testable import Typebar

final class BlindModeBehaviorTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 100)

  func testBlindTypedTargetsRemainVisibleWithoutCorrectnessHintsAndExtrasHaveNoLayoutWidth() {
    let glyphs = TypingPromptPresentation.glyphs(target: "ab", typed: "axz", isFinished: false, blindMode: true)
    XCTAssertEqual(glyphs.map(\.character), Array("ab"))
    XCTAssertEqual(glyphs.map(\.state), [.correct, .correct])
    XCTAssertEqual(glyphs[1].typedCharacter, "x", "Replacement typography still has the original mistype")
  }

  func testBlindSkippedTargetsAreNeutralAndPendingTargetsRemainVisible() {
    let glyphs = TypingPromptPresentation.glyphs(target: "abc bay", typed: "a ", isFinished: false,
      blindMode: true, blindCommittedMissingTargetIndices: [1, 2],
      typedTargetIndices: [0, 3], currentTargetIndex: 4)
    XCTAssertEqual(Array(glyphs.prefix(4)).map(\.state), [.correct, .correct, .correct, .correct])
    XCTAssertEqual(glyphs[4].state, .current)
    XCTAssertEqual(glyphs[5].state, .pending)
  }

  func testZenBlindModeDoesNotHideEnteredUnicodeText() {
    let glyphs = TypingPromptPresentation.zenGlyphs(typed: "🦊e\u{301}", isFinished: false, blindMode: true)
    XCTAssertEqual(glyphs.map(\.state), [.correct, .correct, .current])
    XCTAssertEqual(glyphs.map(\.character), Array("🦊e\u{301} "))
  }

  func testRuntimeBlindTogglePreservesAttemptAndUpdatesResultConfiguration() throws {
    var session = TypingSession(configuration: .timed(seconds: 15), prompt: "abc bay")
    session.insert("ax", at: start)
    let initialGlyphs = session.promptGlyphs
    let initialTyped = session.typed
    session.setBlindMode(true)
    XCTAssertTrue(session.configuration.rules.blindMode)
    XCTAssertEqual(session.promptGlyphs[1].state, .correct)
    XCTAssertEqual(session.typed, initialTyped)
    XCTAssertEqual(session.startedAt, start)
    XCTAssertEqual(session.errors, 1)
    XCTAssertEqual(session.preciseAccuracy, 50)
    session.setBlindMode(false)
    XCTAssertEqual(session.promptGlyphs, initialGlyphs)
    XCTAssertEqual(session.configuration, .timed(seconds: 15))
    session.setBlindMode(true)
    session.tick(at: start.addingTimeInterval(15))
    let result = try XCTUnwrap(session.result())
    XCTAssertTrue(result.configuration.rules.blindMode)
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 2)
    XCTAssertEqual(result.replayEvents.map(\.text), ["a", "x"])
    XCTAssertEqual(result.preciseAccuracy, 50)
  }

  func testTerminalBlindSettingIsFrozenAndRepeatedAttemptRetainsIt() throws {
    var session = TypingSession(configuration: .words(1), prompt: "abc")
    session.setBlindMode(true)
    session.insert("a", at: start)
    session.insert("bc", at: start.addingTimeInterval(1))
    let before = try XCTUnwrap(session.result())
    session.setBlindMode(false)
    XCTAssertEqual(session.configuration, before.configuration)
    XCTAssertTrue(session.repeatedAttempt().configuration.rules.blindMode)
    XCTAssertEqual(try XCTUnwrap(session.result()).configuration, before.configuration)
    let decoded = try JSONDecoder().decode(CompletedTestResult.self,
      from: JSONEncoder().encode(before))
    XCTAssertEqual(decoded, before)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: decoded).portableResult), before)
  }

  func testSourceSoundMatrixIsMutuallyExclusiveAndBlindMistakesUseClicks() {
    for correct: Bool? in [true, false, nil] {
      for blind in [false, true] {
        for clicks in [false, true] {
          for errors in [false, true] {
            let plan = TypingInputSoundPlan(inputWasCorrect: correct, blindMode: blind,
              clickEnabled: clicks, errorEnabled: errors)
            let expectsError = correct == false && !blind && errors
            let expectsClick = correct != nil && !expectsError && clicks
            XCTAssertEqual(plan.playsClick, expectsClick)
            XCTAssertEqual(plan.playsError, expectsError)
            XCTAssertFalse(plan.playsClick && plan.playsError)
          }
        }
      }
    }
  }

  func testConcealmentModifiersStillTakePrecedenceOverBlindNeutralGlyphs() {
    let memory = TypingPromptPresentation.glyphs(target: "abc bay", typed: "ax",
      isFinished: false, blindMode: true, concealAll: true)
    XCTAssertTrue(memory.allSatisfy { $0.state == .hidden })
    let readAhead = TypingPromptPresentation.glyphs(target: "abc bay", typed: "ax",
      isFinished: false, blindMode: true, visibleFutureWords: 0)
    XCTAssertEqual(Array(readAhead.prefix(2)).map(\.state), [.correct, .correct])
    XCTAssertTrue(readAhead.suffix(3).allSatisfy { $0.state == .hidden })
  }

  func testInputFeedbackUsesTheFinalAttemptInsteadOfRemainingVisibleErrors() {
    var session = TypingSession(configuration: .timed(seconds: 10), prompt: "abc bay")
    session.insertBatch("xb", at: start)
    XCTAssertEqual(session.errors, 1)
    XCTAssertEqual(session.lastInputWasCorrect, true)
    XCTAssertEqual(session.preciseAccuracy, 50)
    session.insertBatch("x", at: start.addingTimeInterval(0.1))
    XCTAssertEqual(session.lastInputWasCorrect, false)
    session.insertBatch("", at: start.addingTimeInterval(0.2))
    XCTAssertNil(session.lastInputWasCorrect)
    session.insertBatch("\n", at: start.addingTimeInterval(0.3))
    XCTAssertNil(session.lastInputWasCorrect)
    XCTAssertEqual(session.typed, "xbx")
    session.tick(at: start.addingTimeInterval(10))
    session.insertBatch("a", at: start.addingTimeInterval(11))
    XCTAssertNil(session.lastInputWasCorrect)
  }

  func testLastUTF16UnitCanBeCorrectWhileTheDisplayedGraphemeIsWrong() throws {
    var session = TypingSession(configuration: .timed(seconds: 1), prompt: "a\u{301}b")
    session.insertBatch("x\u{301}", at: start)
    XCTAssertEqual(session.errors, 1)
    XCTAssertEqual(session.lastInputWasCorrect, true)
    XCTAssertEqual(session.preciseAccuracy, 50)
    session.tick(at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 2)
    XCTAssertEqual(result.inputMetrics?.correctAttempts, 1)
  }

  func testStoppedAndAutomaticallyDeletedMistakesStillSelectErrorFeedback() throws {
    for rules in [InputRules(stopOnErrorMode: .letter), InputRules(deleteOnErrorMode: .letter)] {
      var session = TypingSession(configuration: .timed(seconds: 1, rules: rules), prompt: "abc")
      session.insertBatch("x", at: start)
      XCTAssertEqual(session.typed, "")
      XCTAssertEqual(session.errors, 0)
      XCTAssertEqual(session.lastInputWasCorrect, false)
      session.tick(at: start.addingTimeInterval(1))
      XCTAssertEqual(try XCTUnwrap(session.result()).inputMetrics?.totalAttempts, 1)
    }
  }

  func testRejectedOppositeShiftProducesFeedbackButIgnoredNoSpaceDoesNot() {
    var session = TypingSession(configuration: .words(2,
      rules: .init(oppositeShiftMode: .on)).with(modifiers: [.noSpaces]), prompt: "abcbay")
    session.insertBatch("a", forceError: true, at: start)
    XCTAssertEqual(session.typed, "")
    XCTAssertEqual(session.lastInputWasCorrect, false)
    session.insertBatch(" ", at: start.addingTimeInterval(0.1))
    XCTAssertNil(session.lastInputWasCorrect)
    XCTAssertEqual(session.preciseAccuracy, 0)
    session.insertBatch("a", at: start.addingTimeInterval(0.2))
    let before = session.lastInputWasCorrect
    _ = session.shouldFinishWithComposition("bc", forceError: false)
    XCTAssertEqual(session.lastInputWasCorrect, before, "Candidate probes cannot emit a real key")
    XCTAssertEqual(session.typed, "a")
  }

  @MainActor
  func testNativeCompositionConfirmationDoesNotPlayAnExtraClickForItsClearNotification() {
    var session = TypingSession(configuration: .timed(seconds: 10), prompt: "abc")
    let input = TypingInputView(frame: .zero)
    var marked = ""
    var feedback: [TypingInputSoundPlan] = []
    let click = TypingInputSoundPlan(inputWasCorrect: true, blindMode: false,
      clickEnabled: true, errorEnabled: true)
    let error = TypingInputSoundPlan(inputWasCorrect: false, blindMode: false,
      clickEnabled: true, errorEnabled: true)
    input.onCompositionStarted = { session.beginComposition(at: self.start) }
    input.onCompositionChanged = { text in
      if TypingInputSoundPlan.isAudibleCompositionUpdate(previous: marked, current: text) {
        feedback.append(click)
      }
      marked = text
    }
    input.onInsert = { text, forced in
      session.insertBatch(text, forceError: forced, at: self.start)
      let plan = TypingInputSoundPlan(inputWasCorrect: session.lastInputWasCorrect,
        blindMode: false, clickEnabled: true, errorEnabled: true)
      if plan.playsClick || plan.playsError { feedback.append(plan) }
    }
    input.setMarkedText("x", selectedRange: .init(), replacementRange: .init())
    input.setMarkedText("x", selectedRange: .init(), replacementRange: .init())
    XCTAssertEqual(feedback, [click])
    XCTAssertEqual(session.typed, "")
    input.insertText("x", replacementRange: .init())
    XCTAssertEqual(feedback, [click, error])
    input.insertText("\n", replacementRange: .init())
    XCTAssertEqual(feedback, [click, error])
    input.setMarkedText("b", selectedRange: .init(), replacementRange: .init())
    input.unmarkText()
    XCTAssertEqual(feedback, [click, error, click])
    XCTAssertFalse(input.hasMarkedText())
    XCTAssertEqual(session.typed, "x")
  }
}
