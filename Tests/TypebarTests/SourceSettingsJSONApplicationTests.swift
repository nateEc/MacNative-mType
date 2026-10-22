import XCTest
@testable import Typebar

@MainActor
final class SourceSettingsJSONApplicationTests: XCTestCase {
  private func withSettings(_ body: (AppSettings, UserDefaults) throws -> Void) throws {
    let suite = "typebar.source-json-application.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var raw = PracticeThresholdConfiguration()
    try raw.apply(.minimumWpm(mode: .off, customValue: 37))
    try raw.apply(.minimumAccuracy(mode: .off, customValue: 93))
    try raw.apply(.minimumWordBurst(mode: .off, customValue: 84))
    defaults.set(try JSONEncoder().encode(AppSettingsSnapshot(fontSize: 22)), forKey: "appSettings.v1")
    XCTAssertTrue(ThresholdSettingsStore(defaults: defaults).save(
      PracticeThresholdSource(configuration: raw).applying(to: .init(fontSize: 31))))
    try body(AppSettings(defaults: defaults,
      feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory()), defaults)
  }

  private func json(source: Bool = true, arabic: Bool = false) throws -> String {
    var snapshot = AppSettingsSnapshot(strictSpace: true, fontSize: 42)
    snapshot.activeResultTags = ["imported"]
    var configuration = TestConfiguration.words(3, rules: InputRules(strictSpace: true),
      language: arabic ? .arabic : .english)
    if arabic { configuration.modifiers = [.lazyLatin] }
    if source {
      var raw = PracticeThresholdConfiguration()
      try raw.apply(.minimumWpm(mode: .custom, customValue: 0))
      try raw.apply(.minimumAccuracy(mode: .off, customValue: 91))
      try raw.apply(.minimumWordBurst(mode: .flex, customValue: 0))
      let owner = PracticeThresholdSource(configuration: raw)
      snapshot = owner.applying(to: snapshot)
      configuration.rules = owner.applying(to: configuration.rules)
    }
    return try SettingsJSONCommandCodec.export(settings: snapshot, configuration: configuration,
      layoutFluidLayouts: [.ansiDvorak, .ansiQwerty],
      testParameterMemory: .init(duration: 30, wordLimit: 3, customTextDuration: 30,
        customTextWordLimit: 25, customTextSectionLimit: 1))
  }

  func testSourceDocumentAppliesSnapshotAndLayoutsThenRestoresSelectionWithoutReapplyingSettings() throws {
    try withSettings { settings, defaults in
      let incoming = try json()
      let expected = try SettingsJSONCommandCodec.decode(incoming)
      let legacyBytes = defaults.data(forKey: "appSettings.v1")
      let document = try SettingsJSONCommandImport.apply(incoming, to: settings)
      XCTAssertEqual(document, expected)
      XCTAssertEqual(settings.snapshot, expected.settings)
      XCTAssertEqual(settings.layoutFluidLayouts, expected.layoutFluidLayouts)
      XCTAssertEqual(ThresholdSettingsStore(defaults: defaults).read(), .available(expected.settings))
      XCTAssertEqual(defaults.data(forKey: "appSettings.v1"), legacyBytes)
      let preset = SavedTestPreset(configuration: document.configuration)
      let revision = settings.practiceFontApplicationRevision
      XCTAssertTrue(PresetSettingsApplication.commit(original: preset, resolved: preset,
        configuration: preset.configuration, to: settings, appliesGlobalSettings: false))
      XCTAssertEqual(settings.practiceFontApplicationRevision, revision)
      XCTAssertTrue(settings.saveActiveTestSelection(.init(preset: preset,
        testParameterMemory: document.testParameterMemory)))
      let reader = AppSettings(defaults: defaults,
        feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
      XCTAssertEqual(reader.snapshot, expected.settings)
      XCTAssertEqual(reader.layoutFluidLayouts, expected.layoutFluidLayouts)
      let restored = try XCTUnwrap(reader.activeTestSelection)
      var configuration = restored.preset.configuration
      configuration.rules = reader.inputRules
      var session = TestSessionFactory.make(configuration: configuration)
      session.insertBatch(session.prompt, at: Date(timeIntervalSince1970: 100))
      XCTAssertEqual(session.outcome, .completed)
    }
  }

  func testLegacyJSONBridgesOffValuesWithoutLosingCurrentMemories() throws {
    try withSettings { settings, _ in
      var root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json(source: false).utf8)) as? [String: Any])
      root["version"] = 5
      let legacy = String(decoding: try JSONSerialization.data(withJSONObject: root), as: UTF8.self)
      let before = settings.thresholdConfiguration
      let document = try SettingsJSONCommandImport.apply(legacy, to: settings)
      XCTAssertNotNil(document.settings.thresholdSource)
      XCTAssertEqual(document.configuration.rules.thresholdSource, document.settings.thresholdSource)
      XCTAssertEqual(settings.thresholdConfiguration, before)
      XCTAssertEqual(settings.fontSize, 42)
      XCTAssertEqual(settings.activeResultTags, ["imported"])
      XCTAssertNil(try SettingsJSONCommandCodec.decode(legacy).settings.thresholdSource)
    }
  }

  func testSourceImportPreservesRequestedModifiersWhenTheTestUsesAutomaticArabicLazy() throws {
    try withSettings { settings, _ in
      let document = try SettingsJSONCommandImport.apply(json(arabic: true), to: settings)
      XCTAssertEqual(settings.testModifiers, [])
      XCTAssertEqual(document.configuration.modifiers, [.lazyLatin])
      let preset = SavedTestPreset(configuration: document.configuration)
      XCTAssertTrue(PresetSettingsApplication.commit(original: preset, resolved: preset,
        configuration: preset.configuration, to: settings, appliesGlobalSettings: false))
      XCTAssertEqual(settings.testModifiers, [])
    }
  }

  func testSourceResourceRejectionPrecedesPreferenceAndLayoutWrites() throws {
    try withSettings { settings, defaults in
      let domain = defaults.dictionaryRepresentation() as NSDictionary
      var calls = 0
      XCTAssertThrowsError(try SettingsJSONCommandImport.apply(json(), to: settings,
        selectionAdmission: { _ in calls += 1; return false })) {
        XCTAssertEqual($0 as? SettingsJSONCommandError, .selectionUnavailable)
      }
      XCTAssertEqual(calls, 1)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, domain)
    }
  }

  func testConflictingSharedRulesAreRejectedBeforeResourceAdmissionOrWrites() throws {
    try withSettings { settings, defaults in
      var root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json().utf8)) as? [String: Any])
      var state = try XCTUnwrap(root["thresholdState"] as? [String: Any])
      var snapshot = try XCTUnwrap(state["settings"] as? [String: Any])
      snapshot["strictSpace"] = false
      state["settings"] = snapshot
      root["thresholdState"] = state
      let invalid = String(decoding: try JSONSerialization.data(withJSONObject: root), as: UTF8.self)
      let domain = defaults.dictionaryRepresentation() as NSDictionary
      XCTAssertThrowsError(try SettingsJSONCommandImport.apply(invalid, to: settings,
        selectionAdmission: { _ in XCTFail("Conflicting snapshot must not be admitted"); return true })) {
        XCTAssertEqual($0 as? SettingsJSONCommandError, .invalidConfiguration)
      }
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, domain)
    }
  }

  func testResourceCallbackChangingSourceMemoryCannotBeOverwrittenByAStaleLegacyBridge() throws {
    try withSettings { settings, _ in
      let layouts = settings.layoutFluidLayouts
      XCTAssertThrowsError(try SettingsJSONCommandImport.apply(json(source: false), to: settings,
        selectionAdmission: { _ in
          XCTAssertTrue(settings.updateThresholdConfiguration(.minimumWpm(mode: .off, customValue: 55)))
          return true
        })) { XCTAssertEqual($0 as? SettingsJSONCommandError, .settingsNotApplied) }
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWpmCustomValue, 55)
      XCTAssertEqual(settings.fontSize, 31)
      XCTAssertEqual(settings.layoutFluidLayouts, layouts)
    }
  }

  func testLegacyPositiveRulesBecomeSourceValuesWhileRestoringTheWholeSnapshot() throws {
    try withSettings { settings, _ in
      var snapshot = AppSettingsSnapshot(strictSpace: true, fontSize: 42)
      snapshot.minimumWpm = 48.25
      snapshot.minimumAccuracy = 98.5
      snapshot.minimumWordBurstWpm = 88.25
      snapshot.minimumWordBurstMode = .flex
      let configuration = TestConfiguration.words(3, rules: InputRules(strictSpace: true,
        minimumAccuracy: 98.5, minimumWpm: 48.25, minimumWordBurstWpm: 88.25,
        minimumWordBurstMode: .flex))
      let text = try SettingsJSONCommandCodec.export(settings: snapshot, configuration: configuration,
        layoutFluidLayouts: [.ansiDvorak, .ansiQwerty], testParameterMemory: .defaults)
      let document = try SettingsJSONCommandImport.apply(text, to: settings)
      XCTAssertEqual(document.version, 6)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWpmMode, .custom)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWpmCustomValue, 48.25)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumAccuracyCustomValue, 98.5)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWordBurstMode, .flex)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWordBurstCustomValue, 88.25)
      XCTAssertEqual(settings.fontSize, 42)
      XCTAssertEqual(settings.inputRules, document.configuration.rules)
    }
  }

  func testUnavailableOrStaleSourceStateRejectsBeforeResourceCallbacks() throws {
    for kind in ["lock", "appSettings.v4", "activeTestSelection.v2", "missing", "changedOwner"] {
      try withSettings { settings, defaults in
        let owner = UUID()
        switch kind {
        case "lock": settings.setNoQuitConfigurationLock(true, for: owner)
        case "missing": defaults.removeObject(forKey: "appSettings.v4")
        case "changedOwner":
          var raw = try XCTUnwrap(settings.thresholdConfiguration)
          try raw.apply(.minimumWpm(mode: .off, customValue: 55))
          XCTAssertTrue(ThresholdSettingsStore(defaults: defaults).save(
            PracticeThresholdSource(configuration: raw).applying(to: settings.snapshot)))
        default: defaults.set(Data("{\"version\":99}".utf8), forKey: kind)
        }
        defer { settings.setNoQuitConfigurationLock(false, for: owner) }
        let before = settings.snapshot
        let domain = defaults.dictionaryRepresentation() as NSDictionary
        XCTAssertThrowsError(try SettingsJSONCommandImport.apply(json(), to: settings,
          selectionAdmission: { _ in XCTFail("Unavailable state must not be admitted"); return true })) {
          XCTAssertEqual($0 as? SettingsJSONCommandError,
            kind == "lock" ? .configurationLocked : .settingsNotApplied)
        }
        XCTAssertEqual(settings.snapshot, before)
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, domain)
      }
    }
  }

  func testResourceCallbacksCannotInvalidateTheSourceOrLayoutThenContinueImporting() throws {
    for kind in ["lock", "appSettings.v4", "activeTestSelection.v2", "layout"] {
      try withSettings { settings, defaults in
        let owner = UUID()
        defer { settings.setNoQuitConfigurationLock(false, for: owner) }
        let before = settings.snapshot
        XCTAssertThrowsError(try SettingsJSONCommandImport.apply(json(), to: settings,
          selectionAdmission: { _ in
            switch kind {
            case "lock": settings.setNoQuitConfigurationLock(true, for: owner)
            case "layout": settings.layoutFluidLayouts = [.ansiDvorak, .ansiQwerty]
            default: defaults.set(Data("{\"version\":99}".utf8), forKey: kind)
            }
            return true
          })) {
          XCTAssertEqual($0 as? SettingsJSONCommandError,
            kind == "lock" ? .configurationLocked : .settingsNotApplied)
        }
        XCTAssertEqual(settings.snapshot, before)
        if kind == "layout" { XCTAssertEqual(settings.layoutFluidLayouts, [.ansiDvorak, .ansiQwerty]) }
        else if kind != "lock" { XCTAssertEqual(defaults.data(forKey: kind), Data("{\"version\":99}".utf8)) }
      }
    }
  }

  func testLegacyProjectionConflictsDoNotChooseOneOwnerSilently() throws {
    try withSettings { settings, defaults in
      let text = try SettingsJSONCommandCodec.export(settings: .init(minimumWpm: 55),
        configuration: .words(3), layoutFluidLayouts: [], testParameterMemory: .defaults)
      let before = defaults.dictionaryRepresentation() as NSDictionary
      XCTAssertThrowsError(try SettingsJSONCommandImport.apply(text, to: settings,
        selectionAdmission: { _ in XCTFail("Conflicting projection"); return true })) {
        XCTAssertEqual($0 as? SettingsJSONCommandError, .invalidConfiguration)
      }
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
    }
  }

  func testProductionSourceJSONRestoresSelectionWithoutApplyingGlobalFieldsAgain() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    XCTAssertTrue(source.contains("appliesGlobalSettings: document.settings.thresholdSource == nil"))
    XCTAssertTrue(source.contains("throw SettingsJSONCommandError.selectionApplicationFailed"))
  }
}
