import Observation
import XCTest
@testable import Typebar

@MainActor
final class PreferenceLiveModifierTests: XCTestCase {
  @MainActor @Observable
  fileprivate final class LiveContext {
    var modifiers: [TestModifier] = [.roundVisual]
  }

  private func withLiveChallenge(_ body: (AppSettings, UserDefaults, ChallengeLiveConfigurationState) throws -> Void) throws {
    let suite = "typebar.preference-live-modifiers.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    XCTAssertTrue(ThresholdSettingsStore(defaults: defaults).save(
      PracticeThresholdSource(configuration: .init()).applying(to: AppSettingsSnapshot())))
    let settings = AppSettings(defaults: defaults,
      feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
    let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "round-hour"))
    let configuration = ChallengeInputRulePolicy.applying(settings.inputRules,
      to: challenge.preset.configuration.with(challengeID: challenge.id))
    var state = ChallengeLiveConfigurationState()
    XCTAssertTrue(state.install(configuration, settings: settings))
    XCTAssertEqual(state.modifiers(settings: settings), [.roundVisual])
    XCTAssertEqual(settings.testModifiers, [])
    let owner = UUID()
    settings.preferenceConfigurationSaves.register(owner: owner,
      requestedModifiers: { state.modifiers(settings: settings) }, selectedLanguage: { .english }) {}
    defer { settings.preferenceConfigurationSaves.remove(owner: owner) }
    try body(settings, defaults, state)
  }

  func testCompatibleAdditionPreservesTheLiveChallengeSelection() throws {
    try withLiveChallenge { settings, defaults, live in
      XCTAssertTrue(settings.toggleTestModifier(.mirrorVisual))
      XCTAssertEqual(Set(settings.testModifiers), Set([.roundVisual, .mirrorVisual]))
      XCTAssertEqual(Set(live.modifiers(settings: settings)), Set([.roundVisual, .mirrorVisual]))
      XCTAssertFalse(live.isQualificationCurrent(settings: settings))
      let restored = AppSettings(defaults: defaults,
        feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
      XCTAssertEqual(Set(restored.testModifiers), Set([.roundVisual, .mirrorVisual]))
    }
  }

  func testRemovingTheLiveModifierConfirmsTheSameRawEmptyValueAndInvalidatesQualification() throws {
    try withLiveChallenge { settings, _, live in
      let revision = settings.testModifiersApplicationRevision
      let changed = expectation(description: "Same-raw-value application refreshes the live preference")
      withObservationTracking { _ = settings.preferenceTestModifiers } onChange: { changed.fulfill() }
      XCTAssertTrue(settings.toggleTestModifier(.roundVisual))
      wait(for: [changed], timeout: 1)
      XCTAssertEqual(settings.testModifiers, [])
      XCTAssertEqual(live.modifiers(settings: settings), [])
      XCTAssertEqual(settings.testModifiersApplicationRevision, revision + 1)
      XCTAssertFalse(live.isQualificationCurrent(settings: settings))
    }
  }

  func testConflictingAdditionDoesNotWriteOrInvalidateTheLiveChallenge() throws {
    try withLiveChallenge { settings, defaults, live in
      let before = defaults.dictionaryRepresentation() as NSDictionary
      let revision = settings.testModifiersApplicationRevision
      XCTAssertFalse(settings.toggleTestModifier(.nauseaVisual))
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
      XCTAssertEqual(settings.testModifiersApplicationRevision, revision)
      XCTAssertEqual(live.modifiers(settings: settings), [.roundVisual])
      XCTAssertTrue(live.isQualificationCurrent(settings: settings))
    }
  }

  func testEmptyLiveSelectionIsNotReplacedByAnOlderSavedSelection() throws {
    try withLiveChallenge { settings, _, _ in
      settings.testModifiers = [.nauseaVisual]
      let owner = UUID()
      settings.preferenceConfigurationSaves.register(owner: owner, requestedModifiers: { [] }) {}
      settings.preferenceConfigurationSaves.activate(owner: owner)
      defer { settings.preferenceConfigurationSaves.remove(owner: owner) }
      XCTAssertTrue(settings.toggleTestModifier(.roundVisual))
      XCTAssertEqual(settings.testModifiers, [.roundVisual])
    }
  }

  func testChangingActiveOwnerInvalidatesTheObservedPreferenceSelection() {
    let router = PreferenceConfigurationSaveRouter(), first = UUID(), second = UUID()
    router.register(owner: first, requestedModifiers: { [.roundVisual] }) {}
    router.register(owner: second, requestedModifiers: { [] }) {}
    let changed = expectation(description: "Active preference selection invalidation")
    withObservationTracking { _ = router.requestedModifiers } onChange: { changed.fulfill() }
    router.activate(owner: second)
    wait(for: [changed], timeout: 1)
    XCTAssertEqual(router.requestedModifiers, [])
  }

  func testReadingAndSwitchingContextsNeverAdoptsTransientModifiersOrCancelsQualification() throws {
    try withLiveChallenge { settings, defaults, live in
      let before = defaults.dictionaryRepresentation() as NSDictionary
      let revision = settings.testModifiersApplicationRevision
      XCTAssertEqual(settings.preferenceTestModifiers, [.roundVisual])
      XCTAssertEqual(settings.snapshot.testModifiers, [])
      let other = UUID()
      settings.preferenceConfigurationSaves.register(owner: other, requestedModifiers: { [] }) {}
      defer { settings.preferenceConfigurationSaves.remove(owner: other) }
      let changed = expectation(description: "Nested live preference observation")
      withObservationTracking { _ = settings.preferenceTestModifiers } onChange: { changed.fulfill() }
      settings.preferenceConfigurationSaves.activate(owner: other)
      wait(for: [changed], timeout: 1)
      XCTAssertEqual(settings.preferenceTestModifiers, [])
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
      XCTAssertEqual(settings.testModifiersApplicationRevision, revision)
      XCTAssertTrue(live.isQualificationCurrent(settings: settings))
      settings.preferenceConfigurationSaves.remove(owner: other)
      XCTAssertEqual(settings.preferenceTestModifiers, [.roundVisual])
      XCTAssertEqual(settings.snapshot.testModifiers, [])
    }
  }

  func testObservationFollowsLiveProviderUpdatesAndProviderReplacement() throws {
    try withLiveChallenge { settings, defaults, _ in
      let context = LiveContext(), owner = UUID()
      settings.preferenceConfigurationSaves.register(owner: owner, requestedModifiers: { context.modifiers }) {}
      settings.preferenceConfigurationSaves.activate(owner: owner)
      defer { settings.preferenceConfigurationSaves.remove(owner: owner) }
      let before = defaults.dictionaryRepresentation() as NSDictionary
      let contextChanged = expectation(description: "Live producer update")
      withObservationTracking { _ = settings.preferenceTestModifiers } onChange: { contextChanged.fulfill() }
      context.modifiers = [.layoutFluid]
      wait(for: [contextChanged], timeout: 1)
      XCTAssertEqual(settings.preferenceTestModifiers, [.layoutFluid])
      let providerChanged = expectation(description: "Live producer replacement")
      withObservationTracking { _ = settings.preferenceTestModifiers } onChange: { providerChanged.fulfill() }
      settings.preferenceConfigurationSaves.register(owner: owner, requestedModifiers: { [] }) {}
      wait(for: [providerChanged], timeout: 1)
      XCTAssertEqual(settings.preferenceTestModifiers, [])
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
    }
  }

  func testMissingProviderUsesRawPersistenceNotAnotherWindowsTransientSelection() throws {
    try withLiveChallenge { settings, defaults, _ in
      settings.testModifiers = [.mirrorVisual]
      let first = UUID(), second = UUID()
      settings.preferenceConfigurationSaves.register(owner: first, requestedModifiers: { [.roundVisual] }) {}
      settings.preferenceConfigurationSaves.activate(owner: first)
      XCTAssertEqual(settings.preferenceTestModifiers, [.roundVisual])
      settings.preferenceConfigurationSaves.register(owner: second) {}
      settings.preferenceConfigurationSaves.activate(owner: second)
      defer {
        settings.preferenceConfigurationSaves.remove(owner: second)
        settings.preferenceConfigurationSaves.remove(owner: first)
      }
      let before = defaults.dictionaryRepresentation() as NSDictionary
      XCTAssertEqual(settings.preferenceTestModifiers, [.mirrorVisual])
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
    }
  }

  func testPreferenceControlsReadTheLiveSelectionRatherThanRawPersistence() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let preferences = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/PreferencesView.swift"), encoding: .utf8)
    XCTAssertTrue(preferences.contains("get: { settings.preferenceTestModifiers.contains(modifier) }"))
    XCTAssertTrue(preferences.contains("guard enabled != settings.preferenceTestModifiers.contains(modifier)"))
    XCTAssertTrue(preferences.contains("if settings.preferenceTestModifiers.contains(.layoutFluid)"))
  }
}
