import XCTest
@testable import Typebar

final class WebsiteConfigNativePagePreferencesTests: XCTestCase {
  @MainActor
  func testActualBackgroundPriorityEmptyLocalAndSizeSelection() throws {
    let env = ProcessInfo.processInfo.environment
    guard let reference = env["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] ?? env["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct Fixture: Decodable {
      let address: [UInt16], local: [UInt16]?, fit: String, selected: [UInt16]?, objectFit: String?
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-background-selection.mjs").path, reference]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode([Fixture].self, from: data)
    XCTAssertEqual(fixtures.count, 36)
    var runtime = try WebsiteConfigNativeProfile.prepare("{}", context: .init()).projection.runtime
    for fixture in fixtures {
      runtime["customBackground"] = .string(units: fixture.address)
      runtime["customBackgroundSize"] = .string(fixture.fit)
      let draft = try WebsiteConfigNativePagePreferences(runtime: runtime)
      let source = try draft.backgroundSource(localFileAddress: fixture.local.map { .string(units: $0) })
      if let selected = fixture.selected {
        if fixture.local != nil { XCTAssertEqual(source, .localFile) }
        else { XCTAssertEqual(source, .remote(.string(units: selected))) }
        XCTAssertEqual(fixture.objectFit, draft.backgroundFit == .max ? "" : draft.backgroundFit.rawValue)
      } else { XCTAssertEqual(source, .none) }
    }
  }

  static func assertSourceRuntime(_ runtime: [String: WebsiteConfigValue], expected: [String: WebsiteConfigValue]) throws {
    let draft = try WebsiteConfigNativePagePreferences(runtime: runtime)
    let chart = draft.accountChart, filter = draft.backgroundFilter
    let fields: [String: WebsiteConfigValue] = [
      "accountChart": .array([chart.speed, chart.accuracy, chart.average10, chart.average100].map { .string($0 ? "on" : "off") }),
      "ads": .string(draft.advertisingPreference.rawValue), "customBackground": draft.backgroundAddress,
      "customBackgroundSize": .string(draft.backgroundFit.rawValue),
      "customBackgroundFilter": .array([filter.blurRem, filter.brightness, filter.saturation, filter.opacity].map(WebsiteConfigValue.number))]
    XCTAssertEqual(fields, expected.filter { WebsiteConfigNativePagePreferences.mappedKeys.contains($0.key) })
  }

  @MainActor
  func testRequiredFieldsChoicesAndEveryChartCombination() throws {
    let defaults = try WebsiteConfigNativeProfile.prepare("{}", context: .init()).projection.runtime
    for key in WebsiteConfigNativePagePreferences.mappedKeys {
      var runtime = defaults; runtime.removeValue(forKey: key)
      XCTAssertThrowsError(try WebsiteConfigNativePagePreferences(runtime: runtime)) {
        XCTAssertEqual($0 as? WebsiteConfigNativePagePreferencesError, .missingField(key))
      }
      runtime[key] = .null
      XCTAssertThrowsError(try WebsiteConfigNativePagePreferences(runtime: runtime)) {
        XCTAssertEqual($0 as? WebsiteConfigNativePagePreferencesError, .invalidField(key))
      }
    }
    for bits in 0..<16 {
      let fields: [String: WebsiteConfigValue] = ["accountChart": .array((0..<4).map { .string(bits & (1 << $0) != 0 ? "on" : "off") })]
      let projected = try WebsiteConfigNativeProfile.prepare(WebsiteConfigJSONWriter.write(.object(fields)), context: .init()).projection.runtime
      let draft = try WebsiteConfigNativePagePreferences(runtime: projected)
      XCTAssertTrue(draft.accountChart.speed || draft.accountChart.accuracy)
      try Self.assertSourceRuntime(projected, expected: projected)
      var direct = defaults; direct["accountChart"] = fields["accountChart"]
      if bits & 3 == 0 { XCTAssertThrowsError(try WebsiteConfigNativePagePreferences(runtime: direct)) }
      else { XCTAssertNoThrow(try WebsiteConfigNativePagePreferences(runtime: direct)) }
    }
    for mode in ["off", "result", "on", "sellout"] {
      var runtime = defaults; runtime["ads"] = .string(mode)
      XCTAssertEqual(try WebsiteConfigNativePagePreferences(runtime: runtime).advertisingPreference.rawValue, mode)
      let json = WebsiteConfigJSONWriter.write(.object(["ads": .string(mode)]))
      let dev = try WebsiteConfigNativeProfile.prepare(json, context: .init(development: true)).projection.runtime
      XCTAssertEqual(try WebsiteConfigNativePagePreferences(runtime: dev).advertisingPreference, .off)
    }
    let bad: [(String, WebsiteConfigValue)] = [
      ("ads", .string("enabled")), ("customBackgroundSize", .string("fill")),
      ("customBackground", .string("file:///owned.png")), ("customBackground", .string(" https://example.com/a.png ")),
      ("accountChart", .array([.bool(true), .string("on"), .string("on"), .string("on")])),
      ("customBackgroundFilter", .array([.number(0), .number(1), .number(1)])),
      ("customBackgroundFilter", .array([.number(0), .number(.nan), .number(1), .number(1)]))]
    for (key, value) in bad {
      var runtime = defaults; runtime[key] = value
      XCTAssertThrowsError(try WebsiteConfigNativePagePreferences(runtime: runtime))
    }
    let empty = try WebsiteConfigNativePagePreferences(runtime: defaults)
    XCTAssertEqual(try empty.backgroundSource(), .none)
    XCTAssertEqual(try empty.backgroundSource(localFileAddress: .string("owned-file")), .localFile)
  }

  @MainActor
  func testFinalValuesRetainChartRolesRawAddressAndUnboundedFilters() throws {
    var runtime = try WebsiteConfigNativeProfile.prepare("{}", context: .init()).projection.runtime
    runtime["accountChart"] = .array([.string("off"), .string("on"), .string("off"), .string("on")])
    runtime["ads"] = .string("sellout")
    let address = WebsiteConfigValue.string(units: Array("http://example.com/".utf16) + [0xD800] + Array(".png?raw=1".utf16))
    runtime["customBackground"] = address
    runtime["customBackgroundSize"] = .string("max")
    runtime["customBackgroundFilter"] = .array([.number(-0.0), .number(.infinity), .number(-20), .number(2)])
    let draft = try WebsiteConfigNativePagePreferences(runtime: runtime)
    XCTAssertEqual(draft.accountChart, .init(speed: false, accuracy: true, average10: false, average100: true))
    XCTAssertEqual(draft.advertisingPreference, .sellout)
    XCTAssertEqual(draft.backgroundAddress, address)
    XCTAssertEqual(draft.backgroundFit, .max)
    XCTAssertEqual(draft.backgroundFilter.blurRem.sign, .minus)
    XCTAssertEqual(draft.backgroundFilter.brightness, .infinity)
    XCTAssertEqual(draft.backgroundFilter.saturation, -20)
    XCTAssertEqual(draft.backgroundFilter.opacity, 2)
    XCTAssertEqual(try draft.backgroundSource(localFileAddress: .string("data:owned-local-file")), .localFile)
    XCTAssertEqual(try draft.backgroundSource(), .remote(address))
    XCTAssertEqual(try draft.backgroundSource(localFileAddress: .string("")), .none)
    XCTAssertThrowsError(try draft.backgroundSource(localFileAddress: .null))
  }
}
