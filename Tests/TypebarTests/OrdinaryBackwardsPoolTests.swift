import XCTest
@testable import Typebar

final class OrdinaryBackwardsPoolTests: XCTestCase {
  func testWeakspotUnknownCharactersDoNotDiluteKnownCharacterScores() {
    var scores = WeakSpotScores()
    scores.record(character: "a", interval: 1, isCorrect: true)
    scores.record(character: "b", interval: 0.8, isCorrect: true)
    var draws = 0
    let chosen = WeakSpotWordSelection.word(from: ["aaax", "bb"], scores: scores) {
      defer { draws += 1 }
      return draws == 0 ? 0 : 1
    }
    XCTAssertEqual(chosen, "aaax")
    XCTAssertEqual(draws, 20)
  }

  func testSampledContinuationReversesEachWordNotTheDrawOrder() {
    let config = TestConfiguration.words(6).with(modifiers: [.backwards])
    var cursor = GeneratedWordContinuation(configuration: config, weakSpotScores: .init(),
      batchWordCount: 3, previousSource: "oak elm ash")
    let chunk = cursor.nextChunk(generator: { "ab cd ef" })
    XCTAssertEqual(chunk.source, "ab cd ef")
    XCTAssertEqual(chunk.transformed, "ba dc fe")
    XCTAssertEqual(cursor.previousWords, ["cd", "ef"])
  }

  func testNoSpaceSampledTargetsKeepDrawOrderAndGlobalUnderscorePosition() {
    let config = TestConfiguration.words(103).with(modifiers: [.backwards, .underscoreSeparators])
    var cursor = GeneratedWordContinuation(configuration: config, weakSpotScores: .init(),
      batchWordCount: 3, previousSource: Array(repeating: "old", count: 100).joined(separator: " "))
    let chunk = cursor.nextChunk(generator: { "ab cd ef" })
    XCTAssertEqual(chunk.transformed, "ba_dc_fe_")
    XCTAssertEqual(chunk.noSpaceTargetWords, ["ba_", "dc_", "fe_"])
  }

  func testCrossBatchRepeatGuardExaminesTheFirstDrawNotTheReversedTail() {
    let config = TestConfiguration.words(5).with(modifiers: [.backwards])
    var cursor = GeneratedWordContinuation(configuration: config, weakSpotScores: .init(),
      batchWordCount: 3, previousSource: "oak elm")
    var draws = 0
    let chunk = cursor.nextChunk(generator: {
      draws += 1
      return draws == 1 ? "elm cd ef" : "ab cd ef"
    })
    XCTAssertEqual(draws, 2)
    XCTAssertEqual(chunk.transformed, "ba dc fe")
    XCTAssertEqual(cursor.previousWords, ["cd", "ef"])
  }

  func testOrderedLargeLexiconOnlyReadsRequestedMirroredRanks() {
    var reads: [Int] = []
    let source = IndexedLexicon(count: 450_000) { index in reads.append(index); return "word\(index)" }
    let reverse = IndexedLexicon.ordered(source, reversed: true)
    XCTAssertTrue(reads.isEmpty)
    XCTAssertEqual(reverse.count, 450_000)
    XCTAssertEqual(reverse[0], "word449999")
    XCTAssertEqual(reverse[2], "word449997")
    XCTAssertEqual(reads, [449_999, 449_997])
    let normal = IndexedLexicon.ordered(source, reversed: false)
    XCTAssertEqual(normal[0], "word0")
    XCTAssertEqual(reads, [449_999, 449_997, 0])
  }

  func testOrderedViewSupportsEmptyPoolsAndNonzeroStartSlices() {
    let empty = IndexedLexicon.ordered([String](), reversed: true)
    XCTAssertTrue(empty.isEmpty)
    let slice = ["ignore", "ab", "cd", "ef"][1...]
    XCTAssertEqual(IndexedLexicon.ordered(slice, reversed: false).materialized(), ["ab", "cd", "ef"])
    XCTAssertEqual(IndexedLexicon.ordered(slice, reversed: true).materialized(), ["ef", "cd", "ab"])
  }

  func testDeterministicPoolPipelineMatchesActualSourceRankFixtures() {
    for backwards in [false, true] {
      for zipf in [false, true] {
        let source = IndexedLexicon.ordered(["ab", "cd", "ef"], reversed: backwards)
        // Uniform ranks 0/2/1; for Zipf choose thresholds inside ranks 0/2/1.
        var values = zipf ? [0.0, 0.999, 0.7] : [0.0, 0.999, 0.4]
        let sampled = StarterLexicon.prompt(tokens: 3, lexicon: source, separator: " ",
          punctuation: [], contentOptions: .init(), usesZipfFrequency: zipf) { values.removeFirst() }
        let config = TestConfiguration.words(3).with(modifiers: backwards ? [.backwards] : [])
        let chunk = GeneratedWordChunk(source: sampled, configuration: config, preservesWordOrder: true)
        XCTAssertEqual(chunk.transformed, backwards ? "fe ba dc" : "ab ef cd")
        XCTAssertTrue(values.isEmpty)
      }
    }
  }

  func testOrderedViewRetainsRecentWordRedrawAndBoundedTinyPoolEscape() {
    let pool = IndexedLexicon.ordered(["ab", "cd", "ef"], reversed: true)
    var values = [0.0, 0.0, 0.5]
    XCTAssertEqual(RecentWordSelection.sample(from: pool, previousWords: ["ef"],
      usesZipfFrequency: false, random: { values.removeFirst() }), "cd")
    XCTAssertTrue(values.isEmpty)
    var draws = 0
    XCTAssertEqual(RecentWordSelection.sample(from: IndexedLexicon.ordered(["ab"], reversed: true),
      previousWords: ["ab"], usesZipfFrequency: false, random: { draws += 1; return 0 }), "ab")
    XCTAssertEqual(draws, 101)
  }

  func testWeakspotLearnedZeroIsIncludedAndUnknownZeroIsNotFabricated() {
    var scores = WeakSpotScores()
    scores.record(character: "a", interval: 0, isCorrect: true)
    scores.record(character: "b", interval: 1, isCorrect: true)
    scores.record(character: "c", interval: 0.75, isCorrect: true)
    XCTAssertEqual(scores.knownAverageScore(for: "a"), 0)
    XCTAssertNil(scores.knownAverageScore(for: "x"))
    var draws = 0
    XCTAssertEqual(WeakSpotWordSelection.word(from: ["ab", "c"], scores: scores) {
      defer { draws += 1 }; return draws == 0 ? 0 : 1
    }, "c")
    XCTAssertEqual(draws, 20)
  }

  func testWeakspotScoresSourceScalarsInsideCombiningAndAstralWords() {
    for candidate in ["e\u{301}", "🙂x"] {
      var scores = WeakSpotScores()
      scores.record(character: candidate.first == "🙂" ? "🙂" : "e", interval: 1, isCorrect: true)
      scores.record(character: "b", interval: 0.8, isCorrect: true)
      var draws = 0
      XCTAssertEqual(WeakSpotWordSelection.word(from: [candidate, "bb"], scores: scores) {
        defer { draws += 1 }; return draws == 0 ? 0 : 1
      }, candidate)
      XCTAssertEqual(draws, 20)
    }
  }

  func testWeakspotColdBookKeepsFirstCandidateFromTheOrderedPool() {
    let source = IndexedLexicon.ordered(["ab", "cd", "ef"], reversed: true)
    var draws = 0
    XCTAssertEqual(WeakSpotWordSelection.word(from: source, scores: .init()) {
      defer { draws += 1 }; return draws == 0 ? 0 : 1
    }, "ef")
    XCTAssertEqual(draws, 20)
  }

  func testOrdinaryFiniteContinuationFinishesOnlyAfterItsRealFinalSuffixAndRoundTrips() throws {
    let config = TestConfiguration.words(501).with(modifiers: [.backwards, .underscoreSeparators])
    var session = TestSessionFactory.make(configuration: config)
    let opening = session.prompt, start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    for _ in 0..<10_000 {
      if session.completedWordCount >= 500 || session.isFinished { break }
      let next = try XCTUnwrap(session.nextExpectedCharacter)
      session.insertBatch(String(next), at: start)
    }
    XCTAssertEqual(session.completedWordCount, 500)
    XCTAssertFalse(session.isFinished)
    let final = String(session.prompt.dropFirst(session.typed.count))
    XCTAssertTrue(final.hasSuffix("_"))
    session.insertBatch(String(final.dropLast()), at: start.addingTimeInterval(1))
    XCTAssertFalse(session.isFinished)
    session.insertBatch("_", at: start.addingTimeInterval(2))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
    XCTAssertEqual(session.completedWordCount, 501)
    XCTAssertEqual(session.wordReviews.last?.target, final)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [], at: start)).results, [result])
    XCTAssertEqual(session.repeatedAttempt().prompt, opening)
  }

  func testAllSingleLanguagePoolBranchesKeepAnAvailableBackwardsOpening() {
    for language in TypingLanguage.allCases where !language.isCodeLanguage
      && ![TypingLanguage.mixedLanguages, .mixedEnglishChinese].contains(language) {
      let config = TestConfiguration.words(3, language: language).with(modifiers: [.backwards])
      let session = TestSessionFactory.make(configuration: config)
      XCTAssertFalse(session.prompt.isEmpty, language.rawValue)
      XCTAssertEqual(session.configuration, config, language.rawValue)
      XCTAssertEqual(session.repeatedAttempt().prompt, session.prompt, language.rawValue)
      XCTAssertFalse(session.hasStarted)
    }
  }
}
