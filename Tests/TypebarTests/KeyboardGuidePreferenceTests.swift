import XCTest
@testable import Typebar

@MainActor
final class KeyboardGuidePreferenceTests: XCTestCase {
  private func withSettings(source: Bool = false, _ body: (AppSettings, UserDefaults) throws -> Void) throws {
    let suite = "typebar.keyboard-preference.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    if source {
      XCTAssertTrue(ThresholdSettingsStore(defaults: defaults).save(
        PracticeThresholdSource(configuration: .init()).applying(to: AppSettingsSnapshot())))
    }
    try body(AppSettings(defaults: defaults,
      feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}),
      localBackgroundStore: .inMemory()), defaults)
  }

  func testKeyboardAppearanceCommandsEnableStaticBeforeSavingAnOffGuide() throws {
    try withSettings { settings, defaults in
      for target: KeyboardGuideCommandTarget in [.style(.matrix), .legend(.uppercase), .keys(.full)] {
        settings.keyboardGuideMode = .off
        var calls = 0
        target.apply(to: settings, onConfigurationSave: {
          XCTAssertEqual(settings.effectiveKeyboardGuideMode, .staticGuide)
          calls += 1
        })
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(AppSettings(defaults: defaults).effectiveKeyboardGuideMode, .staticGuide)
      }
    }
  }

  func testSizeAndLayoutAlsoEnableAnOffGuideButInvalidSizeDoesNot() throws {
    try withSettings { settings, _ in
      var calls = 0
      XCTAssertFalse(KeyboardGuideScalePolicy.apply(.nan, to: settings, onConfigurationSave: { calls += 1 }))
      XCTAssertEqual(settings.effectiveKeyboardGuideMode, .off)
      XCTAssertEqual(calls, 0)
      XCTAssertTrue(KeyboardGuideScalePolicy.apply(1.4, to: settings, onConfigurationSave: {
        XCTAssertEqual(settings.effectiveKeyboardGuideMode, .staticGuide)
        calls += 1
      }))
      for target: KeyboardGuideLayoutCommandTarget in [.inputSync, .builtIn(.ansiDvorak)] {
        settings.keyboardGuideMode = .off
        target.apply(to: settings, onConfigurationSave: {
          XCTAssertEqual(settings.effectiveKeyboardGuideMode, .staticGuide)
          calls += 1
        })
      }
      XCTAssertEqual(calls, 3)
    }
  }

  func testEnabledModesRemainUntouchedAndNoQuitDoesNotBlockVisualChanges() throws {
    try withSettings { settings, _ in
      let owner = UUID()
      settings.setNoQuitConfigurationLock(true, for: owner)
      defer { settings.setNoQuitConfigurationLock(false, for: owner) }
      for mode: KeyboardGuideMode in [.staticGuide, .react, .next] {
        settings.keyboardGuideMode = mode
        let before = settings.keyboardGuideApplicationRevision
        KeyboardGuideCommandTarget.legend(.uppercase).apply(to: settings)
        XCTAssertEqual(settings.effectiveKeyboardGuideMode, mode)
        XCTAssertEqual(settings.keyboardGuideApplicationRevision, before)
      }
      KeyboardGuideCommandTarget.mode(.off).apply(to: settings)
      KeyboardGuideCommandTarget.keys(.full).apply(to: settings)
      XCTAssertEqual(settings.effectiveKeyboardGuideMode, .staticGuide)
      XCTAssertFalse(settings.allowsRestartingConfigurationChange)
    }
  }

  func testBindingsSaveTheCurrentWindowSnapshotInBothStorageGenerations() throws {
    for source in [false, true] {
      try withSettings(source: source) { settings, defaults in
        settings.installedPracticeFontName = "Menlo"
        settings.keyboardGuideMode = .react
        let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "ten-words-of-pain"))
        let configuration = ChallengeInputRulePolicy.applying(settings.inputRules,
          to: challenge.preset.configuration.with(challengeID: challenge.id))
        var live = ChallengeLiveConfigurationState()
        if source { XCTAssertTrue(live.install(configuration, settings: settings)) }
        else { XCTAssertTrue(live.observeLegacyChallenge(settings: settings, configuration: configuration)) }
        let owner = UUID()
        var saves = 0
        settings.preferenceConfigurationSaves.register(owner: owner,
          keyboardGuideMode: { live.keyboardGuideMode(settings: settings) }) {
          saves += 1
          XCTAssertTrue(settings.persistLiveConfiguration(live, hasActiveLocalFont: { false }))
        }
        defer { settings.preferenceConfigurationSaves.remove(owner: owner) }
        let controls = PracticeKeyboardGuidePreferences(settings: settings)
        XCTAssertEqual(controls.mode.wrappedValue, .off)
        XCTAssertEqual(settings.keyboardGuideMode, .react) // Reading does not adopt an overlay.
        controls.style.wrappedValue = .matrix
        XCTAssertEqual(controls.mode.wrappedValue, .staticGuide)
        XCTAssertEqual(saves, 1)
        XCTAssertFalse(live.isQualificationCurrent(settings: settings))
        let fontEpoch = settings.practiceFontApplicationRevision
        controls.mode.wrappedValue = .off
        controls.scale.wrappedValue = 1.4
        controls.legend.wrappedValue = .uppercase
        controls.keys.wrappedValue = .full
        controls.layout.wrappedValue = .ansiDvorak
        controls.layoutSource.wrappedValue = .systemInput
        XCTAssertEqual(saves, 7)
        controls.scale.wrappedValue = .nan
        XCTAssertEqual(saves, 7)
        XCTAssertEqual(settings.practiceFontApplicationRevision, fontEpoch)
        XCTAssertEqual(settings.installedPracticeFontName, WingdingsChallengeFont.familyName)
        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.snapshot, settings.snapshot)
        XCTAssertEqual(restored.effectiveKeyboardGuideMode, .staticGuide)
        XCTAssertEqual(restored.hasThresholdProfile, source)
      }
    }
  }

  func testGuideContextUsesOnlyTheSaveOwnerAndMissingProviderFallsBackToRaw() throws {
    try withSettings { settings, _ in
      settings.keyboardGuideMode = .react
      let first = UUID(), second = UUID()
      let router = settings.preferenceConfigurationSaves
      router.register(owner: first, keyboardGuideMode: { .off }, save: {})
      router.register(owner: second, keyboardGuideMode: { .next }, save: {})
      XCTAssertEqual(settings.preferenceKeyboardGuideMode, .off)
      router.activate(owner: second)
      XCTAssertEqual(settings.preferenceKeyboardGuideMode, .next)
      let before = settings.keyboardGuideApplicationRevision
      KeyboardGuideCommandTarget.style(.matrix).apply(to: settings)
      XCTAssertEqual(settings.keyboardGuideApplicationRevision, before)
      XCTAssertEqual(settings.keyboardGuideMode, .react)
      router.register(owner: second, save: {})
      XCTAssertEqual(settings.preferenceKeyboardGuideMode, .react)
      router.remove(owner: second)
      XCTAssertEqual(settings.preferenceKeyboardGuideMode, .off)
      router.remove(owner: first)
      XCTAssertEqual(settings.preferenceKeyboardGuideMode, .react)
    }
  }

  func testSettingsAndMainUseTheSharedBindingsAndLiveConfigNotRenderedFunboxMode() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let preferences = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/PreferencesView.swift"), encoding: .utf8)
    for property in ["mode", "scale", "legend", "keys", "style", "layout", "layoutSource"] {
      XCTAssertTrue(preferences.contains("keyboardGuidePreferences.\(property)"))
    }
    XCTAssertTrue(preferences.contains("if settings.preferenceKeyboardGuideMode != .off"))
    let main = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    XCTAssertTrue(main.contains("keyboardGuideMode: { challengeLiveConfiguration.keyboardGuideMode(settings: settings) }"))
  }

  func testAllNativeKeyboardConfirmationsMatchPinnedIndividualSetters() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let reference = environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] ?? environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    guard environment["TYPEBAR_WEBSITE_CONFIG_ZOD_ROOT"] != nil else { return XCTFail("Requires pinned Zod QA dependency") }
    struct Fixture: Decodable {
      var mode: KeyboardGuideMode, noQuit: Bool, key: String, value: WebsiteConfigValue
      var accepted: Bool, resultMode: KeyboardGuideMode, resultValue: WebsiteConfigValue
      var events: [String], saves: [String]
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-config-schema.mjs").path,
      reference, "--keyboard-confirmations"]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode([Fixture].self, from: data)
    XCTAssertEqual(fixtures.count, 192)
    try withSettings { settings, _ in
      let owner = UUID()
      defer { settings.setNoQuitConfigurationLock(false, for: owner) }
      for fixture in fixtures {
        settings.keyboardGuideMode = fixture.mode
        settings.setNoQuitConfigurationLock(fixture.noQuit, for: owner)
        var saves = 0
        let save = { saves += 1 }
        let value: WebsiteConfigValue
        switch (fixture.key, fixture.value) {
        case ("keymapMode", .string(let raw)):
          KeyboardGuideCommandTarget.mode(try XCTUnwrap(KeyboardGuideMode(rawValue: raw))).apply(to: settings, onConfigurationSave: save)
          value = .string(settings.effectiveKeyboardGuideMode.rawValue)
        case ("keymapStyle", .string(let raw)):
          KeyboardGuideCommandTarget.style(try XCTUnwrap(KeyboardGuideStyle(rawValue: raw))).apply(to: settings, onConfigurationSave: save)
          value = .string(settings.keyboardGuideStyle.rawValue)
        case ("keymapLegendStyle", .string(let raw)):
          KeyboardGuideCommandTarget.legend(try XCTUnwrap(KeyboardGuideLegendStyle(rawValue: raw))).apply(to: settings, onConfigurationSave: save)
          value = .string(settings.keyboardGuideLegendStyle.rawValue)
        case ("keymapKeys", .string(let raw)):
          KeyboardGuideCommandTarget.keys(try XCTUnwrap(KeyboardGuideKeysMode(rawValue: raw))).apply(to: settings, onConfigurationSave: save)
          value = .string(settings.keyboardGuideKeysMode.rawValue)
        case ("keymapSize", .number(let number)):
          XCTAssertTrue(KeyboardGuideScalePolicy.apply(number, to: settings, onConfigurationSave: save))
          value = .number(settings.keyboardGuideScale)
        case ("keymapLayout", .string(let raw)):
          let target: KeyboardGuideLayoutCommandTarget = raw == "overrideSync" ? .inputSync : .builtIn(raw == "qwerty" ? .ansiQwerty : .ansiDvorak)
          target.apply(to: settings, onConfigurationSave: save)
          value = .string(settings.keyboardGuideLayoutSource == .inputEmulation ? "overrideSync" : settings.keyboardLayout == .ansiQwerty ? "qwerty" : "dvorak")
        default: return XCTFail("Unexpected keyboard fixture")
        }
        XCTAssertTrue(fixture.accepted)
        XCTAssertEqual(settings.effectiveKeyboardGuideMode, fixture.resultMode, "\(fixture.key) from \(fixture.mode)")
        XCTAssertEqual(value, fixture.resultValue)
        XCTAssertEqual(saves, 1)
        let expectedEvents = fixture.mode == .off && fixture.key != "keymapMode" ? ["keymapMode", fixture.key] : [fixture.key]
        XCTAssertEqual(fixture.events, expectedEvents)
        XCTAssertEqual(fixture.saves, expectedEvents)
      }
    }
  }
}
