import XCTest
@testable import Typebar

@MainActor
final class SourcePartialPresetApplicationTests: XCTestCase {
  private func definition(memory: Double, incoming: Bool) throws -> SavedTestPreset {
    var raw = PracticeThresholdConfiguration()
    try raw.apply(.minimumWpm(mode: .off, customValue: memory))
    try raw.apply(.minimumWordBurst(mode: incoming ? .flex : .fixed, customValue: 0))
    let source = PracticeThresholdSource(configuration: raw)
    var snapshot = source.applying(to: AppSettingsSnapshot(fontSize: incoming ? 41 : 31))
    snapshot.difficulty = incoming ? .expert : .normal
    snapshot.englishVariant = incoming ? .british : .american
    snapshot.strictSpace = incoming
    snapshot.blindMode = incoming
    snapshot.repeatQuotes = incoming
    snapshot.soundVolume = incoming ? 0.8 : 0.2
    snapshot.caretStyle = incoming ? .outline : .bar
    snapshot.theme = incoming ? .midnight : .paper
    snapshot.showKeyTips = !incoming
    snapshot.showTypingCompanion = incoming
    snapshot.showWordBurstHeatmap = incoming
    snapshot.activeResultTags = incoming ? ["snapshot"] : ["current"]
    let rules = source.applying(to: InputRules(strictSpace: incoming, blindMode: incoming))
    var configuration = incoming ? TestConfiguration.timed(seconds: 60) : .words(3)
    configuration.rules = rules
    configuration.difficulty = snapshot.difficulty
    configuration.englishVariant = snapshot.englishVariant
    return .init(configuration: configuration,
      activeResultTags: incoming ? ["incoming"] : ["current"], settingsSnapshot: snapshot)
  }

  private func withSettings(_ body: (AppSettings, UserDefaults, SavedTestPreset) throws -> Void) throws {
    let suite = "typebar.source-partial.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let current = try definition(memory: 37, incoming: false)
    XCTAssertTrue(ThresholdSettingsStore(defaults: defaults).save(try XCTUnwrap(current.settingsSnapshot)))
    try body(AppSettings(defaults: defaults,
      feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory()),
      defaults, current)
  }

  private func commit(_ incoming: SavedTestPreset, current: SavedTestPreset, settings: AppSettings) -> SavedTestPreset {
    let resolved = PresetApplicationPolicy.applying(current: current, preset: incoming)
    XCTAssertTrue(PresetSettingsApplication.commit(original: incoming, resolved: resolved,
      configuration: resolved.configuration, to: settings, appliesGlobalSettings: true))
    return resolved
  }

  private func expectedSnapshot(_ before: AppSettingsSnapshot, incoming: SavedTestPreset,
    groups: Set<PresetSettingGroup>) -> AppSettingsSnapshot {
    var expected = before
    for group in groups {
      switch group {
      case .test: expected.showWordBurstHeatmap = true
      case .behavior:
        expected.difficulty = .expert
        expected.englishVariant = .british
        expected.blindMode = true
        expected.repeatQuotes = true
        expected.thresholdSource = incoming.configuration.rules.thresholdSource
        expected.activeResultTags = ["incoming"]
      case .input: expected.strictSpace = true
      case .sound: expected.soundVolume = 0.8
      case .caret: expected.caretStyle = .outline
      case .appearance: expected.fontSize = 41
      case .theme: expected.theme = .midnight
      case .hideElements: expected.showKeyTips = false
      case .hidden: expected.showTypingCompanion = true
      }
    }
    return expected
  }

  func testEachGroupChangesOnlyItsOwnedSnapshotFieldsAndEvents() throws {
    for group in PresetSettingGroup.allCases {
      try withSettings { settings, defaults, current in
        let incoming = try definition(memory: 73, incoming: true).with(settingGroups: [group])
        let before = settings.snapshot
        let fontRevision = settings.practiceFontApplicationRevision
        let animationRevision = settings.animationFrameRateRevision
        let resolved = commit(incoming, current: current, settings: settings)
        let expected = expectedSnapshot(before, incoming: incoming, groups: [group])
        XCTAssertEqual(settings.snapshot, expected, "group: \(group)")
        XCTAssertEqual(settings.inputRules, resolved.configuration.rules, "group: \(group)")
        XCTAssertEqual(ThresholdSettingsStore(defaults: defaults).read(), .available(expected))
        if group != .appearance {
          XCTAssertEqual(settings.practiceFontApplicationRevision, fontRevision)
          XCTAssertEqual(settings.animationFrameRateRevision, animationRevision)
        } else {
          XCTAssertGreaterThan(settings.practiceFontApplicationRevision, fontRevision)
        }
        XCTAssertEqual(resolved.configuration.mode, group == .test ? .time : .words)
      }
    }
  }

  func testBehaviorMergeIncludesBlindModeInBothLegacyAndSourceSnapshots() throws {
    for source in [false, true] {
      var current = try definition(memory: 37, incoming: false)
      var incoming = try definition(memory: 73, incoming: true)
      if !source {
        current.configuration.rules.thresholdSource = nil
        current.settingsSnapshot?.thresholdSource = nil
        incoming.configuration.rules.thresholdSource = nil
        incoming.settingsSnapshot?.thresholdSource = nil
      }
      let resolved = PresetApplicationPolicy.applying(current: current,
        preset: incoming.with(settingGroups: [.behavior]))
      XCTAssertTrue(resolved.configuration.rules.blindMode)
      XCTAssertEqual(resolved.settingsSnapshot?.blindMode, true)
    }
  }

  func testRulesOnlyPartialPresetsProjectTheirOwnedRulesIntoTheSnapshot() throws {
    for groups: Set<PresetSettingGroup> in [[.behavior], [.input], [.behavior, .input]] {
      try withSettings { settings, defaults, current in
        var incoming = try definition(memory: 73, incoming: true).with(settingGroups: groups)
        incoming.settingsSnapshot = nil
        let resolved = commit(incoming, current: current, settings: settings)
        XCTAssertEqual(settings.inputRules, resolved.configuration.rules)
        XCTAssertEqual(settings.difficulty, groups.contains(.behavior) ? .expert : .normal)
        XCTAssertEqual(settings.blindMode, groups.contains(.behavior))
        XCTAssertEqual(settings.strictSpace, groups.contains(.input))
        XCTAssertEqual(settings.fontSize, 31)
        XCTAssertEqual(ThresholdSettingsStore(defaults: defaults).read(), .available(settings.snapshot))
      }
    }
  }

  func testChangingTestLanguageRecomputesEffectiveModifiersFromUnchangedRequestedSettings() throws {
    try withSettings { settings, _, current in
      var incoming = try definition(memory: 73, incoming: true).with(settingGroups: [.test])
      incoming.configuration.language = .arabic
      incoming.configuration.modifiers = [.lazyLatin]
      let resolved = commit(incoming, current: current, settings: settings)
      XCTAssertEqual(resolved.configuration.modifiers, [.lazyLatin])
      XCTAssertEqual(settings.testModifiers, [])
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWpmCustomValue, 37)
    }
  }

  func testChangingInputPolicyRecomputesTheUnselectedBehaviorModifiers() throws {
    try withSettings { settings, _, base in
      var current = base
      current.configuration.language = .arabic
      current.configuration.modifiers = [.lazyLatin]
      var incoming = try definition(memory: 73, incoming: true).with(settingGroups: [.input])
      incoming.settingsSnapshot?.prefersArabicLazyInput = false
      let resolved = commit(incoming, current: current, settings: settings)
      XCTAssertEqual(resolved.configuration.modifiers, [])
      XCTAssertEqual(settings.testModifiers, [])
      XCTAssertFalse(settings.prefersArabicLazyInput)
    }
  }

  func testStoredSourcePartialDefinitionCanReachTheExistingApplicationPath() throws {
    let incoming = try definition(memory: 73, incoming: true).with(settingGroups: [.behavior])
    let record = try TestPresetRecord(name: "Partial", definition: incoming)
    XCTAssertEqual(record.applicableDefinition, incoming)
    XCTAssertEqual(try LocalPresetCodec.decode(record.definitionData), incoming)
  }

  func testLegacyNonBehaviorPartialDoesNotDowngradeAnExistingSource() throws {
    try withSettings { settings, _, current in
      let incoming = SavedTestPreset(configuration: .words(17),
        settingsSnapshot: .init(fontSize: 41), settingGroups: [.appearance])
      let source = settings.thresholdConfiguration
      _ = commit(incoming, current: current, settings: settings)
      XCTAssertEqual(settings.fontSize, 41)
      XCTAssertEqual(settings.thresholdConfiguration, source)
      XCTAssertEqual(settings.activeResultTags, ["current"])
    }
  }

  func testUnselectedFieldInjectionOrScopeReplacementIsRejectedWithoutWrites() throws {
    try withSettings { settings, defaults, current in
      let incoming = try definition(memory: 73, incoming: true).with(settingGroups: [.input])
      let clean = PresetApplicationPolicy.applying(current: current, preset: incoming)
      var injected = clean
      injected.settingsSnapshot?.fontSize = 99
      var changedScope = clean
      changedScope.settingGroups = [.input, .appearance]
      var changedTags = clean
      changedTags.settingsSnapshot?.activeResultTags = ["injected"]
      let domain = defaults.dictionaryRepresentation() as NSDictionary
      let before = settings.snapshot
      let fontRevision = settings.practiceFontApplicationRevision
      for resolved in [injected, changedScope, changedTags] {
        XCTAssertFalse(PresetSettingsApplication.commit(original: incoming, resolved: resolved,
          configuration: resolved.configuration, to: settings, appliesGlobalSettings: true))
        XCTAssertEqual(settings.snapshot, before)
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, domain)
        XCTAssertEqual(settings.practiceFontApplicationRevision, fontRevision)
      }
    }
  }

  func testPartialAdmissionPreservesLocksUnknownStoresAndLegacyBehaviorProtection() throws {
    try withSettings { settings, defaults, current in
      let incoming = try definition(memory: 73, incoming: true).with(settingGroups: [.behavior])
      let resolved = PresetApplicationPolicy.applying(current: current, preset: incoming)
      let before = settings.snapshot
      let domain = defaults.dictionaryRepresentation() as NSDictionary
      let legacy = SavedTestPreset(configuration: .words(17), settingGroups: [.behavior])
      let legacyResolved = PresetApplicationPolicy.applying(current: current, preset: legacy)
      XCTAssertFalse(PresetSettingsApplication.commit(original: legacy, resolved: legacyResolved,
        configuration: legacyResolved.configuration, to: settings, appliesGlobalSettings: true))
      let owner = UUID()
      settings.setNoQuitConfigurationLock(true, for: owner)
      XCTAssertFalse(PresetSettingsApplication.commit(original: incoming, resolved: resolved,
        configuration: resolved.configuration, to: settings, appliesGlobalSettings: true))
      settings.setNoQuitConfigurationLock(false, for: owner)
      XCTAssertEqual(settings.snapshot, before)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, domain)
      for key in ["appSettings.v4", "activeTestSelection.v2"] {
        let saved = defaults.data(forKey: key)
        defaults.set(Data("{\"version\":99}".utf8), forKey: key)
        let protected = defaults.dictionaryRepresentation() as NSDictionary
        XCTAssertFalse(PresetSettingsApplication.commit(original: incoming, resolved: resolved,
          configuration: resolved.configuration, to: settings, appliesGlobalSettings: true))
        XCTAssertEqual(settings.snapshot, before)
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, protected)
        if let saved { defaults.set(saved, forKey: key) }
        else { defaults.removeObject(forKey: key) }
      }
    }
  }

  func testBehaviorTagsClearWhenAbsentAndCommittedStateSurvivesANewReaderAndSession() throws {
    try withSettings { settings, defaults, current in
      var incoming = try definition(memory: 73, incoming: true).with(settingGroups: [.behavior])
      incoming.activeResultTags = nil
      incoming.settingsSnapshot = nil
      let resolved = commit(incoming, current: current, settings: settings)
      XCTAssertEqual(settings.activeResultTags, [])
      let reader = AppSettings(defaults: defaults,
        feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
      XCTAssertEqual(reader.snapshot, settings.snapshot)
      XCTAssertEqual(reader.thresholdConfiguration?.minimumWpmCustomValue, 73)
      XCTAssertEqual(reader.thresholdConfiguration?.minimumWordBurstMode, .flex)
      XCTAssertEqual(reader.inputRules, resolved.configuration.rules)
      var session = TestSessionFactory.make(configuration: resolved.configuration)
      session.insertBatch(session.prompt, at: Date(timeIntervalSince1970: 100))
      XCTAssertEqual(session.outcome, .completed)
    }
  }

  func testEmptyAndChallengeSourceRecordsRemainUnavailable() throws {
    let incoming = try definition(memory: 73, incoming: true)
    let empty = try TestPresetRecord(name: "Empty", definition: incoming.with(settingGroups: []))
    XCTAssertNil(empty.applicableDefinition)
    var challenge = incoming.with(settingGroups: [.test])
    challenge.configuration.challengeID = "ten-words-of-pain"
    XCTAssertNil(try TestPresetRecord(name: "Challenge", definition: challenge).applicableDefinition)
  }

  func testAllNonemptyGroupCombinationsCommitExactlyTheirSelectedState() throws {
    let allGroups = PresetSettingGroup.allCases
    try withSettings { _, defaults, current in
      let baseline = try XCTUnwrap(current.settingsSnapshot)
      for mask in 1..<(1 << allGroups.count) {
        let groups = Set(allGroups.enumerated().compactMap { index, group in
          mask & (1 << index) == 0 ? nil : group
        })
        // Each case gets a fresh settings owner and persisted baseline without
        // creating/deleting hundreds of unrelated CFPreferences domains.
        XCTAssertTrue(ThresholdSettingsStore(defaults: defaults).save(baseline))
        let settings = AppSettings(defaults: defaults,
          feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}),
          localBackgroundStore: .inMemory())
        let incoming = try definition(memory: 73, incoming: true).with(settingGroups: groups)
        let expected = expectedSnapshot(settings.snapshot, incoming: incoming, groups: groups)
        let fontRevision = settings.practiceFontApplicationRevision
        let resolved = commit(incoming, current: current, settings: settings)
        XCTAssertEqual(settings.snapshot, expected, "mask: \(mask)")
        XCTAssertEqual(ThresholdSettingsStore(defaults: defaults).read(), .available(expected), "mask: \(mask)")
        XCTAssertEqual(settings.inputRules, resolved.configuration.rules, "mask: \(mask)")
        if !groups.contains(.appearance) {
          XCTAssertEqual(settings.practiceFontApplicationRevision, fontRevision, "mask: \(mask)")
        }
      }
    }
  }

  func testInfiniteSelectionRetainsRequestedFiniteFunboxWithoutReinsertingItIntoTheTest() throws {
    try withSettings { settings, defaults, base in
      settings.testModifiers = [.focusCurrentWord]
      var current = base
      current.configuration = current.configuration.with(modifiers: [.focusCurrentWord])
      current.settingsSnapshot = settings.snapshot
      var incoming = try definition(memory: 73, incoming: true).with(settingGroups: [.test])
      incoming.configuration.duration = 0
      let resolved = PresetApplicationPolicy.applying(current: current, preset: incoming)
      XCTAssertTrue(resolved.configuration.isInfinite)
      XCTAssertEqual(resolved.configuration.modifiers, [])
      XCTAssertTrue(PresetSettingsApplication.commit(original: incoming, resolved: resolved,
        configuration: resolved.configuration, to: settings, appliesGlobalSettings: true))
      XCTAssertEqual(settings.testModifiers, [.focusCurrentWord])
      XCTAssertEqual(ThresholdSettingsStore(defaults: defaults).read(), .available(settings.snapshot))
      let full = resolved.with(settingGroups: nil)
      XCTAssertTrue(PresetSettingsApplication.commit(original: full, resolved: full,
        configuration: full.configuration, to: settings, appliesGlobalSettings: true))
    }
  }
}
