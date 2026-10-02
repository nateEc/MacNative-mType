import Foundation
import SwiftData
import XCTest
@testable import Typebar

final class BritishQuoteSourceTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 871_000_000)
  private func quote(_ alternate: String?, base: String = "  ab   cd…  ",
    language: TypingLanguage = .english) -> OfflineQuote {
    .init(id: "owned-british-source", title: "Owned draft", text: base, britishText: alternate,
      language: language, length: .short)
  }
  private func configuration(_ variant: EnglishVariant = .british,
    modifiers: [TestModifier] = [], language: TypingLanguage = .english) -> TestConfiguration {
    .init(mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
      language: language, englishVariant: variant, modifiers: modifiers)
  }
  private func attempt(_ alternate: String?, base: String = "  ab   cd…  ",
    variant: EnglishVariant = .british, modifiers: [TestModifier] = []) -> TypingSession {
    TestSessionFactory.make(configuration: configuration(variant, modifiers: modifiers),
      quote: quote(alternate, base: base))
  }

  func testBritishVariantUsesTheAuthoredAlternateRatherThanTheBase() {
    XCTAssertEqual(attempt("ac ef").prompt, "ac ef")
  }

  func testAmericanVariantAndAbsentOrEmptyAlternateKeepOrdinaryPreparation() {
    XCTAssertEqual(attempt("ac ef", variant: .american).prompt, "ab cd...")
    for alternate in [nil, ""] {
      XCTAssertEqual(attempt(alternate).prompt, "ab cd...")
    }
  }

  func testLiteralAlternateEllipsisIsNotExpandedAndCanComplete() {
    var session = attempt("ac… ef")
    XCTAssertEqual(Array(session.prompt.unicodeScalars), Array("ac… ef".unicodeScalars))
    session.insertBatch("ac… ef", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
    XCTAssertEqual(session.wordReviews.map(\.target), ["ac…", "ef"])
  }

  func testAlternateBoundaryUnicodeAndInteriorTabsAreNotTrimmedOrCanonicalized() {
    let source = "\u{FEFF}\te\u{301}\u{A0} ac\u{2028}ef\u{2029}\t"
    XCTAssertEqual(Array(attempt(source).prompt.unicodeScalars), Array(source.unicodeScalars))
  }

  func testRawCRLFAndNewlineWordsDoNotReceiveOrdinaryQuotePreparation() {
    for source in ["ac\r\n ef…", "ac\r ef…", "ac\n ef…"] {
      let expected = source.replacingOccurrences(of: " ef", with: source.contains("\r ef") ? " ef" : "ef")
      XCTAssertEqual(Array(attempt(source).prompt.unicodeScalars), Array(expected.unicodeScalars))
    }
  }

  func testAuthoredAlternateIsNotSubjectToAnotherSpellingOrQuoteMarkReplacement() {
    XCTAssertEqual(attempt("color-center \"ac\"").prompt, "color-center \"ac\"")
  }

  func testAlternateSelectionIsIndependentOfQuoteLanguageMetadata() {
    let session = TestSessionFactory.make(configuration: configuration(language: .spanish),
      quote: quote("ac ef", language: .spanish))
    XCTAssertEqual(session.prompt, "ac ef")
  }

  func testSelectedEmptyASCIICandidatesFailInsteadOfSilentlyCleaningOrUsingBase() {
    for source in [" ", " ac", "ac ", "ac  ef"] {
      var session = attempt(source)
      XCTAssertEqual(session.prompt, "", source)
      XCTAssertTrue(session.isFinished, source)
      XCTAssertNotNil(session.generationNotice, source)
      session.insertBatch("ab cd...", at: start)
      XCTAssertFalse(session.hasStarted)
      XCTAssertEqual(session.typed, "")
      XCTAssertNil(session.result(at: start.addingTimeInterval(1)))
      XCTAssertTrue(session.repeatedAttempt().isFinished)
    }
  }

  func testInvalidAlternateIsNotValidatedWhenAmericanVariantUsesTheBase() {
    var session = attempt("ac  ef", variant: .american)
    session.insertBatch("ab cd...", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
    XCTAssertNil(session.generationNotice)
  }

  func testBackwardsAndUnderscoreUseTheSelectedPoolBeforeWordAlteration() {
    var session = attempt("ac ef gh", modifiers: [.backwards, .titleCase, .underscoreSeparators])
    XCTAssertEqual(session.prompt, "Hg_Fe_Ca")
    session.insertBatch("Hg_Fe_Ca", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 3)
    XCTAssertEqual(session.wordReviews.map(\.target), ["Hg_", "Fe_", "Ca"])
    XCTAssertEqual(session.errors, 0)
  }

  func testMorseKeepsAnEmptyTransformedWordFromTheSelectedAlternate() {
    var session = attempt("e 中 t", modifiers: [.morseStream])
    XCTAssertEqual(session.prompt, "./-/")
    session.insertBatch("./--", at: start)
    XCTAssertEqual(session.completedWordCount, 1)
    XCTAssertEqual(session.outcome, .active)
    XCTAssertEqual(session.wordReviews.map(\.target), ["./", ""])
  }

  func testRepeatAndPortableResultKeepTheSelectedPromptAndOriginalIdentity() throws {
    let source = quote("ac… ef")
    var session = TestSessionFactory.make(configuration: configuration(), quote: source)
    session.insertBatch("ac… ef", at: start)
    let metadata = try XCTUnwrap(ResultQuoteSource.make(mode: .quote, sourceIsCommunity: false, title: source.title))
    let result = try XCTUnwrap(session.result(quoteSource: metadata))
    XCTAssertEqual(result.prompt, "ac… ef")
    XCTAssertEqual(result.configuration.englishVariant, .british)
    XCTAssertEqual(result.quoteSource, metadata)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 0), "ac… ef")
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [], at: start)).results, [result])
    var repeated = session.repeatedAttempt()
    repeated.insertBatch("ac… ef", at: start.addingTimeInterval(1))
    XCTAssertEqual(repeated.outcome, .completed)
    XCTAssertEqual(source.text, "  ab   cd…  ")
    XCTAssertEqual(source.britishText, "ac… ef")
    XCTAssertEqual(QuoteResultFeedbackTarget.make(mode: .quote, sourceIsCommunity: false,
      selectedQuoteID: source.id), .builtIn(quoteID: source.id))
  }

  func testSearchLengthFavoriteAndQueueRemainBasedOnOriginalQuoteIdentity() {
    let source = quote("ac ef", base: "seed")
    XCTAssertEqual(QuoteSearch.filtered([source], query: "seed").map(\.id), [source.id])
    XCTAssertTrue(QuoteSearch.filtered([source], query: "ac").isEmpty)
    XCTAssertEqual(QuoteSelection.filtered([source], mode: .favorites, lengths: [.short],
      searchQuery: "", isFavorite: { $0 == source.id }), [source])
    var queue = QuoteQueue()
    XCTAssertEqual(queue.next(from: [source], avoiding: nil), source.id)
    XCTAssertEqual(source.length, .short)
  }

  func testPreparedExternalSourceAndCustomTextDoNotSelectAQuoteAlternate() {
    XCTAssertEqual(TestSessionFactory.make(configuration: configuration(), quote: quote("ac ef"),
      streamPrompt: "external…").prompt, "external…")
    let custom = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), englishVariant: .british, customTextPipeDelimiter: false)
    XCTAssertEqual(TestSessionFactory.make(configuration: custom, customText: "seed…", quote: quote("ac ef")).prompt, "seed…")
  }

  func testOwnedCatalogExposesAPairedQuoteWithoutChangingItsSelectionIdentity() throws {
    let source = try XCTUnwrap(OfflineContent.quotes(for: .english).first { $0.id == "colour-study" })
    XCTAssertNotNil(source.britishText)
    XCTAssertNotEqual(source.britishText, source.text)
    let american = TestSessionFactory.make(configuration: configuration(.american), quote: source)
    var british = TestSessionFactory.make(configuration: configuration(), quote: source)
    XCTAssertEqual(american.prompt, source.text)
    XCTAssertEqual(british.prompt, source.britishText)
    british.insertBatch(try XCTUnwrap(source.britishText), at: start)
    XCTAssertEqual(british.outcome, .completed)
    XCTAssertEqual(british.errors, 0)
    XCTAssertEqual(QuoteSelection.filtered([source], mode: .lengths, lengths: [.short],
      searchQuery: "", isFavorite: { _ in false }), [source])
  }

  @MainActor func testNewAlternateResultAndOldBritishResultCoexistInMemoryAndArchive() throws {
    let source = "  old   \r\n source…  "
    let old = CompletedTestResult(id: UUID(), configuration: configuration(), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(1), typedCharacterCount: source.count,
      correctCharacterCount: source.count, errorCount: 0, wpm: 60, rawWpm: 60, accuracy: 100,
      prompt: source)
    var session = attempt("ac… ef")
    session.insertBatch("ac… ef", at: start)
    let new = try XCTUnwrap(session.result())
    let container = try ModelContainer(for: TestResultRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    container.mainContext.insert(TestResultRecord(result: old))
    container.mainContext.insert(TestResultRecord(result: new))
    try container.mainContext.save()
    let results = try container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).compactMap(\.portableResult)
    XCTAssertEqual(Set(results.map(\.id)), [old.id, new.id])
    XCTAssertEqual(try XCTUnwrap(results.first { $0.id == old.id }), old)
    XCTAssertEqual(try XCTUnwrap(results.first { $0.id == new.id }), new)
    var settings = AppSettingsSnapshot()
    settings.englishVariant = .british
    let restored = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: settings, results: [old, new], presets: [], at: start))
    XCTAssertEqual(restored.results, [old, new])
    XCTAssertEqual(restored.settings.englishVariant, .british)
    XCTAssertEqual(Array(try XCTUnwrap(restored.results.first).prompt.unicodeScalars), Array(source.unicodeScalars))
  }

  func testWhitespaceOnlyNonASCIICandidateIsNotMisclassifiedAsMissingAlternate() {
    var session = attempt("\t")
    XCTAssertEqual(session.prompt, "\t")
    XCTAssertNil(session.generationNotice)
    session.insert("\t", at: start)
    XCTAssertEqual(session.outcome, .completed)
  }
}
