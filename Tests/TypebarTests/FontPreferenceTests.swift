import AppKit
import XCTest
@testable import Typebar

@MainActor
final class FontPreferenceTests: XCTestCase {
  private func withSettings(source: Bool = false, _ body: (AppSettings, UserDefaults) throws -> Void) throws {
    let suite = "typebar.font-preference.\(UUID().uuidString)"
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

  func testNamedAndSystemFontApplicationsNeverDeactivateTheLocalOverride() throws {
    try withSettings { settings, _ in
      var saves = 0
      let resolver = NativePracticeFont.Resolver(localFontName: { "Courier" }, installedFontName: { _ in "Menlo" })
      for target: FontFamilyCommandTarget in [.systemDesign(.serif), .knownIdentifier("Georgia"), .installedName("Menlo")] {
        XCTAssertTrue(FontFamilyCommandApplication.apply(target, to: settings,
          isFontAvailable: { _ in true },
          onConfigurationSave: { saves += 1 }))
        XCTAssertEqual(resolver.postScriptName(for: settings.installedPracticeFontName), "Courier")
      }
      XCTAssertTrue(FontFamilyNameCommandPolicy.apply("Owned Family", to: settings,
        onConfigurationSave: { saves += 1 }))
      XCTAssertEqual(saves, 4)
      XCTAssertEqual(resolver.postScriptName(for: settings.installedPracticeFontName), "Courier")
    }
  }

  func testSavingAChallengeFontNeverQueriesOrChangesTheLocalFileSelection() throws {
    for source in [false, true] {
      try withSettings(source: source) { settings, defaults in
        let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "ten-words-of-pain"))
        let configuration = ChallengeInputRulePolicy.applying(settings.inputRules,
          to: challenge.preset.configuration.with(challengeID: challenge.id))
        var live = ChallengeLiveConfigurationState()
        if source { XCTAssertTrue(live.install(configuration, settings: settings)) }
        else { XCTAssertTrue(live.observeLegacyChallenge(settings: settings, configuration: configuration)) }
        XCTAssertTrue(settings.persistLiveConfiguration(live))
        XCTAssertEqual(AppSettings(defaults: defaults).installedPracticeFontName, WingdingsChallengeFont.familyName)
        XCTAssertTrue(live.isQualificationCurrent(settings: settings))
      }
    }
  }

  func testProductionPreferencesDoNotDeactivateFilesInDelayedObservers() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let preferences = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/PreferencesView.swift"), encoding: .utf8)
    XCTAssertFalse(preferences.contains(".onChange(of: settings.practiceFont)"))
    XCTAssertFalse(preferences.contains(".onChange(of: settings.installedPracticeFontName)"))
    XCTAssertFalse(preferences.contains("settings.deactivateLocalPracticeFont()"))
    let settings = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/AppSettings.swift"), encoding: .utf8)
    let from = try XCTUnwrap(settings.range(of: "func persistLiveConfiguration("))
    let to = try XCTUnwrap(settings.range(of: "private func applySourceSnapshot(", range: from.upperBound..<settings.endIndex))
    let saveBody = settings[from.lowerBound..<to.lowerBound]
    XCTAssertFalse(saveBody.contains("LocalFont"))
    XCTAssertFalse(saveBody.contains("localPracticeFont"))
    XCTAssertFalse(saveBody.contains("TransientFontPersistencePolicy"))
    for property in ["size", "design", "installedSelection", "familyName"] {
      XCTAssertTrue(preferences.contains("fontPreferences.\(property)"))
    }
    XCTAssertTrue(preferences.contains(".onSubmit { applyPracticeFontName() }"))
    XCTAssertTrue(preferences.contains("Button(\"应用\") { applyPracticeFontName() }"))
    XCTAssertTrue(preferences.contains("NativePracticeFont.isAvailable(fontPreferences.familyName)"))
    XCTAssertFalse(preferences.contains("NativePracticeFont.isAvailable(settings.installedPracticeFontName)"))
    let app = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    XCTAssertTrue(app.contains("fontFamilyName: { challengeLiveConfiguration.fontFamilyName(settings: settings) }"))
    XCTAssertTrue(app.contains("size: size, installedFontName: challengeLiveConfiguration.fontFamilyName(settings: settings)"))
    XCTAssertFalse(app.contains("if challengeLiveConfiguration.hasTransientFont(settings: settings),"))
    XCTAssertFalse(app.contains("settings.deactivateLocalPracticeFont()"))
  }

  func testBindingsSaveLiveFontAndUnownedFieldsUnderNoQuitInBothStorageGenerations() throws {
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
        settings.setNoQuitConfigurationLock(true, for: owner)
        var saves = 0, results: [Bool] = []
        settings.preferenceConfigurationSaves.register(owner: owner, fontFamilyName: { live.fontFamilyName(settings: settings) }) {
          saves += 1
          XCTAssertTrue(settings.persistLiveConfiguration(live))
        }
        defer {
          settings.setNoQuitConfigurationLock(false, for: owner)
          settings.preferenceConfigurationSaves.remove(owner: owner)
        }
        let controls = PracticeFontPreferences(settings: settings, onResult: { results.append($0) })
        XCTAssertEqual(controls.familyName, WingdingsChallengeFont.familyName)
        XCTAssertEqual(controls.installedSelection.wrappedValue, controls.familyName)
        XCTAssertEqual(settings.installedPracticeFontName, "Menlo")
        let epoch = settings.practiceFontApplicationRevision
        let before = defaults.data(forKey: source ? "appSettings.v4" : "appSettings.v1")
        XCTAssertFalse(controls.applyName("Bad\nName"))
        controls.size.wrappedValue = .nan
        controls.size.wrappedValue = 0
        XCTAssertEqual(saves, 0)
        XCTAssertEqual(settings.practiceFontApplicationRevision, epoch)
        XCTAssertEqual(defaults.data(forKey: source ? "appSettings.v4" : "appSettings.v1"), before)
        controls.size.wrappedValue = 32
        XCTAssertEqual(settings.installedPracticeFontName, WingdingsChallengeFont.familyName)
        XCTAssertEqual(settings.practiceFontApplicationRevision, epoch)
        XCTAssertEqual(settings.effectiveKeyboardGuideMode, .off)
        XCTAssertTrue(controls.applyName("  Owned Family  "))
        XCTAssertEqual(settings.installedPracticeFontName, "Owned Family")
        XCTAssertFalse(live.isQualificationCurrent(settings: settings))
        XCTAssertTrue(controls.applyName(""))
        XCTAssertEqual(settings.installedPracticeFontName, "")
        controls.design.wrappedValue = .serif
        XCTAssertEqual(settings.practiceFont, .serif)
        controls.installedSelection.wrappedValue = "Menlo"
        XCTAssertEqual(settings.installedPracticeFontName, "Menlo")
        XCTAssertEqual(saves, 5)
        XCTAssertEqual(results, [false, false, false, true, true, true, true, true])
        XCTAssertFalse(settings.allowsRestartingConfigurationChange)
        XCTAssertEqual(AppSettings(defaults: defaults).snapshot, settings.snapshot)
        XCTAssertEqual(settings.hasThresholdProfile, source)
      }
    }
  }

  func testOnlyTheActiveFontOwnerIsReadAndEmptyFamilyDoesNotFallBack() throws {
    try withSettings { settings, _ in
      settings.installedPracticeFontName = "Menlo"
      let router = settings.preferenceConfigurationSaves
      let first = UUID(), second = UUID()
      router.register(owner: first, fontFamilyName: { "Wingdings" }, save: {})
      router.register(owner: second, fontFamilyName: { "" }, save: {})
      XCTAssertEqual(settings.preferenceFontFamilyName, "Wingdings")
      router.activate(owner: second)
      XCTAssertEqual(settings.preferenceFontFamilyName, "")
      router.register(owner: second, save: {})
      XCTAssertEqual(settings.preferenceFontFamilyName, "Menlo")
      router.remove(owner: second)
      XCTAssertEqual(settings.preferenceFontFamilyName, "Wingdings")
      router.remove(owner: first)
      XCTAssertEqual(settings.preferenceFontFamilyName, "Menlo")
    }
  }

  func testFileOnlyOperationsDoNotPretendToApplyAConfigFontFamily() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/AppSettings.swift"), encoding: .utf8)
    let start = try XCTUnwrap(source.range(of: "func importLocalPracticeFont("))
    let end = try XCTUnwrap(source.range(of: "func resolvedTheme(", range: start.upperBound..<source.endIndex))
    XCTAssertFalse(source[start.lowerBound..<end.lowerBound].contains("practiceFontApplicationRevision"))
  }

  func testSuccessfulFileOperationsOnlyRefreshTheFileAndFailuresPublishNothing() throws {
    enum Failure: Error { case owned }
    for source in [false, true] {
      try withSettings(source: source) { settings, defaults in
        let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "ten-words-of-pain"))
        let configuration = ChallengeInputRulePolicy.applying(settings.inputRules,
          to: challenge.preset.configuration.with(challengeID: challenge.id))
        var live = ChallengeLiveConfigurationState()
        if source { XCTAssertTrue(live.install(configuration, settings: settings)) }
        else { XCTAssertTrue(live.observeLegacyChallenge(settings: settings, configuration: configuration)) }
        let epoch = settings.practiceFontApplicationRevision
        let local = settings.localPracticeFontRevision
        let data = defaults.data(forKey: source ? "appSettings.v4" : "appSettings.v1")
        var saves = 0
        let owner = UUID()
        settings.preferenceConfigurationSaves.register(owner: owner) { saves += 1 }
        defer { settings.preferenceConfigurationSaves.remove(owner: owner) }
        XCTAssertThrowsError(try settings.importLocalPracticeFont(data: Data([1]), originalFilename: "owned.ttf", save: { _, _ in throw Failure.owned }))
        XCTAssertFalse(settings.activateLocalPracticeFont(activate: { false }))
        XCTAssertThrowsError(try settings.removeLocalPracticeFont(remove: { throw Failure.owned }))
        XCTAssertEqual(settings.localPracticeFontRevision, local)
        try settings.importLocalPracticeFont(data: Data([1]), originalFilename: "owned.ttf", save: {
          XCTAssertEqual($0, Data([1])); XCTAssertEqual($1, "owned.ttf")
        })
        XCTAssertEqual(settings.localPracticeFontRevision, local + 1)
        XCTAssertTrue(settings.activateLocalPracticeFont(activate: { true }))
        XCTAssertEqual(settings.localPracticeFontRevision, local + 2)
        try settings.removeLocalPracticeFont(remove: {})
        XCTAssertEqual(settings.localPracticeFontRevision, local + 3)
        XCTAssertEqual(settings.practiceFontApplicationRevision, epoch)
        XCTAssertEqual(live.fontFamilyName(settings: settings), WingdingsChallengeFont.familyName)
        XCTAssertTrue(live.isQualificationCurrent(settings: settings))
        XCTAssertEqual(defaults.data(forKey: source ? "appSettings.v4" : "appSettings.v1"), data)
        XCTAssertEqual(saves, 0)
      }
    }
  }
}
