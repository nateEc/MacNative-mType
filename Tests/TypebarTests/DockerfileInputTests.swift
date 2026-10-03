import XCTest
@testable import Typebar

final class DockerfileInputTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 200)

  private func configuration(unindent: Bool = true) -> TestConfiguration {
    .words(10, rules: .init(codeUnindentOnBackspace: unindent), language: .dockerFile)
  }

  // The stream target is owned input evidence, not upstream Dockerfile text.
  // This exercises the actual fresh factory and input engine, not AppKit.
  private func fresh(_ prompt: String = "ab \t\tgo() tail", unindent: Bool = true) -> TypingSession {
    TestSessionFactory.make(configuration: configuration(unindent: unindent), streamPrompt: prompt)
  }

  private func saved(_ input: TypingSession) throws -> CompletedTestResult {
    var ended = input
    ended.bailOut(at: start.addingTimeInterval(4))
    return try XCTUnwrap(ended.result())
  }

  func testFreshDockerfileDoesNotQueueOrAutomaticallyInsertTabsAfterCommit() throws {
    var input = fresh()
    input.insertBatch("ab ", at: start, defersAutomaticInput: true)
    XCTAssertEqual(input.typed, "ab ")
    XCTAssertFalse(input.hasPendingAutomaticInput)
    XCTAssertEqual(input.processNextAutomaticInput(for: input.automaticInputAttemptID), [])
    XCTAssertEqual(input.typed, "ab ")
    XCTAssertFalse(try saved(input).replayEvents.contains(where: \.automatic))
    XCTAssertEqual(try saved(input).inputMetrics?.totalAttempts, 3)
  }

  func testCorrectManualLeadingTabDoesNotCascadeAnotherTab() throws {
    var input = fresh("\t\tgo() tail")
    input.insert("\t", at: start)
    XCTAssertEqual(input.typed, "\t")
    XCTAssertFalse(input.hasPendingAutomaticInput)
    XCTAssertEqual(try saved(input).replayEvents.map(\.automatic), [false])
  }

  func testCharacterDeletionRemovesOnlyOneTabInCurrentField() throws {
    var input = fresh()
    input.insertBatch("ab \t\t", at: start, defersAutomaticInput: true)
    input.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(input.typed, "ab \t")
    let deletions = try saved(input).replayEvents.filter { $0.kind == .delete }
    XCTAssertEqual(deletions.count, 1)
    XCTAssertEqual(deletions.compactMap(\.deletionCharIndex), [2])
    XCTAssertEqual(deletions.compactMap(\.inputField?.index), [1])
    XCTAssertTrue(deletions.allSatisfy { $0.wordDeletionCount == nil && $0.characterDeletionCount == nil })
  }

  func testWholeWordDeletionClearsTabsWithoutReopeningPreviousField() throws {
    var input = fresh()
    input.insertBatch("ab \t\t", at: start, defersAutomaticInput: true)
    input.deleteWordBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(input.typed, "ab ")
    let deletions = try saved(input).replayEvents.filter { $0.kind == .delete }
    XCTAssertEqual(deletions.count, 2)
    XCTAssertEqual(deletions.compactMap(\.deletionCharIndex), [2])
    XCTAssertEqual(deletions.last?.inputField?.index, 1)
    XCTAssertEqual(deletions.first?.wordDeletionCount, 2)
  }

  func testCodeUnindentOptionDoesNotChangeFreshDockerfileDeletion() {
    for enabled in [false, true] {
      var input = fresh(unindent: enabled)
      input.insertBatch("ab \t\t", at: start, defersAutomaticInput: true)
      input.deleteBackward(at: start.addingTimeInterval(1))
      XCTAssertEqual(input.typed, "ab \t")
    }
  }

  func testNoSpaceHiddenFieldsKeepOrdinaryTabDeletion() {
    let prepared = fresh().configuration.with(modifiers: [.noSpaces])
    var input = TypingSession(configuration: prepared, prompt: "ab\t\tgo()tail",
      noSpaceWordEndIndices: [2, 8, 12], noSpaceTargetWords: ["ab", "\t\tgo()", "tail"])
    input.insertBatch("ab\t\t", at: start, defersAutomaticInput: true)
    XCTAssertFalse(input.hasPendingAutomaticInput)
    input.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(input.typed, "ab\t")
  }

  func testExistingCodePrefixLanguageStillAutoIndentsAndUnindents() {
    var input = TestSessionFactory.make(configuration: .words(10,
      rules: .init(codeUnindentOnBackspace: true), language: .codeSwift),
      streamPrompt: "ab \t\tgo() tail")
    input.insertBatch("ab ", at: start)
    XCTAssertEqual(input.typed, "ab \t\t")
    input.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(input.typed, "ab")
  }

  func testLegacyDockerfileRetainsAutomaticInputAndUnindentOnRepeat() throws {
    let original = configuration()
    var input = TypingSession(configuration: original, prompt: "ab \t\tgo() tail")
    input.insertBatch("ab ", at: start)
    XCTAssertEqual(input.typed, "ab \t\t")
    XCTAssertEqual(try saved(input).replayEvents.filter(\.automatic).map(\.text), ["\t", "\t"])
    input.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(input.typed, "ab")
    var repeated = input.repeatedAttempt()
    XCTAssertEqual(repeated.configuration, original)
    repeated.insertBatch("ab ", at: start.addingTimeInterval(2))
    XCTAssertEqual(repeated.typed, "ab \t\t")
  }

  func testFreshMarkerSurvivesResultsArchiveShareSelectionAndRepeat() throws {
    var input = fresh()
    XCTAssertEqual(input.configuration.dockerfileUsesLiteralIndentation, true)
    input.insertBatch("ab \t", at: start)
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
    repeated.insertBatch("ab ", at: start.addingTimeInterval(1))
    XCTAssertEqual(repeated.typed, "ab ")
    XCTAssertFalse(repeated.hasPendingAutomaticInput)
  }

  func testLegacyArchiveRoundTripsWithoutBackfillOrScoreChanges() throws {
    var input = TypingSession(configuration: configuration(), prompt: "ab \t\tgo() tail")
    input.insertBatch("ab ", at: start)
    let result = try saved(input)
    let imported = try XCTUnwrap(TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [])).results.first)
    XCTAssertEqual(imported, result)
    XCTAssertNil(imported.configuration.dockerfileUsesLiteralIndentation)
    XCTAssertEqual(input.repeatedAttempt().configuration, imported.configuration)
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let oldData = try encoder.encode(imported.configuration)
    let decoded = try JSONDecoder().decode(TestConfiguration.self, from: oldData)
    XCTAssertEqual(try encoder.encode(decoded), oldData)
    XCTAssertTrue(decoded.usesCodeIndentationInput)
    let newAttempt = TestSessionFactory.make(configuration: decoded, streamPrompt: result.prompt)
    XCTAssertEqual(newAttempt.configuration.dockerfileUsesLiteralIndentation, true)
    XCTAssertNil(decoded.dockerfileUsesLiteralIndentation)
  }

  func testFalseAndForeignLanguageMarkersCannotDisableAnotherCodeLanguage() throws {
    var legacy = configuration()
    legacy.dockerfileUsesLiteralIndentation = false
    let decoded = try JSONDecoder().decode(TestConfiguration.self, from: JSONEncoder().encode(legacy))
    XCTAssertEqual(decoded, legacy)
    XCTAssertTrue(decoded.usesCodeIndentationInput)
    for language in [TypingLanguage.codeSwift, .english, .mixedLanguages] {
      var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
      object["language"] = language.rawValue
      object["dockerfileUsesLiteralIndentation"] = true
      let foreign = try JSONDecoder().decode(TestConfiguration.self, from: JSONSerialization.data(withJSONObject: object))
      XCTAssertNil(foreign.dockerfileUsesLiteralIndentation)
      XCTAssertEqual(foreign.usesCodeIndentationInput, language == .codeSwift)
    }
    XCTAssertNil(TestSessionFactory.make(configuration: .words(1)).configuration.dockerfileUsesLiteralIndentation)
  }

  func testActualOwnedDockerfileGenerationStillCompletesWithoutAutomaticInput() throws {
    var input = TestSessionFactory.make(configuration: .words(6, language: .dockerFile),
      nextRandomWordIndex: { 0 })
    XCTAssertTrue(input.configuration.language.isCodeLanguage)
    XCTAssertEqual(input.configuration.dockerfileUsesLiteralIndentation, true)
    XCTAssertFalse(input.prompt.isEmpty)
    input.insertBatch(input.prompt, at: start)
    XCTAssertEqual(input.outcome, .completed)
    XCTAssertEqual(input.errors, 0)
    XCTAssertFalse(try XCTUnwrap(input.result()).replayEvents.contains(where: \.automatic))
  }

  func testConfidenceAndActualControlAcceptanceAreUnchanged() {
    var protectedConfiguration = fresh().configuration
    protectedConfiguration.rules.confidenceMode = .maximum
    var protected = TypingSession(configuration: protectedConfiguration, prompt: "ab \t\tgo() tail")
    protected.insertBatch("ab \t\t", at: start)
    protected.deleteBackward(at: start.addingTimeInterval(1))
    protected.deleteWordBackward(at: start.addingTimeInterval(2))
    XCTAssertEqual(protected.typed, "ab \t\t")
    let plain = fresh("ab tail")
    XCTAssertFalse(plain.acceptsTabInput)
    XCTAssertFalse(plain.acceptsNewlineInput)
    let controls = fresh("ab\n\t\tgo() tail")
    XCTAssertTrue(controls.acceptsTabInput)
    XCTAssertTrue(controls.acceptsNewlineInput)
  }

  func testLiteralManualVirtualInputKeepsItsOriginAndAttemptCount() throws {
    var input = fresh()
    input.insertBatch("ab \t\t", at: start, origin: .virtualKeyboard)
    XCTAssertEqual(input.typed, "ab \t\t")
    XCTAssertTrue(input.hasUsedOnlyVirtualKeyboard)
    XCTAssertFalse(input.hasPendingAutomaticInput)
    XCTAssertEqual(try saved(input).inputMetrics?.totalAttempts, 5)
    XCTAssertFalse(try saved(input).replayEvents.contains(where: \.automatic))
  }

  func testFreshTimeAndCustomFactoriesUseLiteralIndentationWithoutChangingRules() {
    let requests = [TestConfiguration.timed(seconds: 30, language: .dockerFile),
      .init(mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal,
        rules: .init(codeUnindentOnBackspace: true), language: .dockerFile)]
    for requested in requests {
      var input = TestSessionFactory.make(configuration: requested, customText: "ab \t\tgo() tail",
        streamPrompt: "ab \t\tgo() tail")
      XCTAssertEqual(input.configuration.dockerfileUsesLiteralIndentation, true)
      XCTAssertEqual(input.configuration.rules, requested.rules)
      input.insertBatch("ab ", at: start)
      XCTAssertEqual(input.typed, "ab ")
      XCTAssertFalse(input.hasPendingAutomaticInput)
    }
  }
}
