import XCTest
@testable import Typebar

@MainActor
final class SourceChallengeApplicationTests: XCTestCase {
  func testSameValuePresentationConfirmationsCancelQualificationWithoutReplacingTransientFields() throws {
    for field in ["speed", "pace", "lines"] {
      try withSettings { settings, _ in
        let live = try liveState(settings: settings)
        let before = settings.snapshot
        let revision = settings.challengePresentationApplicationRevision
        switch field {
        case "speed": settings.liveSpeedStyle = before.liveSpeedStyle
        case "pace": settings.paceGuideMode = before.paceGuideMode
        default: settings.showAllPracticeLines = before.showAllPracticeLines
        }
        XCTAssertGreaterThan(settings.challengePresentationApplicationRevision, revision, field)
        XCTAssertTrue(live.shouldClearChallenge(for: .presentation,
          eventRevision: settings.challengePresentationApplicationRevision, settings: settings), field)
        XCTAssertFalse(live.shouldClearChallenge(for: .presentation, eventRevision: revision, settings: settings))
        XCTAssertEqual(settings.snapshot, before)
        XCTAssertEqual(live.difficulty(settings: settings), .normal)
        XCTAssertEqual(live.modifiers(settings: settings), [.roundVisual])
      }
    }
  }

  func testPresentationOwnSetupAndDelayedEventsDoNotCancelANewerChallenge() throws {
    try withSettings { settings, _ in
      let older = try liveState(settings: settings)
      settings.liveSpeedStyle = .text
      let delivered = settings.challengePresentationApplicationRevision
      let newer = try liveState(settings: settings)
      XCTAssertTrue(older.shouldClearChallenge(for: .presentation, eventRevision: delivered, settings: settings))
      XCTAssertFalse(newer.shouldClearChallenge(for: .presentation, eventRevision: delivered, settings: settings))
      settings.paceGuideMode = settings.snapshot.paceGuideMode
      XCTAssertFalse(newer.shouldClearChallenge(for: .presentation, eventRevision: delivered, settings: settings))
      XCTAssertTrue(newer.shouldClearChallenge(for: .presentation,
        eventRevision: settings.challengePresentationApplicationRevision, settings: settings))
    }
  }

  func testCompletionEpochRejectsUnobservedApplicationsButAcceptsNewSetup() throws {
    try withSettings { settings, _ in
      let older = try liveState(settings: settings)
      XCTAssertTrue(older.isQualificationCurrent(settings: settings))
      settings.paceGuideMode = settings.snapshot.paceGuideMode
      XCTAssertFalse(older.isQualificationCurrent(settings: settings))
      let newer = try liveState(settings: settings)
      XCTAssertTrue(newer.isQualificationCurrent(settings: settings))
      XCTAssertFalse(ChallengeLiveConfigurationState().isQualificationCurrent(settings: settings))
      try withSettings { other, _ in
        XCTAssertFalse(newer.isQualificationCurrent(settings: other))
      }
    }
  }

  func testPresentationRevisionIgnoresUnrelatedPreferencesAndOtherSettingsModels() throws {
    try withSettings { settings, _ in
      let live = try liveState(settings: settings)
      let revision = settings.challengePresentationApplicationRevision
      settings.liveAccuracyStyle = .text
      settings.theme = .midnight
      settings.paceCaretStyle = .outline
      settings.paceGuideCustomWpm = 150.25
      XCTAssertEqual(settings.challengePresentationApplicationRevision, revision)
      XCTAssertFalse(live.shouldClearChallenge(for: .presentation, eventRevision: revision, settings: settings))
      try withSettings { other, _ in
        other.liveSpeedStyle = .text
        XCTAssertFalse(live.shouldClearChallenge(for: .presentation,
          eventRevision: other.challengePresentationApplicationRevision, settings: other))
      }
    }
  }

  func testRejectedPresentationSnapshotDoesNotPublishAnApplicationEvent() throws {
    for failure in ["lock", "future"] {
      try withSettings { settings, defaults in
        let live = try liveState(settings: settings)
        var snapshot = settings.snapshot
        snapshot.liveSpeedStyle = .text
        let revision = settings.challengePresentationApplicationRevision
        let owner = UUID()
        if failure == "lock" { settings.setNoQuitConfigurationLock(true, for: owner) }
        else { defaults.set(Data("{\"version\":99}".utf8), forKey: "appSettings.v4") }
        defer { settings.setNoQuitConfigurationLock(false, for: owner) }
        let before = defaults.dictionaryRepresentation() as NSDictionary
        XCTAssertFalse(settings.apply(snapshot))
        XCTAssertEqual(settings.challengePresentationApplicationRevision, revision)
        XCTAssertFalse(live.shouldClearChallenge(for: .presentation, eventRevision: revision, settings: settings))
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
      }
    }
  }

  func testLegacyChallengeReceivesSameValuePresentationEventsWithoutSourceAdoption() throws {
    try withSettings { _, defaults in
      defaults.removeObject(forKey: "appSettings.v4")
      let settings = AppSettings(defaults: defaults,
        feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
      var live = ChallengeLiveConfigurationState()
      XCTAssertTrue(live.observeLegacyChallenge(settings: settings))
      settings.showAllPracticeLines = settings.snapshot.showAllPracticeLines
      XCTAssertTrue(live.shouldClearChallenge(for: .presentation,
        eventRevision: settings.challengePresentationApplicationRevision, settings: settings))
      XCTAssertFalse(settings.hasThresholdProfile)
    }
  }

  func testEnglishMasterBritishSelectionAlreadySurvivesFormalSetupCaptureAndColdRead() throws {
    try withSettings { settings, defaults in
      settings.englishVariant = .british
      let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "english-ten-thousand-hour"))
      var original = challenge.preset
      original.configuration = original.configuration.with(challengeID: challenge.id)
      let prepared = try XCTUnwrap(PresetSourcePreparation.preparing(original, to: settings, appliesGlobalSettings: true))
      let selected = ChallengeSetupSelectionPolicy.Selection(language: .spanish, englishVariant: .british,
        mixedLanguageComponents: [.spanish, .french], contentOptions: .init())
      let configuration = ChallengeInputRulePolicy.applying(settings.inputRules,
        to: ChallengeSetupSelectionPolicy.applying(selected, for: challenge))
      XCTAssertTrue(PresetSettingsApplication.commit(original: prepared.preset, resolved: prepared.preset,
        configuration: configuration, to: settings, appliesGlobalSettings: true,
        expectedSourceState: prepared.baseline))
      XCTAssertEqual(configuration.language, .english10k)
      XCTAssertEqual(configuration.englishVariant, .british)
      XCTAssertEqual(configuration.contentOptions, .init(includePunctuation: true, includeNumbers: true))
      XCTAssertEqual(BritishEnglishPolicy.transformed("color", context: .init(configuration: configuration)), "colour")
      var live = ChallengeLiveConfigurationState()
      XCTAssertTrue(live.install(configuration, settings: settings))
      let capture = SavedTestPreset(configuration: configuration, settingsSnapshot: live.snapshot(settings: settings))
        .capturedForLibrary(settingGroups: nil)
      let record = try TestPresetRecord(name: "British English Master practice", definition: capture)
      let ordinary = try XCTUnwrap(record.applicableDefinition)
      let ready = try XCTUnwrap(PresetSourcePreparation.preparing(ordinary, to: settings, appliesGlobalSettings: true))
      XCTAssertTrue(PresetSettingsApplication.commit(original: ready.preset, resolved: ready.preset,
        configuration: ready.preset.configuration, to: settings, appliesGlobalSettings: true,
        expectedSourceState: ready.baseline))
      let reader = AppSettings(defaults: defaults,
        feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
      XCTAssertEqual(reader.englishVariant, .british)
      let session = TestSessionFactory.make(configuration: ordinary.configuration)
      XCTAssertEqual(session.configuration.englishVariant, .british)
      XCTAssertEqual(session.configuration.language, .english10k)
      XCTAssertNil(session.configuration.challengeID)
    }
  }

  func testSceneObservesAppliedPresentationEventsRatherThanOnlyChangedValues() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    XCTAssertTrue(source.contains(".onChange(of: settings.challengePresentationApplicationRevision)"))
    XCTAssertTrue(source.contains("handleChallengeFieldApplication(.presentation, revision: revision)"))
    XCTAssertFalse(source.contains(".onChange(of: settings.liveSpeedStyle) { _, _ in activeChallengeID = nil }"))
    XCTAssertFalse(source.contains(".onChange(of: settings.paceCaretStyle) { _, _ in activeChallengeID = nil }"))
  }

  func testCompletionChecksQualificationEpochBeforeCapturingPresentationEvidence() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    let begin = try XCTUnwrap(source.range(of: "case .completed, .failed, .bailedOut, .invalidAFK:"))
    let body = source[begin.lowerBound...]
    let epoch = try XCTUnwrap(body.range(of: "challengeLiveConfiguration.isQualificationCurrent(settings: settings)"))
    let snapshot = try XCTUnwrap(body.range(of: "let challengePresentation ="))
    XCTAssertLessThan(epoch.lowerBound, snapshot.lowerBound)
  }

  private func wingdingsState(settings: AppSettings) throws -> (ChallengeLiveConfigurationState, TestConfiguration) {
    settings.installedPracticeFontName = "Georgia"
    settings.keyboardGuideMode = .next
    let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "ten-words-of-pain"))
    var template = challenge.preset
    template.configuration = template.configuration.with(challengeID: challenge.id)
    let configuration = try apply(template, to: settings)
    var live = ChallengeLiveConfigurationState()
    XCTAssertTrue(live.install(configuration, settings: settings))
    return (live, configuration)
  }

  func testSameValueDisplayApplicationReplacesOnlyItsOwnedTransientField() throws {
    for field in [ChallengeLiveConfigurationState.ApplicationField.font, .keyboardGuide] {
      try withSettings { settings, _ in
        let (live, _) = try wingdingsState(settings: settings)
        XCTAssertFalse(live.shouldClearChallenge(for: .font,
          eventRevision: settings.practiceFontApplicationRevision, settings: settings))
        XCTAssertFalse(live.shouldClearChallenge(for: .keyboardGuide,
          eventRevision: settings.keyboardGuideApplicationRevision, settings: settings))
        switch field {
        case .font:
          settings.installedPracticeFontName = "Georgia"
          XCTAssertEqual(live.fontFamilyName(settings: settings), "Georgia")
          XCTAssertEqual(live.keyboardGuideMode(settings: settings), .off)
          XCTAssertTrue(live.shouldClearChallenge(for: field,
            eventRevision: settings.practiceFontApplicationRevision, settings: settings))
        case .keyboardGuide:
          settings.keyboardGuideMode = .next
          XCTAssertEqual(live.fontFamilyName(settings: settings), WingdingsChallengeFont.familyName)
          XCTAssertEqual(live.keyboardGuideMode(settings: settings), .next)
          XCTAssertTrue(live.shouldClearChallenge(for: field,
            eventRevision: settings.keyboardGuideApplicationRevision, settings: settings))
        default: XCTFail("Display field required")
        }
      }
    }
  }

  func testGuideVisibilityConfirmationAndUnrelatedSettingsHaveDistinctOwnership() throws {
    try withSettings { settings, _ in
      let (live, _) = try wingdingsState(settings: settings)
      let fontRevision = settings.practiceFontApplicationRevision
      let guideRevision = settings.keyboardGuideApplicationRevision
      settings.theme = .midnight
      XCTAssertEqual(settings.practiceFontApplicationRevision, fontRevision)
      XCTAssertEqual(settings.keyboardGuideApplicationRevision, guideRevision)
      XCTAssertEqual(live.snapshot(settings: settings).installedPracticeFontName, WingdingsChallengeFont.familyName)
      XCTAssertEqual(live.keyboardGuideMode(settings: settings), .off)
      settings.showKeyboardGuide = true
      XCTAssertGreaterThan(settings.keyboardGuideApplicationRevision, guideRevision)
      XCTAssertEqual(live.keyboardGuideMode(settings: settings), .next)
      XCTAssertEqual(live.fontFamilyName(settings: settings), WingdingsChallengeFont.familyName)
    }
  }

  func testLaterChallengeKeepsUnownedDisplayButCannotReviveAnExplicitlyReplacedFont() throws {
    try withSettings { settings, _ in
      var (live, _) = try wingdingsState(settings: settings)
      let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "round-hour"))
      var template = challenge.preset
      template.configuration = template.configuration.with(challengeID: challenge.id)
      let configuration = try apply(template, to: settings)
      XCTAssertTrue(live.install(configuration, settings: settings))
      XCTAssertEqual(live.fontFamilyName(settings: settings), WingdingsChallengeFont.familyName)
      XCTAssertEqual(live.keyboardGuideMode(settings: settings), .off)
      settings.installedPracticeFontName = "Georgia"
      let priorRevision = settings.practiceFontApplicationRevision
      XCTAssertTrue(live.install(configuration, settings: settings))
      XCTAssertEqual(live.fontFamilyName(settings: settings), "Georgia")
      XCTAssertEqual(live.keyboardGuideMode(settings: settings), .off)
      XCTAssertFalse(live.shouldClearChallenge(for: .font, eventRevision: priorRevision, settings: settings))
    }
  }

  func testOrdinaryThemePresetPersistsAcceptedWingdingsDisplayForANewReader() throws {
    try withSettings { settings, defaults in
      let (live, configuration) = try wingdingsState(settings: settings)
      let current = SavedTestPreset(configuration: configuration, settingsSnapshot: live.snapshot(settings: settings))
      var snapshot = settings.snapshot
      snapshot.theme = .midnight
      let incoming = SavedTestPreset(configuration: .words(3, rules: settings.inputRules),
        settingsSnapshot: snapshot, settingGroups: [.theme])
      let prepared = try XCTUnwrap(PresetSourcePreparation.preparing(incoming, to: settings, appliesGlobalSettings: true))
      let resolved = PresetApplicationPolicy.applying(current: current, preset: prepared.preset)
      XCTAssertTrue(PresetSettingsApplication.commit(original: prepared.preset, resolved: resolved,
        configuration: resolved.configuration, to: settings, appliesGlobalSettings: true,
        expectedSourceState: prepared.baseline, liveConfiguration: live))
      XCTAssertNil(resolved.configuration.challengeID)
      let reader = AppSettings(defaults: defaults,
        feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
      XCTAssertEqual(reader.installedPracticeFontName, WingdingsChallengeFont.familyName)
      XCTAssertEqual(reader.effectiveKeyboardGuideMode, .off)
      XCTAssertEqual(reader.theme, .midnight)
    }
  }

  func testDisplayStateDoesNotTransferBetweenSettingsOwners() throws {
    try withSettings { settings, _ in
      var (live, _) = try wingdingsState(settings: settings)
      try withSettings { other, _ in
        other.installedPracticeFontName = "Courier"
        other.keyboardGuideMode = .react
        XCTAssertEqual(live.snapshot(settings: other), other.snapshot)
        XCTAssertFalse(live.shouldClearChallenge(for: .font,
          eventRevision: other.practiceFontApplicationRevision, settings: other))
        let configuration = TestConfiguration.words(25, rules: other.inputRules).with(challengeID: "clean-twenty-five")
        XCTAssertTrue(live.install(configuration, settings: other))
        XCTAssertEqual(live.fontFamilyName(settings: other), "Courier")
        XCTAssertEqual(live.keyboardGuideMode(settings: other), .react)
      }
    }
  }

  func testLegacyWingdingsDisplayRemainsTransientWithoutAdoptingSource() throws {
    try withSettings { _, defaults in
      defaults.removeObject(forKey: "appSettings.v4")
      let settings = AppSettings(defaults: defaults,
        feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
      settings.installedPracticeFontName = "Georgia"
      settings.keyboardGuideMode = .next
      let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "ten-words-of-pain"))
      var template = challenge.preset
      template.configuration = template.configuration.with(challengeID: challenge.id)
      let configuration = try apply(template, to: settings)
      let before = defaults.dictionaryRepresentation() as NSDictionary
      var live = ChallengeLiveConfigurationState()
      XCTAssertTrue(live.observeLegacyChallenge(settings: settings, configuration: configuration))
      XCTAssertEqual(live.snapshot(settings: settings).installedPracticeFontName, WingdingsChallengeFont.familyName)
      XCTAssertEqual(live.keyboardGuideMode(settings: settings), .off)
      XCTAssertFalse(settings.hasThresholdProfile)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
    }
  }

  func testSceneUsesDisplayOwnershipForRenderingAndQualificationEvents() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    XCTAssertTrue(source.contains("handleChallengeFieldApplication(.font, revision: revision)"))
    XCTAssertTrue(source.contains("handleChallengeFieldApplication(.keyboardGuide, revision: revision)"))
    let begin = try XCTUnwrap(source.range(of: "private var effectiveKeyboardGuideMode:"))
    let end = try XCTUnwrap(source.range(of: "private func clearCommandFontPreview()"))
    let rendering = source[begin.lowerBound..<end.lowerBound]
    XCTAssertTrue(rendering.contains("challengeLiveConfiguration.hasTransientFont(settings: settings)"))
    XCTAssertTrue(rendering.contains("challengeLiveConfiguration.keyboardGuideMode(settings: settings)"))
    XCTAssertFalse(rendering.contains("activeChallengeID =="))
    let forcedGuide = try XCTUnwrap(rendering.range(of: "modifiers.contains(.simonSays)"))
    let inheritedGuide = try XCTUnwrap(rendering.range(of: "challengeLiveConfiguration.keyboardGuideMode(settings: settings)"))
    XCTAssertLessThan(forcedGuide.lowerBound, inheritedGuide.lowerBound,
      "Inherited Wingdings visibility must not hide Simon's required guide")
  }

  func testSceneHandsAcceptedFontToLocalSelectionOnlyAfterSettingsCommit() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    let start = try XCTUnwrap(source.range(of: "@discardableResult private func apply("))
    let body = source[start.lowerBound...]
    let commit = try XCTUnwrap(body.range(of: "guard PresetSettingsApplication.commit("))
    let handoff = try XCTUnwrap(body.range(of: "TransientFontPersistencePolicy.requiresLocalFontDeactivation("))
    XCTAssertLessThan(commit.lowerBound, handoff.lowerBound)
    XCTAssertTrue(body[handoff.lowerBound...].contains("settings.deactivateLocalPracticeFont()"))
  }

  func testFontHandoffRequiresExplicitEffectiveSnapshotAndMatchingAcceptedFamily() {
    XCTAssertTrue(TransientFontPersistencePolicy.requiresLocalFontDeactivation(
      acceptedFamily: "Wingdings", persistedFamily: "Wingdings", savesEffectiveSnapshot: true))
    XCTAssertFalse(TransientFontPersistencePolicy.requiresLocalFontDeactivation(
      acceptedFamily: "Wingdings", persistedFamily: "Wingdings", savesEffectiveSnapshot: false))
    XCTAssertFalse(TransientFontPersistencePolicy.requiresLocalFontDeactivation(
      acceptedFamily: nil, persistedFamily: "Wingdings", savesEffectiveSnapshot: true))
    XCTAssertFalse(TransientFontPersistencePolicy.requiresLocalFontDeactivation(
      acceptedFamily: "Wingdings", persistedFamily: "Georgia", savesEffectiveSnapshot: true))
  }

  func testWingdingsDisplaySnapshotOutlivesQualificationWithoutChangingPreferences() throws {
    try withSettings { settings, defaults in
      settings.installedPracticeFontName = "Georgia"
      settings.keyboardGuideMode = .next
      let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "ten-words-of-pain"))
      var template = challenge.preset
      template.configuration = template.configuration.with(challengeID: challenge.id)
      let configuration = try apply(template, to: settings)
      var live = ChallengeLiveConfigurationState()
      XCTAssertTrue(live.install(configuration, settings: settings))
      let before = defaults.dictionaryRepresentation() as NSDictionary
      let ordinary = configuration.with(challengeID: nil)
      XCTAssertNil(ordinary.challengeID)
      let snapshot = live.snapshot(settings: settings)
      XCTAssertEqual(snapshot.installedPracticeFontName, WingdingsChallengeFont.familyName)
      XCTAssertEqual(snapshot.keyboardGuideMode, .off)
      XCTAssertFalse(snapshot.showKeyboardGuide)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
    }
  }

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

  func testLibraryCaptureOfSourceChallengeAppliesAsOrdinaryPresetWithoutQualification() throws {
    try withSettings { settings, defaults in
      let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "clean-twenty-five"))
      var template = challenge.preset
      template.configuration = template.configuration.with(challengeID: challenge.id)
      let configuration = try apply(template, to: settings)
      var live = ChallengeLiveConfigurationState()
      XCTAssertTrue(live.install(configuration, settings: settings))
      let current = SavedTestPreset(configuration: configuration, customText: template.customText,
        activeResultTags: ["captured"], settingsSnapshot: live.snapshot(settings: settings))
      let beforeCapture = defaults.dictionaryRepresentation() as NSDictionary
      let capture = current.capturedForLibrary(settingGroups: nil)
      XCTAssertNil(capture.configuration.challengeID)
      XCTAssertEqual(capture.configuration, current.configuration.with(challengeID: nil))
      XCTAssertEqual(capture.settingsSnapshot, current.settingsSnapshot)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, beforeCapture)
      let record = try TestPresetRecord(name: "From challenge", definition: capture)
      let incoming = try XCTUnwrap(record.applicableDefinition)
      let prepared = try XCTUnwrap(PresetSourcePreparation.preparing(incoming, to: settings,
        appliesGlobalSettings: true))
      XCTAssertTrue(PresetSettingsApplication.commit(original: prepared.preset, resolved: prepared.preset,
        configuration: prepared.preset.configuration, to: settings, appliesGlobalSettings: true,
        expectedSourceState: prepared.baseline))
      XCTAssertEqual(settings.difficulty, configuration.difficulty)
      XCTAssertEqual(settings.activeResultTags, ["captured"])
      var session = TestSessionFactory.make(configuration: prepared.preset.configuration)
      session.insertBatch(session.prompt, at: Date(timeIntervalSince1970: 100))
      let result = try XCTUnwrap(session.result())
      XCTAssertEqual(result.outcome, .completed)
      XCTAssertNil(result.configuration.challengeID)
      XCTAssertEqual(current.configuration.challengeID, challenge.id)
    }
  }

  func testLibraryCapturePreservesAllSelectedGroupsAndPayloadWithoutMutatingSource() throws {
    try withSettings { settings, defaults in
      let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "round-hour"))
      var template = challenge.preset
      template.configuration = template.configuration.with(challengeID: challenge.id)
      let configuration = try apply(template, to: settings)
      var live = ChallengeLiveConfigurationState()
      XCTAssertTrue(live.install(configuration, settings: settings))
      let current = SavedTestPreset(configuration: configuration, quoteID: "owned-id", customText: "owned text",
        activeResultTags: ["owned"], settingsSnapshot: live.snapshot(settings: settings))
      let before = defaults.dictionaryRepresentation() as NSDictionary
      let all = PresetSettingGroup.allCases
      for mask in 0..<(1 << all.count) {
        let groups = Set(all.enumerated().compactMap { mask & (1 << $0.offset) == 0 ? nil : $0.element })
        let captured = current.capturedForLibrary(settingGroups: groups)
        var expected = current.with(settingGroups: groups)
        expected.configuration.challengeID = nil
        XCTAssertEqual(captured, expected)
        XCTAssertEqual(try LocalPresetCodec.decode(LocalPresetCodec.encode(captured)), captured)
      }
      XCTAssertEqual(current.configuration.challengeID, challenge.id)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
      let ordinary = current.capturedForLibrary(settingGroups: nil)
      XCTAssertEqual(ordinary.capturedForLibrary(settingGroups: nil), ordinary)
    }
  }

  func testWingdingsLibraryCaptureKeepsVisibleFontAndGuideWithoutChallengeIdentity() throws {
    try withSettings { settings, _ in
      let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "ten-words-of-pain"))
      var template = challenge.preset
      template.configuration = template.configuration.with(challengeID: challenge.id)
      let configuration = try apply(template, to: settings)
      var live = ChallengeLiveConfigurationState()
      XCTAssertTrue(live.install(configuration, settings: settings))
      var snapshot = live.snapshot(settings: settings)
      snapshot.showKeyboardGuide = true
      snapshot.keyboardGuideMode = .next
      let current = SavedTestPreset(configuration: configuration, settingsSnapshot: snapshot)
      let capture = current.capturedForLibrary(settingGroups: nil)
      XCTAssertNil(capture.configuration.challengeID)
      XCTAssertEqual(capture.settingsSnapshot?.installedPracticeFontName, WingdingsChallengeFont.familyName)
      XCTAssertEqual(capture.settingsSnapshot?.showKeyboardGuide, false)
      XCTAssertEqual(capture.settingsSnapshot?.keyboardGuideMode, .off)
      XCTAssertEqual(current.settingsSnapshot, snapshot)
      let record = try TestPresetRecord(name: "Symbols", definition: capture)
      let prepared = try XCTUnwrap(PresetSourcePreparation.preparing(try XCTUnwrap(record.applicableDefinition),
        to: settings, appliesGlobalSettings: true))
      XCTAssertTrue(PresetSettingsApplication.commit(original: prepared.preset, resolved: prepared.preset,
        configuration: prepared.preset.configuration, to: settings, appliesGlobalSettings: true,
        expectedSourceState: prepared.baseline))
      XCTAssertEqual(settings.installedPracticeFontName, WingdingsChallengeFont.familyName)
      XCTAssertEqual(settings.effectiveKeyboardGuideMode, .off)
    }
  }

  func testPartialChallengeCapturesApplyOnlyOwnedFieldsToAnOrdinaryTest() throws {
    for group in PresetSettingGroup.allCases {
      try withSettings { settings, _ in
        let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "round-hour"))
        var template = challenge.preset
        template.configuration = template.configuration.with(challengeID: challenge.id)
        let configuration = try apply(template, to: settings)
        var live = ChallengeLiveConfigurationState()
        XCTAssertTrue(live.install(configuration, settings: settings))
        let capture = SavedTestPreset(configuration: configuration, activeResultTags: ["captured"],
          settingsSnapshot: live.snapshot(settings: settings)).capturedForLibrary(settingGroups: [group])
        let record = try TestPresetRecord(name: group.rawValue, definition: capture)
        let incoming = try XCTUnwrap(record.applicableDefinition)
        let prepared = try XCTUnwrap(PresetSourcePreparation.preparing(incoming, to: settings,
          appliesGlobalSettings: true))
        var ordinaryConfiguration = TestConfiguration.words(3, difficulty: settings.difficulty,
          rules: settings.inputRules)
        ordinaryConfiguration.englishVariant = settings.englishVariant
        let ordinary = SavedTestPreset(configuration: ordinaryConfiguration,
          activeResultTags: settings.activeResultTags, settingsSnapshot: settings.snapshot)
        let resolved = PresetApplicationPolicy.applying(current: ordinary, preset: prepared.preset)
        XCTAssertTrue(PresetSettingsApplication.commit(original: prepared.preset, resolved: resolved,
          configuration: resolved.configuration, to: settings, appliesGlobalSettings: true,
          expectedSourceState: prepared.baseline), group.rawValue)
        XCTAssertNil(resolved.configuration.challengeID)
        XCTAssertEqual(resolved.configuration.mode, group == .test ? configuration.mode : .words)
        XCTAssertEqual(settings.difficulty, group == .behavior ? configuration.difficulty : .expert)
        XCTAssertEqual(settings.testModifiers, group == .behavior ? configuration.modifiers : [])
        XCTAssertEqual(settings.activeResultTags, group == .behavior ? ["captured"] : [])
      }
    }
  }

  func testOrdinaryAppearancePartialReplacesSourceChallengeWithoutChangingUnownedLiveFields() throws {
    try withSettings { settings, defaults in
      let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "round-hour"))
      var template = challenge.preset
      template.configuration = template.configuration.with(challengeID: challenge.id)
      let configuration = try apply(template, to: settings)
      var live = ChallengeLiveConfigurationState()
      XCTAssertTrue(live.install(configuration, settings: settings))
      let current = SavedTestPreset(configuration: configuration, activeResultTags: ["current"],
        settingsSnapshot: live.snapshot(settings: settings))
      var snapshot = settings.snapshot
      snapshot.fontSize = 42
      let incoming = SavedTestPreset(configuration: .words(3, rules: settings.inputRules),
        activeResultTags: ["incoming"], settingsSnapshot: snapshot, settingGroups: [.appearance])
      let prepared = try XCTUnwrap(PresetSourcePreparation.preparing(incoming, to: settings,
        appliesGlobalSettings: true))
      let resolved = PresetApplicationPolicy.applying(current: current, preset: prepared.preset)
      XCTAssertNil(resolved.configuration.challengeID)
      XCTAssertTrue(PresetSettingsApplication.commit(original: prepared.preset, resolved: resolved,
        configuration: resolved.configuration, to: settings, appliesGlobalSettings: true,
        expectedSourceState: prepared.baseline, liveConfiguration: live))
      XCTAssertEqual(resolved.configuration, configuration.with(challengeID: nil))
      XCTAssertEqual(settings.snapshot, resolved.settingsSnapshot)
      XCTAssertEqual(live.difficulty(settings: settings), configuration.difficulty)
      XCTAssertEqual(live.modifiers(settings: settings), configuration.modifiers)
      XCTAssertEqual(ThresholdSettingsStore(defaults: defaults).read(), .available(settings.snapshot))
      let reader = AppSettings(defaults: defaults,
        feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
      XCTAssertEqual(reader.difficulty, configuration.difficulty)
      XCTAssertEqual(reader.testModifiers, configuration.modifiers)
    }
  }

  func testAppearancePartialCanExitEverySourceLibraryTemplateWithoutLosingItsParameters() throws {
    for challenge in TypebarChallengeLibrary.all {
      try withSettings { settings, _ in
        var template = challenge.preset
        template.configuration = template.configuration.with(challengeID: challenge.id)
        let configuration = try apply(template, to: settings)
        var live = ChallengeLiveConfigurationState()
        XCTAssertTrue(live.install(configuration, settings: settings))
        let current = SavedTestPreset(configuration: configuration, customText: template.customText,
          settingsSnapshot: live.snapshot(settings: settings))
        var snapshot = settings.snapshot
        snapshot.fontSize = 42
        let incoming = SavedTestPreset(configuration: .words(3, rules: settings.inputRules),
          settingsSnapshot: snapshot, settingGroups: [.appearance])
        let prepared = try XCTUnwrap(PresetSourcePreparation.preparing(incoming, to: settings,
          appliesGlobalSettings: true))
        let resolved = PresetApplicationPolicy.applying(current: current, preset: prepared.preset)
        XCTAssertNil(resolved.configuration.challengeID, challenge.id)
        XCTAssertEqual(resolved.configuration, configuration.with(challengeID: nil), challenge.id)
        XCTAssertEqual(resolved.customText, current.customText, challenge.id)
        XCTAssertTrue(PresetSettingsApplication.commit(original: prepared.preset, resolved: resolved,
          configuration: resolved.configuration, to: settings, appliesGlobalSettings: true,
          expectedSourceState: prepared.baseline, liveConfiguration: live), challenge.id)
        XCTAssertEqual(settings.fontSize, 42, challenge.id)
      }
    }
  }

  func testEachOrdinaryPartialOwnsOnlySelectedPersistentAndTransientFieldsWhenExitingChallenge() throws {
    for group in PresetSettingGroup.allCases {
      try withSettings { settings, _ in
        let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "round-hour"))
        var template = challenge.preset
        template.configuration = template.configuration.with(challengeID: challenge.id)
        let configuration = try apply(template, to: settings)
        var live = ChallengeLiveConfigurationState()
        XCTAssertTrue(live.install(configuration, settings: settings))
        let current = SavedTestPreset(configuration: configuration, settingsSnapshot: live.snapshot(settings: settings))
        let before = settings.snapshot
        var snapshot = before
        snapshot.difficulty = .master
        snapshot.testModifiers = [.mirrorKeyboard]
        snapshot.fontSize = 42
        snapshot.activeResultTags = ["incoming"]
        let incoming = SavedTestPreset(configuration: .words(3, difficulty: .master, rules: settings.inputRules)
          .with(modifiers: [.mirrorKeyboard]), activeResultTags: ["incoming"], settingsSnapshot: snapshot,
          settingGroups: [group])
        let prepared = try XCTUnwrap(PresetSourcePreparation.preparing(incoming, to: settings,
          appliesGlobalSettings: true))
        let resolved = PresetApplicationPolicy.applying(current: current, preset: prepared.preset)
        XCTAssertTrue(PresetSettingsApplication.commit(original: prepared.preset, resolved: resolved,
          configuration: resolved.configuration, to: settings, appliesGlobalSettings: true,
          expectedSourceState: prepared.baseline, liveConfiguration: live), group.rawValue)
        XCTAssertNil(resolved.configuration.challengeID)
        XCTAssertEqual(resolved.configuration.mode, group == .test ? .words : configuration.mode)
        XCTAssertEqual(settings.snapshot, resolved.settingsSnapshot)
        XCTAssertEqual(live.difficulty(settings: settings), group == .behavior ? .master : configuration.difficulty)
        XCTAssertEqual(live.modifiers(settings: settings), group == .behavior ? [.mirrorKeyboard] : configuration.modifiers)
      }
    }
  }

  func testRejectedOrdinaryPartialDoesNotChangeSourceChallengeOrPreferences() throws {
    for failure in ["lock", "profile", "selection"] {
      try withSettings { settings, defaults in
        let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "round-hour"))
        var template = challenge.preset
        template.configuration = template.configuration.with(challengeID: challenge.id)
        let configuration = try apply(template, to: settings)
        var live = ChallengeLiveConfigurationState()
        XCTAssertTrue(live.install(configuration, settings: settings))
        let current = SavedTestPreset(configuration: configuration, settingsSnapshot: live.snapshot(settings: settings))
        let incoming = SavedTestPreset(configuration: .words(3, rules: settings.inputRules),
          settingsSnapshot: settings.snapshot, settingGroups: [.appearance])
        let prepared = try XCTUnwrap(PresetSourcePreparation.preparing(incoming, to: settings,
          appliesGlobalSettings: true))
        let resolved = PresetApplicationPolicy.applying(current: current, preset: prepared.preset)
        let owner = UUID()
        if failure == "lock" { settings.setNoQuitConfigurationLock(true, for: owner) }
        else { defaults.set(Data("{\"version\":99}".utf8),
          forKey: failure == "profile" ? "appSettings.v4" : "activeTestSelection.v2") }
        defer { settings.setNoQuitConfigurationLock(false, for: owner) }
        let before = defaults.dictionaryRepresentation() as NSDictionary
        XCTAssertFalse(PresetSettingsApplication.commit(original: prepared.preset, resolved: resolved,
          configuration: resolved.configuration, to: settings, appliesGlobalSettings: true,
          expectedSourceState: prepared.baseline, liveConfiguration: live))
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
        XCTAssertEqual(current.configuration.challengeID, challenge.id)
      }
    }
  }

  func testPartialDoesNotOverwritePersistentPreferencesUnseenByTheCurrentOwner() throws {
    try withSettings { settings, defaults in
      let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "round-hour"))
      var template = challenge.preset
      template.configuration = template.configuration.with(challengeID: challenge.id)
      let configuration = try apply(template, to: settings)
      var live = ChallengeLiveConfigurationState()
      XCTAssertTrue(live.install(configuration, settings: settings))
      let current = SavedTestPreset(configuration: configuration, settingsSnapshot: live.snapshot(settings: settings))
      var external = settings.snapshot
      external.fontSize = 48
      XCTAssertTrue(ThresholdSettingsStore(defaults: defaults).save(external))
      var snapshot = settings.snapshot
      snapshot.theme = .midnight
      let incoming = SavedTestPreset(configuration: .words(3, rules: settings.inputRules),
        settingsSnapshot: snapshot, settingGroups: [.theme])
      let prepared = try XCTUnwrap(PresetSourcePreparation.preparing(incoming, to: settings,
        appliesGlobalSettings: true))
      let resolved = PresetApplicationPolicy.applying(current: current, preset: prepared.preset)
      XCTAssertFalse(PresetSettingsApplication.commit(original: prepared.preset, resolved: resolved,
        configuration: resolved.configuration, to: settings, appliesGlobalSettings: true,
        expectedSourceState: prepared.baseline, liveConfiguration: live))
      XCTAssertEqual(ThresholdSettingsStore(defaults: defaults).read(), .available(external))
      XCTAssertEqual(settings.fontSize, 31)
    }
  }

  func testLivePartialAdmissionRejectsUnselectedInjectionAndAnotherModelsState() throws {
    try withSettings { settings, defaults in
      let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "round-hour"))
      var template = challenge.preset
      template.configuration = template.configuration.with(challengeID: challenge.id)
      let configuration = try apply(template, to: settings)
      var live = ChallengeLiveConfigurationState()
      XCTAssertTrue(live.install(configuration, settings: settings))
      let current = SavedTestPreset(configuration: configuration, settingsSnapshot: live.snapshot(settings: settings))
      let incoming = SavedTestPreset(configuration: .words(3, rules: settings.inputRules),
        settingsSnapshot: settings.snapshot, settingGroups: [.input])
      let prepared = try XCTUnwrap(PresetSourcePreparation.preparing(incoming, to: settings,
        appliesGlobalSettings: true))
      let clean = PresetApplicationPolicy.applying(current: current, preset: prepared.preset)
      let before = defaults.dictionaryRepresentation() as NSDictionary
      var injected = clean
      injected.settingsSnapshot?.fontSize = 99
      XCTAssertFalse(PresetSettingsApplication.commit(original: prepared.preset, resolved: injected,
        configuration: injected.configuration, to: settings, appliesGlobalSettings: true,
        expectedSourceState: prepared.baseline, liveConfiguration: live))
      try withSettings { other, _ in
        var foreign = ChallengeLiveConfigurationState()
        XCTAssertTrue(foreign.install(configuration, settings: other))
        XCTAssertFalse(PresetSettingsApplication.commit(original: prepared.preset, resolved: clean,
          configuration: clean.configuration, to: settings, appliesGlobalSettings: true,
          expectedSourceState: prepared.baseline, liveConfiguration: foreign))
      }
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
    }
  }

  func testSceneCommitsBeforeClearingQualificationAndRetainsEphemeralSources() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    let start = try XCTUnwrap(source.range(of: "@discardableResult private func apply("))
    let body = source[start.lowerBound...]
    let commit = try XCTUnwrap(body.range(of: "guard PresetSettingsApplication.commit("))
    let selection = try XCTUnwrap(body.range(of: "customWordDurationSelection.accept(configuration)"))
    let identity = try XCTUnwrap(body.range(of: "if appliesTest || appliesGlobalSettings { activeChallengeID = challenge?.id }"))
    XCTAssertLessThan(commit.lowerBound, selection.lowerBound)
    XCTAssertLessThan(selection.lowerBound, identity.lowerBound)
    XCTAssertTrue(source.contains("verifiedScript: activeVerifiedScript,"))
    XCTAssertTrue(source.contains("if activeVerifiedScript != nil { return }"))
    XCTAssertTrue(source.contains("customWordDurationSelection.reconcile(mode: mode"))
  }

  func testLegacyAndOrdinaryCapturesDoNotAdoptSourceOrMutateTheirInput() throws {
    let original = SavedTestPreset(configuration: .words(25).with(challengeID: "clean-twenty-five"),
      activeResultTags: ["legacy"], settingsSnapshot: .init())
    let captured = original.capturedForLibrary(settingGroups: [.test, .behavior])
    XCTAssertNil(captured.configuration.challengeID)
    XCTAssertNil(captured.configuration.rules.thresholdSource)
    XCTAssertNil(captured.settingsSnapshot?.thresholdSource)
    XCTAssertEqual(captured.activeResultTags, original.activeResultTags)
    XCTAssertEqual(try LocalPresetCodec.decode(LocalPresetCodec.encode(captured)), captured)
    XCTAssertEqual(original.configuration.challengeID, "clean-twenty-five")
    var ordinary = original
    ordinary.configuration.challengeID = nil
    XCTAssertEqual(ordinary.capturedForLibrary(settingGroups: nil), ordinary)
  }

  func testNewAndUpdatedPresetUIUseOrdinaryLibraryCapture() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TestPresets.swift"),
      encoding: .utf8)
    XCTAssertEqual(source.components(separatedBy: "currentPreset.capturedForLibrary(").count - 1, 2)
    XCTAssertFalse(source.contains("currentPreset.with("))
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
