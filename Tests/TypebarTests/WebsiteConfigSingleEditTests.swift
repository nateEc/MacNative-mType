import XCTest
@testable import Typebar

final class WebsiteConfigSingleEditTests: XCTestCase {
  @MainActor
  func testTypedEditPreservesFullRuntimeAndDoesNotClaimJSONImportEvidence() throws {
    let original = try WebsiteConfigNativeProfile.prepareDraft(
      #"{"mode":"words","words":123,"time":77,"fontSize":3,"minAccCustom":91,"customBackground":"\ud800","funbox":["rot13","rot13"]}"#,
      pointsPerRem: 18, context: .init())
    let edited = try WebsiteConfigNativeProfile.editDraft(original, key: "soundVolume", value: .number(0.3),
      pointsPerRem: 18, context: .init())
    var expected = original.projection.runtime
    expected["soundVolume"] = .number(0.3)
    XCTAssertEqual(edited.projection.runtime, expected)
    XCTAssertNotNil(original.prepared)
    XCTAssertNil(edited.prepared, "A setter is not evidence of a fresh JSON import")
    XCTAssertEqual(edited.projection.events.map(\.key), ["soundVolume"])
    XCTAssertEqual(edited.projection.events.first?.nosave, false)
    XCTAssertEqual(original.projection.runtime["soundVolume"], .number(0.5))
  }

  @MainActor
  func testRejectedTypedEditAndDependentNoQuitFailureLeaveOriginalDraftIntact() throws {
    let original = try WebsiteConfigNativeProfile.prepareDraft(
      #"{"funbox":["no_quit"],"stopOnError":"word"}"#, pointsPerRem: 16, context: .init())
    let before = original.projection.runtime
    XCTAssertThrowsError(try WebsiteConfigNativeProfile.editDraft(original, key: "words", value: .number(100),
      pointsPerRem: 16, context: .init(), testActive: true))
    XCTAssertThrowsError(try WebsiteConfigNativeProfile.editDraft(original, key: "confidenceMode", value: .string("on"),
      pointsPerRem: 16, context: .init(), testActive: true)) {
      guard case WebsiteConfigProjectionError.failedOverride = $0 else { return XCTFail("Expected dependent setter failure, got \($0)") }
    }
    XCTAssertEqual(original.projection.runtime, before)
    let allowed = try WebsiteConfigNativeProfile.editDraft(original, key: "soundVolume", value: .number(0.1),
      pointsPerRem: 16, context: .init(), testActive: true, nosave: true)
    XCTAssertEqual(allowed.projection.runtime["soundVolume"], .number(0.1))
    XCTAssertEqual(allowed.projection.events.first?.nosave, true)
  }

  @MainActor
  func testSequentialParameterEditsRetainDormantLimitsAndRejectInvalidProposals() throws {
    let defaults = try WebsiteConfigNativeProfile.defaultDocument().values
    let schema = WebsiteConfigSchema(catalogs: WebsiteConfigNativeProfile.catalogs)
    var runtime = defaults
    for (key, value, expectedMode) in [("words", WebsiteConfigValue.number(123), "words"),
      ("time", .number(77), "time"), ("quoteLength", .array([.number(0), .number(0), .number(2)]), "quote")] {
      let edited = try WebsiteConfigRuntimeProjector.edit(current: runtime, key: key, value: value,
        defaults: defaults, schema: schema, context: .init())
      XCTAssertEqual(edited.runtime["mode"], .string(expectedMode))
      XCTAssertEqual(edited.events.last?.key, key)
      runtime = edited.runtime
    }
    XCTAssertEqual(runtime["words"], .number(123))
    XCTAssertEqual(runtime["time"], .number(77))
    XCTAssertEqual(runtime["quoteLength"], .array([.number(0), .number(0), .number(2)]))
    let rejected = try WebsiteConfigRuntimeProjector.edit(current: runtime, key: "words", value: .bool(true),
      defaults: defaults, schema: schema, context: .init())
    XCTAssertEqual(rejected.runtime, runtime)
    XCTAssertEqual(rejected.rejectedKeys, ["words"])
    XCTAssertTrue(rejected.events.isEmpty)
    XCTAssertThrowsError(try WebsiteConfigRuntimeProjector.edit(current: runtime, key: "future", value: .bool(true),
      defaults: defaults, schema: schema, context: .init()))
    runtime.removeValue(forKey: "time")
    XCTAssertThrowsError(try WebsiteConfigRuntimeProjector.edit(current: runtime, key: "words", value: .number(1),
      defaults: defaults, schema: schema, context: .init()))
  }

  func testPinnedSingleEditsPreserveCurrentStateAndSetterEvents() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let reference = environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct Catalogs: Decodable {
      var languages: Set<String>, themes: Set<String>, layouts: Set<String>, fonts: Set<String>, funboxes: Set<String>
    }
    struct Fixture: Decodable {
      var key: String, value: WebsiteConfigValue, current: [String: WebsiteConfigValue]
      var flags: WebsiteConfigRuntimeContext, nosave: Bool, accepted: Bool
      var runtime: [String: WebsiteConfigValue], events: [WebsiteConfigApplicationEvent], saves: [String]
      struct Activity: Decodable { var testActive: Bool }
    }
    struct Output: Decodable {
      var defaults: [String: WebsiteConfigValue], catalogs: Catalogs, fixtures: [Fixture], restartKeys: Set<String>
    }
    // Activity is intentionally separate from environment/authentication context.
    struct Activities: Decodable { struct Item: Decodable { var flags: Fixture.Activity }; var fixtures: [Item] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-config-schema.mjs").path,
      reference, "--single-edit"]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    let activities = try JSONDecoder().decode(Activities.self, from: data)
    let schema = WebsiteConfigSchema(catalogs: .init(languages: output.catalogs.languages, themes: output.catalogs.themes,
      layouts: output.catalogs.layouts, fonts: output.catalogs.fonts, funboxes: output.catalogs.funboxes))
    XCTAssertEqual(WebsiteConfigRuntimeProjector.restartRequiredKeys, output.restartKeys)
    XCTAssertGreaterThan(output.fixtures.count, 1_000)
    for (index, fixture) in output.fixtures.enumerated() {
      let result = try WebsiteConfigRuntimeProjector.edit(current: fixture.current, key: fixture.key, value: fixture.value,
        defaults: output.defaults, schema: schema, context: fixture.flags,
        testActive: activities.fixtures[index].flags.testActive, nosave: fixture.nosave)
      XCTAssertEqual(result.runtime, fixture.runtime, "runtime \(index): \(fixture.key)")
      XCTAssertEqual(result.events, fixture.events, "events \(index): \(fixture.key)")
      XCTAssertEqual(result.rejectedKeys, fixture.accepted ? [] : [fixture.key], "admission \(index)")
      XCTAssertEqual(result.events.filter { $0.nosave == false }.map(\.key), fixture.saves, "save intentions \(index)")
      XCTAssertFalse(result.events.contains { $0.key == "fullConfigChange" || $0.key == "fullConfigChangeFinished" })
    }
  }
}
