import AppKit
import XCTest
@testable import Typebar

final class CompositionCompletionTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_700_000_000)

  @MainActor
  func testMatchingFinalArabicCompositionCompletesOnceThroughTheNativeBridge() throws {
    var session = TypingSession(configuration: .words(2, language: .arabic), prompt: "نافذة طريق")
    let input = TypingInputView(frame: .zero)
    var now = start
    var marked = [String]()
    input.onCompositionStarted = { session.beginComposition(at: now) }
    input.onCompositionChanged = { marked.append($0) }
    input.shouldFinishWithComposition = { text, forced in
      session.shouldFinishWithComposition(text, forceError: forced, at: now)
    }
    input.onInsert = { text, forced in session.insertBatch(text, forceError: forced, at: now) }
    input.insertText("نافذة ", replacementRange: .init())
    now = start.addingTimeInterval(1)
    input.setMarkedText("طر", selectedRange: .init(), replacementRange: .init())
    XCTAssertTrue(input.hasMarkedText())
    XCTAssertEqual(session.typed, "نافذة ")
    XCTAssertEqual(session.outcome, .active)

    now = start.addingTimeInterval(2)
    input.setMarkedText("طريق", selectedRange: .init(), replacementRange: .init())
    XCTAssertFalse(input.hasMarkedText())
    XCTAssertEqual(input.markedRange().location, NSNotFound)
    XCTAssertEqual(marked.last, "")
    XCTAssertEqual(session.typed, "نافذة طريق")
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
    let events = try XCTUnwrap(session.result(at: now)).replayEvents
    input.insertText("طريق", replacementRange: .init())
    XCTAssertEqual(session.typed, "نافذة طريق")
    XCTAssertEqual(session.result(at: now)?.replayEvents, events)
    let result = try XCTUnwrap(session.result(at: now))
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: result.elapsedDuration), session.typed)
  }

  func testOnlyTheCorrectFinalWordMayFinishAndTheProbeDoesNotMutateSession() {
    var session = TypingSession(configuration: .words(2), prompt: "amber pine")
    XCTAssertFalse(session.shouldFinishWithComposition("amber", at: start))
    session.insert("axber pi", at: start)
    let before = session.typedCharacterCount
    XCTAssertTrue(session.shouldFinishWithComposition("ne", at: start.addingTimeInterval(1)))
    XCTAssertFalse(session.shouldFinishWithComposition("na", at: start.addingTimeInterval(1)))
    XCTAssertFalse(session.shouldFinishWithComposition("ne", forceError: true, at: start.addingTimeInterval(1)))
    XCTAssertEqual(session.typed, "axber pi")
    XCTAssertEqual(session.outcome, .active)
    XCTAssertEqual(session.typedCharacterCount, before)

    var quickEnd = TypingSession(configuration: .words(2, rules: .init(quickEnd: true)), prompt: "amber pine")
    quickEnd.insert("amber pi", at: start)
    XCTAssertFalse(quickEnd.shouldFinishWithComposition("na", at: start.addingTimeInterval(1)))
    XCTAssertFalse(quickEnd.shouldFinishWithComposition("", at: start.addingTimeInterval(1)))
  }

  func testTimedInfiniteAndZenCompositionCannotFinishPractice() {
    let zen = TestConfiguration(mode: .zen, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init())
    for configuration in [TestConfiguration.timed(seconds: 30), .timed(seconds: 0), .words(0), zen] {
      var session = TypingSession(configuration: configuration, prompt: "pine")
      session.beginComposition(at: start)
      XCTAssertFalse(session.shouldFinishWithComposition("pine", at: start.addingTimeInterval(1)))
      XCTAssertEqual(session.outcome, .active)
      XCTAssertTrue(session.typed.isEmpty)
    }
  }

  func testFiniteCustomCompositionCanFinishButMatchingEarlierWordStaysMarked() {
    var session = TestSessionFactory.make(
      configuration: .init(mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()),
      customText: "amber pine")
    XCTAssertFalse(session.shouldFinishWithComposition("amber", at: start))
    session.insert("amber ", at: start)
    XCTAssertTrue(session.shouldFinishWithComposition("pine", at: start.addingTimeInterval(1)))
    session.insert("pine", at: start.addingTimeInterval(1))
    XCTAssertFalse(session.shouldFinishWithComposition("pine", at: start.addingTimeInterval(2)))
  }

  func testFinalNoSpaceWordMayFinishEvenAfterAnEarlierIncorrectWord() {
    var session = TypingSession(
      configuration: .words(2, language: .simplifiedChinese), prompt: "窗户道路",
      noSpaceWordEndIndices: [2, 4], noSpaceTargetWords: ["窗户", "道路"])
    XCTAssertFalse(session.shouldFinishWithComposition("窗户", at: start))
    XCTAssertFalse(session.shouldFinishWithComposition("窗户道路", at: start))
    session.insert("花户道", at: start)
    XCTAssertTrue(session.shouldFinishWithComposition("路", at: start.addingTimeInterval(1)))
    XCTAssertFalse(session.shouldFinishWithComposition("陆", at: start.addingTimeInterval(1)))
    XCTAssertEqual(session.typed, "花户道")
    XCTAssertEqual(session.completedWordCount, 1)
    XCTAssertEqual(session.outcome, .active)
  }

  func testFinalWordOfIncrementalStreamUsesTheConfiguredLimitNotTheChunkEdge() {
    var session = TypingSession(
      configuration: .words(3), prompt: "amber pine", repeatingPrompt: "amber pine")
    session.insert("amber ", at: start)
    XCTAssertFalse(session.shouldFinishWithComposition("pine", at: start.addingTimeInterval(1)))
    session.insert("pine ", at: start.addingTimeInterval(1))
    XCTAssertTrue(session.usesIncrementalPromptExtension)
    XCTAssertTrue(session.shouldFinishWithComposition("amber", at: start.addingTimeInterval(2)))
    XCTAssertEqual(session.completedWordCount, 2)
    XCTAssertEqual(session.outcome, .active)
  }

  func testFinalCodeWordCanFinishWhenTheGeneratedCursorStillExists() {
    let configuration = TestConfiguration.words(4, language: .codeSwift)
    var cursor = GeneratedCodeContinuation(configuration: configuration, batchTokenCount: 4,
      sourceWords: ["let value = item"])
    _ = cursor.nextChunk(nextRandomWordIndex: { 0 })
    var session = TypingSession(
      configuration: configuration, prompt: "let value = item",
      generatedCodeContinuation: cursor)
    session.insert("let value = ", at: start)
    XCTAssertFalse(session.usesIncrementalPromptExtension)
    XCTAssertTrue(session.shouldFinishWithComposition("item", at: start.addingTimeInterval(1)))
    XCTAssertEqual(session.typed, "let value = ")
    session.insertBatch("item", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
  }

  func testQuoteAndCustomWordLimitUseTheSameFinalCompositionRule() {
    var quote = TypingSession(
      configuration: .init(mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()),
      prompt: "amber pine")
    quote.insert("amber pi", at: start)
    XCTAssertTrue(quote.shouldFinishWithComposition("ne", at: start.addingTimeInterval(1)))

    var custom = TestSessionFactory.make(
      configuration: .init(
        mode: .custom, duration: nil, wordLimit: 3, difficulty: .normal, rules: .init(),
        customTextCompletion: .words), customText: "amber pine")
    custom.insert("amber pine ", at: start)
    XCTAssertTrue(custom.shouldFinishWithComposition("amber", at: start.addingTimeInterval(1)))
    XCTAssertEqual(custom.outcome, .active)
  }

  func testForcedErrorInTheFinalPrefixCannotBeBypassedByCompositionOrQuickEnd() {
    var session = TypingSession(
      configuration: .words(2, rules: .init(quickEnd: true)), prompt: "amber pine")
    session.insert("amber ", at: start)
    session.insertBatch("pi", forceError: true, at: start)
    XCTAssertFalse(session.shouldFinishWithComposition("ne", at: start.addingTimeInterval(1)))
    XCTAssertEqual(session.typed, "amber pi")
    XCTAssertEqual(session.outcome, .active)
  }

  @MainActor
  func testNativeCompletionDecisionUsesTheSameMirroredTextAsInsertion() {
    var session = TypingSession(configuration: .words(1), prompt: "p")
    let input = TypingInputView(frame: .zero)
    input.shouldFinishWithComposition = { text, forced in
      session.shouldFinishWithComposition(KeyboardMirror.transform(text), forceError: forced, at: self.start)
    }
    input.onCompositionStarted = { session.beginComposition(at: self.start) }
    input.onInsert = { text, forced in
      session.insertBatch(KeyboardMirror.transform(text), forceError: forced, at: self.start)
    }
    input.setMarkedText("p", selectedRange: .init(), replacementRange: .init())
    XCTAssertTrue(input.hasMarkedText())
    XCTAssertTrue(session.typed.isEmpty)
    input.setMarkedText("q", selectedRange: .init(), replacementRange: .init())
    XCTAssertFalse(input.hasMarkedText())
    XCTAssertEqual(session.typed, "p")
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
  }
}
