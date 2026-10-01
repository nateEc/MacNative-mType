import XCTest
@testable import Typebar

final class SinglePassWordTargetsTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 100)

  private func configuration(_ modifiers: [TestModifier] = [.noSpaces, .randomCase]) -> TestConfiguration {
    .words(2).with(modifiers: modifiers)
  }

  private func session(_ chunk: GeneratedWordChunk, configuration: TestConfiguration) -> TypingSession {
    .init(configuration: configuration, prompt: chunk.transformed,
      noSpaceWordEndIndices: NoSpaceWordBoundaryPolicy.endIndices(for: chunk.noSpaceWordLengths),
      noSpaceTargetWords: chunk.noSpaceTargetWords)
  }

  func testExpandedTargetsAreSampledOnceAndDriveWordCompletion() {
    let config = configuration()
    var draws = 0
    let chunk = GeneratedWordChunk(source: "ß ß", configuration: config, nextRandomCaseBit: {
      draws += 1
      return draws <= 2
    })
    XCTAssertEqual(chunk.transformed, "SSSS")
    XCTAssertEqual(draws, 2)
    XCTAssertEqual(chunk.noSpaceWordLengths, [2, 2])
    XCTAssertEqual(chunk.noSpaceTargetWords, ["SS", "SS"])
    var attempt = session(chunk, configuration: config)
    attempt.insertBatch("SS", at: start)
    XCTAssertEqual(attempt.completedWordCount, 1)
    attempt.insertBatch("SS", at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.wordReviews.map(\.target), ["SS", "SS"])
    XCTAssertEqual(attempt.errors, 0)
  }

  func testEqualTotalLengthCannotHideWrongPerWordBoundaries() {
    let config = configuration()
    var draws = 0
    let chunk = GeneratedWordChunk(source: "ß ß", configuration: config, nextRandomCaseBit: {
      defer { draws += 1 }
      return draws == 0 || draws == 3
    })
    XCTAssertEqual(chunk.transformed, "SSß")
    XCTAssertEqual(draws, 2)
    XCTAssertEqual(chunk.noSpaceWordLengths, [2, 1])
    XCTAssertEqual(chunk.noSpaceTargetWords, ["SS", "ß"])
    var attempt = session(chunk, configuration: config)
    attempt.insertBatch("S", at: start)
    XCTAssertEqual(attempt.completedWordCount, 0)
    attempt.insertBatch("Sß", at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.wordReviews.map(\.target), ["SS", "ß"])
    XCTAssertEqual(attempt.errors, 0)
  }

  func testUnderscoreOwnsTheSuffixOfTheActuallyRenderedExpandedWord() {
    let config = configuration([.underscoreSeparators, .randomCase])
    var draws = 0
    let chunk = GeneratedWordChunk(source: "ß a", configuration: config, nextRandomCaseBit: {
      defer { draws += 1 }
      return draws == 0
    })
    XCTAssertEqual(chunk.transformed, "SS_a")
    XCTAssertEqual(draws, 2)
    XCTAssertEqual(chunk.noSpaceWordLengths, [3, 1])
    XCTAssertEqual(chunk.noSpaceTargetWords, ["SS_", "a"])
    var attempt = session(chunk, configuration: config)
    attempt.insertBatch("SS_a", at: start)
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.wordReviews.map(\.target), ["SS_", "a"])
    XCTAssertEqual(attempt.errors, 0)
  }

  func testReversalAndRandomCaseKeepTheActualReversedWordTargets() {
    let config = configuration([.noSpaces, .randomCase, .backwards])
    var draws = 0
    let chunk = GeneratedWordChunk(source: "ab ß", configuration: config, nextRandomCaseBit: {
      defer { draws += 1 }
      return draws == 0 || draws == 2
    })
    XCTAssertEqual(chunk.transformed, "SSbA")
    XCTAssertEqual(draws, 3)
    XCTAssertEqual(chunk.noSpaceWordLengths, [2, 2])
    XCTAssertEqual(chunk.noSpaceTargetWords, ["SS", "bA"])
    var attempt = session(chunk, configuration: config)
    attempt.insertBatch("SSbA", at: start)
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.wordReviews.map(\.target), ["SS", "bA"])
    XCTAssertEqual(attempt.errors, 0)
  }

  func testFactoryFiniteTextSharesTargetsWithRepeatReplayAndPortableResult() throws {
    let config = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), modifiers: [.noSpaces, .randomCase])
    var draws = 0
    var attempt = TestSessionFactory.make(configuration: config, customText: "ß ß", nextRandomCaseBit: {
      draws += 1
      return draws <= 2
    })
    var repeated = attempt.repeatedAttempt()
    XCTAssertEqual(attempt.prompt, "SSSS")
    XCTAssertEqual(draws, 2)
    for input in ["SS", "SS"] {
      attempt.insertBatch(input, at: start.addingTimeInterval(1))
      repeated.insertBatch(input, at: start.addingTimeInterval(1))
    }
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(repeated.outcome, .completed)
    XCTAssertEqual(attempt.wordReviews, repeated.wordReviews)
    XCTAssertEqual(attempt.wordReviews.map(\.target), ["SS", "SS"])
    let result = try XCTUnwrap(attempt.result())
    XCTAssertEqual(result.errorCount, 0)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 1), "SSSS")
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
  }

  func testSourceBoundariesAreUsedBeforeTransformingAnExternalNoSpacePrompt() {
    var draws = 0
    var attempt = TestSessionFactory.make(configuration: configuration(), streamPrompt: "ßß",
      streamNoSpaceBoundarySource: "ß ß", nextRandomCaseBit: {
        draws += 1
        return draws <= 2
      })
    XCTAssertEqual(draws, 2)
    XCTAssertEqual(attempt.prompt, "SSSS")
    attempt.insertBatch("S", at: start)
    XCTAssertEqual(attempt.completedWordCount, 0)
    attempt.insertBatch("SSS", at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.wordReviews.map(\.target), ["SS", "SS"])
    XCTAssertEqual(attempt.errors, 0)
  }

  func testNativeCjkSourceBoundariesSurviveWithoutANoSpaceModifier() {
    var attempt = TestSessionFactory.make(configuration: .words(2, language: .simplifiedChinese)
      .with(modifiers: [.randomCase]), streamPrompt: "ßß", streamNoSpaceBoundarySource: "ß ß",
      nextRandomCaseBit: { true })
    XCTAssertEqual(attempt.prompt, "SSSS")
    attempt.insertBatch("SS", at: start)
    XCTAssertEqual(attempt.completedWordCount, 1)
    attempt.insertBatch("SS", at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.wordReviews.map(\.target), ["SS", "SS"])
    XCTAssertEqual(attempt.errors, 0)
  }

  func testGeneratedWordContinuationCarriesOneSampleForEachAcceptedSourceWord() {
    // Two earlier words plus two newly accepted words must fit the budget.
    let config = TestConfiguration.words(4).with(modifiers: [.noSpaces, .randomCase])
    var cursor = GeneratedWordContinuation(configuration: config, weakSpotScores: .init(),
      batchWordCount: 2, previousSource: "old older")
    var draws = 0
    let chunk = cursor.nextChunk(generator: { "ß a" }, nextRandomCaseBit: {
      draws += 1
      return draws == 1
    })
    XCTAssertEqual(draws, 2)
    XCTAssertEqual(chunk.transformed, "SSa")
    XCTAssertEqual(chunk.noSpaceWordLengths, [2, 1])
    XCTAssertEqual(chunk.noSpaceTargetWords, ["SS", "a"])
    XCTAssertEqual(cursor.previousWords, ["ß", "a"])
  }

  func testGeneratedStreamContinuationSamplesScalarsButNotCommitSpaces() throws {
    let config = TestConfiguration.timed(seconds: 120).with(modifiers: [.gibberishStream, .noSpaces, .randomCase])
    var cursor = GeneratedStreamContinuation(configuration: config, batchWordCount: 3, nextTokenIndex: 0)
    var draws = 0
    let chunk = try XCTUnwrap(cursor.nextChunk(nextRandomCaseBit: { draws += 1; return false }))
    let targets = chunk.source.split(separator: " ").map { $0.lowercased() }
    XCTAssertEqual(draws, targets.reduce(0) { $0 + $1.unicodeScalars.count })
    XCTAssertEqual(chunk.transformed, targets.joined())
    XCTAssertEqual(chunk.noSpaceTargetWords, targets)
    XCTAssertEqual(chunk.noSpaceWordLengths, targets.map(\.count))
    XCTAssertEqual(cursor.nextTokenIndex, 3)
  }

  func testEveryCodeFactoryReusesItsInitialChunkInsteadOfTransformingItAgain() {
    for language in TypingLanguage.allCases.filter(\.isCodeLanguage) {
      let plain = TestConfiguration.words(2, language: language)
      var rawCursor = GeneratedCodeContinuation(configuration: plain, batchTokenCount: 2, nextUnitIndex: 0)
      let source = rawCursor.nextChunk().source
      let targets = source.split(separator: " ").map { $0.lowercased() }
      var draws = 0
      var attempt = TestSessionFactory.make(configuration: plain.with(modifiers: [.noSpaces, .randomCase]),
        nextRandomCaseBit: { draws += 1; return false })
      XCTAssertEqual(draws, targets.reduce(0) { $0 + $1.unicodeScalars.count }, language.displayName)
      XCTAssertEqual(attempt.prompt, targets.joined(), language.displayName)
      attempt.insertBatch(targets.joined(), at: start)
      XCTAssertEqual(attempt.outcome, .completed, language.displayName)
      XCTAssertEqual(attempt.wordReviews.map(\.target), targets, language.displayName)
      XCTAssertEqual(attempt.errors, 0, language.displayName)
    }
  }

  func testEveryCodeContinuationKeeps100ThenOneActualTargetWithNoPrefixSample() {
    for language in TypingLanguage.allCases.filter(\.isCodeLanguage) {
      let config = TestConfiguration.words(101, language: language).with(modifiers: [.noSpaces, .randomCase])
      var cursor = GeneratedCodeContinuation(configuration: config, batchTokenCount: 100, nextUnitIndex: 0)
      for count in [100, 1] {
        var draws = 0
        let chunk = cursor.nextChunk(nextRandomCaseBit: { draws += 1; return false })
        let targets = chunk.source.split(separator: " ").map { $0.lowercased() }
        XCTAssertEqual(draws, targets.reduce(0) { $0 + $1.unicodeScalars.count }, language.displayName)
        XCTAssertEqual(chunk.noSpaceTargetWords, targets, language.displayName)
        XCTAssertEqual(chunk.noSpaceWordLengths, targets.map(\.count), language.displayName)
        XCTAssertEqual(chunk.noSpaceTargetWords.count, count, language.displayName)
        XCTAssertEqual(chunk.transformed, targets.joined(), language.displayName)
      }
      XCTAssertFalse(cursor.hasRemaining, language.displayName)
    }
  }

  func testOrdinaryCommitPromptDoesNotCreateNoSpaceMetadataOrSampleTwice() {
    var draws = 0
    let chunk = GeneratedWordChunk(source: "ß a", configuration: .words(2).with(modifiers: [.randomCase]),
      nextRandomCaseBit: { draws += 1; return draws == 1 })
    XCTAssertEqual(draws, 2)
    XCTAssertEqual(chunk.transformed, "SS a")
    XCTAssertTrue(chunk.noSpaceWordLengths.isEmpty)
    XCTAssertTrue(chunk.noSpaceTargetWords.isEmpty)
  }

  func testMessagingFinalCommitTrimmingUpdatesTheCapturedTargetNotANewTransform() {
    let batch = TestModifierPolicy.transformedBatch("Hi! Next.", modifiers: [.noSpaces, .messagingStyle])
    XCTAssertEqual(batch.text, "hi\nnext")
    XCTAssertEqual(batch.noSpaceTargetWords, ["hi\n", "next"])
    XCTAssertEqual(batch.noSpaceWordLengths, [3, 4])
  }

  func testUnmappableGraphemeAndZeroTargetsDoNotInventOffsets() {
    let fused = TestModifierPolicy.transformedBatch("a \u{301}b", modifiers: [.noSpaces])
    XCTAssertEqual(fused.text, "a\u{301}b")
    XCTAssertTrue(fused.noSpaceWordLengths.isEmpty)
    XCTAssertTrue(fused.noSpaceTargetWords.isEmpty)
    let empty = TestModifierPolicy.transformedBatch("中 a", modifiers: [.morseStream])
    XCTAssertEqual(empty.text, ".-/")
    XCTAssertTrue(empty.noSpaceWordLengths.isEmpty)
    XCTAssertTrue(empty.noSpaceTargetWords.isEmpty)
  }

  func testLegacyTextOnlyBoundaryInferenceDoesNotResampleRandomCase() {
    XCTAssertEqual(NoSpaceWordBoundaryPolicy.wordLengths(source: "ß ß",
      modifiers: [.noSpaces, .randomCase], transformedPrompt: "SSß"), [])
  }

  func testRandomCustomInitialBatchSamplesOnlyTheRenderedCandidates() {
    let config = TestConfiguration(mode: .custom, duration: 120, wordLimit: nil,
      difficulty: .normal, rules: .init(), customTextCompletion: .time,
      customTextOrdering: .random, modifiers: [.noSpaces, .randomCase])
    var draws = 0
    var attempt = TestSessionFactory.make(configuration: config, customText: "ß",
      nextRandomCaseBit: { draws += 1; return true })
    XCTAssertEqual(draws, CustomTextOrderPolicy.maximumCompleteRandomWordCount)
    XCTAssertEqual(attempt.prompt, String(repeating: "SS", count: draws))
    attempt.insertBatch(String(repeating: "SS", count: 10), at: start)
    XCTAssertEqual(attempt.completedWordCount, 10)
    XCTAssertEqual(attempt.wordReviews.map(\.target), Array(repeating: "SS", count: 10))
    XCTAssertEqual(attempt.errors, 0)
    XCTAssertFalse(attempt.isFinished)
  }

  func testSequentialCustomInputCrossesThe100WordBoundaryUsingRenderedTargets() {
    let config = TestConfiguration(mode: .custom, duration: nil, wordLimit: 101,
      difficulty: .normal, rules: .init(), customTextCompletion: .words,
      customTextOrdering: .inOrder, modifiers: [.noSpaces, .randomCase])
    var attempt = TestSessionFactory.make(configuration: config, customText: "ß",
      nextRandomCaseBit: { true })
    let initial = attempt.prompt
    XCTAssertEqual(initial, String(repeating: "SS", count: 100))
    attempt.insertBatch(initial, at: start)
    XCTAssertEqual(attempt.completedWordCount, 100)
    XCTAssertFalse(attempt.isFinished)
    let continuation = String(attempt.prompt.dropFirst(initial.count))
    let nextWord = continuation.hasPrefix("SS") ? "SS" : "ß"
    XCTAssertTrue(continuation.hasPrefix(nextWord))
    attempt.insertBatch(nextWord, at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.completedWordCount, 101)
    XCTAssertEqual(attempt.wordReviews.count, 101)
    XCTAssertEqual(attempt.wordReviews.map(\.target).joined(), initial + nextWord)
    XCTAssertEqual(attempt.errors, 0)
  }

  func testRandomCustomInputCrossesItsInitialBatchUsingRenderedTargets() {
    let config = TestConfiguration(mode: .custom, duration: 120, wordLimit: nil,
      difficulty: .normal, rules: .init(), customTextCompletion: .time,
      customTextOrdering: .random, modifiers: [.noSpaces, .randomCase])
    var attempt = TestSessionFactory.make(configuration: config, customText: "ß",
      nextRandomCaseBit: { true })
    let count = CustomTextOrderPolicy.maximumCompleteRandomWordCount
    let initial = attempt.prompt
    XCTAssertEqual(initial, String(repeating: "SS", count: count))
    attempt.insertBatch(initial, at: start)
    XCTAssertEqual(attempt.completedWordCount, count)
    let continuation = String(attempt.prompt.dropFirst(initial.count))
    let nextWord = continuation.hasPrefix("SS") ? "SS" : "ß"
    XCTAssertTrue(continuation.hasPrefix(nextWord))
    attempt.insertBatch(nextWord, at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.completedWordCount, count + 1)
    XCTAssertEqual(attempt.wordReviews.count, count + 1)
    XCTAssertEqual(attempt.wordReviews.map(\.target).joined(), initial + nextWord)
    XCTAssertEqual(attempt.errors, 0)
    XCTAssertFalse(attempt.isFinished)
  }
}
