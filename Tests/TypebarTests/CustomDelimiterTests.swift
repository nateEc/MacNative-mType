import XCTest
@testable import Typebar

final class CustomDelimiterTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 100)

  // Inject through the real decoder so this suite compiles and demonstrates
  // the old reader ignoring the missing behavior before the model is added.
  private func configuration(_ completion: CustomTextCompletion, pipe: Bool,
    limit: Int = 2, ordering: CustomTextOrdering = .inOrder,
    language: TypingLanguage = .english, modifiers: [TestModifier] = []) throws -> TestConfiguration {
    let base = TestConfiguration(mode: .custom,
      duration: completion == .time ? TimeInterval(limit) : nil,
      wordLimit: completion == .words ? limit : nil, difficulty: .normal, rules: .init(),
      language: language, customTextCompletion: completion,
      customTextSectionLimit: completion == .sections ? limit : nil,
      customTextOrdering: ordering, modifiers: modifiers)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as? [String: Any])
    object["customTextPipeDelimiter"] = pipe
    return try JSONDecoder().decode(TestConfiguration.self, from: JSONSerialization.data(withJSONObject: object))
  }

  private func encodedDelimiter(_ config: TestConfiguration) throws -> Bool? {
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
    return object["customTextPipeDelimiter"] as? Bool
  }

  func testWordLimitedPipePromptFinishesAfterItsWholeGeneratedQueue() throws {
    var session = TestSessionFactory.make(configuration: try configuration(.words, pipe: true, limit: 3),
      customText: "amber bay | cedar dune")
    XCTAssertEqual(session.prompt, "amber bay cedar dune amber bay")
    XCTAssertNil(session.sectionProgress)
    session.insertBatch("amber bay cedar", at: start)
    XCTAssertEqual(session.outcome, .active)
    session.insertBatch(" dune amber bay", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 6)
    XCTAssertEqual(session.errors, 0)
  }

  func testPipeWordLimitKeepsLongSectionRemainderAndStopsAt101Words() throws {
    let words = (0..<140).map { "item\($0)" }
    var session = TestSessionFactory.make(configuration: try configuration(.words, pipe: true, limit: 101),
      customText: words.joined(separator: " ") + " | bay")
    XCTAssertEqual(session.prompt, words.prefix(100).joined(separator: " ") + " ")
    session.insertBatch(words.prefix(101).joined(separator: " "), at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.prompt, words.prefix(101).joined(separator: " "))
    XCTAssertEqual(session.completedWordCount, 101)
  }

  func testTimedPipeSectionsContinueInsteadOfRequiringTheLiteralPipe() throws {
    var session = TestSessionFactory.make(configuration: try configuration(.time, pipe: true, limit: 120),
      customText: "amber bay | cedar dune")
    XCTAssertEqual(session.prompt, String(repeating: "amber bay cedar dune ", count: 25))
    XCTAssertNil(session.sectionProgress)
    session.insertBatch(String(repeating: "amber bay cedar dune ", count: 30), at: start)
    XCTAssertEqual(session.errors, 0)
    XCTAssertEqual(session.completedWordCount, 120)
    XCTAssertFalse(session.isFinished)
    session.insertBatch("amber bay ", at: start.addingTimeInterval(119))
    session.tick(at: start.addingTimeInterval(120))
    XCTAssertEqual(session.outcome, .completed)
  }

  func testShuffledPipeTimedTextKeepsEachSectionTogetherAndEachPositionPerCycle() throws {
    let session = TestSessionFactory.make(configuration: try configuration(.time, pipe: true,
      limit: 120, ordering: .shuffled), customText: "amber one | bay two | cedar three")
    let words = session.prompt.split(separator: " ").map(String.init)
    XCTAssertEqual(words.count, 100)
    guard words.count == 100 else { return }
    for start in stride(from: 0, to: 96, by: 6) {
      var sections: [String] = []
      for index in stride(from: start, to: start + 6, by: 2) {
        sections.append("\(words[index]) \(words[index + 1])")
      }
      XCTAssertEqual(Set(sections), ["amber one", "bay two", "cedar three"])
    }
  }

  func testRandomPipeInfiniteWordsKeepPairsAndCanBailOut() throws {
    var session = TestSessionFactory.make(configuration: try configuration(.words, pipe: true,
      limit: 0, ordering: .random), customText: "amber one | bay two | cedar three")
    let words = session.prompt.split(separator: " ").map(String.init)
    XCTAssertEqual(words.count, 100)
    guard words.count == 100 else { return }
    for index in stride(from: 0, to: 100, by: 2) {
      XCTAssertTrue(["amber one", "bay two", "cedar three"].contains(words[index] + " " + words[index + 1]))
    }
    session.insertBatch(session.prompt, at: start)
    XCTAssertFalse(session.isFinished)
    session.bailOut(at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .bailedOut)
  }

  func testSpaceDelimiterSectionLimitCountsWordsAndPreservesLiteralPipes() throws {
    var session = TestSessionFactory.make(configuration: try configuration(.sections, pipe: false, limit: 3),
      customText: "amber bay|cedar")
    XCTAssertEqual(session.prompt, "amber bay|cedar amber")
    session.insertBatch("amber ", at: start)
    XCTAssertEqual(session.sectionProgress?.completed, 1)
    session.insertBatch("bay|cedar amber", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.sectionProgress?.completed, 3)
  }

  func testPipeSimpleCompletionConsumesEachSectionOnce() throws {
    var session = TestSessionFactory.make(configuration: try configuration(.finish, pipe: true),
      customText: "amber bay | cedar dune")
    XCTAssertEqual(session.prompt, "amber bay cedar dune")
    XCTAssertNil(session.sectionProgress)
    session.insertBatch("amber bay cedar dune", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
  }

  func testDelimiterCleanupNormalizesUnicodeSpacesNewlinesAndCanonicalText() throws {
    var session = TestSessionFactory.make(configuration: try configuration(.sections, pipe: true),
      customText: "  cafe\u{301}\u{00A0}bay\r\n | dune\u{202F}elm  ")
    XCTAssertEqual(session.prompt, "café bay\ndune elm")
    session.insertBatch("café bay\ndune elm", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
  }

  func testNoSpacePipeWordBudgetAndHiddenHistorySurviveTheBatchBoundary() throws {
    let words = (0..<120).map { "item\($0)" }
    var session = TestSessionFactory.make(configuration: try configuration(.words, pipe: true,
      limit: 101, language: .codeSwift, modifiers: [.noSpaces]),
      customText: words.joined(separator: " ") + " | bay")
    session.insertBatch(words.prefix(101).joined(), at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 101)
    XCTAssertEqual(session.wordReviews.count, 101)
    XCTAssertEqual(session.errors, 0)
  }

  func testRandomPipeWordModeAvoidsPreviousWordsRatherThanPreviousWholeSections() throws {
    var stream = try XCTUnwrap(CustomSectionWordStream(source: "amber bay | bay cedar | dune elm | fox glen",
      configuration: configuration(.words, pipe: true, limit: 2, ordering: .random)))
    var draws = [0, 1, 2].makeIterator()
    let chunk = stream.nextChunk(random: { draws.next() ?? 2 })
    XCTAssertEqual(chunk.text, "amber bay dune elm")
  }

  func testExplicitDelimiterRoundTripsAllCompletionModesAndPortableSurfaces() throws {
    for mode in CustomTextCompletion.allCases {
      for pipe in [false, true] {
        let config = try configuration(mode, pipe: pipe)
        XCTAssertEqual(try encodedDelimiter(config), pipe)
        let preset = SavedTestPreset(configuration: config, customText: "amber bay | cedar dune")
        let shared = try TestConfigurationShare.preset(from: TestConfigurationShare.link(for: preset))
        XCTAssertEqual(try encodedDelimiter(shared.configuration), pipe)
        let json = try SettingsJSONCommandCodec.export(settings: .init(), configuration: config,
          layoutFluidLayouts: [.ansiQwerty], testParameterMemory: .legacyDefaults(configuration: config))
        XCTAssertEqual(try encodedDelimiter(SettingsJSONCommandCodec.decode(json).configuration), pipe)
        let selection = ActiveTestSelectionDocument(preset: preset,
          testParameterMemory: .legacyDefaults(configuration: config))
        let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
          settings: .init(), results: [], presets: [], activeTestSelection: selection, at: start))
        XCTAssertEqual(try encodedDelimiter(XCTUnwrap(archive.activeTestSelection).preset.configuration), pipe)
      }
    }
  }

  func testMissingDelimiterKeepsLegacySectionAndLiteralPipeDefaults() throws {
    let legacy = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), customTextCompletion: .sections, customTextSectionLimit: 2)
    let decoded = try JSONDecoder().decode(TestConfiguration.self, from: JSONEncoder().encode(legacy))
    XCTAssertNil(try encodedDelimiter(decoded))
    XCTAssertEqual(TestSessionFactory.make(configuration: decoded, customText: "amber bay | cedar dune").prompt,
      "amber bay cedar dune")
    let finish = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init())
    XCTAssertEqual(TestSessionFactory.make(configuration: finish, customText: "amber | bay").prompt, "amber | bay")
  }

  func testDelimiterExportsUseNewEnvelopeVersionsRatherThanSilentOldReaderFallback() throws {
    let config = try configuration(.time, pipe: true, limit: 120)
    let preset = SavedTestPreset(configuration: config, customText: "amber bay | cedar dune")
    let link = try TestConfigurationShare.link(for: preset)
    let components = try XCTUnwrap(URLComponents(string: link))
    let token = try XCTUnwrap(components.queryItems?.first?.value)
    var base64 = token.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
    let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(Data(base64Encoded: base64))) as? [String: Any])
    XCTAssertEqual(payload["version"] as? Int, 2)
    let json = try SettingsJSONCommandCodec.export(settings: .init(), configuration: config,
      layoutFluidLayouts: [.ansiQwerty], testParameterMemory: .legacyDefaults(configuration: config))
    XCTAssertEqual(try SettingsJSONCommandCodec.decode(json).version, 3)
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [], presets: [], at: start))
    XCTAssertEqual(archive.version, TypebarArchive.currentVersion)
  }

  func testEveryCodeChoiceConsumesTheWholePipeWordQueue() throws {
    for language in TypingLanguage.allCases.filter(\.isCodeLanguage) {
      var session = TestSessionFactory.make(configuration: try configuration(.words, pipe: true,
        limit: 3, language: language), customText: "let vessel | seed() cabin")
      session.insertBatch("let vessel seed()", at: start)
      XCTAssertEqual(session.outcome, .active, language.displayName)
      session.insertBatch(" cabin let vessel", at: start.addingTimeInterval(1))
      XCTAssertEqual(session.outcome, .completed, language.displayName)
      XCTAssertEqual(session.completedWordCount, 6, language.displayName)
      XCTAssertEqual(session.errors, 0, language.displayName)
    }
  }

  func testLegacyPipeWordLinksAndModeOnlyFallbackRetainTheirDelimiter() throws {
    let current = SavedTestPreset(configuration: .words(25))
    let legacy = try LegacyTestSettingsLinkImporter.preset(
      from: "https://share.example.test/practice?testSettings=NoIgxgrgzgLg9gWxAGgHYQDYeQbxDAUwA8YQAuUAQwQCMCAnFEAC0vprkYF1kQBLKAHVOAEwBKlVCMTkY9CAV4B3UeQCsvEQQx8EfQozIgAPiAC+aTNnRZLtm9atcgA",
      current: current)
    XCTAssertEqual(try encodedDelimiter(legacy.configuration), true)
    XCTAssertEqual(TestSessionFactory.make(configuration: legacy.configuration,
      customText: try XCTUnwrap(legacy.customText)).prompt, "amber harbor amber harbor amber")
    for pipe in [false, true] {
      let fallback = LegacyTestSettingsLinkImporter.CustomTextFallback(text: "amber bay | cedar dune",
        completion: .sections, duration: nil, wordLimit: nil, sectionLimit: 3, ordering: .inOrder,
        pipeDelimiter: pipe)
      let preset = try LegacyTestSettingsLinkImporter.preset(
        from: "https://share.example.test/practice?testSettings=NoIgxgrgzgLg9gWxAGgHYQDYbZ76s4H566EYC6QA",
        current: current, customTextFallback: fallback)
      XCTAssertEqual(try encodedDelimiter(preset.configuration), pipe)
    }
  }

  func testPreviousSettingsAndArchiveVersionsDecodeMissingDelimiterWithoutBackfill() throws {
    let config = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), customTextCompletion: .sections, customTextSectionLimit: 2)
    let settingsJSON = try SettingsJSONCommandCodec.export(settings: .init(), configuration: config,
      layoutFluidLayouts: [], testParameterMemory: .legacyDefaults(configuration: config))
    var settingsObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(settingsJSON.utf8)) as? [String: Any])
    settingsObject["version"] = 2
    let decoded = try SettingsJSONCommandCodec.decode(String(decoding:
      JSONSerialization.data(withJSONObject: settingsObject), as: UTF8.self))
    XCTAssertNil(try encodedDelimiter(decoded.configuration))
    settingsObject.removeValue(forKey: "testParameterMemory")
    XCTAssertThrowsError(try SettingsJSONCommandCodec.decode(String(decoding:
      JSONSerialization.data(withJSONObject: settingsObject), as: UTF8.self)))
    let preset = SavedTestPreset(configuration: config, customText: "amber | bay")
    let selection = ActiveTestSelectionDocument(preset: preset, testParameterMemory: .legacyDefaults(configuration: config))
    let data = try TypebarDataTransfer.exportArchive(settings: .init(), results: [], presets: [],
      activeTestSelection: selection, at: start)
    var archiveObject = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    archiveObject["version"] = 9
    let archive = try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: archiveObject))
    XCTAssertEqual(archive.version, 9)
    XCTAssertNil(try encodedDelimiter(XCTUnwrap(archive.activeTestSelection).preset.configuration))
    XCTAssertEqual(archive.activeTestSelection?.preset.customText, "amber | bay")
  }

  func testVersionOneNativeLinkKeepsItsHistoricalDelimiterDefault() throws {
    let config = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), customTextCompletion: .sections, customTextSectionLimit: 2)
    let preset = SavedTestPreset(configuration: config, customText: "amber | bay")
    let encodedPreset = try JSONSerialization.jsonObject(with: JSONEncoder().encode(preset))
    let payload = try JSONSerialization.data(withJSONObject: ["version": 1, "preset": encodedPreset])
    let token = payload.base64EncodedString().replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    let imported = try TestConfigurationShare.preset(from: "typebar://test?preset=\(token)")
    XCTAssertEqual(imported, preset)
    XCTAssertEqual(TestSessionFactory.make(configuration: imported.configuration,
      customText: imported.customText ?? "").prompt, "amber bay")
  }

  func testMalformedDelimiterFailsDecodingInsteadOfBecomingAnImplicitDefault() throws {
    let config = try configuration(.time, pipe: true)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
    for invalid in ["true", 1, [true]] as [Any] {
      object["customTextPipeDelimiter"] = invalid
      XCTAssertThrowsError(try JSONDecoder().decode(TestConfiguration.self,
        from: JSONSerialization.data(withJSONObject: object)))
    }
  }

  func testOldResultKeepsItsStoredPromptAndReplayWhenDelimiterFieldIsMissing() throws {
    var session = TestSessionFactory.make(configuration: try configuration(.words, pipe: true,
      limit: 3, language: .codeSwift), customText: "let vessel | seed() cabin")
    session.insertBatch("let vessel seed() cabin let vessel", at: start)
    let result = try XCTUnwrap(session.result())
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any])
    var config = try XCTUnwrap(object["configuration"] as? [String: Any])
    config.removeValue(forKey: "customTextPipeDelimiter")
    object["configuration"] = config
    let decoded = try JSONDecoder().decode(CompletedTestResult.self,
      from: JSONSerialization.data(withJSONObject: object))
    XCTAssertEqual(decoded.prompt, result.prompt)
    XCTAssertEqual(decoded.replayEvents, result.replayEvents)
    XCTAssertEqual(decoded.wpm, result.wpm)
    XCTAssertNil(try encodedDelimiter(decoded.configuration))
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: decoded).portableResult), decoded)
  }

  func testLongPipeSimpleCompletionKeepsNoSpaceUnicodeHistoryAcrossChunks() throws {
    let words = (0..<120).map { "item\($0)" }
    let config = try configuration(.finish, pipe: true, language: .codeSwift,
      modifiers: [.uppercase, .noSpaces])
    var session = TestSessionFactory.make(configuration: config,
      customText: words.joined(separator: " ") + " | straße")
    XCTAssertEqual(session.prompt, words.prefix(100).joined().uppercased())
    XCTAssertTrue(session.usesIncrementalPromptExtension)
    session.insertBatch(words.joined().uppercased() + "STRASSE", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.wordReviews.count, 121)
    XCTAssertEqual(session.errors, 0)
    XCTAssertEqual(session.wordReviews.last?.target, "STRASSE")
  }

  func testRandomAndShuffledTimedPipeRepeatKeepFutureChunksAndTheirWordContext() throws {
    for ordering in [CustomTextOrdering.random, .shuffled] {
      var session = TestSessionFactory.make(configuration: try configuration(.time, pipe: true,
        limit: 120, ordering: ordering), customText: "amber bay | bay cedar | dune elm | fox glen")
      var repeated = session.repeatedAttempt()
      for _ in 0..<3 {
        let input = String(session.prompt.dropFirst(session.typed.count))
        session.insertBatch(input, at: start)
        repeated.insertBatch(input, at: start)
        session.insertBatch("!", at: start)
        repeated.insertBatch("!", at: start)
        session.deleteBackward(at: start)
        repeated.deleteBackward(at: start)
        XCTAssertEqual(session.prompt, repeated.prompt)
        XCTAssertEqual(session.typed, repeated.typed)
        XCTAssertNil(session.sectionProgress)
      }
      XCTAssertGreaterThan(session.prompt.split(separator: " ").count, 100)
      XCTAssertFalse(session.isFinished)
    }
  }

  func testSeparatorOnlyTextIsInvalidOnlyWhenThePipeDelimiterIsEnabled() throws {
    for pipe in [false, true] {
      let config = try configuration(.finish, pipe: pipe)
      let preset = SavedTestPreset(configuration: config, customText: " | | ")
      let selection = ActiveTestSelectionDocument(preset: preset,
        testParameterMemory: .legacyDefaults(configuration: config))
      if pipe {
        XCTAssertThrowsError(try TestConfigurationShare.link(for: preset))
        XCTAssertNil(ActiveTestSelectionPolicy.validated(selection))
      } else {
        XCTAssertNoThrow(try TestConfigurationShare.link(for: preset))
        XCTAssertNotNil(ActiveTestSelectionPolicy.validated(selection))
      }
    }
  }

  func testFinitePipePromptCanShuffleEachWholeSectionOnce() throws {
    var stream = try XCTUnwrap(CustomSectionWordStream(source: "amber one | bay two | cedar three",
      configuration: configuration(.finish, pipe: true, ordering: .shuffled)))
    XCTAssertEqual(stream.nextChunk(random: { 0 }).text, "amber one cedar three bay two")
    XCTAssertFalse(stream.hasRemaining)
  }
}
