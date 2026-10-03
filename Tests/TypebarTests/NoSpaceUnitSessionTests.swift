import XCTest
@testable import Typebar

final class NoSpaceUnitSessionTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 909_000_000)

  private func attempt(_ source: String, rules: InputRules = .init()) -> TypingSession {
    TestSessionFactory.make(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: rules, modifiers: [.noSpaces]), customText: source)
  }

  func testLetterStopRetainsCorrectHighSurrogateInItsActualNoSpaceField() throws {
    var session = attempt("🙂x tail", rules: .init(stopOnErrorMode: .letter))
    XCTAssertEqual(session.insertBatch("🙃", at: start), [false])
    XCTAssertEqual(session.typed, "�")
    XCTAssertEqual(session.completedWordCount, 0)
    session.bailOut(at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.replayEvents.map(\.textUTF16), [[55357],[56899]])
    XCTAssertEqual(result.replayEvents.map(\.inputStopped), [nil,true])
    XCTAssertEqual(result.replayEvents.map { $0.inputField?.valueUTF16 }, [[55357],[55357]])
    XCTAssertEqual(result.inputMetrics?.correctAttempts, 1)
    XCTAssertEqual(result.inputMetrics?.retainedUnits, 1)
  }

  func testFusedDisplayDoesNotEraseTheSecondWordsUnitOrBackspaceAcrossItsField() throws {
    var session = attempt("a \u{301}b tail", rules: .init(freedomMode: true))
    session.insert("a", at: start)
    XCTAssertEqual(session.completedWordCount, 1)
    session.insert("\u{301}", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "a\u{301}")
    session.deleteBackward(at: start.addingTimeInterval(2))
    XCTAssertEqual(session.typed, "a")
    XCTAssertEqual(session.completedWordCount, 1)
    session.bailOut(at: start.addingTimeInterval(3))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.replayEvents.map { $0.inputField?.index }, [0,1,1])
    XCTAssertEqual(result.replayEvents.map { $0.inputField?.valueUTF16 }, [[97],[769],[]])
    XCTAssertEqual(TypingReplay.typedUTF16(events: result.replayEvents, through: 3), [97])
    XCTAssertEqual(session.wordReviews.map(\.target), ["a","\u{301}b"])
  }

  func testWordStopRetainsWrongFinalUnitAndExtrasWithoutCommittingOrFinishing() throws {
    var session = attempt("ab cd", rules: .init(stopOnErrorMode: .word))
    session.insertBatch("xb", at: start)
    XCTAssertEqual(session.typed, "xb")
    XCTAssertEqual(session.completedWordCount, 0)
    session.insert("c", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "xbc")
    XCTAssertEqual(session.outcome, .active)
    XCTAssertEqual(session.completedWordCount, 0)
    session.bailOut(at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.replayEvents.map { $0.inputField?.index }, [0,0,0])
    XCTAssertEqual(result.replayEvents.map { $0.inputField?.valueUTF16 }, [[120],[120,98],[120,98,99]])
    XCTAssertEqual(result.inputMetrics?.retainedUnits, 3)
    XCTAssertEqual(result.wpm, 0)
  }

  func testRegionalIndicatorTargetsKeepSeparateFieldsEvenInsideOneGlyph() throws {
    var session = attempt("🇫 🇷🇨", rules: .init(freedomMode: true))
    session.insert("🇫", at: start)
    XCTAssertEqual(session.completedWordCount, 1)
    session.insert("🇷🇨", at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.outcome, .completed)
    XCTAssertEqual(result.replayEvents.map { $0.inputField?.index }, [0,0,1,1,1,1])
    XCTAssertEqual(result.inputMetrics?.creditedUnits, 6)
    XCTAssertEqual(session.wordReviews.map(\.target), ["🇫","🇷🇨"])
    XCTAssertEqual(session.wordReviews.map(\.typed), ["🇫","🇷🇨"])
    XCTAssertEqual(result.wpm, 72)
  }

  func testWordStopCapCountsUnitsAndItsTerminalFieldCannotFinishPrematurely() throws {
    var session = attempt("ab", rules: .init(stopOnErrorMode: .word))
    session.insertBatch("xb" + String(repeating: "🙂", count: 20), at: start)
    XCTAssertEqual(session.typed.utf16.count, 22)
    XCTAssertEqual(session.completedWordCount, 0)
    XCTAssertEqual(session.outcome, .active)
    session.bailOut(at: start.addingTimeInterval(1))
    XCTAssertEqual(session.result()?.inputMetrics?.totalAttempts, 22)
    XCTAssertEqual(session.result()?.replayEvents.count, 22)
  }

  func testHardRecoveryReopensOnlyOneUnitOfACommittedSurrogateTarget() throws {
    var session = attempt("🙂 x tail", rules: .init(deleteOnErrorMode: .letterHard))
    session.insertBatch("🙂", at: start)
    session.insert("z", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "�")
    XCTAssertEqual(session.completedWordCount, 0)
    session.bailOut(at: start.addingTimeInterval(2))
    let events = try XCTUnwrap(session.result()).replayEvents
    XCTAssertEqual(events.map(\.kind), [.insert,.insert,.insert,.delete,.delete])
    XCTAssertEqual(events.map { $0.inputField?.index }, [0,0,1,1,0])
    XCTAssertEqual(events.last?.inputField?.valueUTF16, [55357])
    XCTAssertEqual(TypingReplay.typedUTF16(events: events, through: 2), [55357])
  }

  func testWordDeletionUsesFieldsInsideAFlagAndProtectsThePriorCorrectWord() {
    for freedom in [false,true] {
      var session = attempt("🇫 🇷🇨 tail", rules: .init(freedomMode: freedom))
      session.insertBatch("🇫🇷", at: start)
      session.deleteWordBackward(at: start.addingTimeInterval(1))
      XCTAssertEqual(session.typed, "🇫")
      XCTAssertEqual(session.completedWordCount, 1)
      session.deleteBackward(at: start.addingTimeInterval(2))
      XCTAssertEqual(session.typed, freedom ? "�" : "🇫")
      XCTAssertEqual(session.completedWordCount, freedom ? 0 : 1)
    }
  }

  func testBurstUsesEveryUnitAndVirtualTailOfAnImplicitCommitOnce() throws {
    var session = attempt("🙂x tail")
    session.insert("🙂", at: start)
    session.insert("x", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.burstWpm, 48)
    session.bailOut(at: start.addingTimeInterval(2))
    XCTAssertEqual(session.wordBurstHistory, [48])
    XCTAssertEqual(session.result()?.inputMetrics?.creditedUnits, 3)
  }

  func testRawDirectoryCompositionFinishesOnlyItsActualLastField() {
    let sole = attempt("🙂")
    XCTAssertTrue(sole.shouldFinishWithComposition("🙂", at: start))
    var session = attempt("🇫 🇷🇨")
    XCTAssertFalse(session.shouldFinishWithComposition("🇫", at: start))
    session.insertBatch("🇫🇷", at: start)
    XCTAssertTrue(session.shouldFinishWithComposition("🇨", at: start.addingTimeInterval(1)))
    XCTAssertFalse(session.shouldFinishWithComposition("🇱", at: start.addingTimeInterval(1)))
    XCTAssertEqual(session.outcome, .active)
  }

  func testExpertEvaluatesWrongAttemptedFinalUnitEvenWhenWordStopRetainsIt() {
    var configuration = TestConfiguration.words(2, rules: .init(stopOnErrorMode: .word))
      .with(modifiers: [.noSpaces])
    configuration.difficulty = .expert
    var session = TypingSession(configuration: configuration, prompt: "🙂xtail",
      noSpaceTargetWords: ["🙂x","tail"])
    session.insertBatch("🙃x", at: start)
    XCTAssertEqual(session.typed, "🙃x")
    XCTAssertEqual(session.outcome, .failed)
    XCTAssertEqual(session.completedWordCount, 0)
  }

  func testStrictLeadingFinalNewlineMatchesWithoutFabricatingNavigation() throws {
    var session = TypingSession(configuration: .init(mode: .quote, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(strictSpace: true), modifiers: [.noSpaces]),
      prompt: "a\n", noSpaceTargetWords: ["a","\n"])
    session.insert("a", at: start)
    session.insert("\n", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 2)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.replayEvents.last?.commitsWord, false)
    XCTAssertEqual(result.replayEvents.last?.inputField?.index, 1)
    XCTAssertEqual(result.inputMetrics?.creditedUnits, 2)
  }

  func testCorrectedFusedFieldKeepsOnlyItsOwnHistoricalErrorWeight() {
    var session = attempt("a \u{301}b tail")
    session.insert("a", at: start)
    session.insert("x", at: start.addingTimeInterval(1))
    session.deleteBackward(at: start.addingTimeInterval(2))
    session.insertBatch("\u{301}b", at: start.addingTimeInterval(3))
    XCTAssertEqual(session.missedWordErrorCountsByWord, [0,1,0])
    XCTAssertEqual(session.missedWords, ["\u{301}b"])
    XCTAssertEqual(session.wordReviews.map(\.hasInputError), [false,true])
  }

  func testFusedRepeatingTargetsDoNotLoseTheirDirectoryOnGrowth() {
    var session = TypingSession(configuration: .timed(seconds: 5).with(modifiers: [.noSpaces]),
      prompt: "a\u{301}", repeatingPrompt: "a\u{301}", noSpaceTargetWords: ["a","\u{301}"],
      repeatingNoSpaceTargetWords: ["a","\u{301}"])
    session.insertBatch("a\u{301}a\u{301}", at: start)
    XCTAssertEqual(session.completedWordCount, 4)
    session.tick(at: start.addingTimeInterval(5))
    XCTAssertEqual(session.result()?.targetWordDirectory?.words, ["a","\u{301}","a","\u{301}","a","\u{301}"])
    XCTAssertEqual(session.wordReviews.map(\.typed), ["a","\u{301}","a","\u{301}"])
    XCTAssertEqual(session.result()?.inputMetrics?.creditedUnits, 4)
  }
}
