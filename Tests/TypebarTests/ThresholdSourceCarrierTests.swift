import XCTest
@testable import Typebar

final class ThresholdSourceCarrierTests: XCTestCase {
  private func source() throws -> PracticeThresholdSource {
    var value = PracticeThresholdConfiguration()
    try value.apply(.minimumWpm(mode: .off, customValue: 31))
    try value.apply(.minimumAccuracy(mode: .custom, customValue: 0))
    try value.apply(.minimumWordBurst(mode: .fixed, customValue: 0))
    return .init(configuration: value)
  }
  private var encoder: JSONEncoder {
    let value = JSONEncoder()
    value.userInfo[PracticeThresholdSource.codingCapability] = true
    value.dateEncodingStrategy = .iso8601
    return value
  }
  private var decoder: JSONDecoder {
    let value = JSONDecoder()
    value.userInfo[PracticeThresholdSource.codingCapability] = true
    value.dateDecodingStrategy = .iso8601
    return value
  }

  func testLegacyEncodersRejectTheCapsuleAndBothCarriers() throws {
    let value = try source()
    XCTAssertThrowsError(try JSONEncoder().encode(value))
    XCTAssertThrowsError(try JSONEncoder().encode(value.applying(to: InputRules())))
    XCTAssertThrowsError(try JSONEncoder().encode(value.applying(to: AppSettingsSnapshot())))
  }

  func testExplicitCodecRetainsCompleteStateAndDoesNotEnableRememberedThresholds() throws {
    let value = try source()
    let rules = value.applying(to: InputRules(strictSpace: true))
    XCTAssertEqual(rules.minimumWpm, 0)
    XCTAssertEqual(rules.minimumAccuracy, 0)
    XCTAssertEqual(rules.minimumWordBurstWpm, 0)
    XCTAssertEqual(rules.minimumWordBurstMode, .off)
    XCTAssertTrue(rules.strictSpace)
    let restored = try decoder.decode(InputRules.self, from: encoder.encode(rules))
    XCTAssertEqual(restored, rules)
    XCTAssertEqual(restored.thresholdSource?.configuration.minimumWordBurstMode, .fixed)
    let snapshot = value.applying(to: AppSettingsSnapshot(fontSize: 34))
    XCTAssertEqual(try decoder.decode(AppSettingsSnapshot.self, from: encoder.encode(snapshot)), snapshot)
    XCTAssertEqual(snapshot.fontSize, 34)
  }

  func testOldProtocolsRejectSourceBeforeTheirPayloadProjectionCanDiscardIt() throws {
    let value = try source()
    let snapshot = value.applying(to: AppSettingsSnapshot())
    XCTAssertThrowsError(try TestConfigurationShare.link(for:
      .init(configuration: .words(17), settingsSnapshot: snapshot)))
    var configuration = TestConfiguration.words(17)
    configuration.rules = value.applying(to: configuration.rules)
    struct LegacyShare: Encodable { let version = 2; let preset: SavedTestPreset }
    let bytes = try encoder.encode(LegacyShare(preset: .init(configuration: configuration)))
    let token = bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    XCTAssertThrowsError(try TestConfigurationShare.preset(from: "typebar://test?preset=" + token))
    let archive = TypebarArchive(version: 33, exportedAt: Date(timeIntervalSince1970: 1_000),
      settings: snapshot, results: [], presets: [])
    XCTAssertThrowsError(try JSONEncoder().encode(archive))
    let document = TypebarSettingsDocument(version: 5, settings: snapshot, configuration: configuration,
      layoutFluidLayouts: [.ansiQwerty, .ansiDvorak],
      testParameterMemory: .init(duration: 30, wordLimit: 17,
        customTextDuration: 30, customTextWordLimit: 25, customTextSectionLimit: 5))
    XCTAssertThrowsError(try JSONEncoder().encode(document))
  }

  func testUnmigratedActiveStoreCannotOverwriteLegacySelectionBytes() throws {
    let suite = "typebar.threshold-source-gate.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = ActiveTestSelectionStore(defaults: defaults)
    let memory = TypebarTestParameterMemory(duration: 30, wordLimit: 17,
      customTextDuration: 30, customTextWordLimit: 25, customTextSectionLimit: 5)
    let legacy = ActiveTestSelectionDocument(preset: .init(configuration: .words(17)), testParameterMemory: memory)
    XCTAssertTrue(store.save(legacy))
    let before = defaults.data(forKey: ActiveTestSelectionStore.storageKey)
    var configuration = legacy.preset.configuration
    configuration.rules = try source().applying(to: configuration.rules)
    XCTAssertFalse(store.save(.init(version: 1, preset: .init(configuration: configuration), testParameterMemory: memory)))
    XCTAssertEqual(defaults.data(forKey: ActiveTestSelectionStore.storageKey), before)
  }

  func testPresentNullMalformedOrFutureSourceIsNeverTreatedAsMissing() throws {
    let capsule = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(source())) as? [String: Any])
    var future = capsule
    future["version"] = 2
    for invalid: Any in [NSNull(), [], future] {
      var rules = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(InputRules())) as? [String: Any])
      rules["thresholdSource"] = invalid
      XCTAssertThrowsError(try decoder.decode(InputRules.self, from: JSONSerialization.data(withJSONObject: rules)))
      var snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettingsSnapshot())) as? [String: Any])
      snapshot["thresholdSource"] = invalid
      XCTAssertThrowsError(try decoder.decode(AppSettingsSnapshot.self, from: JSONSerialization.data(withJSONObject: snapshot)))
    }
  }

  func testConflictingActiveProjectionIsRejectedRatherThanSilentlyReinterpreted() throws {
    let value = try source()
    var rules = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(value.applying(to: InputRules()))) as? [String: Any])
    rules["minimumWpm"] = 30
    XCTAssertThrowsError(try decoder.decode(InputRules.self, from: JSONSerialization.data(withJSONObject: rules)))
    var snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(value.applying(to: AppSettingsSnapshot()))) as? [String: Any])
    snapshot["minimumAccuracy"] = 99
    XCTAssertThrowsError(try decoder.decode(AppSettingsSnapshot.self, from: JSONSerialization.data(withJSONObject: snapshot)))
  }

  func testUnmigratedDecodersRejectEvenValidSourceAndLegacyDataStaysUnchanged() throws {
    let value = try source()
    XCTAssertThrowsError(try JSONDecoder().decode(PracticeThresholdSource.self, from: encoder.encode(value)))
    XCTAssertThrowsError(try JSONDecoder().decode(InputRules.self, from: encoder.encode(value.applying(to: InputRules()))))
    XCTAssertThrowsError(try JSONDecoder().decode(AppSettingsSnapshot.self, from: encoder.encode(value.applying(to: AppSettingsSnapshot()))))
    let legacy = InputRules(strictSpace: true, minimumWpm: 35, minimumWordBurstWpm: 60,
      minimumWordBurstMode: .flex)
    let bytes = try JSONEncoder().encode(legacy)
    XCTAssertEqual(try JSONDecoder().decode(InputRules.self, from: bytes), legacy)
    XCTAssertEqual(try decoder.decode(InputRules.self, from: bytes), legacy)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    XCTAssertNil(object["thresholdSource"])
  }

  private var memory: TypebarTestParameterMemory {
    .init(duration: 30, wordLimit: 17, customTextDuration: 30, customTextWordLimit: 25, customTextSectionLimit: 5)
  }
  private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(value)) as? [String: Any])
  }

  func testOuterLegacyProtocolsStillRejectWhenInnerModelCapabilityIsExplicitlyEnabled() throws {
    let snapshot = try source().applying(to: AppSettingsSnapshot())
    let archive = TypebarArchive(version: 33, exportedAt: Date(timeIntervalSince1970: 1_000), settings: snapshot, results: [], presets: [])
    XCTAssertThrowsError(try encoder.encode(archive))
    let document = TypebarSettingsDocument(version: 5, settings: snapshot, configuration: .words(17),
      layoutFluidLayouts: [.ansiQwerty, .ansiDvorak], testParameterMemory: memory)
    XCTAssertThrowsError(try encoder.encode(document))

    var rawArchive = try object(TypebarArchive(version: 33, exportedAt: Date(timeIntervalSince1970: 1_000),
      settings: .init(), results: [], presets: []))
    XCTAssertNoThrow(try decoder.decode(TypebarArchive.self, from: JSONSerialization.data(withJSONObject: rawArchive)))
    rawArchive["settings"] = try object(snapshot)
    XCTAssertThrowsError(try decoder.decode(TypebarArchive.self, from: JSONSerialization.data(withJSONObject: rawArchive)))
    var rawDocument = try object(TypebarSettingsDocument(version: 5, settings: .init(), configuration: .words(17),
      layoutFluidLayouts: [.ansiQwerty, .ansiDvorak], testParameterMemory: memory))
    XCTAssertNoThrow(try decoder.decode(TypebarSettingsDocument.self, from: JSONSerialization.data(withJSONObject: rawDocument)))
    rawDocument["settings"] = try object(snapshot)
    XCTAssertThrowsError(try decoder.decode(TypebarSettingsDocument.self, from: JSONSerialization.data(withJSONObject: rawDocument)))
  }

  func testActiveSelectionRejectsKnownSourceBeforeDiscardingItsSnapshot() throws {
    let sourceSnapshot = try source().applying(to: AppSettingsSnapshot())
    let active = ActiveTestSelectionDocument(version: 1, preset: .init(configuration: .words(17), settingsSnapshot: sourceSnapshot),
      testParameterMemory: memory)
    XCTAssertThrowsError(try encoder.encode(active))
    var payload = try object(ActiveTestSelectionDocument(preset: .init(configuration: .words(17)), testParameterMemory: memory))
    var preset = try XCTUnwrap(payload["preset"] as? [String: Any])
    preset["settingsSnapshot"] = try object(sourceSnapshot)
    payload["preset"] = preset
    XCTAssertThrowsError(try decoder.decode(ActiveTestSelectionDocument.self,
      from: JSONSerialization.data(withJSONObject: payload)))
  }

  func testArchiveRejectsSourceBeforeDeletedPresetsAndResultsAreFiltered() throws {
    let date = Date(timeIntervalSince1970: 1_000)
    let base = TypebarArchive(version: 33, exportedAt: date, settings: .init(), results: [], presets: [])
    let id = UUID()
    let preset = NamedPreset(id: id, name: "owned", definition: .init(configuration: .words(17),
      settingsSnapshot: try source().applying(to: AppSettingsSnapshot())))
    var payload = try object(base)
    payload["presets"] = [try object(preset)]
    payload["deletedPresetIDs"] = [id.uuidString]
    XCTAssertThrowsError(try decoder.decode(TypebarArchive.self, from: JSONSerialization.data(withJSONObject: payload)))

    var session = TypingSession(configuration: .words(1), prompt: "owned")
    session.insertBatch("ow", at: date)
    session.insertBatch("ned", at: date.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    var rawResult = try object(result)
    payload = try object(base)
    payload["results"] = [rawResult]
    payload["deletedResultIDs"] = [result.id.uuidString]
    XCTAssertNoThrow(try decoder.decode(TypebarArchive.self, from: JSONSerialization.data(withJSONObject: payload)))
    var configuration = try XCTUnwrap(rawResult["configuration"] as? [String: Any])
    configuration["rules"] = try object(source().applying(to: result.configuration.rules))
    rawResult["configuration"] = configuration
    payload["results"] = [rawResult]
    XCTAssertThrowsError(try decoder.decode(TypebarArchive.self, from: JSONSerialization.data(withJSONObject: payload)))
  }

  func testSourceBearingCarriersDoNotUseLegacyClampOrMissingProjectionDefaults() throws {
    let value = try source()
    let rawRules = try object(value.applying(to: InputRules()))
    let rawSnapshot = try object(value.applying(to: AppSettingsSnapshot()))
    for key in ["minimumWpm", "minimumAccuracy", "minimumWordBurstWpm"] {
      var rules = rawRules
      rules[key] = -1
      XCTAssertThrowsError(try decoder.decode(InputRules.self, from: JSONSerialization.data(withJSONObject: rules)), key)
      var snapshot = rawSnapshot
      snapshot[key] = -1
      XCTAssertThrowsError(try decoder.decode(AppSettingsSnapshot.self, from: JSONSerialization.data(withJSONObject: snapshot)), key)
    }
    for key in ["minimumWpm", "minimumAccuracy", "minimumWordBurstWpm", "minimumWordBurstMode"] {
      var rules = rawRules
      rules.removeValue(forKey: key)
      XCTAssertThrowsError(try decoder.decode(InputRules.self, from: JSONSerialization.data(withJSONObject: rules)), key)
      var snapshot = rawSnapshot
      snapshot.removeValue(forKey: key)
      XCTAssertThrowsError(try decoder.decode(AppSettingsSnapshot.self, from: JSONSerialization.data(withJSONObject: snapshot)), key)
    }
    XCTAssertEqual(try JSONDecoder().decode(InputRules.self, from: Data(#"{"minimumWpm":-1}"#.utf8)).minimumWpm, 0)
    XCTAssertEqual(try JSONDecoder().decode(AppSettingsSnapshot.self, from: Data(#"{"minimumWpm":-1}"#.utf8)).minimumWpm, 0)
  }
}
