import XCTest
@testable import Typebar

final class PolyglotCandidateTests: XCTestCase {
  private func config(_ count: Int = 0, base: TypingLanguage = .english,
    punctuation: Bool = false, numbers: Bool = false, modifiers: [TestModifier] = []) -> TestConfiguration {
    TestConfiguration.words(count, language: .mixedLanguages, mixedLanguageComponents: [.english, .german],
      polyglotBaseLanguage: base, contentOptions: .init(includePunctuation: punctuation, includeNumbers: numbers))
      .with(modifiers: modifiers)
  }

  private func cursor(_ config: TestConfiguration, _ sources: [(TypingLanguage, [String])], count: Int = 1)
    -> GeneratedCandidateContinuation {
    .init(configuration: config, batchTokenCount: count,
      polyglotSources: sources.map { ($0.0, IndexedLexicon($0.1)) }, nextRandomPoolShuffleIndex: { $0 - 1 })
  }

  func testFactoryUsesPerWordNumericDrawsRatherThanIndexDecoration() {
    var units = [0.0, 0.25, 0.999, 0]
    let session = TestSessionFactory.make(configuration: .words(1, language: .mixedLanguages,
      mixedLanguageComponents: [.hindi, .nepali], contentOptions: .init(includeNumbers: true)),
      nextRandomWordIndex: { 0 }, nextRandomContentUnit: {
        guard !units.isEmpty else { XCTFail("Extra draw"); return 0.5 }; return units.removeFirst()
      })
    XCTAssertEqual(session.prompt, "90")
    XCTAssertTrue(units.isEmpty)
  }

  func testUnionRetainsWholeCandidatesFirstPositionAndLastLanguage() {
    var sizes: [Int] = []
    let pool = NativePolyglotCandidates(sources: [(.english, IndexedLexicon(["Bay", "quiet harbor", "é"])),
      (.german, IndexedLexicon(["Bay", "e\u{301}", "oak"]))], nextShuffleIndex: { sizes.append($0); return $0 - 1 })
    XCTAssertEqual(pool.lexicon.materialized(), ["Bay", "quiet harbor", "é", "e\u{301}", "oak"])
    XCTAssertEqual(sizes, [5, 4, 3, 2])
    XCTAssertEqual(pool.language(for: "Bay"), .german)
    XCTAssertEqual(pool.language(for: "é"), .english)
    XCTAssertEqual(pool.language(for: "e\u{301}"), .german)
    XCTAssertNil(pool.language(for: "quiet"))
  }

  func testPoolShuffleChangesRanksButNotLanguageOwnership() {
    let pool = NativePolyglotCandidates(sources: [(.english, IndexedLexicon(["node", "bay"])),
      (.german, IndexedLexicon(["oak"]))], nextShuffleIndex: { _ in 0 })
    XCTAssertEqual(pool.lexicon.materialized(), ["bay", "oak", "node"])
    XCTAssertEqual(pool.language(for: "oak"), .german)
  }

  func testLastDuplicateOwnerControlsCaseAndWeakspotException() {
    var german = cursor(config(1), [(.english, ["Bay"]), (.german, ["Bay"])])
    var english = cursor(config(1), [(.german, ["Bay"]), (.english, ["Bay"])])
    XCTAssertEqual(german.nextChunk(nextRandomWordIndex: { 0 }).transformed, "Bay")
    XCTAssertEqual(english.nextChunk(nextRandomWordIndex: { 0 }).transformed, "bay")
    var weak = cursor(config(1, modifiers: [.weakSpot]), [(.english, ["Bay"]), (.german, ["oak"])])
    XCTAssertEqual(weak.nextChunk(nextRandomWordIndex: { 0 }).transformed, "Bay")
  }

  func testMixedTwitchCandidateLowercasesOnlyWithPunctuationOff() {
    let sources: [(TypingLanguage, [String])] = [(.twitchEmotes, ["StreakStar"]), (.english, ["bay"])]
    var plain = cursor(config(1), sources)
    var punctuated = cursor(config(1, punctuation: true), sources)
    XCTAssertEqual(plain.nextChunk(nextRandomWordIndex: { 0 }).transformed, "streakstar")
    XCTAssertEqual(punctuated.nextChunk(nextRandomWordIndex: { 0 },
      nextRandomContentUnit: { XCTFail("Opening word must not draw punctuation"); return 0 }).transformed, "StreakStar")
  }

  func testSectionsKeepOrderAndDiscardOneBaseDrawPerEmittedWord() {
    var generator = cursor(config(2, punctuation: true), [(.german, ["Bay Oak"]), (.english, ["node"])], count: 2)
    var ranks = [0, 1], units = [0.5, 0.85]
    XCTAssertEqual(generator.nextChunk(nextRandomWordIndex: { ranks.removeFirst() },
      nextRandomContentUnit: { units.removeFirst() }).transformed, "Bay Oak?")
    XCTAssertTrue(ranks.isEmpty)
    XCTAssertTrue(units.isEmpty)
    XCTAssertFalse(generator.hasRemaining)
  }

  func testDecorationUsesPrimaryLanguageNotCandidateLanguage() {
    var french = cursor(config(2, base: .french, punctuation: true), [(.english, ["node"]), (.german, ["bay"])], count: 2)
    var ranks = [0, 1], units = [0.5, 0.85]
    XCTAssertEqual(french.nextChunk(nextRandomWordIndex: { ranks.removeFirst() },
      nextRandomContentUnit: { units.removeFirst() }).transformed, "Node ?")
    var kurdish = cursor(config(1, base: .kurdishCentral, numbers: true), [(.english, ["node"]), (.german, ["bay"])])
    var digits = [0.0, 0, 0]
    XCTAssertEqual(kurdish.nextChunk(nextRandomWordIndex: { 0 },
      nextRandomContentUnit: { digits.removeFirst() }).transformed, "١")
    var preserved = cursor(config(1, base: .typingOfTheDead, punctuation: true), [(.english, ["node"]), (.german, ["bay"])])
    XCTAssertEqual(preserved.nextChunk(nextRandomWordIndex: { 0 },
      nextRandomContentUnit: { XCTFail("Original punctuation must not draw"); return 0 }).transformed, "node")
  }

  func testLazyUsesExactPostCaseMapAndDoesNotNormalizeMissingSectionComponents() {
    var generator = cursor(config(3, modifiers: [.lazyLatin]), [(.french, ["área", "oak"]), (.english, ["écho bay"])])
    XCTAssertEqual(generator.nextChunk(nextRandomWordIndex: { 0 }).transformed, "area")
    var ranks = [0, 1]
    XCTAssertEqual(generator.nextChunk(nextRandomWordIndex: { ranks.removeFirst() }).transformed, " oak")
    XCTAssertTrue(ranks.isEmpty)
    XCTAssertEqual(generator.nextChunk(nextRandomWordIndex: { 2 }).transformed, " écho")
    var absent = cursor(config(1, modifiers: [.lazyLatin]), [(.french, ["ÁRea"]), (.english, ["oak"])])
    XCTAssertEqual(absent.nextChunk(nextRandomWordIndex: { 0 }).transformed, "área")
  }

  func testPrimaryCodeControlsPunctuationFilterButSelectedWordControlsCase() {
    var english = cursor(config(1), [(.codeSwift, ["node:", "Bay"]), (.german, ["oak"])])
    var ranks = [0, 1]
    XCTAssertEqual(english.nextChunk(nextRandomWordIndex: { ranks.removeFirst() }).transformed, "Bay")
    XCTAssertTrue(ranks.isEmpty)
    var code = cursor(config(1, base: .codeSwift), [(.english, ["Node:"]), (.german, ["oak"])])
    XCTAssertEqual(code.nextChunk(nextRandomWordIndex: { 0 }).transformed, "node:")
  }

  func testBackwardsReversesPrimarySourceButNotTheWholeFreshUnion() {
    var generator = cursor(config(2, modifiers: [.backwards]), [(.english, ["node", "bay"]), (.german, ["oak"])], count: 2)
    var ranks = [0, 1]
    XCTAssertEqual(generator.nextChunk(nextRandomWordIndex: { ranks.removeFirst() }).transformed, "yab edon")
  }

  func testCandidateOptionGatesRetryWholeSectionAndStopAtOneHundred() {
    var generator = cursor(config(1), [(.english, ["blue 2bay", "I", "safe harbor"]), (.german, ["oak"])])
    var ranks = [0, 1, 2]
    XCTAssertEqual(generator.nextChunk(nextRandomWordIndex: { ranks.removeFirst() }).transformed, "safe")
    XCTAssertTrue(ranks.isEmpty)
    var degenerate = cursor(config(1), [(.english, ["I"]), (.german, ["I"])])
    var draws = 0
    XCTAssertEqual(degenerate.nextChunk(nextRandomWordIndex: { draws += 1; return 0 }).transformed, "I")
    XCTAssertEqual(draws, 101)
  }

  func testPrimaryConfigurationRoundTripsAndLegacyMissingFieldStaysAbsent() throws {
    let value = config(2, base: .french)
    XCTAssertEqual(try JSONDecoder().decode(TestConfiguration.self, from: JSONEncoder().encode(value)), value)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    object.removeValue(forKey: "polyglotBaseLanguage")
    let legacy = try JSONDecoder().decode(TestConfiguration.self, from: JSONSerialization.data(withJSONObject: object))
    XCTAssertNil(legacy.polyglotBaseLanguage)
    XCTAssertEqual(legacy.wordPoolBaseLanguage, .english)
    XCTAssertNil(TestConfiguration.words(1).with(polyglotBaseLanguage: .french).polyglotBaseLanguage)
    XCTAssertNil(value.with(polyglotBaseLanguage: .mixedLanguages).polyglotBaseLanguage)
    var session = TestSessionFactory.make(configuration: value)
    session.insertBatch(session.prompt, at: Date(timeIntervalSince1970: 100))
    let result = try XCTUnwrap(session.result())
    var prepared = value
    prepared.polyglotUsesPrimaryDirection = true
    prepared.polyglotUsesPrimaryCodeInput = true
    prepared.polyglotUsesPrimaryInputNormalization = true
    XCTAssertEqual(result.configuration, prepared)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [])).results.first?.configuration, prepared)
  }

  func testCachedPolyglotTargetsDoNotRedrawRankShuffleContentOrCase() {
    var generator = cursor(config(3, numbers: true, modifiers: [.noSpaces]), [(.english, ["node"]), (.german, ["bay"])])
    var expected: [GeneratedWordChunk] = []
    for digit in [0.0, 0.2, 0.4] {
      var units = [0, 0, digit]
      expected.append(generator.nextChunk(nextRandomWordIndex: { 0 }, nextRandomContentUnit: { units.removeFirst() }))
    }
    var replay = generator.replayingContinuation(nextRandomPoolShuffleIndex: { $0 - 1 })
    for chunk in expected.dropFirst() {
      let actual = replay.nextChunk(nextRandomWordIndex: { XCTFail("Cached rank"); return 0 },
        nextRandomCaseBit: { XCTFail("Cached case"); return false }, nextRandomContentUnit: { XCTFail("Cached content"); return 0 })
      XCTAssertEqual(actual.transformed, chunk.transformed)
      XCTAssertEqual(actual.noSpaceTargetWords, chunk.noSpaceTargetWords)
    }
    XCTAssertFalse(replay.hasRemaining)
  }

  func testRepeatReshufflesFuturePoolWithoutChangingItsCachedTarget() {
    var generator = cursor(config(), [(.english, ["node", "bay"]), (.german, ["oak"])])
    XCTAssertEqual(generator.nextChunk(nextRandomWordIndex: { 0 }).transformed, "node")
    XCTAssertEqual(generator.nextChunk(nextRandomWordIndex: { 1 }).transformed, " bay")
    var calls = 0
    var repeatCursor = generator.replayingContinuation(nextRandomPoolShuffleIndex: { _ in calls += 1; return 0 })
    XCTAssertEqual(calls, 2)
    XCTAssertEqual(repeatCursor.nextChunk(nextRandomWordIndex: { XCTFail("Cached rank"); return 0 }).transformed, " bay")
    XCTAssertEqual(repeatCursor.nextChunk(nextRandomWordIndex: { 1 }).transformed, " oak")
  }

  func testPrimaryBritishAndSwissStagesApplyRegardlessOfCandidateOwner() {
    var british = config(1), french = config(1, base: .french)
    british.englishVariant = .british
    french.englishVariant = .british
    let sources: [(TypingLanguage, [String])] = [(.english, ["color"]), (.german, ["oak"])]
    var enabled = cursor(british, sources), disabled = cursor(french, sources)
    XCTAssertEqual(enabled.nextChunk(nextRandomWordIndex: { 0 }).transformed, "colour")
    XCTAssertEqual(disabled.nextChunk(nextRandomWordIndex: { 0 }).transformed, "color")
    var swiss = cursor(config(1, base: .swissGerman, punctuation: true), [(.german, ["ßbay"]), (.english, ["oak"])])
    XCTAssertEqual(swiss.nextChunk(nextRandomWordIndex: { 0 },
      nextRandomContentUnit: { XCTFail("Opening only"); return 0 }).transformed, "Ssbay")
  }

  func testPortableShareCarriesPrimaryWhileLegacyConfigurationDoesNotInventIt() throws {
    let value = config(2, base: .spanish)
    let preset = SavedTestPreset(configuration: value, quoteID: nil, customText: nil)
    XCTAssertEqual(try TestConfigurationShare.preset(from: TestConfigurationShare.link(for: preset)).configuration, value)
    let document = ActiveTestSelectionDocument(preset: preset, testParameterMemory: .defaults)
    XCTAssertEqual(try JSONDecoder().decode(ActiveTestSelectionDocument.self,
      from: JSONEncoder().encode(document)).preset.configuration.polyglotBaseLanguage, .spanish)
    let legacy = TestConfiguration.words(2, language: .mixedLanguages)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
    XCTAssertNil(object["polyglotBaseLanguage"])
    XCTAssertFalse(CurrentPersonalBestPolicy.isConfigurationEligible(value))
  }

  func testFactoryFiniteNoSpaceTailArchivesRepeatsAndKeepsPrimary() throws {
    var configuration = config(101, base: .kurdishCentral, numbers: true, modifiers: [.noSpaces])
    configuration.mixedLanguageComponents = [.english, .kurdishCentral]
    var session = TestSessionFactory.make(configuration: configuration,
      nextRandomWordIndex: { 0 }, nextRandomContentUnit: { 0 }, nextRandomPoolShuffleIndex: { $0 - 1 })
    let opening = String(repeating: "١", count: 100), start = Date(timeIntervalSince1970: 100)
    XCTAssertEqual(session.prompt, opening)
    session.insertBatch(opening, at: start)
    XCTAssertEqual(session.completedWordCount, 100)
    let tail = String(session.prompt.dropFirst(opening.count))
    XCTAssertFalse(tail.isEmpty)
    session.insertBatch(tail, at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 101)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.targetWordDirectory?.words, Array(repeating: "١", count: 100) + [tail])
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [])).results, [result])
    var replay = session.repeatedAttempt()
    XCTAssertEqual(replay.configuration.polyglotBaseLanguage, .kurdishCentral)
    replay.insertBatch(opening, at: start.addingTimeInterval(2))
    XCTAssertEqual(replay.prompt, result.prompt)
    replay.insertBatch(tail, at: start.addingTimeInterval(3))
    XCTAssertEqual(replay.outcome, .completed)
    XCTAssertEqual(replay.result()?.targetWordDirectory, result.targetWordDirectory)
  }
}
