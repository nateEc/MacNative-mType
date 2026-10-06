import XCTest
@testable import Typebar

final class CustomPaceSpeedMigrationTests: XCTestCase {
  private let date = Date(timeIntervalSince1970: 1_800_000_000)
  private let configuration = TestConfiguration.timed(seconds: 30)

  private var encoder: JSONEncoder {
    let value = JSONEncoder()
    value.dateEncodingStrategy = .iso8601
    return value
  }

  private func snapshot(_ speed: Double) throws -> AppSettingsSnapshot {
    try JSONDecoder().decode(AppSettingsSnapshot.self,
      from: JSONSerialization.data(withJSONObject: ["paceGuideCustomWpm": speed]))
  }

  private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(value)) as? [String: Any])
  }

  func testDecodedSpeedsRetainFractionsZeroAndValuesOutsideLegacyEditorRange() throws {
    for speed in [0, 0.25, 1, 9, 60.123456789, 350, 1e100] {
      let decoded = try snapshot(speed)
      XCTAssertEqual(Double(decoded.paceGuideCustomWpm), speed)
      let restored = try JSONDecoder().decode(AppSettingsSnapshot.self,
        from: JSONEncoder().encode(decoded))
      XCTAssertEqual(Double(restored.paceGuideCustomWpm), speed)
    }
  }

  func testConstructorDoesNotClampValidNonnegativeIntegers() {
    for speed in [0, 1, 9, 350, 1_000_000] {
      XCTAssertEqual(AppSettingsSnapshot(paceGuideCustomWpm: Double(speed)).paceGuideCustomWpm, Double(speed))
    }
  }

  func testNegativeImportedSpeedsAreRejectedRatherThanSilentlyClamped() {
    XCTAssertThrowsError(try snapshot(-1))
    XCTAssertThrowsError(try snapshot(-0.001))
  }

  func testCustomTargetDoesNotClampAndZeroDisablesIt() {
    for speed in [1, 9, 350, 1_000_000] {
      XCTAssertEqual(PaceGuidePolicy.targetWpm(mode: .custom, customWpm: Double(speed),
        configuration: configuration, samples: []), Double(speed))
    }
    XCTAssertNil(PaceGuidePolicy.targetWpm(mode: .custom, customWpm: 0,
      configuration: configuration, samples: []))
  }

  @MainActor
  func testExpandedSettingsForkStorageWithoutOverwritingLegacyAndStayForked() throws {
    let suite = "TypebarTests.pace-migration.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let legacy = try JSONSerialization.data(withJSONObject:
      ["paceGuideCustomWpm": 95, "fontSize": 34, "alwaysShowDecimalPlaces": true])
    defaults.set(legacy, forKey: "appSettings.v1")
    let settings = AppSettings(defaults: defaults)
    XCTAssertEqual(settings.paceGuideCustomWpm, 95)
    XCTAssertNil(defaults.data(forKey: "appSettings.v2"))
    settings.apply(try snapshot(60.25))
    XCTAssertEqual(Double(settings.paceGuideCustomWpm), 60.25)
    let preservedLegacy = try XCTUnwrap(defaults.data(forKey: "appSettings.v1"))
    XCTAssertEqual(preservedLegacy, legacy, "Select the new storage before any apply writes")
    let checkpoint = preservedLegacy
    XCTAssertEqual(Double(AppSettings(defaults: defaults).paceGuideCustomWpm), 60.25)
    settings.paceGuideCustomWpm = 95
    settings.fontSize = 36
    XCTAssertEqual(defaults.data(forKey: "appSettings.v1"), checkpoint)
    XCTAssertEqual(AppSettings(defaults: defaults).paceGuideCustomWpm, 95)
    XCTAssertEqual(AppSettings(defaults: defaults).fontSize, 36)
  }

  func testArchivePromotesExpandedSettingsAndPresetsToFormatTwentyFour() throws {
    let expanded = try snapshot(350)
    let archive = TypebarArchive(version: 23, exportedAt: date,
      settings: expanded, results: [], presets: [])
    XCTAssertEqual(archive.version, 24)
    let preset = NamedPreset(name: "owned",
      definition: .init(configuration: configuration, settingsSnapshot: expanded))
    XCTAssertEqual(TypebarArchive(version: 23, exportedAt: date, settings: .init(),
      results: [], presets: [preset]).version, 24)
  }

  func testExpandedArchiveCannotMasqueradeAsOldFormatIncludingPresetSnapshots() throws {
    let expanded = try snapshot(350)
    let preset = NamedPreset(name: "owned",
      definition: .init(configuration: configuration, settingsSnapshot: expanded))
    for archive in [
      TypebarArchive(exportedAt: date, settings: expanded, results: [], presets: []),
      TypebarArchive(exportedAt: date, settings: .init(), results: [], presets: [preset])
    ] {
      var json = try object(archive)
      json["version"] = 23
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(
        from: JSONSerialization.data(withJSONObject: json))) {
        XCTAssertEqual($0 as? DataTransferError, .unsupportedVersion(23))
      }
    }
  }

  func testLegacyArchiveWithIntegerSettingsKeepsExplicitFormatAndValue() throws {
    let archive = TypebarArchive(version: 23, exportedAt: date,
      settings: .init(paceGuideCustomWpm: 95), results: [], presets: [])
    let restored = try TypebarDataTransfer.importArchive(from: encoder.encode(archive))
    XCTAssertEqual(restored.version, 23)
    XCTAssertEqual(restored.settings.paceGuideCustomWpm, 95)
  }

  func testUnitInputValidationKeepsFractionsAndRejectsOverflowWithoutIntegerConversion() throws {
    for unit in TypingSpeedUnit.allCases {
      let displayed = unit.converted(wpm: 60.123456789)
      XCTAssertEqual(try XCTUnwrap(PaceCustomSpeedPolicy.canonicalWpm(
        displayedValue: displayed, unit: unit)), 60.123456789, accuracy: 1e-12)
      XCTAssertEqual(try XCTUnwrap(PaceCustomSpeedPolicy.parse(String(displayed), unit: unit)),
        60.123456789, accuracy: 1e-12)
    }
    XCTAssertEqual(PaceCustomSpeedPolicy.parse(" 1e100 ", unit: .wpm), 1e100)
    XCTAssertEqual(PaceCustomSpeedPolicy.parse("0", unit: .wpm), 0)
    for invalid in ["", "NaN", "inf", "-1", "60oops", "1e999"] {
      XCTAssertNil(PaceCustomSpeedPolicy.parse(invalid, unit: .wpm), invalid)
    }
    XCTAssertNil(PaceCustomSpeedPolicy.canonicalWpm(displayedValue: .greatestFiniteMagnitude, unit: .wps))
    XCTAssertNotNil(PaceCustomSpeedPolicy.canonicalWpm(
      displayedValue: Double.greatestFiniteMagnitude / 24, unit: .cps))
    XCTAssertNil(PaceCustomSpeedPolicy.canonicalWpm(
      displayedValue: Double.greatestFiniteMagnitude / 12, unit: .cps))
    XCTAssertNil(PaceCustomSpeedPolicy.canonicalWpm(displayedValue: .leastNonzeroMagnitude, unit: .cpm))
    XCTAssertNotNil(PaceCustomSpeedPolicy.displayedValue(wpm: .greatestFiniteMagnitude, unit: .cps))
    XCTAssertNil(PaceCustomSpeedPolicy.displayedValue(wpm: .leastNonzeroMagnitude, unit: .wps))
  }

  @MainActor
  func testInvalidProgrammaticValuesNormalizeWithoutRemovingExistingSettings() throws {
    let suite = "TypebarTests.pace-invalid.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    settings.paceGuideCustomWpm = 60.25
    settings.fontSize = 36
    for invalid in [Double.nan, .infinity, -1] {
      settings.paceGuideCustomWpm = invalid
      XCTAssertEqual(settings.paceGuideCustomWpm, 100)
      XCTAssertEqual(AppSettings(defaults: defaults).paceGuideCustomWpm, 100)
      XCTAssertEqual(AppSettings(defaults: defaults).fontSize, 36)
      XCTAssertNotNil(defaults.data(forKey: AppSettings.expandedPaceStorageKey))
    }
    XCTAssertEqual(AppSettingsSnapshot(paceGuideCustomWpm: .nan).paceGuideCustomWpm, 100)
    let decoder = JSONDecoder()
    decoder.nonConformingFloatDecodingStrategy = .convertFromString(
      positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
    XCTAssertThrowsError(try decoder.decode(AppSettingsSnapshot.self,
      from: Data(#"{"paceGuideCustomWpm":"NaN"}"#.utf8)))
  }

  @MainActor
  func testEveryExpandedKindForksAndLaterLegacyWriterCannotReplaceNewState() throws {
    for speed in [0, 0.25, 9, 60.25, 301, 1e100] {
      let suite = "TypebarTests.pace-fork.\(UUID().uuidString)"
      let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      defer { defaults.removePersistentDomain(forName: suite) }
      let legacy = try encoder.encode(AppSettingsSnapshot(fontSize: 34, paceGuideCustomWpm: 95))
      defaults.set(legacy, forKey: AppSettings.legacyStorageKey)
      let settings = AppSettings(defaults: defaults)
      settings.paceGuideCustomWpm = speed
      XCTAssertEqual(defaults.data(forKey: AppSettings.legacyStorageKey), legacy)
      XCTAssertEqual(AppSettings(defaults: defaults).paceGuideCustomWpm, speed)
      // Simulate an old writer only in this isolated defaults suite.
      defaults.set(try encoder.encode(AppSettingsSnapshot(fontSize: 40, paceGuideCustomWpm: 125)),
        forKey: AppSettings.legacyStorageKey)
      let reloaded = AppSettings(defaults: defaults)
      XCTAssertEqual(reloaded.paceGuideCustomWpm, speed)
      XCTAssertEqual(reloaded.fontSize, 34)
    }
  }

  @MainActor
  func testMalformedNewGenerationDoesNotSilentlyResurrectLegacySettings() throws {
    let suite = "TypebarTests.pace-corrupt.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let corrupt = Data("not-json".utf8)
    let legacy = try encoder.encode(AppSettingsSnapshot(paceGuideCustomWpm: 95))
    defaults.set(legacy, forKey: AppSettings.legacyStorageKey)
    defaults.set(corrupt, forKey: AppSettings.expandedPaceStorageKey)
    XCTAssertEqual(AppSettings(defaults: defaults).paceGuideCustomWpm, 100)
    XCTAssertEqual(defaults.data(forKey: AppSettings.expandedPaceStorageKey), corrupt)
    XCTAssertEqual(defaults.data(forKey: AppSettings.legacyStorageKey), legacy)
  }

  func testCaretPresetScopeKeepsExactSpeedWhileOtherScopesLeaveItAlone() throws {
    let definition = SavedTestPreset(configuration: configuration, settingsSnapshot: try snapshot(60.25))
    let current = SavedTestPreset(configuration: configuration,
      settingsSnapshot: .init(paceGuideCustomWpm: 95))
    let full = PresetApplicationPolicy.applying(current: current, preset: definition).settingsSnapshot
    let caret = PresetApplicationPolicy.applying(current: current,
      preset: definition.with(settingGroups: [.caret])).settingsSnapshot
    let input = PresetApplicationPolicy.applying(current: current,
      preset: definition.with(settingGroups: [.input])).settingsSnapshot
    XCTAssertEqual(full?.paceGuideCustomWpm, 60.25)
    XCTAssertEqual(caret?.paceGuideCustomWpm, 60.25)
    XCTAssertEqual(input?.paceGuideCustomWpm, 95)
  }

  @MainActor
  func testCurrentPresetEntityAndArchiveRetainPrecisionAndDoNotRescoreOldResult() throws {
    let settings = try snapshot(60.25)
    let preset = TestPresetRecord(name: "owned",
      definition: .init(configuration: configuration, settingsSnapshot: settings))
    XCTAssertEqual(preset.definition?.settingsSnapshot?.paceGuideCustomWpm, 60.25)
    let old = CompletedTestResult(id: UUID(), configuration: configuration, outcome: .completed,
      startedAt: date.addingTimeInterval(-30), finishedAt: date, typedCharacterCount: 75,
      correctCharacterCount: 70, errorCount: 5, wpm: 17, rawWpm: 29, accuracy: 77)
    let data = try TypebarDataTransfer.exportArchive(settings: settings, results: [old],
      presets: [.init(id: preset.id, name: preset.name, definition: try XCTUnwrap(preset.definition))])
    let restored = try TypebarDataTransfer.importArchive(from: data)
    XCTAssertEqual(restored.results, [old])
    XCTAssertEqual(restored.settings.paceGuideCustomWpm, 60.25)
    XCTAssertEqual(restored.presets.first?.definition.settingsSnapshot?.paceGuideCustomWpm, 60.25)
    let legacyData = try encoder.encode(SavedTestPreset(configuration: configuration,
      settingsSnapshot: .init(paceGuideCustomWpm: 95)))
    preset.definitionData = legacyData
    XCTAssertEqual(preset.definition?.settingsSnapshot?.paceGuideCustomWpm, 95)
    XCTAssertEqual(preset.definitionData, legacyData)
  }

  func testDeletedExpandedPresetStillRequiresNewArchiveBeforeFiltering() throws {
    let id = UUID()
    let preset = NamedPreset(id: id, name: "owned", definition:
      .init(configuration: configuration, settingsSnapshot: try snapshot(60.25)))
    var json = try object(TypebarArchive(version: 23, exportedAt: date,
      settings: .init(), results: [], presets: []))
    json["presets"] = [try object(preset)]
    json["deletedPresetIDs"] = [id.uuidString]
    XCTAssertThrowsError(try TypebarDataTransfer.importArchive(
      from: JSONSerialization.data(withJSONObject: json))) {
      XCTAssertEqual($0 as? DataTransferError, .unsupportedVersion(23))
    }
    json["version"] = 24
    XCTAssertTrue(try TypebarDataTransfer.importArchive(
      from: JSONSerialization.data(withJSONObject: json)).presets.isEmpty)
  }

  func testAllExpandedKindsPromoteFormatsAndCompatibleLegacySettingsJSONStillLoads() throws {
    for speed in [0, 0.25, 9, 60.25, 301, 1e100] {
      let settings = try snapshot(speed)
      XCTAssertEqual(TypebarArchive(version: 23, exportedAt: date,
        settings: settings, results: [], presets: []).version, 24)
      let json = try SettingsJSONCommandCodec.export(settings: settings, configuration: configuration,
        layoutFluidLayouts: [], testParameterMemory: .defaults)
      let decoded = try SettingsJSONCommandCodec.decode(json)
      XCTAssertEqual(decoded.version, TypebarSettingsDocument.currentVersion)
      XCTAssertEqual(decoded.settings.paceGuideCustomWpm, speed)
    }
    let document = TypebarSettingsDocument(version: 3, settings: .init(paceGuideCustomWpm: 95),
      configuration: configuration, layoutFluidLayouts: [], testParameterMemory: .defaults)
    let decoded = try SettingsJSONCommandCodec.decode(String(decoding: encoder.encode(document), as: UTF8.self))
    XCTAssertEqual(decoded.version, 3)
    XCTAssertEqual(decoded.settings.paceGuideCustomWpm, 95)
  }

  @MainActor
  func testPreferencesAndCommandActivationDifferAndInvalidInputHasNoEffects() throws {
    let suite = "TypebarTests.pace-apply.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    let generation = settings.activeTestSelectionGeneration
    XCTAssertTrue(PaceCustomSpeedPolicy.apply(100, to: settings, activateCustom: false))
    XCTAssertEqual(settings.paceGuideMode, .off)
    XCTAssertTrue(PaceCustomSpeedPolicy.apply(60.25, to: settings, activateCustom: false))
    XCTAssertEqual(settings.paceGuideMode, .custom)
    settings.paceGuideMode = .personalBest
    XCTAssertTrue(PaceCustomSpeedPolicy.apply(350, to: settings, activateCustom: false))
    XCTAssertEqual(settings.paceGuideMode, .personalBest)
    let data = defaults.data(forKey: AppSettings.expandedPaceStorageKey)
    XCTAssertFalse(PaceCustomSpeedPolicy.apply(.infinity, to: settings, activateCustom: true))
    XCTAssertEqual(defaults.data(forKey: AppSettings.expandedPaceStorageKey), data)
    XCTAssertTrue(PaceCustomSpeedPolicy.apply(350, to: settings, activateCustom: true))
    XCTAssertEqual(settings.paceGuideMode, .custom)
    XCTAssertEqual(settings.activeTestSelectionGeneration, generation)
    XCTAssertEqual(PaceGuideSpeedEditor(unit: .wph, initialWpm: .greatestFiniteMagnitude,
      onApply: { _ in }).unit, .wpm)
  }

  func testPromotionDoesNotStripExistingIDsOrTombstonesUsingTheRequestedOldVersion() throws {
    let id = UUID(), deleted = UUID(), theme = UUID(), layout = UUID(), filter = UUID()
    let preset = NamedPreset(id: id, name: "owned", definition:
      .init(configuration: configuration, settingsSnapshot: try snapshot(60.25)))
    let archive = TypebarArchive(version: 1, exportedAt: date, settings: .init(),
      deletedCustomThemeIDs: [theme], deletedCustomKeyboardLayoutIDs: [layout],
      results: [], deletedResultIDs: [deleted], presets: [preset], deletedPresetIDs: [deleted],
      savedTexts: [.init(id: id, title: "owned", text: "owned text")], deletedSavedTextIDs: [deleted],
      deletedResultFilterPresetIDs: [filter])
    XCTAssertEqual(archive.version, 24)
    XCTAssertEqual(archive.presets.first?.id, id)
    XCTAssertEqual(archive.savedTexts.first?.id, id)
    XCTAssertEqual(archive.deletedCustomThemeIDs, [theme])
    XCTAssertEqual(archive.deletedCustomKeyboardLayoutIDs, [layout])
    XCTAssertEqual(archive.deletedResultIDs, [deleted])
    XCTAssertEqual(archive.deletedPresetIDs, [deleted])
    XCTAssertEqual(archive.deletedSavedTextIDs, [deleted])
    XCTAssertEqual(archive.deletedResultFilterPresetIDs, [filter])
  }

  func testSettingsJSONPromotesAndRejectsExpandedValuesDisguisedAsOldFormat() throws {
    let document = TypebarSettingsDocument(version: 3, settings: try snapshot(350),
      configuration: configuration, layoutFluidLayouts: [], testParameterMemory: .defaults)
    XCTAssertEqual(document.version, 4)
    var json = try object(document)
    json["version"] = 3
    let data = try JSONSerialization.data(withJSONObject: json)
    XCTAssertThrowsError(try SettingsJSONCommandCodec.decode(String(decoding: data, as: UTF8.self))) {
      XCTAssertEqual($0 as? SettingsJSONCommandError, .unsupportedVersion(3))
    }
  }
}
