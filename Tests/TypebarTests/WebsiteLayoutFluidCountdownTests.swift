import XCTest
@testable import Typebar

@MainActor final class WebsiteLayoutFluidCountdownTests: XCTestCase {
  func testActualSourceCountdownActionsAndPersistentVisibility() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else { throw XCTSkip("Requires pinned reference") }
    struct Snapshot: Decodable { let visible: Bool; let text: String? }
    struct Fixture: Decodable {
      let mode: String, progress: Int, total: Int, current: [String: WebsiteConfigValue]
      let countdownActions: [String], countdown: Snapshot
    }
    struct Output: Decodable { let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-config-schema.mjs").path, reference, "--layoutfluid-runtime"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 756)
    var state = WebsiteLayoutFluidCountdown()
    for f in fixtures {
      if f.progress == (f.mode == "time" ? 0 : 1) { state = .init() }
      let event: WebsiteLayoutFluidTransition.Event = f.mode == "time" ? .time(f.progress) : .words(completed: f.progress, total: f.total)
      let actions = WebsiteLayoutFluidCountdown.actions(current: f.current, event: event)
      let context = "\(f.mode) \(f.progress), \(f.current["customLayoutfluid"] as Any)"
      XCTAssertEqual(actions.map(\.trace), f.countdownActions, context)
      state.apply(actions)
      XCTAssertEqual(state.visible, f.countdown.visible, context)
      XCTAssertEqual(state.text, f.countdown.text, context)
    }
  }
}
