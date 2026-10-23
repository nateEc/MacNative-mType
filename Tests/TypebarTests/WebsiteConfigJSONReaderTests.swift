import XCTest
@testable import Typebar

final class WebsiteConfigJSONReaderTests: XCTestCase {
  func testStrictGrammarDuplicateKeysAndNumericRepresentations() throws {
    for json in ["[1,]", "{\"a\":1,}", "{}{}", "01", "+1", "1.", "1e+", "/*x*/{}", "\u{FEFF}{}"] {
      XCTAssertThrowsError(try WebsiteConfigJSONReader.read(json), json)
    }
    let object = try MonkeytypeLegacyConfigMigration.decodeObject("{\"numbers\":false,\"numbers\":true,\"fontSize\":1e400,\"words\":-0}")
    XCTAssertEqual(object["numbers"], .bool(true))
    XCTAssertEqual(object["fontSize"], .number(.infinity))
    guard case .number(let zero) = object["words"] else { return XCTFail("Expected numeric negative zero") }
    XCTAssertEqual(zero.sign, .minus)
    XCTAssertNotEqual(WebsiteConfigValue.string("é"), .string("e\u{0301}"))
    XCTAssertNotEqual(WebsiteConfigValue.object(["é": .null]), .object(["e\u{0301}": .null]))
  }

  func testResourceAndUnrepresentableUnicodeBoundsAreExplicit() throws {
    let atLimit = "\"" + String(repeating: "x", count: WebsiteConfigJSONReader.maximumBytes - 2) + "\""
    XCTAssertNoThrow(try WebsiteConfigJSONReader.read(atLimit))
    XCTAssertThrowsError(try WebsiteConfigJSONReader.read(String(repeating: " ", count: WebsiteConfigJSONReader.maximumBytes + 1))) {
      XCTAssertEqual($0 as? WebsiteConfigJSONReadError, .tooLarge)
    }
    let depth = WebsiteConfigJSONReader.maximumDepth
    XCTAssertNoThrow(try WebsiteConfigJSONReader.read(String(repeating: "[", count: depth) + "0" + String(repeating: "]", count: depth)))
    XCTAssertThrowsError(try WebsiteConfigJSONReader.read(String(repeating: "[", count: depth + 1) + "0" + String(repeating: "]", count: depth + 1))) {
      XCTAssertEqual($0 as? WebsiteConfigJSONReadError, .tooDeep)
    }
    XCTAssertThrowsError(try WebsiteConfigJSONReader.read("\"\\uD800\"")) {
      XCTAssertEqual($0 as? WebsiteConfigJSONReadError, .unsupportedUTF16)
    }
    XCTAssertThrowsError(try WebsiteConfigJSONReader.read("{\"é\":1,\"e\\u0301\":2}")) {
      XCTAssertEqual($0 as? WebsiteConfigJSONReadError, .ambiguousObjectKey)
    }
  }

  func testJSONIntrinsicDifferentialIncludingExplicitRemainingUTF16Gaps() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let reference = environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] ?? environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct Fixture: Decodable {
      var json: String, accepted: Bool, value: WebsiteConfigValue?, unsupported: String?
    }
    struct Output: Decodable { var fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-website-json-reader.mjs").path, reference]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 1342)
    XCTAssertEqual(fixtures.filter { $0.unsupported != nil }.count, 4)
    print("Website JSON intrinsic comparison: \(fixtures.count) fixtures; four explicit remaining UTF-16/key gaps")
    for (index, fixture) in fixtures.enumerated() {
      if let unsupported = fixture.unsupported {
        XCTAssertTrue(fixture.accepted, "Known gap must be accepted by the reference")
        XCTAssertThrowsError(try WebsiteConfigJSONReader.read(fixture.json)) {
          XCTAssertEqual($0 as? WebsiteConfigJSONReadError, unsupported == "utf16" ? .unsupportedUTF16 : .ambiguousObjectKey)
        }
      } else if fixture.accepted {
        XCTAssertEqual(describe(try WebsiteConfigJSONReader.read(fixture.json)), fixture.value, "fixture \(index)")
      } else { XCTAssertThrowsError(try WebsiteConfigJSONReader.read(fixture.json), "fixture \(index)") }
    }
  }

  private func describe(_ value: WebsiteConfigValue) -> WebsiteConfigValue {
    switch value {
    case .null: return .object(["null": .bool(true)])
    case .bool: return value
    case .number(let number):
      let bits = String(number.bitPattern, radix: 16)
      return .object(["number": .string(String(repeating: "0", count: 16 - bits.count) + bits)])
    case .string(let string): return .object(["string": units(string)])
    case .array(let values): return .array(values.map(describe))
    case .object(let object):
      let keys = object.keys.sorted { Array($0.utf16).lexicographicallyPrecedes(Array($1.utf16)) }
      return .object(["object": .array(keys.map { .array([units($0), describe(object[$0]!)]) })])
    }
  }
  private func units(_ string: String) -> WebsiteConfigValue { .array(string.utf16.map { .number(Double($0)) }) }
}
