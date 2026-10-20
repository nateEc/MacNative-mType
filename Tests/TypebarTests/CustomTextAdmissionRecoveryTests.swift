import XCTest
@testable import Typebar

final class CustomTextAdmissionRecoveryTests: XCTestCase {
  private func source() -> CustomTextStateDocument {
    .init(source: .prepared(["a|b", "e\u{301}", "é"]), configuration:
      .init(mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
        customTextCompletion: .sections, customTextSectionLimit: 3,
        customTextOrdering: .inOrder, customTextPipeDelimiter: true))
  }

  func testRejectedSelectionStillRestoresSourceOnNextAllowedResetWithoutClobberingIt() throws {
    let suite = "typebar.custom-admission.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = CustomTextStateStore(defaults: defaults)
    let expected = source()
    XCTAssertTrue(store.save(expected))
    let originalBytes = defaults.data(forKey: CustomTextStateStore.storageKey)
    let decision = CustomTextRestorePolicy.restoration(read: store.read(), activePreset: nil,
      explicitSelectionImport: false)
    var recovery = decision.recovery
    var cached = CustomTextStateDocument(source: .editor("stale"), configuration:
      .init(mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()))
    // The old challenge was rejected; its apply never installed the source.
    XCTAssertEqual(defaults.data(forKey: CustomTextStateStore.storageKey), originalBytes)
    if let pending = recovery.takePendingSource(whenAllowed: true) { cached = pending; recovery.acceptExplicitSource() }
    var session = TestSessionFactory.make(configuration: cached.configuration, customText: cached.source.text,
      preparedCustomSections: cached.source.preparedSections(matching: cached.source.text),
      customTextRecoveryBlocked: recovery.blocksCustomGeneration)
    session.insertBatch(session.prompt, at: Date(timeIntervalSinceReferenceDate: 918_600_000))
    XCTAssertEqual(session.outcome, .completed)
    let expectedUnits = [Array("a|b".utf16), Array("e\u{301}".utf16), Array("é".utf16)]
    XCTAssertEqual(session.wordReviews.map { Array($0.target.utf16) }, expectedUnits)
    XCTAssertEqual(cached.configuration.customTextSectionLimit, 3)
    XCTAssertTrue(store.save(cached))
    let saved = try XCTUnwrap(store.load())
    XCTAssertEqual(saved.source.preparedSections(matching: saved.source.text)?.map { Array($0.utf16) }, expectedUnits)
  }

  func testRestartLockKeepsSourcePendingAndPreventsStalePersistence() {
    var recovery = CustomTextRecoveryState(read: .available(source()))
    XCTAssertNotNil(recovery.pendingSource)
    XCTAssertNil(recovery.takePendingSource(whenAllowed: false))
    XCTAssertNotNil(recovery.pendingSource)
    XCTAssertTrue(recovery.blocksCustomGeneration)
    XCTAssertFalse(recovery.permitsAutomaticPersistence(mode: .custom))
    XCTAssertTrue(recovery.permitsAutomaticPersistence(mode: .words))
    XCTAssertNotNil(recovery.takePendingSource(whenAllowed: true))
    XCTAssertNil(recovery.pendingSource)
    XCTAssertFalse(recovery.blocksCustomGeneration)
  }

  func testExplicitReplacementClearsPendingSourceAndValueCopiesRestoreRejectedChoices() {
    var recovery = CustomTextRecoveryState(read: .available(source()))
    let beforeRejectedChoice = recovery
    recovery.acceptExplicitSource()
    XCTAssertNil(recovery.takePendingSource(whenAllowed: true))
    XCTAssertFalse(recovery.blocksCustomGeneration)
    recovery = beforeRejectedChoice
    let restored = recovery.takePendingSource(whenAllowed: true)
    XCTAssertEqual(restored?.source.preparedSections(matching: source().source.text)?.map { Array($0.utf16) },
      [Array("a|b".utf16), Array("e\u{301}".utf16), Array("é".utf16)])
    XCTAssertNil(recovery.takePendingSource(whenAllowed: true))
  }

  func testLegacyAndExplicitImportsQueueTheirKnownEditorSource() throws {
    let text = "e\u{301} | tail"
    let preset = SavedTestPreset(configuration: source().configuration, customText: text)
    let inputs: [(CustomTextStateRead, Bool)] = [(.missing, false), (.available(source()), true), (.unavailable, true)]
    for (read, explicit) in inputs {
      var recovery = CustomTextRestorePolicy.restoration(read: read, activePreset: preset,
        explicitSelectionImport: explicit).recovery
      XCTAssertFalse(recovery.requiresExplicitSource)
      XCTAssertTrue(recovery.blocksCustomGeneration)
      XCTAssertNil(recovery.takePendingSource(whenAllowed: false))
      let pending = try XCTUnwrap(recovery.takePendingSource(whenAllowed: true))
      XCTAssertNil(pending.source.preparedSections(matching: text))
      XCTAssertEqual(Array(pending.source.text.utf16), Array(text.utf16))
      var session = TestSessionFactory.make(configuration: pending.configuration, customText: pending.source.text,
        customTextRecoveryBlocked: recovery.blocksCustomGeneration)
      session.insertBatch(session.prompt, at: Date(timeIntervalSinceReferenceDate: 918_600_000))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.wordReviews.map(\.target), ["é", "tail", "é"])
    }
  }

  func testAllCompletionLimitsRemainIntactWhileDeferred() throws {
    for completion in CustomTextCompletion.allCases {
      let config = TestConfiguration(mode: .custom, duration: completion == .time ? 45 : nil,
        wordLimit: completion == .words ? 17 : nil, difficulty: .normal, rules: .init(),
        customTextCompletion: completion, customTextSectionLimit: completion == .sections ? 0 : nil,
        customTextOrdering: .shuffled, customTextPipeDelimiter: false)
      let expected = CustomTextStateDocument(source: source().source, configuration: config)
      var recovery = CustomTextRecoveryState(read: .available(expected))
      XCTAssertNil(recovery.takePendingSource(whenAllowed: false))
      let restored = try XCTUnwrap(recovery.takePendingSource(whenAllowed: true))
      XCTAssertEqual(restored.configuration, config)
      XCTAssertEqual(restored.source.preparedSections(matching: expected.source.text)?.map { Array($0.utf16) },
        [Array("a|b".utf16), Array("e\u{301}".utf16), Array("é".utf16)])
    }
  }

  func testUnreadableRecordsDoNotAcquireLegacyQueueAndInvalidStagesCannotReplaceIt() {
    let preset = SavedTestPreset(configuration: source().configuration, customText: "legacy")
    var blocked = CustomTextRestorePolicy.restoration(read: .unavailable, activePreset: preset,
      explicitSelectionImport: false).recovery
    blocked.stageKnownSource(source())
    XCTAssertTrue(blocked.requiresExplicitSource)
    XCTAssertNil(blocked.takePendingSource(whenAllowed: true))
    var valid = CustomTextRecoveryState(read: .available(source()))
    valid.stageKnownSource(.init(source: .prepared([]), configuration: source().configuration))
    XCTAssertEqual(valid.takePendingSource(whenAllowed: true), source())
    let missing = CustomTextRestorePolicy.restoration(read: .missing, activePreset: nil,
      explicitSelectionImport: false).recovery
    XCTAssertNil(missing.pendingSource)
    XCTAssertFalse(missing.blocksCustomGeneration)
  }

  func testPendingSourcePreventsBothWritesUntilActuallyInstalled() throws {
    let suite = "typebar.custom-pending-persistence.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = CustomTextStateStore(defaults: defaults)
    let active = ActiveTestSelectionStore(defaults: defaults)
    XCTAssertTrue(store.save(source()))
    XCTAssertTrue(active.save(.init(preset: .init(configuration: .words(17)), testParameterMemory: .defaults)))
    let sourceBytes = defaults.data(forKey: CustomTextStateStore.storageKey)
    let activeBytes = defaults.data(forKey: ActiveTestSelectionStore.storageKey)
    let recovery = CustomTextRecoveryState(read: store.read())
    if recovery.permitsAutomaticPersistence(mode: .custom) {
      store.save(.init(source: .editor("stale"), configuration: source().configuration))
      active.save(.init(preset: .init(configuration: .words(25)), testParameterMemory: .defaults))
    }
    let session = TestSessionFactory.make(configuration: source().configuration, customText: "stale",
      customTextRecoveryBlocked: recovery.blocksCustomGeneration)
    XCTAssertEqual(session.outcome, .failed)
    XCTAssertFalse(session.hasStarted)
    XCTAssertNil(session.result())
    XCTAssertEqual(defaults.data(forKey: CustomTextStateStore.storageKey), sourceBytes)
    XCTAssertEqual(defaults.data(forKey: ActiveTestSelectionStore.storageKey), activeBytes)
  }

  func testCanonicalAliasesAreDifferentPendingValues() {
    let composed = CustomTextStateDocument(source: .prepared(["é"]), configuration: source().configuration)
    let decomposed = CustomTextStateDocument(source: .prepared(["e\u{301}"]), configuration: source().configuration)
    XCTAssertNotEqual(CustomTextRecoveryState(read: .available(composed)),
      CustomTextRecoveryState(read: .available(decomposed)))
    XCTAssertNotEqual(CustomTextSource.editor("é"), .editor("e\u{301}"))
    XCTAssertEqual(CustomTextSource.prepared(["e\u{301}"]), .prepared(["e\u{301}"]))
    XCTAssertNotEqual(CustomTextSource.editor("same"), .prepared(["same"]))
  }
}
