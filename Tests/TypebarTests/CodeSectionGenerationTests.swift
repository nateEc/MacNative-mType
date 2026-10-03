import XCTest
@testable import Typebar

final class CodeSectionGenerationTests: XCTestCase {
  private func configuration(_ words: Int, modifiers: [TestModifier] = []) -> TestConfiguration {
    .words(words, language: .codeSwift).with(modifiers: modifiers)
  }

  func testFiniteLimitCountsEmittedWordsNotWholeCandidates() {
    var cursor = GeneratedCodeContinuation(configuration: configuration(2), batchTokenCount: 2,
      sourceWords: ["node bay elm", "oak"])
    var draws = 0
    let chunk = cursor.nextChunk(nextRandomWordIndex: { defer { draws += 1 }; return draws == 0 ? 0 : 1 })
    XCTAssertEqual(chunk.source, "node bay")
    XCTAssertEqual(chunk.transformed, "node bay")
    XCTAssertEqual(draws, 2)
    XCTAssertFalse(cursor.hasRemaining)
  }

  func testSectionOrderCrossesChunksAndConsumesDiscardedBaseDraws() {
    var cursor = GeneratedCodeContinuation(configuration: configuration(4), batchTokenCount: 2,
      sourceWords: ["node bay elm", "oak"])
    var draws = 0
    func draw() -> Int { defer { draws += 1 }; return draws == 0 ? 0 : 1 }
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: draw).transformed, "node bay")
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: draw).transformed, " elm oak")
    XCTAssertEqual(draws, 4)
    XCTAssertFalse(cursor.hasRemaining)
  }

  func testRecentWordGateComparesOnlyFirstComponentAndDigitsGateChecksWholeCandidate() {
    var cursor = GeneratedCodeContinuation(configuration: configuration(2), batchTokenCount: 2,
      sourceWords: ["node", "node bay", "oak"])
    var draws = 0
    let ranks = [0, 1, 2]
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: {
      defer { draws += 1 }; return ranks[min(draws, ranks.count - 1)]
    }).transformed, "node oak")
    XCTAssertEqual(draws, 3)
    var numeric = GeneratedCodeContinuation(configuration: configuration(2), batchTokenCount: 2,
      sourceWords: ["node item2", "oak bay"])
    draws = 0
    let numericRanks = [0, 1, 0]
    XCTAssertEqual(numeric.nextChunk(nextRandomWordIndex: {
      defer { draws += 1 }; return numericRanks[min(draws, numericRanks.count - 1)]
    }).transformed, "oak bay")
    XCTAssertEqual(draws, 3)
  }

  func testASCIISectionNormalizationDoesNotSplitTabOrNonbreakingSpace() {
    for (candidate, expected) in [("node   bay  ", "node bay"),
      ("node\tbay elm", "node\tbay elm"), ("node\u{A0}bay elm", "node\u{A0}bay elm")] {
      var cursor = GeneratedCodeContinuation(configuration: configuration(2, modifiers: [.noSpaces]),
        batchTokenCount: 2, sourceWords: [candidate, "oak"])
      var draws = 0
      let chunk = cursor.nextChunk(nextRandomWordIndex: { defer { draws += 1 }; return draws == 0 ? 0 : 1 })
      let targets = expected.components(separatedBy: " ")
      XCTAssertEqual(chunk.noSpaceTargetWords, targets)
      XCTAssertEqual(chunk.transformed, targets.joined())
      XCTAssertEqual(draws, 2)
    }
  }

  func testWeakspotSelectsWholeSectionOnlyAtItsBoundary() {
    var scores = WeakSpotScores()
    scores.record(character: "a", interval: 1, isCorrect: true)
    scores.record(character: "b", interval: 0.8, isCorrect: true)
    var cursor = GeneratedCodeContinuation(configuration: configuration(2, modifiers: [.weakSpot]),
      batchTokenCount: 2, weakSpotScores: scores, sourceWords: ["aaax bb", "bb"])
    let ranks = [1, 0] + Array(repeating: 1, count: 20)
    var draws = 0
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: {
      defer { draws += 1 }; return ranks[min(draws, ranks.count - 1)]
    }).transformed, "aaax bb")
    XCTAssertEqual(draws, 22)
  }

  func testRepeatCopiesTargetsThenStartsFreshSectionInsteadOfOldPendingTail() {
    var cursor = GeneratedCodeContinuation(configuration: configuration(0, modifiers: [.noSpaces]),
      batchTokenCount: 1, sourceWords: ["node bay elm", "oak"])
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: { 0 }).transformed, "node")
    let captured = cursor.nextChunk(nextRandomWordIndex: { 1 })
    XCTAssertEqual(captured.transformed, "bay")
    var repeatCursor = cursor.replayingContinuation()
    let restored = repeatCursor.nextChunk(nextRandomWordIndex: { XCTFail("Unexpected replay draw"); return 0 })
    XCTAssertEqual(restored.noSpaceTargetWords, captured.noSpaceTargetWords)
    XCTAssertEqual(restored.transformed, captured.transformed)
    XCTAssertEqual(repeatCursor.nextChunk(nextRandomWordIndex: { 1 }).transformed, "oak")
    // Copy-on-write state must not clear the original cursor's pending tail.
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: { 1 }).transformed, "elm")
  }

  func testMainFactoryCanSelectOwnedVimPhraseInsteadOfFlatteningIt() {
    let rank = CodePracticeContent.polyglotTokens(for: .codeVim).count
    var draws = 0
    let session = TestSessionFactory.make(configuration: .words(2, language: .codeVim),
      nextRandomWordIndex: { draws += 1; return rank })
    XCTAssertEqual(session.prompt, ":set number")
    XCTAssertEqual(draws, 2)
  }

  func testOnlyTheNineSourceSectionIdentitiesHaveOwnedMultiwordCandidates() {
    let sectionLanguages: Set<TypingLanguage> = [.codeABAP, .codeHaskell, .codeJavaScript,
      .codeJavaScriptReact, .codeOCaml, .codeOok, .codeRust, .codeTypst, .codeVim]
    for language in TypingLanguage.allCases.filter(\.isCodeLanguage) {
      let candidates = CodePracticeContent.wordCandidates(for: language)
      XCTAssertEqual(candidates.contains { $0.contains(" ") }, sectionLanguages.contains(language), language.rawValue)
      XCTAssertTrue(candidates.allSatisfy { !$0.isEmpty && !$0.hasPrefix(" ") && !$0.hasSuffix(" ")
        && !$0.contains("  ") && !$0.contains("\n") && !$0.contains("\t") }, language.rawValue)
      // The main-pool change must not turn Polyglot words into whole phrases.
      XCTAssertFalse(CodePracticeContent.polyglotTokens(for: language).contains { $0.contains(" ") })
      if language == .codeOok { XCTAssertTrue(candidates.allSatisfy { $0.contains(" ") }) }
    }
  }

  func testFactoryEmitsEachOfTheNineOwnedPhrasesInOrderAtFiniteWordLimit() throws {
    for language in [TypingLanguage.codeABAP, .codeHaskell, .codeJavaScript, .codeJavaScriptReact,
      .codeOCaml, .codeOok, .codeRust, .codeTypst, .codeVim] {
      let pool = CodePracticeContent.wordCandidates(for: language)
      let rank = try XCTUnwrap(pool.firstIndex { $0.contains(" ") })
      var draws = 0, contentDraws = 0
      let session = TestSessionFactory.make(configuration: .words(2, language: language,
        contentOptions: .init(includeNumbers: true)), nextRandomWordIndex: { draws += 1; return rank },
        nextRandomContentUnit: { contentDraws += 1; return 0.5 })
      XCTAssertEqual(session.prompt, pool[rank].components(separatedBy: " ").prefix(2).joined(separator: " "),
        language.rawValue)
      XCTAssertEqual(draws, 2, language.rawValue)
      XCTAssertEqual(contentDraws, 2, language.rawValue)
    }
  }

  func testBackwardsReversesCandidatePoolButNotSectionComponentOrder() {
    var cursor = GeneratedCodeContinuation(configuration: configuration(2, modifiers: [.backwards, .noSpaces]),
      batchTokenCount: 2, sourceWords: ["node bay", "oak elm"])
    var draws = 0
    let chunk = cursor.nextChunk(nextRandomWordIndex: { defer { draws += 1 }; return draws == 0 ? 0 : 1 })
    XCTAssertEqual(chunk.source, "oak elm")
    XCTAssertEqual(chunk.transformed, "kaomle")
    XCTAssertEqual(chunk.noSpaceTargetWords, ["kao", "mle"])
    XCTAssertEqual(draws, 2)
  }

  func testInitialLeadingSpacesHitFirstComponentRetryCapBeforeNormalization() {
    var cursor = GeneratedCodeContinuation(configuration: configuration(2), batchTokenCount: 2,
      sourceWords: ["  node   bay  ", "oak"])
    var draws = 0
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: {
      defer { draws += 1 }; return draws < 101 ? 0 : 1
    }).transformed, "node bay")
    XCTAssertEqual(draws, 102)
  }

  func testHundredWordBoundaryKeepsPendingSectionAndTruncatesAtWordOneHundredOne() {
    var cursor = GeneratedCodeContinuation(configuration: configuration(101), batchTokenCount: 100,
      sourceWords: ["node bay elm", "oak"])
    var draws = 0
    let opening = cursor.nextChunk(nextRandomWordIndex: { draws += 1; return 0 })
    XCTAssertEqual(opening.transformed.components(separatedBy: " ").count, 100)
    XCTAssertTrue(opening.transformed.hasSuffix("elm node"))
    let tail = cursor.nextChunk(nextRandomWordIndex: { draws += 1; return 1 })
    XCTAssertEqual(tail.transformed, " bay")
    XCTAssertEqual(draws, 101)
    XCTAssertFalse(cursor.hasRemaining)
    var repeated = cursor.replayingContinuation()
    XCTAssertEqual(repeated.nextChunk(nextRandomWordIndex: { XCTFail("Unexpected replay draw"); return 1 }).transformed,
      tail.transformed)
    XCTAssertFalse(repeated.hasRemaining)
  }

  func testDecorationRunsPerComponentAndNumericOverrideDoesNotLosePendingSection() {
    var cursor = GeneratedCodeContinuation(configuration: .words(2, language: .codeSwift,
      contentOptions: .init(includeNumbers: true)).with(modifiers: [.noSpaces]),
      batchTokenCount: 1, sourceWords: ["node bay elm", "oak"])
    var units = [0.05, 0, 0]
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: { 0 }, nextRandomContentUnit: { units.removeFirst() }).transformed,
      "1")
    XCTAssertTrue(units.isEmpty)
    let tail = cursor.nextChunk(nextRandomWordIndex: { 1 }, nextRandomContentUnit: { 0.5 })
    XCTAssertEqual(tail.transformed, "bay")
    XCTAssertEqual(tail.noSpaceTargetWords, ["bay"])
  }

  func testNoSpaceVimSectionCompletesAndRoundTripsItsActualTargets() throws {
    let pool = CodePracticeContent.wordCandidates(for: .codeVim)
    let rank = try XCTUnwrap(pool.firstIndex(of: ":set number"))
    var session = TestSessionFactory.make(configuration: .words(2, language: .codeVim)
      .with(modifiers: [.noSpaces]), nextRandomWordIndex: { rank })
    XCTAssertEqual(session.prompt, ":setnumber")
    session.insertBatch(session.prompt, at: Date(timeIntervalSince1970: 100))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
    XCTAssertEqual(session.completedWordCount, 2)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [])).results, [result])
    XCTAssertEqual(session.repeatedAttempt().prompt, result.prompt)
  }
}
