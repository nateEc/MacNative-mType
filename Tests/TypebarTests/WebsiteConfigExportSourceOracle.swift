import XCTest
@testable import Typebar

enum WebsiteConfigExportSourceOracle {
  struct Fixture: Decodable {
    struct Step: Decodable { let kind: String, key: String?, json: String, active: Bool }
    let label: String, failure: Bool, commandJSON: String, settingsJSON: String
    let initialJSON: String, steps: [Step]
    let fallbackJSON: String?, readOnly: Bool?, clickToSelect: Bool?
    let delays: [Int], successes: Int, notices: Int, changedByExport: Bool
  }
  static func load() throws -> [Fixture] {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference, schema and real Solid store dependencies")
    }
    struct Output: Decodable { let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-config-schema.mjs").path,
      reference, "--export-config"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    return try JSONDecoder().decode(Output.self, from: data).fixtures
  }
}
