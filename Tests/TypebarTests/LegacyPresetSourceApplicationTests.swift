import XCTest
@testable import Typebar

@MainActor
final class LegacyPresetSourceApplicationTests: XCTestCase {
  private func withSettings(_ body: (AppSettings, UserDefaults) throws -> Void) throws {
    let suite = "typebar.legacy-preset-source.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var raw = PracticeThresholdConfiguration()
    try raw.apply(.minimumWpm(mode: .off, customValue: 37))
    try raw.apply(.minimumAccuracy(mode: .off, customValue: 93))
    try raw.apply(.minimumWordBurst(mode: .off, customValue: 84))
    var snapshot = PracticeThresholdSource(configuration: raw).applying(to: AppSettingsSnapshot(fontSize: 31))
    snapshot.activeResultTags = ["current"]
    defaults.set(try JSONEncoder().encode(AppSettingsSnapshot(fontSize: 22)), forKey: "appSettings.v1")
    XCTAssertTrue(ThresholdSettingsStore(defaults: defaults).save(snapshot))
    try body(AppSettings(defaults: defaults,
      feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory()), defaults)
  }

  private func legacy() -> SavedTestPreset {
    var snapshot = AppSettingsSnapshot(difficulty: .expert, strictSpace: true, blindMode: true, fontSize: 42)
    snapshot.englishVariant = .british
    snapshot.activeResultTags = ["snapshot"]
    return .init(configuration: .words(3, difficulty: .expert,
      rules: InputRules(strictSpace: true, blindMode: true), englishVariant: .british),
      activeResultTags: ["alias"], settingsSnapshot: snapshot)
  }

  private func apply(_ preset: SavedTestPreset, to settings: AppSettings) throws -> SavedTestPreset {
    let preparation = try XCTUnwrap(PresetSourcePreparation.preparing(preset, to: settings,
      appliesGlobalSettings: true))
    let current = SavedTestPreset(configuration: .words(17, rules: settings.inputRules),
      activeResultTags: settings.activeResultTags, settingsSnapshot: settings.snapshot)
    let resolved = PresetApplicationPolicy.applying(current: current, preset: preparation.preset)
    XCTAssertTrue(PresetSettingsApplication.commit(original: preparation.preset, resolved: resolved,
      configuration: resolved.configuration, to: settings, appliesGlobalSettings: true,
      expectedSourceState: preparation.baseline))
    return resolved
  }

  func testStoredLegacyFullPresetAppliesWithoutChangingItsBytesOrRememberedOffValues() throws {
    try withSettings { settings, defaults in
      let record = try TestPresetRecord(name: "Old full", definition: legacy())
      let originalBytes = record.definitionData
      let oldSettingsBytes = defaults.data(forKey: "appSettings.v1")
      let remembered = settings.thresholdConfiguration
      let resolved = try apply(try XCTUnwrap(record.applicableDefinition), to: settings)
      XCTAssertEqual(settings.thresholdConfiguration, remembered)
      XCTAssertNotNil(resolved.configuration.rules.thresholdSource)
      XCTAssertEqual(settings.fontSize, 42)
      XCTAssertTrue(settings.strictSpace)
      XCTAssertTrue(settings.blindMode)
      XCTAssertEqual(settings.activeResultTags, ["alias"])
      XCTAssertEqual(record.definitionData, originalBytes)
      XCTAssertNil(record.definition?.configuration.rules.thresholdSource)
      XCTAssertEqual(defaults.data(forKey: "appSettings.v1"), oldSettingsBytes)
      XCTAssertEqual(ThresholdSettingsStore(defaults: defaults).read(), .available(settings.snapshot))
    }
  }

  func testLegacyBehaviorPresetDoesNotTouchInputAppearanceOrTestSelection() throws {
    try withSettings { settings, _ in
      let before = settings.thresholdConfiguration
      let revision = settings.practiceFontApplicationRevision
      let resolved = try apply(legacy().with(settingGroups: [.behavior]), to: settings)
      XCTAssertEqual(settings.thresholdConfiguration, before)
      XCTAssertEqual(settings.fontSize, 31)
      XCTAssertFalse(settings.strictSpace)
      XCTAssertTrue(settings.blindMode)
      XCTAssertEqual(settings.difficulty, .expert)
      XCTAssertEqual(settings.activeResultTags, ["alias"])
      XCTAssertEqual(resolved.configuration.wordLimit, 17)
      XCTAssertEqual(settings.practiceFontApplicationRevision, revision)
    }
  }

  func testLegacyRulesOnlyPositiveValuesGetSourceModesWithoutReapplyingAppearance() throws {
    try withSettings { settings, _ in
      let preset = SavedTestPreset(configuration: .words(3, rules: InputRules(
        minimumAccuracy: 98.5, minimumWpm: 48.25, minimumWordBurstWpm: 88.25, minimumWordBurstMode: .flex)))
      let revision = settings.practiceFontApplicationRevision
      _ = try apply(preset, to: settings)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWpmMode, .custom)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWpmCustomValue, 48.25)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumAccuracyCustomValue, 98.5)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWordBurstMode, .flex)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWordBurstCustomValue, 88.25)
      XCTAssertEqual(settings.fontSize, 31)
      XCTAssertEqual(settings.activeResultTags, ["current"])
      XCTAssertEqual(settings.practiceFontApplicationRevision, revision)
    }
  }

  func testColdReaderAndActualSessionUseTheBridgedPresetSource() throws {
    try withSettings { settings, defaults in
      let resolved = try apply(legacy(), to: settings)
      let reader = AppSettings(defaults: defaults,
        feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
      XCTAssertEqual(reader.snapshot, settings.snapshot)
      XCTAssertNotNil(reader.inputRules.thresholdSource)
      XCTAssertEqual(reader.inputRules, resolved.configuration.rules)
      var configuration = resolved.configuration
      configuration.rules = reader.inputRules
      var session = TestSessionFactory.make(configuration: configuration)
      session.insertBatch(session.prompt, at: Date(timeIntervalSince1970: 100))
      XCTAssertEqual(session.outcome, .completed)
    }
  }

  func testLegacyOffMeansDisabledEvenWhenTheCurrentModesAreEnabledZero() throws {
    try withSettings { settings, _ in
      XCTAssertTrue(settings.updateThresholdConfiguration(.minimumWpm(mode: .custom, customValue: 0)))
      XCTAssertTrue(settings.updateThresholdConfiguration(.minimumAccuracy(mode: .custom, customValue: 0)))
      XCTAssertTrue(settings.updateThresholdConfiguration(.minimumWordBurst(mode: .fixed, customValue: 0)))
      _ = try apply(legacy(), to: settings)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWpmMode, .off)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumAccuracyMode, .off)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWordBurstMode, .off)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWpmCustomValue, 0)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWordBurstCustomValue, 0)
    }
  }

  func testVeryOldFullTagsStayCompatibleButBehaviorWithoutTagsClearsThem() throws {
    for groups: Set<PresetSettingGroup>? in [nil, [.behavior]] {
      try withSettings { settings, _ in
        var preset = legacy().with(settingGroups: groups)
        preset.settingsSnapshot = nil
        preset.activeResultTags = nil
        _ = try apply(preset, to: settings)
        XCTAssertEqual(settings.activeResultTags, groups == nil ? ["current"] : [])
      }
    }
  }

  func testAllNonemptyLegacyGroupCombinationsKeepUnselectedSourceAndFields() throws {
    let groups = PresetSettingGroup.allCases
    try withSettings { _, defaults in
      let baseline = try XCTUnwrap(ThresholdSettingsStore(defaults: defaults).read().snapshotForLegacyPresetTest)
      for mask in 1..<(1 << groups.count) {
        XCTAssertTrue(ThresholdSettingsStore(defaults: defaults).save(baseline))
        let settings = AppSettings(defaults: defaults,
          feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
        let selected = Set(groups.enumerated().compactMap { index, group in mask & (1 << index) == 0 ? nil : group })
        let preset = legacy().with(settingGroups: selected)
        let revision = settings.practiceFontApplicationRevision
        let resolved = try apply(preset, to: settings)
        var expected = baseline
        if selected.contains(.behavior) {
          expected.difficulty = .expert
          expected.blindMode = true
          expected.englishVariant = .british
          expected.activeResultTags = ["alias"]
        }
        if selected.contains(.input) { expected.strictSpace = true }
        if selected.contains(.appearance) { expected.fontSize = 42 }
        XCTAssertEqual(settings.snapshot, expected, "mask: \(mask)")
        XCTAssertEqual(resolved.configuration.wordLimit, selected.contains(.test) ? 3 : 17)
        XCTAssertEqual(ThresholdSettingsStore(defaults: defaults).read(), .available(expected))
        if !selected.contains(.appearance) { XCTAssertEqual(settings.practiceFontApplicationRevision, revision) }
      }
    }
  }

  func testRawChallengesConflictsAndMalformedCarriersAreNotHiddenByPreparation() throws {
    try withSettings { settings, defaults in
      var conflict = legacy()
      conflict.settingsSnapshot?.minimumWpm = 99
      var challenge = legacy().with(settingGroups: [.appearance])
      challenge.configuration.challengeID = "ten-words-of-pain"
      var sourceWithoutOwner = legacy()
      sourceWithoutOwner.settingsSnapshot?.thresholdSource = settings.snapshot.thresholdSource
      let before = defaults.dictionaryRepresentation() as NSDictionary
      for invalid in [conflict, challenge, sourceWithoutOwner, legacy().with(settingGroups: [])] {
        XCTAssertNil(PresetSourcePreparation.preparing(invalid, to: settings, appliesGlobalSettings: true))
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
      }
    }
  }

  func testPreparationDoesNotWriteOrAdoptAProfileAndLegacyTargetsStayUnchanged() throws {
    let suite = "typebar.legacy-preset-no-adoption.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults,
      feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
    let original = legacy()
    let before = defaults.dictionaryRepresentation() as NSDictionary
    let prepared = try XCTUnwrap(PresetSourcePreparation.preparing(original, to: settings, appliesGlobalSettings: true))
    XCTAssertEqual(prepared.preset, original)
    XCTAssertNil(prepared.baseline)
    let source = PracticeThresholdSource(configuration: .init())
    var sourced = original
    sourced.configuration.rules = source.applying(to: sourced.configuration.rules)
    sourced.settingsSnapshot = source.applying(to: try XCTUnwrap(sourced.settingsSnapshot))
    XCTAssertNil(PresetSourcePreparation.preparing(sourced, to: settings, appliesGlobalSettings: true))
    XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
  }

  func testUnavailableSourceStateCannotPrepareAReplacement() throws {
    for key in ["lock", "missing", "appSettings.v4", "activeTestSelection.v2"] {
      try withSettings { settings, defaults in
        let owner = UUID()
        if key == "lock" { settings.setNoQuitConfigurationLock(true, for: owner) }
        else if key == "missing" { defaults.removeObject(forKey: "appSettings.v4") }
        else { defaults.set(Data("{\"version\":99}".utf8), forKey: key) }
        defer { settings.setNoQuitConfigurationLock(false, for: owner) }
        let before = defaults.dictionaryRepresentation() as NSDictionary
        XCTAssertNil(PresetSourcePreparation.preparing(legacy(), to: settings, appliesGlobalSettings: true))
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
      }
    }
  }

  func testPreparedLegacyMemoryCannotOverwriteALaterSourceUpdate() throws {
    try withSettings { settings, defaults in
      let prepared = try XCTUnwrap(PresetSourcePreparation.preparing(legacy(), to: settings, appliesGlobalSettings: true))
      let resolved = prepared.preset
      XCTAssertTrue(settings.updateThresholdConfiguration(.minimumWpm(mode: .off, customValue: 55)))
      let afterUpdate = settings.snapshot
      let bytes = defaults.data(forKey: "appSettings.v4")
      XCTAssertFalse(PresetSettingsApplication.commit(original: prepared.preset, resolved: resolved,
        configuration: resolved.configuration, to: settings, appliesGlobalSettings: true,
        expectedSourceState: prepared.baseline))
      XCTAssertEqual(settings.snapshot, afterUpdate)
      XCTAssertEqual(defaults.data(forKey: "appSettings.v4"), bytes)
    }
  }

  func testMainPreparesTheApplicationValueBeforeResolvingAndPassesTheBaseline() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    let start = try XCTUnwrap(source.range(of: "@discardableResult private func apply(\n    _ preset:"))
    let end = try XCTUnwrap(source.range(of: "  private func restoreActiveTestSelection", range: start.upperBound..<source.endIndex))
    let body = source[start.lowerBound..<end.lowerBound]
    let preparation = try XCTUnwrap(body.range(of: "PresetSourcePreparation.preparing"))
    let resolution = try XCTUnwrap(body.range(of: "PresetApplicationPolicy.applying"))
    XCTAssertLessThan(preparation.lowerBound, resolution.lowerBound)
    XCTAssertTrue(body.contains("preset: preparedPreset"))
    XCTAssertTrue(body.contains("original: preparedPreset"))
    XCTAssertTrue(body.contains("expectedSourceState: preparation.baseline"))
  }

  func testIndependentStoreUpdateRejectsBothStalePreparationAndStaleCommit() throws {
    try withSettings { settings, defaults in
      let prepared = try XCTUnwrap(PresetSourcePreparation.preparing(legacy(), to: settings, appliesGlobalSettings: true))
      let before = settings.snapshot
      var raw = try XCTUnwrap(settings.thresholdConfiguration)
      try raw.apply(.minimumWpm(mode: .off, customValue: 55))
      let replacement = PracticeThresholdSource(configuration: raw).applying(to: before)
      XCTAssertTrue(ThresholdSettingsStore(defaults: defaults).save(replacement))
      XCTAssertNil(PresetSourcePreparation.preparing(legacy(), to: settings, appliesGlobalSettings: true))
      XCTAssertFalse(PresetSettingsApplication.commit(original: prepared.preset, resolved: prepared.preset,
        configuration: prepared.preset.configuration, to: settings, appliesGlobalSettings: true,
        expectedSourceState: prepared.baseline))
      XCTAssertEqual(settings.snapshot, before)
      XCTAssertEqual(ThresholdSettingsStore(defaults: defaults).read(), .available(replacement))
    }
  }

  func testSelectionOnlyRestorationDoesNotBridgeOrApplyLegacyGlobalMetadata() throws {
    try withSettings { settings, defaults in
      let original = legacy()
      let before = defaults.dictionaryRepresentation() as NSDictionary
      let prepared = try XCTUnwrap(PresetSourcePreparation.preparing(original, to: settings,
        appliesGlobalSettings: false))
      XCTAssertEqual(prepared.preset, original)
      XCTAssertNil(prepared.baseline)
      XCTAssertTrue(PresetSettingsApplication.commit(original: prepared.preset, resolved: prepared.preset,
        configuration: original.configuration, to: settings, appliesGlobalSettings: false))
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
      XCTAssertEqual(settings.fontSize, 31)
      XCTAssertEqual(settings.activeResultTags, ["current"])
    }
  }
}

private extension ThresholdSettingsRead {
  var snapshotForLegacyPresetTest: AppSettingsSnapshot? {
    if case .available(let snapshot) = self { return snapshot }
    return nil
  }
}
