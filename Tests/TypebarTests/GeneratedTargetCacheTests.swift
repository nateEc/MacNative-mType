import XCTest
@testable import Typebar

final class GeneratedTargetCacheTests: XCTestCase {
  private func cursor(_ configuration: TestConfiguration = .words(0)) -> GeneratedWordContinuation {
    .init(configuration: configuration, weakSpotScores: .init(), batchWordCount: 2,
      previousSource: "amber harbor")
  }

  func testOrdinaryRepeatReturnsCapturedSourceAndTargetsWithoutCallingItsGenerator() {
    var current = cursor(.words(0).with(modifiers: [.randomCase]))
    let opening = current
    var bit = false
    let captured = current.nextChunk(generator: { "node bay" }, nextRandomCaseBit: {
      bit.toggle(); return bit
    })
    var replay = current.replayingContinuation(after: opening)
    let restored = replay.nextChunk(generator: { XCTFail("Cached source must not regenerate"); return "oak elm" },
      nextRandomCaseBit: { XCTFail("Cached targets must not transform again"); return false })
    XCTAssertEqual(restored.source, captured.source)
    XCTAssertEqual(restored.transformed, captured.transformed)
  }

  func testNoSpaceCachedTargetsAndBoundariesSurviveChangedCaseDraws() {
    var current = cursor(.words(0).with(modifiers: [.randomCase, .underscoreSeparators]))
    let opening = current
    let captured = current.nextChunk(generator: { "node bay" }, nextRandomCaseBit: { true })
    var replay = current.replayingContinuation(after: opening)
    let restored = replay.nextChunk(generator: { "oak elm" }, nextRandomCaseBit: { false })
    XCTAssertEqual(restored.transformed, captured.transformed)
    XCTAssertEqual(restored.noSpaceTargetWords, captured.noSpaceTargetWords)
    XCTAssertEqual(restored.noSpaceWordLengths, captured.noSpaceWordLengths)
  }

  func testRepeatSkipsThePrimedBatchAlreadyPresentInTheInitialPrompt() {
    var current = cursor()
    _ = current.nextChunk(generator: { "node bay" })
    let primedOpening = current
    let future = current.nextChunk(generator: { "oak elm" })
    var replay = current.replayingContinuation(after: primedOpening)
    XCTAssertEqual(replay.nextChunk(generator: { "cairn drift" }).transformed, future.transformed)
    XCTAssertEqual(replay.nextChunk(generator: { "cedar grove" }).transformed, "cedar grove")
  }

  func testFiniteRepeatRestoresItsExactTailThenCannotGenerateExtraWords() {
    var current = cursor(.words(5))
    let opening = current
    let first = current.nextChunk(generator: { "node bay" })
    let tail = current.nextChunk(generator: { "oak" })
    var replay = current.replayingContinuation(after: opening)
    XCTAssertEqual(replay.nextChunk(generator: { "elm drift" }).transformed, first.transformed)
    XCTAssertEqual(replay.nextChunk(generator: { "cairn" }).transformed, tail.transformed)
    XCTAssertEqual(replay.nextChunk(generator: { XCTFail("Finite cache is complete"); return "wrong" }).transformed, "")
  }

  func testPartialSecondRepeatKeepsTheEntireOriginalFutureAndCanGrowItsOwnCache() {
    var current = cursor()
    let opening = current
    let first = current.nextChunk(generator: { "node bay" })
    let second = current.nextChunk(generator: { "oak elm" })
    var replay = current.replayingContinuation(after: opening)
    XCTAssertEqual(replay.nextChunk(generator: { "cairn drift" }).transformed, first.transformed)
    var nested = replay.replayingContinuation(after: opening)
    XCTAssertEqual(nested.nextChunk(generator: { "wrong one" }).transformed, first.transformed)
    XCTAssertEqual(nested.nextChunk(generator: { "wrong two" }).transformed, second.transformed)
    let grown = nested.nextChunk(generator: { "cedar grove" })
    var third = nested.replayingContinuation(after: opening)
    _ = third.nextChunk(generator: { "wrong one" })
    _ = third.nextChunk(generator: { "wrong two" })
    XCTAssertEqual(third.nextChunk(generator: { "wrong three" }).transformed, grown.transformed)
    XCTAssertEqual(current.nextChunk(generator: { "cairn drift" }).transformed, "cairn drift")
  }

  func testGeneratedStreamRepeatKeepsRandomizedActualTargetsButStillAdvancesNewIndices() throws {
    let configuration = TestConfiguration.words(0).with(modifiers: [.gibberishStream, .randomCase, .noSpaces])
    var current = GeneratedStreamContinuation(configuration: configuration, batchWordCount: 2, nextTokenIndex: 100)
    let opening = current
    let first = try XCTUnwrap(current.nextChunk(nextRandomCaseBit: { true }))
    var replay = current.replayingContinuation(after: opening)
    let restored = try XCTUnwrap(replay.nextChunk(nextRandomCaseBit: {
      XCTFail("Cached stream targets must not transform again"); return false
    }))
    XCTAssertEqual(restored.source, first.source)
    XCTAssertEqual(restored.transformed, first.transformed)
    XCTAssertEqual(restored.noSpaceTargetWords, first.noSpaceTargetWords)
    let future = try XCTUnwrap(replay.nextChunk(nextRandomCaseBit: { false }))
    XCTAssertEqual(future.source, TypebarStreamContent.prompt(configuration: configuration, wordCount: 2, startIndex: 102))
    XCTAssertEqual(replay.nextTokenIndex, 104)
    XCTAssertEqual(current.nextTokenIndex, 102)
  }

  func testNestedOrdinaryOpeningCheckpointDoesNotExpandToItsEntireReplayCache() {
    var current = cursor()
    _ = current.nextChunk(generator: { "node bay" })
    let opening = current
    let first = current.nextChunk(generator: { "oak elm" })
    let second = current.nextChunk(generator: { "cairn drift" })
    var replay = current.replayingContinuation(after: opening)
    let repeatedOpening = replay
    _ = replay.nextChunk(generator: { "wrong one" })
    var nested = replay.replayingContinuation(after: repeatedOpening)
    XCTAssertEqual(nested.nextChunk(generator: { "wrong two" }).transformed, first.transformed)
    XCTAssertEqual(nested.nextChunk(generator: { "wrong three" }).transformed, second.transformed)
  }

  func testNestedSessionRepeatKeepsOpeningAndEveryAlreadyPrefetchedStreamSuffix() {
    let configuration = TestConfiguration.words(0).with(modifiers: [.gibberishStream, .uppercase, .noSpaces])
    let start = Date(timeIntervalSince1970: 100)
    var session = TestSessionFactory.make(configuration: configuration)
    let opening = session.prompt
    session.insertBatch(opening, at: start)
    let first = String(session.prompt.dropFirst(opening.count))
    session.insertBatch(first, at: start.addingTimeInterval(1))
    let full = session.prompt
    var replay = session.repeatedAttempt()
    XCTAssertEqual(replay.prompt, opening)
    replay.insertBatch(opening, at: start.addingTimeInterval(2))
    XCTAssertEqual(replay.prompt, opening + first)
    var nested = replay.repeatedAttempt()
    XCTAssertEqual(nested.prompt, opening)
    nested.insertBatch(opening, at: start.addingTimeInterval(3))
    XCTAssertEqual(nested.prompt, opening + first)
    nested.insertBatch(first, at: start.addingTimeInterval(4))
    XCTAssertEqual(nested.prompt, full)
    XCTAssertEqual(nested.errors, 0)
    XCTAssertEqual(nested.completedWordCount, 200)
  }

  func testOrdinaryWeakspotCacheIgnoresNewScoresUntilItsCapturedFutureEnds() throws {
    var baseline = WeakSpotScores()
    baseline.record(character: "m", interval: 1, isCorrect: true)
    var learned = WeakSpotScores()
    learned.record(character: "h", interval: 5, isCorrect: true)
    let lexicon = TypingLanguage.english.ownedPracticeLexicon()
    let amber = try XCTUnwrap(lexicon.firstIndex(of: "amber"))
    let harbor = try XCTUnwrap(lexicon.firstIndex(of: "harbor"))
    var rank = 0
    let draw = { defer { rank += 1 }; return rank % 2 == 0 ? amber : harbor }
    var current = GeneratedWordContinuation(configuration: .words(0).with(modifiers: [.weakSpot]),
      weakSpotScores: baseline, batchWordCount: 1, previousSource: "quiet")
    let opening = current
    XCTAssertEqual(current.nextChunk(nextRandomWordIndex: draw).transformed, "amber")
    var replay = current.replayingContinuation(after: opening)
    XCTAssertEqual(replay.nextChunk(weakSpotScores: learned,
      nextRandomWordIndex: { XCTFail("Cached Weakspot word must not draw"); return 0 }).transformed, "amber")
    XCTAssertEqual(replay.nextChunk(weakSpotScores: learned, nextRandomWordIndex: draw).transformed, "harbor")
  }

  func testOrdinaryFiniteTailCompletesAndRepeatsActualResultWithoutAnExtraCursor() throws {
    let configuration = TestConfiguration.words(3)
    let start = Date(timeIntervalSince1970: 100)
    var session = TypingSession(configuration: configuration, prompt: "am oak",
      generatedWordContinuation: .init(configuration: configuration, weakSpotScores: .init(),
        batchWordCount: 1, previousSource: "am oak"))
    session.insertBatch("am oak ", at: start)
    let tail = String(session.prompt.dropFirst(7))
    XCTAssertFalse(tail.isEmpty)
    XCTAssertFalse(session.usesIncrementalPromptExtension)
    XCTAssertTrue(session.shouldFinishWithComposition(tail, at: start.addingTimeInterval(1)))
    session.insertBatch(tail, at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .completed)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [])).results, [result])
    var replay = session.repeatedAttempt()
    replay.insertBatch("am oak ", at: start.addingTimeInterval(2))
    XCTAssertEqual(replay.prompt, result.prompt)
    XCTAssertFalse(replay.usesIncrementalPromptExtension)
    replay.insertBatch(tail, at: start.addingTimeInterval(3))
    XCTAssertEqual(replay.outcome, .completed)
    XCTAssertEqual(replay.errors, 0)
  }
}
