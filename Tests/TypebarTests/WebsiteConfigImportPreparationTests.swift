import XCTest
@testable import Typebar

final class WebsiteConfigImportPreparationTests: XCTestCase {
  private func prepare(_ json: String, defaults: [String: WebsiteConfigValue], orderedKeys: [String],
    schema: WebsiteConfigSchema, context: WebsiteConfigRuntimeContext) throws -> WebsiteConfigPreparedImport {
    try WebsiteConfigImportPreparation.prepare(json, defaults: defaults, orderedKeys: orderedKeys, schema: schema, context: context)
  }

  func testPinnedCompleteJSONImportEntryAndRuntimeProjection() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let reference = environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] ?? environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    guard environment["TYPEBAR_WEBSITE_CONFIG_ZOD_ROOT"] != nil else { return XCTFail("Requires pinned Zod") }
    struct Catalogs: Decodable {
      var languages: Set<String>, themes: Set<String>, layouts: Set<String>, fonts: Set<String>, funboxes: Set<String>
    }
    struct Fixture: Decodable {
      var json: String, flags: WebsiteConfigRuntimeContext, accepted: Bool
      var parsed: [String: WebsiteConfigValue]?, requested: [String: WebsiteConfigValue]?
      var runtime: [String: WebsiteConfigValue], rejectedKeys: [String], events: [WebsiteConfigApplicationEvent]
    }
    struct Output: Decodable {
      var defaults: [String: WebsiteConfigValue], catalogs: Catalogs, orderedKeys: [String], fixtures: [Fixture]
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-config-schema.mjs").path,
      reference, "--import-preparation"]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    let schema = WebsiteConfigSchema(catalogs: .init(languages: output.catalogs.languages,
      themes: output.catalogs.themes, layouts: output.catalogs.layouts, fonts: output.catalogs.fonts, funboxes: output.catalogs.funboxes))
    XCTAssertEqual(output.fixtures.count, 403)
    print("Pinned complete website JSON import comparison: \(output.fixtures.count) fixtures")
    for (index, fixture) in output.fixtures.enumerated() {
      if !fixture.accepted {
        XCTAssertThrowsError(try prepare(fixture.json, defaults: output.defaults, orderedKeys: output.orderedKeys,
          schema: schema, context: fixture.flags), "fixture \(index)")
        continue
      }
      let prepared = try prepare(fixture.json, defaults: output.defaults, orderedKeys: output.orderedKeys,
        schema: schema, context: fixture.flags)
      assertFields(prepared.parsed, (fixture.parsed ?? [:]).mapValues(restore), "parsed \(index)")
      let projected = prepared.projection
      if fixture.json == "{\"quickTab\":true}" {
        XCTAssertTrue(prepared.parsed.isEmpty, "A valid partial import strips the legacy alias before migration")
        XCTAssertEqual(projected.requested["quickRestart"], output.defaults["quickRestart"])
      }
      if fixture.json == "{\"quickTab\":true,\"numbers\":\"invalid\"}" {
        XCTAssertEqual(Set(prepared.parsed.keys), schema.keys)
        XCTAssertEqual(projected.requested["quickRestart"], .string("tab"))
      }
      assertFields(projected.requested, (fixture.requested ?? [:]).mapValues(restore), "requested \(index)")
      assertFields(projected.runtime, fixture.runtime.mapValues(restore), "runtime \(index)")
      XCTAssertEqual(projected.rejectedKeys, fixture.rejectedKeys, "rejected \(index)")
      XCTAssertEqual(projected.events.count, fixture.events.count, "events \(index)")
      let events = fixture.events.map { event in
        var restored = event
        restored.previousValue = event.previousValue.map(restore)
        restored.newValue = event.newValue.map(restore)
        return restored
      }
      if let mismatch = zip(projected.events, events).first(where: { $0 != $1 }) {
        XCTFail("event \(index): \(mismatch.0.key) != \(mismatch.1.key)")
      }
    }
  }

  func testPartialValidationStripsUnknownKeysWithoutMigratingOrMutatingInput() {
    let schema = WebsiteConfigSchema(catalogs: .init(languages: [], themes: [], layouts: [], fonts: [], funboxes: []))
    let input: [String: WebsiteConfigValue] = ["numbers": .bool(false), "quickTab": .bool(true), "ownedUnknown": .array([.null])]
    XCTAssertEqual(schema.validatingPartial(input), ["numbers": .bool(false)])
    XCTAssertEqual(input["quickTab"], .bool(true))
    XCTAssertEqual(input["ownedUnknown"], .array([.null]))
    XCTAssertNil(schema.validatingPartial(["numbers": .string("invalid"), "quickTab": .bool(true)]))
  }

  private func assertFields(_ actual: [String: WebsiteConfigValue], _ expected: [String: WebsiteConfigValue], _ label: String) {
    XCTAssertEqual(Set(actual.keys), Set(expected.keys), label)
    for key in expected.keys { XCTAssertEqual(actual[key], expected[key], "\(label).\(key)") }
  }

  private func restore(_ value: WebsiteConfigValue) -> WebsiteConfigValue {
    switch value {
    case .object(let object):
      if object.count == 1, case .array(let units) = object["$probeUTF16"] {
        return .string(units: units.map {
          guard case .number(let unit) = $0 else { preconditionFailure("Invalid probe unit") }
          return UInt16(unit)
        })
      }
      if object.count == 1, case .string(let number) = object["$probeNumber"] {
        if number == "Infinity" { return .number(.infinity) }
        if number == "-Infinity" { return .number(-.infinity) }
        if number == "NaN" { return .number(.nan) }
      }
      return .object(object.mapValues(restore))
    case .array(let values): return .array(values.map(restore))
    default: return value
    }
  }
}
