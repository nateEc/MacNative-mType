import XCTest
@testable import Typebar

final class ZenInputAdmissionTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 400)
  private let spaces = [" ", "\u{2002}", "\u{2003}", "\u{2009}", "\u{3000}", "\u{00a0}",
    "\u{1680}", "\u{202f}", "\u{feff}", "\u{2007}", "\u{2008}", "\u{2004}", "\u{200a}", "\u{200b}"]

  private func configuration(rules: InputRules = .init(), difficulty: Difficulty = .normal,
    language: TypingLanguage = .english) -> TestConfiguration {
    .init(mode: .zen, duration: nil, wordLimit: nil, difficulty: difficulty, rules: rules, language: language)
  }

  private func fresh(rules: InputRules = .init(), difficulty: Difficulty = .normal,
    language: TypingLanguage = .english) -> TypingSession {
    TestSessionFactory.make(configuration: configuration(rules: rules, difficulty: difficulty, language: language))
  }

  private func saved(_ session: TypingSession) throws -> CompletedTestResult {
    var ended = session
    ended.finishZen(at: start.addingTimeInterval(4))
    return try XCTUnwrap(ended.result())
  }

  func testPlatformSpacesNormalizeBeforeFreeformFieldCommit() throws {
    for space in spaces {
      var input = fresh()
      XCTAssertEqual(input.prompt, "")
      input.insertBatch("a" + space + "b", at: start)
      XCTAssertEqual(Array(input.typed.utf16), [97, 32, 98])
      let result = try saved(input)
      XCTAssertEqual(result.replayEvents.map(\.text), ["a", " ", "b"])
      XCTAssertEqual(result.replayEvents.map(\.inputField?.index), [0, 0, 1])
      XCTAssertEqual(result.replayEvents.last?.inputField?.units, [98])
      XCTAssertEqual(result.inputMetrics?.totalAttempts, 3)
      XCTAssertEqual(result.inputMetrics?.correctAttempts, 3)
    }
  }

  func testLeadingSpaceFollowsStrictSpaceAndDifficultyButNotHardDeletion() throws {
    for strict in [false, true] {
      for difficulty in [Difficulty.normal, .expert, .master] {
        var input = fresh(rules: .init(strictSpace: strict), difficulty: difficulty)
        input.insert("\u{3000}", at: start)
        let allowed = strict || difficulty != .normal
        XCTAssertEqual(input.typed, allowed ? " " : "")
        XCTAssertEqual(input.hasStarted, allowed)
        input.insert("x", at: start.addingTimeInterval(1))
        XCTAssertEqual(try saved(input).inputMetrics?.totalAttempts, allowed ? 2 : 1)
        XCTAssertEqual(input.outcome, .active)
      }
    }
    for mode in [DeleteOnErrorMode.letterHard, .wordHard] {
      var input = fresh(rules: .init(deleteOnErrorMode: mode))
      input.insert(" ", at: start)
      XCTAssertEqual(input.typed, "")
      XCTAssertFalse(input.hasStarted)
    }
  }

  func testOrdinaryLeadingSpacesAreRejectedBeforeOppositeShiftScoring() {
    for space in spaces {
      var input = fresh(rules: .init(oppositeShiftMode: .on))
      input.insertBatch(space, forceError: true, at: start)
      XCTAssertEqual(input.typed, "")
      XCTAssertFalse(input.hasStarted)
      XCTAssertNil(input.result())
    }
  }

  func testThirtyUnitCapStillAllowsNormalizedSpaceAndNewlineToAdvance() throws {
    for commit in ["\u{3000}", " ", "\n"] {
      var input = fresh()
      input.insertBatch(String(repeating: "a", count: 30) + "z" + commit + "b", at: start)
      XCTAssertEqual(input.typed, String(repeating: "a", count: 30) + (commit == "\n" ? "\n" : " ") + "b")
      let result = try saved(input)
      XCTAssertEqual(result.inputMetrics?.totalAttempts, 32)
      XCTAssertEqual(result.replayEvents.last?.inputField?.index, 1)
      XCTAssertEqual(result.replayEvents.last?.inputField?.units, [98])
    }
  }

  func testCapPrecedesOppositeShiftAndCountsUTF16RatherThanGlyphs() throws {
    var input = fresh(rules: .init(oppositeShiftMode: .on))
    input.insertBatch(String(repeating: "🙂", count: 15), at: start)
    XCTAssertEqual(input.typed.utf16.count, 30)
    input.insertBatch("x", forceError: true, at: start.addingTimeInterval(1))
    let result = try saved(input)
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 30)
    XCTAssertEqual(result.replayEvents.count, 30)
  }

  func testFreeformHasNoTargetForRussianOrPunctuationEquivalence() throws {
    for language in [TypingLanguage.russian, .dutch, .english] {
      var input = fresh(language: language)
      input.insertBatch("ёеe’—", at: start)
      XCTAssertEqual(Array(input.typed.utf16), Array("ёеe’—".utf16))
      XCTAssertEqual(input.errors, 0)
      XCTAssertEqual(try saved(input).inputMetrics?.correctAttempts, 5)
    }
  }

  func testForbiddenNoSpaceModeIsSanitizedButDirectInputStillHonorsItsAdmissionGuard() {
    let request = configuration().with(modifiers: [.noSpaces])
    XCTAssertFalse(request.modifiers.contains(.noSpaces))
    var bypassed = fresh().configuration
    // Explicit low-level bypass fixture, NOT an accepted UI configuration.
    bypassed.modifiers = [.noSpaces]
    var input = TypingSession(configuration: bypassed, prompt: "")
    input.insertBatch(spaces.joined(), at: start)
    XCTAssertEqual(input.typed, "")
    XCTAssertFalse(input.hasStarted)
    input.insertBatch("a\nb", at: start)
    XCTAssertEqual(input.typed, "a\nb")
  }

  func testAcceptedZenEventsCarryEmptyTargetUTF16Positions() throws {
    var input = fresh()
    input.insertBatch("🙂 a\n", at: start)
    let result = try saved(input)
    XCTAssertEqual(result.replayEvents.map(\.inputPosition?.charIndex), [0, 1, 2, 0, 1])
    XCTAssertEqual(result.replayEvents.map(\.inputPosition?.lastWord), [false, false, false, false, false])
    XCTAssertEqual(result.replayEvents.map(\.inputField?.index), [0, 0, 0, 1, 1])
  }

  func testFreshMarkerSurvivesArchiveShareActiveSelectionAndRepeat() throws {
    var input = fresh()
    XCTAssertEqual(input.configuration.zenUsesSourceInputAdmission, true)
    input.insertBatch("a\u{3000}b", at: start)
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
    // This tests the existing low-level native repeat API. Source Zen UI
    // repeat is disabled; parity of that command is a separate open boundary.
    var repeated = input.repeatedAttempt()
    XCTAssertEqual(repeated.configuration, result.configuration)
    repeated.insertBatch("c\u{2002}d", at: start.addingTimeInterval(1))
    XCTAssertEqual(repeated.typed, "c d")
  }

  func testLegacyArchiveRetainsLiteralSpacesAndCapturedMetricsWithoutBackfill() throws {
    let old = configuration(rules: .init(strictSpace: true))
    var input = TypingSession(configuration: old, prompt: "")
    input.insert(" ", at: start)
    XCTAssertFalse(input.hasStarted)
    input.insertBatch("a\u{3000}b", at: start)
    let result = try saved(input)
    let imported = try XCTUnwrap(TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [])).results.first)
    XCTAssertEqual(imported, result)
    XCTAssertNil(imported.configuration.zenUsesSourceInputAdmission)
    XCTAssertEqual(imported.replayEvents.map(\.text), ["a", "\u{3000}", "b"])
    XCTAssertTrue(imported.replayEvents.allSatisfy { $0.inputPosition == nil })
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(imported.configuration)
    let restored = try JSONDecoder().decode(TestConfiguration.self, from: data)
    XCTAssertEqual(try encoder.encode(restored), data)
    var repeated = input.repeatedAttempt()
    repeated.insertBatch("a\u{3000}b", at: start.addingTimeInterval(1))
    XCTAssertEqual(repeated.typed, "a\u{3000}b")
    XCTAssertEqual(repeated.configuration, old)
    XCTAssertEqual(TestSessionFactory.make(configuration: restored).configuration.zenUsesSourceInputAdmission, true)
    XCTAssertNil(restored.zenUsesSourceInputAdmission)
  }

  func testFalseAndForeignModeMarkersPreserveHistoricalOrOrdinaryBehavior() throws {
    var old = configuration()
    old.zenUsesSourceInputAdmission = false
    let decoded = try JSONDecoder().decode(TestConfiguration.self, from: JSONEncoder().encode(old))
    XCTAssertEqual(decoded, old)
    var input = TypingSession(configuration: decoded, prompt: "")
    input.insertBatch("a\u{3000}b", at: start)
    XCTAssertEqual(input.typed, "a\u{3000}b")
    for mode in [TestMode.words, .time, .quote, .custom] {
      var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
      object["mode"] = mode.rawValue
      object["zenUsesSourceInputAdmission"] = true
      let foreign = try JSONDecoder().decode(TestConfiguration.self, from: JSONSerialization.data(withJSONObject: object))
      XCTAssertNil(foreign.zenUsesSourceInputAdmission)
    }
    let memory = fresh().configuration.with(modifiers: [.memory])
    XCTAssertNotEqual(memory.mode, .zen)
    XCTAssertNil(memory.zenUsesSourceInputAdmission)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(fresh().configuration)) as? [String: Any])
    object["modifiers"] = [TestModifier.memory.rawValue]
    let restoredMemory = try JSONDecoder().decode(TestConfiguration.self, from: JSONSerialization.data(withJSONObject: object))
    XCTAssertNotEqual(restoredMemory.mode, .zen)
    XCTAssertNil(restoredMemory.zenUsesSourceInputAdmission)
    XCTAssertNil(TestSessionFactory.make(configuration: .words(1)).configuration.zenUsesSourceInputAdmission)
  }

  func testStrictBlankFieldsAndLeadingNewlinesKeepSourcePositions() throws {
    var strict = fresh(rules: .init(strictSpace: true))
    strict.insertBatch("  \n\tb", at: start)
    XCTAssertEqual(strict.typed, "  \n\tb")
    let result = try saved(strict)
    XCTAssertEqual(result.replayEvents.map(\.inputField?.index), [0, 1, 2, 3, 3])
    XCTAssertEqual(result.replayEvents.map(\.inputPosition?.charIndex), [0, 0, 0, 0, 1])
    var ordinary = fresh()
    ordinary.insertBatch("\n\nx", at: start)
    XCTAssertEqual(ordinary.typed, "\n\nx")
    XCTAssertEqual(try saved(ordinary).replayEvents.map(\.inputField?.index), [0, 1, 2])
  }

  func testDeletionReentersActualFieldAndNormalizesNextCommit() throws {
    var input = fresh()
    input.insertBatch("a\u{3000}b", at: start)
    input.deleteBackward(at: start.addingTimeInterval(1))
    input.deleteBackward(at: start.addingTimeInterval(2))
    XCTAssertEqual(input.typed, "a")
    input.insertBatch("\u{2003}c", at: start.addingTimeInterval(3))
    XCTAssertEqual(input.typed, "a c")
    let result = try saved(input)
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 5)
    XCTAssertEqual(result.replayEvents.last?.inputPosition?.charIndex, 0)
    XCTAssertEqual(result.replayEvents.last?.inputField?.index, 1)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 4), "a c")
  }

  func testUnknownWhitespaceTabAndCRRemainLiteralWhileLFCommits() throws {
    for text in ["a\u{2005}b", "a\rb", "a\tb", "a\r\nb"] {
      var input = fresh()
      input.insertBatch(text, at: start)
      XCTAssertEqual(Array(input.typed.utf16), Array(text.utf16))
      let result = try saved(input)
      XCTAssertEqual(result.inputMetrics?.totalAttempts, text.utf16.count)
      XCTAssertEqual(result.replayEvents.last?.inputField?.index, text.utf16.contains(10) ? 1 : 0)
    }
  }

  func testExistingEllipsisAndDutchOverridesRemainTargetlessAndRespectCap() throws {
    for (language, entered, retained) in [(TypingLanguage.dutch, "ĳ", "ij"),
      (.english, "ĳ", "ĳ"), (.english, "…", "...")] {
      var input = fresh(language: language)
      input.insert(entered, at: start)
      XCTAssertEqual(input.typed, retained)
      XCTAssertEqual(try saved(input).inputMetrics?.totalAttempts, retained.utf16.count)
    }
    for (language, entered, last) in [(TypingLanguage.dutch, "ĳ", "i"), (.english, "…", ".")] {
      var input = fresh(language: language)
      input.insertBatch(String(repeating: "a", count: 29) + entered, at: start)
      XCTAssertEqual(input.typed, String(repeating: "a", count: 29) + last)
      XCTAssertEqual(try saved(input).inputMetrics?.totalAttempts, 30)
    }
  }

  func testAdmittedOppositeShiftSpaceStartsButDoesNotCommitOrRetainText() throws {
    var input = fresh(rules: .init(strictSpace: true, oppositeShiftMode: .on))
    input.insertBatch("\u{3000}", forceError: true, at: start)
    XCTAssertTrue(input.hasStarted)
    XCTAssertEqual(input.typed, "")
    let result = try saved(input)
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 1)
    XCTAssertEqual(result.inputMetrics?.correctAttempts, 1)
    XCTAssertEqual(result.replayEvents.first?.text, " ")
    XCTAssertEqual(result.replayEvents.first?.inputPosition?.charIndex, 0)
    XCTAssertEqual(result.replayEvents.first?.inputField?.index, 0)
    XCTAssertEqual(result.replayEvents.first?.inputField?.units, [])
    XCTAssertEqual(result.replayEvents.first?.inputStopped, true)
  }

  func testFreshZenIgnoresInjectedTargetContentRatherThanChangingFreeformOverrides() throws {
    var input = TestSessionFactory.make(configuration: configuration(),
      customText: "owned custom", finiteTextSource: "owned finite", streamPrompt: "… target",
      streamNoSpaceBoundarySource: "owned hidden")
    XCTAssertEqual(input.prompt, "")
    input.insert("…", at: start)
    XCTAssertEqual(input.typed, "...")
    XCTAssertEqual(try saved(input).inputMetrics?.totalAttempts, 3)
  }
}
