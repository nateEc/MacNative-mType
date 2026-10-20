import XCTest
@testable import Typebar

final class ThresholdSettingsJSONTests: XCTestCase {
  private func values() throws -> (AppSettingsSnapshot, TestConfiguration) {
    var raw = PracticeThresholdConfiguration()
    try raw.apply(.minimumWpm(mode: .off, customValue: 37))
    try raw.apply(.minimumWordBurst(mode: .flex, customValue: 0))
    let source = PracticeThresholdSource(configuration: raw)
    var configuration = TestConfiguration.words(17)
    configuration.rules = source.applying(to: configuration.rules)
    return (source.applying(to: .init(fontSize: 31)), configuration)
  }
  private func json() throws -> String {
    let (settings, configuration) = try values()
    return try SettingsJSONCommandCodec.export(settings: settings, configuration: configuration,
      layoutFluidLayouts: [.ansiQwerty, .ansiDvorak], testParameterMemory: .defaults)
  }
  private func object() throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json().utf8)) as? [String: Any])
  }
  private func text(_ value: [String: Any]) throws -> String {
    String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
  }

  func testSourceSettingsAreEditableJSONAndRoundTripWithoutLegacyShadow() throws {
    let root = try object()
    XCTAssertEqual(root["version"] as? Int, 6)
    XCTAssertNil(root["settings"])
    XCTAssertNil(root["configuration"])
    let state = try XCTUnwrap(root["thresholdState"] as? [String: Any])
    let raw = try XCTUnwrap(state["thresholds"] as? [String: Any])
    XCTAssertEqual(raw["minimumWpmCustomValue"] as? Double, 37)
    XCTAssertEqual(raw["minimumWordBurstMode"] as? String, "flex")
    let decoded = try SettingsJSONCommandCodec.decode(json())
    let expected = try values()
    XCTAssertEqual(decoded.settings, expected.0)
    XCTAssertEqual(decoded.configuration, expected.1)
    XCTAssertEqual(decoded.testParameterMemory, .defaults)
  }

  func testHumanEditOfDisabledMemoryUpdatesBothCarriers() throws {
    var root = try object()
    var state = try XCTUnwrap(root["thresholdState"] as? [String: Any])
    var raw = try XCTUnwrap(state["thresholds"] as? [String: Any])
    raw["minimumWpmCustomValue"] = 75
    state["thresholds"] = raw
    root["thresholdState"] = state
    let decoded = try SettingsJSONCommandCodec.decode(text(root))
    XCTAssertEqual(decoded.settings.thresholdSource?.configuration.minimumWpmCustomValue, 75)
    XCTAssertEqual(decoded.configuration.rules.thresholdSource, decoded.settings.thresholdSource)
    XCTAssertEqual(decoded.settings.minimumWpm, 0)
  }

  func testDowngradeFutureMixedAndConflictingProjectionAreRejected() throws {
    let root = try object()
    for version in [5, 7] {
      var invalid = root
      invalid["version"] = version
      XCTAssertThrowsError(try SettingsJSONCommandCodec.decode(text(invalid)))
    }
    var invalid = root
    invalid["settings"] = [:]
    XCTAssertThrowsError(try SettingsJSONCommandCodec.decode(text(invalid)))
    var state = try XCTUnwrap(root["thresholdState"] as? [String: Any])
    var settings = try XCTUnwrap(state["settings"] as? [String: Any])
    settings["minimumWpm"] = -1
    state["settings"] = settings
    invalid = root
    invalid["thresholdState"] = state
    XCTAssertThrowsError(try SettingsJSONCommandCodec.decode(text(invalid)))
  }

  @MainActor
  func testUnmigratedApplyDoesNotChangePreferences() throws {
    let suite = "typebar.threshold-settings-json.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    let before = settings.snapshot
    XCTAssertThrowsError(try SettingsJSONCommandImport.apply(json(), to: settings)) {
      XCTAssertEqual($0 as? SettingsJSONCommandError, .thresholdSourceNotReady)
    }
    XCTAssertEqual(settings.snapshot, before)
  }

  func testBothOriginalProjectionsRejectMissingFieldsAndNormalizationAliases() throws {
    let root = try object()
    let state = try XCTUnwrap(root["thresholdState"] as? [String: Any])
    for location in ["settings", "rules"] {
      for key in ["minimumWpm", "minimumAccuracy", "minimumWordBurstWpm", "minimumWordBurstMode"] {
        for missing in [true, false] {
          var changedState = state
          var configuration = try XCTUnwrap(state["configuration"] as? [String: Any])
          var projection = try XCTUnwrap((location == "settings" ? state["settings"] : configuration["rules"]) as? [String: Any])
          if missing { projection.removeValue(forKey: key) }
          else { projection[key] = key == "minimumWordBurstMode" ? "fixed" : -1 }
          if location == "settings" { changedState["settings"] = projection }
          else { configuration["rules"] = projection; changedState["configuration"] = configuration }
          var invalid = root
          invalid["thresholdState"] = changedState
          XCTAssertThrowsError(try SettingsJSONCommandCodec.decode(text(invalid)), "\(location).\(key)")
        }
      }
    }
  }

  func testExportRejectsDifferentMemoriesAndDecoderRejectsFutureCanonicalMode() throws {
    var (settings, configuration) = try values()
    var raw = try XCTUnwrap(settings.thresholdSource?.configuration)
    try raw.apply(.minimumWpm(mode: .off, customValue: 75))
    settings = PracticeThresholdSource(configuration: raw).applying(to: settings)
    XCTAssertThrowsError(try SettingsJSONCommandCodec.export(settings: settings, configuration: configuration,
      layoutFluidLayouts: [], testParameterMemory: .defaults))
    var root = try object()
    var state = try XCTUnwrap(root["thresholdState"] as? [String: Any])
    var thresholds = try XCTUnwrap(state["thresholds"] as? [String: Any])
    thresholds["minimumWordBurstMode"] = "future"
    state["thresholds"] = thresholds
    root["thresholdState"] = state
    XCTAssertThrowsError(try SettingsJSONCommandCodec.decode(text(root)))
  }

  @MainActor
  func testLockedImportThrowsInsteadOfReturningAnApparentSuccess() throws {
    let suite = "typebar.settings-json.locked.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    let owner = UUID()
    settings.setNoQuitConfigurationLock(true, for: owner)
    defer { settings.setNoQuitConfigurationLock(false, for: owner) }
    let before = settings.snapshot
    let document = try SettingsJSONCommandCodec.export(settings: .init(fontSize: 42), configuration: .words(17),
      layoutFluidLayouts: [.ansiDvorak], testParameterMemory: .defaults)
    XCTAssertThrowsError(try SettingsJSONCommandImport.apply(document, to: settings)) {
      XCTAssertEqual($0 as? SettingsJSONCommandError, .configurationLocked)
    }
    XCTAssertEqual(settings.snapshot, before)
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let app = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    XCTAssertTrue(app.contains("guard acceptsRestartingConfigurationChange() else { throw SettingsJSONCommandError.configurationLocked }"),
      "Static hook check only: the sheet must not turn a preflight rejection into success")
  }
}
