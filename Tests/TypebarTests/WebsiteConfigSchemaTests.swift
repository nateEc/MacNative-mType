import XCTest
@testable import Typebar

final class WebsiteConfigSchemaTests: XCTestCase {
  func testPinnedSchemaSanitizerAndMigration() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let reference = environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] ?? environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    guard environment["TYPEBAR_WEBSITE_CONFIG_ZOD_ROOT"] != nil else {
      return XCTFail("Prepare Zod with Scripts/prepare-website-config-schema-qa.sh and set TYPEBAR_WEBSITE_CONFIG_ZOD_ROOT")
    }
    struct Catalogs: Decodable {
      var languages: Set<String>, themes: Set<String>, layouts: Set<String>, fonts: Set<String>, funboxes: Set<String>
    }
    struct Fixture: Decodable {
      var input: [String: WebsiteConfigValue]
      var sanitized: [String: WebsiteConfigValue]
      var merged: [String: WebsiteConfigValue]
    }
    struct Output: Decodable {
      var defaults: [String: WebsiteConfigValue]
      var catalogs: Catalogs
      var fixtures: [Fixture]
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules",
      root.appendingPathComponent("Scripts/check-source-config-schema.mjs").path, reference]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    let schema = WebsiteConfigSchema(catalogs: .init(languages: output.catalogs.languages,
      themes: output.catalogs.themes, layouts: output.catalogs.layouts, fonts: output.catalogs.fonts,
      funboxes: output.catalogs.funboxes))
    XCTAssertEqual(schema.keys, Set(output.defaults.keys))
    XCTAssertEqual(output.fixtures.count, 5705)
    for (index, fixture) in output.fixtures.enumerated() {
      let input = fixture.input.mapValues(restore)
      assertFields(try schema.sanitize(input), fixture.sanitized.mapValues(restore), "sanitize \(index): \(input)")
      assertFields(try schema.migrating(input, defaults: output.defaults), fixture.merged.mapValues(restore),
        "migrate \(index): \(input)")
    }
    XCTAssertThrowsError(try schema.migrating([:], defaults: [:]))
    var invalidDefaults = output.defaults
    invalidDefaults["fontSize"] = .null
    XCTAssertThrowsError(try schema.migrating([:], defaults: invalidDefaults))
  }

  private func assertFields(_ actual: [String: WebsiteConfigValue],
    _ expected: [String: WebsiteConfigValue], _ context: String,
    file: StaticString = #filePath, line: UInt = #line) {
    let differing = Set(actual.keys).union(expected.keys).filter { actual[$0] != expected[$0] }.sorted()
    XCTAssertTrue(differing.isEmpty, "\(context); differing fields: \(differing)", file: file, line: line)
  }

  func testArrayRepairDistinguishesEmptyAllInvalidAndSecondPassRejection() throws {
    let schema = WebsiteConfigSchema(catalogs: .init(languages: ["a", "b"], themes: ["desk"],
      layouts: ["q"], fonts: [], funboxes: ["known"]))
    XCTAssertEqual(try schema.sanitize(["quoteLength": .array([])]), ["quoteLength": .array([])])
    XCTAssertEqual(try schema.sanitize(["quoteLength": .array([.string("bad")])]), [:])
    XCTAssertEqual(try schema.sanitize(["customPolyglot": .array([.string("a"), .string("bad")])]), [:])
    XCTAssertEqual(try schema.sanitize(["customPolyglot": .array([.string("a"), .string("b"), .string("bad")])]),
      ["customPolyglot": .array([.string("a"), .string("b")])])
    XCTAssertEqual(try schema.sanitize(["funbox": .array(Array(repeating: .string("known"), count: 16))]), [:])
    XCTAssertEqual(try schema.sanitize(["accountChart": .array([.string("on"), .string("bad"), .string("on"), .string("on")])]), [:])
    let values = try schema.sanitize(["fontSize": .number(.infinity), "words": .number(.infinity),
      "soundVolume": .number(.infinity), "customBackgroundFilter": .array([.number(.infinity), .number(0), .number(1), .number(1)])])
    XCTAssertEqual(values["fontSize"], .number(.infinity))
    XCTAssertNotNil(values["customBackgroundFilter"])
    XCTAssertNil(values["words"])
    XCTAssertNil(values["soundVolume"])
  }

  private func restore(_ value: WebsiteConfigValue) -> WebsiteConfigValue {
    switch value {
    case .object(let values) where values.count == 1 && values["$probeNumber"] != nil:
      switch values["$probeNumber"] {
      case .string("Infinity"): .number(.infinity)
      case .string("-Infinity"): .number(-.infinity)
      default: .number(.nan)
      }
    case .object(let values): .object(values.mapValues(restore))
    case .array(let values): .array(values.map(restore))
    default: value
    }
  }
}
