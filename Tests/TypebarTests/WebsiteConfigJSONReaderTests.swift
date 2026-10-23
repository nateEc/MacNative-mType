import XCTest
@testable import Typebar

final class WebsiteConfigJSONReaderTests: XCTestCase {
  func testEveryLoneSurrogateAndExactObjectKeysSurviveTransport() throws {
    for unit in UInt16(0xD800)...UInt16(0xDFFF) {
      let escaped = String(format: "\\u%04x", unit)
      let value = try WebsiteConfigJSONReader.read("\"\(escaped)\"")
      XCTAssertEqual(value.stringUnits, [unit])
      XCTAssertNotEqual(value, .string("\u{FFFD}"))
      XCTAssertEqual(try WebsiteConfigJSONReader.read(WebsiteConfigJSONWriter.write(value)), value)
      XCTAssertThrowsError(try JSONEncoder().encode(value))
      let object = try WebsiteConfigJSONReader.read("{\"\(escaped)\":1,\"\(escaped)\":2}")
      XCTAssertEqual(object.objectMembers, [.init(key: [unit], value: .number(2))])
      XCTAssertEqual(try WebsiteConfigJSONReader.read(WebsiteConfigJSONWriter.write(object)), object)
    }
    let distinct = try WebsiteConfigJSONReader.read("{\"é\":1,\"e\\u0301\":2}")
    XCTAssertEqual(distinct.objectMembers?.count, 2)
    XCTAssertEqual(try WebsiteConfigJSONReader.read(WebsiteConfigJSONWriter.write(distinct)), distinct)
    XCTAssertThrowsError(try JSONEncoder().encode(distinct))
    let pair = try WebsiteConfigJSONReader.read("\"\\ud800\\udc00\"")
    XCTAssertEqual(pair.stringUnits, [0xD800, 0xDC00])
    XCTAssertNoThrow(try JSONEncoder().encode(pair))
  }

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

  func testResourceBoundsRemainExplicitWhileUnicodeValuesAreAccepted() throws {
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
    XCTAssertNoThrow(try WebsiteConfigJSONReader.read("\"\\uD800\""))
    XCTAssertNoThrow(try WebsiteConfigJSONReader.read("{\"é\":1,\"e\\u0301\":2}"))
  }

  func testJSONIntrinsicDifferentialAndLosslessUTF16Transport() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let reference = environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] ?? environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct Fixture: Decodable {
      var json: String, accepted: Bool, value: WebsiteConfigValue?, roundTrip: WebsiteConfigValue?, unsupported: String?
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
    print("Website JSON intrinsic comparison: \(fixtures.count) fixtures; former UTF-16/key gaps must now match")
    for (index, fixture) in fixtures.enumerated() {
      if fixture.accepted {
        let parsed = try WebsiteConfigJSONReader.read(fixture.json)
        XCTAssertEqual(describe(parsed), fixture.value, "fixture \(index)")
        XCTAssertEqual(describe(try WebsiteConfigJSONReader.read(WebsiteConfigJSONWriter.write(parsed))), fixture.roundTrip, "round trip \(index)")
      } else { XCTAssertThrowsError(try WebsiteConfigJSONReader.read(fixture.json), "fixture \(index)") }
    }
  }

  private func describe(_ value: WebsiteConfigValue) -> WebsiteConfigValue {
    if let units = value.stringUnits { return .object(["string": .array(units.map { .number(Double($0)) })]) }
    if let members = value.objectMembers {
      let sorted = members.sorted { $0.key.lexicographicallyPrecedes($1.key) }
      return .object(["object": .array(sorted.map { .array([.array($0.key.map { .number(Double($0)) }), describe($0.value)]) })])
    }
    switch value {
    case .null: return .object(["null": .bool(true)])
    case .bool: return value
    case .number(let number):
      let bits = String(number.bitPattern, radix: 16)
      return .object(["number": .string(String(repeating: "0", count: 16 - bits.count) + bits)])
    case .array(let values): return .array(values.map(describe))
    default: preconditionFailure("Strings and objects handled above")
    }
  }
}
