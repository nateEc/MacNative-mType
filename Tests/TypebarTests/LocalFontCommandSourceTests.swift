import Foundation
import XCTest
@testable import Typebar

final class LocalFontCommandSourceTests: XCTestCase {
  func testPinnedStorageTransitionsMatchNativeCommandAvailability() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference checkout")
    }
    struct Fixture: Decodable {
      let name: String
      let stored: Bool, canImport: Bool, canRemove: Bool
    }
    let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", project.appendingPathComponent("Scripts/check-source-local-font-commands.mjs").path,
      reference, "--emit-fixtures"]
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode([Fixture].self, from: data)
    XCTAssertEqual(fixtures.count, 8)
    for item in fixtures {
      for enabled in [false, true] {
        let ids = Set(FontFamilyCommandCatalog.items(hasLocalFont: item.stored,
          usesLocalFont: enabled, availableKnownFontIDs: []).map(\.id))
        XCTAssertEqual(ids.contains("customLocalFont"), item.canImport, item.name)
        XCTAssertEqual(ids.contains("removeLocalFont"), item.canRemove, item.name)
        XCTAssertEqual(ids.contains("useLocalFont"), item.stored && !enabled, item.name)
      }
    }
  }
}
