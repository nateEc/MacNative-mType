import SwiftData
import XCTest
@testable import Typebar

@MainActor
final class SourceArchiveApplicationTests: XCTestCase {
  private func withSettings(feedbackSound: ((UserDefaults) -> TypingFeedbackSound)? = nil,
    _ body: (AppSettings, UserDefaults) throws -> Void) throws {
    let suite = "typebar.source-archive-application.\(UUID().uuidString)"
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
    context: ModelContext, source: ArchiveImportSource = .localFile) throws -> ArchiveImportSummary {
    try LocalArchiveImport.apply(archive, settings: settings,
      results: context.fetch(FetchDescriptor<TestResultRecord>()),
      presets: context.fetch(FetchDescriptor<TestPresetRecord>()),
      savedTexts: context.fetch(FetchDescriptor<SavedCustomTextRecord>()),
      resultTombstoneStore: .init(defaults: defaults), presetTombstoneStore: .init(defaults: defaults),
      savedTextTombstoneStore: .init(defaults: defaults), customizationTombstoneStore: .init(defaults: defaults),
      resultFilterPresets: context.fetch(FetchDescriptor<ResultFilterPresetRecord>()),
      tombstoneStore: .init(defaults: defaults), source: source, modelContext: context)
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
        XCTAssertThrowsError(try apply(archive(), settings: settings, defaults: defaults, context: store.mainContext))
        XCTAssertEqual(settings.snapshot, snapshot)
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before as NSDictionary)
        // SwiftData may retain registered objects after a failed real save.
        // Verify persistence with a fresh container below, not this cache.
        XCTAssertFalse(store.mainContext.hasChanges)
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
