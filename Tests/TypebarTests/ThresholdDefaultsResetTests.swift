import AppKit
import SwiftData
import XCTest

@testable import Typebar

@MainActor
final class ThresholdDefaultsResetTests: XCTestCase {
  private func imageData() throws -> Data {
    let bitmap = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32))
    bitmap.setColor(.red, atX: 0, y: 0)
    return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
  }

  private func withSettings(
    source: Bool = true,
    _ body: (AppSettings, UserDefaults) throws -> Void
  ) throws {
    let suite = "typebar.threshold-reset.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    if source {
      var raw = PracticeThresholdConfiguration()
      try raw.apply(.minimumWpm(mode: .custom, customValue: 33))
      try raw.apply(.minimumAccuracy(mode: .custom, customValue: 0))
      try raw.apply(.minimumWordBurst(mode: .flex, customValue: 0))
      XCTAssertTrue(
        ThresholdSettingsStore(defaults: defaults).save(
          PracticeThresholdSource(configuration: raw).applying(
            to: AppSettingsSnapshot(fontSize: 35))))
    }
    let settings = AppSettings(defaults: defaults, localBackgroundStore: .inMemory())
    try settings.importLocalBackground(data: imageData())
    defaults.set(Data("retained selection".utf8), forKey: "activeTestSelection.v1")
    defaults.set(Data("retained selection 2".utf8), forKey: "activeTestSelection.v2")
    try body(settings, defaults)
  }

  func testSourceResetRestoresCanonicalMemoryAndOnlyRemovesOwnedSelectionAndBackground() throws {
    try withSettings { settings, defaults in
      let legacy = Data("legacy archive".utf8)
      for key in ["appSettings.v1", "appSettings.v2", "appSettings.v3"] {
        defaults.set(legacy, forKey: key)
      }
      XCTAssertTrue(
        settings.restoreDefaults(customizationTombstoneStore: .init(defaults: defaults)))
      XCTAssertEqual(settings.thresholdConfiguration, PracticeThresholdConfiguration())
      XCTAssertEqual(
        AppSettings(defaults: defaults).snapshot,
        PracticeThresholdSource(configuration: .init()).applying(to: AppSettingsSnapshot()))
      XCTAssertFalse(settings.hasLocalBackground)
      XCTAssertNil(defaults.object(forKey: "activeTestSelection.v1"))
      XCTAssertNil(defaults.object(forKey: "activeTestSelection.v2"))
      for key in ["appSettings.v1", "appSettings.v2", "appSettings.v3"] {
        XCTAssertEqual(defaults.data(forKey: key), legacy)
      }
    }
  }

  func testFutureProfileRefusesResetBeforeMemorySelectionsOrBackgroundAreChanged() throws {
    for loaded in [true, false] {
      try withSettings { settings, defaults in
        let future = Data("{\"version\":5}".utf8)
        defaults.set(future, forKey: "appSettings.v4")
        let target =
          loaded
          ? settings
          : AppSettings(defaults: defaults, localBackgroundStore: settings.localBackgroundStore)
        let before = target.snapshot
        let generation = target.activeTestSelectionGeneration
        XCTAssertFalse(
          target.restoreDefaults(customizationTombstoneStore: .init(defaults: defaults)))
        XCTAssertEqual(target.snapshot, before)
        XCTAssertEqual(target.activeTestSelectionGeneration, generation)
        XCTAssertTrue(target.hasLocalBackground)
        XCTAssertNotNil(defaults.object(forKey: "activeTestSelection.v1"))
        XCTAssertNotNil(defaults.object(forKey: "activeTestSelection.v2"))
        XCTAssertEqual(defaults.data(forKey: "appSettings.v4"), future)
      }
    }
  }

  func testNoQuitRefusesResetBeforeAnyOwnedStateChanges() throws {
    try withSettings { settings, defaults in
      let owner = UUID()
      settings.setNoQuitConfigurationLock(true, for: owner)
      defer { settings.setNoQuitConfigurationLock(false, for: owner) }
      let before = settings.snapshot
      let bytes = defaults.data(forKey: "appSettings.v4")
      XCTAssertFalse(
        settings.restoreDefaults(customizationTombstoneStore: .init(defaults: defaults)))
      XCTAssertEqual(settings.snapshot, before)
      XCTAssertEqual(defaults.data(forKey: "appSettings.v4"), bytes)
      XCTAssertTrue(settings.hasLocalBackground)
      XCTAssertNotNil(defaults.object(forKey: "activeTestSelection.v1"))
    }
  }

  func testQASelectionAndInMemoryStoresNeverShareImages() throws {
    XCTAssertTrue(
      TypebarLocalBackgroundStore.configured(
        info: [:], environment: ["TYPEBAR_QA_IN_MEMORY_STORE": "1"]
      ).isInMemory)
    XCTAssertTrue(
      TypebarLocalBackgroundStore.configured(
        info: [QAStoreMode.inMemoryInfoKey: true], environment: [:]
      ).isInMemory)
    XCTAssertFalse(TypebarLocalBackgroundStore.configured(info: [:], environment: [:]).isInMemory)
    let first = TypebarLocalBackgroundStore.inMemory()
    let second = TypebarLocalBackgroundStore.inMemory()
    try first.save(imageData())
    XCTAssertTrue(first.hasImage)
    XCTAssertNotNil(first.image())
    XCTAssertFalse(second.hasImage)
    XCTAssertThrowsError(try first.save(Data("not an image".utf8)))
    XCTAssertNotNil(first.image())
    try first.remove()
    XCTAssertNil(first.image())
    XCTAssertFalse(first.hasImage)
  }

  private func withDirectory(_ body: (URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "typebar-background-fixture-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(root)
  }

  func testDirectoryStorageRetainsFilenameAndSupportsNewReaderWithoutCrossStoreRemoval() throws {
    try withDirectory { root in
      let first = TypebarLocalBackgroundStore(directoryURL: root.appendingPathComponent("first"))
      let second = TypebarLocalBackgroundStore(directoryURL: root.appendingPathComponent("second"))
      let data = try imageData()
      try first.save(data)
      try second.save(data)
      let reader = TypebarLocalBackgroundStore(directoryURL: root.appendingPathComponent("first"))
      XCTAssertNotNil(reader.image())
      XCTAssertEqual(
        try Data(contentsOf: root.appendingPathComponent("first/local-practice-background")), data)
      try reader.remove()
      XCTAssertFalse(first.hasImage)
      XCTAssertTrue(second.hasImage)
      try reader.remove()
    }
  }

  func testUnexpectedBackgroundDirectoryRejectsResetWithoutDeletingItsContents() throws {
    try withDirectory { root in
      let unexpected = root.appendingPathComponent("local-practice-background", isDirectory: true)
      try FileManager.default.createDirectory(at: unexpected, withIntermediateDirectories: true)
      let marker = unexpected.appendingPathComponent("preserve")
      let bytes = Data("fixture contents".utf8)
      try bytes.write(to: marker)
      try withSettings { _, defaults in
        let settings = AppSettings(
          defaults: defaults, localBackgroundStore: .init(directoryURL: root))
        let before = settings.snapshot
        let stored = defaults.data(forKey: "appSettings.v4")
        XCTAssertFalse(settings.restoreDefaults())
        XCTAssertEqual(settings.snapshot, before)
        XCTAssertEqual(defaults.data(forKey: "appSettings.v4"), stored)
        XCTAssertNotNil(defaults.object(forKey: "activeTestSelection.v1"))
        XCTAssertEqual(try Data(contentsOf: marker), bytes)
      }
    }
  }

  func testLegacyResetKeepsOldFormatAndUsesItsOwnTombstoneDomain() throws {
    try withSettings(source: false) { settings, defaults in
      settings.minimumWpm = 33
      let theme = CustomThemeDefinition(
        id: UUID(), name: "Fixture", background: .init(red: 0, green: 0, blue: 0),
        panel: .init(red: 0, green: 0, blue: 0), accent: .init(red: 1, green: 0, blue: 0),
        prefersDark: true)
      settings.customThemes = [theme]
      XCTAssertTrue(settings.restoreDefaults())
      XCTAssertEqual(settings.snapshot, AppSettingsSnapshot())
      XCTAssertNil(defaults.object(forKey: "appSettings.v4"))
      XCTAssertEqual(CustomizationTombstoneStore(defaults: defaults).deletedThemeIDs, [theme.id])
      XCTAssertFalse(settings.hasLocalBackground)
    }
  }

  func testAccountResetPreflightRejectsUnknownSettingsBeforeAnyCleanupCallbackOrModelDelete() throws
  {
    try withSettings { settings, defaults in
      let container = try ModelContainer(
        for: TestResultRecord.self, LocalPersonalBestLedgerRecord.self,
        TestPresetRecord.self, SavedCustomTextRecord.self, ResultFilterPresetRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
      container.mainContext.insert(SavedCustomTextRecord(title: "Keep", text: "fixture"))
      try container.mainContext.save()
      defaults.set(Data("{\"version\":5}".utf8), forKey: "appSettings.v4")
      var calls = 0
      XCTAssertThrowsError(
        try LocalAccountReset.eraseCurrentMacData(
          modelContext: container.mainContext,
          settings: settings, removeBackground: { calls += 1 }, removePracticeFont: { calls += 1 },
          clearPendingPublications: { calls += 1 }, save: { calls += 1 }))
      XCTAssertEqual(calls, 0)
      XCTAssertEqual(
        try container.mainContext.fetchCount(FetchDescriptor<SavedCustomTextRecord>()), 1)
      XCTAssertTrue(settings.hasLocalBackground)
    }
  }

  func testProductionUIUsesTheSameBackgroundStoreAndHandlesResetRejection() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let app = try String(
      contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    let view = try String(
      contentsOf: root.appendingPathComponent("Sources/Typebar/PreferencesView.swift"),
      encoding: .utf8)
    XCTAssertTrue(app.contains("localBackgroundStore: settings.localBackgroundStore"))
    XCTAssertTrue(view.contains("showingRestoreDefaultsFailure = !settings.restoreDefaults()"))
    let preflight = try XCTUnwrap(view.range(of: "guard settings.canRestoreDefaults else"))
    let request = try XCTUnwrap(view.range(of: "guard await account.resetAccount("))
    XCTAssertLessThan(preflight.lowerBound, request.lowerBound)
  }
}
