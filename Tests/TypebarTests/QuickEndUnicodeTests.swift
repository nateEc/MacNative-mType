import AppKit
import XCTest
@testable import Typebar

final class QuickEndUnicodeTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 100)

  func testQuickEndWaitsForUTF16UnitsInsteadOfTheNumberOfVisibleLetters() {
    let cases = [("🙂", "xy"), ("🇨🇦", "xyzt"), ("👩‍🔬", "xyzta"), ("e\u{301}", "xy")]
    for configuration in configurations() {
      for (target, wrong) in cases {
        var session = TypingSession(configuration: configuration, prompt: "seed " + target)
        session.insertBatch("seed x", at: start)
        XCTAssertEqual(session.outcome, .active, "\(configuration.mode): \(target)")
        XCTAssertEqual(session.typed, "seed x")
        session.insertBatch(String(wrong.dropFirst()), at: start.addingTimeInterval(0.2))
        XCTAssertEqual(session.outcome, .completed, "\(configuration.mode): \(target)")
        XCTAssertEqual(session.typed, "seed " + wrong)
      }
    }
  }

  func testOneWrongGraphemeCanCompleteSeveralUTF16TargetUnits() {
    for configuration in configurations() {
      for (target, wrong) in [("ab", "🙂"), ("abcd", "🇨🇦"), ("abcde", "👩‍🔬"), ("ab", "e\u{301}")] {
        var session = TypingSession(configuration: configuration, prompt: "seed " + target)
        session.insertBatch("seed ", at: start)
        session.insertBatch(wrong, at: start.addingTimeInterval(0.2))
        XCTAssertEqual(session.outcome, .completed, "\(configuration.mode): \(target)")
        XCTAssertEqual(session.typed, "seed " + wrong)
      }
    }
  }

  func testMixedWidthInputCompletesWhenItsUTF16LengthMatchesBeforeTheGlyphCursorEnds() {
    for configuration in configurations() {
      var session = TypingSession(configuration: configuration, prompt: "seed abcd")
      session.insertBatch("seed 🙂x", at: start)
      XCTAssertEqual(session.outcome, .active)
      session.insertBatch("y", at: start.addingTimeInterval(0.2))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.typed, "seed 🙂xy")
    }
  }

  func testOvershootingUTF16LengthDoesNotQuickEnd() {
    for configuration in configurations() {
      var session = TypingSession(configuration: configuration, prompt: "seed a")
      session.insertBatch("seed 🙂", at: start)
      XCTAssertEqual(session.outcome, .active)
      session.insertBatch("x", at: start.addingTimeInterval(0.1))
      XCTAssertEqual(session.outcome, .active)
      session.insertBatch(" ", at: start.addingTimeInterval(0.2))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.typed, "seed 🙂x ")
    }
  }

  func testEarlierWordCannotFinishEvenWhenItsUTF16LengthMatches() {
    for configuration in configurations() {
      var session = TypingSession(configuration: configuration, prompt: "ab cd")
      session.insertBatch("🙂", at: start)
      XCTAssertEqual(session.outcome, .active)
      session.insertBatch(" cd", at: start.addingTimeInterval(0.2))
      XCTAssertEqual(session.outcome, .completed)
    }
  }

  func testCorrectUnicodeFinalWordsStillFinishWithQuickEndOff() {
    for configuration in configurations(quickEnd: false) {
      for target in ["🙂", "🇨🇦", "👩‍🔬", "e\u{301}"] {
        var session = TypingSession(configuration: configuration, prompt: "seed " + target)
        session.insertBatch("seed ", at: start)
        session.insertBatch(target, at: start.addingTimeInterval(0.2))
        XCTAssertEqual(session.outcome, .completed)
        XCTAssertEqual(session.errors, 0)
      }
    }
  }

  func testWrongUnicodeFinalWordWithQuickEndOffRequiresACommit() {
    for configuration in configurations(quickEnd: false) {
      var session = TypingSession(configuration: configuration, prompt: "seed ab")
      session.insertBatch("seed 🙂", at: start)
      XCTAssertEqual(session.outcome, .active)
      session.insertBatch(" ", at: start.addingTimeInterval(0.2))
      XCTAssertEqual(session.outcome, .completed)
    }
  }

  func testNewlineCommitIdentifiesTheLastWordWithoutCountingPreviousWords() {
    for configuration in configurations() {
      var session = TypingSession(configuration: configuration, prompt: "seed\nab")
      session.insertBatch("seed\n", at: start)
      session.insertBatch("🙂", at: start.addingTimeInterval(0.2))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.typed, "seed\n🙂")
    }
  }

  func testTabIsFinalWordContentNotAnotherWordBoundary() {
    for configuration in configurations() {
      var session = TypingSession(configuration: configuration, prompt: "seed \tab")
      session.insertBatch("seed 🙂", at: start)
      XCTAssertEqual(session.outcome, .active)
      session.insertBatch("x", at: start.addingTimeInterval(0.2))
      XCTAssertEqual(session.outcome, .completed)
    }
  }

  func testErrorRulesStillBlockUnicodeQuickEnd() {
    for rules in [InputRules(stopOnErrorMode: .letter, quickEnd: true),
      .init(stopOnErrorMode: .word, quickEnd: true), .init(deleteOnErrorMode: .word, quickEnd: true)]
    {
      for var configuration in configurations() {
        configuration.rules = rules
        var session = TypingSession(configuration: configuration, prompt: "seed ab")
        session.insertBatch("seed 🙂", at: start)
        XCTAssertEqual(session.outcome, .active)
        XCTAssertEqual(session.configuration.rules, rules)
      }
    }
  }

  func testLiveQuickEndToggleUsesUTF16OnTheNextAcceptedEvent() {
    for configuration in configurations(quickEnd: false) {
      var session = TypingSession(configuration: configuration, prompt: "seed abcd")
      session.insertBatch("seed 🙂x", at: start)
      session.synchronizeLiveInputRules(.init(quickEnd: true))
      XCTAssertEqual(session.outcome, .active)
      session.insertBatch("y", at: start.addingTimeInterval(0.2))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertTrue(session.configuration.rules.quickEnd)
    }
  }

  func testFiniteStreamChunkEdgeCannotQuickEndBeforeRemainingWordsAreGenerated() {
    let source = String(repeating: "seed ", count: CustomTextPolicy.maximumLength / 5 + 3) + "ab"
    let first = LongSavedTextProgress.nextChunk(in: source, after: 0)
    XCTAssertLessThan(first.count, source.count)
    let configuration = configurations()[2]
    var session = TestSessionFactory.make(configuration: configuration,
      customText: first, finiteTextSource: source)
    session.insertBatch(first, at: start)
    XCTAssertEqual(session.outcome, .active)
    XCTAssertGreaterThan(session.prompt.count, first.count)
    let remainder = String(source.dropFirst(first.count))
    session.insertBatch(String(remainder.dropLast(2)), at: start.addingTimeInterval(0.2))
    XCTAssertEqual(session.outcome, .active)
    session.insertBatch("🙂", at: start.addingTimeInterval(0.4))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.prompt, source)
  }

  func testLongJoinedTargetCanReachItsUTF16LengthWithoutBeingClippedByTheInputGuard() {
    let target = String(repeating: "👩\u{200d}", count: 8) + "🔬"
    XCTAssertEqual(target.count, 1)
    let wrong = String(repeating: "x", count: target.utf16.count)
    for configuration in configurations() {
      var session = TypingSession(configuration: configuration, prompt: "seed " + target)
      session.insertBatch("seed x", at: start)
      XCTAssertEqual(session.outcome, .active)
      session.insertBatch(String(wrong.dropFirst()), at: start.addingTimeInterval(0.2))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.typed, "seed " + wrong)
    }
  }

  func testInputLimitCountsUTF16UnitsAndStillAllowsTheWrongWordCommit() {
    let wrong = String(repeating: "🙂", count: 12)
    var session = TypingSession(configuration: .words(2), prompt: "abc bay")
    session.insertBatch(wrong, at: start)
    XCTAssertEqual(session.outcome, .active)
    XCTAssertEqual(session.typed, wrong)
    session.insertBatch("x", at: start.addingTimeInterval(0.1))
    XCTAssertEqual(session.typed, wrong, "Three target units plus a commit and twenty extras is 24")
    session.insertBatch(" bay", at: start.addingTimeInterval(0.2))
    XCTAssertEqual(session.typed, wrong + " bay")
    XCTAssertEqual(session.outcome, .completed)
  }

  func testUnicodeQuickCompletionRetainsMetricsReplayAndPortableResult() throws {
    for configuration in configurations() {
      var session = TypingSession(configuration: configuration, prompt: "seed ab")
      session.insertBatch("seed ", at: start)
      session.insertBatch("🙂", at: start.addingTimeInterval(0.2))
      let result = try XCTUnwrap(session.result())
      XCTAssertEqual(result.outcome, .completed)
      XCTAssertEqual(result.inputMetrics?.totalAttempts, 7)
      XCTAssertEqual(result.inputMetrics?.correctAttempts, 5)
      XCTAssertEqual(String(decoding: result.replayEvents.flatMap(\.inputUnits), as: UTF16.self), "seed 🙂")
      XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents,
        through: result.elapsedDuration), session.typed)
      XCTAssertEqual(try JSONDecoder().decode(CompletedTestResult.self,
        from: JSONEncoder().encode(result)), result)
      XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
      session.insertBatch("x", at: start.addingTimeInterval(0.3))
      XCTAssertEqual(session.typed, "seed 🙂")
      XCTAssertFalse(session.repeatedAttempt().hasStarted)
    }
  }

  @MainActor func testNativeWrongCandidateStaysMarkedDespiteMatchingUTF16Length() {
    var session = TypingSession(configuration: configurations()[0], prompt: "seed ab")
    session.insertBatch("seed ", at: start)
    let input = TypingInputView(frame: .zero)
    input.onCompositionStarted = { session.beginComposition(at: self.start.addingTimeInterval(0.1)) }
    input.shouldFinishWithComposition = { text, forced in
      session.shouldFinishWithComposition(text, forceError: forced, at: self.start.addingTimeInterval(0.2))
    }
    input.onInsert = { text, forced in
      session.insertBatch(text, forceError: forced, at: self.start.addingTimeInterval(0.2))
    }
    input.setMarkedText("🙂", selectedRange: .init(), replacementRange: .init())
    XCTAssertTrue(input.hasMarkedText())
    XCTAssertEqual(session.typed, "seed ")
    XCTAssertEqual(session.outcome, .active)
    input.insertText("🙂", replacementRange: .init())
    XCTAssertFalse(input.hasMarkedText())
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.typed, "seed 🙂")
  }

  func testGeneratedWordLimitNotTheCurrentChunkDecidesWhichWordCanQuickEnd() {
    var session = TypingSession(configuration: .words(3, rules: .init(quickEnd: true)),
      prompt: "seed ab", repeatingPrompt: "seed ab")
    session.insertBatch("seed 🙂", at: start)
    XCTAssertEqual(session.outcome, .active)
    session.insertBatch(" ", at: start.addingTimeInterval(0.1))
    XCTAssertEqual(session.outcome, .active)
    session.insertBatch("🇨🇦", at: start.addingTimeInterval(0.2))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.typed, "seed 🙂 🇨🇦")
  }

  func testSeparatelyConfirmedCombiningMarkUsesTheRetainedFinalWordUTF16Length() throws {
    for configuration in configurations() {
      var session = TypingSession(configuration: configuration, prompt: "seed ab")
      session.insertBatch("seed e", at: start)
      XCTAssertEqual(session.outcome, .active)
      session.insertBatch("\u{301}", at: start.addingTimeInterval(0.2))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.typed, "seed e\u{301}")
      let result = try XCTUnwrap(session.result())
      XCTAssertEqual(result.inputMetrics?.totalAttempts, 7)
      XCTAssertEqual(result.inputMetrics?.correctAttempts, 5)
      XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents,
        through: result.elapsedDuration), session.typed)
    }
  }

  func testTimedAndInfiniteAttemptsDoNotUseFiniteQuickEnd() {
    for configuration in [TestConfiguration.timed(seconds: 30, rules: .init(quickEnd: true)),
      .words(0, rules: .init(quickEnd: true))]
    {
      var session = TypingSession(configuration: configuration, prompt: "seed ab")
      session.insertBatch("seed 🙂", at: start)
      XCTAssertEqual(session.outcome, .active)
      session.tick(at: start.addingTimeInterval(0.2))
      XCTAssertEqual(session.outcome, .active)
    }
  }

  func testHiddenNoSpaceBoundariesKeepTheirExistingCompletionPath() {
    var session = TypingSession(configuration: .words(2, rules: .init(quickEnd: true),
      language: .simplifiedChinese), prompt: "晴天星光", noSpaceWordEndIndices: [2, 4],
      noSpaceTargetWords: ["晴天", "星光"])
    session.insertBatch("晴天🙂", at: start)
    XCTAssertEqual(session.outcome, .active)
    session.insertBatch("光", at: start.addingTimeInterval(0.2))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.typed, "晴天🙂光")
  }

  private func configurations(quickEnd: Bool = true) -> [TestConfiguration] {
    let rules = InputRules(quickEnd: quickEnd)
    return [
      .words(2, rules: rules),
      .init(mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal, rules: rules),
      .init(mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal,
        rules: rules, customTextCompletion: .finish),
      .init(mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal,
        rules: rules, customTextCompletion: .sections, customTextSectionLimit: 1),
    ]
  }
}
