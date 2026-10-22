import XCTest
@testable import Typebar

@MainActor
final class ChallengeInputRuleApplicationTests: XCTestCase {
  private func withSettings(_ body: (AppSettings, UserDefaults) throws -> Void) throws {
    let suite = "typebar.challenge-input-rules.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults,
      feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
    XCTAssertTrue(settings.apply(.init(strictSpace: true, hideExtraLetters: true, blindMode: true,
      quickEnd: true, minimumAccuracy: 91, minimumWpm: 37, minimumWordBurstWpm: 48,
      minimumWordBurstMode: .flex)))
    try body(settings, defaults)
  }

  private func commit(_ preset: SavedTestPreset, to settings: AppSettings) -> Bool {
    PresetSettingsApplication.commit(original: preset, resolved: preset,
      configuration: preset.configuration, to: settings, appliesGlobalSettings: true)
  }

  func testEveryBuiltInChallengeKeepsCurrentInputRulesWhenApplied() throws {
    for challenge in TypebarChallengeLibrary.all {
      try withSettings { settings, _ in
        let before = settings.inputRules
        var preset = challenge.preset
        preset.configuration = preset.configuration.with(challengeID: challenge.id)
        XCTAssertTrue(commit(preset, to: settings), challenge.id)
        XCTAssertEqual(settings.inputRules, before, challenge.id)
        XCTAssertEqual(settings.difficulty, challenge.preset.configuration.difficulty, challenge.id)
      }
    }
  }

  func testOrdinaryPresetStillReplacesItsOwnedInputRules() throws {
    try withSettings { settings, _ in
      let preset = SavedTestPreset(configuration: .words(3))
      XCTAssertTrue(commit(preset, to: settings))
      XCTAssertEqual(settings.inputRules, preset.configuration.rules)
    }
  }

  func testExplicitChallengeSnapshotStillOwnsSavedRules() throws {
    try withSettings { settings, _ in
      let challenge = try XCTUnwrap(TypebarChallengeLibrary.all.first)
      var preset = challenge.preset
      preset.configuration = preset.configuration.with(challengeID: challenge.id)
      preset.settingsSnapshot = .init(strictSpace: false, minimumWpm: 12)
      XCTAssertTrue(commit(preset, to: settings))
      XCTAssertFalse(settings.strictSpace)
      XCTAssertEqual(settings.minimumWpm, 12)
    }
  }

  func testRebuiltChallengeSessionUsesPreservedAccuracyAndKeepsItsIdentity() throws {
    try withSettings { settings, _ in
      let challenge = try XCTUnwrap(TypebarChallengeLibrary.all.first)
      var preset = challenge.preset
      preset.configuration = preset.configuration.with(challengeID: challenge.id)
      XCTAssertTrue(commit(preset, to: settings))
      let configuration = ChallengeInputRulePolicy.applying(settings.inputRules, to: preset.configuration)
      var withoutRules = configuration
      withoutRules.rules = preset.configuration.rules
      XCTAssertEqual(withoutRules, preset.configuration)
      var session = TypingSession(configuration: configuration, prompt: "amber bay cedar delta")
      let start = Date(timeIntervalSince1970: 100)
      session.insert("ax", at: start)
      session.enforceLivePracticeThresholds(at: start.addingTimeInterval(1))
      XCTAssertEqual(session.failureReason, .minimumAccuracy)
      XCTAssertEqual(session.configuration.challengeID, challenge.id)
      let rebuilt = ChallengeInputRulePolicy.applying(settings.inputRules, to: preset.configuration)
      XCTAssertEqual(rebuilt.rules, settings.inputRules)
    }
  }

  func testProjectionRetainsCompleteSourceWithoutWritingOrEnablingSourceChallenges() throws {
    try withSettings { _, defaults in
      var raw = PracticeThresholdConfiguration()
      try raw.apply(.minimumWpm(mode: .custom, customValue: 0))
      try raw.apply(.minimumAccuracy(mode: .off, customValue: 93))
      try raw.apply(.minimumWordBurst(mode: .flex, customValue: 0))
      let source = PracticeThresholdSource(configuration: raw)
      XCTAssertTrue(ThresholdSettingsStore(defaults: defaults).save(source.applying(to: .init())))
      let settings = AppSettings(defaults: defaults,
        feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
      let before = defaults.dictionaryRepresentation() as NSDictionary
      let challenge = try XCTUnwrap(TypebarChallengeLibrary.all.first)
      var preset = challenge.preset
      preset.configuration = preset.configuration.with(challengeID: challenge.id)
      let configuration = ChallengeInputRulePolicy.applying(settings.inputRules, to: preset.configuration)
      XCTAssertEqual(configuration.rules.thresholdSource, source)
      XCTAssertFalse(commit(preset, to: settings))
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
    }
  }

  func testNoQuitRejectsBeforeAnyChallengeSettingsWrite() throws {
    try withSettings { settings, defaults in
      let owner = UUID()
      settings.setNoQuitConfigurationLock(true, for: owner)
      defer { settings.setNoQuitConfigurationLock(false, for: owner) }
      let before = defaults.dictionaryRepresentation() as NSDictionary
      let challenge = try XCTUnwrap(TypebarChallengeLibrary.all.first)
      var preset = challenge.preset
      preset.configuration = preset.configuration.with(challengeID: challenge.id)
      XCTAssertFalse(commit(preset, to: settings))
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
    }
  }
}
