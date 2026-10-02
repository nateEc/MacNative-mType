import XCTest
@testable import Typebar

final class GeneratedUnderscoreBoundTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

  private func binary(_ index: Int) -> String {
    let value = String(index % 256, radix: 2)
    return String(repeating: "0", count: 8 - value.count) + value
  }

  private func binaryTarget(_ range: Range<Int>, omittedIndex: Int? = 99) -> String {
    range.map { binary($0) + ($0 == omittedIndex ? "" : "_") }.joined()
  }

  func testFiniteWordTargetUsesTheReferenceBoundRatherThanTheNativeBatchEnd() throws {
    var session = TestSessionFactory.make(configuration:
      .words(101).with(modifiers: [.binaryStream, .underscoreSeparators]))
    let target = binaryTarget(0..<101)
    XCTAssertEqual(session.prompt, target)
    session.insertBatch(String(target.dropLast()), at: start)
    XCTAssertFalse(session.isFinished, "第 101 词的下划线也是实际目标")
    session.insertBatch("_", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 101)
    XCTAssertEqual(session.errors, 0)
    XCTAssertEqual(session.wordReviews.last?.target, binary(100) + "_")
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 1), target)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
  }

  func testTimedOpeningOmitsOnlyGlobalWordNinetyNine() {
    let config = TestConfiguration.timed(seconds: 120)
      .with(modifiers: [.binaryStream, .underscoreSeparators])
    let session = TestSessionFactory.make(configuration: config)
    XCTAssertEqual(session.prompt, binaryTarget(0..<GeneratedPromptChunkPolicy.wordCount(for: config)))
  }

  func testInfinitePrimingDoesNotResetTheBoundForTheSecondBatch() {
    var session = TestSessionFactory.make(configuration:
      .words(0).with(modifiers: [.binaryStream, .underscoreSeparators]))
    let opening = binaryTarget(0..<200)
    XCTAssertEqual(session.prompt, opening)
    session.insertBatch(opening, at: start)
    XCTAssertFalse(session.isFinished)
    XCTAssertEqual(session.completedWordCount, 200)
    XCTAssertEqual(session.prompt, binaryTarget(0..<300))
    XCTAssertEqual(session.repeatedAttempt().prompt, opening)
    XCTAssertEqual(session.errors, 0)
  }

  func testLargeFiniteStreamFinishesOnlyAfterTheRealFinalSuffix() {
    var session = TestSessionFactory.make(configuration:
      .words(501).with(modifiers: [.binaryStream, .underscoreSeparators]))
    XCTAssertEqual(session.prompt, binaryTarget(0..<500))
    session.insertBatch(binaryTarget(0..<500), at: start)
    XCTAssertEqual(session.completedWordCount, 500)
    XCTAssertFalse(session.isFinished)
    XCTAssertEqual(session.prompt, binaryTarget(0..<501), "有限续批不得生成预算以外的目标")
    session.insertBatch(binary(500), at: start.addingTimeInterval(1))
    XCTAssertFalse(session.isFinished)
    session.insertBatch("_", at: start.addingTimeInterval(2))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 501)
    XCTAssertEqual(session.errors, 0)
  }

  func testFreshWordContinuationKeepsItsGlobalIndexAcrossCalls() {
    var cursor = GeneratedWordContinuation(configuration:
      .words(0).with(modifiers: [.underscoreSeparators]), weakSpotScores: .init(),
      batchWordCount: 3, previousSource: "oak elm")
    let first = cursor.nextChunk { "red green blue" }
    XCTAssertEqual(first.transformed, "red_green_blue_")
    XCTAssertEqual(first.noSpaceTargetWords, ["red_", "green_", "blue_"])
    let second = cursor.nextChunk { "sun moon star" }
    XCTAssertEqual(second.transformed, "sun_moon_star_")
    XCTAssertEqual(second.noSpaceTargetWords, ["sun_", "moon_", "star_"])
  }

  func testCodeContinuationDoesNotCreateATargetForItsLeadingCommitSpace() {
    let plain = TestConfiguration.words(101, language: .codeSwift)
    var baseline = GeneratedCodeContinuation(configuration: plain, batchTokenCount: 100, nextUnitIndex: 0)
    var cursor = GeneratedCodeContinuation(configuration: plain.with(modifiers: [.underscoreSeparators]),
      batchTokenCount: 100, nextUnitIndex: 0)
    let firstWords = baseline.nextChunk().source.split(whereSeparator: \.isWhitespace).map(String.init)
    let first = cursor.nextChunk()
    XCTAssertEqual(first.noSpaceTargetWords, firstWords.enumerated().map {
      $0.element + ($0.offset == 99 ? "" : "_")
    })
    let finalWords = baseline.nextChunk().source.split(whereSeparator: \.isWhitespace).map(String.init)
    let final = cursor.nextChunk()
    XCTAssertEqual(final.transformed, finalWords.map { $0 + "_" }.joined())
    XCTAssertEqual(final.noSpaceTargetWords, finalWords.map { $0 + "_" })
  }

  func testSequentialCustomContinuationKeepsEveryNewSuffix() {
    let config = TestConfiguration(mode: .custom, duration: 120, wordLimit: nil,
      difficulty: .normal, rules: .init(), customTextCompletion: .time,
      customTextOrdering: .inOrder, modifiers: [.underscoreSeparators])
    var session = TestSessionFactory.make(configuration: config, customText: "a b")
    let opening = String(repeating: "a_b_", count: 49) + "a_b"
    XCTAssertEqual(session.prompt, opening)
    session.insertBatch(opening, at: start)
    XCTAssertEqual(session.prompt, opening + String(repeating: "a_b_", count: 50))
    session.insertBatch(String(repeating: "a_b_", count: 50), at: start.addingTimeInterval(1))
    XCTAssertEqual(session.completedWordCount, 200)
    XCTAssertEqual(session.wordReviews.count, 200)
    XCTAssertEqual(session.errors, 0)
    XCTAssertFalse(session.isFinished)
  }

  func testRandomCustomContinuationKeepsItsLastSuffix() {
    let config = TestConfiguration(mode: .custom, duration: 120, wordLimit: nil,
      difficulty: .normal, rules: .init(), customTextCompletion: .time,
      customTextOrdering: .random, modifiers: [.underscoreSeparators])
    var session = TestSessionFactory.make(configuration: config, customText: "a b c")
    let opening = session.prompt
    XCTAssertEqual(opening.filter { $0 == "_" }.count, 99)
    session.insertBatch(opening, at: start)
    XCTAssertTrue(session.prompt.hasSuffix("_"))
    XCTAssertEqual(session.prompt.filter { $0 == "_" }.count, 199)
    XCTAssertEqual(session.completedWordCount, 100)
    XCTAssertFalse(session.isFinished)
  }

  func testVisibilityAndUnderscoreRemainAnExplicitlyRejectedCombination() {
    for modifier in [TestModifier.focusCurrentWord, .focusNextWord, .focusTwoWords, .focusThreeWords] {
      XCTAssertFalse(TestModifierPolicy.isSourceCompatible([.underscoreSeparators, modifier]))
      XCTAssertNil(InteractiveFunboxSelectionPolicy.updatedModifiers(toggling: modifier,
        current: [.underscoreSeparators]))
      let config = TestConfiguration.words(101)
        .with(modifiers: [.binaryStream, .underscoreSeparators, modifier])
      XCTAssertTrue(config.modifiers.contains(.underscoreSeparators))
      XCTAssertFalse(config.modifiers.contains(modifier))
      let session = TestSessionFactory.make(configuration: config)
      XCTAssertEqual(session.prompt, binaryTarget(0..<101))
    }
  }

  func testFreshFiniteWordContinuationConsumesOnlyTheRemainingBudget() {
    var cursor = GeneratedWordContinuation(configuration:
      .words(101).with(modifiers: [.underscoreSeparators]), weakSpotScores: .init(),
      batchWordCount: 100, previousSource: Array(repeating: "oak", count: 100).joined(separator: " "))
    let last = cursor.nextChunk()
    XCTAssertEqual(last.noSpaceTargetWords.count, 1)
    XCTAssertTrue(last.transformed.hasSuffix("_"))
    var extraDraws = 0
    XCTAssertTrue(cursor.nextChunk(generator: { extraDraws += 1; return "extra" }).transformed.isEmpty)
    XCTAssertEqual(extraDraws, 0, "耗尽后不能采样或改变重复状态")
  }

  func testOrdinaryTimedWordSourceSharesGlobalTargetsAndHistory() {
    let config = TestConfiguration.timed(seconds: 120).with(modifiers: [.underscoreSeparators])
    var session = TestSessionFactory.make(configuration: config)
    let count = GeneratedPromptChunkPolicy.wordCount(for: config)
    let opening = session.prompt
    XCTAssertEqual(opening.filter { $0 == "_" }.count, count - 1)
    XCTAssertTrue(opening.hasSuffix("_"))
    session.insertBatch(opening, at: start)
    XCTAssertEqual(session.completedWordCount, count)
    XCTAssertEqual(session.wordReviews.count, count)
    XCTAssertFalse(session.wordReviews[99].target.hasSuffix("_"))
    XCTAssertTrue(session.wordReviews.enumerated().allSatisfy {
      $0.offset == 99 || $0.element.target.hasSuffix("_")
    })
    XCTAssertEqual(session.prompt.filter { $0 == "_" }.count, count * 2 - 1)
    XCTAssertTrue(session.prompt.hasSuffix("_"))
    XCTAssertEqual(session.errors, 0)
  }

  func testEveryNativeCodeLanguageFinishesAtTheOneWordContinuation() {
    for language in TypingLanguage.allCases.filter(\.isCodeLanguage) {
      let config = TestConfiguration.words(101, language: language)
      var source = GeneratedCodeContinuation(configuration: config, batchTokenCount: 100, nextUnitIndex: 0)
      let openingWords = source.nextChunk().source.split(whereSeparator: \.isWhitespace).map(String.init)
      let finalWord = source.nextChunk().source.trimmingCharacters(in: .whitespacesAndNewlines)
      let opening = openingWords.enumerated().map {
        $0.element + ($0.offset == 99 ? "" : "_")
      }.joined()
      var session = TestSessionFactory.make(configuration: config.with(modifiers: [.underscoreSeparators]))
      XCTAssertEqual(session.prompt, opening, language.rawValue)
      session.insertBatch(opening, at: start)
      XCTAssertEqual(session.completedWordCount, 100, language.rawValue)
      XCTAssertFalse(session.isFinished, language.rawValue)
      XCTAssertEqual(session.prompt, opening + finalWord + "_", language.rawValue)
      session.insertBatch(finalWord, at: start.addingTimeInterval(1))
      XCTAssertFalse(session.isFinished, language.rawValue)
      session.insertBatch("_", at: start.addingTimeInterval(2))
      XCTAssertEqual(session.outcome, .completed, language.rawValue)
      XCTAssertEqual(session.completedWordCount, 101, language.rawValue)
      XCTAssertEqual(session.wordReviews.count, 101, language.rawValue)
      XCTAssertEqual(session.errors, 0, language.rawValue)
    }
  }

  func testShortAndBoundaryWordBudgetsKeepTheirActualFinalTarget() {
    for limit in [1, 2, 99, 100, 101] {
      var session = TestSessionFactory.make(configuration:
        .words(limit).with(modifiers: [.binaryStream, .underscoreSeparators]))
      let target = binaryTarget(0..<limit, omittedIndex: min(limit, 100) - 1)
      XCTAssertEqual(session.prompt, target)
      session.insertBatch(target, at: start)
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.completedWordCount, limit)
      XCTAssertEqual(session.errors, 0)
    }
  }

  func testFiniteStreamCursorStopsWithoutProducingAnExtraBatch() throws {
    var cursor = GeneratedStreamContinuation(configuration:
      .words(501).with(modifiers: [.binaryStream, .underscoreSeparators]),
      batchWordCount: 500, nextTokenIndex: 500)
    let chunk = try XCTUnwrap(cursor.nextChunk())
    XCTAssertEqual(chunk.source, binary(500))
    XCTAssertEqual(chunk.transformed, binary(500) + "_")
    XCTAssertEqual(chunk.noSpaceTargetWords, [binary(500) + "_"])
    XCTAssertEqual(cursor.nextTokenIndex, 501)
    XCTAssertNil(cursor.nextChunk())
    XCTAssertEqual(cursor.nextTokenIndex, 501)
  }

  func testQuoteUsesItsWordBoundInsteadOfTheWholeRenderedStringLength() {
    let source = (0..<101).map { "w\($0)" }.joined(separator: " ")
    let target = (0..<101).map { "w\($0)" + ($0 == 99 ? "" : "_") }.joined()
    let quote = OfflineQuote(id: "authored-bound-probe", title: "Probe", text: source,
      language: .english, length: .long)
    let config = TestConfiguration(mode: .quote, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), modifiers: [.underscoreSeparators])
    var session = TestSessionFactory.make(configuration: config, quote: quote)
    XCTAssertEqual(session.prompt, (0..<100).map { "w\($0)" + ($0 == 99 ? "" : "_") }.joined())
    session.insertBatch(target, at: start)
    XCTAssertEqual(session.prompt, target)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 101)
    XCTAssertEqual(session.errors, 0)
  }

  func testFiniteCustomTextKeepsItsHundredWordAlterationBound() {
    let source = (0..<101).map { "w\($0)" }.joined(separator: " ")
    let target = (0..<101).map { "w\($0)" + ($0 == 99 ? "" : "_") }.joined()
    let config = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), customTextPipeDelimiter: false,
      modifiers: [.underscoreSeparators])
    var session = TestSessionFactory.make(configuration: config, customText: source)
    let opening = (0..<100).map { "w\($0)" + ($0 == 99 ? "" : "_") }.joined()
    XCTAssertEqual(session.prompt, opening)
    session.insertBatch(opening, at: start)
    XCTAssertEqual(session.prompt, target)
    XCTAssertFalse(session.isFinished)
    XCTAssertEqual(session.completedWordCount, 100)
    session.insertBatch("w100_", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 101)
    XCTAssertEqual(session.errors, 0)
  }

  func testLongFiniteCustomTextKeepsGlobalTargetsAcrossTheCharacterChunk() throws {
    let source = Array(repeating: "note", count: 2_800).joined(separator: " ")
    let config = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), customTextPipeDelimiter: false,
      modifiers: [.underscoreSeparators])
    var session = TestSessionFactory.make(configuration: config, customText: "note", finiteTextSource: source)
    let opening = session.prompt
    XCTAssertEqual(opening.filter { $0 == "_" }.count + 1, 2_000)
    XCTAssertTrue(opening.hasSuffix("_"))
    session.insertBatch(opening, at: start)
    XCTAssertFalse(session.isFinished)
    let target = (0..<2_800).map { "note" + ($0 == 99 ? "" : "_") }.joined()
    XCTAssertEqual(session.prompt, target)
    session.insertBatch(String(target.dropFirst(opening.count)), at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 2_800)
    XCTAssertEqual(session.errors, 0)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 1), target)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
  }

  func testCachedHiddenProgressRemainsCorrectAfterUnicodeInputAndDeletion() throws {
    var config = TestConfiguration.words(3).with(modifiers: [.noSpaces])
    config.rules.freedomMode = true
    let prompt = "e\u{0301}🙂xy"
    var session = TypingSession(configuration: config, prompt: prompt,
      noSpaceWordEndIndices: [1, 2, 4], noSpaceTargetWords: ["e\u{0301}", "🙂", "xy"])
    session.insertBatch("e\u{0301}🙂", at: start)
    XCTAssertEqual(session.completedWordCount, 2)
    session.deleteBackward(at: start.addingTimeInterval(0.5))
    XCTAssertEqual(session.typed, "e\u{0301}")
    XCTAssertEqual(session.completedWordCount, 1)
    session.insertBatch("🙂x", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.completedWordCount, 2)
    XCTAssertFalse(session.isFinished)
    session.insertBatch("y", at: start.addingTimeInterval(2))
    XCTAssertEqual(session.completedWordCount, 3)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
    XCTAssertEqual(session.wordReviews.map(\.target), ["e\u{0301}", "🙂", "xy"])
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 2), prompt)
    XCTAssertEqual(result.preciseAccuracy, 100)
  }
}
