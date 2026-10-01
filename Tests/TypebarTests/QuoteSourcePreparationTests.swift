import XCTest
@testable import Typebar

final class QuoteSourcePreparationTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
  private func configuration(_ modifiers: [TestModifier] = []) -> TestConfiguration {
    .init(mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal,
      rules: .init(), modifiers: modifiers)
  }
  private func quote(_ text: String) -> OfflineQuote {
    .init(id: "owned-source-probe", title: "Source probe", text: text,
      language: .english, length: .short)
  }

  func testOrdinarySourceCollapsesOnlyASCIISpacesAndExpandsEveryEllipsis() {
    let session = TestSessionFactory.make(configuration: configuration(),
      quote: quote("  ab   cd…  ef……  "))
    XCTAssertEqual(session.prompt, "ab cd... ef......")
  }

  func testCRLFCRAndLFKeepNewlinesAttachedToThePrecedingWord() {
    let source = "  ab   \r\n  cd \r ef  \n  gh  "
    let session = TestSessionFactory.make(configuration: configuration(), quote: quote(source))
    XCTAssertEqual(QuoteSourcePolicy.preparedText(source), "ab\n cd\n ef\n gh")
    XCTAssertEqual(Array(session.prompt.unicodeScalars), Array("ab\ncd\nef\ngh".unicodeScalars))
  }

  func testConsecutiveNewlinesRetainTheirSeparateGeneratedWordSlots() {
    let session = TestSessionFactory.make(configuration: configuration(),
      quote: quote("\r\n ab\r\n \n\r cd\n "))
    XCTAssertEqual(QuoteSourcePolicy.preparedText("\r\n ab\r\n \n\r cd\n "), "ab\n \n \n cd")
    XCTAssertEqual(session.prompt, "ab\n\n\ncd")
  }

  func testBoundaryTrimUsesECMAScriptSetIncludingBOMButNotNELOrZeroWidthSpace() {
    let trimmed: [UInt32] = [9, 10, 11, 12, 13, 32, 0xA0, 0x1680]
      + Array(0x2000...0x200A) + [0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF]
    for value in trimmed {
      let scalar = String(UnicodeScalar(value)!)
      let session = TestSessionFactory.make(configuration: configuration(), quote: quote(scalar + "ab" + scalar))
      XCTAssertEqual(session.prompt, "ab", String(value, radix: 16))
    }
    for value: UInt32 in [0x85, 0x180E, 0x200B] {
      let source = String(UnicodeScalar(value)!) + "ab" + String(UnicodeScalar(value)!)
      XCTAssertEqual(TestSessionFactory.make(configuration: configuration(), quote: quote(source)).prompt, source)
    }
  }

  func testInteriorUnicodeWhitespaceAndDecomposedScalarsRemainUnchanged() {
    let interior = "a\t\t b\u{A0}\u{A0}c\u{2028}d\u{2029}e\u{FEFF}f e\u{301}"
    let session = TestSessionFactory.make(configuration: configuration(), quote: quote("  " + interior + "  "))
    XCTAssertEqual(Array(session.prompt.unicodeScalars), Array(interior.unicodeScalars))
  }

  func testBackwardsPreparesQuotePoolBeforeReversingAndComputingHiddenTargets() throws {
    let source = quote("  ab   cd…  ef  ")
    var session = TestSessionFactory.make(configuration: configuration([.backwards, .titleCase, .underscoreSeparators]),
      quote: source, showAllLines: true)
    let target = "Fe_...dc_Ba"
    XCTAssertEqual(session.prompt, target)
    session.insertBatch(target, at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 3)
    XCTAssertEqual(session.wordReviews.map(\.target), ["Fe_", "...dc_", "Ba"])
    XCTAssertEqual(session.errors, 0)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 0), target)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from:
      TypebarDataTransfer.exportArchive(settings: .init(), results: [result], presets: [], at: start)).results, [result])
    XCTAssertEqual(source.text, "  ab   cd…  ef  ")
  }

  func testNormalizedNewlineQuoteCanBeTypedAndRepeatedWithoutRenormalizingItsSnapshot() throws {
    let source = quote("  ab \r\n cd…  ")
    var session = TestSessionFactory.make(configuration: configuration(), quote: source)
    let target = "ab\ncd..."
    XCTAssertEqual(session.prompt, target)
    session.insertBatch(target, at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.prompt, target)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 0), target)
    var repeated = session.repeatedAttempt()
    XCTAssertEqual(repeated.prompt, target)
    repeated.insertBatch(target, at: start.addingTimeInterval(1))
    XCTAssertEqual(repeated.outcome, .completed)
    XCTAssertEqual(repeated.errors, 0)
    XCTAssertEqual(source.text, "  ab \r\n cd…  ")
  }

  func testAllWhitespaceSourceBecomesEmptyWithoutInventingFallbackContent() {
    XCTAssertEqual(TestSessionFactory.make(configuration: configuration(),
      quote: quote(" \r\n\t\u{FEFF} ")).prompt, "")
  }

  func testPreparedExternalSourceAndCustomSourceDoNotUseQuotePreparation() {
    let source = " ab   cd… "
    XCTAssertEqual(TestSessionFactory.make(configuration: configuration(), streamPrompt: source).prompt, source)
    let custom = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), customTextPipeDelimiter: false)
    XCTAssertEqual(TestSessionFactory.make(configuration: custom, customText: source).prompt, source)
  }

  func testSavedLegacyQuoteTextIsNotPreparedOnDecodeRecordOrArchiveImport() throws {
    let source = "  ab   \r\n  cd…  "
    let result = CompletedTestResult(id: UUID(), configuration: configuration(), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(1), typedCharacterCount: source.count,
      correctCharacterCount: source.count, errorCount: 0, wpm: 60, rawWpm: 60, accuracy: 100,
      prompt: source)
    let decoded = try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(result))
    XCTAssertEqual(Array(decoded.prompt.unicodeScalars), Array(source.unicodeScalars))
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
    let restored = try TypebarDataTransfer.importArchive(from:
      TypebarDataTransfer.exportArchive(settings: .init(), results: [result], presets: [], at: start))
    XCTAssertEqual(restored.results, [result])
    XCTAssertEqual(Array(try XCTUnwrap(restored.results.first).prompt.unicodeScalars), Array(source.unicodeScalars))
  }

  func testPreparationIsStableAcrossRepeatedCallsAndEveryOwnedLanguageFallback() {
    for source in ["", "  ab… \r\n cd  ", "ab\r\n\n\r cd", "\u{FEFF} e\u{301}\t x \u{A0}"] {
      let prepared = QuoteSourcePolicy.preparedText(source)
      XCTAssertEqual(Array(QuoteSourcePolicy.preparedText(prepared).unicodeScalars), Array(prepared.unicodeScalars))
    }
    for language in TypingLanguage.allCases.filter(\.supportsQuotes) {
      var config = configuration()
      config.language = language
      let session = TestSessionFactory.make(configuration: config)
      XCTAssertFalse(session.prompt.isEmpty, language.rawValue)
      XCTAssertFalse(session.prompt.contains("\r"), language.rawValue)
    }
  }
}
