import SwiftData
import XCTest
@testable import Typebar

@MainActor final class ArchiveSourceAdoptionTests: XCTestCase {
  private func archive(_ mode: PracticeThresholdConfiguration.Mode = .off,
    _ burstMode: MinimumWordBurstMode = .off, infinite: Bool = false) throws -> TypebarArchive {
    let owner = PracticeThresholdSource(configuration: try .init(websiteMinimumWpmMode: mode,
      speed: infinite ? .infinity : 37, accuracyMode: .off, accuracy: 93,
      burstMode: burstMode, burst: infinite ? .infinity : 84))
    let snapshot = owner.applying(to: AppSettingsSnapshot(fontSize: 42))
    let configuration = TestConfiguration.words(3, rules: owner.applying(to: .init()))
    let preset = SavedTestPreset(configuration: configuration, activeResultTags: ["owned"], settingsSnapshot: snapshot)
    let selection = ActiveTestSelectionDocument(preset: .init(configuration: configuration),
      testParameterMemory: .init(duration: 30, wordLimit: 3, customTextDuration: 30,
        customTextWordLimit: 25, customTextSectionLimit: 1))
    return try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(settings: snapshot,
      results: [], presets: [.init(id: UUID(), name: "Owned", definition: preset)], activeTestSelection: selection))
  }

  private func settings(_ defaults: UserDefaults) -> AppSettings {
    .init(defaults: defaults, feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}),
      localBackgroundStore: .inMemory())
  }

  private func container(_ url: URL? = nil, allowsSave: Bool = true) throws -> ModelContainer {
    let configuration = url.map { ModelConfiguration(url: $0, allowsSave: allowsSave, cloudKitDatabase: .none) }
      ?? ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self, SavedCustomTextRecord.self,
      ResultFilterPresetRecord.self, LocalPersonalBestLedgerRecord.self,
      configurations: configuration)
    container.mainContext.autosaveEnabled = false
    return container
  }

  private func apply(_ archive: TypebarArchive, to settings: AppSettings, defaults: UserDefaults,
    container: ModelContainer, source: ArchiveImportSource = .localFile,
    resources: @escaping @MainActor (TestConfiguration) -> Bool = ArchiveSourceAdmission.resourcesAvailable) throws -> ArchiveImportSummary {
    try LocalArchiveImport.apply(archive, settings: settings,
      results: container.mainContext.fetch(FetchDescriptor<TestResultRecord>()),
      presets: container.mainContext.fetch(FetchDescriptor<TestPresetRecord>()), savedTexts: [],
      resultTombstoneStore: .init(defaults: defaults), presetTombstoneStore: .init(defaults: defaults),
      savedTextTombstoneStore: .init(defaults: defaults), customizationTombstoneStore: .init(defaults: defaults),
      tombstoneStore: .init(defaults: defaults), source: source, selectionResourcesAvailable: resources,
      modelContext: container.mainContext)
  }

  func testFreshInstallRestoresSourceSettingsPresetAndCurrentSelection() throws {
    let suite = "typebar.archive-adoption-fresh.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let target = settings(defaults), incoming = try archive(infinite: true), store = try container()
    XCTAssertFalse(target.hasThresholdProfile)
    var summary: ArchiveImportSummary?
    XCTAssertNoThrow(summary = try apply(incoming, to: target, defaults: defaults, container: store))
    guard let summary else { return }
    XCTAssertEqual(summary.insertedPresets, 1)
    XCTAssertTrue(summary.restoredActiveTestSelection)
    XCTAssertEqual(target.snapshot, incoming.settings)
    XCTAssertEqual(target.activeTestSelection, incoming.activeTestSelection)
    let reader = settings(defaults)
    XCTAssertEqual(reader.snapshot, incoming.settings)
    XCTAssertEqual(reader.activeTestSelection, incoming.activeTestSelection)
    var session = TestSessionFactory.make(configuration: try XCTUnwrap(reader.activeTestSelection).preset.configuration)
    session.insertBatch(session.prompt, at: .now)
    XCTAssertEqual(session.outcome, .completed)
  }

  func testFiniteAndInfiniteModesUpgradeExplicitlyWithoutRewritingLegacyKeys() throws {
    for mode: PracticeThresholdConfiguration.Mode in [.off, .custom] {
      for burst: MinimumWordBurstMode in [.off, .fixed, .flex] {
        for infinite in [false, true] {
          let suite = "typebar.archive-adoption-modes.\(UUID())"
          let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
          defer { defaults.removePersistentDomain(forName: suite) }
          var legacy: [String: Data] = [:]
          for (index, key) in [AppSettings.legacyStorageKey, AppSettings.expandedPaceStorageKey,
            AppSettings.accountPaceStorageKey].enumerated() {
            let bytes = try JSONEncoder().encode(AppSettingsSnapshot(fontSize: Double(21 + index)))
            defaults.set(bytes, forKey: key); legacy[key] = bytes
          }
          let oldSelection = ActiveTestSelectionDocument(preset: .init(configuration: .words(25)), testParameterMemory: .defaults)
          XCTAssertTrue(ActiveTestSelectionStore(defaults: defaults).save(oldSelection))
          let selectionBytes = defaults.data(forKey: ActiveTestSelectionStore.storageKey)
          let target = settings(defaults), store = try container(), incoming = try archive(mode, burst, infinite: infinite)
          var summary: ArchiveImportSummary?
          XCTAssertNoThrow(summary = try apply(incoming, to: target, defaults: defaults, container: store))
          guard let summary else { continue }
          XCTAssertEqual(summary.insertedPresets, 1)
          XCTAssertTrue(summary.restoredActiveTestSelection)
          XCTAssertEqual(target.snapshot, incoming.settings)
          let reader = settings(defaults)
          XCTAssertEqual(reader.snapshot, incoming.settings)
          XCTAssertEqual(reader.activeTestSelection, incoming.activeTestSelection)
          for (key, bytes) in legacy { XCTAssertEqual(defaults.data(forKey: key), bytes) }
          XCTAssertEqual(defaults.data(forKey: ActiveTestSelectionStore.storageKey), selectionBytes)
          let generation = reader.activeTestSelectionGeneration
          let repeated = try apply(incoming, to: reader, defaults: defaults, container: store, source: .cloudSync)
          XCTAssertEqual(repeated.insertedPresets, 0)
          XCTAssertFalse(repeated.restoredActiveTestSelection)
          XCTAssertEqual(reader.activeTestSelectionGeneration, generation)
        }
      }
    }
  }

  func testUnreadablePreferencesAndSelectionRefuseAdoptionBeforeRecords() throws {
    for (key, bytes) in [(AppSettings.legacyStorageKey, Data("{".utf8)),
      (ThresholdSettingsStore.storageKey, Data(#"{"version":999}"#.utf8)),
      (ActiveTestSelectionStore.sourceStorageKey, Data("{".utf8))] {
      let suite = "typebar.archive-adoption-unreadable.\(UUID())"
      let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      defer { defaults.removePersistentDomain(forName: suite) }
      defaults.set(bytes, forKey: key)
      let target = settings(defaults), before = target.snapshot, store = try container()
      XCTAssertThrowsError(try apply(archive(), to: target, defaults: defaults, container: store)) {
        XCTAssertEqual($0 as? LocalArchiveImportError, .sourceStateUnavailable)
      }
      XCTAssertEqual(target.snapshot, before)
      XCTAssertEqual(defaults.data(forKey: key), bytes)
      XCTAssertEqual(try store.mainContext.fetchCount(FetchDescriptor<TestPresetRecord>()), 0)
    }
  }

  func testInvalidIncomingSettingsAndNoQuitCannotStartAnAdoption() throws {
    let suite = "typebar.archive-adoption-invalid.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let target = settings(defaults), before = target.snapshot, store = try container(), original = try archive()
    var invalid = original.settings; invalid.minimumWpm = 99
    let incoming = TypebarArchive(exportedAt: original.exportedAt, settings: invalid, results: [], presets: original.presets)
    XCTAssertThrowsError(try apply(incoming, to: target, defaults: defaults, container: store)) {
      XCTAssertEqual($0 as? LocalArchiveImportError, .invalidSourceSettings)
    }
    let lock = UUID(); target.setNoQuitConfigurationLock(true, for: lock)
    defer { target.setNoQuitConfigurationLock(false, for: lock) }
    XCTAssertThrowsError(try apply(original, to: target, defaults: defaults, container: store)) {
      XCTAssertEqual($0 as? LocalArchiveImportError, .noQuitConfigurationLocked)
    }
    XCTAssertEqual(target.snapshot, before)
    XCTAssertFalse(target.hasThresholdProfile)
    XCTAssertEqual(try store.mainContext.fetchCount(FetchDescriptor<TestPresetRecord>()), 0)
  }

  func testPreparedAdoptionRejectsChangedWarmPersistedSourceAndSelectionState() throws {
    for change in ["warm", "legacy", "source", "selection"] {
      let suite = "typebar.archive-adoption-stale.\(UUID())"
      let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      defer { defaults.removePersistentDomain(forName: suite) }
      let target = settings(defaults), incoming = try archive()
      let plan = try ArchiveSourceAdmission.preparing(incoming.settings, selection: incoming.activeTestSelection, to: target)
      switch change {
      case "warm": target.fontSize = 24
      case "legacy": defaults.set(try JSONEncoder().encode(AppSettingsSnapshot(fontSize: 22)), forKey: AppSettings.expandedPaceStorageKey)
      case "source": XCTAssertTrue(ThresholdSettingsStore(defaults: defaults).save(incoming.settings))
      default: XCTAssertTrue(target.saveActiveTestSelection(.init(preset: .init(configuration: .words(25)), testParameterMemory: .defaults)))
      }
      let current = target.snapshot, profile = target.thresholdProfileRead, selection = target.activeTestSelectionRead
      XCTAssertThrowsError(try plan.validateBeforeRecords(to: target)) {
        XCTAssertEqual($0 as? LocalArchiveImportError, .sourceStateUnavailable)
      }
      XCTAssertThrowsError(try plan.applyAfterRecords(to: target)) {
        XCTAssertEqual($0 as? LocalArchiveImportError, .recordsImportedSettingsNotApplied)
      }
      XCTAssertEqual(target.snapshot, current)
      XCTAssertEqual(target.thresholdProfileRead, profile)
      XCTAssertEqual(target.activeTestSelectionRead, selection)
    }
  }

  func testFailedProfileWriteReportsCommittedRecordsWithoutPublishingSourceOrSelection() throws {
    let suite = "typebar.archive-adoption-write-failure.\(UUID())"
    let defaults = try XCTUnwrap(DroppingProfileDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let legacy = try JSONEncoder().encode(AppSettingsSnapshot(fontSize: 23))
    defaults.set(legacy, forKey: AppSettings.legacyStorageKey)
    let target = settings(defaults), before = target.snapshot, store = try container()
    XCTAssertThrowsError(try apply(archive(infinite: true), to: target, defaults: defaults, container: store)) {
      XCTAssertEqual($0 as? LocalArchiveImportError, .recordsImportedSettingsNotApplied)
    }
    XCTAssertEqual(try store.mainContext.fetchCount(FetchDescriptor<TestPresetRecord>()), 1)
    XCTAssertEqual(target.snapshot, before)
    XCTAssertFalse(target.hasThresholdProfile)
    XCTAssertEqual(target.thresholdProfileRead, .missing)
    XCTAssertEqual(target.activeTestSelectionRead, .missing)
    XCTAssertEqual(defaults.data(forKey: AppSettings.legacyStorageKey), legacy)
  }

  func testActualReadOnlyDatabaseFailureDoesNotAdoptPreferences() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-adoption-readonly.\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("history.store")
    try autoreleasepool { let store = try container(url); try store.mainContext.save() }
    let suite = "typebar.archive-adoption-readonly.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let target = settings(defaults), before = target.snapshot
    try autoreleasepool {
      let store = try container(url, allowsSave: false)
      XCTAssertThrowsError(try apply(archive(), to: target, defaults: defaults, container: store)) {
        XCTAssertTrue($0 is ArchivePersistenceFailure)
      }
      XCTAssertEqual(target.snapshot, before)
      XCTAssertFalse(target.hasThresholdProfile)
      XCTAssertEqual(target.activeTestSelectionRead, .missing)
    }
    let reader = try container(url)
    XCTAssertEqual(try reader.mainContext.fetchCount(FetchDescriptor<TestPresetRecord>()), 0)
  }

  func testChallengeResourcesAreRecheckedBeforeRecordsAndAfterAdoption() throws {
    for unavailableAt in [1, 2, 3] {
      let suite = "typebar.archive-adoption-resources.\(UUID())"
      let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      defer { defaults.removePersistentDomain(forName: suite) }
      let target = settings(defaults), before = target.snapshot, store = try container(), original = try archive()
      let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "clean-twenty-five"))
      var configuration = challenge.preset.configuration.with(challengeID: challenge.id)
      configuration.rules = try XCTUnwrap(original.settings.thresholdSource).applying(to: configuration.rules)
      let preset = SavedTestPreset(configuration: configuration, customText: challenge.preset.customText)
      XCTAssertTrue(SourceChallengeAdmission.accepts(preset))
      let selection = ActiveTestSelectionDocument(preset: preset, testParameterMemory: .defaults)
      let incoming = TypebarArchive(exportedAt: original.exportedAt, settings: original.settings,
        results: [], presets: original.presets, activeTestSelection: selection)
      var calls = 0
      XCTAssertThrowsError(try apply(incoming, to: target, defaults: defaults, container: store, resources: { _ in
        calls += 1; return calls != unavailableAt
      })) {
        XCTAssertEqual($0 as? LocalArchiveImportError, unavailableAt == 3
          ? .recordsAndSettingsImportedSelectionNotApplied : .activeTestSelectionResourcesUnavailable)
      }
      XCTAssertEqual(try store.mainContext.fetchCount(FetchDescriptor<TestPresetRecord>()), unavailableAt == 3 ? 1 : 0)
      XCTAssertEqual(target.snapshot, unavailableAt == 3 ? original.settings : before)
      XCTAssertEqual(target.activeTestSelectionRead, .missing)
    }
  }
}

private final class DroppingProfileDefaults: UserDefaults, @unchecked Sendable {
  override func set(_ value: Any?, forKey key: String) {
    guard key != ThresholdSettingsStore.storageKey else { return }
    super.set(value, forKey: key)
  }
}
