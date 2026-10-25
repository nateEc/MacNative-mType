import XCTest
@testable import Typebar

@MainActor final class WebsiteKeymapCommandTests: XCTestCase {
  func testActualPinnedBuildersSettersSizeValidationAndLayoutRestartGuard() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else { throw XCTSkip("Requires pinned reference") }
    struct Fixture: Decodable {
      let key: String, value: WebsiteConfigValue, raw: String?, current: [String: WebsiteConfigValue], active: Bool
      let canSubmit: Bool, initialText: String, runtime: [String: WebsiteConfigValue]
      let events: [WebsiteConfigApplicationEvent], saves: [String], notices: [Bool]
      let restarts: Int, restartAllowed: Bool, resizes: Int, threw: Bool
    }
    struct Output: Decodable { let id: String; let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-config-schema.mjs").path, reference, "--keymap-commands"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.id, WebsiteKeymapSizePresentation.item.id); XCTAssertEqual(output.fixtures.count, 980)
    let targets = KeyboardGuideCommandCatalog.items.compactMap { KeyboardGuideCommandCatalog.target(for: $0.id) }.map(WebsiteKeymapCommandTarget.display)
      + KeyboardGuideLayoutCommandCatalog.items.compactMap { KeyboardGuideLayoutCommandCatalog.target(for: $0.id) }.map(WebsiteKeymapCommandTarget.layout)
    for f in output.fixtures {
      let target: WebsiteKeymapCommandTarget
      if let raw = f.raw {
        let size = WebsiteKeymapCommand.size(raw)
        XCTAssertEqual(size != nil, f.canSubmit, raw)
        XCTAssertEqual(f.initialText, "1")
        guard let size else { XCTAssertTrue(f.events.isEmpty); XCTAssertEqual(f.runtime, f.current); continue }
        target = .size(size); XCTAssertEqual(target.value, f.value)
      } else { target = try XCTUnwrap(targets.first { $0.key == f.key && $0.value == f.value }) }
      let plan = try WebsiteKeymapCommand.plan(current: f.current, target: target, context: .init(), active: f.active)
      XCTAssertEqual(plan.failedOverride, f.threw)
      var runtime = f.current, events: [WebsiteConfigApplicationEvent] = []
      for step in plan.steps where step.accepted {
        let result = try WebsiteConfigRuntimeProjector.edit(current: runtime, key: step.key, value: step.value,
          defaults: WebsiteConfigNativeProfile.defaultDocument().values, schema: .init(catalogs: WebsiteConfigNativeProfile.catalogs),
          context: .init(), testActive: f.active)
        XCTAssertEqual(result.events.count, 1)
        runtime = result.runtime; events += result.events
      }
      XCTAssertEqual(runtime, f.runtime); XCTAssertEqual(events, f.events); XCTAssertEqual(events.map(\.key), f.saves)
      XCTAssertEqual(f.resizes, events.filter { $0.key == "keymapSize" }.count)
      XCTAssertEqual(f.restarts, target.requestsRestart && !plan.failedOverride ? 1 : 0)
      let noQuit: Bool
      if case .array(let names) = f.current["funbox"] { noQuit = names.contains(.string("no_quit")) } else { noQuit = false }
      XCTAssertEqual(f.restartAllowed, f.restarts > 0 && !(f.active && noQuit))
      XCTAssertEqual(f.notices, (plan.steps.filter { !$0.accepted }.map { _ in false }) + (f.restarts > 0 && f.active && noQuit ? [true] : []))
    }
  }
  func testSingleKeyCapabilityRejectsCompoundDependencyAndPhysicalInputChanges() throws {
    let original = try WebsiteConfigNativeProfile.prepareDraft("{}", pointsPerRem: 16, context: .init())
    let compound = try WebsiteConfigNativeProfile.editDraft(original, key: "keymapStyle", value: .string("matrix"), pointsPerRem: 16, context: .init())
    XCTAssertFalse(WebsiteKeymapCommand.admits(compound, from: original))
    let enabled = try WebsiteConfigNativeProfile.editDraft(original, key: "keymapMode", value: .string("static"), pointsPerRem: 16, context: .init())
    XCTAssertTrue(WebsiteKeymapCommand.admits(enabled, from: original))
    let style = try WebsiteConfigNativeProfile.editDraft(enabled, key: "keymapStyle", value: .string("matrix"), pointsPerRem: 16, context: .init())
    XCTAssertTrue(WebsiteKeymapCommand.admits(style, from: enabled))
    let input = try WebsiteConfigNativeProfile.editDraft(enabled, key: "layout", value: .string("dvorak"), pointsPerRem: 16, context: .init())
    XCTAssertFalse(WebsiteKeymapCommand.admits(input, from: enabled))
  }
  func testSizeFormRejectsInvalidInputAndIgnoresLateCompletionAfterCancellation() async throws {
    let form = WebsiteKeymapSizeForm(text: ""), invalid = ["", " ", "0.51", "3.6", "Infinity", "1tail"]
    var calls = 0, completed = 0
    for raw in invalid {
      form.text = raw; XCTAssertNil(form.value)
      form.submit(apply: { _ in calls += 1 }, completed: { completed += 1 })
    }
    XCTAssertEqual(calls, 0)
    var reply: CheckedContinuation<Void, Never>?
    form.text = "0x1"
    form.submit(apply: { value in XCTAssertEqual(value, 1); calls += 1; await withCheckedContinuation { reply = $0 } }, completed: { completed += 1 })
    form.submit(apply: { _ in calls += 1 }, completed: { completed += 1 })
    for _ in 0..<100 where reply == nil { await Task.yield() }
    let continuation = try XCTUnwrap(reply)
    form.cancel(); continuation.resume(); await Task.yield()
    XCTAssertEqual(calls, 1); XCTAssertEqual(completed, 0); XCTAssertFalse(form.isWorking); XCTAssertNil(form.message)
  }
}
