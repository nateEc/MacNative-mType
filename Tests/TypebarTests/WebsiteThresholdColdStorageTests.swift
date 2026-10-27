import XCTest
@testable import Typebar

@MainActor final class WebsiteThresholdColdStorageTests: XCTestCase {
  func testActualPinnedStorageMigrationAgainstNativeThresholdColdValues() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference and schema dependencies")
    }
    struct Fixture: Decodable {
      let modeKey: String, speedKey: String, mode: String, warmBits: String, coldBits: String
      let persistedNull: Bool, unrelatedKeysPreserved: Bool, warmCachePreserved: Bool
      let writes: Int
    }
    struct Output: Decodable { let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-config-schema.mjs").path,
      reference, "--threshold-storage"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.fixtures.count, 20)
    for f in output.fixtures {
      let speed = Double(bitPattern: try XCTUnwrap(UInt64(f.warmBits, radix: 16)))
      var warm = try WebsiteConfigNativeProfile.prepare(#"{"words":77,"numbers":true,"typingSpeedUnit":"cpm","paceCaretStyle":"off"}"#,
        context: .init()).projection.runtime
      warm[f.modeKey] = .string(f.mode); warm[f.speedKey] = .number(speed)
      let bytes = try WebsiteConfigNativeStateCodec.encode(warm)
      let decoded = try WebsiteConfigNativeStateCodec.decode(bytes)
      XCTAssertEqual(decoded, warm)
      guard case .prepared(let cold) = try WebsiteConfigNativeProfile.prepareNativeRestoration(.available(decoded), context: .init()) else {
        return XCTFail("Expected native cold preparation")
      }
      let restored = Double(bitPattern: try XCTUnwrap(UInt64(f.coldBits, radix: 16)))
      var expected = warm; expected[f.speedKey] = .number(restored)
      XCTAssertEqual(cold.projection.runtime, expected, "\(f.modeKey)/\(f.mode)/\(f.warmBits)")
      XCTAssertEqual(cold.loaded, warm)
      XCTAssertEqual(f.persistedNull, speed == .infinity)
      XCTAssertEqual(f.writes, speed == .infinity ? 2 : 1)
      XCTAssertTrue(f.unrelatedKeysPreserved); XCTAssertTrue(f.warmCachePreserved)
      XCTAssertEqual(try WebsiteConfigNativeStateCodec.encode(warm), bytes)
    }
  }
}
