import XCTest
@testable import Typebar

@MainActor final class WebsiteCaretCommandTests: XCTestCase {
  func testPinnedCaretCommandExecutionVisibilityAndNoRestart() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else { throw XCTSkip("Requires pinned reference") }
    struct Fixture: Decodable {
      let key: String, value: WebsiteConfigValue, current: [String:WebsiteConfigValue], active: Bool
      let runtime: [String:WebsiteConfigValue], events: [WebsiteConfigApplicationEvent], saves: [String]
      let restarts: Int, visible: Bool
    }
    struct Output: Decodable { let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-config-schema.mjs").path, reference, "--caret-commands"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 88)
    let targets = CaretCommandCatalog.items.compactMap { CaretCommandCatalog.target(for: $0.id) }
    XCTAssertEqual(targets.filter(\.visibleInWebsiteCommandPalette).count, 16)
    for f in fixtures {
      let target = try XCTUnwrap(targets.first { $0.websiteKey == f.key && $0.websiteValue == f.value })
      let result = try WebsiteConfigRuntimeProjector.edit(current: f.current, key: target.websiteKey, value: target.websiteValue,
        defaults: WebsiteConfigNativeProfile.defaultDocument().values, schema: .init(catalogs: WebsiteConfigNativeProfile.catalogs),
        context: .init(), testActive: f.active)
      XCTAssertEqual(result.runtime, f.runtime); XCTAssertEqual(result.events, f.events)
      XCTAssertEqual(result.events.map(\.key), f.saves); XCTAssertTrue(result.rejectedKeys.isEmpty)
      XCTAssertEqual(f.restarts, 0); XCTAssertFalse(target.requiresRestart)
      XCTAssertEqual(target.visibleInWebsiteCommandPalette, f.visible)
    }
  }
  func testCaretAdmissionRejectsOtherFieldsAndCompoundEdits() throws {
    let original = try WebsiteConfigNativeProfile.prepareDraft("{}", pointsPerRem: 16, context: .init())
    let accepted = try WebsiteConfigNativeProfile.editDraft(original, key: "caretStyle", value: .string("block"), pointsPerRem: 16, context: .init())
    XCTAssertTrue(WebsiteConfigCaretEdit.admits(accepted, from: original))
    let sound = try WebsiteConfigNativeProfile.editDraft(original, key: "soundVolume", value: .number(0.2), pointsPerRem: 16, context: .init())
    XCTAssertFalse(WebsiteConfigCaretEdit.admits(sound, from: original))
    let compound = try WebsiteConfigNativeProfile.editDraft(sound, key: "caretStyle", value: .string("block"), pointsPerRem: 16, context: .init())
    XCTAssertFalse(WebsiteConfigCaretEdit.admits(compound, from: original))
  }
}
