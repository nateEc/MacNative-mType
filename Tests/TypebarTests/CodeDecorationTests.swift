import XCTest
@testable import Typebar

final class CodeDecorationTests: XCTestCase {
  private func decorate(_ draws: [Double], expected: String, language: TypingLanguage = .codeSwift,
    previous: String? = nil, index: Int = 0, bound: Int = 10, word: String = "node",
    options: ContentOptions = .init(includePunctuation: true),
    file: StaticString = #filePath, line: UInt = #line) {
    var remaining = draws
    let actual = CodeWordDecorationPolicy.decorated(word, previousTarget: previous, language: language,
      wordIndex: index, wordBound: bound, options: options, random: {
        guard !remaining.isEmpty else { XCTFail("Unexpected decoration draw", file: file, line: line); return 0.5 }
        return remaining.removeFirst()
      })
    XCTAssertEqual(actual, expected, file: file, line: line)
    XCTAssertTrue(remaining.isEmpty, "Unused decoration draws", file: file, line: line)
  }

  func testForcedTerminalChoicesKeepThePointEightAndPointNineBoundaries() {
    for (unit, mark) in [(0.8, "."), (0.80001, "?"), (0.9, "!")] {
      decorate([0.5, unit], expected: "node" + mark, bound: 1)
    }
  }

  func testCodeRetainsCaseAfterAnExclamationInsteadOfEnteringTheEnglishBranch() {
    decorate(Array(repeating: 0.5, count: 10), expected: "node", previous: "bay!", index: 1)
    decorate(Array(repeating: 0.5, count: 10), expected: "are", word: "are")
  }

  func testQuoteColonDashSemicolonAndCommaBranchesKeepTheirPriority() {
    let cases: [([Double], String)] = [
      ([0.5, 0], "\"node\""), ([0.5, 0.5, 0], "'node'"),
      (Array(repeating: 0.5, count: 4) + [0], "node:"),
      (Array(repeating: 0.5, count: 5) + [0], "-"),
      (Array(repeating: 0.5, count: 6) + [0], "node;"),
      (Array(repeating: 0.5, count: 7) + [0], "node,"),
    ]
    for (draws, expected) in cases { decorate(draws, expected: expected) }
  }

  func testAllBracketPairsAndJavaScriptBackticksUseTheirOwnChoiceCounts() {
    for (unit, pair) in [(0.0, "()"), (0.25, "{}"), (0.5, "[]"), (0.75, "<>")] {
      decorate([0.5, 0.5, 0.5, 0, unit], expected: String(pair.prefix(1)) + "node" + pair.suffix(1))
    }
    for language in [TypingLanguage.codeJavaScript, .codeJavaScript1k, .codeJavaScriptReact] {
      decorate([0.5, 0.5, 0.5, 0, 0.99], expected: "`node`", language: language)
    }
  }

  func testOperatorFamiliesFollowSourcePrefixesIncludingClojureButExcludingCSS() {
    for language in [TypingLanguage.codeC, .codeCPP, .codeCSharp, .codeCUDA, .codeCOBOL,
      .codeClojure, .codeCommonLisp, .codeArduino] {
      decorate(Array(repeating: 0.5, count: 8) + [0, 0.99], expected: "|=", language: language)
    }
    for language in [TypingLanguage.codeCSS, .codeSwift, .codeTypeScript] {
      decorate(Array(repeating: 0.5, count: 8) + [0, 0.99], expected: "/", language: language)
    }
    decorate(Array(repeating: 0.5, count: 8) + [0, 0.99], expected: "`", language: .codeJavaScriptReact)
  }

  func testCommaCanFollowAPeriodButNoneOfTheOtherEarlierBranchesCan() {
    decorate(Array(repeating: 0, count: 8), expected: "node,", previous: "bay.", index: 1)
    decorate(Array(repeating: 0, count: 9) + [0.99], expected: "/", previous: "bay,", index: 1)
  }

  func testPenultimateWordSkipsTheChanceTerminatorWhileGlobalFutureIndexUsesBoundOneHundred() {
    decorate([0.05] + Array(repeating: 0.5, count: 9), expected: "node", index: 8)
    decorate(Array(repeating: 0.5, count: 10), expected: "node", index: 100, bound: 100)
  }

  func testColonGuardsAndSemicolonGuardHaveDifferentExclusions() {
    decorate(Array(repeating: 0.5, count: 4) + [0, 0.5, 0], expected: "node;", previous: "bay:")
    decorate(Array(repeating: 0.5, count: 5) + [0, 0.5, 0], expected: "node,", previous: "-")
  }

  func testStrictProbabilityThresholdsDoNotEnterAnEqualBoundaryBranch() {
    for (position, threshold) in [(0, 0.1), (1, 0.01), (2, 0.011), (3, 0.012),
      (4, 0.013), (5, 0.014), (6, 0.015), (7, 0.2), (8, 0.25)] {
      var draws = Array(repeating: 0.5, count: 10)
      draws[position] = threshold
      decorate(draws, expected: "node")
    }
  }

  func testNumbersReplaceTheWholePunctuatedWordAfterTheTerminalDraws() {
    decorate([0.5, 0.95, 0.05, 0.99, 0, 0.5, 0.9, 0.2], expected: "1592", bound: 1,
      options: .init(includePunctuation: true, includeNumbers: true))
  }

  func testNumberLengthDigitRangesAndThePointOneNonReplacementBoundary() {
    let options = ContentOptions(includeNumbers: true)
    decorate([0.1], expected: "node", options: options)
    decorate([0.09999, 0, 0], expected: "1", options: options)
    decorate([0, 0.25, 0.999, 0], expected: "90", options: options)
    decorate([0, 0.5, 0, 0, 0.999], expected: "109", options: options)
    decorate([0, 0.999, 0.999, 0.999, 0.999, 0.999], expected: "9999", options: options)
  }

  func testNumberLengthAddsTheLowerOffsetBeforeRoundingAtTheNextDownBoundary() {
    decorate([0, Double(0.25).nextDown, 0, 0], expected: "10", options: .init(includeNumbers: true))
  }

  func testLargestValidUnitPreservesTheSourcesRareNumericRangeCarry() {
    decorate([0, Double(1).nextDown, Double(1).nextDown, 0, 0, 0, 0],
      expected: "90000", options: .init(includeNumbers: true))
  }

  func testTabThenNewlineRelocationAndNumericReplacementRemoveInternalControls() {
    decorate([0.5, 0], expected: "node.\t\n", bound: 1, word: "no\tde\n")
    decorate([0.5, 0, 0, 0, 0], expected: "1", bound: 1, word: "no\tde\n",
      options: .init(includePunctuation: true, includeNumbers: true))
    decorate([], expected: "no\tde\n", word: "no\tde\n", options: .init())
  }

  func testDockerfileUsesItsNonCodeCapitalizationAndNeverReceivesCodeOperators() {
    decorate([], expected: "Node", language: .dockerFile, bound: 1)
    decorate(Array(repeating: 0.5, count: 8) + [0, 0.5], expected: "node", language: .dockerFile, index: 1)
    decorate([0.5, 0.5, 0.5, 0], expected: "(node)", language: .dockerFile, index: 1)
  }

  func testFactoryActuallyRoutesContentUnitsIntoNumericReplacement() throws {
    let rank = try XCTUnwrap(CodePracticeContent.polyglotTokens(for: .codeSwift).firstIndex(of: "func"))
    var draws = [0.5, 0.95, 0.05, 0.99, 0.0, 0.5, 0.9, 0.2]
    let session = TestSessionFactory.make(configuration: .words(1, language: .codeSwift,
      contentOptions: .init(includePunctuation: true, includeNumbers: true)), nextRandomWordIndex: { rank },
      nextRandomContentUnit: { draws.removeFirst() })
    XCTAssertEqual(session.prompt, "1592")
    XCTAssertTrue(draws.isEmpty)
  }

  func testEveryCodeEntryRoutesNumbersThroughItsMainFactoryPath() {
    for language in TypingLanguage.allCases.filter(\.isCodeLanguage) {
      var draws = [0.0, 0, 0]
      let session = TestSessionFactory.make(configuration: .words(1, language: language,
        contentOptions: .init(includeNumbers: true)), nextRandomWordIndex: { 0 },
        nextRandomContentUnit: { draws.removeFirst() })
      XCTAssertEqual(session.prompt, "1", language.rawValue)
      XCTAssertTrue(draws.isEmpty, language.rawValue)
    }
  }

  func testDecoratedNoSpaceSessionCompletesStoresItsActualDirectoryAndRepeatsItsCapturedTail() throws {
    let rank = try XCTUnwrap(CodePracticeContent.polyglotTokens(for: .codeSwift).firstIndex(of: "func"))
    let config = TestConfiguration.words(101, language: .codeSwift,
      contentOptions: .init(includePunctuation: true, includeNumbers: true))
      .with(modifiers: [.randomCase, .noSpaces])
    var session = TestSessionFactory.make(configuration: config, nextRandomWordIndex: { rank },
      nextRandomCaseBit: { false }, nextRandomContentUnit: { 0.05 })
    let opening = String(repeating: "1", count: 100)
    XCTAssertEqual(session.prompt, opening)
    let start = Date(timeIntervalSince1970: 100)
    session.insertBatch(opening, at: start)
    let tail = String(session.prompt.dropFirst(opening.count))
    XCTAssertFalse(tail.isEmpty)
    session.insertBatch(tail, at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.targetWordDirectory?.words, Array(repeating: "1", count: 100) + [tail])
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [])).results, [result])
    var replay = session.repeatedAttempt()
    replay.insertBatch(opening, at: start)
    XCTAssertEqual(replay.prompt, opening + tail)
    replay.insertBatch(tail, at: start.addingTimeInterval(1))
    XCTAssertEqual(replay.outcome, .completed)
    XCTAssertEqual(replay.errors, 0)
    XCTAssertEqual(replay.result()?.targetWordDirectory, result.targetWordDirectory)
  }

  func testDecoratedCursorCarriesActualTargetsInsteadOfBatchLocalRawWords() {
    var cursor = GeneratedCodeContinuation(configuration: .words(3, language: .codeSwift,
      contentOptions: .init(includePunctuation: true)), batchTokenCount: 1, sourceWords: ["node", "bay"])
    var draws = [0.01, 0] // Initial period changes the next word's branch gates.
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: { 0 }, nextRandomContentUnit: { draws.removeFirst() }).transformed, "node.")
    draws = Array(repeating: 0, count: 8)
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: { 1 }, nextRandomContentUnit: { draws.removeFirst() }).transformed, " bay,")
    XCTAssertTrue(draws.isEmpty)
  }

  func testCapturedNumericTargetsAndCaseAreNeverRedrawnOnFiniteReplay() {
    let configuration = TestConfiguration.words(3, language: .codeSwift,
      contentOptions: .init(includePunctuation: true, includeNumbers: true))
      .with(modifiers: [.randomCase, .noSpaces])
    var cursor = GeneratedCodeContinuation(configuration: configuration, batchTokenCount: 1, sourceWords: ["node"])
    var chunks: [GeneratedWordChunk] = []
    for digit in [0.0, 0.2, 0.4] {
      var draws = Array(repeating: 0.5, count: 10) + [0.05, 0, digit]
      chunks.append(cursor.nextChunk(nextRandomCaseBit: { false }, nextRandomContentUnit: { draws.removeFirst() }))
      XCTAssertTrue(draws.isEmpty)
    }
    XCTAssertEqual(chunks.map(\.transformed), ["1", "2", "4"])
    XCTAssertEqual(chunks.map(\.noSpaceTargetWords), [["1"], ["2"], ["4"]])
    var replay = cursor.replayingContinuation()
    for expected in chunks.dropFirst() {
      let restored = replay.nextChunk(nextRandomWordIndex: { XCTFail("Unexpected rank draw"); return 0 },
        nextRandomCaseBit: { XCTFail("Unexpected case draw"); return true },
        nextRandomContentUnit: { XCTFail("Unexpected content draw"); return 0 })
      XCTAssertEqual(restored.transformed, expected.transformed)
      XCTAssertEqual(restored.noSpaceWordLengths, expected.noSpaceWordLengths)
      XCTAssertEqual(restored.noSpaceTargetWords, expected.noSpaceTargetWords)
    }
    XCTAssertFalse(replay.hasRemaining)
  }

  func testOneCodeWordWithPunctuationReceivesATerminatorWithoutCapitalization() throws {
    let rank = try XCTUnwrap(CodePracticeContent.polyglotTokens(for: .codeSwift).firstIndex(of: "func"))
    let session = TestSessionFactory.make(configuration: .words(1, language: .codeSwift,
      contentOptions: .init(includePunctuation: true)), nextRandomWordIndex: { rank })
    XCTAssertEqual(String(session.prompt.dropLast()), "func")
    XCTAssertTrue(session.prompt.last.map { ".?!".contains($0) } == true)
  }

  func testEveryCodeSourceAddsTheFiniteOpeningTerminator() {
    for language in TypingLanguage.allCases.filter({ $0.isCodeLanguage && $0 != .dockerFile }) {
      var cursor = GeneratedCodeContinuation(configuration: .words(1, language: language,
        contentOptions: .init(includePunctuation: true)), batchTokenCount: 1, sourceWords: ["node"])
      let chunk = cursor.nextChunk()
      XCTAssertEqual(String(chunk.transformed.dropLast()), "node", language.rawValue)
      XCTAssertTrue(chunk.transformed.last.map { ".?!".contains($0) } == true, language.rawValue)
    }
  }

  func testBackwardsNoSpaceOpeningCapturesTheDecoratedLastWordAsItsActualTarget() {
    let configuration = TestConfiguration.words(101, language: .codeSwift,
      contentOptions: .init(includePunctuation: true)).with(modifiers: [.backwards, .noSpaces])
    var cursor = GeneratedCodeContinuation(configuration: configuration,
      batchTokenCount: 100, sourceWords: ["node", "bay", "elm"])
    let chunk = cursor.nextChunk()
    XCTAssertEqual(chunk.noSpaceTargetWords.count, 100)
    XCTAssertTrue(chunk.noSpaceTargetWords.last?.first.map { ".?!".contains($0) } == true)
    XCTAssertEqual(chunk.transformed, chunk.noSpaceTargetWords.joined())
  }
}
