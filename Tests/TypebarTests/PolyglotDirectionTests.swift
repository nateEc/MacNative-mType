import XCTest
@testable import Typebar

final class PolyglotDirectionTests: XCTestCase {
  func testFieldProjectionAdmitsHebrewMixButPreservesUnverifiedShapingFallback() {
    for hebrew in [TypingLanguage.hebrew, .hebrew1k, .hebrew5k, .hebrew10k] {
      XCTAssertTrue(PromptFieldProjectionPolicy.supports(configuration([.english, hebrew])))
    }
    XCTAssertFalse(PromptFieldProjectionPolicy.supports(configuration([.english, .arabic])))
    XCTAssertFalse(PromptFieldProjectionPolicy.supports(configuration([.english, .hebrew, .arabic])))
    XCTAssertTrue(PromptFieldProjectionPolicy.supports(.words(10, language: .arabic)))
    XCTAssertTrue(PromptFieldProjectionPolicy.supports(.words(10, language: .english)))
  }

  private func configuration(_ languages: [TypingLanguage], base: TypingLanguage? = .english,
    count: Int = 1) -> TestConfiguration {
    .words(count, language: .mixedLanguages, mixedLanguageComponents: languages,
      polyglotBaseLanguage: base, contentOptions: .init(includeNumbers: true))
  }

  private func numericSession(_ configuration: TestConfiguration) -> TypingSession {
    TestSessionFactory.make(configuration: configuration, nextRandomWordIndex: { 0 },
      nextRandomContentUnit: { 0 }, nextRandomPoolShuffleIndex: { $0 - 1 })
  }

  func testLTRPrimarySwitchesToFirstOfWhollyRTLSelectionBeforeDecoration() {
    let requested = configuration([.kurdishCentral, .arabic])
    let session = numericSession(requested)
    XCTAssertEqual(session.configuration.language, .mixedLanguages)
    XCTAssertEqual(session.configuration.polyglotBaseLanguage, .kurdishCentral)
    XCTAssertEqual(session.prompt, "١")
    XCTAssertTrue(session.configuration.usesRightToLeftPrompt)
    XCTAssertTrue(session.generationNotice?.contains("方向") == true)
    XCTAssertEqual(requested.polyglotBaseLanguage, .english)
  }

  func testRTLPrimarySwitchesToFirstOfWhollyLTRSelection() {
    let session = numericSession(configuration([.nepali, .hindi], base: .arabic))
    XCTAssertEqual(session.configuration.polyglotBaseLanguage, .nepali)
    XCTAssertEqual(session.prompt, "१")
    XCTAssertFalse(session.configuration.usesRightToLeftPrompt)
    XCTAssertFalse(session.configuration.containsRightToLeftPromptRun)
    XCTAssertTrue(session.generationNotice?.contains("方向") == true)
  }

  func testMixedDirectionsKeepUnselectedRTLPrimaryAndItsParagraphDirection() {
    let session = numericSession(configuration([.english, .arabic], base: .kurdishCentral))
    XCTAssertEqual(session.configuration.polyglotBaseLanguage, .kurdishCentral)
    XCTAssertEqual(session.prompt, "١")
    XCTAssertTrue(session.configuration.usesRightToLeftPrompt)
    XCTAssertTrue(session.configuration.containsRightToLeftPromptRun)
    XCTAssertNil(session.generationNotice)
  }

  func testMixedDirectionsKeepLTRPrimaryRegardlessOfFirstLanguage() {
    let session = numericSession(configuration([.arabic, .english], base: .nepali))
    XCTAssertEqual(session.configuration.polyglotBaseLanguage, .nepali)
    XCTAssertEqual(session.prompt, "१")
    XCTAssertFalse(session.configuration.usesRightToLeftPrompt)
    XCTAssertNil(session.generationNotice)
  }

  func testSameDirectionKeepsUnselectedPrimaryInsteadOfUsingFirstLanguage() {
    let session = numericSession(configuration([.arabic, .hebrew], base: .kurdishCentral))
    XCTAssertEqual(session.configuration.polyglotBaseLanguage, .kurdishCentral)
    XCTAssertEqual(session.prompt, "١")
    XCTAssertNil(session.generationNotice)
  }

  func testMissingLegacyPrimaryStaysAbsentUntilFreshGeneration() throws {
    let legacy = configuration([.arabic, .hebrew], base: nil)
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(legacy)
    let restored = try JSONDecoder().decode(TestConfiguration.self, from: data)
    XCTAssertNil(restored.polyglotBaseLanguage)
    XCTAssertTrue(restored.usesRightToLeftPrompt, "Keep historical rendering until a fresh attempt")
    let fresh = numericSession(restored)
    XCTAssertEqual(fresh.configuration.polyglotBaseLanguage, .arabic)
    XCTAssertEqual(try encoder.encode(restored), data)
    let ordinaryMixed = numericSession(configuration([.english, .french], base: nil))
    XCTAssertEqual(ordinaryMixed.configuration.polyglotBaseLanguage, .english)
  }

  func testCorrectedPrimarySurvivesCompletionArchiveShareAndRepeat() throws {
    var session = numericSession(configuration([.kurdishCentral, .arabic]))
    session.insertBatch(session.prompt, at: Date(timeIntervalSince1970: 100))
    let result = try XCTUnwrap(session.result())
    let restored = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: []))
    XCTAssertEqual(restored.results.first?.configuration.polyglotBaseLanguage, .kurdishCentral)
    XCTAssertEqual(restored.results.first?.configuration.polyglotUsesPrimaryDirection, true)
    let preset = SavedTestPreset(configuration: result.configuration, quoteID: nil, customText: nil)
    let shared = try TestConfigurationShare.preset(from: TestConfigurationShare.link(for: preset))
    XCTAssertEqual(shared.configuration.polyglotBaseLanguage, .kurdishCentral)
    XCTAssertEqual(shared.configuration.polyglotUsesPrimaryDirection, true)
    let repeated = session.repeatedAttempt()
    XCTAssertEqual(repeated.prompt, session.prompt)
    XCTAssertEqual(repeated.configuration.polyglotBaseLanguage, .kurdishCentral)
    XCTAssertEqual(repeated.configuration.polyglotUsesPrimaryDirection, true)
  }

  func testSingleLanguageGenerationDoesNotAcquirePolyglotMetadata() {
    let session = numericSession(.words(1, language: .arabic,
      contentOptions: .init(includeNumbers: true)))
    XCTAssertEqual(session.configuration.language, .arabic)
    XCTAssertNil(session.configuration.polyglotBaseLanguage)
    XCTAssertNil(session.configuration.polyglotUsesPrimaryDirection)
    XCTAssertNil(session.generationNotice)
  }

  func testCorrectionBuildsOnlyOnePoolAndUsesOnlyResolvedDecorationDraws() {
    let requested = configuration([.kurdishCentral, .arabic])
    let ownedCount = Set((StarterLexicon.kurdishCentralWords + StarterLexicon.arabicWords)
      .map { Array($0.utf16) }).count
    var shuffledSizes: [Int] = [], ranks = 0, units = [0.0, 0, 0]
    let session = TestSessionFactory.make(configuration: requested,
      nextRandomWordIndex: { ranks += 1; return 0 },
      nextRandomContentUnit: { units.removeFirst() },
      nextRandomPoolShuffleIndex: { shuffledSizes.append($0); return $0 - 1 })
    XCTAssertEqual(shuffledSizes, Array(stride(from: ownedCount, through: 2, by: -1)))
    XCTAssertEqual(ranks, 1)
    XCTAssertTrue(units.isEmpty)
    XCTAssertEqual(session.prompt, "١")
  }

  func testFutureSelectionIsPreparedOnlyOnNextAttemptAndKeepsUpdatedReturnLanguage() throws {
    let current = numericSession(configuration([.kurdishCentral, .arabic]))
    var pending = current.configuration
    pending.mixedLanguageComponents = [.english, .french]
    let document = ActiveTestSelectionDocument(preset: .init(configuration: pending, quoteID: nil, customText: nil),
      testParameterMemory: .defaults, polyglotReturnLanguage: current.configuration.polyglotBaseLanguage)
    let restored = try XCTUnwrap(ActiveTestSelectionPolicy.validated(
      JSONDecoder().decode(ActiveTestSelectionDocument.self, from: JSONEncoder().encode(document))))
    XCTAssertEqual(restored.polyglotReturnLanguage, .kurdishCentral)
    XCTAssertEqual(restored.preset.configuration.polyglotBaseLanguage, .kurdishCentral)
    XCTAssertEqual(restored.preset.configuration.polyglotUsesPrimaryDirection, true)
    XCTAssertEqual(current.configuration.mixedLanguageComponents, [.kurdishCentral, .arabic])
    let fresh = numericSession(restored.preset.configuration)
    XCTAssertEqual(fresh.configuration.polyglotBaseLanguage, .english)
    XCTAssertEqual(current.configuration.polyglotBaseLanguage, .kurdishCentral)
    XCTAssertEqual(PolyglotReturnLanguagePolicy.validated(fresh.configuration.polyglotBaseLanguage), .english)
  }

  func testLegacyResultArchiveDoesNotRegenerateTargetsOrFillPrimary() throws {
    let legacy = configuration([.arabic, .hebrew], base: nil, count: 2)
    var session = TypingSession(configuration: legacy, prompt: "owned historical")
    session.insertBatch(session.prompt, at: Date(timeIntervalSince1970: 100))
    let result = try XCTUnwrap(session.result())
    let imported = try XCTUnwrap(TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [])).results.first)
    XCTAssertEqual(imported, result)
    XCTAssertNil(imported.configuration.polyglotBaseLanguage)
    XCTAssertNil(imported.configuration.polyglotUsesPrimaryDirection)
    XCTAssertEqual(imported.prompt, "owned historical")
    _ = numericSession(imported.configuration)
    XCTAssertNil(imported.configuration.polyglotBaseLanguage)
    XCTAssertEqual(session.repeatedAttempt().configuration, legacy)
  }

  func testPrimaryCorrectionAndPreviewNoticesAreBothRetained() {
    let requested = configuration([.kurdishCentral, .arabic], count: 101)
    let session = TestSessionFactory.make(configuration: requested, showAllLines: true,
      nextRandomWordIndex: { 0 }, nextRandomContentUnit: { 0 }, nextRandomPoolShuffleIndex: { $0 - 1 })
    XCTAssertEqual(session.configuration.polyglotBaseLanguage, .kurdishCentral)
    XCTAssertTrue(session.generationNotice?.contains("方向") == true)
    // This finite 101-word preview is complete; the notice starts above 100,000.
    XCTAssertEqual(session.prompt.split(separator: " ").count, 101)
    let oversized = TestSessionFactory.make(configuration: configuration([.kurdishCentral, .arabic], count: 100_001),
      showAllLines: true, nextRandomWordIndex: { 0 }, nextRandomContentUnit: { 0 },
      nextRandomPoolShuffleIndex: { $0 - 1 })
    XCTAssertTrue(oversized.generationNotice?.contains("方向") == true)
    XCTAssertTrue(oversized.generationNotice?.contains("\n") == true)
    XCTAssertTrue(oversized.generationNotice?.contains(
      GeneratedPromptChunkPolicy.previewNotice(for: oversized.configuration, showAllLines: true) ?? "missing") == true)
  }

  func testPreviouslyRecordedPrimaryKeepsLegacyDirectionUntilFreshGeneration() throws {
    let previous = configuration([.english, .arabic], base: .kurdishCentral)
    XCTAssertNil(previous.polyglotUsesPrimaryDirection)
    XCTAssertFalse(previous.usesRightToLeftPrompt)
    let restored = try JSONDecoder().decode(TestConfiguration.self, from: JSONEncoder().encode(previous))
    XCTAssertEqual(restored, previous)
    XCTAssertFalse(restored.usesRightToLeftPrompt)
    let fresh = numericSession(restored)
    XCTAssertEqual(fresh.configuration.polyglotUsesPrimaryDirection, true)
    XCTAssertTrue(fresh.configuration.usesRightToLeftPrompt)
    XCTAssertFalse(restored.usesRightToLeftPrompt)
    XCTAssertEqual(fresh.repeatedAttempt().configuration.polyglotUsesPrimaryDirection, true)
  }
}
