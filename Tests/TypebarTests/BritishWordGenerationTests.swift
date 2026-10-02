import Foundation
import XCTest
@testable import Typebar

final class BritishWordGenerationTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 872_000_000)

  private func configuration(mode: TestMode = .quote, variant: EnglishVariant = .british,
    language: TypingLanguage = .english, modifiers: [TestModifier] = []) -> TestConfiguration {
    .init(mode: mode, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
      language: language, englishVariant: variant, modifiers: modifiers)
  }

  private func quote(_ text: String, alternate: String? = nil,
    config: TestConfiguration? = nil) -> TypingSession {
    TestSessionFactory.make(configuration: config ?? configuration(),
      quote: .init(id: "owned-spelling-probe", title: "Spelling draft", text: text,
        britishText: alternate, language: .english, length: .short))
  }

  func testOrdinaryQuoteUsesOwnedSpellingRulesWithoutAnAlternate() {
    XCTAssertEqual(quote("color favor labor neighbor center theater catalog organize realize recognize traveler license gray tire").prompt,
      "colour favour labour neighbour centre theatre catalogue organise realise recognise traveller licence grey tyre")
    XCTAssertEqual(quote("color", alternate: "").prompt, "colour")
  }

  func testBritishCaseRestorationUsesTheFirstLetterAndWholeWordCase() {
    XCTAssertEqual(quote("COLOR Color cOlOr CoLoR").prompt, "COLOUR Colour colour Colour")
  }

  func testDoubleQuotesAndPunctuationAreRetainedAroundTheChangedWord() {
    XCTAssertEqual(quote("\"color,\" (Center!) \"seed\"").prompt, "'colour,' (Centre!) 'seed'")
  }

  func testHyphenatedWordsTransformEachComponentWithoutDroppingEmptyComponents() {
    XCTAssertEqual(quote("color-center --COLOR-- color---seed").prompt,
      "colour-centre --COLOUR-- colour---seed")
  }

  func testASCIIWordEdgesTreatAccentedBoundaryScalarsAsPunctuation() {
    XCTAssertEqual(Array(quote("écoloré \u{FEFF}center\u{2028} seed").prompt.unicodeScalars),
      Array("écolouré \u{FEFF}centre\u{2028} seed".unicodeScalars))
  }

  func testInteriorDigitsUnderscoresAndNonWordScalarsPreventWholeWordReplacement() {
    XCTAssertEqual(quote("color7 color_ co_lor colór e\u{301}color color's color/center").prompt,
      "color7 color_ co_lor colór e\u{301}color color's color/center")
  }

  func testUnknownWordsStillConvertDoubleQuotesButDoNotGuessSpelling() {
    XCTAssertEqual(quote("\"seed\" program check dialog").prompt, "'seed' program check dialog")
  }

  func testAmericanVariantDoesNotRunBritishWordRules() {
    XCTAssertEqual(quote("\"color\" center tire", config: configuration(variant: .american)).prompt,
      "\"color\" center tire")
  }

  func testNonemptyAuthoredAlternateBypassesAnotherBritishReplacement() {
    XCTAssertEqual(quote("seed", alternate: "\"color\" tire").prompt, "\"color\" tire")
  }

  func testEnglishLanguageAliasesUseTheRuleAndWordleDoesNot() {
    let english: [TypingLanguage] = [.english, .english1k, .english5k, .english10k,
      .english25k, .english450k, .englishCommonlyMisspelled, .englishContractions,
      .englishDoubleLetter, .englishLegal, .englishMedical, .englishShakespearean, .oldEnglish]
    for language in english {
      XCTAssertEqual(quote("color", config: configuration(language: language)).prompt, "colour", language.rawValue)
    }
    for language in [TypingLanguage.englishFiveLetter, .englishFiveLetter1k, .spanish,
      .german, .pigLatin, .codeJavaScript, .mixedLanguages] {
      XCTAssertEqual(quote("\"color\"", config: configuration(language: language)).prompt,
        "\"color\"", language.rawValue)
    }
  }

  func testQuoteExceptionUsesLowercasedPriorAlteredWordWithExactPunctuationRemoval() {
    XCTAssertEqual(quote("will tire Will, tire WILL! tire").prompt, "will tire Will, tire WILL! tire")
    XCTAssertEqual(quote("'will' tire \"will\" tire").prompt, "'will' tyre 'will' tyre")
    XCTAssertEqual(quote("seed tire").prompt, "seed tyre")
  }

  func testCustomAndWordGenerationDoNotApplyQuoteOnlyPreviousWordExceptions() {
    for mode in [TestMode.custom, .words, .time] {
      let chunk = GeneratedWordChunk(source: "will tire color", configuration: configuration(mode: mode))
      XCTAssertEqual(chunk.transformed, "will tyre colour")
    }
  }

  func testBritishReplacementPrecedesFunboxAndUsesItsPriorOutputAsContext() {
    XCTAssertEqual(quote("will tire", config: configuration(modifiers: [.rot13])).prompt, "jvyy gler")
    XCTAssertEqual(quote("color will tire", config: configuration(modifiers: [.uppercase, .backwards])).prompt,
      "ERYT LLIW RUOLOC")
    XCTAssertEqual(quote("will tire", config: configuration(modifiers: [.uppercase])).prompt, "WILL TIRE")
  }

  func testLazyNormalizationRunsBeforeBritishReplacement() {
    XCTAssertEqual(quote("cólór", config: configuration(modifiers: [.lazyLatin])).prompt, "colour")
  }

  func testNoSpaceTargetsUseActualBritishWordLengthsAndCanComplete() {
    var session = quote("color center", config: configuration(modifiers: [.noSpaces]))
    XCTAssertEqual(session.prompt, "colourcentre")
    session.insertBatch("colourcentre", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.wordReviews.map(\.target), ["colour", "centre"])
    XCTAssertEqual(session.errors, 0)
  }

  func testUnderAndMorseUseTheBritishWordNotTheOriginalWord() {
    var under = quote("color center", config: configuration(modifiers: [.underscoreSeparators]))
    XCTAssertEqual(under.prompt, "colour_centre")
    under.insertBatch("colour_centre", at: start)
    XCTAssertEqual(under.outcome, .completed)
    XCTAssertEqual(under.wordReviews.map(\.target), ["colour_", "centre"])
    let morse = quote("color", config: configuration(modifiers: [.morseStream]))
    XCTAssertEqual(morse.prompt, MorseTextPolicy.transformed("colour"))
  }

  func testPipeAndNonPipeCustomCursorsApplyBritishWordGeneration() {
    for usesPipe in [true, false] {
      var config = configuration(mode: .custom)
      config.customTextCompletion = .finish
      config.customTextPipeDelimiter = usesPipe
      var session = TestSessionFactory.make(configuration: config,
        customText: usesPipe ? "color|center" : "color center")
      XCTAssertEqual(session.prompt, "colour centre")
      session.insertBatch("colour centre", at: start)
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.errors, 0)
    }
  }

  func testCustomCursorKeepsConversionAcrossHundredWordChunks() {
    var config = configuration(mode: .custom)
    config.customTextCompletion = .words
    config.wordLimit = 110
    config.customTextPipeDelimiter = false
    var session = TestSessionFactory.make(configuration: config, customText: "color")
    session.insertBatch(Array(repeating: "colour", count: 100).joined(separator: " ") + " ", at: start)
    XCTAssertTrue(session.prompt.contains("colour"))
    session.insertBatch(Array(repeating: "colour", count: 10).joined(separator: " "), at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 110)
    XCTAssertEqual(session.errors, 0)
  }

  func testExplicitFiniteCustomSourceAlsoUsesWordReplacement() {
    var config = configuration(mode: .custom)
    config.customTextCompletion = .finish
    config.customTextPipeDelimiter = false
    let session = TestSessionFactory.make(configuration: config, customText: "\"color\" center",
      finiteTextSource: "\"color\" center")
    XCTAssertEqual(session.prompt, "'colour' centre")
  }

  func testRepeatedAttemptAndPortableResultKeepTheGeneratedBritishPrompt() throws {
    var session = quote("color center")
    session.insertBatch("colour centre", at: start)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.prompt, "colour centre")
    XCTAssertEqual(result.configuration.englishVariant, .british)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [], at: start)).results, [result])
    var repeated = session.repeatedAttempt()
    repeated.insertBatch("colour centre", at: start.addingTimeInterval(1))
    XCTAssertEqual(repeated.outcome, .completed)
  }

  func testQuoteContextRetainsUnderscoreAndMessagingNewlineAfterAlteration() {
    XCTAssertEqual(quote("will tire", config: configuration(modifiers: [.underscoreSeparators])).prompt,
      "will_tyre")
    XCTAssertEqual(quote("will. tire", config: configuration(modifiers: [.messagingStyle])).prompt,
      "will\ntyre")
  }

  func testEachHyphenComponentReceivesTheSameQuotePreviousWord() {
    XCTAssertEqual(quote("will tire-tire seed tire-tire").prompt, "will tire-tire seed tyre-tyre")
  }

  func testExternalSourceDoesNotInheritAnIgnoredQuotesAlternateBypass() {
    let source = OfflineQuote(id: "ignored-source", title: "Ignored", text: "seed",
      britishText: "alternate", language: .english, length: .short)
    XCTAssertEqual(TestSessionFactory.make(configuration: configuration(), quote: source,
      streamPrompt: "color center").prompt, "colour centre")
    var session = TestSessionFactory.make(configuration: configuration(modifiers: [.noSpaces]),
      streamPrompt: "colorcenter", streamNoSpaceBoundarySource: "color center")
    XCTAssertEqual(session.prompt, "colourcentre")
    session.insertBatch("colourcentre", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.wordReviews.map(\.target), ["colour", "centre"])
  }

  func testSequentialCustomSourceKeepsTheRuleAcrossItsOwnContinuation() {
    var config = configuration(mode: .custom)
    config.customTextCompletion = .words
    config.wordLimit = 110
    config.customTextPipeDelimiter = false
    var session = TestSessionFactory.make(configuration: config, customText: "color", finiteTextSource: "color")
    session.insertBatch(Array(repeating: "colour", count: 100).joined(separator: " ") + " ", at: start)
    session.insertBatch(Array(repeating: "colour", count: 10).joined(separator: " "), at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 110)
    XCTAssertEqual(session.errors, 0)
  }

  func testFiniteLongSourceKeepsConversionAcrossRawCursorChunks() {
    let source = String(repeating: "color ", count: 2200) + "center"
    let first = LongSavedTextProgress.nextChunk(in: source, after: 0)
    var config = configuration(mode: .custom)
    config.customTextCompletion = .finish
    config.customTextPipeDelimiter = false
    var session = TestSessionFactory.make(configuration: config, customText: first, finiteTextSource: source)
    session.insertBatch(first.replacingOccurrences(of: "color", with: "colour"), at: start)
    XCTAssertFalse(session.isFinished)
    let rest = String(source.dropFirst(first.count)).replacingOccurrences(of: "color", with: "colour")
      .replacingOccurrences(of: "center", with: "centre")
    session.insertBatch(rest, at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
    XCTAssertEqual(session.prompt, String(repeating: "colour ", count: 2200) + "centre")
    XCTAssertEqual(source, String(repeating: "color ", count: 2200) + "center")
  }

  func testSavedTextProgressMapsLongerBritishDisplayBackToOriginalSourceSlots() {
    let source = "color center"
    var config = configuration(mode: .custom)
    config.customTextCompletion = .finish
    config.customTextPipeDelimiter = false
    var session = TestSessionFactory.make(configuration: config, customText: source, finiteTextSource: source)
    session.insertBatch("colo", at: start)
    XCTAssertEqual(LongSavedTextProgress.advancedOffset(in: source, from: 0, session: session), 0)
    session.insertBatch("ur", at: start.addingTimeInterval(1))
    XCTAssertEqual(LongSavedTextProgress.advancedOffset(in: source, from: 0, session: session), 6)
    session.insertBatch(" cen", at: start.addingTimeInterval(2))
    XCTAssertEqual(LongSavedTextProgress.advancedOffset(in: source, from: 0, session: session), 6)
    session.bailOut(at: start.addingTimeInterval(3))
    XCTAssertEqual(LongSavedTextProgress.advancedOffset(in: source, from: 0, session: session), 6)
  }

  func testSpellingPickerEligibilityUsesExactEnglishSourceIdentities() {
    let enabled = TypingLanguage.allCases.filter(BritishEnglishPolicy.supportsWordConversion)
    XCTAssertEqual(Set(enabled), [.english, .english1k, .english5k, .english10k,
      .english25k, .english450k, .englishCommonlyMisspelled, .englishContractions,
      .englishDoubleLetter, .englishLegal, .englishMedical, .englishShakespearean, .oldEnglish])
  }

  func testZenNeverCreatesATargetFromBritishSpellingSettings() {
    let session = TestSessionFactory.make(configuration: configuration(mode: .zen), customText: "color")
    XCTAssertEqual(session.prompt, "")
    XCTAssertFalse(session.hasStarted)
  }
}
