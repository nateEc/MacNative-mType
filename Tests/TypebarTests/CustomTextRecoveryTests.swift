import XCTest
@testable import Typebar

final class CustomTextRecoveryTests: XCTestCase {
  private func config() -> TestConfiguration {
    .init(mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
      customTextCompletion: .sections, customTextSectionLimit: 2,
      customTextOrdering: .inOrder, customTextPipeDelimiter: true)
  }

  func testUnreadableStateMustNotGenerateOrScoreLegacyDisplayText() throws {
    let suite = "typebar.custom-recovery.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let future = try JSONEncoder().encode(CustomTextStateDocument(version: 2,
      source: .prepared(["a|b", "e\u{301}"]), configuration: config()))
    for data in [Data("broken-json".utf8), future] {
      defaults.set(data, forKey: CustomTextStateStore.storageKey)
      let restoration = CustomTextRestorePolicy.restoration(read: CustomTextStateStore(defaults: defaults).read(),
        activePreset: .init(configuration: config(), customText: "a|b | e\u{301}"), explicitSelectionImport: false)
      var session = TestSessionFactory.make(configuration: config(),
        customText: restoration.document?.source.text ?? "a|b | e\u{301}",
        customTextRecoveryBlocked: restoration.recovery.requiresExplicitSource)
      XCTAssertEqual(session.outcome, .failed)
      XCTAssertTrue(session.prompt.isEmpty)
      XCTAssertNotNil(session.generationNotice)
      session.insertBatch("a b ", at: Date(timeIntervalSinceReferenceDate: 918_500_000))
      XCTAssertFalse(session.hasStarted)
      XCTAssertNil(session.result())
      XCTAssertEqual(defaults.data(forKey: CustomTextStateStore.storageKey), data)
    }
  }

  func testReadDistinguishesMissingMalformedWrongTypeInvalidAndAvailableRecords() throws {
    let suite = "typebar.custom-recovery-read.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = CustomTextStateStore(defaults: defaults)
    XCTAssertEqual(store.read(), .missing)
    defaults.set("not-a-data-record", forKey: CustomTextStateStore.storageKey)
    XCTAssertEqual(store.read(), .unavailable)
    XCTAssertEqual(defaults.string(forKey: CustomTextStateStore.storageKey), "not-a-data-record")
    for document in [CustomTextStateDocument(source: .prepared([]), configuration: config()),
      .init(version: 2, source: .prepared(["future"]), configuration: config())] {
      let bytes = try JSONEncoder().encode(document)
      defaults.set(bytes, forKey: CustomTextStateStore.storageKey)
      XCTAssertEqual(store.read(), .unavailable)
      XCTAssertEqual(defaults.data(forKey: CustomTextStateStore.storageKey), bytes)
    }
    let valid = CustomTextStateDocument(source: .prepared(["a|b", "e\u{301}"]), configuration: config())
    defaults.set(try JSONEncoder().encode(valid), forKey: CustomTextStateStore.storageKey)
    XCTAssertEqual(store.read(), .available(valid))
    let restored = CustomTextRestorePolicy.restoration(read: store.read(), activePreset: nil,
      explicitSelectionImport: false)
    XCTAssertFalse(restored.recovery.requiresExplicitSource)
    XCTAssertEqual(restored.document?.source.preparedSections(matching: valid.source.text)?.map { Array($0.utf16) },
      [Array("a|b".utf16), Array("e\u{301}".utf16)])
  }

  func testMissingIndependentRecordStillAllowsLegacyEditorSelection() {
    let preset = SavedTestPreset(configuration: config(), customText: "a|b | e\u{301}")
    let restoration = CustomTextRestorePolicy.restoration(read: .missing,
      activePreset: preset, explicitSelectionImport: false)
    XCTAssertNil(restoration.document)
    XCTAssertFalse(restoration.recovery.requiresExplicitSource)
    let session = TestSessionFactory.make(configuration: config(), customText: preset.customText!,
      customTextRecoveryBlocked: restoration.recovery.requiresExplicitSource)
    XCTAssertEqual(session.outcome, .active)
    XCTAssertEqual(session.prompt, "a b")
    XCTAssertNil(session.generationNotice)
  }

  func testUnreadableCustomStateDoesNotDisableOrdinaryModesOrTheirPersistence() {
    let recovery = CustomTextRecoveryState(read: .unavailable)
    for mode in [TestMode.time, .words, .quote, .zen] {
      let configuration = TestConfiguration(mode: mode, duration: mode == .time ? 30 : nil,
        wordLimit: mode == .words ? 2 : nil, difficulty: .normal, rules: .init())
      let session = TestSessionFactory.make(configuration: configuration,
        customTextRecoveryBlocked: recovery.requiresExplicitSource)
      XCTAssertEqual(session.outcome, .active, "\(mode)")
      XCTAssertNil(session.generationNotice, "\(mode)")
      XCTAssertTrue(recovery.permitsAutomaticPersistence(mode: mode))
    }
    XCTAssertTrue(recovery.requiresExplicitSource)
    XCTAssertFalse(recovery.permitsAutomaticPersistence(mode: .custom))
  }

  func testOnlyAValidExplicitCustomImportOverridesRecoveryBlocking() {
    let known = SavedTestPreset(configuration: config(), customText: "new|source")
    let explicit = CustomTextRestorePolicy.restoration(read: .unavailable,
      activePreset: known, explicitSelectionImport: true)
    XCTAssertFalse(explicit.recovery.requiresExplicitSource)
    XCTAssertNil(explicit.document)
    XCTAssertTrue(CustomTextRestorePolicy.acceptsReplacement(known))
    for preset in [known, .init(configuration: config(), customText: ""),
      .init(configuration: config()), .init(configuration: .words(2))] {
      let result = CustomTextRestorePolicy.restoration(read: .unavailable,
        activePreset: preset, explicitSelectionImport: preset != known)
      XCTAssertTrue(result.recovery.requiresExplicitSource)
    }
    let invalidAvailable = CustomTextStateDocument(source: .prepared([]), configuration: config())
    let invalid = CustomTextRestorePolicy.restoration(read: .available(invalidAvailable),
      activePreset: nil, explicitSelectionImport: false)
    XCTAssertTrue(invalid.recovery.requiresExplicitSource)
    XCTAssertNil(invalid.document)
  }

  func testBlockedGenerationDoesNotConsumeContentAndRepeatRemainsBlocked() {
    var session = TestSessionFactory.make(configuration: config(), customText: "a|b",
      preparedCustomSections: ["a|b"], customTextRecoveryBlocked: true,
      finiteTextSource: "not-a-recovery-source", streamPrompt: "also-not-a-recovery-source",
      nextRandomWordIndex: { XCTFail("A blocked attempt must not generate content"); return 0 })
    XCTAssertEqual(session.outcome, .failed)
    XCTAssertEqual(session.prompt, "")
    let time = Date(timeIntervalSinceReferenceDate: 918_500_000)
    session.insertBatch("a|b", at: time)
    session.tick(at: time.addingTimeInterval(30))
    XCTAssertFalse(session.hasStarted)
    XCTAssertNil(session.result())
    var repeated = session.repeatedAttempt()
    XCTAssertEqual(repeated.outcome, .failed)
    XCTAssertEqual(repeated.generationNotice, session.generationNotice)
    repeated.insertBatch("a|b", at: time.addingTimeInterval(31))
    XCTAssertFalse(repeated.hasStarted)
    XCTAssertNil(repeated.result())
  }

  func testBlockedAutomaticPersistencePreservesBothRecordsButExplicitChoiceCanRun() throws {
    let suite = "typebar.custom-recovery-persist.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let active = ActiveTestSelectionStore(defaults: defaults)
    XCTAssertTrue(active.save(.init(preset: .init(configuration: .words(17)), testParameterMemory: .defaults)))
    let activeBytes = defaults.data(forKey: ActiveTestSelectionStore.storageKey)
    let future = try JSONEncoder().encode(CustomTextStateDocument(version: 2,
      source: .prepared(["future|source"]), configuration: config()))
    defaults.set(future, forKey: CustomTextStateStore.storageKey)
    let store = CustomTextStateStore(defaults: defaults)
    var recovery = CustomTextRecoveryState(read: store.read())
    let explicit = CustomTextStateDocument(source: .prepared(["new|source"]), configuration: config())
    if recovery.permitsAutomaticPersistence(mode: .custom) {
      store.save(explicit)
      active.save(.init(preset: .init(configuration: config(), customText: "fallback"), testParameterMemory: .defaults))
    }
    XCTAssertEqual(defaults.data(forKey: CustomTextStateStore.storageKey), future)
    XCTAssertEqual(defaults.data(forKey: ActiveTestSelectionStore.storageKey), activeBytes)
    recovery.acceptExplicitSource()
    XCTAssertTrue(recovery.permitsAutomaticPersistence(mode: .custom))
    var session = TestSessionFactory.make(configuration: config(), customText: explicit.source.text,
      preparedCustomSections: explicit.source.preparedSections(matching: explicit.source.text),
      customTextRecoveryBlocked: recovery.requiresExplicitSource)
    session.insertBatch(session.prompt, at: Date(timeIntervalSinceReferenceDate: 918_500_000))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertFalse(store.save(explicit))
    XCTAssertEqual(defaults.data(forKey: CustomTextStateStore.storageKey), future)
    XCTAssertTrue(CustomTextRecoveryState(read: store.read()).requiresExplicitSource)
  }
}
