import XCTest
@testable import Typebar

final class GeneratedLookaheadTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 100)
  private func words(_ text: String) -> [String] { text.split(separator: " ").map(String.init) }

  func testOwnedGeneratedOpeningsUseOneHundredWordsAndRetainTheirCommit() {
    for configuration in [TestConfiguration.words(0), .words(501), .timed(seconds: 120),
      .words(0, language: .codeSwift), .words(0, language: .arenaStrategy),
      .words(0).with(modifiers: [.binaryStream])] {
      let session = TestSessionFactory.make(configuration: configuration)
      XCTAssertEqual(words(session.prompt).count, 100)
      XCTAssertTrue(session.prompt.hasSuffix(" "))
    }
  }

  func testOrdinaryNavigationAddsOneTargetBeforeTheOpeningQueueEnds() throws {
    var session = TestSessionFactory.make(configuration: .words(0))
    let first = try XCTUnwrap(words(session.prompt).first)
    let opening = session.prompt
    session.insertBatch(first, at: start)
    XCTAssertEqual(session.prompt, opening)
    session.insertBatch(" ", at: start.addingTimeInterval(0.2))
    XCTAssertEqual(words(session.prompt).count, 101)
    XCTAssertEqual(session.completedWordCount, 1)
    XCTAssertEqual(session.errors, 0)
    XCTAssertTrue(session.prompt.hasPrefix(opening))
  }

  func testGeneratedStreamRefillsSingleIndicesAndReplaysTheirActualFuture() {
    var session = TestSessionFactory.make(configuration: .words(0).with(modifiers: [.binaryStream]))
    let opening = session.prompt
    session.insertBatch("00000000 ", at: start)
    XCTAssertEqual(words(session.prompt).count, 101)
    XCTAssertEqual(words(session.prompt).last, "01100100")
    let firstFuture = session.prompt
    session.insertBatch("00000001 ", at: start.addingTimeInterval(1))
    XCTAssertEqual(words(session.prompt).count, 102)
    XCTAssertEqual(words(session.prompt).last, "01100101")
    var replay = session.repeatedAttempt()
    XCTAssertEqual(replay.prompt, opening)
    replay.insertBatch("00000000 ", at: start.addingTimeInterval(2))
    XCTAssertEqual(replay.prompt, firstFuture)
    replay.insertBatch("00000001 ", at: start.addingTimeInterval(3))
    XCTAssertEqual(replay.prompt, session.prompt)
    XCTAssertEqual(replay.errors, 0)
  }

  func testCodeAndOrdinaryEntryNavigationEmitOneWordNotAWholeSection() throws {
    for language in [TypingLanguage.codeSwift, .arenaStrategy, .typingOfTheDead] {
      var session = TestSessionFactory.make(configuration: .words(0, language: language))
      let first = try XCTUnwrap(words(session.prompt).first)
      session.insertBatch(first + " ", at: start)
      XCTAssertEqual(words(session.prompt).count, 101, language.rawValue)
      XCTAssertEqual(session.completedWordCount, 1, language.rawValue)
      XCTAssertEqual(session.errors, 0, language.rawValue)
    }
  }

  func testVisibilityPushUsesItsOneToFourWordOpeningEvenWithWholePreview() {
    for (modifier, count) in [(TestModifier.focusCurrentWord, 1), (.focusNextWord, 2),
      (.focusTwoWords, 3), (.focusThreeWords, 4)] {
      for showAll in [false, true] {
        var session = TestSessionFactory.make(configuration: .words(8).with(modifiers: [.binaryStream, modifier]),
          showAllLines: showAll)
        XCTAssertEqual(words(session.prompt).count, count)
        session.insertBatch("00000000 ", at: start)
        XCTAssertEqual(words(session.prompt).count, count + 1)
        XCTAssertEqual(session.completedWordCount, 1)
        XCTAssertEqual(session.errors, 0)
      }
    }
  }

  func testSingleVisibleWordFiniteTailFinishesWithoutGeneratingPastItsBudget() {
    var session = TestSessionFactory.make(configuration: .words(3).with(modifiers: [.binaryStream, .focusCurrentWord]))
    session.insertBatch("00000000 ", at: start)
    XCTAssertEqual(words(session.prompt).count, 2)
    session.insertBatch("00000001 ", at: start.addingTimeInterval(1))
    XCTAssertEqual(words(session.prompt).count, 3)
    XCTAssertFalse(session.prompt.hasSuffix(" "))
    XCTAssertFalse(session.usesIncrementalPromptExtension)
    XCTAssertTrue(session.shouldFinishWithComposition("00000010", at: start.addingTimeInterval(2)))
    session.insertBatch("00000010", at: start.addingTimeInterval(2))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 3)
    XCTAssertEqual(session.errors, 0)
  }

  func testRejectedLeadingOrWordStoppedSpaceDoesNotRefillTheQueue() {
    var session = TestSessionFactory.make(configuration: .words(0, rules: .init(stopOnErrorMode: .word))
      .with(modifiers: [.binaryStream]))
    let opening = session.prompt
    session.insertBatch(" ", at: start)
    XCTAssertEqual(session.prompt, opening)
    session.insertBatch("x ", at: start)
    XCTAssertEqual(session.prompt, opening)
    XCTAssertEqual(session.completedWordCount, 0)
  }

  func testNoSpaceNavigationRefillsBeforeItsEntirePromptIsConsumed() {
    var session = TestSessionFactory.make(configuration: .words(0).with(modifiers: [.binaryStream, .noSpaces]))
    XCTAssertEqual(session.prompt.count, 800)
    session.insertBatch("00000000", at: start)
    XCTAssertEqual(session.prompt.count, 808)
    XCTAssertEqual(session.completedWordCount, 1)
    session.insertBatch("00000001", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.prompt.count, 816)
    XCTAssertEqual(session.errors, 0)
  }

  func testWholeFinitePreviewDoesNotAddMoreTargetsOnNavigation() throws {
    var session = TestSessionFactory.make(configuration: .words(701).with(modifiers: [.binaryStream]), showAllLines: true)
    let opening = session.prompt
    session.insertBatch(try XCTUnwrap(words(opening).first) + " ", at: start)
    XCTAssertEqual(session.prompt, opening)
    XCTAssertFalse(session.usesIncrementalPromptExtension)
  }

  func testSingleWordRefillsKeepBothPreviousWordsForBoundaryRejection() {
    var cursor = GeneratedWordContinuation(configuration: .words(0), weakSpotScores: .init(),
      batchWordCount: 1, previousSource: "amber harbor")
    XCTAssertEqual(cursor.nextChunk(generator: { "bay" }).source, "bay")
    XCTAssertEqual(cursor.previousWords, ["harbor", "bay"])
    var draws = 0
    let next = cursor.nextChunk(generator: {
      defer { draws += 1 }; return draws == 0 ? "harbor" : "oak"
    })
    XCTAssertEqual(draws, 2)
    XCTAssertEqual(next.source, "oak")
    XCTAssertEqual(cursor.previousWords, ["bay", "oak"])
  }

  func testReenteringAPreviousFieldRefillsOnlyAtTheInclusiveLookaheadBoundary() {
    var session = TestSessionFactory.make(configuration: .words(0, rules: .init(freedomMode: true))
      .with(modifiers: [.binaryStream]))
    session.insertBatch("00000000 ", at: start)
    XCTAssertEqual(words(session.prompt).count, 101)
    session.deleteBackward(at: start)
    XCTAssertEqual(session.typed, "00000000")
    session.insertBatch(" ", at: start)
    XCTAssertEqual(words(session.prompt).count, 102)
    session.deleteBackward(at: start)
    session.insertBatch(" ", at: start)
    XCTAssertEqual(words(session.prompt).count, 102)
    XCTAssertEqual(session.completedWordCount, 1)
    XCTAssertEqual(session.errors, 0)
  }

  func testThousandWordNoSpaceQueueCompletesAndRepeatsWithTheOriginalGlobalTargets() throws {
    let configuration = TestConfiguration.words(1001).with(modifiers: [.binaryStream, .underscoreSeparators])
    let target = (0..<1001).map { index in
      let binary = String(index % 256, radix: 2)
      return String(repeating: "0", count: 8 - binary.count) + binary + (index == 99 ? "" : "_")
    }.joined()
    var session = TestSessionFactory.make(configuration: configuration)
    let opening = session.prompt
    session.insertBatch(target, at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.prompt, target)
    XCTAssertEqual(session.errors, 0)
    XCTAssertEqual(session.completedWordCount, 1001)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
    var replay = session.repeatedAttempt()
    XCTAssertEqual(replay.prompt, opening)
    replay.insertBatch(target, at: start.addingTimeInterval(1))
    XCTAssertEqual(replay.outcome, .completed)
    XCTAssertEqual(replay.prompt, target)
    XCTAssertEqual(replay.errors, 0)
    XCTAssertEqual(replay.completedWordCount, 1001)
  }

  func testNavigationIntoAnEmptyMorseFieldStillPrefetchesWithoutSkippingThatField() throws {
    let configuration = TestConfiguration.words(0, language: .codeSwift).with(modifiers: [.morseStream])
    var cursor = GeneratedCandidateContinuation(configuration: configuration, batchTokenCount: 2,
      sourceWords: ["e 中"])
    let opening = cursor.nextChunk(nextRandomWordIndex: { 0 })
    var session = TypingSession(configuration: configuration, prompt: opening.transformed,
      generatedCodeContinuation: cursor,
      noSpaceWordEndIndices: NoSpaceWordBoundaryPolicy.endIndices(for: opening.noSpaceWordLengths),
      noSpaceTargetWords: opening.noSpaceTargetWords)
    XCTAssertEqual(session.prompt, "./")
    session.insertBatch("./", at: start)
    XCTAssertEqual(session.prompt, "././")
    XCTAssertEqual(session.completedWordCount, 1)
    XCTAssertNil(session.nextExpectedCharacter)
    XCTAssertEqual(session.errors, 0)
    session.bailOut(at: start.addingTimeInterval(1))
    XCTAssertEqual(try XCTUnwrap(session.result()).targetWordDirectory?.words, ["./", "", "./"])
  }
}
