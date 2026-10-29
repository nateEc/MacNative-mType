import XCTest
@testable import Typebar

final class FreshLazyEligibilityTests: XCTestCase {
  func testPinnedWordGeneratorHonorsPerComponentEligibility() throws {
    let reference = try XCTUnwrap(ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"])
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", "Scripts/check-source-code-decoration.mjs", reference]
    process.standardOutput = output
    try process.run()
    let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0, text)
    XCTAssertTrue(text.contains("lazy eligibility fixtures passed"), text)
  }

  func testCustomTextRetainsLazyModeOnAnUnsupportedDictionary() {
    let requested = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), language: .portuguese5k, modifiers: [.lazyLatin])
    var session = TestSessionFactory.make(configuration: requested, customText: "não")
    XCTAssertTrue(session.configuration.modifiers.contains(.lazyLatin))
    XCTAssertEqual(session.prompt, "nao")
    session.insertBatch("nao", at: Date(timeIntervalSince1970: 10))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
  }

  func testFreshPreparationRejectsUnsupportedSingleAndMixedPoolsWithoutChangingSavedRequest() {
    for configuration in [
      TestConfiguration.words(1, language: .portuguese5k),
      .words(1, language: .mixedLanguages, mixedLanguageComponents: [.portuguese5k, .portuguese550k]),
    ] {
      let requested = configuration.with(modifiers: [.lazyLatin])
      XCTAssertTrue(requested.modifiers.contains(.lazyLatin))
      XCTAssertFalse(PolyglotGenerationPreparation(requested).configuration.modifiers.contains(.lazyLatin))
    }
  }

  func testMixedCandidatesRespectEachOwnersEligibilityAndExactLookup() {
    let sources: [(TypingLanguage, IndexedLexicon)] = [
      (.portuguese5k, IndexedLexicon(["não"])), (.portuguese1k, IndexedLexicon(["ação"])),
    ]
    let pool = NativePolyglotCandidates(sources: sources, nextShuffleIndex: { $0 - 1 })
    XCTAssertEqual(pool.lazyWord("não"), "não")
    XCTAssertEqual(pool.lazyWord("ação"), "acao")
    XCTAssertEqual(pool.lazyWord("AÇÃO"), "AÇÃO")
    for modifiers: [TestModifier] in [[.lazyLatin], [.lazyLatin, .noSpaces]] {
      let config = TestConfiguration.words(2, language: .mixedLanguages,
        mixedLanguageComponents: [.portuguese5k, .portuguese1k], polyglotBaseLanguage: .english)
        .with(modifiers: modifiers)
      XCTAssertTrue(PolyglotGenerationPreparation(config).configuration.modifiers.contains(.lazyLatin))
      var cursor = GeneratedCandidateContinuation(configuration: config, batchTokenCount: 2,
        polyglotSources: sources, nextRandomPoolShuffleIndex: { $0 - 1 })
      var ranks = [0, 1]
      XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: { ranks.removeFirst() }).transformed,
        modifiers.contains(.noSpaces) ? "nãoacao" : "não acao")
    }
  }

  @MainActor func testWholePreviewUsesEligibilityBeforeGeneratingAndRepeatsCapturedPrompt() async throws {
    let requested = TestConfiguration.words(153, language: .portuguese5k).with(modifiers: [.lazyLatin])
    let session = try await WholePreviewWordPreparation.prepareSession(configuration: requested,
      sourceWords: ["não"], nextRandomWordIndex: { 0 })
    XCTAssertFalse(session.configuration.modifiers.contains(.lazyLatin))
    XCTAssertEqual(session.prompt, Array(repeating: "não", count: 153).joined(separator: " "))
    XCTAssertEqual(session.repeatedAttempt().prompt, session.prompt)
  }

  func testHistoricalConfigurationAndCapturedPromptKeepUnsupportedLazyPreference() throws {
    let requested = TestConfiguration.words(1, language: .portuguese5k).with(modifiers: [.lazyLatin])
    let decoded = try JSONDecoder().decode(TestConfiguration.self, from: JSONEncoder().encode(requested))
    XCTAssertTrue(decoded.modifiers.contains(.lazyLatin))
    var repeated = TypingSession(configuration: decoded, prompt: "nao").repeatedAttempt()
    XCTAssertTrue(repeated.configuration.modifiers.contains(.lazyLatin))
    XCTAssertEqual(repeated.prompt, "nao")
    repeated.insertBatch("nao", at: Date(timeIntervalSince1970: 10))
    XCTAssertEqual(repeated.outcome, .completed)
    XCTAssertEqual(repeated.errors, 0)
  }
}
