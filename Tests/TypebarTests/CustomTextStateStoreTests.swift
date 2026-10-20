import XCTest
@testable import Typebar

final class CustomTextStateStoreTests: XCTestCase {
  func testPreparedSourceSurvivesSavedStateReadAndActualSessionCompletion() throws {
    let suite = "typebar.custom-source-state.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let sections = ["a|b", "e\u{301}", "é"]
    let config = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), customTextCompletion: .sections,
      customTextSectionLimit: 3, customTextOrdering: .inOrder, customTextPipeDelimiter: true)
    let preset = SavedTestPreset(configuration: config, customText: sections.joined(separator: " | "))
    XCTAssertTrue(ActiveTestSelectionStore(defaults: defaults).save(.init(preset: preset,
      testParameterMemory: .defaults)))
    XCTAssertTrue(CustomTextStateStore(defaults: defaults).save(.init(source: .prepared(sections), configuration: config)))
    let restored = try XCTUnwrap(CustomTextStateStore(defaults: defaults).load())
    var session = TestSessionFactory.make(configuration: restored.configuration,
      customText: restored.source.text, preparedCustomSections: restored.source.preparedSections(matching: restored.source.text))
    session.insertBatch(session.prompt, at: Date(timeIntervalSinceReferenceDate: 918_400_000))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.wordReviews.map { Array($0.target.utf16) }, sections.map { Array($0.utf16) })
  }

  private func config() -> TestConfiguration {
    .init(mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
      customTextCompletion: .sections, customTextSectionLimit: 3,
      customTextOrdering: .inOrder, customTextPipeDelimiter: true)
  }

  func testEditorStillUsesNFCAndDoesNotAcquirePreparedOrigin() throws {
    let document = CustomTextStateDocument(source: .editor("e\u{301} | a|b"), configuration: config())
    let restored = try JSONDecoder().decode(CustomTextStateDocument.self, from: JSONEncoder().encode(document))
    XCTAssertTrue(restored.isValid)
    XCTAssertNil(restored.source.preparedSections(matching: restored.source.text))
    let session = TestSessionFactory.make(configuration: restored.configuration, customText: restored.source.text)
    XCTAssertEqual(Array(session.prompt.utf16), Array("é a b".utf16))
  }

  func testPreparedOriginIsNotInferredFromCanonicalDisplayAliases() {
    let source = CustomTextSource.prepared(["e\u{301}"])
    XCTAssertNotNil(source.preparedSections(matching: "e\u{301}"))
    XCTAssertNil(source.preparedSections(matching: "é"))
    XCTAssertNil(CustomTextSource.editor("e\u{301}").preparedSections(matching: "e\u{301}"))
  }

  func testRestorePrecedenceHonorsExplicitCustomImportsAndKeepsOtherModesIndependent() {
    let stored = CustomTextStateDocument(source: .prepared(["a|b"]), configuration: config())
    let custom = SavedTestPreset(configuration: config(), customText: "imported")
    XCTAssertEqual(CustomTextRestorePolicy.source(stored: stored, activePreset: custom,
      explicitSelectionImport: false), stored)
    XCTAssertNil(CustomTextRestorePolicy.source(stored: stored, activePreset: custom,
      explicitSelectionImport: true))
    XCTAssertEqual(CustomTextRestorePolicy.source(stored: stored,
      activePreset: .init(configuration: .words(17)), explicitSelectionImport: true), stored)
    XCTAssertEqual(CustomTextRestorePolicy.source(stored: stored, activePreset: nil,
      explicitSelectionImport: true), stored)
  }

  func testUnsupportedVersionAndInvalidWritesDoNotOverwriteStoredBytes() throws {
    let suite = "typebar.custom-source-validation.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = CustomTextStateStore(defaults: defaults)
    let valid = CustomTextStateDocument(source: .prepared(["a|b"]), configuration: config())
    XCTAssertTrue(store.save(valid))
    let bytes = defaults.data(forKey: CustomTextStateStore.storageKey)
    XCTAssertFalse(store.save(.init(source: .prepared([]), configuration: config())))
    XCTAssertFalse(store.save(.init(source: .editor(" | "), configuration: config())))
    XCTAssertEqual(defaults.data(forKey: CustomTextStateStore.storageKey), bytes)
    let future = try JSONEncoder().encode(CustomTextStateDocument(version: 2,
      source: .prepared(["future|source"]), configuration: config()))
    defaults.set(future, forKey: CustomTextStateStore.storageKey)
    XCTAssertNil(store.load())
    XCTAssertFalse(store.save(valid))
    XCTAssertEqual(defaults.data(forKey: CustomTextStateStore.storageKey), future)
    let corrupt = Data("not-json".utf8)
    defaults.set(corrupt, forKey: CustomTextStateStore.storageKey)
    XCTAssertNil(store.load())
    XCTAssertEqual(defaults.data(forKey: CustomTextStateStore.storageKey), corrupt)
  }

  func testPreparedTextAboveEditorLimitIsNotClampedOrResplit() throws {
    let sections = Array(repeating: "e\u{301}|target", count: 1_100)
    let source = CustomTextSource.prepared(sections)
    XCTAssertGreaterThan(source.text.count, CustomTextPolicy.maximumLength)
    let document = CustomTextStateDocument(source: source, configuration: config())
    let restored = try JSONDecoder().decode(CustomTextStateDocument.self, from: JSONEncoder().encode(document))
    XCTAssertTrue(restored.isValid)
    XCTAssertEqual(restored.source.preparedSections(matching: source.text)?.map { Array($0.utf16) },
      sections.map { Array($0.utf16) })
  }

  func testAllCustomLimitKindsRoundTripWithoutCapturingLanguageOrInputRules() throws {
    for completion in CustomTextCompletion.allCases {
      let configuration = TestConfiguration(mode: .custom,
        duration: completion == .time ? 45 : nil, wordLimit: completion == .words ? 17 : nil,
        difficulty: .expert, rules: .init(strictSpace: true), language: .spanish,
        customTextCompletion: completion, customTextSectionLimit: completion == .sections ? 0 : nil,
        customTextOrdering: .shuffled, customTextPipeDelimiter: false)
      let document = CustomTextStateDocument(source: .prepared(["a|b", "e\u{301}"]), configuration: configuration)
      let data = try JSONEncoder().encode(document)
      let restored = try JSONDecoder().decode(CustomTextStateDocument.self, from: data)
      XCTAssertTrue(restored.isValid)
      XCTAssertEqual(restored.completion, completion)
      XCTAssertEqual(restored.configuration.customTextOrdering, .shuffled)
      XCTAssertEqual(restored.configuration.customTextPipeDelimiter, false)
      XCTAssertEqual(restored.configuration.duration, configuration.duration)
      XCTAssertEqual(restored.configuration.wordLimit, configuration.wordLimit)
      XCTAssertEqual(restored.configuration.customTextSectionLimit, configuration.customTextSectionLimit)
      let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys
      XCTAssertFalse(keys.contains("language"))
      XCTAssertFalse(keys.contains("rules"))
      XCTAssertFalse(keys.contains("difficulty"))
    }
  }

  func testInactiveLimitFieldsCannotInjectUnvalidatedParameterMemory() throws {
    for completion in [CustomTextCompletion.finish, .time, .words] {
      let configuration = TestConfiguration(mode: .custom,
        duration: completion == .time ? 45 : nil, wordLimit: completion == .words ? 17 : nil,
        difficulty: .normal, rules: .init(), customTextCompletion: completion)
      let document = CustomTextStateDocument(source: .prepared(["target"]), configuration: configuration)
      var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
      payload["sectionLimit"] = OfficialTestLimitInput.maximumValue + 1
      let decoded = try JSONDecoder().decode(CustomTextStateDocument.self,
        from: JSONSerialization.data(withJSONObject: payload))
      XCTAssertFalse(decoded.isValid, "Inactive limit must not bypass validation: \(completion)")
    }
  }

  func testNestedPracticeCapturesPreviousCustomContentWithoutChangingTheRootMode() throws {
    let source = CustomTextStateDocument(source: .prepared(["a|b", "e\u{301}"]), configuration: config())
    let preset = SavedTestPreset(configuration: config(), customText: source.source.text)
    let selection = ActiveTestSelectionDocument(preset: preset, testParameterMemory: .defaults)
    let practice = try XCTUnwrap(WordPracticeText.sectionedPractice(segments: ["next"], selectedTargetCount: 1))
    let first = try XCTUnwrap(WordPracticeTransition.begin(previous: nil, practice: practice,
      currentPreset: { preset }, currentSelection: { _ in selection },
      currentCustomTextState: { source }, selectCustomMode: { true }))
    let previousPractice = CustomTextStateDocument(source: .prepared(practice.sections), configuration: config())
    let second = try XCTUnwrap(WordPracticeTransition.begin(previous: first, practice: practice,
      currentPreset: { XCTFail("Recaptured preset"); return preset }, currentSelection: { _ in selection },
      currentCustomTextState: { previousPractice }, selectCustomMode: { true }))
    XCTAssertEqual(second.returnCustomTextState?.source.preparedSections(matching: previousPractice.source.text)?.map { Array($0.utf16) },
      practice.sections.map { Array($0.utf16) })
    XCTAssertEqual(second.returnPreset, preset)
    XCTAssertEqual(second.returnSelection, selection)
    let noSource = try XCTUnwrap(WordPracticeTransition.begin(previous: nil, practice: practice,
      currentPreset: { preset }, currentSelection: { _ in selection }, selectCustomMode: { true }))
    let nested = try XCTUnwrap(WordPracticeTransition.begin(previous: noSource, practice: practice,
      currentPreset: { preset }, currentSelection: { _ in selection },
      currentCustomTextState: { previousPractice }, selectCustomMode: { true }))
    XCTAssertEqual(nested.returnCustomTextState, previousPractice)
  }

  func testLeavingPracticeKeepsLatestCustomContentUnlessAnEarlierCustomSourceWasCaptured() {
    let captured = CustomTextStateDocument(source: .editor("original"), configuration: config())
    let latest = CustomTextStateDocument(source: .prepared(["a|b", "e\u{301}"]), configuration: config())
    XCTAssertEqual(CustomTextRestorePolicy.returningSource(captured: nil, latest: { latest }), latest)
    XCTAssertEqual(CustomTextRestorePolicy.returningSource(captured: captured,
      latest: { latest }), captured)
  }

  func testIndependentProcessesReadPreparedArraysAndKeepOrdinaryMode() throws {
    let environment = ProcessInfo.processInfo.environment
    let key = "TYPEBAR_CUSTOM_STATE_CHILD_STAGE"
    let suiteKey = "TYPEBAR_CUSTOM_STATE_CHILD_SUITE"
    if let stage = environment[key] {
      let suite = try XCTUnwrap(environment[suiteKey])
      XCTAssertTrue(suite.hasPrefix("typebar.custom-source-process."))
      let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      let sections = ["a|b", "e\u{301}", "é"]
      if stage == "write" {
        XCTAssertTrue(ActiveTestSelectionStore(defaults: defaults).save(.init(
          preset: .init(configuration: .words(17)), testParameterMemory: .defaults)))
        XCTAssertTrue(CustomTextStateStore(defaults: defaults).save(.init(source: .prepared(sections), configuration: config())))
        XCTAssertTrue(defaults.synchronize())
      } else {
        XCTAssertEqual(stage, "read")
        XCTAssertEqual(ActiveTestSelectionStore(defaults: defaults).load()?.preset.configuration.mode, .words)
        let restored = try XCTUnwrap(CustomTextStateStore(defaults: defaults).load())
        var session = TestSessionFactory.make(configuration: restored.configuration,
          customText: restored.source.text, preparedCustomSections: restored.source.preparedSections(matching: restored.source.text))
        session.insertBatch(session.prompt, at: Date(timeIntervalSinceReferenceDate: 918_400_000))
        XCTAssertEqual(session.outcome, .completed)
        XCTAssertEqual(session.wordReviews.map { Array($0.target.utf16) }, sections.map { Array($0.utf16) })
        defaults.set(session.wordReviews.map(\.target), forKey: "qa.custom-state-read-targets")
        XCTAssertTrue(defaults.synchronize())
      }
      return
    }
    let suite = "typebar.custom-source-process.\(UUID().uuidString)"
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    for stage in ["write", "read"] {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
      process.arguments = ["xctest", "-XCTest",
        "TypebarTests.CustomTextStateStoreTests/testIndependentProcessesReadPreparedArraysAndKeepOrdinaryMode",
        Bundle(for: Self.self).bundleURL.path]
      let allowed = ["PATH", "DEVELOPER_DIR", "SDKROOT", "DYLD_FRAMEWORK_PATH", "DYLD_LIBRARY_PATH"]
      process.environment = environment.filter { allowed.contains($0.key) }
      process.environment?[key] = stage
      process.environment?[suiteKey] = suite
      process.environment?["TYPEBAR_QA_IN_MEMORY_STORE"] = "1"
      let output = Pipe()
      process.standardOutput = output
      process.standardError = output
      try process.run()
      let deadline = Date().addingTimeInterval(30)
      while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
      if process.isRunning { process.terminate(); XCTFail("Custom-state child timed out: \(stage)") }
      process.waitUntilExit()
      let diagnostics = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .split(separator: "\n").filter { $0.contains("error:") || $0.contains("failed") }.joined(separator: "\n")
      XCTAssertEqual(process.terminationStatus, 0, "Custom-state child \(stage): \(diagnostics)")
      // A filter that silently ran zero child tests must not pass this test.
      let witness = try XCTUnwrap(UserDefaults(suiteName: suite))
      XCTAssertTrue(witness.synchronize())
      let expected = ["a|b", "e\u{301}", "é"].map { Array($0.utf16) }
      if stage == "write" {
        let saved = try XCTUnwrap(CustomTextStateStore(defaults: witness).load())
        XCTAssertEqual(saved.source.preparedSections(matching: saved.source.text)?.map { Array($0.utf16) }, expected)
        XCTAssertEqual(ActiveTestSelectionStore(defaults: witness).load()?.preset.configuration.mode, .words)
      } else {
        let targets = try XCTUnwrap(witness.array(forKey: "qa.custom-state-read-targets") as? [String])
        XCTAssertEqual(targets.map { Array($0.utf16) }, expected)
      }
    }
  }
}
