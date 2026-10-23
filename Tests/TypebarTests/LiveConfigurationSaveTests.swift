import XCTest
@testable import Typebar

@MainActor
final class LiveConfigurationSaveTests: XCTestCase {
  private func withLive(source: Bool,
    _ body: (AppSettings, UserDefaults, ChallengeLiveConfigurationState) throws -> Void) throws {
    let suite = "typebar.live-config-save.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    if source {
      let snapshot = AppSettingsSnapshot(difficulty: .expert, installedPracticeFontName: "Menlo",
        showKeyboardGuide: true, keyboardGuideMode: .react)
      XCTAssertTrue(ThresholdSettingsStore(defaults: defaults).save(
        PracticeThresholdSource(configuration: .init()).applying(to: snapshot)))
    }
    let settings = AppSettings(defaults: defaults,
      feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
    if !source {
      settings.difficulty = .expert
      settings.installedPracticeFontName = "Menlo"
      settings.keyboardGuideMode = .react
    }
    let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "ten-words-of-pain"))
    let configuration = ChallengeInputRulePolicy.applying(settings.inputRules,
      to: challenge.preset.configuration.with(challengeID: challenge.id))
    var live = ChallengeLiveConfigurationState()
    if source { XCTAssertTrue(live.install(configuration, settings: settings)) }
    else { XCTAssertTrue(live.observeLegacyChallenge(settings: settings, configuration: configuration)) }
    try body(settings, defaults, live)
  }

  private func save(_ settings: AppSettings, _ live: ChallengeLiveConfigurationState) -> Bool {
    settings.persistLiveConfiguration(live)
  }

  private func revisions(_ settings: AppSettings) -> [UInt64] {
    [settings.difficultyApplicationRevision, settings.testModifiersApplicationRevision,
      settings.practiceFontApplicationRevision, settings.keyboardGuideApplicationRevision,
      settings.challengePresentationApplicationRevision, settings.practiceWrapperRevision]
  }

  func testSavingTheCompleteCurrentConfigurationDoesNotReplayApplicationEvents() throws {
    for source in [false, true] {
      try withLive(source: source) { settings, defaults, live in
        let expected = live.snapshot(settings: settings)
        let before = revisions(settings)
        XCTAssertNotEqual(expected.installedPracticeFontName, settings.installedPracticeFontName)
        XCTAssertTrue(live.isQualificationCurrent(settings: settings))
        XCTAssertTrue(save(settings, live))
        XCTAssertEqual(revisions(settings), before)
        XCTAssertTrue(live.isQualificationCurrent(settings: settings))
        let restored = AppSettings(defaults: defaults,
          feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
        XCTAssertEqual(restored.snapshot, expected)
        XCTAssertEqual(settings.snapshot, expected)
        XCTAssertEqual(settings.hasThresholdProfile, source)
        settings.soundVolume = 0.42
        let later = AppSettings(defaults: defaults,
          feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
        XCTAssertEqual(later.installedPracticeFontName, expected.installedPracticeFontName)
        XCTAssertEqual(later.keyboardGuideMode, expected.keyboardGuideMode)
        XCTAssertEqual(later.difficulty, expected.difficulty)
      }
    }
  }

  func testSavingCurrentValuesIsAllowedUnderNoQuitWithoutUnlockingTheAttempt() throws {
    try withLive(source: true) { settings, _, live in
      let owner = UUID()
      settings.setNoQuitConfigurationLock(true, for: owner)
      defer { settings.setNoQuitConfigurationLock(false, for: owner) }
      XCTAssertFalse(settings.allowsRestartingConfigurationChange)
      let before = revisions(settings)
      XCTAssertTrue(save(settings, live))
      XCTAssertFalse(settings.allowsRestartingConfigurationChange)
      XCTAssertEqual(revisions(settings), before)
      XCTAssertTrue(live.isQualificationCurrent(settings: settings))
    }
  }

  func testFunboxConfirmationSavesTheLiveSnapshotAndPromotesPracticeOnlyAfterSuccess() throws {
    try withLive(source: true) { settings, defaults, live in
      let expectedDifficulty = live.difficulty(settings: settings)
      let original = ActiveTestSelectionDocument(preset: .init(configuration: .words(17)), testParameterMemory: .defaults)
      let practice = try XCTUnwrap(WordPracticeText.sectionedPractice(segments: ["a|b"], selectedTargetCount: 1))
      var navigation = try XCTUnwrap(WordPracticeTransition.begin(previous: nil, practice: practice,
        currentPreset: { original.preset }, currentSelection: { _ in original }, selectCustomMode: { true }))
      let store = ActiveTestSelectionStore(defaults: defaults)
      XCTAssertTrue(store.save(original))
      @MainActor func current() -> ActiveTestSelectionDocument {
        .init(preset: .init(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
          difficulty: settings.difficulty, rules: settings.inputRules,
          customTextCompletion: .sections, customTextSectionLimit: 1,
          customTextOrdering: practice.ordering, customTextPipeDelimiter: true,
          modifiers: settings.testModifiers), customText: practice.text), testParameterMemory: .defaults)
      }
      let owner = UUID()
      var confirmations = 0
      var committed = false
      settings.preferenceConfigurationSaves.register(owner: owner,
        requestedModifiers: { live.modifiers(settings: settings) }, selectedLanguage: { .english }) {
        confirmations += 1
        committed = self.save(settings, live)
        if committed { _ = navigation.persistSelection(current: current(), cause: .configurationSave, save: store.save) }
      }
      defer { settings.preferenceConfigurationSaves.remove(owner: owner) }
      let controls = PracticeFunboxPreferences(settings: settings)
      // Two individually compatible visual owners exercise noncanonical raw
      // insertion order as well as the complete live snapshot after the event.
      controls.selection(for: .roundVisual).wrappedValue = true
      controls.selection(for: .mirrorVisual).wrappedValue = true
      controls.selection(for: .mirrorVisual).wrappedValue = true
      XCTAssertTrue(committed)
      XCTAssertEqual(confirmations, 2)
      XCTAssertEqual(store.load(), current())
      XCTAssertTrue(navigation.persistSelection(current: current(), cause: .automatic, save: store.save))
      XCTAssertEqual(ActiveTestSelectionStore(defaults: defaults).load(), current())
      let restored = AppSettings(defaults: defaults,
        feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
      XCTAssertEqual(restored.difficulty, expectedDifficulty)
      XCTAssertEqual(restored.installedPracticeFontName, WingdingsChallengeFont.familyName)
      XCTAssertEqual(restored.keyboardGuideMode, .off)
      XCTAssertEqual(Set(restored.testModifiers), Set([.roundVisual, .mirrorVisual]))
    }
  }

  func testFutureSourceAndExternalProfileChangesAreNotOverwritten() throws {
    try withLive(source: true) { settings, defaults, live in
      let before = settings.snapshot, epoch = revisions(settings)
      var external = before
      external.soundVolume = 0.73
      XCTAssertTrue(ThresholdSettingsStore(defaults: defaults).save(external))
      XCTAssertFalse(save(settings, live))
      XCTAssertEqual(settings.snapshot, before)
      XCTAssertEqual(settings.thresholdProfileRead, .available(external))
      XCTAssertEqual(revisions(settings), epoch)
      let future = Data("{\"version\":999}".utf8)
      defaults.set(future, forKey: ThresholdSettingsStore.storageKey)
      XCTAssertFalse(save(settings, live))
      XCTAssertEqual(defaults.data(forKey: ThresholdSettingsStore.storageKey), future)
      XCTAssertEqual(settings.snapshot, before)
    }
  }

  func testSavingTheNamedFontHasNoLocalFileHandoffOrAdditionalFontEvents() throws {
    try withLive(source: true) { settings, defaults, live in
      let before = revisions(settings)
      XCTAssertTrue(settings.persistLiveConfiguration(live))
      XCTAssertEqual(revisions(settings), before)
      XCTAssertEqual(settings.installedPracticeFontName, WingdingsChallengeFont.familyName)
      XCTAssertEqual(AppSettings(defaults: defaults,
        feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}),
        localBackgroundStore: .inMemory()).installedPracticeFontName, WingdingsChallengeFont.familyName)
      XCTAssertTrue(live.isQualificationCurrent(settings: settings))
    }
  }

  func testForeignOverlayIsRefusedEvenWhenItsProjectionWouldBeEmpty() throws {
    try withLive(source: true) { _, _, live in
      let suite = "typebar.foreign-live-save.\(UUID().uuidString)"
      let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      defer { defaults.removePersistentDomain(forName: suite) }
      let other = AppSettings(defaults: defaults,
        feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
      let before = defaults.dictionaryRepresentation() as NSDictionary
      XCTAssertFalse(save(other, live))
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
    }
  }

  func testRejectedAndLockedFunboxBindingsNeverDispatchAConfigurationSave() throws {
    try withLive(source: true) { settings, defaults, _ in
      settings.testModifiers = [.roundVisual]
      let owner = UUID()
      var saves = 0
      settings.preferenceConfigurationSaves.register(owner: owner) { saves += 1 }
      defer {
        settings.preferenceConfigurationSaves.remove(owner: owner)
        settings.setNoQuitConfigurationLock(false, for: owner)
      }
      let before = defaults.dictionaryRepresentation() as NSDictionary
      let epoch = revisions(settings)
      let controls = PracticeFunboxPreferences(settings: settings,
        acceptsChange: { settings.allowsRestartingConfigurationChange })
      controls.selection(for: .nauseaVisual).wrappedValue = true
      settings.setNoQuitConfigurationLock(true, for: owner)
      controls.selection(for: .mirrorVisual).wrappedValue = true
      XCTAssertEqual(saves, 0)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
      XCTAssertEqual(revisions(settings), epoch)
    }
  }

  func testFailedFullSaveDoesNotPromoteTheWordPracticeNavigationRecord() throws {
    try withLive(source: true) { settings, defaults, live in
      let original = ActiveTestSelectionDocument(preset: .init(configuration: .words(17)), testParameterMemory: .defaults)
      let practice = try XCTUnwrap(WordPracticeText.sectionedPractice(segments: ["a|b"], selectedTargetCount: 1))
      var navigation = try XCTUnwrap(WordPracticeTransition.begin(previous: nil, practice: practice,
        currentPreset: { original.preset }, currentSelection: { _ in original }, selectCustomMode: { true }))
      let store = ActiveTestSelectionStore(defaults: defaults)
      XCTAssertTrue(store.save(original))
      let owner = UUID()
      var saved: Bool?
      settings.preferenceConfigurationSaves.register(owner: owner,
        requestedModifiers: { live.modifiers(settings: settings) }) {
        saved = self.save(settings, live)
        if saved == true {
          _ = navigation.persistSelection(current: original, cause: .configurationSave, save: store.save)
        }
      }
      defer { settings.preferenceConfigurationSaves.remove(owner: owner) }
      let future = Data("{\"version\":999}".utf8)
      defaults.set(future, forKey: ThresholdSettingsStore.storageKey)
      PracticeFunboxPreferences(settings: settings).selection(for: .mirrorVisual).wrappedValue = true
      XCTAssertEqual(saved, false)
      XCTAssertEqual(defaults.data(forKey: ThresholdSettingsStore.storageKey), future)
      XCTAssertEqual(store.load(), original)
      var changed = original
      changed = .init(preset: .init(configuration: .words(18)), testParameterMemory: .defaults)
      XCTAssertEqual(navigation.persistedSelection(current: changed), original)
    }
  }

  func testDetachedLegacyObserverCannotAuthorizeAnotherModelsSave() throws {
    let suite = "typebar.detached-live-save.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var detached = ChallengeLiveConfigurationState()
    do {
      let original = AppSettings(defaults: defaults,
        feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
      XCTAssertTrue(detached.observeLegacyChallenge(settings: original))
    }
    let other = AppSettings(defaults: defaults,
      feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
    let before = defaults.dictionaryRepresentation() as NSDictionary
    XCTAssertFalse(save(other, detached))
    XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
  }

  func testPristineOrdinaryWindowCanSaveWithoutAdoptingANewGeneration() throws {
    let suite = "typebar.pristine-live-save.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults,
      feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
    let before = revisions(settings)
    XCTAssertTrue(save(settings, .init()))
    XCTAssertEqual(revisions(settings), before)
    XCTAssertNil(defaults.object(forKey: ThresholdSettingsStore.storageKey))
  }

  func testMainPersistsTheFullSnapshotBeforePromotingThePracticeSelection() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let app = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    let start = try XCTUnwrap(app.range(of: "private func persistExplicitTestConfiguration()"))
    let end = try XCTUnwrap(app.range(of: "private func persistActiveTestSelection", range: start.upperBound..<app.endIndex))
    let body = String(app[start.lowerBound..<end.lowerBound])
    let snapshot = try XCTUnwrap(body.range(of: "guard settings.persistLiveConfiguration(challengeLiveConfiguration)"))
    let selection = try XCTUnwrap(body.range(of: "guard wordPractice != nil"))
    XCTAssertLessThan(snapshot.lowerBound, selection.lowerBound)
    XCTAssertTrue(body.contains("cause: .configurationSave"))
    XCTAssertTrue(body.contains("account.localNotices.post("))
  }
}
