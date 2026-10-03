import XCTest
@testable import Typebar

final class CodePoolSamplingTests: XCTestCase {
  private func configuration(_ words: Int = 3, modifiers: [TestModifier] = []) -> TestConfiguration {
    TestConfiguration.words(words, language: .codeSwift).with(modifiers: modifiers)
  }

  func testOrderedPoolPipelineKeepsTheDrawOrderAndCrossChunkRecentTargets() {
    var cursor = GeneratedCodeContinuation(configuration: configuration(6, modifiers: [.backwards]),
      batchTokenCount: 3, sourceWords: ["ab", "cd", "ef"])
    var ranks = [0, 2, 1]
    let first = cursor.nextChunk(nextRandomWordIndex: { ranks.removeFirst() })
    XCTAssertEqual(first.source, "ef ab cd")
    XCTAssertEqual(first.transformed, "fe ba dc")
    // The source compares against the altered targets, not the source words.
    ranks = [1, 1, 1]
    let second = cursor.nextChunk(nextRandomWordIndex: { ranks.removeFirst() })
    XCTAssertEqual(second.source, " cd cd cd")
    XCTAssertEqual(second.transformed, " dc dc dc")
    XCTAssertTrue(ranks.isEmpty)
    XCTAssertFalse(cursor.hasRemaining)
  }

  func testCodeKeepsPunctuationAndUppercaseWhileASCIIOnlyDigitsAreFiltered() {
    var cursor = GeneratedCodeContinuation(configuration: configuration(3), batchTokenCount: 3,
      sourceWords: ["foo()", "Foundation", "v2", "v٢"])
    var ranks = [0, 1, 2, 3]
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: { ranks.removeFirst() }).transformed,
      "foo() Foundation v٢")
    XCTAssertTrue(ranks.isEmpty)
  }

  func testCodeRedrawKeepsTheSourceFirstComparisonCaseAsymmetry() {
    var cursor = GeneratedCodeContinuation(configuration: configuration(2), batchTokenCount: 2,
      sourceWords: ["aa", "AA"])
    var ranks = [0, 1, 1]
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: { ranks.removeFirst() }).transformed, "aa AA")
    XCTAssertTrue(ranks.isEmpty)
  }

  func testNumericTinyPoolStopsAfterOneHundredRedrawsAndDoesNotLoopForever() {
    var cursor = GeneratedCodeContinuation(configuration: configuration(1), batchTokenCount: 1,
      sourceWords: ["value2"])
    var draws = 0
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: { draws += 1; return Int.min }).transformed, "value2")
    XCTAssertEqual(draws, 101)
  }

  func testStandaloneIIsRedrawnWithoutChangingOtherCodeUppercase() {
    var cursor = GeneratedCodeContinuation(configuration: configuration(1), batchTokenCount: 1,
      sourceWords: ["I", "Foundation"])
    var ranks = [0, 1]
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: { ranks.removeFirst() }).transformed, "Foundation")
    XCTAssertTrue(ranks.isEmpty)
  }

  func testWeakspotCodeSelectionConsumesBaseDrawThenTwentyLearnedCandidates() {
    var scores = WeakSpotScores()
    scores.record(character: "a", interval: 1, isCorrect: true)
    scores.record(character: "b", interval: 0.8, isCorrect: true)
    var cursor = GeneratedCodeContinuation(configuration: configuration(1, modifiers: [.weakSpot]),
      batchTokenCount: 1, weakSpotScores: scores, sourceWords: ["aaax", "bb"])
    var ranks = [1, 0] + Array(repeating: 1, count: 19)
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: { ranks.removeFirst() }).transformed, "aaax")
    XCTAssertTrue(ranks.isEmpty)
  }

  func testZipfCodePoolUsesTheOwnedRankWeightsAndSupportsReversedPools() {
    for backwards in [false, true] {
      var cursor = GeneratedCodeContinuation(configuration: configuration(1,
        modifiers: [.zipf] + (backwards ? [.backwards] : [])), batchTokenCount: 1,
        sourceWords: ["ab", "cd", "ef"])
      XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: { Int.max }).transformed, backwards ? "ba" : "ef")
    }
  }

  func testFinishedCursorReplaysCapturedRandomTargetsWithoutAnyResampling() {
    let config = configuration(101, modifiers: [.noSpaces, .randomCase])
    var cursor = GeneratedCodeContinuation(configuration: config, batchTokenCount: 100,
      sourceWords: ["ab", "cd", "ef"])
    var rank = 0, bit = false
    func draw() -> Int { defer { rank += 1 }; return rank % 3 }
    func caseBit() -> Bool { bit.toggle(); return bit }
    _ = cursor.nextChunk(nextRandomWordIndex: draw, nextRandomCaseBit: caseBit)
    let tail = cursor.nextChunk(nextRandomWordIndex: draw, nextRandomCaseBit: caseBit)
    XCTAssertFalse(cursor.hasRemaining)
    var replay = cursor.replayingContinuation()
    XCTAssertTrue(replay.hasRemaining)
    var unexpectedDraws = 0
    let copied = replay.nextChunk(nextRandomWordIndex: { unexpectedDraws += 1; return 0 },
      nextRandomCaseBit: { unexpectedDraws += 1; return false })
    XCTAssertEqual(unexpectedDraws, 0)
    XCTAssertEqual(copied.source, tail.source)
    XCTAssertEqual(copied.transformed, tail.transformed)
    XCTAssertEqual(copied.noSpaceTargetWords, tail.noSpaceTargetWords)
    XCTAssertEqual(copied.noSpaceWordLengths, tail.noSpaceWordLengths)
    XCTAssertFalse(replay.hasRemaining)
    XCTAssertEqual(replay.nextChunk().transformed, "")
  }

  func testReplayCanGenerateNewWordsAfterItsCapturedFutureAndRepeatAgain() {
    var cursor = GeneratedCodeContinuation(configuration: configuration(0), batchTokenCount: 1,
      sourceWords: ["ab", "cd", "ef"])
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: { 0 }).transformed, "ab")
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: { 1 }).transformed, " cd")
    var replay = cursor.replayingContinuation()
    XCTAssertEqual(replay.nextChunk(nextRandomWordIndex: { XCTFail("Unexpected replay draw"); return 0 }).transformed, " cd")
    XCTAssertEqual(replay.nextChunk(nextRandomWordIndex: { 2 }).transformed, " ef")
    var repeated = replay.replayingContinuation()
    XCTAssertEqual(repeated.nextChunk().transformed, " cd")
    XCTAssertEqual(repeated.nextChunk().transformed, " ef")
    XCTAssertTrue(repeated.hasRemaining)
  }

  func testLongFiniteCodeCursorReplaysItsEntireCapturedSuffixWithoutExtraWords() {
    var cursor = GeneratedCodeContinuation(configuration: configuration(10_000), batchTokenCount: 100,
      sourceWords: ["ab", "cd", "ef"])
    var rank = 0
    var chunks: [String] = []
    while cursor.hasRemaining {
      chunks.append(cursor.nextChunk(nextRandomWordIndex: { defer { rank += 1 }; return rank % 3 }).transformed)
    }
    XCTAssertEqual(chunks.joined().split(separator: " ").count, 10_000)
    var replay = cursor.replayingContinuation()
    var restored: [String] = []
    while replay.hasRemaining {
      restored.append(replay.nextChunk(nextRandomWordIndex: { XCTFail("Unexpected replay draw"); return 0 }).transformed)
    }
    XCTAssertEqual(restored, Array(chunks.dropFirst()))
  }

  func testLegacyProgramOrderResultStillRoundTripsAsItsFixedPrompt() throws {
    var session = TypingSession(configuration: configuration(3), prompt: "import Foundation func")
    session.insertBatch(session.prompt, at: Date(timeIntervalSince1970: 100))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.prompt, "import Foundation func")
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [])).results, [result])
    XCTAssertEqual(session.repeatedAttempt().prompt, result.prompt)
  }

  func testCodeFactoryConsumesTheSelectedPoolRankInsteadOfProgramOrder() throws {
    let pool = CodePracticeContent.polyglotTokens(for: .codeSwift)
    let rank = try XCTUnwrap(pool.firstIndex(of: "func"))
    var draws = 0
    let session = TestSessionFactory.make(configuration: .words(1, language: .codeSwift),
      nextRandomWordIndex: { draws += 1; return rank })
    XCTAssertEqual(session.prompt, "func")
    XCTAssertEqual(draws, 1)
  }

  func testCodeBackwardsReversesThePoolBeforeRankSelection() throws {
    let pool = CodePracticeContent.polyglotTokens(for: .codeSwift)
    let rank = pool.count - 1 - (try XCTUnwrap(pool.firstIndex(of: "func")))
    let configuration = TestConfiguration.words(1, language: .codeSwift).with(modifiers: [.backwards])
    let session = TestSessionFactory.make(configuration: configuration, nextRandomWordIndex: { rank })
    XCTAssertEqual(session.prompt, "cnuf")
  }

  func testCodePoolRedrawsThePreviousTwoCandidatesWithoutReorderingTheBatch() throws {
    let pool = CodePracticeContent.polyglotTokens(for: .codeSwift)
    let function = try XCTUnwrap(pool.firstIndex(of: "func"))
    let binding = try XCTUnwrap(pool.firstIndex(of: "Foundation"))
    let returning = try XCTUnwrap(pool.firstIndex(of: "import"))
    var ranks = [function, function, binding, binding, returning]
    let session = TestSessionFactory.make(configuration: .words(3, language: .codeSwift),
      nextRandomWordIndex: { ranks.isEmpty ? returning : ranks.removeFirst() })
    XCTAssertEqual(session.prompt, "func Foundation import")
    XCTAssertTrue(ranks.isEmpty)
  }

  func testCodeNumbersOffRejectsASampledNumericIdentifier() throws {
    let pool = CodePracticeContent.polyglotTokens(for: .codeSwift)
    let numeric = try XCTUnwrap(pool.firstIndex { $0.contains("0") })
    let function = try XCTUnwrap(pool.firstIndex(of: "func"))
    var ranks = [numeric, function]
    let session = TestSessionFactory.make(configuration: .words(1, language: .codeSwift),
      nextRandomWordIndex: { ranks.isEmpty ? function : ranks.removeFirst() })
    XCTAssertEqual(session.prompt, "func")
    XCTAssertTrue(ranks.isEmpty)
  }
}
