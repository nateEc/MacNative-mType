import AppKit
import XCTest
@testable import Typebar

final class QuoteBoundaryContinuationTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 873_100_000)
  private let words = ["a", "\u{301}"] + Array(repeating: "b", count: 203)

  private func config(_ modifiers: [TestModifier], rules: InputRules = .init()) -> TestConfiguration {
    .init(mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal,
      rules: rules, englishVariant: .american, modifiers: modifiers)
  }

  private func session(_ source: String, modifiers: [TestModifier] = [.noSpaces],
    rules: InputRules = .init(), all: Bool = false) -> TypingSession {
    TestSessionFactory.make(configuration: config(modifiers, rules: rules),
      quote: .init(id: "owned-boundary-probe", title: "Boundary probe", text: source,
        language: .english, length: .long), showAllLines: all)
  }

  func testUnsafeInitialBoundariesCompleteTheEntirePoolRatherThanStoppingAt102() {
    let target = words.joined()
    var legacy = TypingSession(configuration: config([.noSpaces]), prompt: target)
    legacy.insertBatch(target, at: start)
    XCTAssertEqual(legacy.outcome, .completed)
    XCTAssertEqual(legacy.errors, 0)
    var attempt = session(words.joined(separator: " "))
    XCTAssertEqual(attempt.prompt, words.prefix(100).joined())
    attempt.insertBatch(target, at: start)
    XCTAssertEqual(attempt.prompt, target)
    XCTAssertEqual(attempt.typed, target)
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.errors, 0)
    XCTAssertFalse(attempt.usesIncrementalPromptExtension)
  }

  func testUnitCommitsMaintainTheSameHundredWordLookaheadAsAlignedTargets() {
    var attempt = session(words.joined(separator: " "))
    let prefix = attempt.prompt
    attempt.insertBatch(prefix, at: start)
    XCTAssertEqual(attempt.prompt, words.prefix(200).joined())
    for index in 100..<205 {
      attempt.insert("b", at: start.addingTimeInterval(Double(index - 99)))
      XCTAssertEqual(attempt.prompt, words.prefix(min(index + 101, 205)).joined())
    }
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.typed, words.joined())
    XCTAssertEqual(attempt.errors, 0)
  }

  func testCompatibleTextTransformsRetainTheirActualTargetsAfterBoundaryFallback() {
    for (modifier, target) in [(TestModifier.uppercase, "A\u{301}" + String(repeating: "B", count: 203)),
      (.doubleCharacters, "aa\u{301}\u{301}" + String(repeating: "bb", count: 203)),
      (.rot13, "n\u{301}" + String(repeating: "o", count: 203))] {
      var attempt = session(words.joined(separator: " "), modifiers: [.noSpaces, modifier])
      XCTAssertEqual(Set(attempt.configuration.modifiers), Set([.noSpaces, modifier]))
      attempt.insertBatch(target, at: start)
      XCTAssertEqual(attempt.outcome, .completed, modifier.rawValue)
      XCTAssertEqual(attempt.prompt, target, modifier.rawValue)
      XCTAssertEqual(attempt.errors, 0, modifier.rawValue)
      XCTAssertEqual(attempt.wordReviews.count, words.count, modifier.rawValue)
      XCTAssertEqual(attempt.wordReviews.map(\.typed).joined(), target, modifier.rawValue)
      XCTAssertTrue(attempt.wordReviews.allSatisfy(\.isCorrect), modifier.rawValue)
    }
  }

  func testUnitCommitsPrefetchOnlyAtActualWordEndsAndNeverOnBlockedErrors() {
    var attempt = session(words.joined(separator: " "), rules: .init(stopOnErrorMode: .letter))
    attempt.insert("a\u{301}", at: start)
    XCTAssertEqual(attempt.prompt, words.prefix(102).joined())
    let afterCommits = attempt.prompt
    attempt.insert("x", at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.prompt, afterCommits)
    XCTAssertEqual(attempt.typed, "a\u{301}")
    attempt.insertBatch(String(words.joined().dropFirst()), at: start.addingTimeInterval(2))
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.prompt, words.joined())
  }

  func testUnsafeFallbackRepeatReplayAndArchiveRetainTheFullActualTarget() throws {
    var attempt = session(words.joined(separator: " "))
    attempt.insertBatch(words.joined(), at: start)
    let result = try XCTUnwrap(attempt.result())
    XCTAssertEqual(result.prompt, words.joined())
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents,
      through: result.elapsedDuration), words.joined())
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [], at: start)).results, [result])
    var repeated = attempt.repeatedAttempt()
    XCTAssertEqual(repeated.prompt, words.prefix(100).joined())
    XCTAssertFalse(repeated.hasStarted)
    repeated.insertBatch(words.joined(), at: start.addingTimeInterval(1))
    XCTAssertEqual(repeated.outcome, .completed)
    XCTAssertEqual(repeated.prompt, words.joined())
  }

  func testUnsafeFallbackEventuallyRequestsALaterInvalidCandidateAtTheInputDate() {
    let source = (["a", "\u{301}"] + Array(repeating: "b", count: 101)).joined(separator: " ")
    let quote = OfflineQuote(id: "owned-invalid-boundary", title: "Late invalid",
      text: "base", britishText: source + "  tail", language: .english, length: .long)
    let configuration = TestConfiguration(mode: .quote, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), englishVariant: .british, modifiers: [.noSpaces])
    var attempt = TestSessionFactory.make(configuration: configuration, quote: quote)
    attempt.insertBatch("a\u{301}" + String(repeating: "b", count: 101), at: start)
    XCTAssertEqual(attempt.outcome, .failed)
    XCTAssertEqual(attempt.failureReason, .wordGeneration)
    XCTAssertEqual(attempt.finishedAt, start)
    XCTAssertNotNil(attempt.generationNotice)
  }

  func testShowAllUnsafeQuoteStillMatchesTheExistingWholeTargetFallback() {
    var attempt = session(words.joined(separator: " "), all: true)
    XCTAssertEqual(attempt.prompt, words.joined())
    attempt.insertBatch(words.joined(), at: start)
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.errors, 0)
  }

  func testFusedScalarFamiliesKeepTraversingTheEntirePool() {
    for components in [["\u{1100}", "\u{1161}"], ["\u{1F1E6}", "\u{1F1E7}"],
      ["\u{1F469}", "\u{200D}", "\u{1F4BB}"]] {
      let sourceWords = components + Array(repeating: "b", count: 205 - components.count)
      let target = sourceWords.joined()
      var whole = session(sourceWords.joined(separator: " "), all: true)
      whole.insertBatch(target, at: start)
      XCTAssertEqual(whole.outcome, .completed)
      XCTAssertEqual(whole.errors, 0)
      var attempt = session(sourceWords.joined(separator: " "))
      XCTAssertEqual(attempt.prompt, sourceWords.prefix(100).joined())
      attempt.insertBatch(target, at: start)
      XCTAssertEqual(attempt.outcome, .completed)
      XCTAssertEqual(attempt.prompt, target)
      XCTAssertEqual(attempt.typed, target)
      XCTAssertEqual(attempt.errors, 0)
      XCTAssertEqual(attempt.wordReviews.map(\.target), sourceWords)
      XCTAssertEqual(attempt.wordReviews.map(\.typed), sourceWords)
    }
  }

  func testBoundaryMetadataLostDuringRefillDoesNotStopTheRemainingPool() {
    let sourceWords = Array(repeating: "a", count: 100) + ["\u{301}"] + Array(repeating: "b", count: 104)
    let target = sourceWords.joined()
    var attempt = session(sourceWords.joined(separator: " "))
    XCTAssertEqual(attempt.prompt, String(repeating: "a", count: 100))
    attempt.insertBatch(target, at: start)
    XCTAssertEqual(attempt.prompt, target)
    XCTAssertEqual(attempt.typed, target)
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.errors, 0)
    XCTAssertEqual(attempt.wordReviews.map(\.target), sourceWords)
    XCTAssertEqual(attempt.wordReviews.map(\.typed), sourceWords)
  }

  func testReopeningAUnitFieldMaintainsLookaheadWithoutDuplicatingTargetIdentity() {
    var attempt = session(words.joined(separator: " "), rules: .init(freedomMode: true))
    let prefix = attempt.prompt
    attempt.insertBatch(String(prefix.dropLast()) + "x", at: start)
    XCTAssertEqual(attempt.prompt, words.prefix(200).joined())
    attempt.deleteBackward(at: start.addingTimeInterval(1))
    attempt.insert("b", at: start.addingTimeInterval(2))
    XCTAssertEqual(attempt.prompt, words.prefix(201).joined())
    attempt.insertBatch(String(words.joined().dropFirst(prefix.count)), at: start.addingTimeInterval(3))
    XCTAssertEqual(attempt.prompt, words.joined())
    XCTAssertEqual(attempt.typed, words.joined())
    XCTAssertEqual(attempt.outcome, .completed)
  }

  func testFallbackLateFailureRepeatResetsCursorAndDoesNotKeepTheFailureNotice() {
    let raw = (["a", "\u{301}"] + Array(repeating: "b", count: 101)).joined(separator: " ")
    let quote = OfflineQuote(id: "owned-repeat-boundary", title: "Repeat invalid",
      text: "base", britishText: raw + "  tail", language: .english, length: .long)
    let configuration = TestConfiguration(mode: .quote, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), englishVariant: .british, modifiers: [.noSpaces])
    var attempt = TestSessionFactory.make(configuration: configuration, quote: quote)
    let target = "a\u{301}" + String(repeating: "b", count: 101)
    attempt.insertBatch(target, at: start)
    XCTAssertEqual(attempt.outcome, .failed)
    var repeated = attempt.repeatedAttempt()
    XCTAssertFalse(repeated.isFinished)
    XCTAssertFalse(repeated.hasStarted)
    XCTAssertNil(repeated.generationNotice)
    XCTAssertEqual(repeated.prompt, "a\u{301}" + String(repeating: "b", count: 98))
    repeated.insertBatch(target, at: start.addingTimeInterval(1))
    XCTAssertEqual(repeated.outcome, .failed)
    XCTAssertEqual(repeated.failureReason, .wordGeneration)
    XCTAssertEqual(repeated.finishedAt, start.addingTimeInterval(1))
  }

  func testLaterMessagingNewlineDoesNotChangeTheInitialQuoteInputCapability() {
    var attempt = session("ab tail. end", modifiers: [.messagingStyle, .focusCurrentWord])
    XCTAssertFalse(attempt.acceptsNewlineInput)
    attempt.insertBatch("ab ", at: start)
    XCTAssertEqual(attempt.prompt, "ab tail\n")
    XCTAssertFalse(attempt.acceptsNewlineInput)
    XCTAssertFalse(attempt.hasPracticeNewlineContent)
    let before = attempt.typed
    attempt.insert("\n", at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.typed, before)
    XCTAssertFalse(attempt.repeatedAttempt().acceptsNewlineInput)
  }

  func testDefaultHundredWordWindowAlsoKeepsItsInitialControlSignal() {
    let source = String(repeating: "ab ", count: 100) + "tail. end"
    var attempt = session(source, modifiers: [.messagingStyle])
    XCTAssertFalse(attempt.acceptsNewlineInput)
    attempt.insertBatch("ab ", at: start)
    XCTAssertTrue(attempt.prompt.contains("tail\n"))
    XCTAssertFalse(attempt.acceptsNewlineInput)
    XCTAssertFalse(attempt.hasPracticeNewlineContent)
  }

  func testInitiallyGeneratedNewlinesAndRawFutureControlsRemainEnabled() {
    for all in [false, true] {
      let initial = session("ab. tail end", modifiers: [.messagingStyle, .focusCurrentWord], all: all)
      XCTAssertTrue(initial.acceptsNewlineInput)
      XCTAssertTrue(initial.repeatedAttempt().acceptsNewlineInput)
      let raw = session("ab tail\n end\tlast", modifiers: [.focusCurrentWord], all: all)
      XCTAssertTrue(raw.acceptsNewlineInput)
      XCTAssertTrue(raw.acceptsTabInput)
    }
    XCTAssertTrue(session("ab tail. end", modifiers: [.messagingStyle], all: true).acceptsNewlineInput)
  }

  func testInitialSignalIsCapturedBeforeFinalCommitRemovalAndOnRepeat() {
    for (source, modifiers, all, target) in [("ab.", [TestModifier.messagingStyle], false, "ab"),
      ("ab tail.", [.messagingStyle], true, "ab tail"),
      ("ab.", [.messagingStyle, .focusCurrentWord], false, "ab")] {
      let attempt = session(source, modifiers: modifiers, all: all)
      XCTAssertEqual(attempt.prompt, target)
      XCTAssertTrue(attempt.acceptsNewlineInput)
      XCTAssertTrue(attempt.hasPracticeNewlineContent)
      XCTAssertTrue(attempt.repeatedAttempt().acceptsNewlineInput)
    }
  }

  @MainActor
  func testFutureOnlyMessagingNewlineKeepsNativeReturnInTheRestartRouteWithoutAWindow() throws {
    var attempt = session("ab tail. end", modifiers: [.messagingStyle, .focusCurrentWord])
    attempt.insertBatch("ab ", at: start)
    let input = TypingInputView(frame: .zero)
    input.acceptsNewlineInput = attempt.acceptsNewlineInput
    input.quickRestartKey = .enter
    var inserts = [String]()
    var restarts = 0
    input.onInsert = { value, _ in inserts.append(value) }
    input.onRestart = { restarts += 1 }
    input.keyDown(with: try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
      modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil, characters: "\r",
      charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)))
    XCTAssertEqual(restarts, 1)
    XCTAssertTrue(inserts.isEmpty)
  }
}
