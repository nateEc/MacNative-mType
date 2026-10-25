import XCTest
@testable import Typebar

@MainActor final class WebsiteLayoutFluidTransitionTests: XCTestCase {
  func testActualSpaceTimerSettersAndCurrentVisualSelection() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else { throw XCTSkip("Requires pinned reference") }
    struct Fixture: Decodable {
      let mode: String, progress: Int, total: Int, current: [String: WebsiteConfigValue], runtime: [String: WebsiteConfigValue]
      let events: [WebsiteConfigApplicationEvent], saves: [String], notices: [Bool], guide: String
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
    for f in fixtures {
      let event: WebsiteLayoutFluidTransition.Event = f.mode == "time" ? .time(f.progress) : .words(completed: f.progress, total: f.total)
      let plan = try WebsiteLayoutFluidTransition.plan(current: f.current, event: event, context: .init(), active: true)
      XCTAssertFalse(plan.failedOverride)
      var runtime = f.current, events: [WebsiteConfigApplicationEvent] = []
      for step in plan.steps where step.accepted {
        let result = try WebsiteConfigRuntimeProjector.edit(current: runtime, key: step.key, value: step.value,
          defaults: WebsiteConfigNativeProfile.defaultDocument().values, schema: .init(catalogs: WebsiteConfigNativeProfile.catalogs),
          context: .init(), testActive: true, nosave: step.nosave)
        XCTAssertEqual(result.events.count, 1); runtime = result.runtime; events += result.events
      }
      XCTAssertEqual(runtime, f.runtime); XCTAssertEqual(events, f.events)
      XCTAssertEqual(events.filter { $0.nosave == false }.map(\.key), f.saves)
      XCTAssertEqual(plan.steps.filter { !$0.accepted }.map { _ in true }, f.notices)
      let visual = runtime["keymapLayout"] == .string("overrideSync") ? runtime["layout"] : runtime["keymapLayout"]
      XCTAssertEqual(visual == .string("default") ? .string("qwerty") : visual, .string(f.guide))
    }
  }
  func testCapabilityRequiresFluidSingleSetterAndAnActualSequenceLayout() throws {
    let original = try WebsiteConfigNativeProfile.prepareDraft(#"{"funbox":["layoutfluid"],"customLayoutfluid":["qwerty","colemak"],"keymapMode":"static"}"#, pointsPerRem: 16, context: .init())
    for nosave in [false, true] {
      for (key, name, allowed) in [("layout","colemak",true),("keymapLayout","colemak",true),
        ("keymapMode","static",true),("keymapMode","next",false),("layout","dvorak",false)] {
        let next = try WebsiteConfigNativeProfile.editDraft(original, key: key, value: .string(name), pointsPerRem: 16, context: .init(), nosave: nosave)
        XCTAssertEqual(WebsiteLayoutFluidTransition.admits(next, from: original), allowed)
      }
    }
    let ordinary = try WebsiteConfigNativeProfile.prepareDraft("{}", pointsPerRem: 16, context: .init())
    let edit = try WebsiteConfigNativeProfile.editDraft(ordinary, key: "layout", value: .string("colemak"), pointsPerRem: 16, context: .init())
    XCTAssertFalse(WebsiteLayoutFluidTransition.admits(edit, from: ordinary))
  }
}
