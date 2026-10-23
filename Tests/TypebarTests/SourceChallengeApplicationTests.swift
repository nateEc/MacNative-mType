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

  func testCanonicalSourceChallengeRecordCanBeReadPreparedAndCompleted() throws {
    try withSettings { settings, defaults in
      let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "clean-twenty-five"))
      var original = challenge.preset
      original.configuration = original.configuration.with(challengeID: challenge.id)
      original.configuration.rules = settings.inputRules
      let record = try TestPresetRecord(name: "Canonical", definition: original)
      let bytes = record.definitionData
      let incoming = try XCTUnwrap(record.applicableDefinition)
      let before = settings.snapshot
      let configuration = try apply(incoming, to: settings)
      var expected = before
      expected.testModifiers = []
      XCTAssertEqual(settings.snapshot, expected)
      XCTAssertEqual(record.definitionData, bytes)
      XCTAssertNotNil(defaults.data(forKey: "appSettings.v1"))
      var session = TestSessionFactory.make(configuration: configuration)
      session.insertBatch(session.prompt, at: Date(timeIntervalSince1970: 100))
      XCTAssertTrue(ChallengeEvaluator.evaluate(try XCTUnwrap(session.result()), challenge: challenge).passed)
    }
  }

  func testEveryCanonicalSourceLibraryRecordIsAvailableWithoutChangingStoredBytes() throws {
    try withSettings { settings, _ in
      for challenge in TypebarChallengeLibrary.all {
        var preset = challenge.preset
        preset.configuration = preset.configuration.with(challengeID: challenge.id)
        preset.configuration.rules = settings.inputRules
        let record = try TestPresetRecord(name: challenge.id, definition: preset)
        let bytes = record.definitionData
        XCTAssertEqual(record.applicableDefinition, preset, challenge.id)
        XCTAssertEqual(record.definitionData, bytes, challenge.id)
      }
    }
  }

  func testSourceChallengeRecordDoesNotExposeInvalidTemplateOrGlobalOverrides() throws {
    try withSettings { settings, _ in
      let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "clean-twenty-five"))
      var preset = challenge.preset
      preset.configuration = preset.configuration.with(challengeID: challenge.id)
      preset.configuration.rules = settings.inputRules
      var snapshot = preset; snapshot.settingsSnapshot = settings.snapshot
      var partial = preset; partial.settingGroups = [.test]
      var tags = preset; tags.activeResultTags = []
      var forged = preset; forged.configuration.wordLimit = 3
      var unknown = preset; unknown.configuration.challengeID = "unknown"
      for rejected in [snapshot, partial, tags, forged, unknown] {
        let record = try TestPresetRecord(name: "Rejected", definition: rejected)
        let bytes = record.definitionData
        XCTAssertNil(record.applicableDefinition)
        XCTAssertEqual(record.definitionData, bytes)
      }
    }
  }

  func testAvailableSourceRecordDoesNotBypassTargetOrResourceAdmission() throws {
    try withSettings { settings, defaults in
      let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "ten-words-of-pain"))
      var preset = challenge.preset
      preset.configuration = preset.configuration.with(challengeID: challenge.id)
      preset.configuration.rules = settings.inputRules
      let record = try TestPresetRecord(name: "Needs font", definition: preset)
      let incoming = try XCTUnwrap(record.applicableDefinition)
      let before = defaults.dictionaryRepresentation() as NSDictionary
      XCTAssertEqual(PresetResourceAdmission.refusal(for: incoming.configuration,
        wingdingsAvailable: { false }, scriptIsVerified: { _ in false }), .missingWingdings)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
      defaults.removeObject(forKey: "appSettings.v4")
      let legacy = AppSettings(defaults: defaults,
        feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
      let legacyBefore = defaults.dictionaryRepresentation() as NSDictionary
      XCTAssertNil(PresetSourcePreparation.preparing(incoming, to: legacy, appliesGlobalSettings: true))
      XCTAssertFalse(legacy.hasThresholdProfile)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, legacyBefore)
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

  func testClearingChallengeIdentityKeepsLiveDifficultyAndModifiersWithoutSavingThem() throws {
    try withSettings { settings, defaults in
      let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "round-hour"))
      var preset = challenge.preset
      preset.configuration = preset.configuration.with(challengeID: challenge.id)
      let selected = try apply(preset, to: settings)
      var live = ChallengeLiveConfigurationState()
      XCTAssertTrue(live.install(selected, settings: settings))
      let profile = defaults.data(forKey: "appSettings.v4")
      let ordinary = TestConfiguration.timed(seconds: selected.duration ?? 30,
        difficulty: live.difficulty(settings: settings), rules: settings.inputRules)
        .with(modifiers: live.modifiers(settings: settings))
      XCTAssertNil(ordinary.challengeID)
      XCTAssertEqual(ordinary.difficulty, selected.difficulty)
      XCTAssertEqual(ordinary.modifiers, selected.modifiers)
      var session = TypingSession(configuration: ordinary, prompt: "amber bay")
      session.insertBatch("wrong ", at: Date(timeIntervalSince1970: 100))
      XCTAssertEqual(session.outcome, .active)
      XCTAssertNil(session.failureReason)
      XCTAssertEqual(defaults.data(forKey: "appSettings.v4"), profile)
    }
  }

  private func liveState(settings: AppSettings) throws -> ChallengeLiveConfigurationState {
    let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "round-hour"))
    var preset = challenge.preset
    preset.configuration = preset.configuration.with(challengeID: challenge.id)
    let configuration = try apply(preset, to: settings)
    var state = ChallengeLiveConfigurationState()
    XCTAssertTrue(state.install(configuration, settings: settings))
    return state
  }

  func testSameValueDifficultyApplicationReplacesOnlyTheLiveDifficulty() throws {
    try withSettings { settings, _ in
      let state = try liveState(settings: settings)
      let persisted = settings.difficulty
      settings.difficulty = persisted
      XCTAssertEqual(state.difficulty(settings: settings), .expert)
      XCTAssertEqual(state.modifiers(settings: settings), [.roundVisual])
    }
  }

  func testSameValueModifierClearReplacesOnlyTheLiveModifiers() throws {
    try withSettings { settings, _ in
      let state = try liveState(settings: settings)
      let persisted = settings.testModifiers
      settings.testModifiers = persisted
      XCTAssertEqual(state.modifiers(settings: settings), [])
      XCTAssertEqual(state.difficulty(settings: settings), .normal)
    }
  }

  func testUnrelatedPreferencesAndThresholdUpdatesDoNotInvalidateLiveFields() throws {
    try withSettings { settings, _ in
      let state = try liveState(settings: settings)
      settings.fontSize = 35
      XCTAssertTrue(settings.updateThresholdConfiguration(.minimumWpm(mode: .off, customValue: 55)))
      var appearance = settings.snapshot
      appearance.fontSize = 39
      XCTAssertTrue(settings.apply(appearance, groups: [.appearance]))
      XCTAssertEqual(state.difficulty(settings: settings), .normal)
      XCTAssertEqual(state.modifiers(settings: settings), [.roundVisual])
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWpmCustomValue, 55)
    }
  }

  func testBehaviorGroupApplicationEvenWithSameValuesSupersedesLiveFields() throws {
    try withSettings { settings, _ in
      let state = try liveState(settings: settings)
      XCTAssertTrue(settings.apply(settings.snapshot, groups: [.behavior]))
      XCTAssertEqual(state.difficulty(settings: settings), .expert)
      XCTAssertEqual(state.modifiers(settings: settings), [])
    }
  }

  func testRejectedApplicationDoesNotInvalidateOrPersistLiveFields() throws {
    try withSettings { settings, defaults in
      let state = try liveState(settings: settings)
      let before = defaults.dictionaryRepresentation() as NSDictionary
      var invalid = settings.snapshot
      invalid.minimumWpm = 50
      XCTAssertFalse(settings.apply(invalid))
      XCTAssertEqual(state.difficulty(settings: settings), .normal)
      XCTAssertEqual(state.modifiers(settings: settings), [.roundVisual])
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
    }
  }

  func testOtherWindowFunboxClearDoesNotSupersedeUnownedDifficulty() throws {
    try withSettings { settings, _ in
      let state = try liveState(settings: settings)
      settings.testModifiers = [.mirrorKeyboard]
      let revision = settings.difficultyApplicationRevision
      XCTAssertTrue(settings.clearChallengeModifiers())
      XCTAssertEqual(settings.difficultyApplicationRevision, revision)
      XCTAssertEqual(state.difficulty(settings: settings), .normal)
      XCTAssertEqual(state.modifiers(settings: settings), [])
    }
  }

  func testAutomaticNormalizationChangesOnlyWindowStateAndDoesNotResurrectModifiers() throws {
    try withSettings { settings, defaults in
      var state = try liveState(settings: settings)
      let before = defaults.dictionaryRepresentation() as NSDictionary
      state.normalizeModifiers([], settings: settings)
      XCTAssertTrue(state.hasTransientModifiers(settings: settings))
      XCTAssertEqual(state.modifiers(settings: settings), [])
      XCTAssertEqual(state.difficulty(settings: settings), .normal)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
    }
  }

  func testExplicitPresetCaptureUsesLiveSnapshotWithoutChangingPreferences() throws {
    try withSettings { settings, defaults in
      let state = try liveState(settings: settings)
      let before = defaults.dictionaryRepresentation() as NSDictionary
      let snapshot = state.snapshot(settings: settings)
      let configuration = TestConfiguration.words(3, difficulty: state.difficulty(settings: settings),
        rules: settings.inputRules).with(modifiers: state.modifiers(settings: settings))
      let preset = SavedTestPreset(configuration: configuration, settingsSnapshot: snapshot)
      XCTAssertTrue(PresetSettingsApplication.agreesWithSnapshot(preset))
      XCTAssertEqual(try LocalPresetCodec.decode(LocalPresetCodec.encode(preset)), preset)
      XCTAssertEqual(snapshot.difficulty, .normal)
      XCTAssertEqual(settings.snapshot.difficulty, .expert)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
    }
  }

  func testUnloadedLegacyReaderDoesNotAdoptAnAppearingSourceProfile() throws {
    let suite = "typebar.challenge-live-no-adoption.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let oldReader = AppSettings(defaults: defaults,
      feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
    oldReader.difficulty = .expert
    let source = PracticeThresholdSource(configuration: .init())
    XCTAssertTrue(ThresholdSettingsStore(defaults: defaults).save(source.applying(to: .init())))
    var live = ChallengeLiveConfigurationState()
    let configuration = TestConfiguration.words(3).with(challengeID: "clean-twenty-five")
    let before = defaults.dictionaryRepresentation() as NSDictionary
    XCTAssertFalse(live.install(configuration, settings: oldReader))
    XCTAssertEqual(live.difficulty(settings: oldReader), .expert)
    XCTAssertNil(oldReader.inputRules.thresholdSource)
    XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
  }

  func testSourceFunboxClearRefusesToOverwriteUnseenPersistedPreferences() throws {
    try withSettings { settings, defaults in
      var external = settings.snapshot
      external.fontSize = 42
      XCTAssertTrue(ThresholdSettingsStore(defaults: defaults).save(external))
      let before = defaults.dictionaryRepresentation() as NSDictionary
      let revision = settings.testModifiersApplicationRevision
      XCTAssertFalse(settings.clearChallengeModifiers())
      XCTAssertEqual(settings.testModifiers, [.mirrorKeyboard])
      XCTAssertEqual(settings.testModifiersApplicationRevision, revision)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
    }
  }

  func testSceneObservesExplicitDifficultyAndModifierApplicationEvents() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let scene = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"),
      encoding: .utf8)
    XCTAssertTrue(scene.contains(".onChange(of: settings.difficultyApplicationRevision)"))
    XCTAssertTrue(scene.contains(".onChange(of: settings.testModifiersApplicationRevision)"))
  }

  func testOwnSetupApplicationEventsDoNotCancelInstalledChallenge() throws {
    try withSettings { settings, _ in
      let state = try liveState(settings: settings)
      XCTAssertFalse(state.shouldClearChallenge(for: .difficulty,
        eventRevision: settings.difficultyApplicationRevision, settings: settings))
      XCTAssertFalse(state.shouldClearChallenge(for: .modifiers,
        eventRevision: settings.testModifiersApplicationRevision, settings: settings))
    }
  }

  func testSameValueDifficultyEventClearsIdentityButRetainsUnownedModifiers() throws {
    try withSettings { settings, defaults in
      let state = try liveState(settings: settings)
      let value = settings.difficulty
      settings.difficulty = value
      let before = defaults.dictionaryRepresentation() as NSDictionary
      var identity: String? = "round-hour"
      if state.shouldClearChallenge(for: .difficulty,
        eventRevision: settings.difficultyApplicationRevision, settings: settings) { identity = nil }
      XCTAssertNil(identity)
      XCTAssertEqual(state.modifiers(settings: settings), [.roundVisual])
      XCTAssertEqual(state.difficulty(settings: settings), .expert)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
    }
  }

  func testSameValueModifierEventClearsIdentityButRetainsUnownedDifficulty() throws {
    try withSettings { settings, defaults in
      let state = try liveState(settings: settings)
      let value = settings.testModifiers
      settings.testModifiers = value
      let before = defaults.dictionaryRepresentation() as NSDictionary
      XCTAssertTrue(state.shouldClearChallenge(for: .modifiers,
        eventRevision: settings.testModifiersApplicationRevision, settings: settings))
      XCTAssertFalse(state.shouldClearChallenge(for: .difficulty,
        eventRevision: settings.difficultyApplicationRevision, settings: settings))
      XCTAssertEqual(state.difficulty(settings: settings), .normal)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
    }
  }

  func testDelayedDeliveryDoesNotClearNewSetupButStillInvalidatesOlderWindow() throws {
    try withSettings { settings, _ in
      let oldWindow = try liveState(settings: settings)
      let oldRevision = settings.difficultyApplicationRevision
      let value = settings.difficulty
      settings.difficulty = value
      let newWindow = try liveState(settings: settings)
      let current = settings.difficultyApplicationRevision
      XCTAssertFalse(newWindow.shouldClearChallenge(for: .difficulty,
        eventRevision: oldRevision, settings: settings))
      XCTAssertFalse(newWindow.shouldClearChallenge(for: .difficulty,
        eventRevision: current, settings: settings))
      XCTAssertTrue(oldWindow.shouldClearChallenge(for: .difficulty,
        eventRevision: current, settings: settings))
    }
  }

  func testRejectedAndLockedApplicationsDoNotCreateCancellationEvents() throws {
    try withSettings { settings, _ in
      let state = try liveState(settings: settings)
      var invalid = settings.snapshot
      invalid.minimumWpm = 50
      XCTAssertFalse(settings.apply(invalid))
      let owner = UUID()
      settings.setNoQuitConfigurationLock(true, for: owner)
      defer { settings.setNoQuitConfigurationLock(false, for: owner) }
      XCTAssertFalse(settings.apply(settings.snapshot))
      XCTAssertFalse(state.shouldClearChallenge(for: .difficulty,
        eventRevision: settings.difficultyApplicationRevision, settings: settings))
      XCTAssertFalse(state.shouldClearChallenge(for: .modifiers,
        eventRevision: settings.testModifiersApplicationRevision, settings: settings))
    }
  }

  func testTransientFieldsAndEventsAreBoundToTheInstalledSettingsModel() throws {
    try withSettings { settings, defaults in
      let state = try liveState(settings: settings)
      let other = AppSettings(defaults: defaults,
        feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
      let value = other.difficulty
      other.difficulty = value
      XCTAssertFalse(state.shouldClearChallenge(for: .difficulty,
        eventRevision: other.difficultyApplicationRevision, settings: other))
      XCTAssertEqual(state.difficulty(settings: other), .expert)
      XCTAssertEqual(state.modifiers(settings: other), [])
      XCTAssertEqual(state.difficulty(settings: settings), .normal)
    }
  }

  func testLegacySetupIgnoresOwnEventsButSameValuePreferencesCancelQualification() throws {
    let suite = "typebar.legacy-challenge-events.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults,
      feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
    settings.difficulty = .expert
    let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "round-hour"))
    let configuration = challenge.preset.configuration.with(challengeID: challenge.id)
    let preset = SavedTestPreset(configuration: configuration)
    XCTAssertTrue(PresetSettingsApplication.commit(original: preset, resolved: preset,
      configuration: configuration, to: settings, appliesGlobalSettings: true))
    var state = ChallengeLiveConfigurationState()
    XCTAssertTrue(state.observeLegacyChallenge(settings: settings))
    XCTAssertFalse(state.hasTransientModifiers(settings: settings))
    XCTAssertFalse(state.shouldClearChallenge(for: .difficulty,
      eventRevision: settings.difficultyApplicationRevision, settings: settings))
    XCTAssertFalse(state.shouldClearChallenge(for: .modifiers,
      eventRevision: settings.testModifiersApplicationRevision, settings: settings))
    let difficulty = settings.difficulty
    settings.difficulty = difficulty
    XCTAssertTrue(state.shouldClearChallenge(for: .difficulty,
      eventRevision: settings.difficultyApplicationRevision, settings: settings))
    let modifiers = settings.testModifiers
    settings.testModifiers = modifiers
    XCTAssertTrue(state.shouldClearChallenge(for: .modifiers,
      eventRevision: settings.testModifiersApplicationRevision, settings: settings))
    XCTAssertEqual(state.difficulty(settings: settings), settings.difficulty)
    XCTAssertEqual(state.modifiers(settings: settings), settings.testModifiers)
    XCTAssertNil(defaults.object(forKey: "appSettings.v4"))
  }
}
