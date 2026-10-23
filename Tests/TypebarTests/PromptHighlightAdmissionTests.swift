import XCTest
@testable import Typebar

@MainActor
final class PromptHighlightAdmissionTests: XCTestCase {
  private func withSettings(source: Bool, _ body: (AppSettings, UserDefaults) throws -> Void) throws {
    let suite = "TypebarTests.HighlightAdmission.\(UUID().uuidString)"
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

  func testRejectedPreferenceBindingNeverWritesOrDispatchesAnEvent() throws {
    for source in [false, true] {
      try withSettings(source: source) { settings, defaults in
        settings.testModifiers = [.readAhead]
        let before = settings.snapshot
        let disk = defaults.dictionaryRepresentation() as NSDictionary
        let wrapper = settings.practiceWrapperRevision
        let presentation = settings.challengePresentationApplicationRevision
        var results: [Bool] = []
        var saves = 0
        let owner = UUID()
        settings.preferenceConfigurationSaves.register(owner: owner) { saves += 1 }
        defer { settings.preferenceConfigurationSaves.remove(owner: owner) }
        let controls = PracticePromptHighlightPreferences(settings: settings, onResult: { results.append($0) })
        let rejected = PromptHighlightMode.allCases.filter {
          !FunboxForcedContentOptionsPolicy.allowedForcedHighlightModes.contains($0)
        }
        for mode in rejected {
          controls.selection.wrappedValue = mode
          XCTAssertEqual(controls.selection.wrappedValue, before.promptHighlightMode)
          XCTAssertEqual(settings.snapshot, before)
          XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, disk)
          XCTAssertEqual(settings.practiceWrapperRevision, wrapper)
          XCTAssertEqual(settings.challengePresentationApplicationRevision, presentation)
        }
        XCTAssertFalse(rejected.isEmpty)
        XCTAssertEqual(results, Array(repeating: false, count: rejected.count))
        XCTAssertEqual(saves, 0)
      }
    }
  }

  func testPreferenceAdmissionReadsLatestLiveOwnerWithoutPersistingItsModifiers() throws {
    try withSettings(source: true) { settings, _ in
      settings.testModifiers = [.readAhead]
      let first = UUID(), second = UUID()
      var firstModifiers: [TestModifier] = [.readAhead]
      var calls: [String] = []
      settings.preferenceConfigurationSaves.register(owner: first,
        requestedModifiers: { firstModifiers }) { calls.append("first") }
      settings.preferenceConfigurationSaves.register(owner: second,
        requestedModifiers: { [.readAhead] }) { calls.append("second") }
      defer {
        settings.preferenceConfigurationSaves.remove(owner: first)
        settings.preferenceConfigurationSaves.remove(owner: second)
      }
      let controls = PracticePromptHighlightPreferences(settings: settings)
      let revision = settings.challengePresentationApplicationRevision
      let wrapper = settings.practiceWrapperRevision
      controls.selection.wrappedValue = .word
      XCTAssertEqual(settings.promptHighlightMode, .letter)
      firstModifiers = []
      controls.selection.wrappedValue = .word
      controls.selection.wrappedValue = .word
      XCTAssertEqual(settings.promptHighlightMode, .word)
      XCTAssertEqual(settings.challengePresentationApplicationRevision, revision + 2)
      XCTAssertEqual(settings.practiceWrapperRevision, wrapper + 2)
      XCTAssertEqual(calls, ["first", "first"])
      XCTAssertEqual(settings.testModifiers, [.readAhead])
      settings.preferenceConfigurationSaves.activate(owner: second)
      controls.selection.wrappedValue = .nextWord
      XCTAssertEqual(settings.promptHighlightMode, .word)
      XCTAssertEqual(calls, ["first", "first"])
      settings.preferenceConfigurationSaves.remove(owner: second)
      controls.selection.wrappedValue = .nextWord
      XCTAssertEqual(settings.promptHighlightMode, .nextWord)
      XCTAssertEqual(calls, ["first", "first", "first"])
      settings.preferenceConfigurationSaves.register(owner: first) { calls.append("replacement") }
      controls.selection.wrappedValue = .word
      XCTAssertEqual(settings.promptHighlightMode, .nextWord,
        "Re-registering without a live provider must not retain the old window state")
      settings.preferenceConfigurationSaves.remove(owner: first)
      controls.selection.wrappedValue = .word
      XCTAssertEqual(settings.promptHighlightMode, .nextWord)
      XCTAssertEqual(settings.challengePresentationApplicationRevision, revision + 3)
    }
  }

  func testRejectedLivePreferencePreservesTheCompletionQualificationFence() throws {
    try withSettings(source: false) { settings, defaults in
      let owner = UUID()
      settings.preferenceConfigurationSaves.register(owner: owner,
        requestedModifiers: { [.readAhead] }) {}
      defer { settings.preferenceConfigurationSaves.remove(owner: owner) }
      var live = ChallengeLiveConfigurationState()
      XCTAssertTrue(live.observeLegacyChallenge(settings: settings))
      let disk = defaults.dictionaryRepresentation() as NSDictionary
      let controls = PracticePromptHighlightPreferences(settings: settings)
      controls.selection.wrappedValue = .word
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, disk)
      XCTAssertTrue(live.isQualificationCurrent(settings: settings))
      controls.selection.wrappedValue = .letter
      XCTAssertFalse(live.isQualificationCurrent(settings: settings),
        "An accepted same-value confirmation still cancels qualification")
    }
  }

  func testCommandUsesItsOwnLiveModifiersAndOnlySavesAcceptedConfirmations() throws {
    try withSettings(source: true) { settings, _ in
      settings.testModifiers = [.readAhead]
      let other = UUID()
      settings.preferenceConfigurationSaves.register(owner: other, requestedModifiers: { [] }) {}
      defer { settings.preferenceConfigurationSaves.remove(owner: other) }
      var saves = 0
      let revision = settings.challengePresentationApplicationRevision
      XCTAssertFalse(AppearanceCommandTarget.highlight(.word).apply(to: settings,
        requestedModifiers: [.readAhead], onConfigurationSave: { saves += 1 }))
      XCTAssertEqual(settings.promptHighlightMode, .letter)
      XCTAssertEqual(settings.challengePresentationApplicationRevision, revision)
      for _ in 0..<2 {
        XCTAssertTrue(AppearanceCommandTarget.highlight(.word).apply(to: settings,
          requestedModifiers: [], onConfigurationSave: { saves += 1 }))
      }
      XCTAssertEqual(settings.promptHighlightMode, .word)
      XCTAssertEqual(settings.challengePresentationApplicationRevision, revision + 2)
      XCTAssertEqual(saves, 2)
      XCTAssertEqual(settings.testModifiers, [.readAhead])
    }
  }

  func testNoQuitDoesNotBlockNonRestartingHighlightButUnreadableSourceDoes() throws {
    try withSettings(source: true) { settings, defaults in
      let owner = UUID()
      settings.setNoQuitConfigurationLock(true, for: owner)
      defer { settings.setNoQuitConfigurationLock(false, for: owner) }
      XCTAssertTrue(settings.applyPromptHighlightMode(.word))
      defaults.set(Data("{\"version\":99}".utf8), forKey: "appSettings.v4")
      let disk = defaults.dictionaryRepresentation() as NSDictionary
      let revision = settings.challengePresentationApplicationRevision
      XCTAssertFalse(settings.applyPromptHighlightMode(.off))
      XCTAssertEqual(settings.promptHighlightMode, .word)
      XCTAssertEqual(settings.challengePresentationApplicationRevision, revision)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, disk)
    }
  }

  func testAdmissionOriginSurvivesRejectionButNotBulkAssignmentOrColdRead() throws {
    try withSettings(source: false) { settings, defaults in
      settings.testModifiers = [.readAhead]
      XCTAssertTrue(settings.applyPromptHighlightMode(.word, modifiers: []))
      XCTAssertTrue(settings.promptHighlightWasInteractivelyAdmitted)
      XCTAssertFalse(settings.applyPromptHighlightMode(.nextWord, modifiers: [.readAhead]))
      XCTAssertTrue(settings.promptHighlightWasInteractivelyAdmitted,
        "A rejected attempt must not invalidate the pending accepted assignment's origin")
      let reload = AppSettings(defaults: defaults,
        feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}),
        localBackgroundStore: .inMemory())
      XCTAssertFalse(reload.promptHighlightWasInteractivelyAdmitted)
      settings.promptHighlightMode = .off
      XCTAssertFalse(settings.promptHighlightWasInteractivelyAdmitted,
        "An old direct/bulk assignment cannot inherit another event's admission")
    }
  }

  func testInteractiveProductionEntrypointsUsePrewriteAdmission() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let preferences = try String(contentsOf: root.appendingPathComponent(
      "Sources/Typebar/PreferencesView.swift"), encoding: .utf8)
    let commands = try String(contentsOf: root.appendingPathComponent(
      "Sources/Typebar/CommandPalette.swift"), encoding: .utf8)
    let app = try String(contentsOf: root.appendingPathComponent(
      "Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    XCTAssertFalse(preferences.contains("selection: $settings.promptHighlightMode"))
    XCTAssertTrue(preferences.contains("selection: promptHighlightPreferences.selection"))
    XCTAssertTrue(commands.contains("settings.applyPromptHighlightMode(mode, modifiers: requestedModifiers)"))
    XCTAssertTrue(app.contains("requestedModifiers: { practiceRequestedModifiers }"))
    XCTAssertTrue(app.contains("guard settings.promptHighlightWasInteractivelyAdmitted\n        || FunboxForcedContentOptionsPolicy.accepts("),
      "A different window must not roll back an explicitly admitted global preference")
  }
}
