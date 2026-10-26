import XCTest
@testable import Typebar

final class WebsiteKeymapDeferredSourceTests: XCTestCase {
  func testActualSourceModeGatesInputAndCompositionAndFlashClearsNextHighlight() throws {
    let env = ProcessInfo.processInfo.environment
    guard let reference = env["TYPEBAR_REFERENCE_ROOT"] ?? env["TYPEBAR_LAYOUT_AUDIT_REFERENCE"] else { throw XCTSkip("Requires pinned reference") }
    struct Fixture: Decodable { let mode: String, word: String, action: String; let initial: [UInt16]?, units: [UInt16]? }
    struct Output: Decodable { let modeFixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-keymap-deferred.mjs").path, reference]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).modeFixtures
    XCTAssertEqual(fixtures.count, 24)
    for f in fixtures {
      var session = TypingSession(configuration: .words(100), prompt: f.word + " tail")
      session.synchronizeWebsiteKeymapMode(try XCTUnwrap(KeyboardGuideMode(rawValue: f.mode)))
      XCTAssertEqual(session.websiteKeymapHighlightUnits, f.initial, "Initial \(f.mode), \(f.word)")
      if f.action == "input" { session.insertBatch("x") }
      else { session.beginComposition(); session.refreshLiveAccuracyAfterComposition(hadMarkedText: false, hasMarkedText: true) }
      XCTAssertEqual(session.websiteKeymapHighlightUnits, f.units, "\(f.mode), \(f.word), \(f.action)")
    }
  }
  func testActualSourceDelayedCallbacksReadCurrentWordAndPreserveRawUnits() throws {
    let env = ProcessInfo.processInfo.environment
    guard let reference = env["TYPEBAR_REFERENCE_ROOT"] ?? env["TYPEBAR_LAYOUT_AUDIT_REFERENCE"] else { throw XCTSkip("Requires pinned reference") }
    struct Fixture: Decodable { let kind: String, word: String, finalMode: String; let position: Int, delay: Int; let units: [UInt16]? }
    struct Output: Decodable { let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-keymap-deferred.mjs").path, reference]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 216)
    for f in fixtures {
      var config = TestConfiguration.words(100); config.rules.blindMode = true
      var session = TypingSession(configuration: config, prompt: f.word.isEmpty ? "" : f.word + " tail")
      if f.position > 0 { session.insertBatch(String(repeating: "x", count: f.position)) }
      session.refreshWebsiteKeymapDeferredHighlight(f.kind == "mode" ? .firstScalar : .layoutPosition)
      XCTAssertEqual(session.websiteKeymapHighlightUnits, f.units, "\(f.kind), \(f.word.debugDescription), \(f.position), \(f.finalMode)")
      XCTAssertEqual(f.delay, f.kind == "mode" ? 0 : 1)
    }
    print("Pinned deferred keymap callbacks: \(fixtures.count)")
  }
}
