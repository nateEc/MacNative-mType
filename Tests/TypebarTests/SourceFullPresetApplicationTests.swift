import XCTest
@testable import Typebar

@MainActor
final class SourceFullPresetApplicationTests: XCTestCase {
  private func withSettings(_ body: (AppSettings, UserDefaults) throws -> Void) throws {
    let suite = "typebar.source-full-preset.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var raw = PracticeThresholdConfiguration()
    try raw.apply(.minimumWpm(mode: .off, customValue: 37))
    XCTAssertTrue(ThresholdSettingsStore(defaults: defaults).save(
      PracticeThresholdSource(configuration: raw).applying(to: AppSettingsSnapshot(fontSize: 31))))
    let feedback = TypingFeedbackSound(loadSound: { _ in nil }, beep: {})
    try body(AppSettings(defaults: defaults, feedbackSound: feedback, localBackgroundStore: .inMemory()), defaults)
  }

  private func preset(snapshot: Bool) throws -> SavedTestPreset {
    var raw = PracticeThresholdConfiguration()
    try raw.apply(.minimumWpm(mode: .custom, customValue: 0))
    try raw.apply(.minimumWordBurst(mode: .fixed, customValue: 0))
    let source = PracticeThresholdSource(configuration: raw)
    let rules = source.applying(to: InputRules(strictSpace: true))
    var settings = source.applying(to: AppSettingsSnapshot(strictSpace: true, fontSize: 35))
    settings.activeResultTags = ["snapshot-tag"]
    return .init(configuration: .words(3, rules: rules), activeResultTags: ["preset-tag"],
      settingsSnapshot: snapshot ? settings : nil)
  }

  func testFullSourceSnapshotAndTagAliasCommitTogether() throws {
    try withSettings { settings, defaults in
      let incoming = try preset(snapshot: true)
      XCTAssertTrue(PresetSettingsApplication.commit(original: incoming, resolved: incoming,
        configuration: incoming.configuration, to: settings, appliesGlobalSettings: true))
      var expected = try XCTUnwrap(incoming.settingsSnapshot)
      expected.activeResultTags = ["preset-tag"]
      XCTAssertEqual(settings.snapshot, expected)
      XCTAssertEqual(ThresholdSettingsStore(defaults: defaults).read(), .available(expected))
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWpmMode, .custom)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWordBurstMode, .fixed)
    }
  }

  func testRulesOnlyPresetCommitsTagsWithoutReapplyingAppearance() throws {
    try withSettings { settings, defaults in
      let incoming = try preset(snapshot: false)
      let fontRevision = settings.practiceFontApplicationRevision
      let animationRevision = settings.animationFrameRateRevision
      XCTAssertTrue(PresetSettingsApplication.commit(original: incoming, resolved: incoming,
        configuration: incoming.configuration, to: settings, appliesGlobalSettings: true))
      XCTAssertEqual(settings.inputRules, incoming.configuration.rules)
      XCTAssertEqual(settings.activeResultTags, ["preset-tag"])
      XCTAssertEqual(settings.fontSize, 31)
      XCTAssertEqual(settings.practiceFontApplicationRevision, fontRevision)
      XCTAssertEqual(settings.animationFrameRateRevision, animationRevision)
      XCTAssertEqual(ThresholdSettingsStore(defaults: defaults).read(), .available(settings.snapshot))
    }
  }

  func testStoredFullSourcePresetIsAvailableToTheExistingApplicationPath() throws {
    let incoming = try preset(snapshot: true)
    let record = try TestPresetRecord(name: "Source full", definition: incoming)
    XCTAssertEqual(record.applicableDefinition, incoming)
  }

  func testSnapshotRuleDifficultyVariantAndModifierDisagreementsDoNotWrite() throws {
    try withSettings { settings, defaults in
      let incoming = try preset(snapshot: true)
      var conflicting: [SavedTestPreset] = []
      var copy = incoming
      copy.settingsSnapshot?.strictSpace = false
      conflicting.append(copy)
      copy = incoming
      copy.configuration.difficulty = .expert
      conflicting.append(copy)
      copy = incoming
      copy.configuration.englishVariant = .british
      conflicting.append(copy)
      copy = incoming
      copy.configuration.modifiers = [.lazyLatin]
      conflicting.append(copy)
      let domain = defaults.dictionaryRepresentation() as NSDictionary
      let before = settings.snapshot
      for definition in conflicting {
        XCTAssertFalse(PresetSettingsApplication.commit(original: definition, resolved: definition,
          configuration: definition.configuration, to: settings, appliesGlobalSettings: true))
        XCTAssertEqual(settings.snapshot, before)
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, domain)
      }
    }
  }

  func testAutomaticallyDerivedArabicModifierDoesNotRejectCapturedPreset() throws {
    try withSettings { settings, defaults in
      var incoming = try preset(snapshot: true)
      incoming.configuration.language = .arabic
      incoming.configuration.modifiers = [.lazyLatin]
      XCTAssertEqual(incoming.settingsSnapshot?.testModifiers, [])
      XCTAssertTrue(PresetSettingsApplication.commit(original: incoming, resolved: incoming,
        configuration: incoming.configuration, to: settings, appliesGlobalSettings: true))
      XCTAssertEqual(settings.testModifiers, [])
      XCTAssertEqual(ThresholdSettingsStore(defaults: defaults).read(), .available(settings.snapshot))
    }
  }

  func testEmptyTagAliasClearsAndAbsentAliasUsesSnapshotTags() throws {
    try withSettings { settings, defaults in
      var incoming = try preset(snapshot: true)
      for tags: [String]? in [nil, []] {
        incoming.activeResultTags = tags
        XCTAssertTrue(PresetSettingsApplication.commit(original: incoming, resolved: incoming,
          configuration: incoming.configuration, to: settings, appliesGlobalSettings: true))
        XCTAssertEqual(settings.activeResultTags, tags ?? ["snapshot-tag"])
        XCTAssertEqual(ThresholdSettingsStore(defaults: defaults).read(), .available(settings.snapshot))
      }
    }
  }

  func testDerivedConfigurationCannotReplaceResolvedFullPreset() throws {
    try withSettings { settings, defaults in
      let incoming = try preset(snapshot: true)
      let domain = defaults.dictionaryRepresentation() as NSDictionary
      var different = incoming.configuration
      different.rules.strictSpace = false
      XCTAssertFalse(PresetSettingsApplication.commit(original: incoming, resolved: incoming,
        configuration: different, to: settings, appliesGlobalSettings: true))
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, domain)
    }
  }

  func testCommittedPresetSurvivesNewReaderAndStartsActualSession() throws {
    try withSettings { settings, defaults in
      let record = try TestPresetRecord(name: "Full", definition: preset(snapshot: true))
      let incoming = try XCTUnwrap(record.applicableDefinition)
      XCTAssertTrue(PresetSettingsApplication.commit(original: incoming, resolved: incoming,
        configuration: incoming.configuration, to: settings, appliesGlobalSettings: true))
      let reader = AppSettings(defaults: defaults,
        feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}),
        localBackgroundStore: .inMemory())
      XCTAssertEqual(reader.snapshot, settings.snapshot)
      XCTAssertEqual(reader.inputRules, incoming.configuration.rules)
      var effective = incoming.configuration
      effective.rules = reader.inputRules
      var session = TestSessionFactory.make(configuration: effective)
      XCTAssertEqual(session.configuration.rules.thresholdSource, incoming.configuration.rules.thresholdSource)
      session.insertBatch(session.prompt, at: Date(timeIntervalSince1970: 100))
      XCTAssertEqual(session.outcome, .completed)
    }
  }

  func testGlobalSourceAdmissionKeepsLockUnknownStoresAndUnsupportedPresetsUnchanged() throws {
    try withSettings { settings, defaults in
      let incoming = try preset(snapshot: true)
      var blocked = [incoming.with(settingGroups: [])]
      var challenge = incoming
      challenge.configuration.challengeID = "ten-words-of-pain"
      blocked.append(challenge)
      var noncanonicalTags = incoming
      noncanonicalTags.activeResultTags = [" tag "]
      blocked.append(noncanonicalTags)
      let before = settings.snapshot
      var domain = defaults.dictionaryRepresentation() as NSDictionary
      for definition in blocked {
        XCTAssertFalse(PresetSettingsApplication.commit(original: definition, resolved: definition,
          configuration: definition.configuration, to: settings, appliesGlobalSettings: true))
        XCTAssertEqual(settings.snapshot, before)
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, domain)
      }
      let owner = UUID()
      settings.setNoQuitConfigurationLock(true, for: owner)
      XCTAssertFalse(PresetSettingsApplication.commit(original: incoming, resolved: incoming,
        configuration: incoming.configuration, to: settings, appliesGlobalSettings: true))
      settings.setNoQuitConfigurationLock(false, for: owner)
      XCTAssertEqual(settings.snapshot, before)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, domain)
      for key in ["activeTestSelection.v2", "appSettings.v4"] {
        let saved = defaults.data(forKey: key)
        defaults.set(Data("{\"version\":99}".utf8), forKey: key)
        domain = defaults.dictionaryRepresentation() as NSDictionary
        XCTAssertFalse(PresetSettingsApplication.commit(original: incoming, resolved: incoming,
          configuration: incoming.configuration, to: settings, appliesGlobalSettings: true))
        XCTAssertEqual(settings.snapshot, before)
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, domain)
        if let saved { defaults.set(saved, forKey: key) }
        else { defaults.removeObject(forKey: key) }
      }
    }
  }

  func testSourcePresetCannotAdoptLegacyProfile() throws {
    let suite = "typebar.source-full-no-adoption.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults,
      feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
    let incoming = try preset(snapshot: true)
    let domain = defaults.dictionaryRepresentation() as NSDictionary
    XCTAssertFalse(PresetSettingsApplication.commit(original: incoming, resolved: incoming,
      configuration: incoming.configuration, to: settings, appliesGlobalSettings: true))
    XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, domain)
    XCTAssertNil(defaults.data(forKey: "appSettings.v4"))
  }
}
