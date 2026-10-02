import AppKit
import XCTest
@testable import Typebar

final class QuoteStreamingTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 873_000_000)
  private func configuration(modifiers: [TestModifier] = [], rules: InputRules = .init(),
    british: Bool = false) -> TestConfiguration {
    .init(mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal, rules: rules,
      englishVariant: british ? .british : .american, modifiers: modifiers)
  }
  private func attempt(_ source: String, alternate: String? = nil,
    config: TestConfiguration? = nil, all: Bool = false,
    nextBit: () -> Bool = { true }) -> TypingSession {
    TestSessionFactory.make(configuration: config ?? configuration(),
      quote: .init(id: "owned-quote-cursor", title: "Cursor draft", text: source,
        britishText: alternate, language: .english, length: .long), showAllLines: all,
      nextRandomCaseBit: nextBit)
  }
  private func numbered(_ count: Int) -> [String] {
    (0..<count).map { String(format: "w%03d", $0) }
  }

  func testDefaultInitialQuoteIsOneHundredWordsWithItsLastCommit() {
    let session = attempt(numbered(205).joined(separator: " "))
    XCTAssertEqual(session.prompt, numbered(100).joined(separator: " ") + " ")
    XCTAssertTrue(session.usesIncrementalPromptExtension)
    XCTAssertFalse(session.hasStarted)
  }

  func testFutureSourceNewlineAllowsReturnBeforeThatWordIsGenerated() {
    var session = attempt("ab cd\nef", config: configuration(modifiers: [.focusCurrentWord]))
    XCTAssertEqual(session.prompt, "ab ")
    session.insert("x", at: start)
    session.insert("\n", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "x\n")
  }

  func testControlCapabilitiesInspectTheSelectedPoolNotOnlyTheWindow() {
    let config = configuration(modifiers: [.focusCurrentWord], british: true)
    let ordinaryControls = attempt("ab cd\nef\tgh", alternate: "ab cd",
      config: configuration(modifiers: [.focusCurrentWord]))
    let alternateControls = attempt("ab cd", alternate: "ab cd\nef\tgh", config: config)
    for session in [ordinaryControls, alternateControls] {
      XCTAssertEqual(session.prompt, "ab ")
      XCTAssertTrue(session.acceptsNewlineInput)
      XCTAssertTrue(session.acceptsTabInput)
      XCTAssertTrue(session.repeatedAttempt().acceptsNewlineInput)
      XCTAssertTrue(session.repeatedAttempt().acceptsTabInput)
      XCTAssertEqual(CommandPaletteDynamicShortcut.resolve(quickRestartKey: .escape,
        promptAcceptsTab: session.acceptsTabInput), .shiftTab)
    }
    let plain = attempt("ab cd", config: config)
    XCTAssertFalse(plain.acceptsNewlineInput)
    XCTAssertFalse(plain.acceptsTabInput)
    let zen = TypingSession(configuration: .init(mode: .zen, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init()), prompt: "")
    XCTAssertTrue(zen.acceptsNewlineInput)
    XCTAssertTrue(zen.acceptsTabInput)
    XCTAssertFalse(zen.hasPracticeNewlineContent)
  }

  func testUnselectedOrdinaryControlsDoNotLeakIntoAlternateInputOrRepeat() {
    let session = attempt("ab cd\nef\tgh", alternate: "ab cd",
      config: configuration(modifiers: [.focusCurrentWord], british: true))
    XCTAssertEqual(session.prompt, "ab ")
    XCTAssertFalse(session.acceptsNewlineInput)
    XCTAssertFalse(session.acceptsTabInput)
    XCTAssertFalse(session.hasPracticeNewlineContent)
    XCTAssertFalse(session.repeatedAttempt().acceptsNewlineInput)
    XCTAssertFalse(session.repeatedAttempt().acceptsTabInput)
    XCTAssertEqual(CommandPaletteDynamicShortcut.resolve(quickRestartKey: .escape,
      promptAcceptsTab: session.acceptsTabInput), .tab)
  }

  @MainActor
  func testFutureControlsRouteNativeReturnAndTabToInputInsteadOfRestartWithoutWindow() throws {
    let session = attempt("ab cd\nef\tgh", config: configuration(modifiers: [.focusCurrentWord]))
    for (text, code, restart) in [("\r", UInt16(36), QuickRestartKey.enter),
      ("\t", UInt16(48), QuickRestartKey.tab)] {
      let input = TypingInputView(frame: .zero)
      input.acceptsNewlineInput = session.acceptsNewlineInput
      input.acceptsTabInput = session.acceptsTabInput
      input.quickRestartKey = restart
      var inserts = [String]()
      var restarts = 0
      input.onInsert = { value, _ in inserts.append(value) }
      input.onRestart = { restarts += 1 }
      input.keyDown(with: try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
        modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil,
        characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)))
      XCTAssertEqual(inserts, [text == "\r" ? "\n" : "\t"])
      XCTAssertEqual(restarts, 0)
    }
  }

  func testOneForwardCommitAddsOnlyOneFutureWordAndLettersDoNotDraw() {
    var session = attempt(numbered(205).joined(separator: " "))
    session.insertBatch("w000", at: start)
    XCTAssertEqual(session.prompt, numbered(100).joined(separator: " ") + " ")
    session.insert(" ", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.prompt, numbered(101).joined(separator: " ") + " ")
    XCTAssertEqual(session.completedWordCount, 1)
    XCTAssertFalse(session.isFinished)
  }

  func testShowAllLinesGeneratesTheEntireQuoteAndRemovesOnlyTheFinalCommit() {
    let source = numbered(205).joined(separator: " ")
    let session = attempt(source, all: true)
    XCTAssertEqual(session.prompt, source)
    XCTAssertFalse(session.usesIncrementalPromptExtension)
  }

  func testVisibilityPushOverridesShowAllAndRefillsItsExactWindow() {
    let source = numbered(10).joined(separator: " ")
    for (modifier, count) in [(TestModifier.focusCurrentWord, 1), (.focusNextWord, 2),
      (.focusTwoWords, 3), (.focusThreeWords, 4)] {
      var session = attempt(source, config: configuration(modifiers: [modifier]), all: true)
      XCTAssertEqual(session.prompt, numbered(count).joined(separator: " ") + " ")
      session.insertBatch("w000 ", at: start)
      XCTAssertEqual(session.prompt, numbered(count + 1).joined(separator: " ") + " ")
      XCTAssertFalse(session.isFinished)
    }
  }

  func testLetterStopDoesNotDrawOrAdvanceTheQuoteCursor() {
    var session = attempt("ab cd ef", config: configuration(modifiers: [.focusCurrentWord],
      rules: .init(stopOnErrorMode: .letter)))
    session.insert("x", at: start)
    XCTAssertEqual(session.prompt, "ab ")
    XCTAssertEqual(session.completedWordCount, 0)
    session.insertBatch("ab ", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.prompt, "ab cd ")
  }

  func testStoppedWrongCommitDoesNotConsumeTheNextCandidate() {
    var session = attempt("ab cd ef", config: configuration(modifiers: [.focusCurrentWord],
      rules: .init(stopOnErrorMode: .word)))
    session.insertBatch("ax ", at: start)
    XCTAssertEqual(session.prompt, "ab ")
    XCTAssertEqual(session.completedWordCount, 0)
    XCTAssertFalse(session.isFinished)
  }

  func testBlindWrongCommitStillAddsTheNextRealCandidate() {
    var session = attempt("ab cd ef", config: configuration(modifiers: [.focusCurrentWord],
      rules: .init(blindMode: true)))
    session.insertBatch("x ", at: start)
    XCTAssertEqual(session.prompt, "ab cd ")
    XCTAssertEqual(session.completedWordCount, 1)
  }

  func testReopeningAnEarlierPushWindowDoesNotDrawAnAlreadyBufferedWordTwice() {
    var session = attempt("ab cd ef gh", config: configuration(modifiers: [.focusCurrentWord],
      rules: .init(freedomMode: true)))
    session.insertBatch("ab ", at: start)
    XCTAssertEqual(session.prompt, "ab cd ")
    session.deleteBackward(at: start.addingTimeInterval(1))
    session.insert(" ", at: start.addingTimeInterval(2))
    XCTAssertEqual(session.prompt, "ab cd ")
    session.insertBatch("cd ", at: start.addingTimeInterval(3))
    XCTAssertEqual(session.prompt, "ab cd ef ")
  }

  func testLongQuoteCompletesWithoutAnExtraFinalSpaceAndKeepsFullResult() throws {
    let source = numbered(205).joined(separator: " ")
    var session = attempt(source)
    session.insertBatch(source, at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.prompt, source)
    XCTAssertEqual(session.completedWordCount, 205)
    XCTAssertEqual(session.errors, 0)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.prompt, source)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [], at: start)).results, [result])
  }

  func testBritishLaterGenerationUsesPreviousTextWithoutItsNewlineCommit() {
    var session = attempt("will. tire", config: configuration(modifiers: [.messagingStyle, .focusCurrentWord],
      british: true))
    XCTAssertEqual(session.prompt, "will\n")
    session.insertBatch("will\n", at: start)
    XCTAssertEqual(session.prompt, "will\ntire")
    session.insertBatch("tire", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
    XCTAssertEqual(attempt("will. tire", config: configuration(modifiers: [.messagingStyle], british: true),
      all: true).prompt, "will\ntyre")
  }

  func testUnderscoreTargetsUseTheInitialAndLaterGenerationBounds() {
    let words = numbered(103)
    var session = attempt(words.joined(separator: " "), config: configuration(modifiers: [.underscoreSeparators]))
    let targets = words.enumerated().map { index, word in word + (index == 99 ? "" : "_") }
    XCTAssertEqual(session.prompt, targets.prefix(100).joined())
    session.insertBatch(targets.joined(), at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 103)
    XCTAssertEqual(session.wordReviews.map(\.target), targets)
    XCTAssertEqual(session.errors, 0)
  }

  func testBackwardsReversesTheWholePoolBeforeTakingTheInitialWindow() {
    let targets = numbered(205).reversed().map { String($0.reversed()) }
    var session = attempt(numbered(205).joined(separator: " "), config: configuration(modifiers: [.backwards]))
    XCTAssertEqual(session.prompt, targets.prefix(100).joined(separator: " ") + " ")
    session.insertBatch(targets.joined(separator: " "), at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
  }

  func testMorseAddsOneCapturedTargetPerRealWordAndCompletesTheEntireQuote() {
    var session = attempt(Array(repeating: "e", count: 105).joined(separator: " "),
      config: configuration(modifiers: [.morseStream]))
    XCTAssertEqual(session.prompt, String(repeating: "./", count: 100))
    session.insertBatch(String(repeating: "./", count: 105), at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 105)
    XCTAssertEqual(session.wordReviews.map(\.target), Array(repeating: "./", count: 105))
  }

  func testDeferredEmptyAlternateFailsOnlyWhenTheCandidateIsRequested() throws {
    let source = Array(repeating: "ab", count: 100).joined(separator: " ") + "  tail"
    var session = attempt("base", alternate: source, config: configuration(british: true))
    XCTAssertFalse(session.isFinished)
    XCTAssertNil(session.generationNotice)
    XCTAssertEqual(session.prompt, String(repeating: "ab ", count: 100))
    session.insertBatch("ab ", at: start)
    XCTAssertEqual(session.outcome, .failed)
    XCTAssertEqual(session.typed, "ab ")
    XCTAssertNotNil(session.generationNotice)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.outcome, .failed)
    XCTAssertFalse(ResultSavingPolicy.shouldPersist(outcome: result.outcome, enabled: true))
  }

  func testShowAllRequestsTheSameInvalidLateCandidateDuringInitialization() {
    let source = String(repeating: "ab ", count: 100) + " tail"
    let session = attempt("base", alternate: source, config: configuration(british: true), all: true)
    XCTAssertTrue(session.isFinished)
    XCTAssertFalse(session.hasStarted)
    XCTAssertNil(session.result())
    XCTAssertNotNil(session.generationNotice)
  }

  func testRepeatOfALateGenerationFailureResetsCursorAndItsInitialNotice() {
    let source = String(repeating: "ab ", count: 100) + " tail"
    var session = attempt("base", alternate: source, config: configuration(british: true))
    session.insertBatch("ab ", at: start)
    var repeated = session.repeatedAttempt()
    XCTAssertFalse(repeated.isFinished)
    XCTAssertNil(repeated.generationNotice)
    XCTAssertFalse(repeated.hasStarted)
    XCTAssertEqual(repeated.prompt, String(repeating: "ab ", count: 100))
    repeated.insertBatch("ab ", at: start.addingTimeInterval(1))
    XCTAssertEqual(repeated.outcome, .failed)
  }

  func testOnlyInitialVisibleWordsConsumeRandomCaseDraws() {
    var draws = 0
    let session = attempt(Array(repeating: "ab", count: 205).joined(separator: " "),
      config: configuration(modifiers: [.randomCase]), nextBit: { draws += 1; return true })
    XCTAssertEqual(draws, 200)
    XCTAssertEqual(session.prompt, String(repeating: "AB ", count: 100))
  }

  func testQuoteCounterAndBarUseWholeSourceRatherThanCurrentBuffer() {
    var session = attempt(numbered(205).joined(separator: " "))
    XCTAssertEqual(session.progressText(at: start), "0/205")
    XCTAssertEqual(session.progressLabel, "进度")
    XCTAssertEqual(session.progressFraction(at: start), 0)
    session.insertBatch(numbered(3).joined(separator: " ") + " ", at: start)
    XCTAssertEqual(session.progressText(at: start), "3/205")
    XCTAssertEqual(session.progressFraction(at: start), 0.01)
  }

  func testNonemptyFinalLFIsRemovedButNewlineOnlyWordKeepsItsCommit() {
    for (source, target) in [("ab\n", "ab"), ("ab\r\n", "ab\r"), ("\n", "\n")] {
      XCTAssertEqual(Array(attempt("base", alternate: source, config: configuration(british: true)).prompt.unicodeScalars),
        Array(target.unicodeScalars))
    }
  }

  func testPreparedExternalQuoteIsNotMistakenForAnOwnedPoolCursor() {
    let source = numbered(205).joined(separator: " ")
    let session = TestSessionFactory.make(configuration: configuration(), streamPrompt: source)
    XCTAssertEqual(session.prompt, source)
    XCTAssertFalse(session.usesIncrementalPromptExtension)
  }

  func testQuoteRepeatRegeneratesItsInitialRandomTargetsFromTheSameRawPool() {
    let source = Array(repeating: "ab", count: 205).joined(separator: " ")
    let original = attempt(source, config: configuration(modifiers: [.randomCase]), nextBit: { true })
    var draws = 0
    let repeated = original.repeatedAttempt(nextRandomCaseBit: { draws += 1; return false })
    XCTAssertEqual(draws, 200)
    XCTAssertEqual(original.prompt, String(repeating: "AB ", count: 100))
    XCTAssertEqual(repeated.prompt, String(repeating: "ab ", count: 100))
    XCTAssertEqual(repeated.typed, "")
    XCTAssertFalse(repeated.hasStarted)
    XCTAssertTrue(repeated.usesIncrementalPromptExtension)
  }

  func testNormalHundredWordWindowAlsoUsesStrippedPreviousCommitOnRefill() {
    let source = String(repeating: "ab ", count: 99) + "will. tire seed"
    var session = attempt(source, config: configuration(modifiers: [.messagingStyle], british: true))
    XCTAssertEqual(session.prompt, String(repeating: "ab ", count: 99) + "will\n")
    session.insertBatch("ab ", at: start)
    XCTAssertEqual(session.prompt, String(repeating: "ab ", count: 99) + "will\ntire ")
  }

  func testQuoteCounterStopsAtLastSourceIndexButCompletionFillsTheBar() {
    var session = attempt("ab cd ef gh")
    session.insertBatch("ab cd ef gh", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.progressText(at: start), "3/4")
    XCTAssertEqual(session.progressFraction(at: start), 1)
  }

  func testDeferredFailureAtAnUnsegmentedBoundaryUsesTheInputEventDate() {
    let source = String(repeating: "a ", count: 99) + "\u{301}  tail"
    var session = attempt("base", alternate: source,
      config: configuration(modifiers: [.noSpaces], british: true))
    XCTAssertFalse(session.isFinished)
    let target = session.prompt
    session.insertBatch(target, at: start)
    XCTAssertEqual(session.outcome, .failed)
    XCTAssertEqual(session.finishedAt, start)
    XCTAssertEqual(session.failureReason, .wordGeneration)
  }

  func testLegacyLongQuoteSnapshotIsNotRegeneratedDuringRecordAndArchiveRoundTrip() throws {
    let source = "  " + numbered(205).joined(separator: "  ") + "…  "
    let result = CompletedTestResult(id: UUID(), configuration: configuration(), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(1), typedCharacterCount: source.count,
      correctCharacterCount: source.count, errorCount: 0, wpm: 60, rawWpm: 60, accuracy: 100,
      prompt: source)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [], at: start)).results, [result])
  }
}
