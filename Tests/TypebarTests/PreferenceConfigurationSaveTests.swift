import XCTest

@testable import Typebar

@MainActor
final class PreferenceConfigurationSaveTests: XCTestCase {
  private func withSettings(
    source: Bool = false, _ body: (AppSettings, UserDefaults) throws -> Void
  ) throws {
    let suite = "typebar.preference-save.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    if source {
      XCTAssertTrue(
        ThresholdSettingsStore(defaults: defaults).save(
          PracticeThresholdSource(configuration: .init()).applying(to: AppSettingsSnapshot())))
    }
    try body(AppSettings(defaults: defaults), defaults)
  }

  func testThresholdConfirmationDeliversAfterTheFinalValueEvenWhenUnchanged() throws {
    try withSettings { settings, _ in
      let owner = UUID()
      var values: [Double] = []
      settings.preferenceConfigurationSaves.register(owner: owner) {
        values.append(settings.minimumWpm)
      }
      defer { settings.preferenceConfigurationSaves.remove(owner: owner) }
      let controls = PracticeThresholdPreferences(settings: settings)
      controls.wpm.wrappedValue = 35
      controls.wpm.wrappedValue = 35
      XCTAssertEqual(values, [35, 35])
    }
  }

  func testPreferenceChangePromotesPracticeSelectionAndSurvivesAutomaticSave() throws {
    for source in [false, true] {
      try withSettings(source: source) { settings, defaults in
        let original = ActiveTestSelectionDocument(
          preset: .init(configuration: .words(17)), testParameterMemory: .defaults)
        let practice = try XCTUnwrap(
          WordPracticeText.sectionedPractice(segments: ["a|b"], selectedTargetCount: 1))
        var navigation = try XCTUnwrap(
          WordPracticeTransition.begin(
            previous: nil, practice: practice,
            currentPreset: { original.preset }, currentSelection: { _ in original },
            selectCustomMode: { true }))
        let store = ActiveTestSelectionStore(defaults: defaults)
        XCTAssertTrue(store.save(original))
        @MainActor func current() -> ActiveTestSelectionDocument {
          .init(
            preset: .init(
              configuration: .init(
                mode: .custom, duration: nil, wordLimit: nil,
                difficulty: .normal, rules: settings.inputRules,
                customTextCompletion: .sections, customTextSectionLimit: 1,
                customTextOrdering: practice.ordering, customTextPipeDelimiter: true),
              customText: practice.text), testParameterMemory: .defaults)
        }
        let owner = UUID()
        defer { settings.preferenceConfigurationSaves.remove(owner: owner) }
        settings.preferenceConfigurationSaves.register(owner: owner) {
          XCTAssertTrue(
            navigation.persistSelection(
              current: current(), cause: .configurationSave, save: store.save))
        }
        let controls = PracticeThresholdPreferences(settings: settings)
        controls.wpm.wrappedValue = 35
        let expected = current()
        XCTAssertEqual(store.load(), expected)
        XCTAssertTrue(
          navigation.persistSelection(current: current(), cause: .automatic, save: store.save))
        XCTAssertEqual(ActiveTestSelectionStore(defaults: defaults).load(), expected)
      }
    }
  }

  func testSourceBindingsDeliverCompleteFinalRulesBeforeResultFeedback() throws {
    try withSettings(source: true) { settings, _ in
      let owner = UUID()
      defer { settings.preferenceConfigurationSaves.remove(owner: owner) }
      var rules: [InputRules] = []
      var events: [String] = []
      settings.preferenceConfigurationSaves.register(owner: owner) {
        rules.append(settings.inputRules)
        events.append("save")
      }
      let controls = PracticeThresholdPreferences(
        settings: settings,
        onResult: {
          XCTAssertTrue($0)
          events.append("result")
        })
      controls.wpmEnabled.wrappedValue = true
      controls.wpm.wrappedValue = 0
      controls.accuracyEnabled.wrappedValue = true
      controls.accuracy.wrappedValue = 0
      controls.burstMode.wrappedValue = .flex
      controls.burst.wrappedValue = 0
      XCTAssertEqual(rules.count, 6)
      XCTAssertEqual(rules[1].thresholdSource?.configuration.minimumWpmMode, .custom)
      XCTAssertEqual(rules.last?.thresholdSource, settings.inputRules.thresholdSource)
      XCTAssertEqual(events, Array(repeating: ["save", "result"], count: 6).flatMap { $0 })
    }
  }

  func testRejectedAndAutomaticChangesNeverDeliverPreferenceSaves() throws {
    try withSettings(source: true) { settings, defaults in
      let owner = UUID()
      defer { settings.preferenceConfigurationSaves.remove(owner: owner) }
      var calls = 0
      settings.preferenceConfigurationSaves.register(owner: owner) { calls += 1 }
      settings.minimumWpm = 40  // Model synchronization is not a preference confirmation.
      let controls = PracticeThresholdPreferences(settings: settings)
      controls.accuracy.wrappedValue = 101
      settings.setNoQuitConfigurationLock(true, for: owner)
      controls.wpm.wrappedValue = 35
      settings.setNoQuitConfigurationLock(false, for: owner)
      let refused = PracticeThresholdPreferences(settings: settings, acceptsChange: { false })
      refused.wpm.wrappedValue = 35
      defaults.set(Data("{\"version\":5}".utf8), forKey: "appSettings.v4")
      controls.wpm.wrappedValue = 35
      XCTAssertEqual(calls, 0)
    }
  }

  func testOnlyMostRecentlyActiveLiveOwnerReceivesAndRegistrationDoesNotStealFocus() {
    let router = PreferenceConfigurationSaveRouter()
    let first = UUID()
    let second = UUID()
    var events: [String] = []
    XCTAssertFalse(router.deliver())
    router.register(owner: first) { events.append("first") }
    router.register(owner: second) { events.append("second") }
    XCTAssertTrue(router.deliver())
    XCTAssertEqual(events, ["first"])
    router.activate(owner: second)
    router.register(owner: first) { events.append("updated first") }
    XCTAssertTrue(router.deliver())
    XCTAssertEqual(events, ["first", "second"])
    router.activate(owner: UUID())
    router.remove(owner: second)
    XCTAssertTrue(router.deliver())
    XCTAssertEqual(events.last, "updated first")
    router.remove(owner: first)
    XCTAssertFalse(router.deliver())
  }

  func testRemovalReleasesCallbackAndRecursiveDeliveryIsNotBroadcast() {
    final class Lifetime {}
    let router = PreferenceConfigurationSaveRouter()
    let owner = UUID()
    var lifetime: Lifetime? = Lifetime()
    weak var observed = lifetime
    var calls = 0
    router.register(owner: owner) { [captured = lifetime!] in
      _ = captured
      calls += 1
      XCTAssertFalse(router.deliver())
      router.remove(owner: owner)
    }
    lifetime = nil
    XCTAssertNotNil(observed)
    XCTAssertTrue(router.deliver())
    XCTAssertEqual(calls, 1)
    XCTAssertNil(observed)
    XCTAssertFalse(router.deliver())
  }

  func testSelectionWriteFailureDoesNotPromotePracticeNavigation() throws {
    try withSettings { settings, _ in
      let original = ActiveTestSelectionDocument(
        preset: .init(configuration: .words(17)), testParameterMemory: .defaults)
      let practice = try XCTUnwrap(
        WordPracticeText.sectionedPractice(segments: ["a|b"], selectedTargetCount: 1))
      var navigation = try XCTUnwrap(
        WordPracticeTransition.begin(
          previous: nil, practice: practice,
          currentPreset: { original.preset }, currentSelection: { _ in original },
          selectCustomMode: { true }))
      let current = ActiveTestSelectionDocument(
        preset: .init(configuration: .timed(seconds: 12)), testParameterMemory: .defaults)
      let owner = UUID()
      defer { settings.preferenceConfigurationSaves.remove(owner: owner) }
      var writes = 0
      settings.preferenceConfigurationSaves.register(owner: owner) {
        XCTAssertFalse(
          navigation.persistSelection(
            current: current, cause: .configurationSave,
            save: { _ in
              writes += 1
              return false
            }))
      }
      PracticeThresholdPreferences(settings: settings).wpm.wrappedValue = 35
      XCTAssertEqual(settings.minimumWpm, 35)
      XCTAssertEqual(writes, 1)
      XCTAssertEqual(navigation.persistedSelection(current: current), original)
    }
  }

  func testProductionLifecycleRegistersActivatesAndRemovesOneOwner() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let app = try String(
      contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    XCTAssertTrue(app.contains("@State private var preferenceConfigurationOwner = UUID()"))
    XCTAssertTrue(
      app.contains(
        "settings.preferenceConfigurationSaves.register(owner: preferenceConfigurationOwner,\n        requestedModifiers: { practiceRequestedModifiers }) {\n        persistExplicitTestConfiguration()"
      ))
    XCTAssertTrue(
      app.contains(
        "settings.preferenceConfigurationSaves.activate(owner: preferenceConfigurationOwner)"))
    XCTAssertTrue(
      app.contains(
        ".onDisappear {\n      settings.preferenceConfigurationSaves.remove(owner: preferenceConfigurationOwner)"
      ))
  }
}
