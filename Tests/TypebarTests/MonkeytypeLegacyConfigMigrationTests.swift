import XCTest
@testable import Typebar

final class MonkeytypeLegacyConfigMigrationTests: XCTestCase {
  func testCompletePinnedLegacyReplacementFixtures() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct Fixture: Decodable {
      let before: [String: WebsiteConfigValue]
      let after: [String: WebsiteConfigValue]
    }
    struct Output: Decodable { let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules",
      root.appendingPathComponent("Scripts/check-source-legacy-config.mjs").path, reference]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.fixtures.count, 669)
    for (index, fixture) in output.fixtures.enumerated() {
      XCTAssertEqual(jsonProjection(MonkeytypeLegacyConfigMigration.replacingLegacyValues(fixture.before)),
        fixture.after, "fixture \(index): \(fixture.before)")
    }
  }

  private func jsonProjection(_ input: [String: WebsiteConfigValue]) -> [String: WebsiteConfigValue] {
    input.mapValues(project)
  }

  private func project(_ value: WebsiteConfigValue) -> WebsiteConfigValue {
    switch value {
    case .number(let number) where !number.isFinite: .null
    case .array(let values): .array(values.map(project))
    case .object(let values): .object(jsonProjection(values))
    default: value
    }
  }

  func testObjectParsingIsTypedAndHasNoSettingsSideEffects() throws {
    let input = try MonkeytypeLegacyConfigMigration.decodeObject("{\"fontSize\":true,\"future\":null}")
    XCTAssertEqual(input["fontSize"], .bool(true))
    XCTAssertEqual(input["future"], .null)
    for json in ["[]", "null", "true", "1", "\"text\""] {
      XCTAssertThrowsError(try MonkeytypeLegacyConfigMigration.decodeObject(json))
    }
    XCTAssertThrowsError(try MonkeytypeLegacyConfigMigration.decodeObject("{"))
  }

  func testNonfiniteIntermediateValuesAreNotConfusedWithNullOrSavedAsJSON() throws {
    let input: [String: WebsiteConfigValue] = ["fontSize": .string("0x 10"),
      "soundVolume": .string("Infinity"), "future": .null]
    let migrated = MonkeytypeLegacyConfigMigration.replacingLegacyValues(input)
    guard case .number(let font) = migrated["fontSize"],
      case .number(let volume) = migrated["soundVolume"] else { return XCTFail("Typed numeric intermediates required") }
    XCTAssertTrue(font.isNaN)
    XCTAssertEqual(volume, .infinity)
    XCTAssertNotEqual(migrated["fontSize"], .null)
    XCTAssertEqual(migrated["future"], .null)
    XCTAssertEqual(input["fontSize"], .string("0x 10"))
    XCTAssertThrowsError(try JSONEncoder().encode(WebsiteConfigValue.object(migrated)))
    let negativeZero = MonkeytypeLegacyConfigMigration.replacingLegacyValues(["fontSize": .string("-0")])
    guard case .number(let zero) = negativeZero["fontSize"] else { return XCTFail("Expected numeric zero") }
    XCTAssertEqual(zero.sign, .minus)
  }
}
