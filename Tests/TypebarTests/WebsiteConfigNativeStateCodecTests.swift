import XCTest
@testable import Typebar

final class WebsiteConfigNativeStateCodecTests: XCTestCase {
  @MainActor
  static func assertRoundTrip(_ runtime: [String: WebsiteConfigValue]) throws {
    let decoded = try WebsiteConfigNativeStateCodec.decode(WebsiteConfigNativeStateCodec.encode(runtime))
    XCTAssertEqual(decoded, runtime)
    func bits(_ a: WebsiteConfigValue, _ b: WebsiteConfigValue) {
      switch (a, b) {
      case (.number(let a), .number(let b)): XCTAssertEqual(a.bitPattern, b.bitPattern)
      case (.array(let a), .array(let b)):
        XCTAssertEqual(a.count, b.count)
        for (a, b) in zip(a, b) { bits(a, b) }
      default: XCTAssertEqual(a, b)
      }
    }
    for (key, value) in runtime { bits(value, try XCTUnwrap(decoded[key])) }
  }

  @MainActor
  func testEverySurrogateUnitAndDeterministicDoublePatternsSurvive() throws {
    var runtime = try WebsiteConfigNativeProfile.prepare("{}", context: .init()).projection.runtime
    for start in stride(from: 0xD800, through: 0xDFFF, by: 512) {
      let units = Array("https://example.com/".utf16) + (start..<(start + 512)).map(UInt16.init) + Array(".png".utf16)
      runtime["customBackground"] = .string(units: units)
      try Self.assertRoundTrip(runtime)
    }
    runtime["customBackground"] = .string("https://example.com/é/e\u{301}.png")
    var seed: UInt64 = 0x87bb42ce90476015
    let special: [Double] = [-0.0, .infinity, -.infinity, .leastNonzeroMagnitude, -.leastNonzeroMagnitude, .greatestFiniteMagnitude]
    for index in 0..<512 {
      seed = seed &* 6364136223846793005 &+ 1442695040888963407
      let number = index < special.count ? special[index] : Double(bitPattern: seed)
      if number.isNaN { continue }
      runtime["customBackgroundFilter"] = .array([.number(number), .number(1), .number(-0.0), .number(1)])
      try Self.assertRoundTrip(runtime)
    }
  }

  @MainActor
  func testExpandedNativeBudgetDoesNotWidenWebsiteInputLimit() throws {
    var runtime = try WebsiteConfigNativeProfile.prepare("{}", context: .init()).projection.runtime
    runtime["favThemes"] = .array(Array(repeating: .string("serika_dark"), count: 25_000))
    let data = try WebsiteConfigNativeStateCodec.encode(runtime)
    XCTAssertGreaterThan(data.count, WebsiteConfigJSONReader.maximumBytes)
    XCTAssertLessThan(data.count, WebsiteConfigNativeStateCodec.maximumBytes)
    XCTAssertThrowsError(try WebsiteConfigJSONReader.read(String(decoding: data, as: UTF8.self))) {
      XCTAssertEqual($0 as? WebsiteConfigJSONReadError, .tooLarge)
    }
    XCTAssertEqual(try WebsiteConfigNativeStateCodec.decode(data), runtime)
    XCTAssertThrowsError(try WebsiteConfigNativeStateCodec.decode(Data(repeating: 32, count: WebsiteConfigNativeStateCodec.maximumBytes + 1)))
  }

  @MainActor
  func testStrictEnvelopeFieldAndValueAdmissionNeverDefaults() throws {
    let runtime = try WebsiteConfigNativeProfile.prepare("{}", context: .init()).projection.runtime
    let valid = try WebsiteConfigNativeStateCodec.encode(runtime)
    let text = String(decoding: valid, as: UTF8.self)
    guard case .array(let original) = try WebsiteConfigJSONReader.read(text),
      case .array(let fields) = original[2] else { return XCTFail("Missing native envelope") }
    func check(_ root: [WebsiteConfigValue]) {
      XCTAssertThrowsError(try WebsiteConfigNativeStateCodec.decode(Data(WebsiteConfigJSONWriter.write(.array(root)).utf8)))
    }
    var changed = original; changed[1] = .number(2); check(changed)
    changed = original; changed.append(.null); check(changed)
    changed = original; changed[0] = .string("typebar.other"); check(changed)
    changed = original; changed[2] = .array(Array(fields.dropLast())); check(changed)
    changed = original; changed[2] = .array(fields + [fields[0]]); check(changed)
    var duplicate = fields; duplicate[1] = duplicate[0]
    changed = original; changed[2] = .array(duplicate); check(changed)
    for name in ["future", "showKeyTips"] {
      var modified = fields
      guard case .array(var pair) = modified[0] else { return XCTFail("Missing field pair") }
      pair[0] = .string(name); modified[0] = .array(pair)
      changed = original; changed[2] = .array(modified); check(changed)
    }
    func field(_ key: String, _ value: WebsiteConfigValue) throws {
      var modified = fields
      let index = try XCTUnwrap(modified.firstIndex { if case .array(let pair) = $0 { return pair[0] == .string(key) }; return false })
      modified[index] = .array([.string(key), value])
      var root = original; root[2] = .array(modified); check(root)
    }
    for bits in ["0", "000000000000000g", "7FF0000000000000", "7ff8000000000000"] {
      try field("paceCaretCustomSpeed", .array([.string("n"), .string(bits)]))
    }
    try field("numbers", .array([.string("b"), .number(1)]))
    try field("theme", .array([.string("s"), .string("zzzz")]))
    try field("theme", .array([.string("s"), .string("0")]))
    try field("theme", .array([.string("future"), .string("serika")]))
    try field("favThemes", .array([.string("a"), .array([.array([.string("a"), .array([])])])]))
    var invalid = runtime; invalid.removeValue(forKey: "theme")
    XCTAssertThrowsError(try WebsiteConfigNativeStateCodec.encode(invalid))
    invalid = runtime; invalid["future"] = .bool(true)
    XCTAssertThrowsError(try WebsiteConfigNativeStateCodec.encode(invalid))
    invalid = runtime; invalid["customBackgroundFilter"] = .array([.number(.nan), .number(1), .number(1), .number(1)])
    XCTAssertThrowsError(try WebsiteConfigNativeStateCodec.encode(invalid))
    for data in [Data(), Data([255]), Data("{}".utf8), Data("[".utf8)] {
      XCTAssertThrowsError(try WebsiteConfigNativeStateCodec.decode(data))
    }
    XCTAssertThrowsError(try WebsiteConfigNativeProfile.prepare(text, context: .init()))
    XCTAssertThrowsError(try SettingsJSONCommandCodec.decode(text))
    let website = WebsiteConfigJSONWriter.write(.object(runtime))
    XCTAssertThrowsError(try WebsiteConfigNativeStateCodec.decode(Data(website.utf8)))
  }

  @MainActor
  func testNativeRoundTripRetainsBitsRawUnitsDuplicatesAndIndependentFlags() throws {
    let json = #"{"customBackground":"https://example.com/\ud800.png","customBackgroundFilter":[-0,1e400,-1e400,2],"autoSwitchTheme":true,"customTheme":true,"favThemes":["dracula","serika","dracula"],"funbox":["rot13","rot13"],"quoteLength":[0,0,1]}"#
    let runtime = try WebsiteConfigNativeProfile.prepare(json, context: .init()).projection.runtime
    let encoded = try WebsiteConfigNativeStateCodec.encode(runtime)
    XCTAssertFalse(encoded.isEmpty)
    let decoded = try WebsiteConfigNativeStateCodec.decode(encoded)
    XCTAssertEqual(decoded, runtime)
    guard case .array(let filters) = decoded["customBackgroundFilter"],
      case .number(let zero) = filters[0], case .number(let positive) = filters[1], case .number(let negative) = filters[2] else {
      return XCTFail("Lost source filter numbers")
    }
    XCTAssertEqual(zero.bitPattern, (-0.0 as Double).bitPattern)
    XCTAssertEqual(positive.bitPattern, Double.infinity.bitPattern)
    XCTAssertEqual(negative.bitPattern, (-Double.infinity).bitPattern)
    XCTAssertEqual(decoded["customBackground"]?.stringUnits, runtime["customBackground"]?.stringUnits)
    XCTAssertEqual(try WebsiteConfigNativeStateCodec.encode(decoded), encoded)
  }
}
