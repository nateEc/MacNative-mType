import XCTest
@testable import Typebar

final class PolyglotInputNormalizationTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 300)

  private func requested(_ base: TypingLanguage,
    selected: [TypingLanguage] = [.english, .french]) -> TestConfiguration {
    .words(10, language: .mixedLanguages, mixedLanguageComponents: selected, polyglotBaseLanguage: base)
  }

  // Real preparation and input, owned targets: this does not prove catalog,
  // browser event-loop or IME equivalence.
  private func fresh(_ base: TypingLanguage, prompt: String,
    selected: [TypingLanguage] = [.english, .french]) -> TypingSession {
    TestSessionFactory.make(configuration: requested(base, selected: selected), streamPrompt: prompt)
  }

  private func saved(_ input: TypingSession) throws -> CompletedTestResult {
    var ended = input
    ended.bailOut(at: start.addingTimeInterval(4))
    return try XCTUnwrap(ended.result())
  }

  func testUnselectedRussianPrimaryNormalizesAllThreeSpellingsToActualTarget() throws {
    for target in ["ё", "е", "e"] {
      for entered in ["ё", "е", "e"] {
        var input = fresh(.russian, prompt: target + " tail")
        input.insert(entered, at: start)
        XCTAssertEqual(input.typed, target)
        XCTAssertEqual(input.errors, 0)
        let result = try saved(input)
        XCTAssertEqual(result.inputMetrics?.totalAttempts, 1)
        XCTAssertEqual(result.inputMetrics?.correctAttempts, 1)
        XCTAssertEqual(result.replayEvents.map(\.text), [target])
      }
    }
  }

  func testRussianSizePrimariesNormalizeButSpecializedPrimariesRemainLiteral() {
    for base in [TypingLanguage.russian, .russian1k, .russian5k, .russian10k,
      .russian25k, .russian50k, .russian375k] {
      var input = fresh(base, prompt: "ёл tail")
      input.insertBatch("eл", at: start)
      XCTAssertEqual(input.typed, "ёл", base.rawValue)
      XCTAssertEqual(input.errors, 0, base.rawValue)
    }
    for base in [TypingLanguage.russianAbbreviations, .russianContractions, .russianContractions1k] {
      var input = fresh(base, prompt: "ёл tail")
      input.insertBatch("eл", at: start)
      XCTAssertEqual(input.typed, "eл", base.rawValue)
      XCTAssertEqual(input.errors, 1, base.rawValue)
    }
  }

  func testUnselectedDutchPrimaryExpandsOneLigatureIntoTwoJudgedEvents() throws {
    for base in [TypingLanguage.dutch, .dutch1k, .dutch10k] {
      var input = fresh(base, prompt: "ij tail")
      input.insert("ĳ", at: start)
      XCTAssertEqual(input.typed, "ij", base.rawValue)
      let result = try saved(input)
      XCTAssertEqual(result.inputMetrics?.totalAttempts, 2)
      XCTAssertEqual(result.inputMetrics?.correctAttempts, 2)
      XCTAssertEqual(result.replayEvents.map(\.text), ["i", "j"])
      XCTAssertEqual(result.replayEvents.map(\.inputPosition?.charIndex), [0, 1])
      XCTAssertEqual(result.replayEvents.map(\.offset), [0, 0])
    }
  }

  func testDutchLiteralTargetAndUppercaseLigatureAreNotExpanded() throws {
    var literal = fresh(.dutch, prompt: "ĳ tail")
    literal.insert("ĳ", at: start)
    XCTAssertEqual(literal.typed, "ĳ")
    XCTAssertEqual(try saved(literal).inputMetrics?.totalAttempts, 1)
    var upper = fresh(.dutch, prompt: "IJ tail")
    upper.insert("Ĳ", at: start)
    XCTAssertEqual(upper.typed, "Ĳ")
    XCTAssertEqual(upper.errors, 1)
    XCTAssertEqual(try saved(upper).inputMetrics?.totalAttempts, 1)
  }

  func testCandidateLanguageDoesNotEnablePrimaryNormalization() {
    for (target, entered) in [("ё", "e"), ("ij", "ĳ")] {
      var input = fresh(.english, prompt: target + " tail", selected: [.russian, .dutch])
      input.insert(entered, at: start)
      XCTAssertEqual(input.typed, entered)
      XCTAssertEqual(input.errors, 1)
    }
  }

  func testDirectionCorrectionUsesResolvedPrimaryInsteadOfOriginalDutchOrRussian() {
    for (base, target, entered) in [(TypingLanguage.dutch, "ij", "ĳ"), (.russian, "ё", "e")] {
      var input = fresh(base, prompt: target + " tail", selected: [.arabic, .hebrew])
      XCTAssertEqual(input.configuration.polyglotBaseLanguage, .arabic)
      input.insert(entered, at: start)
      XCTAssertEqual(input.typed, entered)
      XCTAssertEqual(input.errors, 1)
    }
  }

  func testDutchBatchExpansionAndNoSpaceTargetsRetainTheirPositions() throws {
    var batch = fresh(.dutch, prompt: "ijx tail")
    batch.insertBatch("ĳx", at: start)
    XCTAssertEqual(batch.typed, "ijx")
    XCTAssertEqual(try saved(batch).replayEvents.map(\.inputPosition?.charIndex), [0, 1, 2])
    let configuration = fresh(.russian, prompt: "unused").configuration.with(modifiers: [.noSpaces])
    var noSpace = TypingSession(configuration: configuration, prompt: "ёлtail",
      noSpaceWordEndIndices: [2, 6], noSpaceTargetWords: ["ёл", "tail"])
    noSpace.insertBatch("eл", at: start)
    XCTAssertEqual(noSpace.typed, "ёл")
    XCTAssertEqual(noSpace.completedWordCount, 1)
    XCTAssertEqual(noSpace.errors, 0)
  }

  func testLegacyPrimaryAndEarlierInputMarkersDoNotChangeOldNormalization() throws {
    for (base, target, entered) in [(TypingLanguage.russian, "ё", "e"), (.dutch, "ij", "ĳ")] {
      var configuration = requested(base)
      configuration.polyglotUsesPrimaryDirection = true
      configuration.polyglotUsesPrimaryCodeInput = true
      let restored = try JSONDecoder().decode(TestConfiguration.self, from: JSONEncoder().encode(configuration))
      XCTAssertEqual(restored, configuration)
      var input = TypingSession(configuration: restored, prompt: target + " tail")
      input.insert(entered, at: start)
      XCTAssertEqual(input.typed, entered)
      XCTAssertEqual(input.errors, 1)
      XCTAssertEqual(input.repeatedAttempt().configuration, configuration)
    }
  }

  func testFreshMarkerSurvivesResultsArchiveShareSelectionAndRepeat() throws {
    var input = fresh(.russian, prompt: "ёл tail")
    XCTAssertEqual(input.configuration.polyglotUsesPrimaryInputNormalization, true)
    input.insertBatch("eл", at: start)
    let result = try saved(input)
    let imported = try XCTUnwrap(TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [])).results.first)
    XCTAssertEqual(imported, result)
    let preset = SavedTestPreset(configuration: result.configuration, quoteID: nil, customText: nil)
    XCTAssertEqual(try TestConfigurationShare.preset(from: TestConfigurationShare.link(for: preset)).configuration,
      result.configuration)
    let document = ActiveTestSelectionDocument(preset: preset, testParameterMemory: .defaults)
    let restored = try XCTUnwrap(ActiveTestSelectionPolicy.validated(
      JSONDecoder().decode(ActiveTestSelectionDocument.self, from: JSONEncoder().encode(document))))
    XCTAssertEqual(restored.preset.configuration, result.configuration)
    var repeated = input.repeatedAttempt()
    XCTAssertEqual(repeated.configuration, result.configuration)
    XCTAssertEqual(repeated.prompt, input.prompt)
    repeated.insertBatch("eл", at: start.addingTimeInterval(1))
    XCTAssertEqual(repeated.typed, "ёл")
    XCTAssertEqual(repeated.errors, 0)
  }

  func testLegacyArchiveRetainsSpellingFixedMetricsAndMissingMarker() throws {
    var input = TypingSession(configuration: requested(.russian), prompt: "ёл tail")
    input.insertBatch("eл", at: start)
    let result = try saved(input)
    let imported = try XCTUnwrap(TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [])).results.first)
    XCTAssertEqual(imported, result)
    XCTAssertNil(imported.configuration.polyglotUsesPrimaryInputNormalization)
    XCTAssertEqual(imported.replayEvents.map(\.text), ["e", "л"])
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let oldData = try encoder.encode(imported.configuration)
    let decoded = try JSONDecoder().decode(TestConfiguration.self, from: oldData)
    XCTAssertEqual(try encoder.encode(decoded), oldData)
    var repeated = input.repeatedAttempt()
    repeated.insertBatch("eл", at: start.addingTimeInterval(1))
    XCTAssertEqual(repeated.typed, "eл")
    XCTAssertEqual(repeated.errors, 1)
  }

  func testFalseAndOrphanMarkersCannotEnableForeignNormalization() throws {
    var old = requested(.russian)
    old.polyglotUsesPrimaryInputNormalization = false
    let decoded = try JSONDecoder().decode(TestConfiguration.self, from: JSONEncoder().encode(old))
    XCTAssertEqual(decoded, old)
    XCTAssertEqual(decoded.inputNormalizationLanguage, .mixedLanguages)
    var input = TypingSession(configuration: decoded, prompt: "ё tail")
    input.insert("e", at: start)
    XCTAssertEqual(input.typed, "e")
    XCTAssertEqual(input.errors, 1)
    for language in [TypingLanguage.english, .mixedLanguages] {
      var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
      object["language"] = language.rawValue
      object.removeValue(forKey: "polyglotBaseLanguage")
      object["polyglotUsesPrimaryInputNormalization"] = true
      let orphan = try JSONDecoder().decode(TestConfiguration.self, from: JSONSerialization.data(withJSONObject: object))
      XCTAssertNil(orphan.polyglotUsesPrimaryInputNormalization)
      XCTAssertEqual(orphan.inputNormalizationLanguage, language)
    }
  }

  func testRemovingPrimaryClearsNormalizationWhileOtherChangesKeepIt() {
    let configuration = fresh(.dutch, prompt: "ij tail").configuration
    for base in [TypingLanguage?.none, .mixedLanguages] {
      let cleared = configuration.with(polyglotBaseLanguage: base)
      XCTAssertNil(cleared.polyglotBaseLanguage)
      XCTAssertNil(cleared.polyglotUsesPrimaryInputNormalization)
      XCTAssertEqual(cleared.inputNormalizationLanguage, .mixedLanguages)
    }
    let modified = configuration.with(modifiers: [.noSpaces])
    XCTAssertEqual(modified.polyglotUsesPrimaryInputNormalization, true)
    XCTAssertEqual(modified.inputNormalizationLanguage, .dutch)
    XCTAssertNil(TestSessionFactory.make(configuration: .words(1, language: .russian))
      .configuration.polyglotUsesPrimaryInputNormalization)
  }

  func testGlobalPunctuationAndCanonicalIdentityRemainIndependentOfPrimary() {
    for base in [TypingLanguage.russian, .dutch, .english] {
      var punctuation = fresh(base, prompt: "' tail")
      punctuation.insert("’", at: start)
      XCTAssertEqual(punctuation.typed, "'")
      XCTAssertEqual(punctuation.errors, 0)
      var canonical = fresh(base, prompt: "é tail")
      canonical.insertBatch("e\u{0301}", at: start)
      XCTAssertEqual(Array(canonical.typed.utf16), [101, 769])
      XCTAssertGreaterThan(canonical.errors, 0)
    }
  }

  func testDeletionAndReentryUseActualFieldPositionWithoutErasingAttempts() throws {
    for (base, target, entered, retained, retry) in [
      (TypingLanguage.russian, "ёл", "e", "", "e"), (.dutch, "ij", "ĳ", "i", "j")
    ] {
      var input = fresh(base, prompt: target + " tail")
      input.insert(entered, at: start)
      input.deleteBackward(at: start.addingTimeInterval(1))
      XCTAssertEqual(input.typed, retained)
      input.insert(retry, at: start.addingTimeInterval(2))
      XCTAssertEqual(input.typed, base == .russian ? "ё" : "ij")
      XCTAssertEqual(input.errors, 0)
      let result = try saved(input)
      XCTAssertEqual(result.inputMetrics?.totalAttempts, base == .russian ? 2 : 3)
      XCTAssertEqual(result.replayEvents.last?.inputPosition?.charIndex, base == .russian ? 0 : 1)
      XCTAssertEqual(result.replayEvents.filter { $0.kind == .delete }.count, 1)
    }
  }

  func testOnlyFreshGenerationUpgradesMissingOrFalseMarkersInTimeAndWordModes() {
    for mode in [TestMode.words, .time] {
      var old = mode == .words ? requested(.russian) : .timed(seconds: 30,
        language: .mixedLanguages, mixedLanguageComponents: [.english, .french], polyglotBaseLanguage: .russian)
      old.polyglotUsesPrimaryInputNormalization = false
      var input = TestSessionFactory.make(configuration: old, streamPrompt: "ёл tail")
      XCTAssertEqual(input.configuration.polyglotUsesPrimaryInputNormalization, true)
      XCTAssertEqual(old.polyglotUsesPrimaryInputNormalization, false)
      input.insert("e", at: start)
      XCTAssertEqual(input.typed, "ё")
      XCTAssertEqual(input.errors, 0)
    }
  }
}
