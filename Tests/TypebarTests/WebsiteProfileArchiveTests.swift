import SwiftData
import XCTest
@testable import Typebar

@MainActor final class WebsiteProfileArchiveTests: XCTestCase {
  private enum Interrupted: Error { case stop }
  private func custom(_ count: Double, text: [WebsiteConfigValue] = [.string("aa"), .string("bb")]) throws -> WebsiteCustomTextSettings {
    try .init(value: .object(["text": .array(text), "mode": .string("repeat"),
      "limit": .object(["mode": .string("word"), "value": .number(count)]), "pipeDelimiter": .bool(false)]))
  }
  @MainActor private final class Target {
    let suite = "typebar.profile-archive-target.\(UUID())"
    let support = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-profile-archive-target.\(UUID())")
    let defaults: UserDefaults, settings: AppSettings, container: ModelContainer
    init(readOnly: Bool = false, rejectText: Bool = false) throws {
      try FileManager.default.createDirectory(at: support, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
      defaults = try XCTUnwrap(rejectText ? RejectingTextDefaults(suiteName: suite) : UserDefaults(suiteName: suite))
      settings = .init(defaults: defaults, feedbackSound: .init(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
      let database = support.appendingPathComponent("history.store")
      func open(_ writable: Bool) throws -> ModelContainer {
        try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self, SavedCustomTextRecord.self,
          ResultFilterPresetRecord.self, LocalPersonalBestLedgerRecord.self,
          configurations: ModelConfiguration(url: database, allowsSave: writable, cloudKitDatabase: .none))
      }
      if readOnly { try autoreleasepool { let first = try open(true); try first.mainContext.save() } }
      container = try open(!readOnly)
      container.mainContext.autosaveEnabled = false
    }
    func close() { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: support) }
    func apply(_ archive: TypebarArchive, settings target: AppSettings? = nil) throws -> ArchiveImportSummary {
      try LocalArchiveImport.apply(archive, settings: target ?? settings,
        results: container.mainContext.fetch(FetchDescriptor<TestResultRecord>()),
        presets: container.mainContext.fetch(FetchDescriptor<TestPresetRecord>()), savedTexts: [],
        resultTombstoneStore: .init(defaults: defaults), presetTombstoneStore: .init(defaults: defaults),
        savedTextTombstoneStore: .init(defaults: defaults), customizationTombstoneStore: .init(defaults: defaults),
        tombstoneStore: .init(defaults: defaults), websiteProfileApplicationSupport: support, modelContext: container.mainContext)
    }
  }
  private func profile() throws -> WebsiteProfileArchive {
    let fallback = CustomTextStateDocument(source: .editor("owned fallback e\u{301}"),
      configuration: .init(mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()))
    return try .init(runtime: WebsiteConfigNativeProfile.prepare(#"{"mode":"custom","words":17,"time":42}"#, context: .init()).projection.runtime,
      lazyMemory: .init(remember: true, prefersArabic: false),
      customTextData: XCTUnwrap(WebsiteCustomTextStateStore.encodeDocument(custom(3.5))),
      fallbackCustomTextData: JSONEncoder().encode(fallback))
  }
  private func archive(_ profile: WebsiteProfileArchive) throws -> TypebarArchive {
    try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(settings: .init(fontSize: 31), results: [],
      presets: [.init(id: UUID(), name: "owned", definition: .init(configuration: .words(3)))], websiteProfile: profile))
  }
  func testCompleteSavedProfileHasAnExplicitArchiveCarrier() throws {
    let runtime = try WebsiteConfigNativeProfile.defaultDocument().values
    let payload: [String: Any] = ["kind": "typebar.archive.website-profile", "version": 1,
      "runtimeData": try WebsiteConfigNativeStateCodec.encode(runtime).base64EncodedString(),
      "lazyRemember": true, "lazyPrefersArabic": false]
    let data = try TypebarDataTransfer.exportArchive(settings: .init(), results: [], presets: [])
    var root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    root["version"] = 38
    root["websiteProfileData"] = try JSONSerialization.data(withJSONObject: payload).base64EncodedString()
    XCTAssertNoThrow(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: root)))
  }

  func testAllSavedProfileValuesLazyMemoryAndIndependentTextSurviveDocumentReexport() throws {
    var runtime = try WebsiteConfigNativeProfile.defaultDocument().values
    let units = Array("https://owned.invalid/".utf16) + [UInt16(0xd800)] + Array(".png".utf16)
    runtime["customBackground"] = .string(units: units)
    runtime["customBackgroundFilter"] = .array([.number(-0.0), .number(.infinity), .number(-.infinity), .number(1)])
    runtime["minWpmCustomSpeed"] = .number(.infinity)
    let text = try custom(.infinity, text: [.string(units: [0xd800]), .string("e\u{301}"), .string("😀")])
    let profile = try WebsiteProfileArchive(runtime: runtime, lazyMemory: .init(remember: true, prefersArabic: false),
      customTextData: XCTUnwrap(WebsiteCustomTextStateStore.encodeDocument(text)))
    let bytes = try TypebarDataTransfer.exportArchive(settings: .init(), results: [], presets: [], websiteProfile: profile)
    let decoded = try TypebarDataTransfer.importArchive(from: bytes)
    XCTAssertEqual(decoded.websiteProfile, profile)
    XCTAssertEqual(decoded.websiteProfile?.runtime["customBackground"]?.stringUnits, units)
    let copied = try TypebarDataTransfer.importArchive(from: TypebarArchiveDocument(archive: decoded).archiveData())
    XCTAssertEqual(copied.websiteProfile, profile)
    let restoredText = try XCTUnwrap(WebsiteCustomTextStateStore.decodeDocument(XCTUnwrap(copied.websiteProfile?.customTextData)))
    XCTAssertEqual(restoredText.value, text.value)
    XCTAssertEqual(restoredText.limitValue.bitPattern, Double.infinity.bitPattern)
    XCTAssertThrowsError(try JSONEncoder().encode(TypebarArchive(version: 37, exportedAt: .now,
      settings: .init(), results: [], presets: [], websiteProfile: profile)))
  }

  func testEveryInterruptedJournalStageBlocksOrdinaryReadersAndRecoversIdempotently() throws {
    for stage in WebsiteConfigFileRegister.ArchiveStage.allCases {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-profile-restore.\(UUID())")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
      defer { try? FileManager.default.removeItem(at: directory) }
      let suite = "typebar.profile-restore.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      defer { defaults.removePersistentDomain(forName: suite) }
      let store = WebsiteCustomTextStateStore(defaults: defaults), register = WebsiteConfigFileRegister(directory: directory)
      let before = try WebsiteConfigNativeProfile.defaultDocument().values
      let initial = try XCTUnwrap(register.read().revision)
      guard case .committed(let oldRevision) = try register.commit(runtime: before, lazyMemory: .init(), replacing: initial)
      else { return XCTFail("Initial commit failed") }
      XCTAssertTrue(store.save(try custom(2)))
      var after = before; after["words"] = .number(17)
      let text = try custom(3.5)
      let profile = try WebsiteProfileArchive(runtime: after, lazyMemory: .init(remember: true, prefersArabic: false),
        customTextData: XCTUnwrap(WebsiteCustomTextStateStore.encodeDocument(text)))
      let plan = try register.prepareArchiveRestore(profile, customStore: store)
      XCTAssertThrowsError(try register.restoreArchive(plan, customStore: store, checkpoint: {
        if $0 == stage { throw Interrupted.stop }
      }))
      XCTAssertEqual(try register.read().state, .unavailable)
      if stage == .customWritten {
        let record = try WebsiteConfigJSONReader.read(String(decoding: Data(contentsOf: directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename)), as: UTF8.self))
        guard case .array(let fields) = record else { return XCTFail("Missing compatibility barrier") }
        XCTAssertEqual(fields.first, .string("typebar.website-profile-restore-pending"))
      }
      XCTAssertEqual(try register.commit(runtime: before, lazyMemory: .init(), replacing: oldRevision), .unavailable)
      XCTAssertTrue(try register.recoverArchiveRestore(customStore: store))
      let read = try register.read()
      XCTAssertEqual(read.state, .available(after))
      XCTAssertEqual(read.lazyMemory, profile.lazyMemory)
      XCTAssertEqual(store.read(), .available(text))
      let bytes = try Data(contentsOf: directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename))
      XCTAssertFalse(try register.recoverArchiveRestore(customStore: store))
      XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename)), bytes)
      XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(WebsiteConfigFileRegister.archiveJournalFilename).path))
    }
  }

  func testJournalDoesNotOverwriteForeignTextAndCanContinueAfterConflictResolution() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-profile-conflict.\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: directory) }
    let suite = "typebar.profile-conflict.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = WebsiteCustomTextStateStore(defaults: defaults), register = WebsiteConfigFileRegister(directory: directory)
    XCTAssertTrue(store.save(try custom(2)))
    let original = try store.recordForArchive()
    let profile = try WebsiteProfileArchive(runtime: WebsiteConfigNativeProfile.defaultDocument().values,
      lazyMemory: .init(), customTextData: XCTUnwrap(WebsiteCustomTextStateStore.encodeDocument(custom(17))))
    let plan = try register.prepareArchiveRestore(profile, customStore: store)
    XCTAssertThrowsError(try register.restoreArchive(plan, customStore: store, checkpoint: {
      if $0 == .journalWritten { throw Interrupted.stop }
    }))
    XCTAssertTrue(store.save(try custom(31)))
    let foreign = try store.recordForArchive()
    XCTAssertThrowsError(try register.recoverArchiveRestore(customStore: store))
    XCTAssertEqual(try store.recordForArchive(), foreign)
    XCTAssertEqual(try register.read().state, .unavailable)
    XCTAssertTrue(store.restoreArchiveDocument(original, replacing: foreign))
    XCTAssertTrue(try register.recoverArchiveRestore(customStore: store))
    XCTAssertEqual(try store.recordForArchive(), profile.customTextData)
  }

  func testActualFileImportReopensBothTextStoresAndIsIdempotent() throws {
    let target = try Target(); defer { target.close() }
    let expected = try profile(), incoming = try archive(expected)
    let file = target.support.appendingPathComponent("backup.json")
    try TypebarArchiveDocument(archive: incoming).archiveData().write(to: file, options: .atomic)
    let summary = try target.apply(TypebarDataTransfer.importArchive(from: Data(contentsOf: file)))
    XCTAssertTrue(summary.restoredWebsiteProfile)
    XCTAssertEqual(summary.insertedPresets, 1)
    XCTAssertEqual(target.settings.websiteProfileArchiveGeneration, 1)
    let reader = AppSettings(defaults: try XCTUnwrap(UserDefaults(suiteName: target.suite)),
      feedbackSound: .init(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
    XCTAssertEqual(try WebsiteProfileArchiveTarget.captureSaved(settings: reader, applicationSupport: target.support), expected)
    XCTAssertEqual(try reader.websiteCustomArchiveStore.fallbackRecordForArchive(), expected.fallbackCustomTextData)
    let directory = try XCTUnwrap(WebsiteConfigStorageDirectory.existing(applicationSupport: target.support))
    let register = WebsiteConfigFileRegister(directory: directory), before = try register.read().revision
    let generation = target.settings.websiteProfileArchiveGeneration
    let again = try target.apply(incoming)
    XCTAssertEqual(again.insertedPresets, 0)
    XCTAssertFalse(again.restoredWebsiteProfile)
    XCTAssertEqual(target.settings.websiteProfileArchiveGeneration, generation)
    XCTAssertEqual(try register.read().revision, before)
    let reopened = try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self, SavedCustomTextRecord.self,
      ResultFilterPresetRecord.self, LocalPersonalBestLedgerRecord.self,
      configurations: ModelConfiguration(url: target.support.appendingPathComponent("history.store"), cloudKitDatabase: .none))
    XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<TestPresetRecord>()), 1)
  }

  func testProfileWriteFailureRetainsJournalAndRetryKeepsCommittedRows() throws {
    let target = try Target(rejectText: true); defer { target.close() }
    let expected = try profile(), incoming = try archive(expected)
    XCTAssertThrowsError(try target.apply(incoming)) { XCTAssertTrue($0 is WebsiteProfileArchiveImportFailure) }
    XCTAssertEqual(try target.container.mainContext.fetchCount(FetchDescriptor<TestPresetRecord>()), 1)
    XCTAssertEqual(target.settings.websiteProfileArchiveGeneration, 0)
    let directory = try XCTUnwrap(WebsiteConfigStorageDirectory.existing(applicationSupport: target.support))
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: directory).read().state, .unavailable)
    let healthy = AppSettings(defaults: try XCTUnwrap(UserDefaults(suiteName: target.suite)),
      feedbackSound: .init(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
    let summary = try target.apply(incoming, settings: healthy)
    XCTAssertEqual(summary.insertedPresets, 0)
    XCTAssertTrue(summary.restoredWebsiteProfile)
    XCTAssertEqual(try WebsiteProfileArchiveTarget.captureSaved(settings: healthy, applicationSupport: target.support), expected)
    XCTAssertEqual(healthy.websiteProfileArchiveGeneration, 1)
  }

  func testReadOnlyDatabaseAndActiveOwnerRefuseBeforeProfileOrTextCommit() throws {
    for readOnly in [true, false] {
      let target = try Target(readOnly: readOnly); defer { target.close() }
      if !readOnly {
        let owner = UUID()
        target.settings.preferenceConfigurationSaves.register(owner: owner, save: {})
        target.settings.preferenceConfigurationSaves.setWebsiteArchiveAdmission(owner: owner, check: { false })
      }
      let before = target.settings.snapshot
      XCTAssertThrowsError(try target.apply(archive(profile())))
      XCTAssertEqual(target.settings.snapshot, before)
      XCTAssertEqual(target.settings.websiteProfileArchiveGeneration, 0)
      XCTAssertEqual(target.settings.websiteCustomTextStateRead, .missing)
      XCTAssertNil(try WebsiteProfileArchiveTarget.captureSaved(settings: target.settings, applicationSupport: target.support))
    }
  }

  func testSavedCaptureIgnoresNativePreferencesAndRefusesOpaqueProfileOrText() throws {
    let target = try Target(); defer { target.close() }
    let expected = try profile()
    _ = try target.apply(archive(expected))
    target.settings.fontSize = 48
    XCTAssertEqual(try WebsiteProfileArchiveTarget.captureSaved(settings: target.settings, applicationSupport: target.support), expected)
    let directory = try XCTUnwrap(WebsiteConfigStorageDirectory.existing(applicationSupport: target.support))
    let path = directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename)
    let good = try Data(contentsOf: path), opaque = Data("unknown future profile".utf8)
    try opaque.write(to: path)
    XCTAssertThrowsError(try WebsiteProfileArchiveTarget.captureSaved(settings: target.settings, applicationSupport: target.support))
    XCTAssertEqual(try Data(contentsOf: path), opaque)
    try good.write(to: path)
    target.defaults.set(opaque, forKey: WebsiteCustomTextStateStore.storageKey)
    XCTAssertThrowsError(try WebsiteProfileArchiveTarget.captureSaved(settings: target.settings, applicationSupport: target.support))
    XCTAssertEqual(target.defaults.data(forKey: WebsiteCustomTextStateStore.storageKey), opaque)
  }

  func testFutureMalformedAndDowngradedProfilePayloadsAreNotIgnored() throws {
    let expected = try profile()
    let bytes = try TypebarDataTransfer.exportArchive(settings: .init(), results: [], presets: [], websiteProfile: expected)
    let root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    var invalids: [[String: Any]] = []
    for version in [37, TypebarArchive.currentVersion + 1] { var bad = root; bad["version"] = version; invalids.append(bad) }
    let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: expected.archiveData()) as? [String: Any])
    for (key, value): (String, Any) in [("kind", "foreign"), ("version", 2), ("lazyRemember", "true"),
      ("runtimeData", Data("{}".utf8).base64EncodedString()), ("customTextData", Data("bad".utf8).base64EncodedString()),
      ("fallbackCustomTextData", Data("bad".utf8).base64EncodedString())] {
      var changed = payload; changed[key] = value
      var bad = root; bad["websiteProfileData"] = try JSONSerialization.data(withJSONObject: changed).base64EncodedString()
      invalids.append(bad)
    }
    for invalid in invalids { XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: invalid))) }
    let plain = TypebarArchive(exportedAt: .now, settings: .init(), results: [], presets: [])
    XCTAssertEqual(try TypebarArchiveConflictMerge.mergeWithReport(local: plain, remote: archive(expected)).archive.websiteProfile, expected)
  }

  func testProfileDocumentCodecWorksOffMainActorWithoutResourcePreparation() async throws {
    let expected = try profile(), bytes = try expected.archiveData()
    let result = try await Task.detached { try WebsiteProfileArchive.decode(bytes).archiveData() }.value
    XCTAssertEqual(try WebsiteProfileArchive.decode(result), expected)
  }

  func testExportCaptureNeverDropsOpaquePresetRows() throws {
    let record = try TestPresetRecord(name: "owned", definition: .init(configuration: .words(3)))
    XCTAssertEqual(try LocalArchiveRecordCapture.presets([record]).count, 1)
    record.definitionData = Data("unknown future preset".utf8)
    XCTAssertNil(record.definition)
    let bytes = record.definitionData
    XCTAssertThrowsError(try LocalArchiveRecordCapture.presets([record]))
    XCTAssertEqual(record.definitionData, bytes)
  }

  func testSignedZeroProfileIsNotTreatedAsAnUnchangedSnapshot() throws {
    let target = try Target(); defer { target.close() }
    let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: target.support)
    let register = WebsiteConfigFileRegister(directory: directory)
    let before = try WebsiteConfigNativeProfile.defaultDocument().values
    guard case .committed = try register.commit(runtime: before, lazyMemory: .init(), replacing: XCTUnwrap(register.read().revision))
    else { return XCTFail("Initial commit failed") }
    var after = before
    after["customBackgroundFilter"] = .array([.number(-0.0), .number(1), .number(1), .number(1)])
    let original = try WebsiteProfileArchive(runtime: before, lazyMemory: .init(), customTextData: nil)
    let expected = try WebsiteProfileArchive(runtime: after, lazyMemory: .init(), customTextData: nil)
    XCTAssertNotEqual(original, expected)
    let prepared = try register.prepareArchiveRestore(expected, customStore: target.settings.websiteCustomArchiveStore)
    XCTAssertFalse(prepared.isUnchanged)
    try register.restoreArchive(prepared, customStore: target.settings.websiteCustomArchiveStore)
    guard case .available(let actual) = try register.read().state,
      case .array(let filters)? = actual["customBackgroundFilter"], case .number(let value) = filters[0]
    else { return XCTFail("Missing profile") }
    XCTAssertEqual(value.bitPattern, (-0.0).bitPattern)
  }
}

private final class RejectingTextDefaults: UserDefaults, @unchecked Sendable {
  override func set(_ value: Any?, forKey key: String) {
    guard key != WebsiteCustomTextStateStore.storageKey else { return }
    super.set(value, forKey: key)
  }
}
