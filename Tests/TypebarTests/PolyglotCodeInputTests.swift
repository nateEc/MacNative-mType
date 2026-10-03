import XCTest
@testable import Typebar

final class PolyglotCodeInputTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 100)

  private func requested(_ base: TypingLanguage = .codeSwift,
    selected: [TypingLanguage] = [.english, .french], unindent: Bool = true
  ) -> TestConfiguration {
    .words(10, rules: .init(codeUnindentOnBackspace: unindent), language: .mixedLanguages,
      mixedLanguageComponents: selected, polyglotBaseLanguage: base)
  }

  // Owned targets isolate input from catalog sampling; factory preparation is
  // real, but this does not claim complete generated-code or AppKit parity.
  private func fresh(_ requested: TestConfiguration) -> TestConfiguration {
    TestSessionFactory.make(configuration: requested, nextRandomWordIndex: { 0 },
      nextRandomPoolShuffleIndex: { $0 - 1 }).configuration
  }

  private func saved(_ input: TypingSession) throws -> CompletedTestResult {
    var ended = input
    ended.bailOut(at: start.addingTimeInterval(4))
    return try XCTUnwrap(ended.result())
  }

  func testUnselectedCodePrimaryQueuesTabsOnlyAfterCorrectCommit() throws {
    var input = TypingSession(configuration: fresh(requested()), prompt: "ab \t\tgo() tail")
    _ = input.insertBatch("ab ", at: start, defersAutomaticInput: true)
    XCTAssertEqual(input.typed, "ab ")
    XCTAssertTrue(input.hasPendingAutomaticInput)
    XCTAssertEqual(input.processNextAutomaticInput(for: input.automaticInputAttemptID), [true])
    XCTAssertEqual(input.processNextAutomaticInput(for: input.automaticInputAttemptID), [true])
    XCTAssertEqual(input.typed, "ab \t\t")
    let automatic = try saved(input).replayEvents.filter(\.automatic)
    XCTAssertEqual(automatic.map(\.text), ["\t", "\t"])
    XCTAssertEqual(automatic.map(\.offset), [0, 0])
    XCTAssertEqual(try saved(input).inputMetrics?.totalAttempts, 5)
  }

  func testManualBatchStillPrecedesDeferredAutomaticTab() throws {
    var input = TypingSession(configuration: fresh(requested()), prompt: "\t\tgo() tail")
    XCTAssertEqual(TypingLiveInputFeedback.insertBatch("\tX", into: &input, at: start,
      defersAutomaticInput: true), [false])
    XCTAssertEqual(input.typed, "\tX")
    XCTAssertEqual(input.processNextAutomaticInput(for: input.automaticInputAttemptID), [false])
    XCTAssertEqual(input.typed, "\tX\t")
    XCTAssertEqual(try saved(input).replayEvents.map(\.automatic), [false, false, true])
  }

  func testCodeCandidateDoesNotTurnOrdinaryPrimaryIntoCodeInput() throws {
    var input = TypingSession(configuration: fresh(requested(.english,
      selected: [.codeSwift, .french])), prompt: "\t\tgo() tail")
    input.insert("\t", at: start)
    XCTAssertEqual(input.typed, "\t")
    XCTAssertFalse(input.hasPendingAutomaticInput)
    XCTAssertFalse(try saved(input).replayEvents.contains(where: \.automatic))
  }

  func testDockerfilePrimaryIsNotSourceCodePrefixInput() {
    var input = TypingSession(configuration: fresh(requested(.dockerFile)), prompt: "ab \t\tgo() tail")
    input.insertBatch("ab \t\t", at: start)
    XCTAssertEqual(input.typed, "ab \t\t")
    XCTAssertFalse(input.hasPendingAutomaticInput)
    input.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(input.typed, "ab \t")
  }

  func testTabOnlyFieldUnindentKeepsTwoGroupedActionsAndDestinationPosition() throws {
    for wholeWord in [false, true] {
      var input = TypingSession(configuration: fresh(requested()), prompt: "first ab\n\t\tgo() tail")
      input.insertBatch("first ab\n", at: start)
      XCTAssertEqual(input.typed, "first ab\n\t\t")
      if wholeWord { input.deleteWordBackward(at: start.addingTimeInterval(1)) }
      else { input.deleteBackward(at: start.addingTimeInterval(1)) }
      XCTAssertEqual(input.typed, wholeWord ? "first " : "first ab")
      let deletions = try saved(input).replayEvents.filter { $0.kind == .delete }
      let positioned = deletions.filter { $0.deletionCharIndex != nil }
      XCTAssertEqual(positioned.map(\.deletionCharIndex), [2, wholeWord ? 0 : 2])
      XCTAssertEqual(positioned.map(\.inputField?.index), [2, 1])
      XCTAssertTrue(deletions.allSatisfy { $0.inputPosition == nil })
    }
  }

  func testUnindentOptionAndConfidenceStillGuardTheNewRoute() {
    var disabled = TypingSession(configuration: fresh(requested(unindent: false)), prompt: "ab \t\tgo() tail")
    disabled.insertBatch("ab ", at: start)
    disabled.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(disabled.typed, "ab \t")
    var protectedConfiguration = fresh(requested())
    protectedConfiguration.rules.confidenceMode = .maximum
    var protected = TypingSession(configuration: protectedConfiguration, prompt: "ab \t\tgo() tail")
    protected.insertBatch("ab ", at: start)
    protected.deleteWordBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(protected.typed, "ab \t\t")
  }

  func testNoSpaceFieldsUseTheSamePrimaryWithoutLosingBoundaries() {
    var input = TypingSession(configuration: fresh(requested()).with(modifiers: [.noSpaces]),
      prompt: "ab\t\tgo()tail", noSpaceWordEndIndices: [2, 8, 12],
      noSpaceTargetWords: ["ab", "\t\tgo()", "tail"])
    input.insertBatch("ab", at: start)
    XCTAssertEqual(input.typed, "ab\t\t")
    input.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(input.typed, "a")
  }

  func testControlAcceptanceFollowsTargetsNotPrimaryOrCandidate() {
    for base in [TypingLanguage.english, .codeSwift] {
      let configuration = fresh(requested(base))
      let plain = TypingSession(configuration: configuration, prompt: "ab tail")
      XCTAssertFalse(plain.acceptsTabInput)
      XCTAssertFalse(plain.acceptsNewlineInput)
      let controls = TypingSession(configuration: configuration, prompt: "ab\n\tgo() tail")
      XCTAssertTrue(controls.acceptsTabInput)
      XCTAssertTrue(controls.acceptsNewlineInput)
    }
  }

  func testLegacyCodePrimaryRemainsManualIncludingRepeat() throws {
    let configuration = requested()
    var input = TypingSession(configuration: configuration, prompt: "ab \t\tgo() tail")
    input.insertBatch("ab \t\t", at: start)
    XCTAssertFalse(try saved(input).replayEvents.contains(where: \.automatic))
    input.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(input.typed, "ab \t")
    XCTAssertEqual(input.repeatedAttempt().configuration, configuration)
    let restored = try JSONDecoder().decode(TestConfiguration.self, from: JSONEncoder().encode(configuration))
    XCTAssertEqual(restored, configuration)
  }

  func testAllNativeCodePrimaryIdentitiesUseThePrefixRouteExceptDockerfile() {
    let codes = TypingLanguage.allCases.filter(\.isCodeLanguage)
    XCTAssertFalse(codes.isEmpty)
    for code in codes {
      let configuration = PolyglotGenerationPreparation(requested(code)).configuration
      var input = TypingSession(configuration: configuration, prompt: "ab \tgo() tail")
      input.insertBatch("ab ", at: start)
      XCTAssertEqual(input.typed, code == .dockerFile ? "ab " : "ab \t", code.rawValue)
    }
  }

  func testFreshMarkerSurvivesResultArchiveShareAndOriginalTargetRepeat() throws {
    let configuration = fresh(requested())
    XCTAssertEqual(configuration.polyglotUsesPrimaryCodeInput, true)
    var input = TypingSession(configuration: configuration, prompt: "ab \tgo() tail")
    input.insertBatch("ab ", at: start)
    let result = try saved(input)
    let imported = try XCTUnwrap(TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [])).results.first)
    XCTAssertEqual(imported, result)
    XCTAssertEqual(imported.configuration.polyglotUsesPrimaryCodeInput, true)
    let preset = SavedTestPreset(configuration: configuration, quoteID: nil, customText: nil)
    XCTAssertEqual(try TestConfigurationShare.preset(from: TestConfigurationShare.link(for: preset)).configuration,
      configuration)
    var repeated = input.repeatedAttempt()
    XCTAssertEqual(repeated.configuration, configuration)
    XCTAssertEqual(repeated.prompt, input.prompt)
    repeated.insertBatch("ab ", at: start.addingTimeInterval(1))
    XCTAssertEqual(repeated.typed, "ab \t")
  }

  func testPreviousDirectionMarkerDoesNotEnableCodeInputOrBackfillOldResult() throws {
    var previous = requested()
    previous.polyglotUsesPrimaryDirection = true
    XCTAssertNil(previous.polyglotUsesPrimaryCodeInput)
    var input = TypingSession(configuration: previous, prompt: "ab \tgo() tail")
    input.insertBatch("ab ", at: start)
    XCTAssertEqual(input.typed, "ab ")
    let result = try saved(input)
    let imported = try XCTUnwrap(TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [])).results.first)
    XCTAssertEqual(imported, result)
    XCTAssertNil(imported.configuration.polyglotUsesPrimaryCodeInput)
    XCTAssertEqual(input.repeatedAttempt().configuration, previous)
    XCTAssertEqual(fresh(imported.configuration).polyglotUsesPrimaryCodeInput, true)
    XCTAssertNil(imported.configuration.polyglotUsesPrimaryCodeInput)
  }

  func testExplicitFalseAndOrphanMarkersDoNotEnableInput() throws {
    var disabled = fresh(requested())
    disabled.polyglotUsesPrimaryCodeInput = false
    let decoded = try JSONDecoder().decode(TestConfiguration.self, from: JSONEncoder().encode(disabled))
    XCTAssertEqual(decoded, disabled)
    XCTAssertFalse(decoded.usesCodeIndentationInput)
    XCTAssertNil(disabled.with(polyglotBaseLanguage: nil).polyglotUsesPrimaryCodeInput)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(disabled)) as? [String: Any])
    object.removeValue(forKey: "polyglotBaseLanguage")
    object["polyglotUsesPrimaryCodeInput"] = true
    let orphan = try JSONDecoder().decode(TestConfiguration.self, from: JSONSerialization.data(withJSONObject: object))
    XCTAssertNil(orphan.polyglotUsesPrimaryCodeInput)
    XCTAssertFalse(orphan.usesCodeIndentationInput)
    XCTAssertNil(TestSessionFactory.make(configuration: .words(1)).configuration.polyglotUsesPrimaryCodeInput)
  }

  func testDirectionCorrectionUsesResolvedNonCodePrimaryForInput() {
    let configuration = fresh(requested(selected: [.arabic, .hebrew]))
    XCTAssertEqual(configuration.polyglotBaseLanguage, .arabic)
    XCTAssertEqual(configuration.polyglotUsesPrimaryCodeInput, true)
    var input = TypingSession(configuration: configuration, prompt: "ab \t\tgo() tail")
    input.insertBatch("ab ", at: start)
    XCTAssertEqual(input.typed, "ab ")
    XCTAssertFalse(input.hasPendingAutomaticInput)
  }

  func testIncorrectCommitDoesNotQueueTabsAndStoppedInputDoesNotNavigate() {
    var input = TypingSession(configuration: fresh(requested()), prompt: "ab \t\tgo() tail")
    input.insertBatch("a ", at: start)
    XCTAssertFalse(input.hasPendingAutomaticInput)
    XCTAssertEqual(input.typed, "a ")
    var configuration = fresh(requested())
    configuration.rules.stopOnErrorMode = .letter
    var stopped = TypingSession(configuration: configuration, prompt: "ab \t\tgo() tail")
    stopped.insertBatch("a ", at: start)
    XCTAssertEqual(stopped.typed, "a")
    XCTAssertFalse(stopped.hasPendingAutomaticInput)
  }

  func testRepeatedAttemptRejectsOldCallbackWithoutConsumingNewQueue() {
    var old = TypingSession(configuration: fresh(requested()), prompt: "\t\tgo() tail")
    old.insertBatch("\t", at: start, defersAutomaticInput: true)
    var repeated = old.repeatedAttempt()
    repeated.insertBatch("\t", at: start.addingTimeInterval(1), defersAutomaticInput: true)
    XCTAssertEqual(repeated.processNextAutomaticInput(for: old.automaticInputAttemptID), [])
    XCTAssertEqual(repeated.typed, "\t")
    XCTAssertTrue(repeated.hasPendingAutomaticInput)
    XCTAssertEqual(repeated.processNextAutomaticInput(for: repeated.automaticInputAttemptID), [true])
    XCTAssertEqual(repeated.typed, "\t\t")
  }
}
