import XCTest
@testable import Typebar

final class ThresholdShareTests: XCTestCase {
  private func preset() throws -> SavedTestPreset {
    var raw = PracticeThresholdConfiguration()
    try raw.apply(.minimumWpm(mode: .off, customValue: 37))
    try raw.apply(.minimumWordBurst(mode: .flex, customValue: 0))
    let source = PracticeThresholdSource(configuration: raw)
    var configuration = TestConfiguration.words(17)
    configuration.rules = source.applying(to: configuration.rules)
    return .init(configuration: configuration, activeResultTags: ["private-tag"],
      settingsSnapshot: source.applying(to: .init(fontSize: 31)), settingGroups: [.behavior])
  }
  private func data(_ link: String) throws -> Data {
    var token = try XCTUnwrap(URLComponents(string: link)?.queryItems?.first?.value)
      .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    token += String(repeating: "=", count: (4 - token.count % 4) % 4)
    return try XCTUnwrap(Data(base64Encoded: token))
  }
  private func link(_ object: [String: Any]) throws -> String {
    let token = try JSONSerialization.data(withJSONObject: object).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    return "typebar://test?preset=" + token
  }

  func testSourceLinkPreservesMemoryAndZeroModeButNotLocalScopeOrSettings() throws {
    let expected = try preset()
    let link = try TestConfigurationShare.link(for: expected)
    let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data(link)) as? [String: Any])
    XCTAssertEqual(root["version"] as? Int, 3)
    XCTAssertNil(root["preset"])
    XCTAssertNotNil(root["selectionData"] as? String)
    let decoded = try TestConfigurationShare.preset(from: link)
    XCTAssertEqual(decoded.configuration, expected.configuration)
    XCTAssertNil(decoded.activeResultTags)
    XCTAssertNil(decoded.settingsSnapshot)
    XCTAssertNil(decoded.settingGroups)
    struct OldPayload: Decodable { let version: Int; let preset: SavedTestPreset }
    XCTAssertThrowsError(try JSONDecoder().decode(OldPayload.self, from: data(link)))
  }

  func testLegacyLinkVersionStaysTwoAndOldVersionOneRemainsReadable() throws {
    let expected = SavedTestPreset(configuration: .words(25))
    let original = try TestConfigurationShare.link(for: expected)
    var root = try XCTUnwrap(JSONSerialization.jsonObject(with: data(original)) as? [String: Any])
    XCTAssertEqual(root["version"] as? Int, 2)
    root["version"] = 1
    XCTAssertEqual(try TestConfigurationShare.preset(from: link(root)), expected)
  }

  func testDowngradedFutureMixedOrDamagedPayloadDoesNotFallBack() throws {
    let sourceLink = try TestConfigurationShare.link(for: preset())
    let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data(sourceLink)) as? [String: Any])
    for version in [1, 2, 4] {
      var invalid = root
      invalid["version"] = version
      XCTAssertThrowsError(try TestConfigurationShare.preset(from: link(invalid)))
    }
    var invalid = root
    invalid["preset"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(SavedTestPreset(configuration: .words(25))))
    XCTAssertThrowsError(try TestConfigurationShare.preset(from: link(invalid)))
    invalid = root
    invalid["selectionData"] = Data("{".utf8).base64EncodedString()
    XCTAssertThrowsError(try TestConfigurationShare.preset(from: link(invalid)))
    invalid = root
    invalid.removeValue(forKey: "selectionData")
    XCTAssertThrowsError(try TestConfigurationShare.preset(from: link(invalid)))
  }

  @MainActor
  func testSourceLinkApplicationIsRejectedBeforeCallbackUntilSettingsMigration() throws {
    let link = try TestConfigurationShare.link(for: preset())
    let center = LocalNoticeCenter()
    defer { center.clearAll() }
    var calls = 0
    let outcome = TestConfigurationShareActions.apply(link, current: .init(configuration: .words(25)),
      challenges: [], notices: center, applyPreset: { value in calls += 1; return value },
      loadChallenge: { _ in .applied })
    XCTAssertEqual(outcome.outcome, .rejected)
    XCTAssertFalse(outcome.shouldDismiss)
    XCTAssertEqual(calls, 0)
    XCTAssertEqual(outcome.status, TestConfigurationShareError.thresholdSourceNotReady.errorDescription)
    XCTAssertFalse(outcome.status?.contains(link) ?? true)
  }

  func testOriginalCarriersAreValidatedBeforeGlobalSnapshotIsRemoved() throws {
    var invalid = try preset()
    var raw = try XCTUnwrap(invalid.settingsSnapshot?.thresholdSource?.configuration)
    try raw.apply(.minimumWpm(mode: .off, customValue: 75))
    invalid.settingsSnapshot = PracticeThresholdSource(configuration: raw).applying(to: .init())
    XCTAssertThrowsError(try TestConfigurationShare.link(for: invalid))
    invalid = try preset()
    invalid.configuration.rules.thresholdSource = nil
    XCTAssertThrowsError(try TestConfigurationShare.link(for: invalid))
    invalid = try preset()
    invalid.configuration.rules.minimumWpm = 99
    XCTAssertThrowsError(try TestConfigurationShare.link(for: invalid))
  }

  func testIncomingSourcePayloadRejectsLocalMetadataAndFutureCapsules() throws {
    let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data(TestConfigurationShare.link(for: preset()))) as? [String: Any])
    let bytes = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(root["selectionData"] as? String)))
    let selection = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    for (key, value): (String, Any) in [("settingsSnapshot", ["fontSize": 31]),
      ("activeResultTags", ["private-tag"]), ("settingGroups", ["appearance"])] {
      var inner = selection
      inner[key] = value
      var invalid = root
      invalid["selectionData"] = try JSONSerialization.data(withJSONObject: inner).base64EncodedString()
      XCTAssertThrowsError(try TestConfigurationShare.preset(from: link(invalid)))
    }
    var inner = selection
    var configuration = try XCTUnwrap(inner["configuration"] as? [String: Any])
    var rules = try XCTUnwrap(configuration["rules"] as? [String: Any])
    var capsule = try XCTUnwrap(rules["thresholdSource"] as? [String: Any])
    capsule["version"] = 2
    rules["thresholdSource"] = capsule
    configuration["rules"] = rules
    inner["configuration"] = configuration
    var invalid = root
    invalid["selectionData"] = try JSONSerialization.data(withJSONObject: inner).base64EncodedString()
    XCTAssertThrowsError(try TestConfigurationShare.preset(from: link(invalid)))
    invalid["version"] = 4
    XCTAssertThrowsError(try TestConfigurationShare.preset(from: link(invalid))) {
      XCTAssertEqual($0 as? TestConfigurationShareError, .unsupportedVersion(4))
    }
    invalid = root
    invalid["selectionData"] = try JSONEncoder().encode(SavedTestPreset(configuration: .words(25))).base64EncodedString()
    XCTAssertThrowsError(try TestConfigurationShare.preset(from: link(invalid)))
  }
}
