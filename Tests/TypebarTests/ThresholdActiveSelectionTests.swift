import XCTest
import SwiftData
@testable import Typebar

final class ThresholdActiveSelectionTests: XCTestCase {
  private func document() throws -> ActiveTestSelectionDocument {
    var raw = PracticeThresholdConfiguration()
    try raw.apply(.minimumWpm(mode: .off, customValue: 37))
    try raw.apply(.minimumWordBurst(mode: .flex, customValue: 0))
    let source = PracticeThresholdSource(configuration: raw)
    var configuration = TestConfiguration.words(17)
    configuration.rules = source.applying(to: configuration.rules)
    return .init(preset: .init(configuration: configuration, activeResultTags: ["private"],
      settingsSnapshot: source.applying(to: .init(fontSize: 31))), quoteSource: .community,
      testParameterMemory: .defaults)
  }
  private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let suite = "typebar.threshold-selection.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(defaults)
  }

  func testSourceSelectionHasIndependentGenerationWithoutGlobalSettings() throws {
    try withDefaults { defaults in
      let store = ActiveTestSelectionStore(defaults: defaults)
      XCTAssertEqual(store.read(), .missing)
      let legacy = ActiveTestSelectionDocument(preset: .init(configuration: .words(25)), testParameterMemory: .defaults)
      XCTAssertTrue(store.save(legacy))
      let old = defaults.data(forKey: ActiveTestSelectionStore.storageKey)
      let expected = try document()
      XCTAssertEqual(expected.version, 2)
      XCTAssertTrue(store.save(expected))
      let loaded = try XCTUnwrap(store.load())
      XCTAssertEqual(loaded.preset.configuration, expected.preset.configuration)
      XCTAssertNil(loaded.preset.settingsSnapshot)
      XCTAssertNil(loaded.preset.activeResultTags)
      XCTAssertEqual(loaded.testParameterMemory, expected.testParameterMemory)
      XCTAssertEqual(loaded.quoteSource, .community)
      XCTAssertEqual(defaults.data(forKey: ActiveTestSelectionStore.storageKey), old)
      XCTAssertNotNil(defaults.data(forKey: "activeTestSelection.v2"))
      XCTAssertFalse(store.save(legacy))
      XCTAssertEqual(store.load(), loaded)
      XCTAssertEqual(ActiveTestSelectionStore(defaults: defaults).read(), .available(loaded))
    }
  }

  func testPresentUnreadableOrFutureGenerationDoesNotFallBackOrOverwrite() throws {
    try withDefaults { defaults in
      let store = ActiveTestSelectionStore(defaults: defaults)
      XCTAssertTrue(store.save(.init(preset: .init(configuration: .words(25)), testParameterMemory: .defaults)))
      for value: Any in ["wrong type", Data(), Data("{".utf8), Data("{\"version\":3}".utf8)] {
        defaults.set(value, forKey: "activeTestSelection.v2")
        XCTAssertEqual(store.read(), .unavailable)
        XCTAssertNil(store.load())
        XCTAssertFalse(try store.save(document()))
        if let bytes = value as? Data { XCTAssertEqual(defaults.data(forKey: "activeTestSelection.v2"), bytes) }
        else { XCTAssertEqual(defaults.string(forKey: "activeTestSelection.v2"), "wrong type") }
      }
    }
  }

  func testNewWireFormatAndArchiveRoundTripWithoutV1PresetShadow() throws {
    let expected = try document()
    let bytes = try JSONEncoder().encode(expected)
    let root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    XCTAssertNil(root["preset"])
    XCTAssertNotNil(root["presetData"] as? String)
    let restored = try JSONDecoder().decode(ActiveTestSelectionDocument.self, from: bytes)
    XCTAssertEqual(restored.preset.configuration, expected.preset.configuration)
    let archive = try TypebarDataTransfer.exportArchive(settings: .init(), results: [], presets: [], activeTestSelection: expected)
    let decoded = try TypebarDataTransfer.importArchive(from: archive)
    XCTAssertEqual(decoded.activeTestSelection?.preset.configuration, expected.preset.configuration)
    XCTAssertGreaterThanOrEqual(decoded.version, 35)
  }

  func testContradictorySnapshotCannotBeTrimmedOrHiddenByArchiveConstruction() throws {
    try withDefaults { defaults in
      var preset = try document().preset
      preset.settingsSnapshot = .init(fontSize: 42)
      let invalid = ActiveTestSelectionDocument(preset: preset, testParameterMemory: .defaults)
      XCTAssertFalse(ActiveTestSelectionStore(defaults: defaults).save(invalid))
      XCTAssertNil(defaults.object(forKey: "activeTestSelection.v2"))
      XCTAssertThrowsError(try TypebarDataTransfer.exportArchive(settings: .init(), results: [], presets: [], activeTestSelection: invalid))
    }
  }

  func testWireRejectsDowngradesMixedPayloadsAndIncomingLocalMetadata() throws {
    let root = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(document())) as? [String: Any])
    for version in [1, 3] {
      var invalid = root
      invalid["version"] = version
      XCTAssertThrowsError(try JSONDecoder().decode(ActiveTestSelectionDocument.self, from: JSONSerialization.data(withJSONObject: invalid)))
    }
    var mixed = root
    mixed["preset"] = [:]
    XCTAssertThrowsError(try JSONDecoder().decode(ActiveTestSelectionDocument.self, from: JSONSerialization.data(withJSONObject: mixed)))
    for metadata in ["snapshot", "tags", "scope"] {
      var preset = try document().preset
      if metadata != "snapshot" { preset.settingsSnapshot = nil }
      if metadata == "tags" { preset.activeResultTags = ["private"] }
      if metadata == "scope" { preset.settingGroups = [.behavior] }
      var invalid = root
      invalid["presetData"] = try LocalPresetCodec.encode(preset).base64EncodedString()
      XCTAssertThrowsError(try JSONDecoder().decode(ActiveTestSelectionDocument.self, from: JSONSerialization.data(withJSONObject: invalid)))
    }
  }

  func testArchiveVersionFenceRejectsSourceSelectionInEarlierGenerations() throws {
    let bytes = try TypebarDataTransfer.exportArchive(settings: .init(), results: [], presets: [], activeTestSelection: document())
    let root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    for version in [1, 34] {
      var invalid = root
      invalid["version"] = version
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: invalid)))
      XCTAssertThrowsError(try JSONEncoder().encode(TypebarArchive(version: version, exportedAt: .now,
        settings: .init(), results: [], presets: [], activeTestSelection: document())))
    }
  }

  @MainActor
  func testUnmigratedSourceSelectionRestoreRefusesBeforePreferencesChange() throws {
    try withDefaults { defaults in
      let settings = AppSettings(defaults: defaults)
      let before = settings.snapshot
      let bytes = try TypebarDataTransfer.exportArchive(settings: .init(fontSize: 42), results: [], presets: [], activeTestSelection: document())
      let archive = try TypebarDataTransfer.importArchive(from: bytes)
      let container = try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self,
        LocalPersonalBestLedgerRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
      XCTAssertThrowsError(try LocalArchiveImport.apply(archive, settings: settings, results: [], presets: [], savedTexts: [],
        modelContext: container.mainContext)) {
          XCTAssertEqual($0 as? LocalArchiveImportError, .thresholdSourceNotReady)
      }
      XCTAssertEqual(settings.snapshot, before)
    }
  }
}
