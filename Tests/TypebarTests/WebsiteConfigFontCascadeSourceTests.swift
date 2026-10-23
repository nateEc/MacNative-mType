import Foundation
import XCTest
@testable import Typebar

@MainActor
final class WebsiteConfigFontCascadeSourceTests: XCTestCase {
  func testEveryPinnedLanguageAndLocalPresenceUsesActualApplicationCascade() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let reference = environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] ?? environment["TYPEBAR_REFERENCE_ROOT"]
    else { throw XCTSkip("Requires pinned reference checkout") }
    struct Fixture: Decodable { let language: String, local: String, css: String; let preferredFont: String? }
    struct Result: Decodable { let pin: String; let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-font-command-preview.mjs").path,
      reference, "--emit-cascade-fixtures"]
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let result = try JSONDecoder().decode(Result.self, from: data)
    XCTAssertEqual(result.pin, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(result.fixtures.count, 1338)
    XCTAssertEqual(Set(result.fixtures.map(\.language)), Set(WebsiteLanguageIdentity.byWebsiteName.keys))
    for fixture in result.fixtures {
      let language = try XCTUnwrap(WebsiteLanguageIdentity.byWebsiteName[fixture.language])
      let candidates = WebsiteConfigFontResource.candidates(family: "Owned_Family", language: language,
        hasLocal: fixture.local != "absent")
      let names = candidates.map { candidate in
        switch candidate {
        case .local: "\"LOCALCUSTOM\""
        case .family(let value): "\"\(value.replacingOccurrences(of: "_", with: " "))\""
        case .monospace: "monospace"
        }
      }
      XCTAssertEqual(names.joined(separator: ","), fixture.css, "\(fixture.language): \(fixture.local)")
      XCTAssertEqual(LanguagePracticeFontFallback.preferredIdentifiers(for: language), fixture.preferredFont.map { [$0] } ?? [])
    }
  }
}
