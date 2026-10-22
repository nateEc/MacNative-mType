import XCTest
@testable import Typebar

@MainActor
final class SourceChallengeApplicationTests: XCTestCase {
  private func withSettings(_ body: (AppSettings, UserDefaults) throws -> Void) throws {
    let suite = "typebar.source-challenge.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var raw = PracticeThresholdConfiguration()
    try raw.apply(.minimumWpm(mode: .custom, customValue: 0))
    try raw.apply(.minimumAccuracy(mode: .off, customValue: 93))
    try raw.apply(.minimumWordBurst(mode: .flex, customValue: 0))
    var snapshot = PracticeThresholdSource(configuration: raw).applying(to: AppSettingsSnapshot(
      difficulty: .expert, strictSpace: true, fontSize: 31))
    snapshot.testModifiers = [.mirrorKeyboard]
    defaults.set(try JSONEncoder().encode(AppSettingsSnapshot(fontSize: 22)), forKey: "appSettings.v1")
    XCTAssertTrue(ThresholdSettingsStore(defaults: defaults).save(snapshot))
    try body(AppSettings(defaults: defaults,
      feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory()), defaults)
  }

  private func apply(_ preset: SavedTestPreset, to settings: AppSettings,
    global: Bool = true) throws -> TestConfiguration {
    let prepared = try XCTUnwrap(PresetSourcePreparation.preparing(preset, to: settings,
      appliesGlobalSettings: global))
    let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: preset.configuration.challengeID))
    let selection = ChallengeSetupSelectionPolicy.Selection(configuration: preset.configuration)
    let candidate = ChallengeSetupSelectionPolicy.applying(selection, for: challenge,
      template: challenge.id == "one-handed-bandit" ? preset.configuration : nil)
    let configuration = ChallengeInputRulePolicy.applying(settings.inputRules, to: candidate)
    XCTAssertTrue(PresetSettingsApplication.commit(original: prepared.preset, resolved: prepared.preset,
      configuration: configuration, to: settings, appliesGlobalSettings: global,
      expectedSourceState: prepared.baseline))
    return configuration
  }

  func testSourceChallengeChangesOnlyPersistedFunboxClearNotTransientDifficultyOrThresholds() throws {
    try withSettings { settings, defaults in
      let before = settings.snapshot
      let old = defaults.data(forKey: "appSettings.v1")
      let fontRevision = settings.practiceFontApplicationRevision
      let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "thumb-hour"))
      var preset = challenge.preset
      preset.configuration = preset.configuration.with(challengeID: challenge.id)
      let configuration = try apply(preset, to: settings)
      var expected = before
      expected.testModifiers = []
      XCTAssertEqual(settings.snapshot, expected)
      XCTAssertEqual(ThresholdSettingsStore(defaults: defaults).read(), .available(expected))
      XCTAssertEqual(configuration.difficulty, .normal)
      XCTAssertEqual(configuration.rules, settings.inputRules)
      XCTAssertEqual(configuration.challengeID, challenge.id)
      XCTAssertEqual(settings.practiceFontApplicationRevision, fontRevision)
      XCTAssertEqual(defaults.data(forKey: "appSettings.v1"), old)
    }
  }

  func testSourceFunboxChallengeUsesTransientModifiersAndLeavesGlobalModifiersCleared() throws {
    try withSettings { settings, _ in
      let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "round-hour"))
      var preset = challenge.preset
      preset.configuration = preset.configuration.with(challengeID: challenge.id)
      let configuration = try apply(preset, to: settings)
      let session = TestSessionFactory.make(configuration: configuration)
      XCTAssertEqual(session.configuration.modifiers, [.roundVisual])
      XCTAssertEqual(settings.testModifiers, [])
      XCTAssertEqual(settings.difficulty, .expert)
      XCTAssertEqual(session.configuration.rules.thresholdSource, settings.inputRules.thresholdSource)
    }
  }

  func testEveryLibraryTemplatePreparesAndCommitsWithoutPersistingChallengeFields() throws {
    for challenge in TypebarChallengeLibrary.all {
      try withSettings { settings, _ in
        var original = challenge.preset
        original.configuration = original.configuration.with(challengeID: challenge.id)
        let before = settings.snapshot
        let result = try apply(original, to: settings)
        var expected = before
        expected.testModifiers = []
        XCTAssertEqual(settings.snapshot, expected, challenge.id)
        XCTAssertEqual(result.challengeID, challenge.id)
        XCTAssertEqual(result.rules.thresholdSource, before.thresholdSource)
      }
    }
  }

  func testSavedSourceSelectionColdRestoresAndCompletesActualChallenge() throws {
    try withSettings { settings, defaults in
      let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "clean-twenty-five"))
      var original = challenge.preset
      original.configuration = original.configuration.with(challengeID: challenge.id)
      let configuration = try apply(original, to: settings)
      var session = TestSessionFactory.make(configuration: configuration)
      let document = ActiveTestSelectionDocument(preset: .init(configuration: session.configuration),
        testParameterMemory: .defaults)
      XCTAssertTrue(settings.saveActiveTestSelection(document))
      let profile = defaults.data(forKey: "appSettings.v4")
      let reader = AppSettings(defaults: defaults,
        feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
      let restored = try apply(try XCTUnwrap(reader.activeTestSelection).preset, to: reader, global: false)
      XCTAssertEqual(defaults.data(forKey: "appSettings.v4"), profile)
      XCTAssertEqual(restored.rules.thresholdSource, configuration.rules.thresholdSource)
      session = TestSessionFactory.make(configuration: restored)
      session.insertBatch(session.prompt, at: Date(timeIntervalSince1970: 100))
      let result = try XCTUnwrap(session.result())
      XCTAssertEqual(result.outcome, .completed)
      XCTAssertTrue(ChallengeEvaluator.evaluate(result, challenge: challenge).passed)
      XCTAssertEqual(result.configuration.rules.thresholdSource, settings.inputRules.thresholdSource)
    }
  }

  func testSnapshotsPartialGroupsTagsAndForgedChallengeParametersAreRejectedWithoutWrites() throws {
    try withSettings { settings, defaults in
      let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "thumb-hour"))
      var original = challenge.preset
      original.configuration = original.configuration.with(challengeID: challenge.id)
      var snapshot = original; snapshot.settingsSnapshot = settings.snapshot
      var partial = original; partial.settingGroups = [.test]
      var tags = original; tags.activeResultTags = ["injected"]
      var forged = original; forged.configuration.duration = 1
      var modifiers = original; modifiers.configuration.modifiers = [.mirrorKeyboard]
      var unknown = original; unknown.configuration.challengeID = "unknown"
      var malformed = original
      var raw = PracticeThresholdConfiguration()
      try raw.apply(.minimumWpm(mode: .custom, customValue: 50))
      malformed.configuration.rules.thresholdSource = .init(configuration: raw)
      let before = defaults.dictionaryRepresentation() as NSDictionary
      for rejected in [snapshot, partial, tags, forged, modifiers, unknown, malformed] {
        XCTAssertNil(PresetSourcePreparation.preparing(rejected, to: settings, appliesGlobalSettings: true))
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
      }
    }
  }

  func testPreparedSourceChallengeRefusesLateLockProfileAndSelectionChanges() throws {
    for failure in ["lock", "appSettings.v4", "activeTestSelection.v2", "threshold"] {
      try withSettings { settings, defaults in
        let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "thumb-hour"))
        var original = challenge.preset
        original.configuration = original.configuration.with(challengeID: challenge.id)
        let prepared = try XCTUnwrap(PresetSourcePreparation.preparing(original, to: settings,
          appliesGlobalSettings: true))
        let configuration = prepared.preset.configuration
        let owner = UUID()
        if failure == "lock" { settings.setNoQuitConfigurationLock(true, for: owner) }
        else if failure == "threshold" {
          XCTAssertTrue(settings.updateThresholdConfiguration(.minimumWpm(mode: .off, customValue: 55)))
        } else { defaults.set(Data("{\"version\":99}".utf8), forKey: failure) }
        defer { settings.setNoQuitConfigurationLock(false, for: owner) }
        let before = defaults.dictionaryRepresentation() as NSDictionary
        XCTAssertFalse(PresetSettingsApplication.commit(original: prepared.preset, resolved: prepared.preset,
          configuration: configuration, to: settings, appliesGlobalSettings: true,
          expectedSourceState: prepared.baseline))
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
      }
    }
  }

  func testSelectionOnlyRestoreDoesNotClearCurrentGlobalFunbox() throws {
    try withSettings { settings, defaults in
      let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "thumb-hour"))
      var original = challenge.preset
      original.configuration = original.configuration.with(challengeID: challenge.id)
      let before = defaults.dictionaryRepresentation() as NSDictionary
      _ = try apply(original, to: settings, global: false)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
    }
  }

  func testResourcePreflightStillRejectsMissingChallengeDependencies() throws {
    try withSettings { settings, defaults in
      let before = defaults.dictionaryRepresentation() as NSDictionary
      let wingdings = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "ten-words-of-pain"))
      XCTAssertEqual(PresetResourceAdmission.refusal(for: wingdings.preset.configuration.with(challengeID: wingdings.id),
        wingdingsAvailable: { false }, scriptIsVerified: { _ in false }), .missingWingdings)
      let script = try XCTUnwrap(TypebarChallengeLibrary.all.first { $0.requirements.referenceScriptSpecification != nil })
      XCTAssertEqual(PresetResourceAdmission.refusal(for: script.preset.configuration.with(challengeID: script.id),
        wingdingsAvailable: { true }, scriptIsVerified: { _ in false }), .missingVerifiedScript)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
      XCTAssertEqual(settings.testModifiers, [.mirrorKeyboard])
    }
  }

  func testCapturedAutomaticArabicModifiersRemainRestorableWithoutAllowingInjectedModifiers() throws {
    try withSettings { settings, defaults in
      let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "thumb-hour"))
      let selection = ChallengeSetupSelectionPolicy.Selection(language: .arabic, englishVariant: .american,
        mixedLanguageComponents: TypingLanguage.referenceDefaultMixedComponents, contentOptions: .init())
      var configuration = ChallengeInputRulePolicy.applying(settings.inputRules,
        to: ChallengeSetupSelectionPolicy.applying(selection, for: challenge))
      configuration = configuration.with(modifiers: EffectiveTestModifierPolicy.modifiers(
        requested: [], language: .arabic, mode: configuration.mode,
        mixedLanguageComponents: configuration.mixedLanguageComponents, automaticallyEnabledArabic: true))
      let before = defaults.dictionaryRepresentation() as NSDictionary
      XCTAssertNotNil(PresetSourcePreparation.preparing(.init(configuration: configuration),
        to: settings, appliesGlobalSettings: false))
      configuration.modifiers.append(.mirrorKeyboard)
      XCTAssertNil(PresetSourcePreparation.preparing(.init(configuration: configuration),
        to: settings, appliesGlobalSettings: false))
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
    }
  }
}
