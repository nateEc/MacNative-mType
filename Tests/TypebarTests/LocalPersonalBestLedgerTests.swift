import Foundation
import SwiftData
import XCTest
@testable import Typebar

@MainActor
final class LocalPersonalBestLedgerTests: XCTestCase {
  private let admission = Date(timeIntervalSince1970: 500.1259)

  private func result(_ speed: Double = 60.25, configuration: TestConfiguration = .timed(seconds: 15),
    age: Double = 0, raw: Double = 70.5, accuracy: Double = 98.25,
    tags: [String] = ["focus"], outcome: TestOutcome = .completed) -> CompletedTestResult {
    let start = Date(timeIntervalSince1970: 100 + age)
    return .init(id: UUID(), configuration: configuration, outcome: outcome,
      startedAt: start, finishedAt: start.addingTimeInterval(20),
      typedCharacterCount: 100, correctCharacterCount: 99, errorCount: 1,
      wpm: speed.isFinite ? Int(speed.rounded()) : 0,
      rawWpm: raw.isFinite ? Int(raw.rounded()) : 0, accuracy: Int(accuracy.rounded()),
      preciseWpm: speed, preciseRawWpm: raw, preciseAccuracy: accuracy,
      tags: tags, prompt: "owned secret prompt")
  }

  private func container(_ url: URL? = nil, allowsSave: Bool = true) throws -> ModelContainer {
    let configuration = url.map { ModelConfiguration(url: $0, allowsSave: allowsSave, cloudKitDatabase: .none) }
      ?? ModelConfiguration(isStoredInMemoryOnly: true)
    let value = try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self,
      SavedCustomTextRecord.self, ResultFilterPresetRecord.self, LocalPersonalBestLedgerRecord.self,
      configurations: configuration)
    value.mainContext.autosaveEnabled = false
    return value
  }

  private func ledger(_ context: ModelContext) throws -> LocalPersonalBestLedger {
    try XCTUnwrap(context.fetch(FetchDescriptor<LocalPersonalBestLedgerRecord>()).first).decodedLedger()
  }

  func testDeletingHistoryAndColdReloadKeepPersonalAndTagSnapshots() throws {
    try withStore { url in
      let first = result(60.49), laterTie = result(60.49, age: -50, raw: 99.99, accuracy: 100)
      var saved: LocalPersonalBestLedger?
      try autoreleasepool {
        let store = try container(url)
        defer { withExtendedLifetime(store) {} }
        let context = store.mainContext
        try LocalPersonalBestStore.initialize(in: context)
        try LocalPersonalBestStore.save(first, in: context, acceptedAt: admission)
        try LocalPersonalBestStore.save(laterTie, in: context, acceptedAt: admission.addingTimeInterval(1))
        saved = try ledger(context)
        XCTAssertEqual(saved?.entries.first?.row.id, first.id)
        XCTAssertEqual(saved?.entries.first?.row.rawWpm, 70.5)
        XCTAssertEqual(saved?.entries.first?.row.accuracy, 98.25)
        XCTAssertEqual(saved?.entries.first?.recordedAt, Date(timeIntervalSince1970: 500.125))
        XCTAssertEqual(saved?.entries.first?.row.finishedAt, first.finishedAt)
        try context.delete(model: TestResultRecord.self); try context.save()
      }
      try autoreleasepool {
        let store = try container(url)
        defer { withExtendedLifetime(store) {} }
        let context = store.mainContext
        try LocalPersonalBestStore.initialize(in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TestResultRecord>()), 0)
        let current = try ledger(context)
        XCTAssertEqual(current, saved)
        XCTAssertEqual(ResultTagCommandCatalog.knownTags(active: [], historical: current.tagEntries.map(\.tag)), ["focus"])
        XCTAssertEqual(current.best(configuration: first.configuration)?.row.id, first.id)
        XCTAssertEqual(current.best(configuration: first.configuration, activeTags: ["FOCUS"])?.row.id, first.id)
        for mode in [PaceGuideMode.personalBest, .activeTagPersonalBest] {
          XCTAssertEqual(PaceGuidePolicy.targetWpm(mode: mode, customWpm: 100,
            configuration: first.configuration, samples: [], activeTags: ["focus"],
            personalBestLedger: current), 60.49)
        }
        let feedback = try XCTUnwrap(current.feedback(for: result(60.48)))
        XCTAssertFalse(feedback.isNewPersonalBest); XCTAssertEqual(feedback.previousBestWpm, 60.49)
        XCTAssertEqual(current.tagFeedback(for: result(60.48)).first?.previousBestWpm, 60.49)
      }
    }
  }

  func testKnownEmptyLedgerDoesNotFallBackToHistory() throws {
    let candidate = result(90)
    for mode in [PaceGuideMode.personalBest, .activeTagPersonalBest] {
      XCTAssertNil(PaceGuidePolicy.targetWpm(mode: mode, customWpm: 100,
        configuration: candidate.configuration, samples: [.init(result: candidate)],
        activeTags: ["focus"], personalBestLedger: .init()))
    }
    XCTAssertEqual(PaceGuidePolicy.targetWpm(mode: .average, customWpm: 100,
      configuration: candidate.configuration, samples: [.init(result: candidate)],
      personalBestLedger: .init()), 90)
  }

  func testFullGroupingFixedAndInfiniteMode2AndVisualModifierIdentity() throws {
    var book = LocalPersonalBestLedger()
    let base = TestConfiguration.timed(seconds: 15)
    var punctuation = base; punctuation.contentOptions.includePunctuation = true
    var numbers = base; numbers.contentOptions.includeNumbers = true
    var language = base; language.language = .spanish
    var difficulty = base; difficulty.difficulty = .expert
    let configurations = [base, punctuation, numbers, language, difficulty,
      base.with(modifiers: [.lazyLatin]), .timed(seconds: 0), .words(0), .words(25),
      .init(mode: .custom, duration: 15, wordLimit: 10, difficulty: .normal, rules: .init()),
      .init(mode: .zen, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init())]
    for configuration in configurations { try book.accept(result(configuration: configuration), at: admission) }
    XCTAssertEqual(book.entries.count, 11)
    try book.accept(result(61.25, configuration: base.with(modifiers: [.mirrorVisual])), at: admission)
    XCTAssertEqual(book.entries.count, 11)
    XCTAssertEqual(book.best(configuration: base)?.row.wpm, 61.25)
    for mode in [TestMode.custom, .zen] {
      let candidate = result(62.25, configuration: .init(mode: mode, duration: 60, wordLimit: 50,
        difficulty: .normal, rules: .init()))
      try book.accept(candidate, at: admission)
      XCTAssertEqual(book.best(configuration: candidate.configuration)?.row.id, candidate.id)
    }
    XCTAssertEqual(book.entries.count, 11); try book.validate()
  }

  func testIndependentTagsUpdateEvenWhenPersonalBestDoesNotImprove() throws {
    var book = LocalPersonalBestLedger()
    let personal = result(90, tags: ["other"]), tagged = result(60, tags: ["Fócus"])
    try book.accept(personal, at: admission); try book.accept(tagged, at: admission)
    XCTAssertEqual(book.entries.first?.row.id, personal.id)
    XCTAssertEqual(book.best(configuration: tagged.configuration, activeTags: ["focus"])?.row.id, tagged.id)
    XCTAssertEqual(book.best(configuration: tagged.configuration, activeTags: ["focus", "other"])?.row.wpm, 90)
    try book.accept(result(60, age: -50, accuracy: 100, tags: ["focus"]), at: admission)
    XCTAssertEqual(book.best(configuration: tagged.configuration, activeTags: ["focus"])?.row.id, tagged.id)
  }

  func testIneligibleRunsAndQuoteNeverCreatePBButBailoutCanBeSaved() throws {
    let store = try container()
    defer { withExtendedLifetime(store) {} }
    let context = store.mainContext
    try LocalPersonalBestStore.initialize(in: context)
    var stop = TestConfiguration.timed(seconds: 15); stop.rules.stopOnErrorMode = .letter
    let quote = TestConfiguration(mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init())
    for candidate in [result(outcome: .bailedOut), result(configuration: quote),
      result(configuration: .timed(seconds: 15).with(modifiers: [.noSpaces])), result(configuration: stop)] {
      try LocalPersonalBestStore.save(candidate, in: context)
    }
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<TestResultRecord>()), 4)
    XCTAssertTrue(try ledger(context).entries.isEmpty)
    XCTAssertTrue(try ledger(context).tagEntries.isEmpty)
  }

  func testFailedSaveRollsBackBothLedgerAndResultAndRetryAcceptsOnce() throws {
    enum Failure: Error { case denied }
    let store = try container()
    defer { withExtendedLifetime(store) {} }
    let context = store.mainContext
    try LocalPersonalBestStore.initialize(in: context)
    let baseline = result(60), candidate = result(61.25)
    try LocalPersonalBestStore.save(baseline, in: context)
    let before = try ledger(context)
    XCTAssertThrowsError(try LocalPersonalBestStore.save(candidate, in: context, save: { throw Failure.denied }))
    XCTAssertEqual(try ledger(context), before)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<TestResultRecord>()), 1)
    try LocalPersonalBestStore.save(candidate, in: context, acceptedAt: admission)
    let after = try ledger(context)
    try LocalPersonalBestStore.save(candidate, in: context, acceptedAt: admission.addingTimeInterval(99))
    XCTAssertEqual(try ledger(context), after)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<TestResultRecord>()), 2)
  }

  func testActualReadOnlyDiskFailureDoesNotPersistLedgerOrHistory() throws {
    try withStore { url in
      let first = result(60), candidate = result(70)
      var before: LocalPersonalBestLedger?
      try autoreleasepool {
        let store = try container(url)
        defer { withExtendedLifetime(store) {} }
        let context = store.mainContext
        try LocalPersonalBestStore.save(first, in: context, acceptedAt: admission)
        before = try ledger(context)
      }
      try autoreleasepool {
        let store = try container(url, allowsSave: false)
        defer { withExtendedLifetime(store) {} }
        let context = store.mainContext
        XCTAssertThrowsError(try LocalPersonalBestStore.save(candidate, in: context))
        XCTAssertEqual(try ledger(context), before)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TestResultRecord>()), 1)
      }
      try autoreleasepool {
        let store = try container(url)
        defer { withExtendedLifetime(store) {} }
        let context = store.mainContext
        XCTAssertEqual(try ledger(context), before)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TestResultRecord>()), 1)
      }
    }
  }

  func testLegacyBaselineIsFrozenOnceAndMissingConfigurationIsNotDefaulted() throws {
    let store = try container()
    defer { withExtendedLifetime(store) {} }
    let context = store.mainContext
    let first = result(60.25), unknown = TestResultRecord(result: result(99))
    var configuration = try XCTUnwrap(JSONSerialization.jsonObject(with: unknown.configurationData) as? [String: Any])
    configuration.removeValue(forKey: "language")
    unknown.configurationData = try JSONSerialization.data(withJSONObject: configuration)
    context.insert(TestResultRecord(result: first)); context.insert(unknown); try context.save()
    try LocalPersonalBestStore.initialize(in: context)
    let book = try ledger(context)
    XCTAssertFalse(book.historyComplete); XCTAssertEqual(book.entries.count, 1)
    XCTAssertEqual(book.entries.first?.row.id, first.id)
    XCTAssertEqual(book.entries.first?.origin, .legacyHistory); XCTAssertNil(book.entries.first?.recordedAt)
    try context.delete(model: TestResultRecord.self); try context.save()
    try LocalPersonalBestStore.initialize(in: context)
    XCTAssertEqual(try ledger(context), book)
  }

  func testChangingHistoryTagsDoesNotReawardOrRemoveAcceptedTagPB() throws {
    let store = try container()
    defer { withExtendedLifetime(store) {} }
    let context = store.mainContext
    let candidate = result()
    let record = try LocalPersonalBestStore.save(candidate, in: context)
    let before = try ledger(context)
    record.tags = ["later"]; try context.save()
    XCTAssertEqual(try ledger(context), before)
    XCTAssertNotNil(before.best(configuration: candidate.configuration, activeTags: ["focus"]))
    XCTAssertNil(before.best(configuration: candidate.configuration, activeTags: ["later"]))
  }

  func testCorruptLedgerRefusesSavingAndDoesNotOverwriteItsBytes() throws {
    for bytes in [Data("broken".utf8), Data("{\"version\":2,\"historyComplete\":true,\"entries\":[],\"tagEntries\":[]}".utf8)] {
      let store = try container()
      defer { withExtendedLifetime(store) {} }
      let context = store.mainContext
      let record = try LocalPersonalBestLedgerRecord(ledger: .init())
      record.ledgerData = bytes; context.insert(record); try context.save()
      XCTAssertThrowsError(try LocalPersonalBestStore.initialize(in: context))
      XCTAssertThrowsError(try LocalPersonalBestStore.save(result(), in: context))
      XCTAssertEqual(record.ledgerData, bytes)
      XCTAssertEqual(try context.fetchCount(FetchDescriptor<TestResultRecord>()), 0)
    }
  }

  func testDuplicateGroupsInvalidCompanionsAndInventedLegacyClockAreRejected() throws {
    var book = LocalPersonalBestLedger(); try book.accept(result(), at: admission)
    var duplicate = book; duplicate.entries.append(try XCTUnwrap(book.entries.first))
    XCTAssertThrowsError(try duplicate.validate())
    var tags = book; tags.tagEntries.append(try XCTUnwrap(book.tagEntries.first))
    XCTAssertThrowsError(try tags.validate())
    let first = try XCTUnwrap(book.entries.first)
    book.entries = [.init(row: first.row, recordedAt: admission, origin: .legacyHistory)]
    XCTAssertThrowsError(try book.validate())
    var clean = duplicate; clean.entries = [first]
    let record = try LocalPersonalBestLedgerRecord(ledger: clean)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: record.ledgerData) as? [String: Any])
    var entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
    var row = try XCTUnwrap(entries[0]["row"] as? [String: Any])
    row["rawWpm"] = -1; entries[0]["row"] = row; object["entries"] = entries
    record.ledgerData = try JSONSerialization.data(withJSONObject: object)
    XCTAssertThrowsError(try record.decodedLedger())
  }

  func testSnapshotDoesNotRetainPromptOrReplayAndEmptyFreshStoreIsComplete() throws {
    let store = try container()
    defer { withExtendedLifetime(store) {} }
    let context = store.mainContext
    try LocalPersonalBestStore.initialize(in: context)
    XCTAssertTrue(try ledger(context).historyComplete)
    try LocalPersonalBestStore.save(result(), in: context)
    let record = try XCTUnwrap(context.fetch(FetchDescriptor<LocalPersonalBestLedgerRecord>()).first)
    let json = String(decoding: record.ledgerData, as: UTF8.self)
    XCTAssertFalse(json.contains("owned secret prompt")); XCTAssertFalse(json.contains("replay"))
    XCTAssertFalse(json.contains("typedCharacterCount"))
  }

  func testRealArchiveImportAndCloudDeletionPreserveIndependentPB() throws {
    let store = try container()
    defer { withExtendedLifetime(store) {} }
    let context = store.mainContext
    let suite = "TypebarTests.local-pb-import.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    let candidate = result(65.25)
    let archive = TypebarArchive(exportedAt: admission, settings: settings.snapshot,
      results: [candidate], presets: [], savedTexts: [])
    let tombstones = ResultTombstoneStore(defaults: defaults)
    let summary = try LocalArchiveImport.apply(archive, settings: settings, results: [],
      presets: [], savedTexts: [], resultTombstoneStore: tombstones, modelContext: context)
    XCTAssertEqual(summary.insertedResults, 1)
    let before = try ledger(context)
    XCTAssertFalse(before.historyComplete)
    XCTAssertEqual(before.entries.first?.origin, .importedHistory)
    XCTAssertNil(before.entries.first?.recordedAt)
    let deletion = TypebarArchive(exportedAt: admission, settings: settings.snapshot,
      results: [], deletedResultIDs: [candidate.id], presets: [], savedTexts: [])
    let records = try context.fetch(FetchDescriptor<TestResultRecord>())
    let removed = try LocalArchiveImport.apply(deletion, settings: settings, results: records,
      presets: [], savedTexts: [], resultTombstoneStore: tombstones, source: .cloudSync, modelContext: context)
    XCTAssertEqual(removed.deletedResults, 1)
    XCTAssertEqual(try ledger(context), before)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<TestResultRecord>()), 0)
  }

  func testAccountResetCreatesKnownEmptyLedgerInsteadOfRebuildingOldHistory() throws {
    let store = try container()
    defer { withExtendedLifetime(store) {} }
    let context = store.mainContext
    let suite = "TypebarTests.local-pb-reset.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try LocalPersonalBestStore.save(result(), in: context)
    try LocalAccountReset.eraseCurrentMacData(modelContext: context, settings: AppSettings(defaults: defaults),
      removeBackground: {}, removePracticeFont: {}, clearPendingPublications: {})
    XCTAssertEqual(try ledger(context), .init())
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<TestResultRecord>()), 0)
    try LocalPersonalBestStore.initialize(in: context)
    XCTAssertEqual(try ledger(context), .init())
  }

  func testExistingEmptyLegacyStoreDoesNotClaimDeletedHistoryWasRecovered() throws {
    let store = try container()
    defer { withExtendedLifetime(store) {} }
    let context = store.mainContext
    try LocalPersonalBestStore.initialize(in: context, legacyStorePresent: true)
    XCTAssertFalse(try ledger(context).historyComplete)
    XCTAssertTrue(try ledger(context).entries.isEmpty)
  }

  func testFirstSaveFailureDoesNotLeaveAnEmptyOrAwardedLedger() throws {
    enum Failure: Error { case denied }
    let store = try container(); defer { withExtendedLifetime(store) {} }
    let context = store.mainContext
    XCTAssertThrowsError(try LocalPersonalBestStore.save(result(), in: context, save: { throw Failure.denied }))
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<TestResultRecord>()), 0)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<LocalPersonalBestLedgerRecord>()), 0)
    try LocalPersonalBestStore.save(result(), in: context)
    XCTAssertEqual(try ledger(context).entries.count, 1)
  }

  func testActualReadOnlyImportFailureRestoresLedgerAndKeepsDiskUnchanged() throws {
    try withStore { url in
      var before: LocalPersonalBestLedger?
      try autoreleasepool {
        let store = try container(url); defer { withExtendedLifetime(store) {} }
        try LocalPersonalBestStore.save(result(60), in: store.mainContext)
        before = try ledger(store.mainContext)
      }
      try autoreleasepool {
        let store = try container(url, allowsSave: false); defer { withExtendedLifetime(store) {} }
        let context = store.mainContext
        let suite = "TypebarTests.local-pb-failed-import.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let archive = TypebarArchive(exportedAt: admission, settings: settings.snapshot,
          results: [result(90)], presets: [], savedTexts: [])
        XCTAssertThrowsError(try LocalArchiveImport.apply(archive, settings: settings,
          results: context.fetch(FetchDescriptor<TestResultRecord>()), presets: [], savedTexts: [], modelContext: context))
        XCTAssertEqual(try ledger(context), before)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TestResultRecord>()), 1)
      }
      try autoreleasepool {
        let store = try container(url); defer { withExtendedLifetime(store) {} }
        XCTAssertEqual(try ledger(store.mainContext), before)
      }
    }
  }

  func testResetCommitFailureDoesNotPersistBatchDeletionBeforeCommit() throws {
    enum Failure: Error { case denied }
    try withStore { url in
      var before: LocalPersonalBestLedger?
      try autoreleasepool {
        let store = try container(url); defer { withExtendedLifetime(store) {} }
        let context = store.mainContext
        try LocalPersonalBestStore.save(result(), in: context)
        before = try ledger(context)
        let suite = "TypebarTests.local-pb-reset-commit.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertThrowsError(try LocalAccountReset.eraseCurrentMacData(modelContext: context, settings: settings,
          removeBackground: {}, removePracticeFont: {}, clearPendingPublications: {}, save: { throw Failure.denied }))
        XCTAssertEqual(try ledger(context), before)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TestResultRecord>()), 1)
      }
      try autoreleasepool {
        let store = try container(url); defer { withExtendedLifetime(store) {} }
        XCTAssertEqual(try ledger(store.mainContext), before)
        XCTAssertEqual(try store.mainContext.fetchCount(FetchDescriptor<TestResultRecord>()), 1)
      }
    }
  }

  private func withStore(_ body: (URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-local-pb-tests-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(root.appendingPathComponent("store.sqlite"))
  }

  func testActualReadOnlyResetFailurePreservesLedgerAndHistory() throws {
    try withStore { url in
      var before: LocalPersonalBestLedger?
      try autoreleasepool {
        let store = try container(url); defer { withExtendedLifetime(store) {} }
        try LocalPersonalBestStore.save(result(), in: store.mainContext)
        before = try ledger(store.mainContext)
      }
      try autoreleasepool {
        let store = try container(url, allowsSave: false); defer { withExtendedLifetime(store) {} }
        let context = store.mainContext
        let suite = "TypebarTests.local-pb-failed-reset.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.showPersonalBest = false
        XCTAssertThrowsError(try LocalAccountReset.eraseCurrentMacData(modelContext: context, settings: settings,
          removeBackground: {}, removePracticeFont: {}, clearPendingPublications: {}))
        XCTAssertEqual(try ledger(context), before)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TestResultRecord>()), 1)
        XCTAssertFalse(settings.showPersonalBest)
      }
      try autoreleasepool {
        let store = try container(url); defer { withExtendedLifetime(store) {} }
        XCTAssertEqual(try ledger(store.mainContext), before)
        XCTAssertEqual(try store.mainContext.fetchCount(FetchDescriptor<TestResultRecord>()), 1)
      }
    }
  }
}
