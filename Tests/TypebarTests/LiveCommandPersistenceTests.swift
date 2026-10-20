import XCTest
@testable import Typebar

@MainActor
final class LiveCommandPersistenceTests: XCTestCase {
  private func withSettings(_ body: (AppSettings, UserDefaults) throws -> Void) rethrows {
    let suite = "typebar.live-command-save.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(AppSettings(defaults: defaults), defaults)
  }

  func testSuccessfulLiveCommandsSaveAfterTheirValuesAreAppliedIncludingSameValueEvents() throws {
    try withSettings { settings, _ in
      var calls = 0
      let commit = { calls += 1 }
      SoundCommandTarget.volume(0.4).apply(to: settings, onConfigurationSave: {
        XCTAssertEqual(settings.soundVolume, 0.4); commit()
      })
      CaretCommandTarget.repeatedPace(true).apply(to: settings, onConfigurationSave: {
        XCTAssertTrue(settings.repeatedPace); commit()
      })
      PaceCaretCommandTarget.mode(.off).apply(to: settings, onConfigurationSave: commit)
      XCTAssertTrue(AppearanceCommandTarget.showAllLines(false).apply(to: settings, onConfigurationSave: commit))
      KeyboardGuideCommandTarget.mode(.off).apply(to: settings, onConfigurationSave: commit)
      BehaviorCommandTarget.blindMode(true).apply(to: settings, onConfigurationSave: commit)
      XCTAssertTrue(ThemeCommandApplication.apply(.builtIn(.grove), to: settings, onConfigurationSave: {
        XCTAssertEqual(settings.theme, .grove); commit()
      }))
      XCTAssertTrue(ThemeCommandApplication.apply(.builtIn(.grove), to: settings, onConfigurationSave: commit))
      XCTAssertEqual(calls, 8)
    }
  }

  func testEditorsAndRejectedCommandsNeverSaveThePracticeMode() {
    withSettings { settings, _ in
      var calls = 0
      settings.practiceTapeMode = .word
      XCTAssertFalse(AppearanceCommandTarget.showAllLines(true).apply(to: settings, onConfigurationSave: { calls += 1 }))
      XCTAssertFalse(ThemeCommandApplication.apply(.custom(UUID()), to: settings, onConfigurationSave: { calls += 1 }))
      PaceCaretCommandTarget.customSpeed.apply(to: settings, onConfigurationSave: { calls += 1 })
      XCTAssertEqual(calls, 0)
    }
  }

  func testLiveRuleSaveReadsUpdatedRulesAndPreservesTheActiveAttempt() throws {
    try withSettings { settings, defaults in
      let practice = try XCTUnwrap(WordPracticeText.sectionedPractice(segments: ["amber"], selectedTargetCount: 1))
      let original = ActiveTestSelectionDocument(preset: .init(configuration: .words(17)),
        testParameterMemory: .init(duration: 30, wordLimit: 17,
          customTextDuration: 45, customTextWordLimit: 9, customTextSectionLimit: 5))
      XCTAssertTrue(ActiveTestSelectionStore(defaults: defaults).save(original))
      var navigation = try XCTUnwrap(WordPracticeTransition.begin(previous: nil, practice: practice,
        currentPreset: { original.preset }, currentSelection: { _ in original }, selectCustomMode: { true }))
      let configuration = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
        difficulty: .normal, rules: settings.inputRules, customTextCompletion: .sections,
        customTextSectionLimit: 5, customTextOrdering: practice.ordering, customTextPipeDelimiter: true)
      var session = TestSessionFactory.make(configuration: configuration,
        customText: practice.text, preparedCustomSections: practice.sections)
      session.insertBatch("am", at: Date(timeIntervalSince1970: 1_000))
      let prompt = session.prompt
      var savedRules: InputRules?
      InputRuleCommandTarget.freedomMode(true).apply(to: settings, session: &session, onConfigurationSave: {
        savedRules = settings.inputRules
        var updated = configuration
        updated.rules = settings.inputRules
        let selected = ActiveTestSelectionDocument(preset: .init(configuration:
          updated, customText: practice.text),
          testParameterMemory: original.testParameterMemory)
        XCTAssertTrue(navigation.persistSelection(current: selected, cause: .configurationSave,
          save: ActiveTestSelectionStore(defaults: defaults).save))
      })
      XCTAssertEqual(savedRules, settings.inputRules)
      XCTAssertEqual(session.typed, "am")
      XCTAssertEqual(session.prompt, prompt)
      XCTAssertTrue(session.hasStarted)
      XCTAssertEqual(session.configuration.rules, settings.inputRules)
      let restored = try XCTUnwrap(ActiveTestSelectionStore(defaults: defaults).load())
      XCTAssertEqual(restored.preset.configuration.mode, .custom)
      XCTAssertEqual(restored.preset.configuration.rules, settings.inputRules)
    }
  }

  func testFunboxRejectedHighlightDoesNotSaveOrTemporarilyPersistTheInvalidValue() {
    withSettings { settings, defaults in
      settings.testModifiers = [.readAhead]
      settings.promptHighlightMode = .letter
      let before = defaults.data(forKey: "appSettings.v1")
      var calls = 0
      XCTAssertFalse(AppearanceCommandTarget.highlight(.nextTwoWords).apply(to: settings,
        onConfigurationSave: { calls += 1 }))
      XCTAssertEqual(calls, 0)
      XCTAssertEqual(settings.promptHighlightMode, .letter)
      XCTAssertEqual(defaults.data(forKey: "appSettings.v1"), before)
    }
  }
}
