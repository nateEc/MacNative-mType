import XCTest
@testable import Typebar

@MainActor final class WebsiteConfigGeneratedTextOrderTests: XCTestCase {
  private func configuration() -> TestConfiguration {
    var config = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), modifiers: [.doubleCharacters, .rot13])
    config.websiteTextAlterationOrder = [.doubleCharacters, .doubleCharacters, .rot13]
    return config
  }

  func testActualFactoryUsesRepeatedImportedEffectsWithoutChangingLegacyGeneration() throws {
    let config = configuration()
    let session = TestSessionFactory.make(configuration: config, customText: "ab")
    XCTAssertEqual(session.prompt, "nnnnoooo")
    XCTAssertEqual(session.configuration.websiteTextAlterationOrder, config.websiteTextAlterationOrder)
    var legacy = config; legacy.websiteTextAlterationOrder = nil
    XCTAssertEqual(TestSessionFactory.make(configuration: legacy, customText: "ab").prompt, "nnoo")
  }

  func testArchiveRetainsTheOrderedPlanAndRejectsNonTextOrMissingEffects() throws {
    let config = configuration(), encoder = JSONEncoder(), decoder = JSONDecoder()
    let data = try encoder.encode(config)
    let decoded = try decoder.decode(TestConfiguration.self, from: data)
    XCTAssertEqual(decoded, config)
    XCTAssertEqual(TestSessionFactory.make(configuration: decoded, customText: "ab").prompt, "nnnnoooo")
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["modifiers"] = [TestModifier.doubleCharacters.rawValue, TestModifier.doubleCharacters.rawValue,
      TestModifier.rot13.rawValue]
    let normalized = try decoder.decode(TestConfiguration.self, from: JSONSerialization.data(withJSONObject: object))
    XCTAssertEqual(normalized.websiteTextAlterationOrder, config.websiteTextAlterationOrder)
    XCTAssertEqual(TestSessionFactory.make(configuration: normalized, customText: "ab").prompt, "nnnnoooo")
    for invalid in [[TestModifier.noQuit.rawValue], [TestModifier.doubleCharacters.rawValue]] {
      object["websiteTextAlterationOrder"] = invalid
      XCTAssertThrowsError(try decoder.decode(TestConfiguration.self, from: JSONSerialization.data(withJSONObject: object)))
    }
    object.removeValue(forKey: "websiteTextAlterationOrder")
    XCTAssertNil(try decoder.decode(TestConfiguration.self, from: JSONSerialization.data(withJSONObject: object)).websiteTextAlterationOrder)
  }

  func testDraftInstallsItsExactSequenceAndNativeEditsDoNotInventANewOrder() throws {
    let draft = try WebsiteConfigNativeProfile.prepareDraft(
      #"{"mode":"custom","funbox":["ddoouubblleedd","ddoouubblleedd","rot13"]}"#,
      pointsPerRem: 16, context: .init())
    var legacy = configuration(); legacy.websiteTextAlterationOrder = nil
    let imported = try draft.generators.applyingTextOrder(to: legacy)
    XCTAssertEqual(imported.websiteTextAlterationOrder, [.doubleCharacters, .doubleCharacters, .rot13])
    XCTAssertEqual(TestSessionFactory.make(configuration: imported, customText: "ab").prompt, "nnnnoooo")
    XCTAssertThrowsError(try draft.generators.applyingTextOrder(to: .words(2)))
    XCTAssertEqual(imported.with(modifiers: [.rot13]).websiteTextAlterationOrder, [.rot13])
    XCTAssertNil(imported.with(modifiers: [.doubleCharacters, .rot13, .uppercase]).websiteTextAlterationOrder)

    let current = SavedTestPreset(configuration: imported, customText: "ab")
    var testOnly = SavedTestPreset(configuration: .words(5)); testOnly.settingGroups = [.test]
    XCTAssertEqual(PresetApplicationPolicy.applying(current: current, preset: testOnly)
      .configuration.websiteTextAlterationOrder, imported.websiteTextAlterationOrder)
    testOnly.settingGroups = [.behavior]
    XCTAssertNil(PresetApplicationPolicy.applying(current: current, preset: testOnly).configuration.websiteTextAlterationOrder)
  }

  func testActualGeneratedCursorRetainsThePlanAcrossAllBatches() {
    var config = configuration(); config.mode = .words; config.wordLimit = 230; config.language = .codeSwift
    var cursor = GeneratedCodeContinuation(configuration: config, batchTokenCount: 100,
      sourceWords: ["ab cd ef"])
    var count = 0
    for _ in 0..<3 {
      let chunk = cursor.nextChunk(nextRandomWordIndex: { 0 })
      let source = chunk.source.split(separator: " ").map(String.init)
      let actual = chunk.transformed.split(separator: " ").map(String.init)
      let expected = ["ab": "nnnnoooo", "cd": "ppppqqqq", "ef": "rrrrssss"]
      XCTAssertTrue(source.allSatisfy { expected[$0] != nil })
      XCTAssertEqual(actual, source.compactMap { expected[$0] })
      count += source.count
    }
    XCTAssertEqual(count, 230); XCTAssertFalse(cursor.hasRemaining)
  }

  func testQuoteAndCustomSectionCursorsKeepEffectsAfterTheOpeningWindow() throws {
    var config = configuration(); config.mode = .quote
    let quote = OfflineQuote(id: "own", title: "own", text: Array(repeating: "ab", count: 101).joined(separator: " "),
      language: .english, length: .long)
    var quotes = QuoteWordStream(quote: quote, configuration: config, showAllLines: false)
    let initial = try quotes.initialChunk()
    XCTAssertEqual(initial.text.split(separator: " "), Array(repeating: "nnnnoooo", count: 100))
    // Finite quote completion removes the final commit, not its target.
    XCTAssertEqual(try quotes.nextWord().text, "nnnnoooo"); XCTAssertFalse(quotes.hasRemaining)

    config.mode = .custom; config.customTextCompletion = .words; config.wordLimit = 205
    var custom = try XCTUnwrap(CustomSectionWordStream(preparedSections: ["ab cd"], configuration: config))
    var output: [String] = []
    for _ in 0..<3 { output += custom.nextChunk().text.split(separator: " ").map(String.init) }
    XCTAssertEqual(output.count, 205)
    XCTAssertEqual(output, (0..<205).map { $0.isMultiple(of: 2) ? "nnnnoooo" : "ppppqqqq" })
    XCTAssertFalse(custom.hasRemaining)
  }

  func testCooperativePreparationAndWholePreviewUseTheSameOrderedExecution() async throws {
    var config = configuration(); config.mode = .words; config.wordLimit = 201
    let live = try await LivePromptTransformation.prepare("ab cd", configuration: config,
      preservesNoSpaceBoundaries: false, wordOffset: 0, wordBound: 201)
    XCTAssertEqual(live.text, "nnnnoooo ppppqqqq")
    let prepared = try await WholePreviewWordPreparation.prepareSession(configuration: config,
      sourceWords: ["ab"], nextRandomWordIndex: { 0 })
    XCTAssertEqual(prepared.prompt.split(separator: " "), Array(repeating: "nnnnoooo", count: 201))
    let repeated = prepared.repeatedAttempt()
    XCTAssertEqual(repeated.prompt, prepared.prompt)
    XCTAssertEqual(repeated.configuration.websiteTextAlterationOrder, config.websiteTextAlterationOrder)
  }

  func testUTF16IntermediateValuesAreNotRepairedBetweenImportedEffects() {
    var config = configuration()
    config.modifiers = [.backwards]
    config.websiteTextAlterationOrder = [.backwards, .backwards]
    let session = TestSessionFactory.make(configuration: config, customText: "a😀b")
    XCTAssertEqual(session.prompt, "a😀b")
    XCTAssertEqual(session.repeatedAttempt().prompt, session.prompt)
  }

  func testRealGeneratedTargetsDistinguishUnderscoreBeforeAndAfterDoubling() {
    for (order, expected) in [([TestModifier.underscoreSeparators, .doubleCharacters], ["aabb__", "aabb"]),
      ([.doubleCharacters, .underscoreSeparators], ["aabb_", "aabb"])] {
      var config = TestConfiguration.words(2).with(modifiers: [.doubleCharacters, .underscoreSeparators])
      config.websiteTextAlterationOrder = order
      var cursor = GeneratedCodeContinuation(configuration: config, batchTokenCount: 2, sourceWords: ["ab"])
      let chunk = cursor.nextChunk(nextRandomWordIndex: { 0 })
      XCTAssertEqual(chunk.noSpaceTargetWords, expected)
      XCTAssertEqual(chunk.transformed, expected.joined())
    }
  }

  func testLiveGeneratorContinuationUsesThePlanButSidePublicationBypassesIt() throws {
    var config = configuration(); config.mode = .words; config.wordLimit = 3
    config.modifiers.append(.referenceStream)
    let now = Date(timeIntervalSince1970: 4000)
    var generated = TestSessionFactory.make(configuration: config, streamPrompt: "ab", streamsLiveContent: true)
    generated.insertBatch("nnnnoooo ", at: now)
    XCTAssertTrue(generated.needsLiveContentGeneration)
    XCTAssertTrue(generated.acceptGeneratedLiveContent(.init(text: "cd ef", noSpaceBoundarySource: nil)))
    // The generator publishes only the demanded field, not its buffered tail.
    XCTAssertEqual(generated.prompt, "nnnnoooo ppppqqqq ")
    generated.insertBatch("ppppqqqq rrrrssss", at: now)
    XCTAssertEqual(generated.prompt, "nnnnoooo ppppqqqq rrrrssss")
    XCTAssertEqual(generated.outcome, .completed); XCTAssertEqual(generated.errors, 0)
    XCTAssertEqual(try XCTUnwrap(generated.result(at: now)).configuration.websiteTextAlterationOrder,
      config.websiteTextAlterationOrder)

    var side = TestSessionFactory.make(configuration: config, streamPrompt: "ab", streamsLiveContent: true)
    XCTAssertTrue(side.appendLiveContent(.init(text: "xy", noSpaceBoundarySource: nil)))
    XCTAssertTrue(side.prompt.contains("xy")); XCTAssertFalse(side.prompt.contains("kkkkllll"))
  }
}
