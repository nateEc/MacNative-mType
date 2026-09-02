import AppKit
import SwiftData
import SwiftUI
import XCTest

@testable import Typebar

final class TypingEngineTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 10_000)

  func testTimedTestCompletesAtDeadline() {
    var session = TypingSession(configuration: .timed(seconds: 15), prompt: "amber harbor")
    session.insert("a", at: start)
    session.tick(at: start.addingTimeInterval(15))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.remainingSeconds(at: start.addingTimeInterval(15)), 0)
  }

  func testCustomDurationAndWordCountRespectTheirExactConfiguredLimits() {
    var timed = TypingSession(configuration: .timed(seconds: 73), prompt: "amber harbor")
    timed.insert("a", at: start)
    timed.tick(at: start.addingTimeInterval(72.9))
    XCTAssertEqual(timed.outcome, .active)
    timed.tick(at: start.addingTimeInterval(73))
    XCTAssertEqual(timed.outcome, .completed)

    var words = TestSessionFactory.make(configuration: .words(137))
    XCTAssertEqual(words.prompt.split(separator: " ").count, 137)
    words.insert(words.prompt, at: start)
    XCTAssertEqual(words.outcome, .completed)
  }

  func testWordsTestCompletesAtWordLimit() {
    var session = TypingSession(configuration: .words(2), prompt: "amber harbor quiet")
    session.insert("amber harbor", at: start)
    XCTAssertEqual(session.outcome, .completed)
  }

  func testLiveProgressUsesCountdownForTimeAndCommittedWordsForWordTests() {
    var timed = TypingSession(configuration: .timed(seconds: 30), prompt: "amber harbor")
    XCTAssertEqual(timed.progressLabel, "剩余")
    XCTAssertEqual(timed.progressText(at: start), "30s")
    XCTAssertEqual(timed.progressFraction(at: start), 0)
    timed.insert("a", at: start)
    XCTAssertEqual(timed.progressText(at: start.addingTimeInterval(4.2)), "26s")
    XCTAssertEqual(
      try XCTUnwrap(timed.progressFraction(at: start.addingTimeInterval(4.2))), 0.14, accuracy: 0.001)

    var words = TypingSession(configuration: .words(3), prompt: "amber harbor quiet")
    XCTAssertEqual(words.progressLabel, "进度")
    XCTAssertEqual(words.progressText(at: start), "0/3")
    XCTAssertEqual(words.progressFraction(at: start), 0)
    words.insert("amxer ", at: start)
    XCTAssertEqual(words.progressText(at: start), "1/3")
    XCTAssertEqual(try XCTUnwrap(words.progressFraction(at: start)), 1.0 / 3.0, accuracy: 0.001)
    words = TypingSession(configuration: .words(3), prompt: "amber harbor quiet")
    words.insert("amber harbor quiet", at: start)
    XCTAssertEqual(words.outcome, .completed)
    XCTAssertEqual(words.progressText(at: start), "3/3")
    XCTAssertEqual(words.progressFraction(at: start), 1)
  }

  func testQuickEndOnlyFinishesAFullLengthIncorrectLastWordWithoutErrorRules() {
    var ordinary = TypingSession(configuration: .words(2), prompt: "amber harbor")
    ordinary.insert("amber haxxxx", at: start)
    XCTAssertEqual(ordinary.outcome, .active)
    ordinary.insert(" ", at: start)
    XCTAssertEqual(ordinary.outcome, .completed)

    var rules = InputRules(quickEnd: true)
    var quickEnd = TypingSession(configuration: .words(2, rules: rules), prompt: "amber haxxxx")
    quickEnd.insert("amber habxxx", at: start)
    XCTAssertEqual(quickEnd.outcome, .completed)

    rules.stopOnError = true
    var blocked = TypingSession(configuration: .words(2, rules: rules), prompt: "amber haxxxx")
    blocked.insert("amber habxxx", at: start)
    XCTAssertEqual(blocked.outcome, .active)
  }

  func testQuoteAndCustomTestsCompleteAtEndOfPrompt() {
    for mode in [TestMode.quote, .custom] {
      var session = TypingSession(
        configuration: .init(
          mode: mode, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()),
        prompt: "violet")
      session.insert("violet", at: start)
      XCTAssertEqual(session.outcome, .completed)
    }
  }

  func testZenNeverAutoCompletes() {
    var session = TypingSession(
      configuration: .init(
        mode: .zen, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()),
      prompt: "violet")
    session.insert("violet", at: start)
    XCTAssertEqual(session.outcome, .active)
  }

  func testAbandonOnlyAppliesAfterTypingStartsAndDoesNotProduceCompletedOutcome() {
    var session = TypingSession(configuration: .timed(seconds: 30), prompt: "amber")
    session.abandon(at: start)
    XCTAssertEqual(session.outcome, .active)
    XCTAssertNil(session.result(at: start))

    session.insert("a", at: start)
    session.abandon(at: start.addingTimeInterval(4))
    XCTAssertEqual(session.outcome, .abandoned)
    XCTAssertEqual(session.result(at: start.addingTimeInterval(4))?.outcome, .abandoned)
  }

  func testMasterFailsOnFirstMistake() {
    var session = TypingSession(
      configuration: .timed(seconds: 30, difficulty: .master), prompt: "amber")
    session.insert("x", at: start)
    XCTAssertEqual(session.outcome, .failed)
  }

  func testExpertFailsWhenIncorrectWordIsCommitted() {
    var session = TypingSession(
      configuration: .timed(seconds: 30, difficulty: .expert), prompt: "amber harbor")
    session.insert("amxer ", at: start)
    XCTAssertEqual(session.outcome, .failed)
  }

  func testStopOnErrorRejectsIncorrectCharacter() {
    var rules = InputRules()
    rules.stopOnError = true
    var session = TypingSession(configuration: .timed(seconds: 30, rules: rules), prompt: "amber")
    session.insert("x", at: start)
    XCTAssertEqual(session.typed, "")
  }

  func testDeleteOnErrorDiscardsTheWrongCharacterWithoutChangingAcceptedInput() {
    var rules = InputRules()
    rules.deleteOnError = true
    var session = TypingSession(
      configuration: .timed(seconds: 30, rules: rules), prompt: "amber")
    session.insert("am", at: start)
    session.insert("x", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "am")
    XCTAssertEqual(session.errors, 0)
    session.insert("ber", at: start.addingTimeInterval(2))
    XCTAssertEqual(session.typed, "amber")
  }

  func testConfidenceModePreventsReturningToAnIncorrectPreviousWord() {
    let rules = InputRules(confidenceMode: .on)
    var session = TypingSession(
      configuration: .words(3, rules: rules), prompt: "amber bay cedar")
    session.insert("amber x ", at: start)
    session.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "amber x ")

    session.insert("b", at: start.addingTimeInterval(2))
    session.deleteBackward(at: start.addingTimeInterval(3))
    XCTAssertEqual(session.typed, "amber x ")
  }

  func testMaximumConfidenceModeDisablesBackspaceAndNormalizesConflicts() {
    let conflicting = InputRules(
      stopOnError: true, deleteOnError: true, freedomMode: true, confidenceMode: .maximum)
    let configuration = TestConfiguration.words(1, rules: conflicting)
    XCTAssertEqual(configuration.rules.confidenceMode, .maximum)
    XCTAssertFalse(configuration.rules.stopOnError)
    XCTAssertFalse(configuration.rules.deleteOnError)
    XCTAssertFalse(configuration.rules.freedomMode)

    var session = TypingSession(configuration: configuration, prompt: "amber")
    session.insert("am", at: start)
    session.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "am")
  }

  func testQuickRestartKeyMatchesOnlyItsConfiguredNativeKey() {
    XCTAssertTrue(QuickRestartKey.escape.matches(charactersIgnoringModifiers: "\u{1B}"))
    XCTAssertTrue(QuickRestartKey.tab.matches(charactersIgnoringModifiers: "\t"))
    XCTAssertTrue(QuickRestartKey.enter.matches(charactersIgnoringModifiers: "\r"))
    XCTAssertTrue(QuickRestartKey.enter.matches(charactersIgnoringModifiers: "\n"))
    XCTAssertFalse(QuickRestartKey.off.matches(charactersIgnoringModifiers: "\u{1B}"))
    XCTAssertFalse(QuickRestartKey.tab.matches(charactersIgnoringModifiers: "\r"))
  }

  func testClearCurrentWordOnErrorModifierKeepsCompletedWordsAndReplayInSync() {
    var session = TypingSession(
      configuration: .words(2).with(modifiers: [.clearCurrentWordOnError]),
      prompt: "amber bay")
    session.insert("amber b", at: start)
    session.insert("x", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "amber ")
    XCTAssertEqual(session.errors, 0)

    session.insert("bay", at: start.addingTimeInterval(2))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(
      TypingReplay.typedText(events: session.result()?.replayEvents ?? [], through: 2), "amber bay")
  }

  func testClearCurrentWordOnErrorModifierDoesNotClearChineseInput() {
    var session = TypingSession(
      configuration: .timed(seconds: 30, language: .simplifiedChinese)
        .with(modifiers: [.clearCurrentWordOnError]),
      prompt: "你好")
    session.insert("你", at: start)
    session.insert("x", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "你x")
  }

  func testTimeWarningsUseTheSelectedCountdownOffsetAndNeverRepeatWithinOneSecond() {
    XCTAssertTrue(
      TimeWarningPolicy.shouldPlay(remainingSeconds: 10, previousSecond: 11, offset: .tenSeconds))
    XCTAssertFalse(
      TimeWarningPolicy.shouldPlay(remainingSeconds: 10, previousSecond: 10, offset: .tenSeconds))
    XCTAssertTrue(
      TimeWarningPolicy.shouldPlay(remainingSeconds: 1, previousSecond: 2, offset: .oneSecond))
    XCTAssertFalse(
      TimeWarningPolicy.shouldPlay(remainingSeconds: 4, previousSecond: 5, offset: .fiveSeconds))
    XCTAssertFalse(
      TimeWarningPolicy.shouldPlay(remainingSeconds: 5, previousSecond: 6, offset: .off))
  }

  func testMinimumWordBurstFailsOnlyForSlowCorrectCommittedWords() {
    var rules = InputRules(minimumWordBurstWpm: 60)
    var slow = TypingSession(configuration: .words(2, rules: rules), prompt: "amber harbor")
    slow.insert("a", at: start)
    slow.insert("mber", at: start.addingTimeInterval(8))
    slow.insert(" ", at: start.addingTimeInterval(9))
    XCTAssertEqual(slow.outcome, .failed)
    XCTAssertEqual(slow.result()?.outcome, .failed)

    var incorrect = TypingSession(configuration: .words(2, rules: rules), prompt: "amber harbor")
    incorrect.insert("axber", at: start)
    incorrect.insert(" ", at: start.addingTimeInterval(9))
    XCTAssertEqual(incorrect.outcome, .active)

    rules.minimumWordBurstWpm = 0
    var disabled = TypingSession(configuration: .words(2, rules: rules), prompt: "amber harbor")
    disabled.insert("a", at: start)
    disabled.insert("mber", at: start.addingTimeInterval(8))
    disabled.insert(" ", at: start.addingTimeInterval(9))
    XCTAssertEqual(disabled.outcome, .active)
  }

  func testMinimumAccuracyFailsFiniteTestsOnlyWhenCompletionWouldOtherwiseSucceed() {
    let rules = InputRules(minimumAccuracy: 90)
    var failed = TypingSession(configuration: .words(2, rules: rules), prompt: "amber bay")
    failed.insert("axxer bay ", at: start)
    XCTAssertEqual(failed.accuracy, 80)
    XCTAssertEqual(failed.outcome, .failed)
    XCTAssertEqual(failed.result()?.outcome, .failed)

    var passing = TypingSession(configuration: .words(2, rules: rules), prompt: "amber bay")
    passing.insert("amber bay", at: start)
    XCTAssertEqual(passing.outcome, .completed)

    var disabled = TypingSession(configuration: .words(2, rules: .init()), prompt: "amber bay")
    disabled.insert("axxer bay ", at: start)
    XCTAssertEqual(disabled.outcome, .completed)
  }

  func testMinimumWpmFailsFiniteTestsOnlyWhenFinalPaceIsTooLow() {
    let rules = InputRules(minimumWpm: 10)
    var slow = TypingSession(configuration: .words(2, rules: rules), prompt: "amber bay")
    slow.insert("a", at: start)
    slow.insert("mber bay", at: start.addingTimeInterval(60))
    XCTAssertEqual(slow.outcome, .failed)

    var fast = TypingSession(configuration: .words(2, rules: rules), prompt: "amber bay")
    fast.insert("amber bay", at: start)
    XCTAssertEqual(fast.outcome, .completed)
  }

  func testFreedomModeOnlyAllowsDeletingCommittedCorrectWordsWhenEnabled() {
    let prompt = "amber harbor"
    var protectedSession = TypingSession(configuration: .words(2), prompt: prompt)
    protectedSession.insert("amber ", at: start)
    protectedSession.deleteBackward()
    XCTAssertEqual(protectedSession.typed, "amber ")

    var incorrectWordSession = TypingSession(configuration: .words(2), prompt: prompt)
    incorrectWordSession.insert("amberx ", at: start)
    incorrectWordSession.deleteBackward()
    XCTAssertEqual(incorrectWordSession.typed, "amberx")

    var freeSession = TypingSession(
      configuration: .words(2, rules: .init(freedomMode: true)), prompt: prompt)
    freeSession.insert("amber ", at: start)
    freeSession.deleteBackward()
    XCTAssertEqual(freeSession.typed, "amber")
  }

  func testBlindModeKeepsInputForMetricsWithoutChangingValidation() {
    var session = TypingSession(
      configuration: .timed(seconds: 30, rules: .init(blindMode: true)), prompt: "amber")
    session.insert("ax", at: start)
    XCTAssertEqual(session.typed, "ax")
    XCTAssertEqual(session.errors, 1)
    XCTAssertEqual(session.accuracy, 50)
  }

  func testStrictSpaceRejectsPrematureSpace() {
    var rules = InputRules()
    rules.strictSpace = true
    var session = TypingSession(
      configuration: .timed(seconds: 30, rules: rules), prompt: "amber harbor")
    session.insert("am ", at: start)
    XCTAssertEqual(session.typed, "am")
  }

  func testStatsUseCorrectCharactersAndFixedClock() {
    var session = TypingSession(configuration: .timed(seconds: 30), prompt: "amber")
    session.insert("amxzr", at: start)
    XCTAssertEqual(session.errors, 2)
    XCTAssertEqual(session.accuracy, 60)
    XCTAssertEqual(session.wpm(at: start.addingTimeInterval(12)), 3)
    XCTAssertEqual(session.rawWpm(at: start.addingTimeInterval(12)), 5)
  }

  func testBurstUsesAcceptedCharactersFromTheCurrentOrLatestCommittedWord() {
    var session = TypingSession(configuration: .timed(seconds: 30), prompt: "amber harbor")
    session.insert("a", at: start)
    session.insert("m", at: start.addingTimeInterval(0.1))
    XCTAssertEqual(session.burstWpm, 360)

    session.insert("ber ", at: start.addingTimeInterval(0.5))
    XCTAssertEqual(session.burstWpm, 144)

    session.insert("h", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.burstWpm, 144)
    session.insert("a", at: start.addingTimeInterval(1.1))
    XCTAssertEqual(session.burstWpm, 360)
  }

  func testRecentWordBurstHistoryKeepsTheLatestEightCommittedWords() {
    var session = TypingSession(
      configuration: .timed(seconds: 60),
      prompt: Array(repeating: "a", count: 10).joined(separator: " "))
    for index in 0..<10 {
      let wordStart = start.addingTimeInterval(Double(index + 1))
      session.insert("a", at: wordStart)
      session.insert(" ", at: wordStart.addingTimeInterval(0.1))
    }
    XCTAssertEqual(session.recentWordBursts.count, 8)
    XCTAssertTrue(session.recentWordBursts.allSatisfy { $0 > 0 })
  }

  func testWordBurstHistoryTracksAttemptedWordsAndLeavesSingleEventWordsNeutral() {
    var session = TypingSession(configuration: .timed(seconds: 30), prompt: "amber bay")
    session.insert("a", at: start)
    session.insert("mber ", at: start.addingTimeInterval(0.5))
    session.insert("b", at: start.addingTimeInterval(1))
    session.insert("ay", at: start.addingTimeInterval(1.4))

    XCTAssertEqual(session.wordReviews.count, 2)
    XCTAssertEqual(session.wordBurstHistory, [144, 120])

    var singleEvent = TypingSession(configuration: .timed(seconds: 30), prompt: "amber bay")
    singleEvent.insert("amber ", at: start)
    XCTAssertEqual(singleEvent.wordBurstHistory, [nil])
  }

  func testMissedWordsIncludesOnlyAttemptedIncorrectSpaceDelimitedTargetsWithoutDuplicates() {
    var session = TypingSession(
      configuration: .timed(seconds: 30), prompt: "amber harbor amber quiet")
    session.insert("amber habxxx amber ", at: start)
    XCTAssertEqual(session.missedWords, ["harbor"])

    var partial = TypingSession(configuration: .timed(seconds: 30), prompt: "amber harbor quiet")
    partial.insert("amx", at: start)
    XCTAssertEqual(partial.missedWords, ["amber"])

    var chinese = TypingSession(
      configuration: .timed(seconds: 30, language: .simplifiedChinese), prompt: "晨光窗边")
    chinese.insert("晨x", at: start)
    XCTAssertTrue(chinese.missedWords.isEmpty)

    var spanish = TypingSession(
      configuration: .timed(seconds: 30, language: .spanish), prompt: "árbol puerto calma")
    spanish.insert("árbol puertx ", at: start)
    XCTAssertEqual(spanish.missedWords, ["puerto"])
  }

  func testWordReviewsPairOnlyAttemptedWordsWithTheirTargetAndTypedValue() {
    var session = TypingSession(configuration: .timed(seconds: 30), prompt: "amber harbor quiet")
    session.insert("amber habxxx ", at: start)

    XCTAssertEqual(
      session.wordReviews,
      [
        .init(index: 0, target: "amber", typed: "amber"),
        .init(index: 1, target: "harbor", typed: "habxxx"),
      ])
    XCTAssertTrue(session.wordReviews[0].isCorrect)
    XCTAssertFalse(session.wordReviews[1].isCorrect)
  }

  func testKeyboardGuideHighlightsOnlySupportedNextKeys() {
    var session = TypingSession(configuration: .timed(seconds: 30), prompt: "a 1，")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: session.nextExpectedCharacter), "home-0")
    session.insert("a", at: start)
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: session.nextExpectedCharacter), "space")
    session.insert(" ", at: start)
    XCTAssertEqual(
      KeyboardGuideModel.highlightedKey(for: session.nextExpectedCharacter), "number-0")
    session.insert("1", at: start)
    XCTAssertNil(KeyboardGuideModel.highlightedKey(for: session.nextExpectedCharacter))
  }

  func testKeyboardGuideUsesTheSelectedLayoutAndSupportsAsciiPunctuation() {
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "q", layout: .ansiQwerty), "top-0")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "q", layout: .ansiDvorak), "bottom-1")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "/", layout: .ansiDvorak), "top-10")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "_", layout: .ansiDvorak), "number-10")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "?", layout: .ansiDvorak), "top-10")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "e", layout: .ansiColemak), "home-7")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: ";", layout: .ansiColemak), "top-9")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "e", layout: .ansiWorkman), "home-7")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: ";", layout: .ansiWorkman), "top-9")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "r", layout: .ansiWorkman), "top-2")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "a", layout: .frenchAzerty), "top-0")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "q", layout: .frenchAzerty), "home-0")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "é", layout: .frenchAzerty), "number-1")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "à", layout: .frenchAzerty), "number-9")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: ".", layout: .frenchAzerty), "bottom-7")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "_", layout: .ansiQwerty), "number-10")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "_", layout: .frenchAzerty), "number-7")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "，", layout: .ansiDvorak), nil)
  }

  func testNonDefaultKeyboardLayoutsEmulatePhysicalAnsiKeyPositions() {
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(
        forKeyCode: 13, modifierFlags: [], layout: .ansiDvorak), ",")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(
        forKeyCode: 13, modifierFlags: [.shift], layout: .ansiDvorak), "<")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(
        forKeyCode: 1, modifierFlags: [], layout: .ansiColemak), "r")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(
        forKeyCode: 13, modifierFlags: [], layout: .ansiWorkman), "d")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(
        forKeyCode: 12, modifierFlags: [], layout: .frenchAzerty), "a")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(
        forKeyCode: 18, modifierFlags: [.shift], layout: .frenchAzerty), "1")
    XCTAssertNil(
      KeyboardLayoutEmulator.character(
        forKeyCode: 0, modifierFlags: [], layout: .ansiQwerty))
    XCTAssertNil(
      KeyboardLayoutEmulator.character(
        forKeyCode: 0, modifierFlags: [.option], layout: .ansiDvorak))
  }

  @MainActor
  func testNativeInputKeepsMarkedCompositionOutOfTheTypingEngineUntilCommit() {
    let input = TypingInputView(frame: .zero)
    var markedText = [String]()
    var insertedText = [String]()
    input.onCompositionChanged = { markedText.append($0) }
    input.onInsert = { text, _ in insertedText.append(text) }

    input.setMarkedText("拼", selectedRange: NSRange(location: 0, length: 1), replacementRange: .init())
    XCTAssertEqual(markedText, ["拼"])
    XCTAssertTrue(insertedText.isEmpty)
    XCTAssertTrue(input.hasMarkedText())

    input.insertText("拼", replacementRange: .init())
    XCTAssertEqual(markedText, ["拼", ""])
    XCTAssertEqual(insertedText, ["拼"])
    XCTAssertFalse(input.hasMarkedText())
  }

  func testOppositeShiftPolicyAllowsCentreKeysAndRequiresTheOtherHandElsewhere() {
    XCTAssertFalse(
      OppositeShiftPolicy.usesOppositeShift(
        keyCode: 0, leftShiftPressed: true, rightShiftPressed: false))
    XCTAssertTrue(
      OppositeShiftPolicy.usesOppositeShift(
        keyCode: 4, leftShiftPressed: true, rightShiftPressed: false))
    XCTAssertTrue(
      OppositeShiftPolicy.usesOppositeShift(
        keyCode: 16, leftShiftPressed: true, rightShiftPressed: false))
    XCTAssertTrue(
      OppositeShiftPolicy.usesOppositeShift(
        keyCode: 11, leftShiftPressed: false, rightShiftPressed: true))
    XCTAssertTrue(
      OppositeShiftPolicy.usesOppositeShift(
        keyCode: 0, leftShiftPressed: false, rightShiftPressed: false))
    XCTAssertEqual(KeyboardLayoutEmulator.keyCode(for: "a", layout: .ansiDvorak), 0)
    XCTAssertEqual(KeyboardLayoutEmulator.keyCode(for: "p", layout: .ansiDvorak), 15)
    XCTAssertEqual(KeyboardLayoutEmulator.keyCode(for: "A", layout: .frenchAzerty), 12)
    XCTAssertEqual(KeyboardLayoutEmulator.keyCode(for: "@", layout: .ansiQwerty), 19)
    XCTAssertFalse(
      OppositeShiftPolicy.usesOppositeShift(
        keyCode: try! XCTUnwrap(KeyboardLayoutEmulator.keyCode(for: "p", layout: .ansiDvorak)),
        leftShiftPressed: true,
        rightShiftPressed: false))
  }

  func testForcedPhysicalInputErrorRetainsTypedTextButChangesMetricsReviewsAndReplay() {
    var session = TypingSession(configuration: .words(2), prompt: "a b ")
    let start = Date(timeIntervalSince1970: 1_000)
    session.insert("a", forceError: true, at: start)
    session.insert(" ", at: start.addingTimeInterval(0.2))
    session.insert("b", at: start.addingTimeInterval(0.4))

    XCTAssertEqual(session.typed, "a b")
    XCTAssertEqual(session.errors, 1)
    XCTAssertEqual(session.accuracy, 67)
    XCTAssertEqual(session.promptGlyphs[0].state, .incorrect)
    XCTAssertEqual(session.wordReviews.first?.typed, "a")
    XCTAssertFalse(session.wordReviews.first?.isCorrect ?? true)
    XCTAssertTrue(session.missedWords.contains("a"))
    XCTAssertTrue(session.result(at: start.addingTimeInterval(1))?.replayEvents.first?.forceError ?? false)
  }

  func testCodePracticeAutoIndentsUnindentsReplaysAndFinishesWordMode() {
    let configuration = TestConfiguration.words(
      1, rules: .init(codeUnindentOnBackspace: true), language: .codeSwift)
    let start = Date(timeIntervalSince1970: 2_000)
    var session = TypingSession(configuration: configuration, prompt: "if ready {\n\tgo()\n}")

    session.insert("if ready {\n", at: start)
    XCTAssertEqual(session.typed, "if ready {\n\t")

    session.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "if ready {")

    session.insert("\ngo()\n}", at: start.addingTimeInterval(2))
    XCTAssertTrue(session.isFinished)
    XCTAssertEqual(session.typed, "if ready {\n\tgo()\n}")
    let replayEvents = session.result(at: start.addingTimeInterval(2))?.replayEvents ?? []
    XCTAssertTrue(replayEvents.contains(where: \ .automatic))
    XCTAssertEqual(TypingReplay.typedText(events: replayEvents, through: 2), session.typed)
  }

  func testEveryOfficialCodeLanguageHasAnOriginalPromptAndCompletesCodeMode() {
    let languages = TypingLanguage.allCases.filter(\.isCodeLanguage)
    let expectedDisplayNames: Set<String> = [
      "ABAP", "ABAP 1k", "Arduino", "Assembly", "Bash", "Brainf*ck", "C", "C#", "C++",
      "COBOL", "CSS", "CUDA", "Clojure", "Common Lisp", "Dart", "Elixir", "Erlang", "F#",
      "Fortran", "GDScript", "GDScript 2", "Gleam", "Go", "Haskell", "HTML", "Java",
      "JavaScript", "JavaScript 1k", "JavaScript React", "Julia", "Jule", "Kotlin", "LaTeX", "Lua", "Luau",
      "MATLAB", "Nim", "Nix", "OCaml", "Odin", "Ook!", "OpenCL", "PHP", "Pascal", "Perl",
      "PowerShell", "Python", "Python 1k", "Python 2k", "Python 5k", "R", "R 2k", "Rockstar",
      "Ruby", "Rust", "SQL", "Scala", "Swift", "SystemVerilog", "TypeScript", "Typst", "V",
      "VHDL", "Vim", "Vimscript", "Visual Basic", "YoptaScript", "Zig", "6502 Assembly",
    ]
    XCTAssertEqual(languages.count, 69)
    XCTAssertEqual(Set(languages), Set(CodeLanguageCatalog.displayNames.keys))
    XCTAssertEqual(Set(languages.map(\.displayName)), Set(expectedDisplayNames.map { "Code · \($0)" }))

    let start = Date(timeIntervalSince1970: 3_000)
    for language in languages {
      let prompt = OfflineContent.generatedPrompt(
        wordCount: 9, language: language, contentOptions: .init())
      XCTAssertFalse(prompt.isEmpty, language.displayName)
      XCTAssertFalse(language.supportsQuotes, language.displayName)
      XCTAssertFalse(language.usesSpaceDelimitedWords, language.displayName)

      var session = TypingSession(configuration: .words(9, language: language), prompt: prompt)
      for character in prompt {
        if character == "\t", session.typed.last == "\t" { continue }
        session.insert(String(character), at: start)
      }
      XCTAssertTrue(session.isFinished, language.displayName)
      XCTAssertEqual(session.typed, prompt, language.displayName)
      XCTAssertEqual(session.result(at: start)?.prompt, prompt, language.displayName)
    }
  }

  func testPracticeTapePolicyAnchorsByWordOrCharacterWithoutChangingInput() {
    let typed = "alpha beta"
    XCTAssertEqual(PracticeTapePolicy.anchorCharacterIndex(typed: typed, mode: .off), 0)
    XCTAssertEqual(PracticeTapePolicy.anchorCharacterIndex(typed: typed, mode: .word), 6)
    XCTAssertEqual(PracticeTapePolicy.anchorCharacterIndex(typed: typed, mode: .letter), 10)
    XCTAssertEqual(
      PracticeTapePolicy.horizontalOffset(
        typed: typed, mode: .word, margin: 0.5, glyphWidth: 10, containerWidth: 100), 10)
    XCTAssertEqual(
      PracticeTapePolicy.horizontalOffset(
        typed: typed, mode: .letter, margin: 0.5, glyphWidth: 10, containerWidth: 100), 50)
    XCTAssertEqual(
      PracticeTapePolicy.horizontalOffset(
        typed: typed, mode: .off, margin: 0.5, glyphWidth: 10, containerWidth: 100), 0)
  }

  func testPracticeLineDisplayPolicyMatchesSupportedUntimedModes() {
    XCTAssertTrue(PracticeLineDisplayPolicy.shouldShowAllLines(
      settingEnabled: true, tapeMode: .off, testMode: .words, hasTimeLimit: false))
    XCTAssertTrue(PracticeLineDisplayPolicy.shouldShowAllLines(
      settingEnabled: true, tapeMode: .off, testMode: .quote, hasTimeLimit: false))
    XCTAssertTrue(PracticeLineDisplayPolicy.shouldShowAllLines(
      settingEnabled: true, tapeMode: .off, testMode: .custom, hasTimeLimit: false))

    XCTAssertFalse(PracticeLineDisplayPolicy.shouldShowAllLines(
      settingEnabled: false, tapeMode: .off, testMode: .words, hasTimeLimit: false))
    XCTAssertFalse(PracticeLineDisplayPolicy.shouldShowAllLines(
      settingEnabled: true, tapeMode: .letter, testMode: .words, hasTimeLimit: false))
    XCTAssertFalse(PracticeLineDisplayPolicy.shouldShowAllLines(
      settingEnabled: true, tapeMode: .off, testMode: .time, hasTimeLimit: true))
    XCTAssertFalse(PracticeLineDisplayPolicy.shouldShowAllLines(
      settingEnabled: true, tapeMode: .off, testMode: .custom, hasTimeLimit: true))
    XCTAssertFalse(PracticeLineDisplayPolicy.shouldShowAllLines(
      settingEnabled: true, tapeMode: .off, testMode: .zen, hasTimeLimit: false))
  }

  func testKeyboardMirrorTransformsOnlyAsciiPhysicalRowsAndPreservesComposedText() {
    XCTAssertEqual(KeyboardMirror.transform("qaz19"), "plm02")
    XCTAssertEqual(KeyboardMirror.transform("QAZ"), "PLM")
    XCTAssertEqual(KeyboardMirror.transform("á中"), "á中")
    XCTAssertEqual(
      KeyboardGuideModel.highlightedKey(for: KeyboardMirror.transform("a").first), "home-8")
  }

  func testCommandPaletteSearchNormalizesCaseAndMatchesKeywords() {
    let items = [
      CommandPaletteItem(
        id: "history", title: "打开练习历史", subtitle: "查看成绩", systemImage: "clock",
        keywords: ["history", "统计"]),
      CommandPaletteItem(
        id: "restart", title: "重新开始测试", subtitle: "当前配置", systemImage: "arrow",
        keywords: ["restart", "重开"]),
    ]

    XCTAssertEqual(CommandPaletteSearch.results(items: items, query: "  HISTORY "), [items[0]])
    XCTAssertEqual(CommandPaletteSearch.results(items: items, query: "统计"), [items[0]])
    XCTAssertEqual(CommandPaletteSearch.results(items: items, query: "重开"), [items[1]])
    XCTAssertEqual(CommandPaletteSearch.results(items: items, query: ""), items)
  }

  func testSettingsSearchMatchesEveryWhitespaceSeparatedTokenAcrossLocalizedTerms() {
    XCTAssertTrue(
      SettingsSearch.matches(query: "KEYBOARD layout", terms: ["键盘布局", "Keyboard Layout", "下一键"]))
    XCTAssertTrue(SettingsSearch.matches(query: "快速结束", terms: ["最后一词快速结束", "Quick End"]))
    XCTAssertFalse(SettingsSearch.matches(query: "账户 主题", terms: ["自建账户", "登录", "邮箱"]))
    XCTAssertTrue(SettingsSearch.matches(query: "   ", terms: ["任意设置"]))
  }

  func testTestConfigurationShareRoundTripsAndRejectsInvalidLinks() throws {
    let custom = SavedTestPreset(
      configuration: .init(
        mode: .custom, duration: nil, wordLimit: nil, difficulty: .expert,
        rules: .init(quickEnd: true, minimumWordBurstWpm: 90), language: .english), quoteID: nil,
      customText: "A locally shared practice passage.")
    let link = try TestConfigurationShare.link(for: custom)
    XCTAssertEqual(try TestConfigurationShare.preset(from: link), custom)

    XCTAssertThrowsError(try TestConfigurationShare.preset(from: "https://example.com/test"))
    XCTAssertThrowsError(
      try TestConfigurationShare.link(
        for: .init(configuration: .timed(seconds: 2), quoteID: nil, customText: nil)))
    XCTAssertThrowsError(
      try TestConfigurationShare.preset(from: "typebar://test?preset=not-base64"))
  }

  func testCustomTextPolicyBoundsEditorSharingAndArchiveImport() throws {
    let valid = String(repeating: "a", count: CustomTextPolicy.maximumLength)
    let oversized = valid + "b"
    XCTAssertEqual(CustomTextPolicy.clamped(oversized), valid)
    XCTAssertTrue(CustomTextPolicy.isValid(valid))
    XCTAssertFalse(CustomTextPolicy.isValid(oversized))

    let oversizedPreset = SavedTestPreset(
      configuration: .init(
        mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()),
      quoteID: nil,
      customText: oversized
    )
    XCTAssertThrowsError(try TestConfigurationShare.link(for: oversizedPreset))

    let archive = TypebarArchive(
      exportedAt: start, settings: .init(), results: [], presets: [],
      savedTexts: [
        .init(title: "Valid", text: "A valid local passage."),
        .init(title: "Oversized", text: oversized),
        .init(title: "", text: "Missing title"),
      ])
    XCTAssertEqual(
      TypebarArchiveMerge.savedTextsToInsert(from: archive, existing: []),
      [.init(title: "Valid", text: "A valid local passage.")])
  }

  func testResultSavingPolicyPersistsOnlyCompletedResultsWhenEnabled() {
    XCTAssertTrue(ResultSavingPolicy.shouldPersist(outcome: .completed, enabled: true))
    XCTAssertFalse(ResultSavingPolicy.shouldPersist(outcome: .completed, enabled: false))
    XCTAssertFalse(ResultSavingPolicy.shouldPersist(outcome: .failed, enabled: true))
    XCTAssertFalse(ResultSavingPolicy.shouldPersist(outcome: .abandoned, enabled: true))
  }

  func testCompletedStatusTextReflectsWhetherResultWasSaved() {
    XCTAssertEqual(TestOutcome.completed.statusText(savesResult: true), "本次完成 · 已保存到本机")
    XCTAssertEqual(TestOutcome.completed.statusText(savesResult: false), "本次完成 · 未保存为完成成绩")
  }

  func testCompletedSessionCreatesPortableResult() throws {
    var session = TypingSession(
      configuration: .init(
        mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()),
      prompt: "amber")
    session.insert("amber", at: start)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.outcome, .completed)
    XCTAssertEqual(result.typedCharacterCount, 5)
    XCTAssertEqual(result.correctCharacterCount, 5)
    XCTAssertEqual(result.configuration.mode, .custom)
    XCTAssertEqual(result.rawWpm, 60)
    XCTAssertEqual(result.prompt, "amber")
    XCTAssertEqual(result.replayEvents.map(\.kind), [.insert, .insert, .insert, .insert, .insert])
  }

  func testResultShareTextUsesOnlyLocalCompletedResultData() {
    let configuration = TestConfiguration.timed(seconds: 30, language: .english)
    let result = CompletedTestResult(
      id: UUID(), configuration: configuration, outcome: .completed, startedAt: start,
      finishedAt: start.addingTimeInterval(30), typedCharacterCount: 12, correctCharacterCount: 11,
      errorCount: 1, wpm: 72, rawWpm: 74, accuracy: 91, prompt: "amber harbor", replayEvents: [])
    XCTAssertEqual(
      ResultShareText.make(for: result), "Typebar\n72 WPM · 91% 准确率 · 1 错误\ntime · english · 30 秒")
  }

  func testReplayRebuildsAcceptedInsertsAndDeletesAtRecordedTimes() {
    var session = TypingSession(
      configuration: .init(
        mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()),
      prompt: "amber")
    session.insert("ax", at: start)
    session.deleteBackward(at: start.addingTimeInterval(1))
    session.insert("mber", at: start.addingTimeInterval(2))
    let result = session.result(at: start.addingTimeInterval(2))

    XCTAssertEqual(TypingReplay.typedText(events: result?.replayEvents ?? [], through: 0), "ax")
    XCTAssertEqual(TypingReplay.typedText(events: result?.replayEvents ?? [], through: 1), "a")
    XCTAssertEqual(TypingReplay.typedText(events: result?.replayEvents ?? [], through: 2), "amber")
  }

  func testExtraCharactersNeverCauseAnOutOfBoundsRead() {
    var session = TypingSession(configuration: .timed(seconds: 30), prompt: "a")
    session.insert("abc", at: start)
    XCTAssertEqual(session.typed, "abc")
  }

  func testPromptPresentationMarksCorrectIncorrectCurrentExtraAndBlindCharacters() {
    let active = TypingPromptPresentation.glyphs(
      target: "amber", typed: "ax", isFinished: false, blindMode: false)
    XCTAssertEqual(
      active,
      [
        .init(character: "a", state: .correct),
        .init(character: "m", state: .incorrect, typedCharacter: "x"),
        .init(character: "b", state: .current),
        .init(character: "e", state: .pending),
        .init(character: "r", state: .pending),
      ])

    let extra = TypingPromptPresentation.glyphs(
      target: "a", typed: "ax", isFinished: false, blindMode: false)
    XCTAssertEqual(
      extra,
      [
        .init(character: "a", state: .correct),
        .init(character: "x", state: .extra),
      ])

    let blind = TypingPromptPresentation.glyphs(
      target: "a", typed: "ax", isFinished: false, blindMode: true)
    XCTAssertEqual(
      blind,
      [
        .init(character: "a", state: .hidden),
        .init(character: "x", state: .hidden),
      ])
  }

  func testTypedCharacterEffectsOnlySelectCompletedPromptWords() {
    XCTAssertEqual(
      TypedCharacterEffectPolicy.completedCharacterIndices(
        target: "amber bay quiet", typed: "amxer ", isFinished: false),
      Set(0..<5))
    XCTAssertEqual(
      TypedCharacterEffectPolicy.completedCharacterIndices(
        target: "amber bay", typed: "amber bay", isFinished: true),
      Set(0..<5).union(6..<9))
    XCTAssertTrue(
      TypedCharacterEffectPolicy.completedCharacterIndices(
        target: "amber bay", typed: "amber", isFinished: false).isEmpty)
  }

  func testAttentionWarningsRespectFocusLanguageCompletionAndPreferences() {
    XCTAssertEqual(
      TypingAttentionPolicy.warnings(
        isInputFocused: false, capsLockEnabled: true, language: .english, isFinished: false,
        showFocusWarning: true, showCapsLockWarning: true),
      [.inputUnfocused, .capsLockEnabled]
    )
    XCTAssertEqual(
      TypingAttentionPolicy.warnings(
        isInputFocused: true, capsLockEnabled: true, language: .simplifiedChinese,
        isFinished: false, showFocusWarning: true, showCapsLockWarning: true),
      []
    )
    XCTAssertEqual(
      TypingAttentionPolicy.warnings(
        isInputFocused: false, capsLockEnabled: true, language: .mixedEnglishChinese,
        isFinished: true, showFocusWarning: true, showCapsLockWarning: true),
      []
    )
    XCTAssertEqual(
      TypingAttentionPolicy.warnings(
        isInputFocused: false, capsLockEnabled: true, language: .english, isFinished: false,
        showFocusWarning: false, showCapsLockWarning: false),
      []
    )
  }

  func testSessionFactoryUsesACompletePromptForEveryMode() {
    let timed = TestSessionFactory.make(configuration: .timed(seconds: 120))
    let words = TestSessionFactory.make(configuration: .words(25))
    let quote = TestSessionFactory.make(
      configuration: .init(
        mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()),
      quote: OfflineContent.quotes[1])
    let zen = TestSessionFactory.make(
      configuration: .init(
        mode: .zen, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()))
    let custom = TestSessionFactory.make(
      configuration: .init(
        mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()),
      customText: "own text")

    XCTAssertGreaterThanOrEqual(timed.prompt.split(separator: " ").count, 480)
    XCTAssertEqual(words.prompt.split(separator: " ").count, 25)
    XCTAssertEqual(quote.prompt, OfflineContent.quotes[1].text)
    XCTAssertGreaterThanOrEqual(zen.prompt.split(separator: " ").count, 10_000)
    XCTAssertEqual(custom.prompt, "own text")
  }

  func testSimplifiedChineseWordsUseOriginalUnspacedTermsAndFinishAtLimit() {
    let configuration = TestConfiguration.words(10, language: .simplifiedChinese)
    var session = TestSessionFactory.make(configuration: configuration)
    XCTAssertFalse(session.prompt.contains(" "))
    XCTAssertEqual(session.prompt.count, 20)

    session.insert(session.prompt, at: start)
    XCTAssertEqual(session.outcome, .completed)
  }

  func testMixedEnglishChineseUsesOnlyTypebarOwnedCorporaAndSpaceDelimitedWordCompletion() {
    let configuration = TestConfiguration.words(
      8, language: .mixedEnglishChinese, englishVariant: .british)
    var session = TestSessionFactory.make(configuration: configuration)
    let tokens = session.prompt.split(separator: " ").map(String.init)

    XCTAssertEqual(tokens.count, 8)
    XCTAssertTrue(
      tokens.enumerated().allSatisfy { index, token in
        index.isMultiple(of: 2)
          ? StarterLexicon.britishWords.contains(token)
          : StarterLexicon.simplifiedChineseWords.contains(token)
      })
    XCTAssertFalse(TypingLanguage.mixedEnglishChinese.supportsQuotes)
    XCTAssertTrue(OfflineContent.quotes(for: .mixedEnglishChinese).isEmpty)
    XCTAssertTrue(session.wordReviews.isEmpty)

    session.insert(session.prompt, at: start)
    XCTAssertEqual(session.outcome, .completed)
  }

  func testMixedLanguagesCyclesOnlyTypebarOwnedCorporaAndCompletesByWords() {
    let configuration = TestConfiguration.words(
      8, language: .mixedLanguages, englishVariant: .british)
    var session = TestSessionFactory.make(configuration: configuration)
    let tokens = session.prompt.split(separator: " ").map(String.init)
    let corpora = [
      StarterLexicon.britishWords, StarterLexicon.spanishWords, StarterLexicon.germanWords,
      StarterLexicon.frenchWords, StarterLexicon.italianWords, StarterLexicon.portugueseWords,
      StarterLexicon.simplifiedChineseWords,
    ]

    XCTAssertEqual(tokens.count, 8)
    XCTAssertTrue(
      tokens.enumerated().allSatisfy { corpora[$0.offset % corpora.count].contains($0.element) })
    XCTAssertTrue(TypingLanguage.mixedLanguages.usesSpaceDelimitedWords)
    XCTAssertFalse(TypingLanguage.mixedLanguages.supportsQuotes)
    session.insert(session.prompt, at: start)
    XCTAssertEqual(session.outcome, .completed)

    let selected = [TypingLanguage.italian, .french]
    let customConfiguration = TestConfiguration.words(
      6, language: .mixedLanguages, mixedLanguageComponents: selected)
    let customTokens = TestSessionFactory.make(configuration: customConfiguration).prompt.split(
      separator: " "
    ).map(String.init)
    XCTAssertTrue(
      customTokens.enumerated().allSatisfy { index, token in
        [StarterLexicon.italianWords, StarterLexicon.frenchWords][index % 2].contains(token)
      })
    XCTAssertEqual(customConfiguration.mixedLanguageComponents, selected)
    XCTAssertEqual(
      TypingLanguage.normalizedMixedComponents([.english]), TypingLanguage.defaultMixedComponents)
  }

  func testContentOptionsGenerateAndPersistNumbersAndPunctuation() {
    let options = ContentOptions(includePunctuation: true, includeNumbers: true)
    let configuration = TestConfiguration.words(10, language: .english, contentOptions: options)
    var session = TestSessionFactory.make(configuration: configuration)
    XCTAssertTrue(session.prompt.contains(where: { $0.isNumber }))
    XCTAssertTrue(session.prompt.contains(where: { ",.!?".contains($0) }))

    session.insert(session.prompt, at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.configuration.contentOptions, options)
  }

  func testOfflineCharacterStreamsOverrideBuiltInWordsWithoutExternalContent() {
    let binary = TestSessionFactory.make(
      configuration: TestConfiguration.words(3).with(modifiers: [.binaryStream]))
    XCTAssertEqual(
      binary.prompt.split(separator: " ").map(String.init), ["00000000", "00000001", "00000010"])
    let accounting = TestSessionFactory.make(
      configuration: TestConfiguration.words(2).with(modifiers: [.accountingStream]))
    XCTAssertTrue(
      accounting.prompt.split(separator: " ").allSatisfy {
        $0.contains(".") && $0.last.map(\.isNumber) == true
      })
    XCTAssertEqual(
      TestModifierPolicy.toggling(.accountingStream, in: [.binaryStream]), [.accountingStream])
    let hexadecimal = TestSessionFactory.make(
      configuration: TestConfiguration.words(2).with(modifiers: [.hexadecimalStream]))
    XCTAssertTrue(hexadecimal.prompt.split(separator: " ").allSatisfy { $0.hasPrefix("0x") })
    let symbols = TestSessionFactory.make(
      configuration: TestConfiguration.words(2).with(modifiers: [.symbolStream]))
    XCTAssertTrue(symbols.prompt.allSatisfy { "!@#$%^&*+=?/[]{}<>~ ".contains($0) })
    XCTAssertEqual(TestModifierPolicy.toggling(.symbolStream, in: [.binaryStream]), [.symbolStream])
    let ascii = TestSessionFactory.make(
      configuration: TestConfiguration.words(4).with(modifiers: [.asciiStream]))
    XCTAssertTrue(ascii.prompt.allSatisfy { $0 == " " || (33...126).contains($0.asciiValue ?? 0) })
    let specials = TestSessionFactory.make(
      configuration: TestConfiguration.words(4).with(modifiers: [.specialCharacterStream]))
    XCTAssertTrue(specials.prompt.allSatisfy { "`~!@#$%^&*()-_=+{}[]|\\/?:;,.<> ".contains($0) })
    XCTAssertEqual(
      TestModifierPolicy.toggling(.specialCharacterStream, in: [.asciiStream]),
      [.specialCharacterStream])
    let gibberish = TestSessionFactory.make(
      configuration: TestConfiguration.words(7).with(modifiers: [.gibberishStream]))
    XCTAssertTrue(gibberish.prompt.split(separator: " ").allSatisfy {
      (1...7).contains($0.count) && $0.allSatisfy { $0.isASCII && $0.isLowercase }
    })
    XCTAssertEqual(TestModifierPolicy.toggling(.gibberishStream, in: [.symbolStream]), [.gibberishStream])
    let poetry = TestSessionFactory.make(
      configuration: TestConfiguration.words(5).with(modifiers: [.poetryStream]))
    XCTAssertEqual(poetry.prompt.split(separator: " ").count, 5)
    XCTAssertTrue(poetry.prompt.allSatisfy { $0.isLetter || $0 == " " })
    XCTAssertEqual(TestModifierPolicy.toggling(.poetryStream, in: [.gibberishStream]), [.poetryStream])
    let reference = TestSessionFactory.make(
      configuration: TestConfiguration.words(6).with(modifiers: [.referenceStream]))
    XCTAssertEqual(reference.prompt.split(separator: " ").count, 6)
    XCTAssertTrue(reference.prompt.allSatisfy { $0.isLetter || $0 == " " })
    XCTAssertEqual(TestModifierPolicy.toggling(.referenceStream, in: [.poetryStream]), [.referenceStream])
    let arrows = TestSessionFactory.make(
      configuration: TestConfiguration.words(4).with(modifiers: [.arrowStream]))
    XCTAssertEqual(arrows.prompt.split(separator: " ").map(String.init), ["↑", "→", "↓", "←"])
    XCTAssertEqual(ArrowKeyInputPolicy.character(forKeyCode: 126), "↑")
    XCTAssertEqual(ArrowKeyInputPolicy.character(forKeyCode: 124), "→")
    XCTAssertEqual(ArrowKeyInputPolicy.character(forKeyCode: 125), "↓")
    XCTAssertEqual(ArrowKeyInputPolicy.character(forKeyCode: 123), "←")
    XCTAssertNil(ArrowKeyInputPolicy.character(forKeyCode: 0))
    XCTAssertEqual(TestModifierPolicy.toggling(.arrowStream, in: [.symbolStream]), [.arrowStream])
    let ipv4 = TestSessionFactory.make(
      configuration: TestConfiguration.words(2).with(modifiers: [.ipv4Stream]))
    XCTAssertTrue(
      ipv4.prompt.split(separator: " ").allSatisfy { $0.split(separator: ".").count == 4 })
    let ipv6 = TestSessionFactory.make(
      configuration: TestConfiguration.words(2).with(modifiers: [.ipv6Stream]))
    XCTAssertTrue(
      ipv6.prompt.split(separator: " ").allSatisfy { $0.split(separator: ":").count == 4 })
    XCTAssertEqual(TestModifierPolicy.toggling(.ipv6Stream, in: [.ipv4Stream]), [.ipv6Stream])
    let pseudolang = TestSessionFactory.make(
      configuration: TestConfiguration.words(2).with(modifiers: [.pseudolangStream]))
    XCTAssertTrue(pseudolang.prompt.split(separator: " ").allSatisfy { $0.allSatisfy(\.isLetter) })
    let morse = TestSessionFactory.make(
      configuration: TestConfiguration.words(2).with(modifiers: [.morseStream]))
    XCTAssertTrue(morse.prompt.allSatisfy { ".-/ ".contains($0) })
    XCTAssertEqual(
      TestModifierPolicy.toggling(.morseStream, in: [.pseudolangStream]), [.morseStream])
  }

  @MainActor
  func testNativeInputBridgeSendsArrowKeysToTheTypingEngineOnlyInArrowMode() throws {
    var accepted = [String]()
    let view = TypingInputView()
    view.onInsert = { text, _ in accepted.append(text) }
    let up = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false,
        keyCode: 126))

    view.mapsArrowKeysToInput = true
    view.keyDown(with: up)
    XCTAssertEqual(accepted, ["↑"])

    accepted.removeAll()
    view.mapsArrowKeysToInput = false
    view.keyDown(with: up)
    XCTAssertTrue(accepted.isEmpty)
  }

  @MainActor
  func testNativeInputBridgeOnlySendsReturnWhenThePromptAcceptsNewlines() throws {
    var accepted = [String]()
    let view = TypingInputView()
    view.onInsert = { text, _ in accepted.append(text) }
    let enter = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false,
        keyCode: 36))

    view.quickRestartKey = .enter
    view.acceptsNewlineInput = true
    view.keyDown(with: enter)
    XCTAssertEqual(accepted, ["\n"])

    accepted.removeAll()
    view.acceptsNewlineInput = false
    view.keyDown(with: enter)
    XCTAssertTrue(accepted.isEmpty)
  }

  func testZipfFrequencyModifierUsesRankWeightedTypebarLexicon() {
    XCTAssertEqual(ZipfWordSelection.index(in: 24, random: { 0 }), 0)
    XCTAssertEqual(ZipfWordSelection.index(in: 24, random: { 0.999_999 }), 23)
    XCTAssertLessThan(ZipfWordSelection.index(in: 24, random: { 0.25 }), 12)

    let configuration = TestConfiguration.words(30).with(modifiers: [.zipf])
    let session = TestSessionFactory.make(configuration: configuration)
    let tokens = session.prompt.split(separator: " ").map(String.init)
    XCTAssertEqual(tokens.count, 30)
    XCTAssertTrue(tokens.allSatisfy(StarterLexicon.words.contains))
    XCTAssertEqual(
      TestModifierPolicy.toggling(.zipf, in: [.uppercase]), [.uppercase, .zipf])
  }

  func testTextBoundaryModifiersTransformPromptsFinishWordsAndRemainMutuallyExclusive() {
    let noSpaceConfiguration = TestConfiguration.words(2).with(modifiers: [.noSpaces])
    var noSpaceSession = TestSessionFactory.make(configuration: noSpaceConfiguration)
    XCTAssertFalse(noSpaceSession.prompt.contains(" "))
    noSpaceSession.insert(noSpaceSession.prompt, at: start)
    XCTAssertEqual(noSpaceSession.outcome, .completed)
    XCTAssertTrue(noSpaceSession.wordReviews.isEmpty)

    let underscoreConfiguration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
      modifiers: [.underscoreSeparators])
    let underscoreSession = TestSessionFactory.make(
      configuration: underscoreConfiguration, customText: "amber harbor")
    XCTAssertEqual(underscoreSession.prompt, "amber_harbor")

    XCTAssertEqual(TestModifierPolicy.normalized([.noSpaces, .underscoreSeparators]), [.noSpaces])
    XCTAssertEqual(
      TestModifierPolicy.toggling(.underscoreSeparators, in: [.noSpaces]), [.underscoreSeparators])

    let uppercaseConfiguration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
      modifiers: [.noSpaces, .uppercase])
    let uppercaseSession = TestSessionFactory.make(
      configuration: uppercaseConfiguration, customText: "amber harbor")
    XCTAssertEqual(uppercaseSession.prompt, "AMBERHARBOR")
    XCTAssertEqual(
      TestModifierPolicy.normalized([.noSpaces, .underscoreSeparators, .uppercase]),
      [.noSpaces, .uppercase])
    XCTAssertEqual(
      TestModifierPolicy.toggling(.uppercase, in: [.noSpaces]), [.noSpaces, .uppercase])
    XCTAssertEqual(
      TestModifierPolicy.toggling(.underscoreSeparators, in: [.noSpaces, .uppercase]),
      [.underscoreSeparators, .uppercase])

    let titleCase = TestSessionFactory.make(
      configuration: .init(
        mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
        modifiers: [.titleCase]),
      customText: "amber HARBOR 9lives"
    )
    XCTAssertEqual(titleCase.prompt, "Amber Harbor 9lives")
    let alternatingCase = TestSessionFactory.make(
      configuration: .init(
        mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
        modifiers: [.alternatingCase]),
      customText: "amber bay!"
    )
    XCTAssertEqual(alternatingCase.prompt, "aMbEr bAy!")
    let cipherAndBackwards = TestSessionFactory.make(
      configuration: .init(
        mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
        modifiers: [.rot13, .backwards]),
      customText: "amber bay"
    )
    XCTAssertEqual(cipherAndBackwards.prompt, "erozn lno")
    XCTAssertEqual(
      TestModifierPolicy.normalized([.uppercase, .titleCase, .alternatingCase]), [.uppercase])
    XCTAssertEqual(
      TestModifierPolicy.toggling(.titleCase, in: [.uppercase, .noSpaces]), [.noSpaces, .titleCase])

    let doubledConfiguration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
      modifiers: [.uppercase, .doubleCharacters])
    let doubledSession = TestSessionFactory.make(
      configuration: doubledConfiguration, customText: "amber bay")
    XCTAssertEqual(doubledSession.prompt, "AAMMBBEERR BBAAYY")
    XCTAssertEqual(
      TestModifierPolicy.normalized([.noSpaces, .doubleCharacters]), [.noSpaces, .doubleCharacters])

    var focusSession = TypingSession(
      configuration: .init(
        mode: .words, duration: nil, wordLimit: 3, difficulty: .normal, rules: .init(),
        modifiers: [.focusCurrentWord]), prompt: "amber harbor quiet")
    XCTAssertEqual(
      focusSession.promptGlyphs.map(\.state),
      [
        .current, .pending, .pending, .pending, .pending, .pending, .hidden, .hidden, .hidden,
        .hidden, .hidden, .hidden, .hidden, .hidden, .hidden, .hidden, .hidden, .hidden,
      ])
    focusSession.insert("amber ", at: start)
    XCTAssertEqual(focusSession.promptGlyphs[6].state, .current)
    XCTAssertEqual(focusSession.promptGlyphs[13].state, .hidden)

    let nextWordConfiguration = TestConfiguration(
      mode: .words, duration: nil, wordLimit: 4, difficulty: .normal, rules: .init(),
      modifiers: [.focusNextWord])
    var nextWordSession = TypingSession(
      configuration: nextWordConfiguration, prompt: "amber harbor quiet moss")
    XCTAssertEqual(nextWordSession.promptGlyphs[6].state, .pending)
    XCTAssertEqual(nextWordSession.promptGlyphs[13].state, .hidden)
    nextWordSession.insert("amber ", at: start)
    XCTAssertEqual(nextWordSession.promptGlyphs[13].state, .pending)
    XCTAssertEqual(nextWordSession.promptGlyphs[19].state, .hidden)
    XCTAssertEqual(
      TestModifierPolicy.toggling(.focusTwoWords, in: [.focusCurrentWord, .uppercase]),
      [.uppercase, .focusTwoWords])
    XCTAssertEqual(
      TestConfiguration.words(3).with(modifiers: [.focusThreeWords]).visibleFutureWordCount, 3)

    var lazySession = TypingSession(
      configuration: .init(
        mode: .words, duration: nil, wordLimit: 2, difficulty: .normal, rules: .init(),
        modifiers: [.correctBeforeAdvance]), prompt: "amber bay")
    lazySession.insert("amxer ", at: start)
    XCTAssertEqual(lazySession.typed, "amxer")
    lazySession.deleteBackward(at: start)
    lazySession.deleteBackward(at: start)
    lazySession.deleteBackward(at: start)
    lazySession.insert("ber ", at: start)
    XCTAssertEqual(lazySession.typed, "amber ")
  }

  func testRandomCaseModifierChangesOnlyAsciiLetterCaseAndConflictsWithOtherCaseModes() {
    var bits = [true, false, false, true]
    let transformed = RandomCasePolicy.transformed("Ab-cD 7") { bits.removeFirst() }
    XCTAssertEqual(transformed, "Ab-cD 7")

    let randomCase = TestModifierPolicy.transformed("amber bay!", modifiers: [.randomCase])
    XCTAssertEqual(randomCase.lowercased(), "amber bay!")
    XCTAssertEqual(
      TestModifierPolicy.toggling(.randomCase, in: [.uppercase, .noSpaces]),
      [.noSpaces, .randomCase])
    XCTAssertEqual(
      TestModifierPolicy.normalized([.randomCase, .alternatingCase]), [.alternatingCase])
  }

  func testMessagingStyleUsesLowercaseShortLinesAndConflictsWithCaseModes() {
    XCTAssertEqual(
      MessagingTextPolicy.transformed("Hello, World! (Next?) \"Ready.\""),
      "hello, world\n next\n ready")
    XCTAssertEqual(
      TestModifierPolicy.transformed("Hi! There?", modifiers: [.messagingStyle]), "hi\n there")
    XCTAssertEqual(
      TestModifierPolicy.toggling(.messagingStyle, in: [.uppercase, .noSpaces]),
      [.noSpaces, .messagingStyle])
  }

  func testVisualModifiersApplyOnlyToThePracticePresentation() {
    XCTAssertEqual(PracticeVisualTransform.make(modifiers: []), .init(horizontalScale: 1, rotationDegrees: 0))
    XCTAssertEqual(
      PracticeVisualTransform.make(modifiers: [.mirrorVisual]),
      .init(horizontalScale: -1, rotationDegrees: 0))
    XCTAssertEqual(
      PracticeVisualTransform.make(modifiers: [.mirrorVisual, .upsideDownVisual]),
      .init(horizontalScale: -1, rotationDegrees: 180))
    XCTAssertEqual(
      TestModifierPolicy.transformed("amber", modifiers: [.mirrorVisual, .upsideDownVisual]), "amber")
    XCTAssertEqual(PracticeVisualEffect.make(modifiers: []).usesCRT, false)
    XCTAssertEqual(PracticeVisualEffect.make(modifiers: [.crtVisual]).usesCRT, true)
    XCTAssertEqual(PracticeVisualEffect.make(modifiers: [.earthquakeVisual]).usesEarthquake, true)
    XCTAssertEqual(PracticeVisualEffect.make(modifiers: [.spaceVisual]).usesSpace, true)
    XCTAssertEqual(PracticeVisualEffect.make(modifiers: [.nauseaVisual]).usesNausea, true)
    XCTAssertEqual(PracticeVisualEffect.make(modifiers: [.roundVisual]).usesRound, true)
    XCTAssertEqual(PracticeVisualEffect.make(modifiers: [.chooVisual]).usesChoo, true)
    XCTAssertEqual(PracticeVisualEffect.make(modifiers: [.aslVisual]).usesASL, true)
    XCTAssertTrue(TestModifierPolicy.normalized([.layoutFluid]).contains(.layoutFluid))
    XCTAssertEqual(
      EarthquakeOffsetPolicy.offset(at: start, isEnabled: true, reducesMotion: true).x, 0)
    XCTAssertEqual(EarthquakeOffsetPolicy.offset(at: start, isEnabled: false, reducesMotion: false).y, 0)
        let firstStar = StarfieldPolicy.point(index: 0, in: .init(width: 100, height: 100))
        XCTAssertEqual(firstStar.x, 29, accuracy: 0.000_001)
        XCTAssertEqual(firstStar.y, 11.458_333_333_333_334, accuracy: 0.000_001)
    XCTAssertEqual(
      NauseaVisualPolicy.transform(at: start, isEnabled: false, reducesMotion: false), .identity)
    XCTAssertEqual(
      NauseaVisualPolicy.transform(at: start, isEnabled: true, reducesMotion: true), .identity)
    let nauseaTransform = NauseaVisualPolicy.transform(at: start, isEnabled: true, reducesMotion: false)
    XCTAssertNotEqual(nauseaTransform, .identity)
    XCTAssertGreaterThan(nauseaTransform.horizontalScale, 0)
    XCTAssertGreaterThan(nauseaTransform.verticalScale, 0)
    XCTAssertEqual(RoundVisualPolicy.rotationDegrees(at: start, isEnabled: false, reducesMotion: false), 0)
    XCTAssertEqual(RoundVisualPolicy.rotationDegrees(at: start, isEnabled: true, reducesMotion: true), 0)
    XCTAssertGreaterThanOrEqual(
      RoundVisualPolicy.rotationDegrees(at: start, isEnabled: true, reducesMotion: false), 0)
    XCTAssertLessThan(
      RoundVisualPolicy.rotationDegrees(at: start, isEnabled: true, reducesMotion: false), 360)
    XCTAssertEqual(
      ChooVisualPolicy.rotationDegrees(
        at: start, glyphIndex: 4, isEnabled: false, reducesMotion: false), 0)
    XCTAssertEqual(
      ChooVisualPolicy.rotationDegrees(
        at: start, glyphIndex: 4, isEnabled: true, reducesMotion: true), 0)
    XCTAssertNotEqual(
      ChooVisualPolicy.rotationDegrees(
        at: start, glyphIndex: 4, isEnabled: true, reducesMotion: false), 0)
    XCTAssertEqual(
      LayoutFluidPolicy.activeLayout(
        completedWords: 0, wordLimit: 30, layouts: [.ansiQwerty, .ansiColemak, .ansiDvorak]),
      .ansiQwerty)
    XCTAssertEqual(
      LayoutFluidPolicy.activeLayout(
        completedWords: 10, wordLimit: 30, layouts: [.ansiQwerty, .ansiColemak, .ansiDvorak]),
      .ansiColemak)
    XCTAssertEqual(
      LayoutFluidPolicy.upcomingLayout(
        completedWords: 8, wordLimit: 30, layouts: [.ansiQwerty, .ansiColemak, .ansiDvorak])?.layout,
      .ansiColemak)
    XCTAssertNotNil(ASLHandshapePolicy.fingerMask(for: "A"))
    XCTAssertNil(ASLHandshapePolicy.fingerMask(for: "7"))
    XCTAssertTrue(ASLHandshapePolicy.usesMotionCue(for: "J"))
    XCTAssertTrue(ASLHandshapePolicy.usesMotionCue(for: "z"))
    XCTAssertFalse(ASLHandshapePolicy.usesMotionCue(for: "A"))
  }

  func testListeningModifierPersistsWithoutChangingPromptText() {
    let modifiers = TestModifierPolicy.toggling(.listening, in: [.rot13, .doubleCharacters])
    XCTAssertTrue(modifiers.contains(.listening))
    XCTAssertEqual(
      TestModifierPolicy.transformed("amber harbor", modifiers: modifiers),
      "nnzzoorree uunneeoobbee")
  }

  func testMemoryModifierHidesPromptOnlyAfterTheFirstAcceptedInput() {
    let configuration = TestConfiguration.words(2).with(modifiers: [.memory])
    var session = TypingSession(configuration: configuration, prompt: "amber harbor")

    XCTAssertFalse(session.hasStarted)
    XCTAssertEqual(session.promptGlyphs.first?.state, .current)
    session.insert("a", at: start)
    XCTAssertTrue(session.hasStarted)
    XCTAssertEqual(
      session.promptGlyphs.map(\.state), Array(repeating: .hidden, count: session.prompt.count))

    XCTAssertEqual(
      TestModifierPolicy.toggling(.memory, in: [.listening, .focusNextWord]), [.memory])
    XCTAssertFalse(
      TestConfiguration(
        mode: .zen, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
        modifiers: [.memory]
      ).modifiers.contains(.memory))
  }

  func testSimonSaysHidesPendingCharactersButKeepsTheNextExpectedInputAvailable() {
    let configuration = TestConfiguration.words(2).with(modifiers: [.simonSays])
    var session = TypingSession(configuration: configuration, prompt: "amber bay")

    XCTAssertTrue(session.promptGlyphs.allSatisfy { $0.state == .hidden })
    XCTAssertEqual(session.nextExpectedCharacter, "a")
    session.insert("a", at: start)
    XCTAssertEqual(session.promptGlyphs[0].state, .correct)
    XCTAssertTrue(session.promptGlyphs.dropFirst().allSatisfy { $0.state == .hidden })
    XCTAssertEqual(TestModifierPolicy.toggling(.simonSays, in: [.memory]), [.simonSays])
  }

  func testReadAheadModifiersConcealTheConfiguredCurrentAndFutureWordsAfterStarting() {
    var session = TypingSession(
      configuration: TestConfiguration.words(4).with(modifiers: [.readAhead]),
      prompt: "amber harbor quiet moss")
    XCTAssertEqual(session.promptGlyphs.first?.state, .current)
    session.insert("a", at: start)
    XCTAssertEqual(session.promptGlyphs[0].state, .hidden)
    XCTAssertEqual(session.promptGlyphs[6].state, .hidden)
    XCTAssertEqual(session.promptGlyphs[13].state, .pending)
    session.insert("mber ", at: start)
    XCTAssertEqual(session.promptGlyphs[6].state, .hidden)
    XCTAssertEqual(session.promptGlyphs[13].state, .hidden)
    XCTAssertEqual(session.promptGlyphs[19].state, .pending)
    XCTAssertEqual(
      TestModifierPolicy.toggling(.readAheadHard, in: [.memory, .focusNextWord]), [.readAheadHard])
  }

  func testNoQuitModifierLocksOnlyAnActiveStartedSession() {
    var session = TypingSession(
      configuration: TestConfiguration.words(2).with(modifiers: [.noQuit]), prompt: "amber harbor")
    XCTAssertFalse(TypingRestartPolicy.isLocked(session))
    session.insert("a", at: start)
    XCTAssertTrue(TypingRestartPolicy.isLocked(session))
    session.abandon(at: start)
    XCTAssertFalse(TypingRestartPolicy.isLocked(session))
    XCTAssertTrue(TestModifierPolicy.normalized([.noQuit, .uppercase]).contains(.noQuit))
  }

  func testRepeatingCustomTextSupportsWordAndTimeLimits() {
    let wordConfiguration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: 3, difficulty: .normal, rules: .init(),
      customTextCompletion: .words
    )
    var wordSession = TestSessionFactory.make(
      configuration: wordConfiguration, customText: "amber harbor")
    wordSession.insert("amber harbor amber", at: start)
    XCTAssertEqual(wordSession.outcome, .completed)
    XCTAssertEqual(wordSession.configuration.customTextCompletion, .words)

    let timeConfiguration = TestConfiguration(
      mode: .custom, duration: 5, wordLimit: nil, difficulty: .normal, rules: .init(),
      customTextCompletion: .time
    )
    var timeSession = TestSessionFactory.make(configuration: timeConfiguration, customText: "amber")
    timeSession.insert("amber amber ", at: start)
    XCTAssertTrue(timeSession.prompt.hasPrefix("amber amber amber"))
    XCTAssertEqual(timeSession.outcome, .active)
    timeSession.tick(at: start.addingTimeInterval(5))
    XCTAssertEqual(timeSession.outcome, .completed)
  }

  func testPipeDelimitedCustomTextCompletesTheRequestedSections() {
    let configuration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
      customTextCompletion: .sections, customTextSectionLimit: 2
    )
    var session = TestSessionFactory.make(
      configuration: configuration, customText: "amber harbor | quiet meadow | copper lantern")
    XCTAssertEqual(session.prompt, "amber harbor quiet meadow")
    XCTAssertEqual(session.sectionProgress?.total, 2)
    session.insert("amber harbor ", at: start)
    XCTAssertEqual(session.sectionProgress?.completed, 1)
    session.insert("quiet meadow", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(CustomTextPolicy.sections(in: "one|| two | "), ["one", "two"])
  }

  func testCustomTextOrderingUsesOnlyUserSuppliedTokens() {
    let text = "amber harbor quiet"
    let shuffled = CustomTextOrderPolicy.prompt(from: text, ordering: .shuffled, random: { 1 })
    XCTAssertEqual(
      shuffled.split(separator: " ").map(String.init).sorted(),
      text.split(separator: " ").map(String.init).sorted())
    XCTAssertNotEqual(shuffled, text)

    var randomIndex = 0
    let randomized = CustomTextOrderPolicy.prompt(
      from: text, ordering: .random,
      random: {
        defer { randomIndex += 1 }
        return randomIndex % 3
      })
    XCTAssertTrue(
      randomized.split(separator: " ").map(String.init).allSatisfy(
        ["amber", "harbor", "quiet"].contains))
    XCTAssertGreaterThan(randomized.split(separator: " ").count, 3)
    XCTAssertEqual(CustomTextOrderPolicy.prompt(from: text, ordering: .inOrder), text)
  }

  func testBritishEnglishUsesOnlyTypebarOwnedBritishSpellingCorpus() {
    let configuration = TestConfiguration.words(32, language: .english, englishVariant: .british)
    let session = TestSessionFactory.make(configuration: configuration)
    let words = Set(session.prompt.split(separator: " ").map(String.init))
    XCTAssertTrue(words.isSubset(of: Set(StarterLexicon.britishWords)))
    XCTAssertFalse(words.isEmpty)
  }

  func testGermanUsesOnlyTypebarOwnedUnicodeCorpusAndQuotes() {
    let prompt = OfflineContent.generatedPrompt(
      wordCount: 12, language: .german,
      contentOptions: .init(includePunctuation: true, includeNumbers: true))
    XCTAssertTrue(prompt.contains(" "))
    XCTAssertTrue(
      prompt.split(separator: " ").allSatisfy { token in
        let normalized = token.trimmingCharacters(
          in: CharacterSet.punctuationCharacters.union(.decimalDigits))
        return StarterLexicon.germanWords.contains(normalized)
      })
    XCTAssertEqual(OfflineContent.quotes(for: .german, length: .short).count, 1)
    XCTAssertEqual(OfflineContent.quotes(for: .german, length: .medium).count, 1)
    XCTAssertEqual(OfflineContent.quotes(for: .german, length: .long).count, 1)
    XCTAssertTrue(TypingLanguage.german.usesSpaceDelimitedWords)
    XCTAssertTrue(TypingLanguage.german.supportsQuotes)
  }

  func testFrenchItalianAndPortugueseUseOnlyTypebarOwnedCorporaAndQuotes() {
    for (language, lexicon) in [
      (TypingLanguage.french, StarterLexicon.frenchWords), (.italian, StarterLexicon.italianWords),
      (.portuguese, StarterLexicon.portugueseWords),
    ] {
      let prompt = OfflineContent.generatedPrompt(
        wordCount: 12, language: language,
        contentOptions: .init(includePunctuation: true, includeNumbers: true))
      XCTAssertTrue(
        prompt.split(separator: " ").allSatisfy { token in
          let normalized = token.trimmingCharacters(
            in: CharacterSet.punctuationCharacters.union(.decimalDigits))
          return lexicon.contains(normalized)
        })
      XCTAssertEqual(OfflineContent.quotes(for: language, length: .short).count, 1)
      XCTAssertEqual(OfflineContent.quotes(for: language, length: .medium).count, 1)
      XCTAssertEqual(OfflineContent.quotes(for: language, length: .long).count, 1)
      XCTAssertEqual(OfflineContent.quotes(for: language, length: .extended).count, 1)
      XCTAssertTrue(language.usesSpaceDelimitedWords)
      XCTAssertTrue(language.supportsQuotes)
    }
  }

  func testLazyLatinModifierNormalizesAccentsLigaturesAndGeneratedPrompts() {
    XCTAssertEqual(TypingTextNormalizer.lazyLatin("árvore Straße cœur Łódź"), "arvore Strasse coeur Lodz")
    let session = TestSessionFactory.make(
      configuration: .words(4, language: .german).with(modifiers: [.lazyLatin]))
    XCTAssertFalse(session.prompt.contains("ä"))
    XCTAssertFalse(session.prompt.contains("ü"))
    XCTAssertFalse(session.prompt.contains("ß"))
  }

  func testNativeSpeechUsesStableSystemLocalesForSupportedLanguages() {
    XCTAssertEqual(TypingLanguage.english.speechLocaleIdentifier, "en-US")
    XCTAssertEqual(TypingLanguage.spanish.speechLocaleIdentifier, "es-ES")
    XCTAssertEqual(TypingLanguage.german.speechLocaleIdentifier, "de-DE")
    XCTAssertEqual(TypingLanguage.french.speechLocaleIdentifier, "fr-FR")
    XCTAssertEqual(TypingLanguage.italian.speechLocaleIdentifier, "it-IT")
    XCTAssertEqual(TypingLanguage.portuguese.speechLocaleIdentifier, "pt-PT")
    XCTAssertEqual(TypingLanguage.simplifiedChinese.speechLocaleIdentifier, "zh-CN")
    XCTAssertEqual(TypingLanguage.mixedEnglishChinese.speechLocaleIdentifier, "zh-CN")
    XCTAssertEqual(TypingLanguage.mixedLanguages.speechLocaleIdentifier, "en-US")
  }

  func testWeakSpotPracticeUsesOnlyTypebarWordsAndCompletedLocalReplayErrors() {
    let result = CompletedTestResult(
      id: UUID(), configuration: .words(2, language: .english), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(10), typedCharacterCount: 12,
      correctCharacterCount: 11, errorCount: 1, wpm: 14, rawWpm: 14, accuracy: 92,
      prompt: "amber harbor", replayEvents: [.init(offset: 1, kind: .insert, text: "axber harbor")]
    )
    let prompt = try? XCTUnwrap(
      WeakSpotPractice.prompt(
        results: [result], language: .english, englishVariant: .american, wordCount: 6))
    XCTAssertNotNil(prompt)
    XCTAssertEqual(WeakSpotPractice.characterScores(results: [result], language: .english)["m"], 1)
    XCTAssertTrue(
      prompt?.split(separator: " ").allSatisfy { StarterLexicon.words.contains(String($0)) }
        ?? false)
    XCTAssertTrue(prompt?.contains("amber") ?? false)
    XCTAssertNil(
      WeakSpotPractice.prompt(results: [], language: .english, englishVariant: .american))
    XCTAssertNil(
      WeakSpotPractice.prompt(
        results: [result], language: .simplifiedChinese, englishVariant: .american))
  }

  func testModerationQueueStatesAndReportIdentifiersRemainStable() {
    XCTAssertEqual(
      RemoteQuoteModerationStatus.allCases.map(\.rawValue),
      ["pending", "approved", "rejected"]
    )
    let report = RemoteModerationQuoteReport(
      reason: .inaccurateAttribution,
      note: "Needs source review.",
      submittedAt: start
    )
    XCTAssertEqual(report.reason.displayName, "署名或来源不准确")
    XCTAssertFalse(report.id.isEmpty)
    XCTAssertEqual(RemoteQuoteModerationStatus.pending.displayName, "待审核")
    XCTAssertEqual(
      RemoteProfileModerationStatus.allCases.map(\.rawValue),
      ["open", "resolved", "dismissed"]
    )
    XCTAssertEqual(RemoteProfileModerationStatus.open.displayName, "待处理")
  }

  func testQuoteContentFiltersAndFallsBackByLanguage() {
    let chineseQuotes = OfflineContent.quotes(for: .simplifiedChinese)
    XCTAssertFalse(chineseQuotes.isEmpty)
    XCTAssertTrue(chineseQuotes.allSatisfy { $0.language == .simplifiedChinese })

    let configuration = TestConfiguration(
      mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
      language: .simplifiedChinese)
    let session = TestSessionFactory.make(configuration: configuration)
    XCTAssertEqual(session.prompt, chineseQuotes[0].text)

    let spanishQuotes = OfflineContent.quotes(for: .spanish)
    XCTAssertEqual(spanishQuotes.count, 7)
    XCTAssertTrue(spanishQuotes.allSatisfy { $0.language == .spanish })
    let spanishConfiguration = TestConfiguration.words(
      3, language: .spanish, contentOptions: .init(includePunctuation: true, includeNumbers: true))
    var spanishSession = TypingSession(
      configuration: spanishConfiguration, prompt: "árbol puente calma")
    spanishSession.insert("árbol puente calma", at: start)
    XCTAssertEqual(spanishSession.outcome, .completed)
    XCTAssertTrue(
      OfflineContent.generatedPrompt(
        wordCount: 12, language: .spanish,
        contentOptions: .init(includePunctuation: true, includeNumbers: true)
      ).split(separator: " ").count == 12)
  }

  func testQuoteLengthFiltersAndRepeatPolicyUseOnlyTypebarAuthoredQuotes() {
    let shortEnglish = OfflineContent.quotes(for: .english, length: .short)
    let longChinese = OfflineContent.quotes(for: .simplifiedChinese, length: .long)
    let extendedEnglish = OfflineContent.quotes(for: .english, length: .extended)
    XCTAssertFalse(shortEnglish.isEmpty)
    XCTAssertFalse(longChinese.isEmpty)
    XCTAssertEqual(extendedEnglish.count, 1)
    XCTAssertTrue(shortEnglish.allSatisfy { $0.length == .short && $0.language == .english })
    XCTAssertTrue(
      longChinese.allSatisfy { $0.length == .long && $0.language == .simplifiedChinese })
    XCTAssertTrue(extendedEnglish.allSatisfy { $0.length == .extended && $0.language == .english })

    let current = try! XCTUnwrap(shortEnglish.first)
    let next = OfflineContent.nextQuote(
      from: shortEnglish, currentID: current.id, allowsRepeat: false, index: 0)
    XCTAssertNotEqual(next?.id, current.id)
    let repeated = OfflineContent.nextQuote(
      from: shortEnglish, currentID: current.id, allowsRepeat: true, index: 0)
    XCTAssertEqual(repeated?.id, current.id)
  }

  func testQuoteRestartPolicyRepeatsOnlyAnInProgressQuoteWhenEnabled() {
    XCTAssertTrue(
      QuoteRestartPolicy.shouldKeepCurrent(
        repeatWhileTyping: true, hasStarted: true, isFinished: false))
    XCTAssertFalse(
      QuoteRestartPolicy.shouldKeepCurrent(
        repeatWhileTyping: false, hasStarted: true, isFinished: false))
    XCTAssertFalse(
      QuoteRestartPolicy.shouldKeepCurrent(
        repeatWhileTyping: true, hasStarted: false, isFinished: false))
    XCTAssertFalse(
      QuoteRestartPolicy.shouldKeepCurrent(
        repeatWhileTyping: true, hasStarted: true, isFinished: true))
  }

  func testEverySingleLanguageHasAnOriginalExtendedQuoteThatBuildsACompleteSession() {
    let languages: [TypingLanguage] = [
      .english, .spanish, .german, .french, .italian, .portuguese, .simplifiedChinese,
    ]
    for language in languages {
      let quote = try! XCTUnwrap(OfflineContent.quotes(for: language, length: .extended).first)
      XCTAssertEqual(quote.language, language)
      XCTAssertEqual(quote.length, .extended)
      XCTAssertGreaterThan(quote.text.count, 120)
      let session = TestSessionFactory.make(
        configuration: .init(
          mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
          language: language, quoteLength: .extended),
        quote: quote)
      XCTAssertEqual(session.prompt, quote.text)
    }
  }

  func testQuoteSearchMatchesAllTermsWithoutSendingOrMutatingContent() {
    let quotes = [
      OfflineQuote(id: "first", title: "Morning Field", text: "A quiet orchard opens at dawn.", language: .english, length: .short),
      OfflineQuote(id: "second", title: "Harbor Note", text: "A bright harbor keeps a careful rhythm.", language: .english, length: .short),
    ]
    XCTAssertEqual(QuoteSearch.filtered(quotes, query: "quiet dawn").map(\.id), ["first"])
    XCTAssertEqual(QuoteSearch.filtered(quotes, query: "BRIGHT rhythm").map(\.id), ["second"])
    XCTAssertTrue(QuoteSearch.filtered(quotes, query: "quiet harbor").isEmpty)
    XCTAssertEqual(QuoteSearch.filtered(quotes, query: "   ").map(\.id), quotes.map(\.id))
  }

  func testQuoteRatingsPersistAndTreatNeutralAsUnrated() {
    let suite = "quote-rating-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = QuoteRatingStore(defaults: defaults)
    XCTAssertEqual(store.rating(for: "craft"), .neutral)
    store.set(.up, for: "craft")
    XCTAssertEqual(QuoteRatingStore(defaults: defaults).rating(for: "craft"), .up)
    store.set(.neutral, for: "craft")
    XCTAssertEqual(QuoteRatingStore(defaults: defaults).rating(for: "craft"), .neutral)
  }

  func testLegacyConfigurationDefaultsToEnglish() throws {
    let legacy = """
      {"mode":"time","duration":30,"wordLimit":null,"difficulty":"normal","rules":{"strictSpace":false,"stopOnError":false,"deleteOnError":false,"hideExtraLetters":false}}
      """
    let configuration = try JSONDecoder().decode(TestConfiguration.self, from: Data(legacy.utf8))
    XCTAssertEqual(configuration.language, .english)
    XCTAssertEqual(configuration.englishVariant, .american)
    XCTAssertEqual(configuration.quoteLength, .all)
    XCTAssertTrue(configuration.modifiers.isEmpty)
    XCTAssertEqual(configuration.contentOptions, ContentOptions())
  }

  @MainActor
  func testPresetRoundTripsWithAllSessionInputs() throws {
    let container = try ModelContainer(
      for: TestPresetRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    var rules = InputRules()
    rules.strictSpace = true
    rules.minimumWordBurstWpm = 75
    let definition = SavedTestPreset(
      configuration: .init(
        mode: .custom, duration: nil, wordLimit: nil, difficulty: .expert, rules: rules),
      quoteID: nil,
      customText: "a tailored practice"
    )
    container.mainContext.insert(TestPresetRecord(name: "Focused practice", definition: definition))
    try container.mainContext.save()

    let record = try XCTUnwrap(
      container.mainContext.fetch(FetchDescriptor<TestPresetRecord>()).first)
    XCTAssertEqual(record.name, "Focused practice")
    XCTAssertEqual(record.definition, definition)
    XCTAssertEqual(record.definition?.configuration.rules.minimumWordBurstWpm, 75)
  }

  func testResultStatisticsAggregateCompletedTests() {
    let day = Date(timeIntervalSinceReferenceDate: 1_000)
    let statistics = ResultStatistics(metrics: [
      .init(finishedAt: day, wpm: 60, accuracy: 95, typingSeconds: 30),
      .init(finishedAt: day.addingTimeInterval(60), wpm: 90, accuracy: 85, typingSeconds: 60),
    ])
    XCTAssertEqual(statistics.completedTests, 2)
    XCTAssertEqual(statistics.averageWPM, 75)
    XCTAssertEqual(statistics.bestWPM, 90)
    XCTAssertEqual(statistics.averageAccuracy, 90)
    XCTAssertEqual(statistics.totalTypingSeconds, 90)
  }

  func testRecentTestAverageUsesTheLatestTenMatchingCurrentSettings() {
    let current = TestConfiguration.words(
      25, difficulty: .expert, language: .english,
      contentOptions: .init(includePunctuation: true, includeNumbers: false)
    )
    let matching = (0..<11).map { offset in
      RecentAverageSample(
        configuration: current, prompt: "generated \(offset)",
        finishedAt: start.addingTimeInterval(TimeInterval(offset)), wpm: 50 + offset,
        accuracy: 80 + offset)
    }
    let differentWordLimit = RecentAverageSample(
      configuration: .words(
        50, difficulty: .expert, language: .english,
        contentOptions: .init(includePunctuation: true, includeNumbers: false)),
      prompt: "other", finishedAt: start.addingTimeInterval(99), wpm: 999, accuracy: 1)
    let quote = TestConfiguration(
      mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
      language: .english)
    let differentQuote = RecentAverageSample(
      configuration: quote, prompt: "another quote", finishedAt: start.addingTimeInterval(100),
      wpm: 999, accuracy: 1)

    let average = RecentTestAveragePolicy.average(
      currentConfiguration: current, currentPrompt: "irrelevant for words",
      samples: matching + [differentWordLimit, differentQuote])
    XCTAssertEqual(average, .init(count: 10, wpm: 56, accuracy: 86))

    XCTAssertNil(
      RecentTestAveragePolicy.average(
        currentConfiguration: quote, currentPrompt: "current quote", samples: [differentQuote]))
    XCTAssertNil(
      RecentTestAveragePolicy.average(
        currentConfiguration: current, currentPrompt: "irrelevant for words", samples: matching,
        limit: 0))
  }

  func testCurrentPersonalBestExcludesIneligibleResultsAndUsesMatchingSettings() {
    let current = TestConfiguration.words(
      25, difficulty: .expert, language: .english,
      contentOptions: .init(includePunctuation: true, includeNumbers: false))
    let eligible = RecentAverageSample(
      configuration: current, prompt: "first", finishedAt: start, wpm: 72, accuracy: 98)
    let best = RecentAverageSample(
      configuration: current, prompt: "second", finishedAt: start.addingTimeInterval(1),
      wpm: 84, accuracy: 93)
    let ineligibleStream = RecentAverageSample(
      configuration: current.with(modifiers: [.zipf]), prompt: "zipf",
      finishedAt: start.addingTimeInterval(2), wpm: 999, accuracy: 100)
    let stoppedWithError = RecentAverageSample(
      configuration: TestConfiguration(
        mode: .words, duration: nil, wordLimit: 25, difficulty: .expert,
        rules: .init(stopOnError: true), language: .english,
        contentOptions: .init(includePunctuation: true, includeNumbers: false)),
      prompt: "stopped", finishedAt: start.addingTimeInterval(3), wpm: 500, accuracy: 99)
    let differentWordLimit = RecentAverageSample(
      configuration: .words(
        50, difficulty: .expert, language: .english,
        contentOptions: .init(includePunctuation: true, includeNumbers: false)),
      prompt: "longer", finishedAt: start.addingTimeInterval(4), wpm: 600, accuracy: 100)

    XCTAssertEqual(
      CurrentPersonalBestPolicy.personalBest(
        currentConfiguration: current, currentPrompt: "ignored", samples: [
          eligible, best, ineligibleStream, stoppedWithError, differentWordLimit,
        ]),
      .init(wpm: 84, accuracy: 93))
    XCTAssertFalse(CurrentPersonalBestPolicy.isConfigurationEligible(current.with(modifiers: [.zipf])))
    XCTAssertFalse(
      CurrentPersonalBestPolicy.isConfigurationEligible(
        .words(25, difficulty: .expert, language: .mixedLanguages)))
    XCTAssertNil(
      CurrentPersonalBestPolicy.personalBest(
        currentConfiguration: current.with(modifiers: [.zipf]), currentPrompt: "ignored",
        samples: [eligible, best]))
    XCTAssertNil(
      CurrentPersonalBestPolicy.personalBest(
        currentConfiguration: TestConfiguration(
          mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
          language: .english), currentPrompt: "quote", samples: [eligible, best]))
  }

  func testWordBurstHeatmapUsesCurrentResultQuintilesAndLeavesMissingBurstsNeutral() throws {
    let heatmap = try XCTUnwrap(
      WordBurstHeatmapPolicy.make(bursts: [20, 40, 60, 80, 100, nil, 0]))

    XCTAssertEqual(heatmap.lowerBounds, [20, 40, 60, 80, 100])
    XCTAssertEqual(
      heatmap.tones,
      [.slow, .measured, .steady, .fast, .swift, .unmeasured, .unmeasured])
    XCTAssertNil(WordBurstHeatmapPolicy.make(bursts: [nil, 0]))
  }

  func testResultPerformanceTraceRebuildsSpeedBurstAndCorrectedErrorsFromReplay() {
    let points = ResultPerformanceTrace.points(
      prompt: "amber",
      events: [
        .init(offset: 0, kind: .insert, text: "a"),
        .init(offset: 1, kind: .insert, text: "m"),
        .init(offset: 2, kind: .insert, text: "x"),
        .init(offset: 3, kind: .delete, text: ""),
        .init(offset: 4, kind: .insert, text: "b"),
      ],
      duration: 4)

    XCTAssertEqual(points.map(\.elapsed), [1, 2, 3, 4])
    XCTAssertEqual(points.map(\.wpm), [24, 12, 8, 9])
    XCTAssertEqual(points.map(\.rawWpm), [24, 18, 8, 9])
    XCTAssertEqual(points.map(\.burstWpm), [36, 24, 36, 12])
    XCTAssertEqual(points.map(\.errorCount), [0, 1, 0, 0])
    XCTAssertEqual(
      ResultPerformanceTrace.points(
        prompt: "amber", events: [.init(offset: 0, kind: .insert, text: "a")], duration: 121),
      [])
  }

  func testOfflineAchievementsAreDerivedFromCompletedLocalMetrics() {
    let metrics = [
      ResultMetric(finishedAt: start, wpm: 84, accuracy: 99, typingSeconds: 16),
      ResultMetric(
        finishedAt: start.addingTimeInterval(60), wpm: 52, accuracy: 92, typingSeconds: 884),
    ]
    let achievements = TypebarAchievementPolicy.achievements(metrics: metrics)
    XCTAssertEqual(
      achievements.filter(\.isUnlocked).map(\.id),
      ["first-finish", "clear-key", "swift-line", "steady-room"])
    XCTAssertEqual(achievements.first(where: { $0.id == "swift-line" })?.progress, "80/80 WPM")

    let empty = TypebarAchievementPolicy.achievements(metrics: [])
    XCTAssertTrue(empty.allSatisfy { !$0.isUnlocked })
    XCTAssertEqual(empty.first?.progress, "0/1")
  }

  func testChallengeEvaluatorReportsEveryUnmetRequirement() throws {
    let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "calm-thirty"))
    let result = CompletedTestResult(
      id: UUID(),
      configuration: challenge.preset.configuration.with(challengeID: challenge.id),
      outcome: .completed,
      startedAt: start,
      finishedAt: start.addingTimeInterval(30),
      typedCharacterCount: 60,
      correctCharacterCount: 50,
      errorCount: 11,
      wpm: 34,
      rawWpm: 40,
      accuracy: 93
    )

    let evaluation = ChallengeEvaluator.evaluate(result, challenge: challenge)

    XCTAssertFalse(evaluation.passed)
    XCTAssertEqual(evaluation.failedRequirements.count, 3)
  }

  func testChallengeEvaluatorPassesWhenEveryRequirementIsMet() throws {
    let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "clean-twenty-five"))
    let result = CompletedTestResult(
      id: UUID(),
      configuration: challenge.preset.configuration.with(challengeID: challenge.id),
      outcome: .completed,
      startedAt: start,
      finishedAt: start.addingTimeInterval(20),
      typedCharacterCount: 100,
      correctCharacterCount: 100,
      errorCount: 0,
      wpm: 60,
      rawWpm: 60,
      accuracy: 100
    )

    XCTAssertTrue(ChallengeEvaluator.evaluate(result, challenge: challenge).passed)
  }

  func testDailyChallengeIsStableForOneCalendarDayAndCyclesLibrary() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let morning = ISO8601DateFormatter().date(from: "2026-09-02T01:00:00Z")!
    let evening = ISO8601DateFormatter().date(from: "2026-09-02T23:00:00Z")!
    XCTAssertEqual(
      TypebarChallengeLibrary.dailyChallenge(on: morning, calendar: calendar),
      TypebarChallengeLibrary.dailyChallenge(on: evening, calendar: calendar))
    XCTAssertTrue(
      TypebarChallengeLibrary.all.contains(
        TypebarChallengeLibrary.dailyChallenge(on: morning, calendar: calendar)))
  }

  func testChallengeConfigurationRoundTripsWithoutAffectingLegacyConfiguration() throws {
    let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "long-breath"))
    let encoded = try JSONEncoder().encode(
      challenge.preset.configuration.with(challengeID: challenge.id))
    let decoded = try JSONDecoder().decode(TestConfiguration.self, from: encoded)
    XCTAssertEqual(decoded.challengeID, challenge.id)

    let legacy = """
      {"mode":"words","duration":null,"wordLimit":25,"difficulty":"normal","rules":{},"language":"english","englishVariant":"american","quoteLength":"all","customTextCompletion":"finish","customTextOrdering":"inOrder","modifiers":[],"contentOptions":{"includePunctuation":false,"includeNumbers":false}}
      """
    XCTAssertNil(
      try JSONDecoder().decode(TestConfiguration.self, from: Data(legacy.utf8)).challengeID)
  }

  func testWPMHistogramKeepsEmptyIntervalsBetweenSelectedResults() {
    let metrics = [
      ResultMetric(finishedAt: start, wpm: 11, accuracy: 95, typingSeconds: 30),
      ResultMetric(finishedAt: start, wpm: 19, accuracy: 95, typingSeconds: 30),
      ResultMetric(finishedAt: start, wpm: 20, accuracy: 95, typingSeconds: 30),
      ResultMetric(finishedAt: start, wpm: 26, accuracy: 95, typingSeconds: 30),
      ResultMetric(finishedAt: start, wpm: 41, accuracy: 95, typingSeconds: 30),
    ]

    let buckets = WPMHistogram.buckets(metrics: metrics)

    XCTAssertEqual(buckets.map(\.label), ["10–19", "20–29", "30–39", "40–49"])
    XCTAssertEqual(buckets.map(\.count), [2, 2, 0, 1])
  }

  func testResultHistoryFilterCombinesModeLanguageTagAndPersonalBest() {
    let timeEnglish = UUID()
    let wordsEnglish = UUID()
    let wordsChinese = UUID()
    let entries = [
      ResultHistoryEntry(id: timeEnglish, mode: .time, language: .english, tags: ["morning"]),
      ResultHistoryEntry(id: wordsEnglish, mode: .words, language: .english, tags: ["focus"]),
      ResultHistoryEntry(
        id: wordsChinese, mode: .words, language: .simplifiedChinese, tags: ["focus", "evening"]),
    ]
    let filter = ResultHistoryFilter(
      mode: .words, language: .english, tag: "focus", personalBestOnly: true)
    XCTAssertEqual(
      filter.matchingIDs(entries: entries, personalBestIDs: [wordsEnglish, wordsChinese]),
      [wordsEnglish])

    let all = ResultHistoryFilter()
    XCTAssertEqual(
      all.matchingIDs(entries: entries, personalBestIDs: []),
      Set([timeEnglish, wordsEnglish, wordsChinese]))
  }

  func testPersonalBestMarksEveryTiedHighestResult() {
    let first = UUID()
    let second = UUID()
    let third = UUID()
    let best = ResultStatistics.personalBestIDs(metrics: [
      .init(id: first, finishedAt: start, wpm: 70, accuracy: 95, typingSeconds: 30),
      .init(id: second, finishedAt: start, wpm: 92, accuracy: 90, typingSeconds: 30),
      .init(id: third, finishedAt: start, wpm: 92, accuracy: 98, typingSeconds: 30),
    ])
    XCTAssertEqual(best, [second, third])
  }

  func testArchiveRoundTripsIndependentLocalData() throws {
    let settings = AppSettingsSnapshot(fontSize: 32)
    let result = CompletedTestResult(
      id: UUID(), configuration: .timed(seconds: 30), outcome: .completed, startedAt: start,
      finishedAt: start.addingTimeInterval(30), typedCharacterCount: 50, correctCharacterCount: 48,
      errorCount: 2, wpm: 19, rawWpm: 20, accuracy: 96)
    let preset = NamedPreset(
      name: "Short", definition: .init(configuration: .words(10), quoteID: nil, customText: nil))
    let savedText = NamedSavedText(title: "Notes", text: "An original text for focused practice.")
    let data = try TypebarDataTransfer.exportArchive(
      settings: settings, results: [result], presets: [preset], savedTexts: [savedText], at: start)
    let archive = try TypebarDataTransfer.importArchive(from: data)
    XCTAssertEqual(archive.settings, settings)
    XCTAssertEqual(archive.results, [result])
    XCTAssertEqual(archive.presets, [preset])
    XCTAssertEqual(archive.savedTexts, [savedText])
  }

  func testArchiveMergeSkipsExistingResultsAndPresets() {
    let existingID = UUID()
    let retainedResult = CompletedTestResult(
      id: existingID, configuration: .timed(seconds: 30), outcome: .completed, startedAt: start,
      finishedAt: start.addingTimeInterval(30), typedCharacterCount: 50, correctCharacterCount: 50,
      errorCount: 0, wpm: 20, rawWpm: 20, accuracy: 100)
    let newResult = CompletedTestResult(
      id: UUID(), configuration: .words(10), outcome: .completed, startedAt: start,
      finishedAt: start.addingTimeInterval(20), typedCharacterCount: 50, correctCharacterCount: 49,
      errorCount: 1, wpm: 29, rawWpm: 30, accuracy: 98)
    let existingPreset = NamedPreset(
      name: "Short", definition: .init(configuration: .words(10), quoteID: nil, customText: nil))
    let newPreset = NamedPreset(
      name: "Long",
      definition: .init(configuration: .timed(seconds: 120), quoteID: nil, customText: nil))
    let existingText = NamedSavedText(title: "Existing", text: "Already here")
    let newText = NamedSavedText(title: "New", text: "Bring this one in")
    let archive = TypebarArchive(
      version: 2, exportedAt: start, settings: .init(), results: [retainedResult, newResult],
      presets: [existingPreset, newPreset], savedTexts: [existingText, newText])

    XCTAssertEqual(
      TypebarArchiveMerge.resultsToInsert(from: archive, existingIDs: [existingID]), [newResult])
    XCTAssertEqual(
      TypebarArchiveMerge.presetsToInsert(from: archive, existing: [existingPreset]), [newPreset])
    XCTAssertEqual(
      TypebarArchiveMerge.savedTextsToInsert(from: archive, existing: [existingText]), [newText])
  }

  func testVersionOneArchiveImportsWithoutSavedTexts() throws {
    let oldArchive = """
      {"version":1,"exportedAt":"2001-01-01T02:46:40Z","settings":{"difficulty":"normal","strictSpace":false,"stopOnError":false,"deleteOnError":false,"hideExtraLetters":false,"fontSize":28},"results":[],"presets":[]}
      """
    let archive = try TypebarDataTransfer.importArchive(from: Data(oldArchive.utf8))
    XCTAssertEqual(archive.version, 1)
    XCTAssertTrue(archive.savedTexts.isEmpty)
  }

  func testDailyActivityGroupsMetricsByCalendarDay() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let metrics = [
      ResultMetric(
        finishedAt: Date(timeIntervalSince1970: 86_400 + 60), wpm: 40, accuracy: 90,
        typingSeconds: 30),
      ResultMetric(
        finishedAt: Date(timeIntervalSince1970: 86_400 + 3_600), wpm: 50, accuracy: 90,
        typingSeconds: 45),
      ResultMetric(
        finishedAt: Date(timeIntervalSince1970: 172_800 + 60), wpm: 60, accuracy: 90,
        typingSeconds: 15),
    ]
    let activity = ActivityAggregation.daily(metrics: metrics, calendar: calendar)
    XCTAssertEqual(activity.map(\.completedTests), [2, 1])
    XCTAssertEqual(activity.map(\.typingSeconds), [75, 15])
  }

  func testRecentActivityBarsFillEveryRequestedDayWithoutCollapsingGaps() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let end = Date(timeIntervalSince1970: 345_600)
    let activity = [
      DailyActivity(day: end.addingTimeInterval(-172_800), completedTests: 2, typingSeconds: 75),
      DailyActivity(day: end, completedTests: 1, typingSeconds: 30),
    ]

    let points = ActivityAggregation.recentDays(
      activity: activity, days: 4, endingAt: end, calendar: calendar)

    XCTAssertEqual(points.map(\.completedTests), [0, 2, 0, 1])
    XCTAssertEqual(points.map(\.typingSeconds), [0, 75, 0, 30])
    XCTAssertEqual(
      points.map(\.day),
      [
        end.addingTimeInterval(-259_200),
        end.addingTimeInterval(-172_800),
        end.addingTimeInterval(-86_400),
        end,
      ])
  }

  func testCurrentStreakOnlyCountsConsecutiveDaysEndingToday() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let today = Date(timeIntervalSince1970: 345_600)
    let activity = [
      DailyActivity(day: today, completedTests: 1, typingSeconds: 10),
      DailyActivity(day: today.addingTimeInterval(-86_400), completedTests: 1, typingSeconds: 10),
      DailyActivity(day: today.addingTimeInterval(-259_200), completedTests: 1, typingSeconds: 10),
    ]
    XCTAssertEqual(
      ActivityAggregation.currentStreak(activity: activity, today: today, calendar: calendar), 2)
  }

  func testHeatmapIncludesEmptyDaysAndMapsIntensity() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let end = Date(timeIntervalSince1970: 345_600)
    let activity = [
      DailyActivity(day: end.addingTimeInterval(-86_400), completedTests: 1, typingSeconds: 10),
      DailyActivity(day: end, completedTests: 5, typingSeconds: 50),
    ]
    let cells = ActivityHeatmap.cells(
      activity: activity, days: 4, endingAt: end, calendar: calendar)

    XCTAssertEqual(cells.map(\.completedTests), [0, 0, 1, 5])
    XCTAssertEqual(cells.map(\.intensity), [0, 0, 1, 3])
  }

  @MainActor
  func testAppSettingsPersistAndRestore() throws {
    let suiteName = "TypebarTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettings(defaults: defaults)
    settings.difficulty = .master
    settings.strictSpace = true
    settings.deleteOnError = true
    settings.blindMode = true
    settings.fontSize = 34
    settings.practiceFont = .serif
    settings.theme = .midnight
    settings.publishCompletedResults = true
    settings.saveCompletedResults = false
    settings.keyboardLayout = .ansiDvorak
    settings.layoutFluidLayouts = [.ansiWorkman, .frenchAzerty, .ansiQwerty]
    settings.quickEnd = true
    settings.quickRestartKey = .enter
    settings.followSystemTheme = true
    settings.randomThemeOnRestart = true
    settings.practiceBackdrop = .halos
    settings.reducePracticeMotion = true
    settings.toggleFavoriteTheme(.grove)
    settings.addCustomTheme(
      name: "Harbour", background: .black, panel: .gray, accent: .orange, prefersDark: true)
    let customThemeID = try XCTUnwrap(settings.customThemes.first?.id)
    settings.toggleFavoriteCustomTheme(customThemeID)
    settings.englishVariant = .british
    settings.freedomMode = true
    settings.confidenceMode = .maximum
    settings.oppositeShiftMode = .keymap
    settings.codeUnindentOnBackspace = true
    settings.minimumAccuracy = 97
    settings.minimumWpm = 85
    settings.minimumWordBurstWpm = 85
    settings.practiceLineWidth = .wide
    settings.customPracticeLineColumns = 112
    settings.practiceTapeMode = .letter
    settings.practiceTapeMargin = 0.35
    settings.smoothPracticeLineScroll = false
    settings.showAllPracticeLines = true
    settings.caretStyle = .underline
    settings.typoIndicatorStyle = .both
    settings.compositionDisplayStyle = .below
    settings.typingSpeedUnit = .cps
    settings.alwaysShowDecimalPlaces = true
    settings.alwaysShowWordsHistory = true
    settings.showWordBurstHeatmap = true
    settings.resultPerformanceVisibility = .init(raw: false, burst: false, errors: true)
    settings.startGraphsAtZero = false
    settings.showAverage = .both
    settings.showPersonalBest = true
    settings.typedCharacterEffect = .dots
    settings.liveSpeedStyle = .mini
    settings.liveAccuracyStyle = .off
    settings.liveBurstStyle = .mini
    settings.liveProgressStyle = .bar
    settings.testModifiers = [.noSpaces, .uppercase]
    settings.favoriteQuoteIDs = ["craft"]
    settings.repeatQuotes = true
    settings.showKeyboardGuide = false
    settings.showFocusWarning = false
    settings.showCapsLockWarning = false
    settings.playErrorBeep = true
    settings.playKeyclickSound = true
    settings.timeWarningOffset = .threeSeconds
    settings.soundVolume = 0.4
    settings.globalHotkeyEnabled = true
    settings.paceGuideMode = .custom
    settings.paceGuideCustomWpm = 95
    settings.paceCaretStyle = .block
    settings.repeatedPace = true

    let restored = AppSettings(defaults: defaults)
    XCTAssertEqual(restored.difficulty, .master)
    XCTAssertTrue(restored.inputRules.strictSpace)
    XCTAssertFalse(restored.inputRules.deleteOnError)
    XCTAssertTrue(restored.inputRules.blindMode)
    XCTAssertEqual(restored.fontSize, 34)
    XCTAssertEqual(restored.practiceFont, .serif)
    XCTAssertEqual(restored.theme, .midnight)
    XCTAssertTrue(restored.publishCompletedResults)
    XCTAssertFalse(restored.saveCompletedResults)
    XCTAssertEqual(restored.keyboardLayout, .ansiDvorak)
    XCTAssertEqual(restored.layoutFluidLayouts, [.ansiWorkman, .frenchAzerty, .ansiQwerty])
    XCTAssertTrue(restored.quickEnd)
    XCTAssertEqual(restored.quickRestartKey, .enter)
    XCTAssertTrue(restored.followSystemTheme)
    XCTAssertTrue(restored.randomThemeOnRestart)
    XCTAssertEqual(restored.practiceBackdrop, .halos)
    XCTAssertTrue(restored.reducePracticeMotion)
    XCTAssertTrue(restored.isFavoriteTheme(.grove))
    XCTAssertTrue(restored.isFavoriteCustomTheme(customThemeID))
    XCTAssertEqual(restored.englishVariant, .british)
    XCTAssertFalse(restored.freedomMode)
    XCTAssertEqual(restored.confidenceMode, .maximum)
    XCTAssertEqual(restored.oppositeShiftMode, .keymap)
    XCTAssertTrue(restored.codeUnindentOnBackspace)
    XCTAssertEqual(restored.minimumAccuracy, 97)
    XCTAssertEqual(restored.minimumWpm, 85)
    XCTAssertEqual(restored.minimumWordBurstWpm, 85)
    XCTAssertEqual(restored.practiceLineWidth, .wide)
    XCTAssertEqual(restored.customPracticeLineColumns, 112)
    XCTAssertEqual(restored.practiceTapeMode, .letter)
    XCTAssertEqual(restored.practiceTapeMargin, 0.35)
    XCTAssertFalse(restored.smoothPracticeLineScroll)
    XCTAssertTrue(restored.showAllPracticeLines)
    XCTAssertEqual(restored.caretStyle, .underline)
    XCTAssertEqual(restored.typoIndicatorStyle, .both)
    XCTAssertEqual(restored.compositionDisplayStyle, .below)
    XCTAssertEqual(restored.typingSpeedUnit, .cps)
    XCTAssertTrue(restored.alwaysShowDecimalPlaces)
    XCTAssertTrue(restored.alwaysShowWordsHistory)
    XCTAssertTrue(restored.showWordBurstHeatmap)
    XCTAssertEqual(restored.resultPerformanceVisibility, .init(raw: false, burst: false, errors: true))
    XCTAssertFalse(restored.startGraphsAtZero)
    XCTAssertEqual(restored.showAverage, .both)
    XCTAssertTrue(restored.showPersonalBest)
    XCTAssertEqual(restored.typedCharacterEffect, .dots)
    XCTAssertEqual(restored.liveSpeedStyle, .mini)
    XCTAssertEqual(restored.liveAccuracyStyle, .off)
    XCTAssertEqual(restored.liveBurstStyle, .mini)
    XCTAssertEqual(restored.liveProgressStyle, .bar)
    XCTAssertEqual(restored.testModifiers, [.noSpaces, .uppercase])
    XCTAssertTrue(restored.isFavoriteQuote("craft"))
    XCTAssertTrue(restored.repeatQuotes)
    XCTAssertEqual(restored.resolvedTheme(for: .dark).colorScheme, .dark)
    XCTAssertEqual(restored.resolvedTheme(for: .light).colorScheme, .light)
    XCTAssertFalse(restored.showKeyboardGuide)
    XCTAssertFalse(restored.showFocusWarning)
    XCTAssertFalse(restored.showCapsLockWarning)
    XCTAssertTrue(restored.playErrorBeep)
    XCTAssertTrue(restored.playKeyclickSound)
    XCTAssertEqual(restored.timeWarningOffset, .threeSeconds)
    XCTAssertEqual(restored.soundVolume, 0.4)
    XCTAssertTrue(restored.globalHotkeyEnabled)
    XCTAssertEqual(restored.paceGuideMode, .custom)
    XCTAssertEqual(restored.paceGuideCustomWpm, 95)
    XCTAssertEqual(restored.paceCaretStyle, .block)
    XCTAssertTrue(restored.repeatedPace)
  }

  @MainActor
  func testApplyingAConfigurationRestoresEveryInputRuleForRestart() {
    let suiteName = "TypebarTests.rules-\(UUID().uuidString)"
    let localDefaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { localDefaults.removePersistentDomain(forName: suiteName) }
    let settings = AppSettings(defaults: localDefaults)
    let rules = InputRules(
      strictSpace: true,
      stopOnError: true,
      deleteOnError: true,
      hideExtraLetters: true,
      blindMode: true,
      quickEnd: true,
      freedomMode: true,
      minimumAccuracy: 96,
      minimumWpm: 80,
      minimumWordBurstWpm: 90
    )
    settings.apply(TestConfiguration.words(25, rules: rules, language: .german))
    XCTAssertEqual(settings.inputRules, rules)
    XCTAssertEqual(settings.englishVariant, EnglishVariant.american)
  }

  @MainActor
  func testGlobalHotkeyUsesOnlyControlShiftSpace() {
    XCTAssertTrue(GlobalHotkeyMonitor.matches(keyCode: 49, modifiers: [.control, .shift]))
    XCTAssertFalse(GlobalHotkeyMonitor.matches(keyCode: 49, modifiers: [.control]))
    XCTAssertFalse(GlobalHotkeyMonitor.matches(keyCode: 36, modifiers: [.control, .shift]))
  }

  func testLegacySettingsSnapshotDefaultsToPaperTheme() throws {
    let legacy = """
      {"difficulty":"normal","strictSpace":false,"stopOnError":false,"deleteOnError":false,"hideExtraLetters":false,"fontSize":28}
      """
    let snapshot = try JSONDecoder().decode(AppSettingsSnapshot.self, from: Data(legacy.utf8))
    XCTAssertEqual(snapshot.theme, .paper)
    XCTAssertFalse(snapshot.publishCompletedResults)
    XCTAssertTrue(snapshot.saveCompletedResults)
    XCTAssertTrue(snapshot.customThemes.isEmpty)
    XCTAssertNil(snapshot.activeCustomThemeID)
    XCTAssertTrue(snapshot.favoriteThemeIDs.isEmpty)
    XCTAssertTrue(snapshot.showKeyboardGuide)
    XCTAssertEqual(snapshot.keyboardLayout, .ansiQwerty)
    XCTAssertFalse(snapshot.quickEnd)
    XCTAssertFalse(snapshot.followSystemTheme)
    XCTAssertFalse(snapshot.randomThemeOnRestart)
    XCTAssertEqual(snapshot.practiceBackdrop, .solid)
    XCTAssertFalse(snapshot.reducePracticeMotion)
    XCTAssertTrue(snapshot.startGraphsAtZero)
    XCTAssertEqual(snapshot.englishVariant, .american)
    XCTAssertTrue(snapshot.favoriteQuoteIDs.isEmpty)
    XCTAssertFalse(snapshot.repeatQuotes)
    XCTAssertFalse(snapshot.freedomMode)
    XCTAssertEqual(snapshot.minimumAccuracy, 0)
    XCTAssertEqual(snapshot.minimumWpm, 0)
    XCTAssertEqual(snapshot.minimumWordBurstWpm, 0)
    XCTAssertEqual(snapshot.practiceLineWidth, .standard)
    XCTAssertEqual(snapshot.customPracticeLineColumns, 60)
    XCTAssertEqual(snapshot.caretStyle, .block)
    XCTAssertEqual(snapshot.typoIndicatorStyle, .off)
    XCTAssertEqual(snapshot.typingSpeedUnit, .wpm)
    XCTAssertFalse(snapshot.alwaysShowWordsHistory)
    XCTAssertFalse(snapshot.showWordBurstHeatmap)
    XCTAssertEqual(snapshot.resultPerformanceVisibility, .init())
    XCTAssertEqual(snapshot.showAverage, .off)
    XCTAssertFalse(snapshot.showPersonalBest)
    XCTAssertEqual(snapshot.typedCharacterEffect, .keep)
    XCTAssertEqual(snapshot.liveSpeedStyle, .text)
    XCTAssertEqual(snapshot.liveAccuracyStyle, .text)
    XCTAssertEqual(snapshot.liveBurstStyle, .text)
    XCTAssertEqual(snapshot.liveProgressStyle, .text)
    XCTAssertTrue(snapshot.testModifiers.isEmpty)
    XCTAssertTrue(snapshot.showFocusWarning)
    XCTAssertTrue(snapshot.showCapsLockWarning)
    XCTAssertFalse(snapshot.playErrorBeep)
    XCTAssertEqual(snapshot.timeWarningOffset, .off)
    XCTAssertEqual(snapshot.paceGuideMode, .off)
    XCTAssertEqual(snapshot.paceGuideCustomWpm, 60)
    XCTAssertEqual(snapshot.paceCaretStyle, .bar)
    XCTAssertFalse(snapshot.repeatedPace)
    XCTAssertEqual(
      try XCTUnwrap(PracticeLineWidth.compact.maximumWidth(fontSize: 20)), 520.8, accuracy: 0.001)
    XCTAssertEqual(
      try XCTUnwrap(PracticeLineWidth.custom.maximumWidth(fontSize: 20, customColumns: 99)), 1227.6,
      accuracy: 0.001)
    XCTAssertEqual(
      try XCTUnwrap(PracticeLineWidth.custom.maximumWidth(fontSize: 20, customColumns: 999)), 1736,
      accuracy: 0.001)
    XCTAssertNil(PracticeLineWidth.fluid.maximumWidth(fontSize: 20))
  }

  func testTypingSpeedUnitsFormatCanonicalWpmPresentation() {
    XCTAssertEqual(TypingSpeedUnit.wpm.formatted(wpm: 72), "72")
    XCTAssertEqual(TypingSpeedUnit.cpm.formatted(wpm: 72), "360")
    XCTAssertEqual(TypingSpeedUnit.wps.formatted(wpm: 72), "1.2")
    XCTAssertEqual(TypingSpeedUnit.wpm.formatted(wpm: 72, alwaysShowDecimalPlaces: true), "72.00")
    XCTAssertEqual(TypingSpeedUnit.cpm.formatted(wpm: 72, alwaysShowDecimalPlaces: true), "360.00")
    XCTAssertEqual(TypingSpeedUnit.wps.formatted(wpm: 72, alwaysShowDecimalPlaces: true), "1.20")
    XCTAssertEqual(TypingSpeedUnit.cps.formatted(wpm: 72), "6.0")
    XCTAssertEqual(TypingSpeedUnit.wph.formatted(wpm: 72), "4320")
    XCTAssertEqual(TypingSpeedUnit.cps.formatted(wpm: 72, alwaysShowDecimalPlaces: true), "6.00")
    XCTAssertEqual(TypingSpeedUnit.wph.formatted(wpm: 72, alwaysShowDecimalPlaces: true), "4320.00")
    XCTAssertEqual(TypingSpeedUnit.wps.converted(wpm: 72), 1.2, accuracy: 0.001)
    XCTAssertEqual(TypingSpeedUnit.cps.converted(wpm: 72), 6, accuracy: 0.001)
  }

  func testPaceGuideUsesOnlyComparableCompletedResultsAndClampsProgress() {
    let calendar = Calendar(identifier: .gregorian)
    let today = Date(timeIntervalSinceReferenceDate: 10_000_000)
    let configuration = TestConfiguration.timed(seconds: 30, language: .english)
    let samples = [
      PaceGuideSample(
        configuration: configuration, outcome: .completed, finishedAt: today, wpm: 72),
      PaceGuideSample(
        configuration: configuration, outcome: .completed,
        finishedAt: today.addingTimeInterval(-86_400), wpm: 48),
      PaceGuideSample(
        configuration: .timed(seconds: 30, language: .simplifiedChinese), outcome: .completed,
        finishedAt: today, wpm: 180),
      PaceGuideSample(
        configuration: configuration, outcome: .abandoned, finishedAt: today, wpm: 250),
    ]

    XCTAssertEqual(
      PaceGuidePolicy.targetWpm(
        mode: .personalBest, customWpm: 60, configuration: configuration, samples: samples,
        now: today, calendar: calendar), 72)
    XCTAssertEqual(
      PaceGuidePolicy.targetWpm(
        mode: .average, customWpm: 60, configuration: configuration, samples: samples, now: today,
        calendar: calendar), 60)
    XCTAssertEqual(
      PaceGuidePolicy.targetWpm(
        mode: .dailyAverage, customWpm: 60, configuration: configuration, samples: samples,
        now: today, calendar: calendar), 72)
    XCTAssertEqual(
      PaceGuidePolicy.targetWpm(
        mode: .custom, customWpm: 1, configuration: configuration, samples: [], now: today,
        calendar: calendar), PaceGuidePolicy.minimumWpm)
    XCTAssertEqual(
      PaceGuidePolicy.targetWpm(
        mode: .lastTest, customWpm: 60, configuration: configuration, samples: [],
        lastTestWpm: 360, now: today, calendar: calendar), PaceGuidePolicy.maximumWpm)
    XCTAssertNil(
      PaceGuidePolicy.targetWpm(
        mode: .lastTest, customWpm: 60, configuration: configuration, samples: [],
        lastTestWpm: nil, now: today, calendar: calendar))
    XCTAssertNil(
      PaceGuidePolicy.targetWpm(
        mode: .off, customWpm: 60, configuration: configuration, samples: samples, now: today,
        calendar: calendar))
    XCTAssertEqual(
      PaceGuidePolicy.expectedCharacterIndex(elapsed: 2, targetWpm: 60, promptLength: 40), 10)
    XCTAssertEqual(
      PaceGuidePolicy.expectedCharacterIndex(elapsed: 120, targetWpm: 300, promptLength: 40), 39)
  }

  @MainActor
  func testRandomBuiltInThemeUsesOnlyOriginalBuiltInsAndRespectsSystemMode() {
    let suiteName = "TypebarTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = AppSettings(defaults: defaults)

    settings.randomizeBuiltInTheme(using: 1)
    XCTAssertEqual(settings.theme, .midnight)
    settings.followSystemTheme = true
    settings.randomizeBuiltInTheme(using: 2)
    XCTAssertEqual(settings.theme, .midnight)
  }

  @MainActor
  func testCustomThemePersistsSelectsAndFallsBackWhenDeleted() throws {
    let suiteName = "TypebarTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettings(defaults: defaults)
    settings.addCustomTheme(
      name: "Dawn",
      background: Color(red: 0.2, green: 0.3, blue: 0.4),
      panel: Color(red: 0.3, green: 0.4, blue: 0.5),
      accent: Color(red: 0.8, green: 0.5, blue: 0.2),
      prefersDark: true
    )
    let id = try XCTUnwrap(settings.activeCustomThemeID)
    XCTAssertEqual(settings.customThemes.first?.name, "Dawn")
    settings.toggleFavoriteCustomTheme(id)
    XCTAssertTrue(settings.isFavoriteCustomTheme(id))

    let restored = AppSettings(defaults: defaults)
    XCTAssertEqual(restored.activeCustomThemeID, id)
    let restoredBackground = try XCTUnwrap(restored.customThemes.first?.background)
    XCTAssertEqual(restoredBackground.red, 0.2, accuracy: 0.000_001)
    XCTAssertEqual(restoredBackground.green, 0.3, accuracy: 0.000_001)
    XCTAssertEqual(restoredBackground.blue, 0.4, accuracy: 0.000_001)

    restored.deleteCustomTheme(id)
    XCTAssertTrue(restored.customThemes.isEmpty)
    XCTAssertNil(restored.activeCustomThemeID)
    XCTAssertFalse(restored.isFavoriteCustomTheme(id))
    XCTAssertTrue(restored.favoriteThemeIDs.isEmpty)
    XCTAssertEqual(restored.activeTheme.colorScheme, .light)
  }

  @MainActor
  func testResultRecordRoundTripsThroughSwiftData() throws {
    let container = try ModelContainer(
      for: TestResultRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    var session = TypingSession(
      configuration: .init(
        mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()),
      prompt: "amber")
    session.insert("amber", at: start)
    let result = try XCTUnwrap(session.result())
    container.mainContext.insert(TestResultRecord(result: result))
    try container.mainContext.save()

    let stored = try XCTUnwrap(
      container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).first)
    XCTAssertEqual(stored.id, result.id)
    XCTAssertEqual(stored.configuration?.mode, .quote)
    XCTAssertEqual(stored.wpm, result.wpm)
    XCTAssertEqual(stored.accuracy, 100)
    XCTAssertEqual(stored.portableResult, result)

    stored.addTag("morning")
    stored.addTag("MORNING")
    stored.addTag(" focus ")
    try container.mainContext.save()
    XCTAssertEqual(stored.tags, ["morning", "focus"])
    XCTAssertEqual(stored.portableResult?.tags, ["morning", "focus"])
  }

  func testResultTagPolicyNormalizesDeduplicatesAndLimitsTags() {
    let tags = ResultTagPolicy.normalized([
      "  flow", "FLOW", "review", "", "a very long tag that cannot be accepted", "one", "two",
      "three", "four",
    ])
    XCTAssertEqual(tags, ["flow", "review", "one", "two", "three"])
  }

  @MainActor
  func testResultFilterPresetPersistsACompleteFilter() throws {
    let container = try ModelContainer(
      for: ResultFilterPresetRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let filter = ResultHistoryFilter(
      mode: .words, language: .english, tag: "focus", personalBestOnly: true)
    let preset = try XCTUnwrap(ResultFilterPresetRecord(name: " Focused English ", filter: filter))
    container.mainContext.insert(preset)
    try container.mainContext.save()

    let stored = try XCTUnwrap(
      container.mainContext.fetch(FetchDescriptor<ResultFilterPresetRecord>()).first)
    XCTAssertEqual(stored.name, "Focused English")
    XCTAssertEqual(stored.filter, filter)
    XCTAssertNil(ResultFilterPresetRecord(name: " ", filter: filter))
    XCTAssertNil(ResultFilterPresetRecord(name: String(repeating: "a", count: 41), filter: filter))
  }

  @MainActor
  func testSavedCustomTextRoundTripsThroughSwiftData() throws {
    let container = try ModelContainer(
      for: SavedCustomTextRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    container.mainContext.insert(
      SavedCustomTextRecord(title: "Morning", text: "A deliberate beginning."))
    try container.mainContext.save()

    let savedText = try XCTUnwrap(
      container.mainContext.fetch(FetchDescriptor<SavedCustomTextRecord>()).first)
    XCTAssertEqual(savedText.title, "Morning")
    XCTAssertEqual(savedText.text, "A deliberate beginning.")
  }
}
