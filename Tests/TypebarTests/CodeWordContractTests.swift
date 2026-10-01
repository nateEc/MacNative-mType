import AppKit
import XCTest
@testable import Typebar

final class CodeWordContractTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 100)

  func testEveryCodeChoiceUsesTheRequestedFiniteWordBudgetRatherThanWholePrograms() {
    for language in TypingLanguage.allCases.filter(\.isCodeLanguage) {
      for limit in [1, 2, 25, 100, 101] {
        let session = TestSessionFactory.make(configuration: .words(limit, language: language))
        XCTAssertEqual(session.prompt.split(whereSeparator: \.isWhitespace).count,
          min(limit, 100), "\(language): \(limit)")
        XCTAssertFalse(session.prompt.contains("\n"), "\(language): generated code words are not program blocks")
        XCTAssertFalse(session.prompt.contains("\t"), "\(language): indentation remains a custom-text input feature")
      }
    }
  }

  func testOneCodeWordFinishesWithoutRequiringTheRestOfTheAuthoredSnippet() {
    var session = TestSessionFactory.make(configuration: .words(1, language: .codeSwift))
    let word = String(session.prompt.split(whereSeparator: \.isWhitespace)[0])
    session.insertBatch(word, at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.typed, word)
    XCTAssertEqual(session.prompt, word)
  }

  func testWrongFinalCodeWordStaysEditableWithoutQuickEndUntilItIsCommitted() {
    var session = TypingSession(configuration: .words(4, language: .codeSwift),
      prompt: "let vessel = seed")
    session.insertBatch("let vessel = xxxx", at: start)
    XCTAssertEqual(session.outcome, .active)
    session.deleteBackward(at: start.addingTimeInterval(0.1))
    XCTAssertEqual(session.typed, "let vessel = xxx")
    session.insertBatch("x ", at: start.addingTimeInterval(0.2))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.typed, "let vessel = xxxx ")
  }

  func testCodeQuickEndUsesUTF16LengthForTheFinalWord() {
    var session = TypingSession(configuration: .words(4, rules: .init(quickEnd: true), language: .codeSwift),
      prompt: "let vessel = ab")
    session.insertBatch("let vessel = ", at: start)
    session.insertBatch("🙂", at: start.addingTimeInterval(0.2))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.typed, "let vessel = 🙂")
  }

  func testCodeAllowsAnEarlyIncorrectWordCommitThenFinishesOnItsCorrectLastWord() {
    var session = TypingSession(configuration: .words(4, language: .codeSwift),
      prompt: "let vessel = seed")
    session.insertBatch("l ", at: start)
    XCTAssertEqual(session.outcome, .active)
    session.insertBatch("vessel = seed", at: start.addingTimeInterval(0.2))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.typed, "l vessel = seed")
    XCTAssertGreaterThan(session.errors, 0)
  }

  func testCodeStopOnErrorWordRetainsTheSeparatorWithoutCommittingTheIncorrectFinalWord() {
    var session = TypingSession(configuration: .words(4,
      rules: .init(stopOnErrorMode: .word, quickEnd: true), language: .codeSwift),
      prompt: "let vessel = seed")
    session.insertBatch("let vessel = xxxx", at: start)
    XCTAssertEqual(session.outcome, .active)
    session.insertBatch(" ", at: start.addingTimeInterval(0.2))
    XCTAssertEqual(session.outcome, .active)
    XCTAssertEqual(session.typed, "let vessel = xxxx ")
    session.deleteBackward(at: start.addingTimeInterval(0.3))
    XCTAssertEqual(session.typed, "let vessel = xxxx")
  }

  func testTimedAndInfiniteCodePracticeUseA100WordOpening() {
    for configuration in [TestConfiguration.timed(seconds: 30, language: .codeSwift),
      .words(0, language: .codeSwift)]
    {
      let session = TestSessionFactory.make(configuration: configuration)
      XCTAssertEqual(session.prompt.split(whereSeparator: \.isWhitespace).count, 100)
      XCTAssertFalse(session.prompt.contains("\n"))
      XCTAssertFalse(session.isFinished)
    }
  }

  func testOrdinaryWordStopKeepsRepeatedSeparatorsInsideTheEditableWord() throws {
    var session = TypingSession(configuration: .timed(seconds: 30,
      rules: .init(stopOnErrorMode: .word)), prompt: "abc bay")
    session.insertBatch("abx  b", at: start)
    XCTAssertEqual(session.typed, "abx  b")
    XCTAssertEqual(session.completedWordCount, 0)
    XCTAssertEqual(session.wordReviews.map(\.typed), ["abx  b"])
    XCTAssertEqual(session.wpm(at: start.addingTimeInterval(1)), 0)
    session.tick(at: start.addingTimeInterval(30))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.replayEvents.filter { $0.commitsWord == false }.count, 2)
    let trace = ResultPerformanceTrace.point(prompt: result.prompt, events: result.replayEvents,
      elapsed: 1, configuration: result.configuration)
    XCTAssertEqual(trace.wpm, 0)
    XCTAssertEqual(trace.errorCount, 3) // x, second separator, and b; first separator matches.
    XCTAssertEqual(TypingReplay.inputGlyphs(prompt: result.prompt, events: result.replayEvents,
      through: 1).last?.state, .extra)
    XCTAssertNil(TypingReplay.characterSeekOffsets(prompt: result.prompt,
      events: result.replayEvents)[4]) // b never reached the second target word.
    XCTAssertEqual(try JSONDecoder().decode(CompletedTestResult.self,
      from: JSONEncoder().encode(result)), result)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
  }

  func testReplayKeepsWordStopCursorAcrossDeletionAndARealCommit() {
    let events: [TypingReplayEvent] = [
      .init(offset: 0.1, kind: .insert, text: "abx"),
      .init(offset: 0.2, kind: .insert, text: " ", commitsWord: false),
      .init(offset: 0.3, kind: .insert, text: "b"),
      .init(offset: 0.4, kind: .delete, text: ""),
      .init(offset: 0.5, kind: .delete, text: ""),
      .init(offset: 0.6, kind: .delete, text: ""),
      .init(offset: 0.7, kind: .insert, text: "c"),
      .init(offset: 0.8, kind: .insert, text: " "),
      .init(offset: 0.9, kind: .insert, text: "bay"),
    ]
    let prompt = "abc bay"
    XCTAssertEqual(TypingReplay.inputGlyphs(prompt: prompt, events: events,
      through: 0.3).last?.state, .extra)
    XCTAssertEqual(TypingReplay.soundCues(prompt: prompt, events: events,
      after: 0.2, through: 0.3), [.error])
    XCTAssertEqual(TypingReplay.typedText(events: events, through: 1), prompt)
    XCTAssertTrue(TypingReplay.inputGlyphs(prompt: prompt, events: events,
      through: 1).allSatisfy { $0.state == .correct })
    XCTAssertEqual(TypingReplay.characterSeekOffsets(prompt: prompt, events: events)[4], 0.9)
    let trace = ResultPerformanceTrace.point(prompt: prompt, events: events,
      elapsed: 1, configuration: .words(2))
    XCTAssertEqual(trace.wpm, 84)
    XCTAssertEqual(trace.errorCount, 2)
  }

  func testCodeCursorClampsTheFiniteTailAndRetainsUnusedSourceWords() {
    var cursor = GeneratedCodeContinuation(configuration: .words(101, language: .codeSwift),
      batchTokenCount: 100, nextUnitIndex: 0)
    let first = cursor.nextChunk()
    let tail = cursor.nextChunk()
    XCTAssertEqual(first.source.split(separator: " ").count, 100)
    XCTAssertEqual(tail.source.split(separator: " ").count, 1)
    XCTAssertTrue(tail.source.hasPrefix(" "))
    XCTAssertFalse(cursor.hasRemaining)
    XCTAssertEqual(cursor.nextChunk().source, "")
    var expected: [String] = []
    for index in 0..<20 {
      expected += CodePracticeContent.prompt(language: .codeSwift, targetTokenCount: 1,
        startUnitIndex: index).split(whereSeparator: \.isWhitespace).map(String.init)
    }
    XCTAssertEqual(first.source + tail.source, expected.prefix(101).joined(separator: " "))
  }

  func testTurningWordStopOffDoesNotReclassifyAlreadyRetainedSeparators() {
    var session = TypingSession(configuration: .words(2,
      rules: .init(stopOnErrorMode: .word)), prompt: "abc bay")
    session.insertBatch("abx ", at: start)
    session.synchronizeLiveInputRules(.init(confidenceMode: .on))
    session.deleteBackward(at: start.addingTimeInterval(0.1))
    XCTAssertEqual(session.typed, "abx") // retained space is current input, not a protected commit.
    session.deleteWordBackward(at: start.addingTimeInterval(0.2))
    XCTAssertEqual(session.typed, "")
    session.insertBatch("abc bay", at: start.addingTimeInterval(0.3))
    XCTAssertEqual(session.outcome, .completed)
  }

  func testWordStopExpertFailsOnAcceptedSeparatorWithoutAdvancing() {
    var session = TypingSession(configuration: .words(2, difficulty: .expert,
      rules: .init(stopOnErrorMode: .word)), prompt: "abc bay")
    session.insertBatch("abx", at: start)
    XCTAssertEqual(session.outcome, .active)
    session.insertBatch(" ", at: start.addingTimeInterval(0.2))
    XCTAssertEqual(session.outcome, .failed)
    XCTAssertEqual(session.typed, "abx ")
    XCTAssertEqual(session.completedWordCount, 0)
  }

  func testOldReplayEventsDecodeWithoutInventingWordStopMetadata() throws {
    let data = Data("[{\"offset\":0,\"kind\":\"insert\",\"text\":\"a \"}]".utf8)
    let events = try JSONDecoder().decode([TypingReplayEvent].self, from: data)
    XCTAssertNil(events[0].commitsWord)
    XCTAssertEqual(TypingReplay.typedText(events: events, through: 1), "a ")
  }

  func testWordStopStrictLeadingSeparatorRemainsInTheFirstField() {
    for difficulty in [Difficulty.normal, .expert] {
      var session = TypingSession(configuration: .words(2, difficulty: difficulty,
        rules: .init(strictSpace: true, stopOnErrorMode: .word)), prompt: "abc bay")
      session.insertBatch(" ", at: start)
      XCTAssertEqual(session.typed, " ")
      XCTAssertEqual(session.completedWordCount, 0)
      XCTAssertEqual(session.outcome, .active)
      XCTAssertEqual(session.wordReviews.map(\.typed), [" "])
      session.deleteBackward(at: start.addingTimeInterval(0.1))
      XCTAssertEqual(session.typed, "")
      session.insertBatch("abc bay", at: start.addingTimeInterval(0.2))
      XCTAssertEqual(session.outcome, .completed)
    }
    var ordinary = TypingSession(configuration: .words(2,
      rules: .init(stopOnErrorMode: .word)), prompt: "abc bay")
    ordinary.insertBatch(" ", at: start)
    XCTAssertEqual(ordinary.typed, "")
    XCTAssertFalse(ordinary.hasStarted)
  }

  func testWordStopCannotBypassTheInputLimitWithUncommittedSpaces() {
    var session = TypingSession(configuration: .words(2,
      rules: .init(stopOnErrorMode: .word)), prompt: "abc bay")
    session.insertBatch("a" + String(repeating: "x", count: 23), at: start)
    let input = session.typed
    let accuracy = session.preciseAccuracy
    session.insertBatch("  ", at: start.addingTimeInterval(0.1))
    XCTAssertEqual(session.typed, input)
    XCTAssertEqual(session.preciseAccuracy, accuracy)
    XCTAssertEqual(session.completedWordCount, 0)
    XCTAssertEqual(session.outcome, .active)
  }

  @MainActor func testWrongCodeCandidateIsNotAutoConfirmedButConfirmedInputCanQuickEnd() throws {
    var session = TypingSession(configuration: .words(4, rules: .init(quickEnd: true), language: .codeSwift),
      prompt: "let vessel = ab")
    session.insertBatch("let vessel = ", at: start)
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
    XCTAssertEqual(session.typed, "let vessel = ")
    XCTAssertFalse(session.isFinished)
    input.insertText("🙂", replacementRange: .init())
    XCTAssertEqual(session.outcome, .completed)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents,
      through: result.elapsedDuration), session.typed)
    XCTAssertEqual(try JSONDecoder().decode(CompletedTestResult.self,
      from: JSONEncoder().encode(result)), result)
  }
}
