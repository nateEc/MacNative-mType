import XCTest
@testable import Typebar

final class LanguageWordPoolTests: XCTestCase {
  private func check(_ language: TypingLanguage, _ draws: [Double], _ expected: String,
    word: String = "node", previous: String? = "bay", index: Int = 1, bound: Int = 10,
    options: ContentOptions = .init(includePunctuation: true), file: StaticString = #filePath, line: UInt = #line) {
    var remaining = draws
    let actual = PoolWordDecorationPolicy.decorated(word, previousTarget: previous, language: language,
      wordIndex: index, wordBound: bound, options: options, random: {
        guard !remaining.isEmpty else { XCTFail("Extra draw", file: file, line: line); return 0.5 }
        return remaining.removeFirst()
      })
    XCTAssertEqual(actual, expected, file: file, line: line)
    XCTAssertTrue(remaining.isEmpty, file: file, line: line)
  }

  func testLanguageTerminalFamiliesAndUnrelatedScripts() {
    for language: TypingLanguage in [.hindi, .bangla, .nepali, .nepaliRomanized] {
      check(language, [0, 0.8], "node।")
    }
    for language: TypingLanguage in [.simplifiedChinese, .traditionalChinese, .japaneseHiragana, .japaneseRomaji] {
      check(language, [0, 0.8], "node。")
      check(language, [0, 0.85], "node？")
      check(language, [0, 0.9], "node！")
    }
    for language: TypingLanguage in [.arabic, .persian, .urdu, .kurdishCentral] { check(language, [0, 0.85], "node؟") }
    check(.greek, [0, 0.85], "node;")
    for language: TypingLanguage in [.sanskrit, .pashto, .greeklish, .pinyin] { check(language, [0, 0.85], "node?") }
  }

  func testFrenchAndGreekBranchesReplaceRatherThanAppend() {
    check(.french, [0, 0.85], "?")
    check(.french, [0, 0.9], "!")
    check(.french, Array(repeating: 0.5, count: 4) + [0], ":")
    check(.french, Array(repeating: 0.5, count: 6) + [0], ";")
    check(.greek, Array(repeating: 0.5, count: 6) + [0], ".")
  }

  func testLanguageWrappingAndSeparators() {
    check(.simplifiedChinese, [0.5, 0.5, 0.5, 0], "（node）")
    check(.simplifiedChinese, Array(repeating: 0.5, count: 4) + [0], "node：")
    check(.simplifiedChinese, Array(repeating: 0.5, count: 6) + [0], "node；")
    for (language, mark): (TypingLanguage, String) in [(.arabic, "؛"), (.kurdishCentral, "؛"), (.persian, ";"), (.urdu, ";")] {
      check(language, Array(repeating: 0.5, count: 6) + [0], "node" + mark)
    }
    for (language, mark): (TypingLanguage, String) in [(.arabic, "،"), (.persian, "،"), (.urdu, "،"), (.kurdishCentral, "،"),
      (.simplifiedChinese, "，"), (.japaneseRomaji, "、")] {
      check(language, Array(repeating: 0.5, count: 7) + [0], "node" + mark)
    }
  }

  func testQuoteExclusionsStillConsumeTheirDraws() {
    check(.russian, [0.5, 0, 0, 0], "(node)")
    for language: TypingLanguage in [.ukrainian, .slovak] {
      check(language, [0.5, 0.5, 0, 0], "(node)")
      check(language, [0.5, 0], "\"node\"")
    }
  }

  func testOpeningTurkishAndGeorgianDrawOrder() {
    check(.turkish, [], "İzİ", word: "izI", previous: nil, index: 0)
    check(.georgian, Array(repeating: 0.5, count: 10), "node", previous: nil, index: 0)
    check(.simplifiedChinese, [0, 0.8], "node。", previous: "bay。")
    check(.arabic, [], "Node", previous: "bay؟")
  }

  func testAllOrdinaryFactoryRoutesUseInjectedNumericUnitsAndFamilyGlyphs() {
    let languages = TypingLanguage.allCases.filter(\.supportsQuotes)
    XCTAssertEqual(languages.count, 376)
    for language in languages {
      var units = [0.0, 0, 0]
      let session = TestSessionFactory.make(configuration: .words(1, language: language,
        contentOptions: .init(includeNumbers: true)), nextRandomWordIndex: { 0 }, nextRandomContentUnit: {
          guard !units.isEmpty else { XCTFail("Extra draw: \(language)"); return 0.5 }
          return units.removeFirst()
        })
      let identity = language.rawValue
      let expected = identity.hasPrefix("kurdish") ? "١"
        : identity.hasPrefix("hindi") || identity.hasPrefix("nepali") ? "१"
        : identity.hasPrefix("bangla") ? "১" : "1"
      XCTAssertEqual(session.prompt, expected, identity)
      XCTAssertTrue(units.isEmpty, identity)
    }
  }

  func testOrdinaryCaseExemptionsAndLazyCandidateGate() {
    for language: TypingLanguage in [.german, .swissGerman, .klingon] {
      var cursor = GeneratedCandidateContinuation(configuration: .words(1, language: language),
        batchTokenCount: 1, sourceWords: ["Bay"])
      XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: { 0 }).transformed, "Bay")
    }
    var cursor = GeneratedCandidateContinuation(configuration: .words(0, language: .french)
      .with(modifiers: [.lazyLatin]), batchTokenCount: 1, sourceWords: ["área", "oak"])
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: { 0 }).transformed, "area")
    var ranks = [0, 1]
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: { ranks.removeFirst() }).transformed, " oak")
    XCTAssertTrue(ranks.isEmpty)
  }

  func testSpanishTrackerOpensPersistsAndClosesWithoutAnExtraTerminalDraw() {
    var state = PoolWordDecorationState()
    func decorated(_ word: String, language: TypingLanguage = .spanish, index: Int, previous: String?, draws: [Double]) -> String {
      var units = draws
      let result = PoolWordDecorationPolicy.decorated(word, previousTarget: previous, language: language,
        wordIndex: index, wordBound: 10, options: .init(includePunctuation: true), state: &state, random: {
          guard !units.isEmpty else { XCTFail("Extra draw"); return 0.5 }; return units.removeFirst()
        })
      XCTAssertTrue(units.isEmpty)
      return result
    }
    XCTAssertEqual(decorated("node", index: 0, previous: nil, draws: [0.91]), "¿Node")
    XCTAssertEqual(state.spanishClosing, "?")
    XCTAssertEqual(decorated("bay", language: .french, index: 0, previous: nil, draws: []), "Bay")
    XCTAssertEqual(decorated("oak", index: 0, previous: nil, draws: [0.8]), "Oak")
    XCTAssertEqual(state.spanishClosing, "?")
    XCTAssertEqual(decorated("bay", index: 9, previous: "oak", draws: [0.5]), "bay?")
    XCTAssertNil(state.spanishClosing)
    XCTAssertEqual(decorated("node", index: 9, previous: "bay", draws: [0.5]), "node")
    XCTAssertEqual(decorated("bay", index: 0, previous: nil, draws: [0.9]), "¡Bay")
    XCTAssertEqual(state.spanishClosing, "!")
  }

  func testFiniteOpeningKeepsTrackerWhenCursorIsDiscardedAndOtherModesCarryIt() {
    let first = TestSessionFactory.make(configuration: .words(1, language: .spanish,
      contentOptions: .init(includePunctuation: true)), nextRandomWordIndex: { 0 }, nextRandomContentUnit: { 0.95 })
    XCTAssertEqual(first.liveWordDecorationState.spanishClosing, "?")
    XCTAssertFalse(first.usesIncrementalPromptExtension)
    XCTAssertEqual(first.repeatedAttempt().liveWordDecorationState, first.liveWordDecorationState)
    var zen = TestConfiguration.words(1), quote = TestConfiguration.words(1)
    zen.mode = .zen
    quote.mode = .quote
    for config in [TestConfiguration.words(1, language: .french), zen, quote] {
      let other = TestSessionFactory.make(configuration: config, wordDecorationState: first.liveWordDecorationState)
      XCTAssertEqual(other.liveWordDecorationState, first.liveWordDecorationState)
    }
    let external = TestSessionFactory.make(configuration: .words(1), streamPrompt: "bay",
      wordDecorationState: first.liveWordDecorationState)
    XCTAssertEqual(external.liveWordDecorationState, first.liveWordDecorationState)
    let repeated = first.repeatedAttempt().withWordDecorationState(.init(spanishClosing: "!"))
    XCTAssertEqual(repeated.prompt, first.prompt)
    XCTAssertEqual(repeated.liveWordDecorationState.spanishClosing, "!")
  }

  func testSpanishCachePreservesLatestAppMarkerAndUncachedContinuationUsesIt() {
    let config = TestConfiguration.words(0, language: .spanish, contentOptions: .init(includePunctuation: true))
    var cursor = GeneratedCandidateContinuation(configuration: config, batchTokenCount: 1, sourceWords: ["node", "bay"])
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: { 0 }, nextRandomContentUnit: { 0.95 }).transformed, "¿Node")
    var units = Array(repeating: 0.5, count: 10)
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: { 1 }, nextRandomContentUnit: { units.removeFirst() }).transformed, " bay")
    var replay = cursor.replayingContinuation().withDecorationState(.init(spanishClosing: "!"))
    XCTAssertEqual(replay.nextChunk(nextRandomWordIndex: { XCTFail("Cached rank"); return 0 },
      nextRandomContentUnit: { XCTFail("Cached unit"); return 0 }).transformed, " bay")
    XCTAssertEqual(replay.decorationState.spanishClosing, "!")
    XCTAssertEqual(replay.nextChunk(nextRandomWordIndex: { 0 }, nextRandomContentUnit: { 0 }).transformed, " node!")
    XCTAssertNil(replay.decorationState.spanishClosing)
    let session = TypingSession(configuration: config, prompt: "¿Node ", generatedCodeContinuation: cursor)
      .withWordDecorationState(.init(spanishClosing: "!"))
    XCTAssertEqual(session.repeatedAttempt().liveWordDecorationState.spanishClosing, "!")
  }

  func testNonASCIIGuardsAndSwissPreDecorationConversion() {
    check(.simplifiedChinese, Array(repeating: 0.5, count: 7) + [0], "node，", previous: "bay，")
    check(.arabic, [0, 0.8], "node.", previous: "bay،")
    check(.french, Array(repeating: 0.5, count: 4) + [0, 0.5, 0], ";", previous: "bay:")
    var cursor = GeneratedCandidateContinuation(configuration: .words(1, language: .swissGerman,
      contentOptions: .init(includePunctuation: true)), batchTokenCount: 1, sourceWords: ["ßbay"])
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: { 0 },
      nextRandomContentUnit: { XCTFail("Only capitalize"); return 0 }).transformed, "Ssbay")
  }

  func testNumericOverwriteKeepsAnOpenedSpanishMarker() {
    var state = PoolWordDecorationState(), units = [0.95, 0, 0, 0]
    XCTAssertEqual(PoolWordDecorationPolicy.decorated("node", previousTarget: nil, language: .spanish,
      wordIndex: 0, wordBound: 1, options: .init(includePunctuation: true, includeNumbers: true),
      state: &state, random: { units.removeFirst() }), "1")
    XCTAssertTrue(units.isEmpty)
    XCTAssertEqual(state.spanishClosing, "?")
  }

  func testHindiNoSpaceFiniteTailCompletesArchivesAndRepeatsActualGlyphTargets() throws {
    var session = TestSessionFactory.make(configuration: .words(101, language: .hindi,
      contentOptions: .init(includeNumbers: true)).with(modifiers: [.noSpaces]),
      nextRandomWordIndex: { 0 }, nextRandomContentUnit: { 0 })
    let opening = String(repeating: "१", count: 100), start = Date(timeIntervalSince1970: 100)
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
    XCTAssertEqual(result.targetWordDirectory?.words, Array(repeating: "१", count: 100) + [tail])
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [])).results, [result])
    var replay = session.repeatedAttempt()
    replay.insertBatch(opening, at: start.addingTimeInterval(2))
    XCTAssertEqual(replay.prompt, result.prompt)
    replay.insertBatch(tail, at: start.addingTimeInterval(3))
    XCTAssertEqual(replay.outcome, .completed)
    XCTAssertEqual(replay.result()?.targetWordDirectory, result.targetWordDirectory)
  }
}
