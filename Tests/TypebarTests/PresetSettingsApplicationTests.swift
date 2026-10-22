import XCTest

@testable import Typebar

@MainActor
final class PresetSettingsApplicationTests: XCTestCase {
  private var threeWordMemory: TypebarTestParameterMemory {
    .init(
      duration: 30, wordLimit: 3, customTextDuration: 30,
      customTextWordLimit: 25, customTextSectionLimit: 1)
  }
  private func withSettings(source: Bool, _ body: (AppSettings, UserDefaults) throws -> Void) throws
  {
    let suite = "typebar.preset-admission.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    if source {
      var raw = PracticeThresholdConfiguration()
      try raw.apply(.minimumWpm(mode: .off, customValue: 37))
      try raw.apply(.minimumWordBurst(mode: .flex, customValue: 0))
      XCTAssertTrue(
        ThresholdSettingsStore(defaults: defaults).save(
          PracticeThresholdSource(configuration: raw).applying(
            to: AppSettingsSnapshot(fontSize: 31))))
    }
    try body(AppSettings(defaults: defaults, localBackgroundStore: .inMemory()), defaults)
  }

  func testExistingSourceCanRestoreAnOrdinarySelectionWithoutWritingGlobalSettings() throws {
    try withSettings(source: true) { settings, defaults in
      let preset = SavedTestPreset(configuration: .words(3))
      let before = settings.snapshot
      let bytes = defaults.data(forKey: "appSettings.v4")
      XCTAssertTrue(
        PresetSettingsApplication.commit(
          original: preset, resolved: preset,
          configuration: preset.configuration, to: settings, appliesGlobalSettings: false))
      XCTAssertEqual(settings.snapshot, before)
      XCTAssertEqual(defaults.data(forKey: "appSettings.v4"), bytes)
    }
  }

  func testStoredSourceSelectionUsesTheLoadedGlobalRulesInTheActualSession() throws {
    try withSettings(source: true) { settings, defaults in
      let preset = SavedTestPreset(configuration: .words(3, rules: settings.inputRules))
      XCTAssertTrue(
        settings.saveActiveTestSelection(
          .init(preset: preset, testParameterMemory: threeWordMemory)))
      XCTAssertTrue(settings.updateThresholdConfiguration(.minimumWpm(mode: .off, customValue: 53)))
      let reader = AppSettings(defaults: defaults, localBackgroundStore: .inMemory())
      let restored = try XCTUnwrap(reader.activeTestSelection)
      XCTAssertNotEqual(
        restored.preset.configuration.rules.thresholdSource, reader.inputRules.thresholdSource)
      XCTAssertTrue(
        PresetSettingsApplication.commit(
          original: restored.preset, resolved: restored.preset,
          configuration: restored.preset.configuration, to: reader, appliesGlobalSettings: false))
      var effective = restored.preset.configuration
      effective.wordLimit = restored.testParameterMemory.wordLimit
      effective.rules = reader.inputRules
      var session = TestSessionFactory.make(configuration: effective)
      XCTAssertEqual(session.configuration.rules.thresholdSource, reader.inputRules.thresholdSource)
      session.insertBatch(session.prompt, at: Date(timeIntervalSince1970: 100))
      XCTAssertEqual(session.outcome, .completed)
    }
  }

  func testLegacySelectionInAnExistingSourceProfileCanSaveV2WithoutChangingV1OrGlobalSettings()
    throws
  {
    try withSettings(source: true) { settings, defaults in
      let old = ActiveTestSelectionDocument(
        preset: .init(configuration: .words(3)),
        testParameterMemory: threeWordMemory)
      XCTAssertTrue(settings.saveActiveTestSelection(old))
      let oldBytes = defaults.data(forKey: "activeTestSelection.v1")
      let globalBytes = defaults.data(forKey: "appSettings.v4")
      let reader = AppSettings(defaults: defaults, localBackgroundStore: .inMemory())
      let restored = try XCTUnwrap(reader.activeTestSelection)
      XCTAssertEqual(restored.version, 1)
      XCTAssertTrue(
        PresetSettingsApplication.commit(
          original: restored.preset, resolved: restored.preset,
          configuration: restored.preset.configuration, to: reader, appliesGlobalSettings: false))
      var effective = restored.preset.configuration
      effective.wordLimit = restored.testParameterMemory.wordLimit
      effective.rules = reader.inputRules
      let next = ActiveTestSelectionDocument(
        preset: .init(configuration: effective),
        testParameterMemory: restored.testParameterMemory)
      XCTAssertTrue(reader.saveActiveTestSelection(next))
      XCTAssertEqual(ActiveTestSelectionStore(defaults: defaults).load()?.version, 2)
      XCTAssertEqual(defaults.data(forKey: "activeTestSelection.v1"), oldBytes)
      XCTAssertEqual(defaults.data(forKey: "appSettings.v4"), globalBytes)
    }
  }

  func testSelectionRefusalHappensBeforeJSONPreferenceOrLayoutWrites() throws {
    try withSettings(source: false) { settings, defaults in
      let json = try SettingsJSONCommandCodec.export(
        settings: .init(fontSize: 42),
        configuration: .words(3), layoutFluidLayouts: [], testParameterMemory: .defaults)
      let before = settings.snapshot
      let domain = defaults.dictionaryRepresentation() as NSDictionary
      var calls = 0
      XCTAssertThrowsError(
        try SettingsJSONCommandImport.apply(
          json, to: settings,
          selectionAdmission: { _ in
            calls += 1
            return false
          })
      ) { XCTAssertEqual($0 as? SettingsJSONCommandError, .selectionUnavailable) }
      XCTAssertEqual(calls, 1)
      XCTAssertEqual(settings.snapshot, before)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, domain)
    }
  }

  func testSelectionOnlyRestorationNeverAppliesPrivateGlobalMetadataOrTags() throws {
    try withSettings(source: true) { settings, defaults in
      let source = try XCTUnwrap(settings.snapshot.thresholdSource)
      var metadata = source.applying(to: AppSettingsSnapshot(fontSize: 99))
      metadata.activeResultTags = ["incoming"]
      let preset = SavedTestPreset(
        configuration: .words(3, rules: settings.inputRules),
        activeResultTags: ["incoming"], settingsSnapshot: metadata)
      let before = settings.snapshot
      let domain = defaults.dictionaryRepresentation() as NSDictionary
      XCTAssertTrue(
        PresetSettingsApplication.commit(
          original: preset, resolved: preset,
          configuration: preset.configuration, to: settings, appliesGlobalSettings: false))
      XCTAssertEqual(settings.snapshot, before)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, domain)
    }
  }

  func testUnreadableProfileOrSelectionRefusesWithoutReplacingItsBytes() throws {
    for key in ["appSettings.v4", "activeTestSelection.v2"] {
      try withSettings(source: true) { settings, defaults in
        let future = Data("{\"version\":99}".utf8)
        defaults.set(future, forKey: key)
        let before = settings.snapshot
        let preset = SavedTestPreset(configuration: .words(3))
        XCTAssertFalse(
          PresetSettingsApplication.commit(
            original: preset, resolved: preset,
            configuration: preset.configuration, to: settings, appliesGlobalSettings: false))
        XCTAssertEqual(settings.snapshot, before)
        XCTAssertEqual(defaults.data(forKey: key), future)
      }
    }
  }

  func testSourceChallengesPartialPresetsAndLegacyGlobalApplicationRemainGuarded() throws {
    try withSettings(source: true) { settings, defaults in
      let preset = SavedTestPreset(configuration: .words(3, rules: settings.inputRules))
      let domain = defaults.dictionaryRepresentation() as NSDictionary
      let legacy = SavedTestPreset(configuration: .words(3))
      XCTAssertFalse(
        PresetSettingsApplication.commit(
          original: legacy, resolved: legacy,
          configuration: legacy.configuration, to: settings, appliesGlobalSettings: true))
      let partial = preset.with(settingGroups: [.input])
      XCTAssertFalse(
        PresetSettingsApplication.commit(
          original: partial, resolved: partial,
          configuration: partial.configuration, to: settings, appliesGlobalSettings: false))
      let challenge = SavedTestPreset(
        configuration: preset.configuration.with(challengeID: "ten-words-of-pain"))
      XCTAssertFalse(
        PresetSettingsApplication.commit(
          original: challenge, resolved: challenge,
          configuration: challenge.configuration, to: settings, appliesGlobalSettings: false))
      XCTAssertFalse(
        PresetSettingsApplication.commit(
          original: challenge, resolved: challenge,
          configuration: challenge.configuration.with(challengeID: nil), to: settings,
          appliesGlobalSettings: false))
      var conflicting = preset
      conflicting.configuration.rules.minimumWpm = 99
      XCTAssertFalse(
        PresetSettingsApplication.commit(
          original: conflicting, resolved: preset,
          configuration: preset.configuration, to: settings, appliesGlobalSettings: false))
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, domain)
      let owner = UUID()
      settings.setNoQuitConfigurationLock(true, for: owner)
      defer { settings.setNoQuitConfigurationLock(false, for: owner) }
      XCTAssertFalse(
        PresetSettingsApplication.commit(
          original: preset, resolved: preset,
          configuration: preset.configuration, to: settings, appliesGlobalSettings: false))
    }
  }

  func testLegacyGlobalApplicationCommitsSettingsAndOwnedTagsButSelectionOnlyDoesNot() throws {
    try withSettings(source: false) { settings, _ in
      let preset = SavedTestPreset(
        configuration: .words(3), activeResultTags: ["new"],
        settingsSnapshot: .init(fontSize: 42))
      let before = settings.snapshot
      XCTAssertTrue(
        PresetSettingsApplication.commit(
          original: preset, resolved: preset,
          configuration: preset.configuration, to: settings, appliesGlobalSettings: false))
      XCTAssertEqual(settings.snapshot, before)
      XCTAssertTrue(
        PresetSettingsApplication.commit(
          original: preset, resolved: preset,
          configuration: preset.configuration, to: settings, appliesGlobalSettings: true))
      XCTAssertEqual(settings.fontSize, 42)
      XCTAssertEqual(settings.activeResultTags, ["new"])
    }
  }

  func testJSONRechecksLockAndSourceStateAfterAdmission() throws {
    try withSettings(source: false) { settings, defaults in
      let json = try SettingsJSONCommandCodec.export(
        settings: .init(fontSize: 42), configuration: .words(3),
        layoutFluidLayouts: [], testParameterMemory: .defaults)
      let before = settings.snapshot
      let owner = UUID()
      XCTAssertThrowsError(
        try SettingsJSONCommandImport.apply(
          json, to: settings,
          selectionAdmission: { _ in
            settings.setNoQuitConfigurationLock(true, for: owner)
            return true
          })
      ) { XCTAssertEqual($0 as? SettingsJSONCommandError, .configurationLocked) }
      settings.setNoQuitConfigurationLock(false, for: owner)
      let future = Data("{\"version\":99}".utf8)
      XCTAssertThrowsError(
        try SettingsJSONCommandImport.apply(
          json, to: settings,
          selectionAdmission: { _ in
            defaults.set(future, forKey: "appSettings.v4")
            return true
          })
      ) { XCTAssertEqual($0 as? SettingsJSONCommandError, .thresholdSourceNotReady) }
      XCTAssertEqual(settings.snapshot, before)
      XCTAssertEqual(defaults.data(forKey: "appSettings.v4"), future)
      XCTAssertNil(defaults.object(forKey: "layoutFluidLayouts.v1"))
    }
  }

  func testResourceAdmissionCoversUnavailableWingdingsAndUnverifiedScriptsWithoutLoadingThem()
    throws
  {
    let ordinary = TestConfiguration.words(3)
    XCTAssertNil(
      PresetResourceAdmission.refusal(
        for: ordinary,
        wingdingsAvailable: {
          XCTFail("ordinary selection must not probe Wingdings")
          return false
        },
        scriptIsVerified: { _ in
          XCTFail("ordinary selection must not probe scripts")
          return false
        }))
    let wingdings = ordinary.with(challengeID: "ten-words-of-pain")
    XCTAssertEqual(
      PresetResourceAdmission.refusal(
        for: wingdings, wingdingsAvailable: { false },
        scriptIsVerified: { _ in true }), .missingWingdings)
    let script = try XCTUnwrap(
      TypebarChallengeLibrary.all.first { $0.requirements.referenceScriptSpecification != nil })
    let configuration = script.preset.configuration.with(challengeID: script.id)
    XCTAssertEqual(
      PresetResourceAdmission.refusal(
        for: configuration, wingdingsAvailable: { true },
        scriptIsVerified: { _ in false }), .missingVerifiedScript)
    XCTAssertNil(
      PresetResourceAdmission.refusal(
        for: configuration, wingdingsAvailable: { true },
        scriptIsVerified: { $0 == script.requirements.referenceScriptSpecification }))
    XCTAssertTrue(
      SettingsJSONCommandError.selectionApplicationFailed.localizedDescription.contains("已导入"))
  }

  func testProductionOrderingCommitsBeforeSelectionAndChecksJSONResourcesBeforeImport() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let app = try String(
      contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    let start = try XCTUnwrap(
      app.range(of: "@discardableResult private func apply(\n    _ preset:"))
    let end = try XCTUnwrap(
      app.range(
        of: "  private func restoreActiveTestSelection", range: start.upperBound..<app.endIndex))
    let body = app[start.lowerBound..<end.lowerBound]
    let commit = try XCTUnwrap(body.range(of: "PresetSettingsApplication.commit"))
    XCTAssertLessThan(
      try XCTUnwrap(body.range(of: "acceptsPresetResources(appliedPreset.configuration)"))
        .lowerBound, commit.lowerBound)
    XCTAssertLessThan(
      commit.lowerBound, try XCTUnwrap(body.range(of: "if let restoringSelection")).lowerBound)
    XCTAssertLessThan(
      commit.lowerBound, try XCTUnwrap(body.range(of: "wordPractice = nil")).lowerBound)
    XCTAssertFalse(body.contains("settings.apply("))
    XCTAssertFalse(body.contains("settings.activeResultTags ="))
    XCTAssertTrue(app.contains("selectionAdmission: { acceptsPresetResources($0) }"))
    XCTAssertTrue(app.contains("throw SettingsJSONCommandError.selectionApplicationFailed"))
  }
}
