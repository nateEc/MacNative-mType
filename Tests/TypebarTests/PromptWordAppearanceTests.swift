import SwiftUI
import XCTest
@testable import Typebar

final class PromptWordAppearanceTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 100)

  func testOffUsesFutureColorForCorrectTextButKeepsMistakesVisible() {
    var session = TypingSession(configuration: .words(2), prompt: "abc bay")
    session.insertBatch("ax", at: start)
    XCTAssertEqual(Array(plan(session, .off).prefix(3)).map(\.color), [.future, .error, .future])
  }

  func testEveryWordScopeUsesTextColorForTheWholeActiveAndRequestedFutureWords() {
    let session = TypingSession(configuration: .words(5), prompt: "abc bay cedar lake oak")
    let ranges = [0..<3, 4..<7, 8..<13, 14..<18, 19..<22]
    for (mode, count) in [(PromptHighlightMode.word, 1), (.nextWord, 2), (.nextTwoWords, 3), (.nextThreeWords, 4)] {
      let appearance = plan(session, mode)
      for (word, range) in ranges.enumerated() {
        XCTAssertTrue(appearance[range].allSatisfy { $0.color == (word < count ? .completed : .future) })
      }
    }
  }

  func testCommittedCorrectWordsUseFutureColorInWordModes() {
    var session = TypingSession(configuration: .words(3), prompt: "abc bay cedar")
    session.insertBatch("abc ", at: start)
    let appearance = plan(session, .word)
    XCTAssertTrue(appearance[0..<3].allSatisfy { $0.color == .future })
    XCTAssertTrue(appearance[4..<7].allSatisfy { $0.color == .completed })
    XCTAssertTrue(appearance[8..<13].allSatisfy { $0.color == .future })
  }

  func testAnActiveMistakeColorsTheWholeWordWithoutACommitUnderline() {
    var session = TypingSession(configuration: .words(3), prompt: "abc bay cedar")
    session.insertBatch("x", at: start)
    let appearance = plan(session, .nextWord)
    XCTAssertTrue(appearance[0..<3].allSatisfy { $0.color == .error && !$0.hasErrorUnderline })
    XCTAssertTrue(appearance[4..<7].allSatisfy { $0.color == .completed })
  }

  func testOrdinaryIncompleteCommitUnderlinesTheWordWithoutReclassifyingMissingLetters() {
    var session = TypingSession(configuration: .words(3), prompt: "abc bay cedar")
    session.insertBatch("a ", at: start)
    XCTAssertTrue(session.promptWordPresentations[0].hasCommitError)
    let letter = plan(session, .letter)
    XCTAssertTrue(letter[0..<3].allSatisfy(\.hasErrorUnderline))
    XCTAssertEqual(letter[0].color, .completed)
    XCTAssertEqual(letter[1].color, .future)
    XCTAssertTrue(plan(session, .word)[0..<3].allSatisfy { $0.color == .error })
    XCTAssertFalse(letter[3].hasErrorUnderline, "Word separators are not part of the word border")
  }

  func testBlindCommitCannotAcquireAPastWordBorderWhenBlindIsDisabledLater() {
    var session = TypingSession(configuration: .words(3, rules: .init(blindMode: true)),
      prompt: "abc bay cedar")
    session.insertBatch("x ", at: start)
    session.setBlindMode(false)
    XCTAssertFalse(session.promptWordPresentations[0].hasCommitError)
    let appearance = plan(session, .word)
    XCTAssertTrue(appearance[0..<3].allSatisfy { $0.color == .future && !$0.hasErrorUnderline })
    XCTAssertEqual(plan(session, .letter)[0].color, .error)
  }

  func testBlindToggleMasksButDoesNotEraseAnOrdinaryCommitError() {
    var session = TypingSession(configuration: .words(3), prompt: "abc bay cedar")
    session.insertBatch("a ", at: start)
    session.setBlindMode(true)
    XCTAssertTrue(session.promptWordPresentations[0].hasCommitError)
    XCTAssertTrue(plan(session, .word)[0..<3].allSatisfy { $0.color == .future && !$0.hasErrorUnderline })
    session.setBlindMode(false)
    XCTAssertTrue(plan(session, .word)[0..<3].allSatisfy { $0.color == .error && $0.hasErrorUnderline })
  }

  func testAllowedReturnClearsTheWordBorderWhileARejectedDeletePreservesIt() {
    for confidence in [ConfidenceMode.off, .maximum] {
      var session = TypingSession(configuration: .words(3,
        rules: .init(confidenceMode: confidence)), prompt: "abc bay cedar")
      session.insertBatch("a ", at: start)
      XCTAssertTrue(session.promptWordPresentations[0].hasCommitError)
      session.deleteBackward(at: start.addingTimeInterval(0.2))
      XCTAssertEqual(session.promptWordPresentations[0].hasCommitError, confidence == .maximum)
    }
  }

  func testAnActiveExtraLetterMakesItsOwningWordUseErrorColor() {
    var session = TypingSession(configuration: .words(2), prompt: "abc bay")
    session.insertBatch("abcx", at: start)
    let appearance = plan(session, .word)
    XCTAssertTrue(appearance[0..<3].allSatisfy { $0.color == .error })
    XCTAssertEqual(appearance.last?.color, .error)
    XCTAssertTrue(session.promptWordPresentations[0].hasInputError)
  }

  func testConcealmentCannotExposeAnErrorColorOrWordUnderline() {
    var session = TypingSession(configuration: TestConfiguration.words(3).with(modifiers: [.memory]),
      prompt: "abc bay cedar")
    session.insertBatch("x ", at: start)
    XCTAssertTrue(plan(session, .letter).allSatisfy { $0.color == .hidden && !$0.hasErrorUnderline })
  }

  func testErrorUnderlineAttributeUsesTheErrorColorIndependentlyOfTextColor() {
    var session = TypingSession(configuration: .words(3), prompt: "abc bay cedar")
    session.insertBatch("a ", at: start)
    var text = AttributedString("a")
    text.foregroundColor = .green
    plan(session, .letter)[0].applyErrorUnderline(to: &text, errorColor: .pink)
    XCTAssertEqual(text.underlineStyle, Text.LineStyle(color: .pink))
    XCTAssertEqual(text.foregroundColor, .green)
  }

  func testNoSpaceRetainedBoundaryOwnsItsCommitBorderAndClearsOnReturn() {
    var session = TypingSession(configuration: TestConfiguration.words(2).with(modifiers: [.noSpaces]),
      prompt: "abcbay", noSpaceWordEndIndices: [3, 6], noSpaceTargetWords: ["abc", "bay"])
    session.insertBatch("axc", at: start)
    XCTAssertEqual(session.promptWordPresentations.map(\.range), [0..<3, 3..<6])
    XCTAssertEqual(session.promptWordPresentations[0].phase, .committed)
    XCTAssertTrue(session.promptWordPresentations[0].hasCommitError)
    XCTAssertTrue(plan(session, .letter)[0..<3].allSatisfy(\.hasErrorUnderline))
    session.deleteBackward(at: start.addingTimeInterval(0.2))
    XCTAssertFalse(session.promptWordPresentations[0].hasCommitError)
    XCTAssertEqual(session.promptWordPresentations[0].phase, .active)
    XCTAssertEqual(session.typed, "ax")
  }

  func testRejectedCommitDoesNotCreateAWordBorder() {
    var session = TypingSession(configuration: .words(3, rules: .init(stopOnErrorMode: .word)),
      prompt: "abc bay cedar")
    session.insertBatch("a ", at: start)
    XCTAssertEqual(session.typed, "a ")
    XCTAssertFalse(session.promptWordPresentations[0].hasCommitError)
    XCTAssertTrue(plan(session, .letter).allSatisfy { !$0.hasErrorUnderline })
    XCTAssertEqual(session.preciseAccuracy, 50)
  }

  func testWordDeletionAndTruncationClearOnlyTheDiscardedCommitBorders() {
    var session = TypingSession(configuration: .words(3), prompt: "abc bay cedar")
    session.insertBatch("a b ", at: start)
    XCTAssertTrue(session.promptWordPresentations[0].hasCommitError)
    XCTAssertTrue(session.promptWordPresentations[1].hasCommitError)
    session.deleteWordBackward(at: start.addingTimeInterval(0.2))
    XCTAssertEqual(session.typed, "a ")
    XCTAssertTrue(session.promptWordPresentations[0].hasCommitError)
    XCTAssertFalse(session.promptWordPresentations[1].hasCommitError)
    session.replaceInput(with: "a", at: start.addingTimeInterval(0.4))
    XCTAssertTrue(session.promptWordPresentations.allSatisfy { !$0.hasCommitError })
  }

  func testCorrectedRecommitDoesNotKeepTheOldBorderOrEraseAttemptedMistakes() {
    var session = TypingSession(configuration: .words(3), prompt: "abc bay cedar")
    session.insertBatch("axc ", at: start)
    XCTAssertTrue(session.promptWordPresentations[0].hasCommitError)
    for _ in 0..<3 { session.deleteBackward(at: start.addingTimeInterval(0.2)) }
    session.insertBatch("bc ", at: start.addingTimeInterval(0.4))
    XCTAssertEqual(session.typed, "abc ")
    XCTAssertFalse(session.promptWordPresentations[0].hasCommitError)
    XCTAssertEqual(session.errors, 0)
    XCTAssertEqual(session.preciseAccuracy, 600.0 / 7, accuracy: 0.000_001)
  }

  func testAppearanceDoesNotChangeResultArchivesAndRepeatedAttemptsStartWithoutBorders() throws {
    var session = TypingSession(configuration: .timed(seconds: 1), prompt: "abc bay cedar")
    session.insertBatch("a ", at: start)
    for mode in PromptHighlightMode.allCases { _ = plan(session, mode) }
    session.tick(at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.preciseAccuracy, 50)
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 2)
    XCTAssertEqual(result.inputMetrics?.correctAttempts, 1)
    XCTAssertEqual(result.replayEvents.map(\.text), ["a", " "])
    let decoded = try JSONDecoder().decode(CompletedTestResult.self,
      from: JSONEncoder().encode(result))
    XCTAssertEqual(decoded, result)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: decoded).portableResult), result)
    XCTAssertTrue(session.repeatedAttempt().promptWordPresentations.allSatisfy { !$0.hasCommitError })
  }

  func testZenWordScopesUseEnteredTextWithoutTargetErrors() {
    var session = TypingSession(configuration: .init(mode: .zen, duration: nil,
      wordLimit: nil, difficulty: .normal, rules: .init()), prompt: "")
    session.insertBatch("abc bay", at: start)
    XCTAssertTrue(plan(session, .word)[0..<3].allSatisfy { $0.color == .future })
    XCTAssertTrue(plan(session, .word)[4..<7].allSatisfy { $0.color == .completed })
    XCTAssertTrue(plan(session, .off).allSatisfy { $0.color == .future && !$0.hasErrorUnderline })
  }

  func testLongWordPresentationSnapshotIsBoundedAndKeepsTheActiveScope() {
    let prompt = String(repeating: "abc ", count: 8_000) + "bay"
    var session = TypingSession(configuration: .words(8_001), prompt: prompt)
    session.insertBatch("a ", at: start)
    let before = Date()
    let words = session.promptWordPresentations
    let appearance = PromptGlyphAppearance.plan(glyphs: session.promptGlyphs, words: words,
      mode: .nextThreeWords, blindMode: false)
    XCTAssertLessThan(Date().timeIntervalSince(before), 5, "Coarse resource guard, not a frame-rate claim")
    XCTAssertEqual(words.count, 8_001)
    XCTAssertEqual(words[1].phase, .active)
    XCTAssertTrue(appearance[0..<3].allSatisfy { $0.color == .error && $0.hasErrorUnderline })
    XCTAssertTrue(appearance[4..<7].allSatisfy { $0.color == .completed })
    XCTAssertTrue(appearance.suffix(3).allSatisfy { $0.color == .future })
  }

  func testHiddenTypedEffectRemovesMistypedWordsAndTheirBordersIncludingOwnedExtras() {
    var session = TypingSession(configuration: .words(3), prompt: "abc bay cedar")
    session.insertBatch("abcx ", at: start)
    let appearance = PromptGlyphAppearance.plan(glyphs: session.promptGlyphs,
      words: session.promptWordPresentations, mode: .word, blindMode: false, typedEffect: .hide)
    XCTAssertTrue(appearance[0..<3].allSatisfy { $0.color == .hidden && !$0.hasErrorUnderline })
    XCTAssertEqual(appearance.last?.color, .hidden)
    XCTAssertTrue(appearance[4..<7].allSatisfy { $0.color == .completed })
  }

  func testOffBlindColorUsesTheFutureRoleBeforeFlippedAndColorfulThemeMapping() {
    var session = TypingSession(configuration: .words(3, rules: .init(blindMode: true)),
      prompt: "abc bay cedar")
    session.insertBatch("x", at: start)
    let appearance = plan(session, .off)
    XCTAssertEqual(appearance[0].color, .future)
    XCTAssertEqual(PromptTextColorPolicy.tone(for: .future,
      flipsCompletionAndFuture: true, usesAccentForCompleted: true), .accent)
    XCTAssertFalse(appearance[0].hasErrorUnderline)
    XCTAssertEqual(session.errors, 1)
  }

  private func plan(_ session: TypingSession, _ mode: PromptHighlightMode) -> [PromptGlyphAppearance] {
    PromptGlyphAppearance.plan(glyphs: session.promptGlyphs, words: session.promptWordPresentations,
      mode: mode, blindMode: session.configuration.rules.blindMode)
  }
}
