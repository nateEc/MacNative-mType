import XCTest
@testable import Typebar

final class BlindCommittedWordPresentationTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 100)

  func testBlindEarlyCommitKeepsMissingLettersNeutralAfterBlindIsDisabled() {
    var session = TypingSession(configuration: .words(3, rules: .init(blindMode: true)),
      prompt: "amber bay cedar")
    session.insertBatch("am ", at: start)
    session.setBlindMode(false)
    XCTAssertEqual(states(session, in: 2..<5), [.correct, .correct, .correct])
    XCTAssertEqual(session.typed, "am ")
    XCTAssertEqual(session.nextExpectedCharacter, "b")
    XCTAssertEqual(session.errors, 1)
    XCTAssertEqual(session.preciseAccuracy, 200.0 / 3, accuracy: 0.000_001)
  }

  func testOrdinaryCommittedMissingLettersStayUntypedWhenBlindIsEnabledLater() {
    var session = TypingSession(configuration: .words(3), prompt: "amber bay cedar")
    session.insertBatch("am ", at: start)
    XCTAssertEqual(states(session, in: 2..<5), [.pending, .pending, .pending])
    session.setBlindMode(true)
    XCTAssertEqual(states(session, in: 2..<5), [.pending, .pending, .pending])
  }

  func testCommittedMistypesRegainErrorColorWithoutReclassifyingBlindMissingLetters() {
    var session = TypingSession(configuration: .words(3, rules: .init(blindMode: true)),
      prompt: "amber bay cedar")
    session.insertBatch("ax ", at: start)
    session.setBlindMode(false)
    XCTAssertEqual(session.promptGlyphs[1].state, .incorrect)
    XCTAssertEqual(session.promptGlyphs[1].typedCharacter, "x")
    XCTAssertEqual(states(session, in: 2..<5), [.correct, .correct, .correct])
    session.setBlindMode(true)
    XCTAssertEqual(session.promptGlyphs[1].state, .correct)
    session.setBlindMode(false)
    XCTAssertEqual(session.promptGlyphs[1].state, .incorrect)
    XCTAssertEqual(session.errors, 2)
  }

  func testReturningToTheWordAndRecommittingOrdinarilyDropsItsBlindDisplayState() {
    var session = TypingSession(configuration: .words(3, rules: .init(blindMode: true)),
      prompt: "amber bay cedar")
    session.insertBatch("am ", at: start)
    session.setBlindMode(false)
    XCTAssertEqual(states(session, in: 2..<5), [.correct, .correct, .correct])
    session.deleteBackward(at: start.addingTimeInterval(0.2))
    XCTAssertEqual(session.typed, "am")
    XCTAssertEqual(states(session, in: 2..<5), [.current, .pending, .pending])
    session.insertBatch(" ", at: start.addingTimeInterval(0.4))
    XCTAssertEqual(states(session, in: 2..<5), [.pending, .pending, .pending])
    XCTAssertEqual(session.preciseAccuracy, 50)
  }

  func testBlockedBackspaceDoesNotDiscardCommittedBlindPresentation() {
    var session = TypingSession(configuration: .words(3,
      rules: .init(blindMode: true, confidenceMode: .maximum)), prompt: "amber bay cedar")
    session.insertBatch("am ", at: start)
    session.setBlindMode(false)
    session.deleteBackward(at: start.addingTimeInterval(0.2))
    XCTAssertEqual(session.typed, "am ")
    XCTAssertEqual(states(session, in: 2..<5), [.correct, .correct, .correct])
    session.bailOut(at: start.addingTimeInterval(1))
    XCTAssertEqual(session.result()?.replayEvents.map(\.text), ["a", "m", " "])
  }

  func testEachCommittedWordUsesItsOwnCommitTimeBlindSetting() {
    var session = TypingSession(configuration: .words(4, rules: .init(blindMode: true)),
      prompt: "amber bay cedar lake")
    session.insertBatch("am ", at: start)
    session.setBlindMode(false)
    session.insertBatch("b ", at: start.addingTimeInterval(0.2))
    session.setBlindMode(true)
    session.insertBatch("ce ", at: start.addingTimeInterval(0.4))
    session.setBlindMode(false)
    XCTAssertEqual(states(session, in: 2..<5), [.correct, .correct, .correct])
    XCTAssertEqual(states(session, in: 7..<9), [.pending, .pending])
    XCTAssertEqual(states(session, in: 12..<15), [.correct, .correct, .correct])
    XCTAssertEqual(session.nextExpectedCharacter, "l")
    XCTAssertEqual(session.errors, 3)
    XCTAssertEqual(session.preciseAccuracy, 62.5)
  }

  func testCommittedPresentationDoesNotRewriteResultsOrSurviveAsAttemptState() throws {
    var session = TypingSession(configuration: .timed(seconds: 1, rules: .init(blindMode: true)),
      prompt: "amber bay cedar")
    session.insertBatch("am ", at: start)
    session.setBlindMode(false)
    session.tick(at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    XCTAssertFalse(result.configuration.rules.blindMode)
    XCTAssertEqual(result.inputMetrics?.correctAttempts, 2)
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 3)
    XCTAssertEqual(result.preciseAccuracy, 66.67)
    let decoded = try JSONDecoder().decode(CompletedTestResult.self,
      from: JSONEncoder().encode(result))
    XCTAssertEqual(decoded, result)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: decoded).portableResult), result)
    var repeated = session.repeatedAttempt()
    repeated.insertBatch("am ", at: start.addingTimeInterval(2))
    XCTAssertEqual(states(repeated, in: 2..<5), [.pending, .pending, .pending])
  }

  func testCompositionCompletionProbeDoesNotMarkTheRealWordAsBlindCommitted() {
    var session = TypingSession(configuration: .words(3, rules: .init(blindMode: true)),
      prompt: "amber bay cedar")
    session.insertBatch("am", at: start)
    _ = session.shouldFinishWithComposition(" ", forceError: false)
    XCTAssertEqual(session.typed, "am")
    session.setBlindMode(false)
    session.insertBatch(" ", at: start.addingTimeInterval(0.2))
    XCTAssertEqual(states(session, in: 2..<5), [.pending, .pending, .pending])
  }

  func testWordBackspaceClearsOnlyTheReturnedWordAndLeavesEarlierBlindWordsNeutral() {
    var session = TypingSession(configuration: .words(3, rules: .init(blindMode: true)),
      prompt: "amber bay cedar")
    session.insertBatch("am b ", at: start)
    session.setBlindMode(false)
    session.deleteWordBackward(at: start.addingTimeInterval(0.2))
    XCTAssertEqual(session.typed, "am ")
    XCTAssertEqual(states(session, in: 2..<5), [.correct, .correct, .correct])
    XCTAssertEqual(states(session, in: 6..<9), [.current, .pending, .pending])
    session.insertBatch("b ", at: start.addingTimeInterval(0.4))
    XCTAssertEqual(states(session, in: 7..<9), [.pending, .pending])
    XCTAssertEqual(states(session, in: 2..<5), [.correct, .correct, .correct])
  }

  func testHardAutomaticErrorRecoveryReopensOnlyThePreviousBlindWord() {
    var session = TypingSession(configuration: .words(3,
      rules: .init(deleteOnErrorMode: .letterHard, blindMode: true)), prompt: "amber bay cedar")
    // This rule rejects incomplete commits, so use fully typed words as a
    // recovery control. It must not invent a missing-letter display override.
    session.insertBatch("amber bay ", at: start)
    session.insertBatch("x", at: start.addingTimeInterval(0.2))
    session.setBlindMode(false)
    XCTAssertEqual(session.typed, "amber bay")
    XCTAssertEqual(session.nextExpectedCharacter, " ")
    XCTAssertEqual(session.promptGlyphs[0].state, .correct)
    XCTAssertEqual(session.promptGlyphs[8].state, .correct)
    XCTAssertEqual(session.promptGlyphs[9].state, .current)
  }

  func testReplacementTruncationRemovesDiscardedWordsWithoutLeakingTheirNeutralState() {
    var session = TypingSession(configuration: .words(3, rules: .init(blindMode: true)),
      prompt: "amber bay cedar")
    session.insertBatch("am b ", at: start)
    session.setBlindMode(false)
    session.replaceInput(with: "am", at: start.addingTimeInterval(0.2))
    XCTAssertEqual(session.typed, "am")
    XCTAssertEqual(states(session, in: 2..<5), [.current, .pending, .pending])
    session.insertBatch(" ", at: start.addingTimeInterval(0.4))
    XCTAssertEqual(states(session, in: 2..<5), [.pending, .pending, .pending])
    XCTAssertEqual(states(session, in: 6..<9), [.current, .pending, .pending])
  }

  func testUnicodeMissingDisplayUsesCaretIndicesWithoutReweightingInputUnits() throws {
    var session = TypingSession(configuration: .timed(seconds: 1, rules: .init(blindMode: true)),
      prompt: "a\u{301}mber bay")
    session.insertBatch("a\u{301} ", at: start)
    session.setBlindMode(false)
    XCTAssertEqual(states(session, in: 1..<5), [.correct, .correct, .correct, .correct])
    XCTAssertEqual(session.nextExpectedCharacter, "b")
    session.tick(at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.inputMetrics?.correctAttempts, 2)
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 3)
    XCTAssertEqual(result.preciseAccuracy, 66.67)
  }

  func testMemoryConcealsBlindCommittedMissingLettersUntilTheAttemptEnds() {
    var session = TypingSession(configuration: TestConfiguration.words(3,
      rules: .init(blindMode: true)).with(modifiers: [.memory]), prompt: "amber bay cedar")
    session.insertBatch("am ", at: start)
    session.setBlindMode(false)
    XCTAssertTrue(session.promptGlyphs.allSatisfy { $0.state == .hidden })
    session.bailOut(at: start.addingTimeInterval(1))
    XCTAssertEqual(states(session, in: 2..<5), [.correct, .correct, .correct])
  }

  private func states(_ session: TypingSession, in range: Range<Int>) -> [TypingPromptCharacterState] {
    Array(session.promptGlyphs[range]).map(\.state)
  }
}
