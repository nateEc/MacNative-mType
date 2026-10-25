import XCTest
@testable import Typebar

/// Source contract only. Native full-import failure persistence is still a
/// separate unfinished implementation, not inferred from a passing probe.
final class WebsiteConfigImportFailureOrderReferenceTests: XCTestCase {
  func testPinnedImportSeparatesSetterStorageAndUnawaitedInitializationFailures() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let reference = environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    guard environment["TYPEBAR_WEBSITE_CONFIG_ZOD_ROOT"] != nil else { return XCTFail("Requires pinned Zod") }
    struct Fixture: Decodable {
      let scenario: String
      let writes, stores, success, errors: Int
      let asyncFailure: Bool
      let trace: [String]
    }
    struct Output: Decodable { let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-config-schema.mjs").path,
      reference, "--import-failure-order"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 13)
    XCTAssertEqual(Set(fixtures.map(\.scenario)).count, 13)
    for fixture in fixtures {
      XCTAssertEqual(fixture.success + fixture.errors, 1, fixture.scenario)
      if fixture.scenario == "source-init-pending" || fixture.scenario == "source-init-failure" {
        XCTAssertEqual(fixture.writes, 1); XCTAssertEqual(fixture.success, 1)
        XCTAssertEqual(fixture.asyncFailure, fixture.scenario == "source-init-failure")
        let saved = try XCTUnwrap(fixture.trace.firstIndex(of: "storage-written"))
        let completed = try XCTUnwrap(fixture.trace.firstIndex(of: fixture.asyncFailure ? "async-error" : "init-complete"))
        XCTAssertLessThan(saved, completed, "Source import saves without awaiting the test subscriber's initialization")
      }
      if fixture.scenario == "full-storage" {
        XCTAssertEqual(fixture.stores, 1); XCTAssertEqual(fixture.writes, 0); XCTAssertEqual(fixture.errors, 1)
      }
      if fixture.scenario == "full-storage-after-correction" {
        XCTAssertEqual(fixture.stores, 1); XCTAssertEqual(fixture.writes, 1); XCTAssertEqual(fixture.errors, 1)
      }
    }
  }
}
