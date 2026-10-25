import XCTest
@testable import Typebar

@MainActor final class WebsiteInputCommandTests: XCTestCase {
  func testAllInputCommandsMatchActualPinnedSettersIncludingPartialOverrideFailure() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else { throw XCTSkip("Requires pinned reference") }
    struct Fixture: Decodable {
      let key: String, value: WebsiteConfigValue, current: [String:WebsiteConfigValue], active: Bool, threw: Bool
      let restartRequests: Int, events: [WebsiteConfigApplicationEvent], runtime: [String:WebsiteConfigValue], saves: [String], notices: [Bool]
    }
    struct Output: Decodable { let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-config-schema.mjs").path, reference, "--input-commands"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 2310)
    let targets = InputRuleCommandCatalog.items.compactMap { InputRuleCommandCatalog.target(for: $0.id) }
    XCTAssertEqual(targets.count, 33)
    var partialFailures = 0
    for (index, fixture) in fixtures.enumerated() {
      let target = try XCTUnwrap(targets.first { $0.websiteKey == fixture.key && $0.websiteValue == fixture.value })
      let plan = try WebsiteConfigInputCommand.plan(current: fixture.current, target: target, context: .init(), active: fixture.active)
      XCTAssertEqual(plan.failedOverride, fixture.threw, "throw \(index)")
      var runtime = fixture.current, events: [WebsiteConfigApplicationEvent] = []
      var noQuitNotices = 0
      let noQuit = fixture.active && fixture.current["funbox"] == .array([.string("no_quit")])
      for step in plan.steps {
        if step.accepted {
          events.append(.init(key: step.key, previousValue: runtime[step.key], newValue: step.value, nosave: false))
          runtime[step.key] = step.value
        } else if noQuit && WebsiteConfigRuntimeProjector.restartRequiredKeys.contains(step.key) { noQuitNotices += 1 }
      }
      let restarts = fixture.key == "lazyMode" && !plan.failedOverride ? 1 : 0
      if restarts > 0 && noQuit { noQuitNotices += 1 }
      XCTAssertEqual(restarts, fixture.restartRequests, "dispatch \(index)")
      XCTAssertEqual(runtime, fixture.runtime, "runtime \(index)")
      XCTAssertEqual(events, fixture.events, "events \(index)")
      XCTAssertEqual(events.map(\.key), fixture.saves, "saves \(index)")
      XCTAssertEqual(noQuitNotices, fixture.notices.count, "notices \(index)")
      XCTAssertTrue(fixture.notices.allSatisfy { $0 })
      if plan.failedOverride && !events.isEmpty { partialFailures += 1 }
    }
    XCTAssertEqual(partialFailures, 2)
  }
}
