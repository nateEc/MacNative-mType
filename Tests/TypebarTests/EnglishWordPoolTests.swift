import XCTest
@testable import Typebar

final class EnglishWordPoolTests: XCTestCase {
  private func decorated(_ word: String, draws: [Double], expected: String,
    previous: String? = "bay", index: Int = 100, bound: Int = 100,
    options: ContentOptions = .init(includePunctuation: true),
    file: StaticString = #filePath, line: UInt = #line) {
    var remaining = draws
    let actual = PoolWordDecorationPolicy.decorated(word, previousTarget: previous, language: .english,
      wordIndex: index, wordBound: bound, options: options, random: {
        guard !remaining.isEmpty else { XCTFail("Unexpected content draw", file: file, line: line); return 0.5 }
        return remaining.removeFirst()
      })
    XCTAssertEqual(actual, expected, file: file, line: line)
    XCTAssertTrue(remaining.isEmpty, "Unused content draws", file: file, line: line)
  }

  func testEnglishContractionsUseTheFinalBranchDrawThenTheirOwnChoice() {
    decorated("are", draws: Array(repeating: 0.5, count: 9) + [0.49, 0], expected: "aren't")
    decorated("(IT)", draws: Array(repeating: 0.5, count: 9) + [0, 0.99], expected: "(IT'LL)")
    decorated("I", draws: Array(repeating: 0.5, count: 9) + [0, 0], expected: "I'm")
    decorated("are", draws: Array(repeating: 0.5, count: 10), expected: "are")
  }

  func testContractionMatchUsesASCIIWordBoundariesInsteadOfStrippingNumbersOrUnderscores() {
    for word in ["2are", "are2", "_are", "are_", "are bay"] {
      decorated(word, draws: Array(repeating: 0.5, count: 9) + [0], expected: word)
    }
    decorated("éareé", draws: Array(repeating: 0.5, count: 9) + [0, 0], expected: "éaren'té")
  }

  func testNumericReplacementRunsAfterTheEnglishContractionAndConsumesBoth() {
    decorated("are", draws: Array(repeating: 0.5, count: 9) + [0, 0, 0, 0.25, 0.999, 0],
      expected: "90", options: .init(includePunctuation: true, includeNumbers: true))
  }

  func testGlobalFutureWordIsNotReinterpretedAsABatchOpeningOrFiniteEndpoint() {
    decorated("node", draws: Array(repeating: 0.5, count: 10), expected: "node")
    decorated("node", draws: [], expected: "Node", previous: "bay!", index: 100)
    decorated("node", draws: [], expected: "Node", previous: nil, index: 0, bound: 1)
  }

  func testOpeningCapitalizationUsesTheFirstUTF16UnitNotAnAstralLetter() {
    decorated("𐐨bay", draws: [], expected: "𐐨bay", previous: nil, index: 0)
    decorated("ébay", draws: [], expected: "Ébay", previous: nil, index: 0)
  }

  func testAllThirteenEnglishFactoryRoutesConsumeInjectedNumericUnits() {
    let languages: [TypingLanguage] = [.english, .english1k, .english5k, .english10k, .english25k,
      .english450k, .englishCommonlyMisspelled, .englishContractions, .englishDoubleLetter,
      .englishLegal, .englishMedical, .englishShakespearean, .oldEnglish]
    for language in languages {
      var draws = [0.0, 0, 0]
      let session = TestSessionFactory.make(configuration: .words(1, language: language,
        contentOptions: .init(includeNumbers: true)), nextRandomWordIndex: { 0 }, nextRandomContentUnit: {
          guard !draws.isEmpty else { XCTFail("Extra numeric draw: \(language)"); return 0.5 }
          return draws.removeFirst()
        })
      XCTAssertEqual(session.prompt, "1", language.rawValue)
      XCTAssertTrue(draws.isEmpty, language.rawValue)
    }
  }

  func testEnglishFactoryUsesTheActualRankAndSingleWordCapitalization() throws {
    let rank = try XCTUnwrap(TypingLanguage.english.ownedPracticeLexicon().firstIndex(of: "amber"))
    let session = TestSessionFactory.make(configuration: .words(1,
      contentOptions: .init(includePunctuation: true)), nextRandomWordIndex: { rank },
      nextRandomContentUnit: { XCTFail("First word should only capitalize"); return 0 })
    XCTAssertEqual(session.prompt, "Amber")
  }

  func testCursorRetainsAnEnglishCandidateSectionAndDoesNotChooseASecondSectionWord() {
    var cursor = GeneratedCandidateContinuation(configuration: .words(2,
      contentOptions: .init(includePunctuation: true)), batchTokenCount: 2, sourceWords: ["blue bay"])
    var ranks = 0, units = [0.5, 0.8]
    let chunk = cursor.nextChunk(nextRandomWordIndex: { ranks += 1; return 0 },
      nextRandomContentUnit: { units.removeFirst() })
    XCTAssertEqual(chunk.transformed, "Blue bay.")
    XCTAssertEqual(ranks, 2)
    XCTAssertTrue(units.isEmpty)
    XCTAssertFalse(cursor.hasRemaining)
  }

  func testAlteredPreviousEnglishTargetControlsTheNextCapitalizationBranch() {
    let configuration = TestConfiguration.words(0, contentOptions: .init(includePunctuation: true))
      .with(modifiers: [.backwards])
    var cursor = GeneratedCandidateContinuation(configuration: configuration,
      batchTokenCount: 1, sourceWords: ["node", "bay"])
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: { 1 },
      nextRandomContentUnit: { XCTFail("Opening should only capitalize"); return 0 }).transformed, "edoN")
    var units = Array(repeating: 0.5, count: 9) + [0]
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: { 0 },
      nextRandomContentUnit: { units.removeFirst() }).transformed, " yab")
    XCTAssertTrue(units.isEmpty)
  }

  func testEnglishNumericCacheReplaysWithoutRankContentOrCaseDraws() {
    let configuration = TestConfiguration.words(3, contentOptions: .init(includeNumbers: true))
      .with(modifiers: [.noSpaces])
    var cursor = GeneratedCandidateContinuation(configuration: configuration, batchTokenCount: 1,
      sourceWords: ["node", "bay"])
    var chunks: [GeneratedWordChunk] = []
    for digit in [0.0, 0.2, 0.4] {
      var units = [0, 0, digit]
      chunks.append(cursor.nextChunk(nextRandomWordIndex: { 0 }, nextRandomContentUnit: { units.removeFirst() }))
      XCTAssertTrue(units.isEmpty)
    }
    XCTAssertEqual(chunks.map(\.transformed), ["1", "2", "4"])
    var replay = cursor.replayingContinuation()
    for expected in chunks.dropFirst() {
      let restored = replay.nextChunk(nextRandomWordIndex: { XCTFail("Cached rank draw"); return 0 },
        nextRandomCaseBit: { XCTFail("Cached case draw"); return false },
        nextRandomContentUnit: { XCTFail("Cached content draw"); return 0 })
      XCTAssertEqual(restored.transformed, expected.transformed)
      XCTAssertEqual(restored.noSpaceTargetWords, expected.noSpaceTargetWords)
    }
    XCTAssertFalse(replay.hasRemaining)
  }

  func testEnglishWeakspotReadsNewScoresOnlyWhenSelectingAnUncachedWord() {
    var baseline = WeakSpotScores(), learned = WeakSpotScores()
    baseline.record(character: "a", interval: 1, isCorrect: true)
    learned.record(character: "z", interval: 5, isCorrect: true)
    let configuration = TestConfiguration.words(0).with(modifiers: [.weakSpot])
    var cursor = GeneratedCandidateContinuation(configuration: configuration, batchTokenCount: 1,
      weakSpotScores: baseline, sourceWords: ["aa", "zz"])
    func drawPair() -> () -> Int {
      var ranks = [1] + (0..<20).map { $0 % 2 }
      return { ranks.removeFirst() }
    }
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: drawPair()).transformed, "aa")
    XCTAssertEqual(cursor.nextChunk(weakSpotScores: learned,
      nextRandomWordIndex: drawPair()).transformed, " zz")
    var replay = cursor.replayingContinuation()
    XCTAssertEqual(replay.nextChunk(weakSpotScores: baseline,
      nextRandomWordIndex: { XCTFail("Cached word must not sample"); return 0 }).transformed, " zz")
  }

  func testOldEnglishLazyCandidateComparisonRejectsThePreviousNormalizedTarget() {
    var cursor = GeneratedCandidateContinuation(configuration: .words(0, language: .oldEnglish)
      .with(modifiers: [.lazyLatin]), batchTokenCount: 1, sourceWords: ["área", "oak"])
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: { 0 }).transformed, "area")
    var ranks = [0, 1]
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: { ranks.removeFirst() }).transformed, " oak")
    XCTAssertTrue(ranks.isEmpty)
  }

  func testEnglishFactoryFiniteNoSpaceTailStoresAndRepeatsAllActualTargets() throws {
    var session = TestSessionFactory.make(configuration: .words(101,
      contentOptions: .init(includeNumbers: true)).with(modifiers: [.noSpaces]),
      nextRandomWordIndex: { 0 }, nextRandomContentUnit: { 0 })
    let opening = String(repeating: "1", count: 100), start = Date(timeIntervalSince1970: 100)
    XCTAssertEqual(session.prompt, opening)
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
    XCTAssertEqual(result.targetWordDirectory?.words, Array(repeating: "1", count: 100) + [tail])
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [])).results, [result])
    var replay = session.repeatedAttempt()
    replay.insertBatch(opening, at: start.addingTimeInterval(2))
    XCTAssertEqual(replay.prompt, result.prompt)
    replay.insertBatch(tail, at: start.addingTimeInterval(3))
    XCTAssertEqual(replay.outcome, .completed)
    XCTAssertEqual(replay.errors, 0)
    XCTAssertEqual(replay.result()?.targetWordDirectory, result.targetWordDirectory)
  }
}
