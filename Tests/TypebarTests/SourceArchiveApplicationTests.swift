import SwiftData
import XCTest
@testable import Typebar

@MainActor
final class SourceArchiveApplicationTests: XCTestCase {
  private func withSettings(sourceProfile: Bool = true, feedbackSound: ((UserDefaults) -> TypingFeedbackSound)? = nil,
    _ body: (AppSettings, UserDefaults) throws -> Void) throws {
    let suite = "typebar.source-archive-application.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var raw = PracticeThresholdConfiguration()
    try raw.apply(.minimumWpm(mode: .off, customValue: 37))
    try raw.apply(.minimumAccuracy(mode: .off, customValue: 93))
    try raw.apply(.minimumWordBurst(mode: .off, customValue: 84))
    defaults.set(try JSONEncoder().encode(AppSettingsSnapshot(fontSize: 22)), forKey: "appSettings.v1")
    if sourceProfile {
      XCTAssertTrue(ThresholdSettingsStore(defaults: defaults).save(
        PracticeThresholdSource(configuration: raw).applying(to: .init(fontSize: 31))))
    }
    try body(AppSettings(defaults: defaults,
      feedbackSound: feedbackSound?(defaults) ?? TypingFeedbackSound(loadSound: { _ in nil }, beep: {}),
      localBackgroundStore: .inMemory()), defaults)
  }

  private func container(_ url: URL? = nil, allowsSave: Bool = true) throws -> ModelContainer {
    let configuration = url.map { ModelConfiguration(url: $0, allowsSave: allowsSave, cloudKitDatabase: .none) }
      ?? ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self, SavedCustomTextRecord.self,
      ResultFilterPresetRecord.self, LocalPersonalBestLedgerRecord.self, configurations: configuration)
    container.mainContext.autosaveEnabled = false
    return container
  }

  private func archive(source: Bool = true, selection: Bool = true) throws -> TypebarArchive {
    var snapshot = AppSettingsSnapshot(strictSpace: true, fontSize: 42)
    var configuration = TestConfiguration.words(3, rules: InputRules(strictSpace: true))
    if source {
      var raw = PracticeThresholdConfiguration()
      try raw.apply(.minimumWpm(mode: .custom, customValue: 0))
      try raw.apply(.minimumWordBurst(mode: .flex, customValue: 0))
      let owner = PracticeThresholdSource(configuration: raw)
      snapshot = owner.applying(to: snapshot)
      configuration.rules = owner.applying(to: configuration.rules)
    }
    let start = Date(timeIntervalSince1970: 1000)
    let result = CompletedTestResult(id: UUID(), configuration: .timed(seconds: 15), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(15), typedCharacterCount: 75,
      correctCharacterCount: 75, errorCount: 0, wpm: 60, rawWpm: 60, accuracy: 100)
    let active = ActiveTestSelectionDocument(preset: .init(configuration: configuration),
      testParameterMemory: .init(duration: 30, wordLimit: 3, customTextDuration: 30,
        customTextWordLimit: 25, customTextSectionLimit: 1))
    return .init(exportedAt: start, settings: snapshot, results: [result],
      presets: [.init(id: UUID(), name: "Old preset", definition: .init(configuration: .words(3)))],
      savedTexts: [.init(id: UUID(), title: "Owned", text: "owned practice text")],
      activeTestSelection: selection ? active : nil)
  }

  private func apply(_ archive: TypebarArchive, settings: AppSettings, defaults: UserDefaults,
    context: ModelContext, source: ArchiveImportSource = .localFile,
    resources: @escaping @MainActor (TestConfiguration) -> Bool = ArchiveSourceAdmission.resourcesAvailable) throws -> ArchiveImportSummary {
    try LocalArchiveImport.apply(archive, settings: settings,
      results: context.fetch(FetchDescriptor<TestResultRecord>()),
      presets: context.fetch(FetchDescriptor<TestPresetRecord>()),
      savedTexts: context.fetch(FetchDescriptor<SavedCustomTextRecord>()),
      resultTombstoneStore: .init(defaults: defaults), presetTombstoneStore: .init(defaults: defaults),
      savedTextTombstoneStore: .init(defaults: defaults), customizationTombstoneStore: .init(defaults: defaults),
      resultFilterPresets: context.fetch(FetchDescriptor<ResultFilterPresetRecord>()),
      tombstoneStore: .init(defaults: defaults), source: source,
      selectionResourcesAvailable: resources, modelContext: context)
  }

  private func challengeArchive(source: Bool = true, id: String = "clean-twenty-five") throws -> TypebarArchive {
    let original = try archive(source: source)
    let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: id))
    var configuration = challenge.preset.configuration.with(challengeID: challenge.id)
    if let owner = original.settings.thresholdSource {
      configuration.rules = owner.applying(to: configuration.rules)
    }
    let selection = ActiveTestSelectionDocument(preset: .init(configuration: configuration,
      customText: challenge.preset.customText), testParameterMemory: .defaults)
    return .init(exportedAt: original.exportedAt, settings: original.settings,
      results: original.results, presets: original.presets, savedTexts: original.savedTexts,
      activeTestSelection: selection)
  }

  func testSourceArchiveRestoresChallengeSelectionAndColdReaderCompletesIt() throws {
    try withSettings { settings, defaults in
      let store = try container()
      let original = try challengeArchive()
      let incoming = try TypebarDataTransfer.importArchive(from: TypebarArchiveDocument(archive: original).archiveData())
      let summary = try apply(incoming, settings: settings, defaults: defaults, context: store.mainContext)
      XCTAssertTrue(summary.restoredActiveTestSelection)
      XCTAssertEqual(summary.insertedResults, 1)
      let reader = AppSettings(defaults: defaults,
        feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
      let selection = try XCTUnwrap(reader.activeTestSelection)
      let prepared = try XCTUnwrap(PresetSourcePreparation.preparing(selection.preset, to: reader,
        appliesGlobalSettings: false))
      let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: selection.preset.configuration.challengeID))
      let configuration = ChallengeInputRulePolicy.applying(reader.inputRules,
        to: ChallengeSetupSelectionPolicy.applying(.init(configuration: selection.preset.configuration), for: challenge))
      let profile = defaults.data(forKey: "appSettings.v4")
      XCTAssertTrue(PresetSettingsApplication.commit(original: prepared.preset, resolved: prepared.preset,
        configuration: configuration, to: reader, appliesGlobalSettings: false,
        expectedSourceState: prepared.baseline))
      var session = TestSessionFactory.make(configuration: configuration)
      session.insertBatch(session.prompt, at: Date(timeIntervalSince1970: 100))
      let result = try XCTUnwrap(session.result())
      XCTAssertTrue(ChallengeEvaluator.evaluate(result, challenge: challenge).passed)
      XCTAssertEqual(defaults.data(forKey: "appSettings.v4"), profile)
    }
  }

  func testLegacyChallengeArchivePromotesSelectionWithoutDiscardingSourceMemories() throws {
    try withSettings { settings, defaults in
      let store = try container()
      let remembered = settings.thresholdConfiguration
      let old = defaults.data(forKey: "appSettings.v1")
      let summary = try apply(challengeArchive(source: false), settings: settings,
        defaults: defaults, context: store.mainContext)
      XCTAssertTrue(summary.restoredActiveTestSelection)
      XCTAssertEqual(settings.thresholdConfiguration, remembered)
      XCTAssertEqual(settings.activeTestSelection?.version, 2)
      XCTAssertEqual(settings.activeTestSelection?.preset.configuration.challengeID, "clean-twenty-five")
      XCTAssertEqual(defaults.data(forKey: "appSettings.v1"), old)
    }
  }

  func testMissingChallengeResourcesRejectBeforeRecordsPreferencesAndMarkers() throws {
    try withSettings { settings, defaults in
      let store = try container()
      let incoming = try challengeArchive(id: "ten-words-of-pain")
      let before = defaults.dictionaryRepresentation() as NSDictionary
      XCTAssertThrowsError(try apply(incoming, settings: settings, defaults: defaults,
        context: store.mainContext, resources: { configuration in
          PresetResourceAdmission.refusal(for: configuration, wingdingsAvailable: { false },
            scriptIsVerified: { _ in false }) == nil
        })) { XCTAssertEqual($0 as? LocalArchiveImportError, .activeTestSelectionResourcesUnavailable) }
      XCTAssertEqual(try store.mainContext.fetchCount(FetchDescriptor<TestResultRecord>()), 0)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
    }
  }

  func testResourceCallbackCannotOverwriteANewerProfileBeforeRecordWrites() throws {
    try withSettings { settings, defaults in
      let store = try container()
      let originalThresholds = settings.thresholdConfiguration
      XCTAssertThrowsError(try apply(challengeArchive(), settings: settings, defaults: defaults,
        context: store.mainContext, resources: { _ in settings.fontSize = 48; return true })) {
        XCTAssertEqual($0 as? LocalArchiveImportError, .sourceStateUnavailable)
      }
      XCTAssertEqual(settings.fontSize, 48)
      XCTAssertEqual(settings.thresholdConfiguration, originalThresholds)
      XCTAssertEqual(try store.mainContext.fetchCount(FetchDescriptor<TestResultRecord>()), 0)
      XCTAssertNil(settings.activeTestSelection)
    }
  }

  func testLateResourceLossReportsCommittedRecordsAndSettingsWithoutSavingSelection() throws {
    var available = true
    try withSettings(feedbackSound: { _ in
      TypingFeedbackSound(loadSound: { _ in available = false; return nil }, beep: {})
    }) { settings, defaults in
      let store = try container()
      let original = try challengeArchive()
      var snapshot = original.settings
      snapshot.playKeyclickSound = true
      let incoming = TypebarArchive(exportedAt: original.exportedAt, settings: snapshot,
        results: original.results, presets: original.presets, savedTexts: original.savedTexts,
        activeTestSelection: original.activeTestSelection)
      XCTAssertThrowsError(try apply(incoming, settings: settings, defaults: defaults,
        context: store.mainContext, resources: { _ in available })) {
        XCTAssertEqual($0 as? LocalArchiveImportError, .recordsAndSettingsImportedSelectionNotApplied)
      }
      XCTAssertEqual(try store.mainContext.fetchCount(FetchDescriptor<TestResultRecord>()), 1)
      XCTAssertEqual(settings.snapshot, snapshot)
      XCTAssertNil(settings.activeTestSelection)
      XCTAssertEqual(settings.activeTestSelectionGeneration, 0)
    }
  }

  func testLateResourceCallbackPreservesAChangedSelectionRatherThanOverwritingIt() throws {
    try withSettings { settings, defaults in
      let store = try container()
      var calls = 0
      XCTAssertThrowsError(try apply(challengeArchive(), settings: settings, defaults: defaults,
        context: store.mainContext, resources: { _ in
          calls += 1
          if calls == 3 {
            XCTAssertTrue(settings.importActiveTestSelection(.init(preset: .init(
              configuration: .words(17, rules: settings.inputRules)), testParameterMemory: .defaults)))
          }
          return true
        })) { XCTAssertEqual($0 as? LocalArchiveImportError, .recordsAndSettingsImportedSelectionNotApplied) }
      XCTAssertEqual(try store.mainContext.fetchCount(FetchDescriptor<TestResultRecord>()), 1)
      XCTAssertEqual(settings.activeTestSelection?.preset.configuration.wordLimit, 17)
      XCTAssertNil(settings.activeTestSelection?.preset.configuration.challengeID)
    }
  }

  func testForgedChallengeSelectionIsRejectedBeforeResourceChecksAndWrites() throws {
    try withSettings { settings, defaults in
      let store = try container()
      let original = try challengeArchive()
      var preset = try XCTUnwrap(original.activeTestSelection).preset
      preset.configuration.wordLimit = 3
      let incoming = TypebarArchive(exportedAt: original.exportedAt, settings: original.settings,
        results: original.results, presets: original.presets, savedTexts: original.savedTexts,
        activeTestSelection: .init(preset: preset, testParameterMemory: .defaults))
      let before = defaults.dictionaryRepresentation() as NSDictionary
      var checked = false
      XCTAssertThrowsError(try apply(incoming, settings: settings, defaults: defaults,
        context: store.mainContext, resources: { _ in checked = true; return true })) {
        XCTAssertEqual($0 as? LocalArchiveImportError, .invalidActiveTestSelection)
      }
      XCTAssertFalse(checked)
      XCTAssertEqual(try store.mainContext.fetchCount(FetchDescriptor<TestResultRecord>()), 0)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
    }
  }

  func testReimportedChallengeReplaysRestorationWithoutDuplicatingRecords() throws {
    try withSettings { settings, defaults in
      let store = try container()
      let incoming = try challengeArchive()
      _ = try apply(incoming, settings: settings, defaults: defaults, context: store.mainContext)
      let generation = settings.activeTestSelectionGeneration
      let repeated = try apply(incoming, settings: settings, defaults: defaults, context: store.mainContext)
      XCTAssertEqual(repeated.insertedResults, 0)
      XCTAssertEqual(repeated.insertedPresets, 0)
      XCTAssertEqual(repeated.insertedSavedTexts, 0)
      XCTAssertTrue(repeated.restoredActiveTestSelection)
      XCTAssertEqual(settings.activeTestSelectionGeneration, generation + 1)
      XCTAssertEqual(try store.mainContext.fetchCount(FetchDescriptor<TestResultRecord>()), 1)
    }
  }

  func testLegacyUnchangedCloudMergeDoesNotPublishSettingsOrSelectionEvents() throws {
    try withSettings(sourceProfile: false) { settings, defaults in
      let store = try container()
      let original = try challengeArchive(source: false)
      _ = try apply(original, settings: settings, defaults: defaults, context: store.mainContext)
      let incoming = TypebarArchive(exportedAt: original.exportedAt, settings: settings.snapshot,
        results: original.results, presets: original.presets, savedTexts: original.savedTexts,
        activeTestSelection: settings.activeTestSelection)
      let generation = settings.activeTestSelectionGeneration
      let difficultyRevision = settings.difficultyApplicationRevision
      let modifierRevision = settings.testModifiersApplicationRevision
      let presentationRevision = settings.challengePresentationApplicationRevision
      let before = defaults.dictionaryRepresentation() as NSDictionary
      let summary = try apply(incoming, settings: settings, defaults: defaults,
        context: store.mainContext, source: .cloudSync)
      XCTAssertFalse(summary.restoredActiveTestSelection)
      XCTAssertEqual(summary.insertedResults, 0)
      XCTAssertEqual(settings.activeTestSelectionGeneration, generation)
      XCTAssertEqual(settings.difficultyApplicationRevision, difficultyRevision)
      XCTAssertEqual(settings.testModifiersApplicationRevision, modifierRevision)
      XCTAssertEqual(settings.challengePresentationApplicationRevision, presentationRevision)
      XCTAssertFalse(settings.hasThresholdProfile)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
    }
  }

  func testUnchangedCloudMergeDoesNotApplySettingsOrReplayChallengeSelection() throws {
    try withSettings { settings, defaults in
      let store = try container()
      let incoming = try challengeArchive()
      _ = try apply(incoming, settings: settings, defaults: defaults, context: store.mainContext)
      let generation = settings.activeTestSelectionGeneration
      let difficulty = settings.difficultyApplicationRevision
      let modifiers = settings.testModifiersApplicationRevision
      let presentation = settings.challengePresentationApplicationRevision
      let before = defaults.dictionaryRepresentation() as NSDictionary
      let merged = try apply(incoming, settings: settings, defaults: defaults,
        context: store.mainContext, source: .cloudSync)
      XCTAssertFalse(merged.restoredActiveTestSelection)
      XCTAssertEqual(merged.insertedResults, 0)
      XCTAssertEqual(settings.activeTestSelectionGeneration, generation)
      XCTAssertEqual(settings.difficultyApplicationRevision, difficulty)
      XCTAssertEqual(settings.testModifiersApplicationRevision, modifiers)
      XCTAssertEqual(settings.challengePresentationApplicationRevision, presentation)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
    }
  }

  func testFullSourceArchiveImportsRecordsSettingsAndSelectionWithoutRewritingLegacyHistory() throws {
    try withSettings { settings, defaults in
      let container = try container()
      let original = try archive()
      let decoded = try TypebarDataTransfer.importArchive(from: TypebarArchiveDocument(archive: original).archiveData())
      let legacyBytes = defaults.data(forKey: "appSettings.v1")
      let summary = try apply(decoded, settings: settings, defaults: defaults, context: container.mainContext)
      XCTAssertEqual(summary.insertedResults, 1)
      XCTAssertEqual(summary.insertedPresets, 1)
      XCTAssertEqual(summary.insertedSavedTexts, 1)
      XCTAssertTrue(summary.restoredActiveTestSelection)
      XCTAssertEqual(settings.snapshot, decoded.settings)
      XCTAssertEqual(settings.activeTestSelection, decoded.activeTestSelection)
      XCTAssertEqual(defaults.data(forKey: "appSettings.v1"), legacyBytes)
      let records = try container.mainContext.fetch(FetchDescriptor<TestResultRecord>())
      XCTAssertEqual(records.first?.portableResult, decoded.results.first)
      XCTAssertNil(records.first?.configuration?.rules.thresholdSource)
    }
  }

  func testLegacyArchiveBridgesSettingsAndSelectionWhileRetainingOffMemoriesAndOldSelectionBytes() throws {
    try withSettings { settings, defaults in
      let container = try container()
      let existing = ActiveTestSelectionDocument(preset: .init(configuration: .words(25)), testParameterMemory: .defaults)
      XCTAssertTrue(settings.saveActiveTestSelection(existing))
      let oldBytes = defaults.data(forKey: "activeTestSelection.v1")
      let remembered = settings.thresholdConfiguration
      let summary = try apply(archive(source: false), settings: settings, defaults: defaults, context: container.mainContext)
      XCTAssertTrue(summary.restoredActiveTestSelection)
      XCTAssertEqual(settings.thresholdConfiguration, remembered)
      XCTAssertEqual(settings.activeTestSelection?.version, 2)
      XCTAssertEqual(settings.activeTestSelection?.testParameterMemory.wordLimit, 3)
      XCTAssertEqual(defaults.data(forKey: "activeTestSelection.v1"), oldBytes)
      XCTAssertEqual(settings.fontSize, 42)
    }
  }

  func testRepeatedSourceArchiveDoesNotDuplicateRecordsOrDispatchSelectionAgain() throws {
    try withSettings { settings, defaults in
      let container = try container()
      let incoming = try archive()
      _ = try apply(incoming, settings: settings, defaults: defaults, context: container.mainContext)
      let generation = settings.activeTestSelectionGeneration
      let summary = try apply(incoming, settings: settings, defaults: defaults, context: container.mainContext)
      XCTAssertEqual(summary.insertedResults, 0)
      XCTAssertEqual(summary.insertedPresets, 0)
      XCTAssertEqual(summary.insertedSavedTexts, 0)
      XCTAssertFalse(summary.restoredActiveTestSelection)
      XCTAssertEqual(settings.activeTestSelectionGeneration, generation)
    }
  }

  func testColdReaderRestoresSourceArchiveAndActualSessionFromSavedSelection() throws {
    try withSettings { settings, defaults in
      let container = try container()
      _ = try apply(archive(), settings: settings, defaults: defaults, context: container.mainContext)
      let reader = AppSettings(defaults: defaults,
        feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
      let selection = try XCTUnwrap(reader.activeTestSelection)
      var configuration = selection.preset.configuration
      configuration.wordLimit = selection.testParameterMemory.wordLimit
      configuration.rules = reader.inputRules
      var session = TestSessionFactory.make(configuration: configuration)
      session.insertBatch(session.prompt, at: Date(timeIntervalSince1970: 100))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(reader.thresholdConfiguration?.minimumWpmMode, .custom)
      XCTAssertEqual(reader.thresholdConfiguration?.minimumWordBurstMode, .flex)
    }
  }

  func testActualLateSettingsFailureReportsCommittedRecordsInsteadOfSuccess() throws {
    let future = Data("{\"version\":99}".utf8)
    try withSettings(feedbackSound: { defaults in
      TypingFeedbackSound(loadSound: { _ in defaults.set(future, forKey: "appSettings.v4"); return nil }, beep: {})
    }) { settings, defaults in
      let container = try container()
      let original = try archive()
      var snapshot = original.settings
      snapshot.playKeyclickSound = true
      let incoming = TypebarArchive(exportedAt: original.exportedAt, settings: snapshot,
        results: original.results, presets: original.presets, savedTexts: original.savedTexts,
        activeTestSelection: original.activeTestSelection)
      XCTAssertThrowsError(try apply(incoming, settings: settings, defaults: defaults, context: container.mainContext)) {
        XCTAssertEqual($0 as? LocalArchiveImportError, .recordsImportedSettingsNotApplied)
      }
      XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<TestResultRecord>()), 1)
      XCTAssertEqual(defaults.data(forKey: "appSettings.v4"), future)
      XCTAssertNil(settings.activeTestSelection)
    }
  }

  func testInvalidSourceSnapshotIsRejectedBeforeAnyRecordOrPreferenceWrite() throws {
    try withSettings { settings, defaults in
      let container = try container()
      let original = try archive()
      var invalid = original.settings
      invalid.minimumWpm = 45
      let incoming = TypebarArchive(exportedAt: original.exportedAt, settings: invalid,
        results: original.results, presets: original.presets, savedTexts: original.savedTexts,
        activeTestSelection: original.activeTestSelection)
      let before = defaults.dictionaryRepresentation()
      XCTAssertThrowsError(try apply(incoming, settings: settings, defaults: defaults, context: container.mainContext)) {
        XCTAssertEqual($0 as? LocalArchiveImportError, .invalidSourceSettings)
      }
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before as NSDictionary)
      XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<TestResultRecord>()), 0)
      XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<TestPresetRecord>()), 0)
      XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<SavedCustomTextRecord>()), 0)
    }
  }

  func testFutureSelectionStoreIsRejectedBeforeAnyRecordOrPreferenceWrite() throws {
    try withSettings { settings, defaults in
      let container = try container()
      defaults.set(Data("{\"version\":99}".utf8), forKey: "activeTestSelection.v2")
      let before = defaults.dictionaryRepresentation()
      XCTAssertThrowsError(try apply(archive(), settings: settings, defaults: defaults, context: container.mainContext)) {
        XCTAssertEqual($0 as? LocalArchiveImportError, .sourceStateUnavailable)
      }
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before as NSDictionary)
      XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<TestResultRecord>()), 0)
    }
  }

  func testAbsentArchivedSelectionKeepsExistingSelectionWhileApplyingGlobalSettings() throws {
    try withSettings { settings, defaults in
      let container = try container()
      let existing = try XCTUnwrap(archive().activeTestSelection)
      XCTAssertTrue(settings.saveActiveTestSelection(existing))
      let generation = settings.activeTestSelectionGeneration
      let incoming = try archive(selection: false)
      let summary = try apply(incoming, settings: settings, defaults: defaults, context: container.mainContext)
      XCTAssertFalse(summary.restoredActiveTestSelection)
      XCTAssertEqual(settings.activeTestSelection, existing)
      XCTAssertEqual(settings.activeTestSelectionGeneration, generation)
      XCTAssertEqual(settings.snapshot, incoming.settings)
    }
  }

  func testRealReadOnlyDatabaseFailureLeavesPreferencesAndPersistedRecordsUntouched() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-source-archive-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("store.sqlite")
    try autoreleasepool {
      let store = try container(url)
      try store.mainContext.save()
      withExtendedLifetime(store) {}
    }
    try withSettings { settings, defaults in
      let before = defaults.dictionaryRepresentation()
      let snapshot = settings.snapshot
      try autoreleasepool {
        let store = try container(url, allowsSave: false)
        defer { withExtendedLifetime(store) {} }
        let incoming = try archive()
        XCTAssertThrowsError(try apply(incoming, settings: settings, defaults: defaults, context: store.mainContext)) {
          XCTAssertTrue($0.localizedDescription.contains("重新打开应用"))
          XCTAssertTrue($0.localizedDescription.contains("设置与删除标记未导入"))
          XCTAssertEqual((($0 as? ArchivePersistenceFailure)?.underlyingError as NSError?)?.domain,
            NSCocoaErrorDomain)
        }
        XCTAssertEqual(settings.snapshot, snapshot)
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before as NSDictionary)
        // Failed saves can leave registered objects in this context. The fresh
        // container below is authoritative for persistence, not this cache.
        XCTAssertFalse(store.mainContext.hasChanges)
        XCTAssertThrowsError(try apply(incoming, settings: settings, defaults: defaults, context: store.mainContext)) {
          XCTAssertNotNil($0 as? ArchivePersistenceFailure)
        }
        XCTAssertEqual(settings.snapshot, snapshot)
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before as NSDictionary)
      }
      try autoreleasepool {
        let store = try container(url)
        defer { withExtendedLifetime(store) {} }
        XCTAssertEqual(try store.mainContext.fetchCount(FetchDescriptor<TestResultRecord>()), 0)
        XCTAssertEqual(try store.mainContext.fetchCount(FetchDescriptor<TestPresetRecord>()), 0)
        XCTAssertEqual(try store.mainContext.fetchCount(FetchDescriptor<SavedCustomTextRecord>()), 0)
      }
    }
  }

  func testActualLateSelectionFailureReportsSavedSettingsAndRecords() throws {
    let future = Data("{\"version\":99}".utf8)
    try withSettings(feedbackSound: { defaults in
      TypingFeedbackSound(loadSound: { _ in defaults.set(future, forKey: "activeTestSelection.v2"); return nil }, beep: {})
    }) { settings, defaults in
      let container = try container()
      let original = try archive()
      var snapshot = original.settings
      snapshot.playKeyclickSound = true
      let incoming = TypebarArchive(exportedAt: original.exportedAt, settings: snapshot,
        results: original.results, presets: original.presets, savedTexts: original.savedTexts,
        activeTestSelection: original.activeTestSelection)
      XCTAssertThrowsError(try apply(incoming, settings: settings, defaults: defaults, context: container.mainContext)) {
        XCTAssertEqual($0 as? LocalArchiveImportError, .recordsAndSettingsImportedSelectionNotApplied)
      }
      XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<TestResultRecord>()), 1)
      XCTAssertEqual(ThresholdSettingsStore(defaults: defaults).read(), .available(snapshot))
      XCTAssertEqual(defaults.data(forKey: "activeTestSelection.v2"), future)
      XCTAssertEqual(settings.activeTestSelectionGeneration, 0)
    }
  }
}
