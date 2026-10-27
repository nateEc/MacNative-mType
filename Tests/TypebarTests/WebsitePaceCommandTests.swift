import XCTest
@testable import Typebar

@MainActor final class WebsitePaceCommandTests: XCTestCase {
  func testPinnedPaceCommandsUnitsSetterEventsAndRestartAdmission() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else { throw XCTSkip("Requires pinned reference") }
    struct Init: Equatable { let mode: String; let speed: Double }
    struct SourceInit: Decodable { let mode: String; let speedBits: String }
    struct EventNumbers: Decodable { let previous: String?, next: String? }
    struct Fixture: Decodable {
      let mode: String?, raw: String?, unit: String, active: Bool, authenticated: Bool
      let current: [String:WebsiteConfigValue], runtime: [String:WebsiteConfigValue], canSubmit: Bool, nonfinite: Bool
      let events: [WebsiteConfigApplicationEvent], saves: [String], notices: [Bool], restarts: Int, restartAllowed: Bool
      let inits: [SourceInit], initialText: String, runtimePaceBits: String
      let eventNumbers: [EventNumbers]
    }
    struct Output: Decodable { let id: String; let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-config-schema.mjs").path, reference, "--pace-commands"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.id, WebsitePaceSpeedPresentation.item.id); XCTAssertEqual(output.fixtures.count, 488)
    let targets = PaceCaretCommandCatalog.items.compactMap { PaceCaretCommandCatalog.target(for: $0.id) }
    for f in output.fixtures {
      let target = try f.mode.map { mode in try XCTUnwrap(targets.first { $0.websiteMode == mode }) } ?? .customSpeed
      XCTAssertEqual(f.initialText, "80")
      if !f.canSubmit {
        XCTAssertNil(WebsitePaceCommand.speed(try XCTUnwrap(f.raw), unit: try XCTUnwrap(TypingSpeedUnit(rawValue: f.unit))))
        XCTAssertEqual(f.restarts, 0); XCTAssertEqual(f.runtime, f.current); continue
      }
      let context = WebsiteConfigRuntimeContext(authenticated: f.authenticated)
      let plan = try WebsitePaceCommand.plan(current: f.current, target: target, input: f.raw, context: context, active: f.active)
      var runtime = f.current, events: [WebsiteConfigApplicationEvent] = [], inits: [Init] = []
      for step in plan.steps where step.accepted {
        let result = try WebsiteConfigRuntimeProjector.edit(current: runtime, key: step.key, value: step.value,
          defaults: WebsiteConfigNativeProfile.defaultDocument().values, schema: .init(catalogs: WebsiteConfigNativeProfile.catalogs), context: context, testActive: f.active)
        runtime = result.runtime; events += result.events
        if step.key == "paceCaret", case .string(let mode)? = runtime["paceCaret"], case .number(let speed)? = runtime["paceCaretCustomSpeed"] {
          inits.append(.init(mode: mode, speed: speed))
        }
      }
      func number(_ bits: String) throws -> Double { Double(bitPattern: try XCTUnwrap(UInt64(bits, radix: 16))) }
      var expectedRuntime = f.runtime
      expectedRuntime["paceCaretCustomSpeed"] = .number(try number(f.runtimePaceBits))
      XCTAssertEqual(f.events.count, f.eventNumbers.count)
      let expectedEvents = try zip(f.events, f.eventNumbers).map { event, bits in
        var event = event
        if let previous = bits.previous { event.previousValue = .number(try number(previous)) }
        if let next = bits.next { event.newValue = .number(try number(next)) }
        return event
      }
      XCTAssertEqual(runtime, expectedRuntime); XCTAssertEqual(events, expectedEvents); XCTAssertEqual(events.map(\.key), f.saves)
      XCTAssertEqual(inits, try f.inits.map { Init(mode: $0.mode, speed: try number($0.speedBits)) }); XCTAssertEqual(f.restarts, 1)
      let noQuit = f.active && f.current["funbox"] == .array([.string("no_quit")])
      XCTAssertEqual(f.restartAllowed, !noQuit)
      XCTAssertEqual(f.notices, (plan.steps.contains { !$0.accepted } ? [false] : []) + (noQuit ? [true] : []))
    }
    let tagged = try WebsiteConfigNativeProfile.prepareDraft(#"{"paceCaret":"tagPb"}"#, pointsPerRem: 16, context: .init(authenticated: true))
    XCTAssertEqual(tagged.behavior.paceGuideMode, .accountTagPersonalBest)
  }
  func testPaceAdmissionDoesNotAcceptCompoundSelectionOrUnrelatedFields() throws {
    let original = try WebsiteConfigNativeProfile.prepareDraft("{}", pointsPerRem: 16, context: .init())
    let mode = try WebsiteConfigNativeProfile.editDraft(original, key: "paceCaret", value: .string("custom"), pointsPerRem: 16, context: .init())
    XCTAssertTrue(WebsitePaceCommand.admits(mode, from: original))
    let compound = try WebsiteConfigNativeProfile.editDraft(mode, key: "paceCaretCustomSpeed", value: .number(120), pointsPerRem: 16, context: .init())
    XCTAssertFalse(WebsitePaceCommand.admits(compound, from: original))
    XCTAssertTrue(WebsitePaceCommand.admits(compound, from: mode))
    let other = try WebsiteConfigNativeProfile.editDraft(original, key: "soundVolume", value: .number(0.2), pointsPerRem: 16, context: .init())
    XCTAssertFalse(WebsitePaceCommand.admits(other, from: original))
  }
  func testFormCapturesOneRawInputAndCancelsLateCompletion() async throws {
    let form = WebsitePaceSpeedForm(text: "600", unit: .cpm)
    var calls: [String] = [], completed = false
    var resume: CheckedContinuation<Void, Error>?
    form.submit(apply: { raw in calls.append(raw); try await withCheckedThrowingContinuation { resume = $0 } }, completed: { completed = true })
    for _ in 0..<20 where resume == nil { await Task.yield() }
    XCTAssertEqual(calls, ["600"]); XCTAssertTrue(form.isWorking)
    form.text = "900"; form.submit(apply: { calls.append($0) }, completed: { completed = true })
    XCTAssertEqual(calls, ["600"])
    form.cancel(); resume?.resume(); resume = nil
    for _ in 0..<20 { await Task.yield() }
    XCTAssertFalse(completed); XCTAssertFalse(form.isWorking)
    form.text = "-1"; XCTAssertFalse(form.canSubmit)
    form.text = ""; XCTAssertTrue(form.canSubmit)
    form.text = "Infinity"; XCTAssertTrue(form.canSubmit)
  }
}
