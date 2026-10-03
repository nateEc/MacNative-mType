import XCTest
@testable import Typebar

final class OrdinaryEntryGenerationTests: XCTestCase {
  func testFactoryUsesOwnedEntryRanksAndCountsEmittedWordsForAllFourEntryPaths() {
    let cases: [(TypingLanguage, Int, String, ContentOptions)] = [
      (.typingOfTheDead, 0, "The hallway", .init(includePunctuation: true)),
      (.pokemon1k, 0, "ash cub", .init()),
      (.arenaStrategy, 53, StarterLexicon.arenaStrategyEntries[53].lowercased(), .init()),
      (.tamilOld, 2, StarterLexicon.tamilOldWords[2], .init()),
    ]
    for (language, rank, expected, options) in cases {
      var draws = 0
      let session = TestSessionFactory.make(configuration: .words(2, language: language, contentOptions: options),
        nextRandomWordIndex: { draws += 1; return rank })
      XCTAssertEqual(session.prompt, expected, language.rawValue)
      XCTAssertEqual(draws, 2, language.rawValue)
    }
  }

  func testOriginalPunctuationSkipsAdditionalDecorationAtAOneWordLimit() {
    var ranks = 0, units = 0
    let session = TestSessionFactory.make(configuration: .words(1, language: .typingOfTheDead,
      contentOptions: .init(includePunctuation: true)), nextRandomWordIndex: { ranks += 1; return 0 },
      nextRandomContentUnit: { units += 1; return 0 })
    XCTAssertEqual(session.prompt, "The")
    XCTAssertEqual(ranks, 1)
    XCTAssertEqual(units, 0)
  }

  func testOrdinarySectionLowercasesComponentsAndKeepsPendingWordsAcrossChunks() {
    var cursor = GeneratedCodeContinuation(configuration: .words(3, language: .arenaStrategy),
      batchTokenCount: 2, sourceWords: ["Node Bay Elm", "Oak"])
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: { 0 }).transformed, "node bay")
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: { 1 }).transformed, " elm")
    XCTAssertFalse(cursor.hasRemaining)
  }

  func testOrdinaryPunctuationOffRejectsOnlyTheSourceASCIISymbolSet() {
    var cursor = GeneratedCodeContinuation(configuration: .words(1, language: .pokemon1k),
      batchTokenCount: 1, sourceWords: ["node-ray", "foo♀"])
    var draws = 0
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: {
      defer { draws += 1 }; return draws == 0 ? 0 : 1
    }).transformed, "foo♀")
    XCTAssertEqual(draws, 2)
  }

  func testWeakspotFactorySelectsOneWholeEntryThenEmitsItsTwoComponents() {
    var draws = 0
    let session = TestSessionFactory.make(configuration: .words(2, language: .pokemon1k)
      .with(modifiers: [.weakSpot]), nextRandomWordIndex: { draws += 1; return 0 })
    XCTAssertEqual(session.prompt, "ash cub")
    XCTAssertEqual(draws, 22)
  }

  func testWeakspotGetWordHookKeepsOrdinaryCandidateCaseWhenPunctuationIsOff() {
    var cursor = GeneratedCandidateContinuation(configuration: .words(2, language: .arenaStrategy)
      .with(modifiers: [.weakSpot]), batchTokenCount: 2, sourceWords: ["Node Bay", "Oak"])
    let ranks = [1, 0] + Array(repeating: 1, count: 20)
    var draws = 0
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: {
      defer { draws += 1 }; return ranks[min(draws, ranks.count - 1)]
    }).transformed, "Node Bay")
    XCTAssertEqual(draws, 22)
  }

  func testOriginalPunctuationOffKeepsAnAcceptedExclamationAndCappedPeriodSection() {
    for (candidate, expectedDraws) in [("The hallway breathes!", 3), ("The hallway breathes.", 103)] {
      var cursor = GeneratedCandidateContinuation(configuration: .words(3, language: .typingOfTheDead),
        batchTokenCount: 3, sourceWords: [candidate])
      var draws = 0
      XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: { draws += 1; return 0 }).transformed,
        candidate.lowercased())
      XCTAssertEqual(draws, expectedDraws)
    }
  }

  func testOrdinaryDecorationCapitalizesBeforeNumbersAndDoesNotEraseTheNextComponent() {
    var cursor = GeneratedCandidateContinuation(configuration: .words(2, language: .pokemon1k,
      contentOptions: .init(includePunctuation: true, includeNumbers: true)), batchTokenCount: 2,
      sourceWords: ["node bay", "oak"])
    var units = [0.05, 0, 0, 0.5, 0.95, 0.5]
    var draws = 0
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: { defer { draws += 1 }; return draws == 0 ? 0 : 1 },
      nextRandomContentUnit: { units.removeFirst() }).transformed, "1 bay!")
    XCTAssertEqual(draws, 2)
    XCTAssertTrue(units.isEmpty)
  }

  func testOriginalPunctuationStillAllowsPerWordNumericReplacement() {
    var cursor = GeneratedCandidateContinuation(configuration: .words(2, language: .typingOfTheDead,
      contentOptions: .init(includePunctuation: true, includeNumbers: true)), batchTokenCount: 2,
      sourceWords: ["The hallway breathes!"])
    var units = [0.05, 0, 0, 0.5]
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: { 0 },
      nextRandomContentUnit: { units.removeFirst() }).transformed, "1 hallway")
    XCTAssertTrue(units.isEmpty)
  }

  func testBackwardsOrdersEntryPoolButRetainsSectionOrderAndHiddenTargets() {
    var cursor = GeneratedCandidateContinuation(configuration: .words(2, language: .arenaStrategy)
      .with(modifiers: [.backwards, .noSpaces]), batchTokenCount: 2,
      sourceWords: ["Node Bay", "Oak Elm"])
    let chunk = cursor.nextChunk(nextRandomWordIndex: { 0 })
    XCTAssertEqual(chunk.source, "oak elm")
    XCTAssertEqual(chunk.transformed, "kaomle")
    XCTAssertEqual(chunk.noSpaceTargetWords, ["kao", "mle"])
  }

  func testFourEntryFactoriesCompleteHiddenWordsAndRoundTripActualResults() throws {
    for (language, rank, options) in [(TypingLanguage.typingOfTheDead, 0, ContentOptions(includePunctuation: true)),
      (.pokemon1k, 0, .init()), (.arenaStrategy, 53, .init()), (.tamilOld, 2, .init())] {
      var session = TestSessionFactory.make(configuration: .words(2, language: language, contentOptions: options)
        .with(modifiers: [.noSpaces]), nextRandomWordIndex: { rank })
      XCTAssertFalse(session.prompt.contains(" "), language.rawValue)
      session.insertBatch(session.prompt, at: Date(timeIntervalSince1970: 100))
      XCTAssertEqual(session.outcome, .completed, language.rawValue)
      XCTAssertEqual(session.completedWordCount, 2, language.rawValue)
      XCTAssertEqual(session.errors, 0, language.rawValue)
      let result = try XCTUnwrap(session.result())
      XCTAssertEqual(session.wordReviews.map(\.target).joined(), result.prompt)
      XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
      XCTAssertEqual(try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
        settings: .init(), results: [result], presets: [])).results, [result])
      XCTAssertEqual(session.repeatedAttempt().prompt, result.prompt)
    }
  }

  func testFactoryHundredWordOpeningFinishesItsActualTailAndRepeatsCapturedTargets() throws {
    var session = TestSessionFactory.make(configuration: .words(101, language: .pokemon1k)
      .with(modifiers: [.noSpaces]), nextRandomWordIndex: { 0 })
    let opening = session.prompt, start = Date(timeIntervalSince1970: 100)
    session.insertBatch(opening, at: start)
    XCTAssertEqual(session.completedWordCount, 100)
    XCTAssertFalse(session.isFinished)
    let tail = String(session.prompt.dropFirst(opening.count))
    XCTAssertFalse(tail.isEmpty)
    session.insertBatch(tail, at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 101)
    XCTAssertEqual(session.errors, 0)
    let result = try XCTUnwrap(session.result())
    var replay = session.repeatedAttempt()
    XCTAssertEqual(replay.prompt, opening)
    replay.insertBatch(opening, at: start)
    XCTAssertEqual(replay.prompt, result.prompt)
    replay.insertBatch(tail, at: start.addingTimeInterval(1))
    XCTAssertEqual(replay.result()?.targetWordDirectory, result.targetWordDirectory)
    XCTAssertEqual(replay.outcome, .completed)
  }

  func testRepeatedEntryCacheEndsAtAFreshSectionWithoutMutatingOriginalPendingTail() {
    var cursor = GeneratedCandidateContinuation(configuration: .words(0, language: .arenaStrategy),
      batchTokenCount: 1, sourceWords: ["Node Bay Elm", "Oak"])
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: { 0 }).transformed, "node")
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: { 1 }).transformed, " bay")
    var replay = cursor.replayingContinuation()
    XCTAssertEqual(replay.nextChunk(nextRandomWordIndex: { XCTFail("Unexpected replay draw"); return 0 }).transformed, " bay")
    XCTAssertEqual(replay.nextChunk(nextRandomWordIndex: { 1 }).transformed, " oak")
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: { 1 }).transformed, " elm")
  }

  func testEntryContentAPIsReturnSourceWordsWithoutASecondBackwardsTransformation() {
    for language in [TypingLanguage.typingOfTheDead, .pokemon1k, .arenaStrategy, .tamilOld] {
      let expected = Set(OrdinaryEntryContent.pool(for: language)!.flatMap {
        $0.components(separatedBy: " ").map { $0.lowercased() }
      })
      let source = OrdinaryEntryContent.prompt(wordCount: 25, language: language,
        contentOptions: .init(), modifiers: [.backwards])
      XCTAssertEqual(source.components(separatedBy: " ").count, 25)
      XCTAssertTrue(source.components(separatedBy: " ").allSatisfy { expected.contains($0) })
    }
  }
}
