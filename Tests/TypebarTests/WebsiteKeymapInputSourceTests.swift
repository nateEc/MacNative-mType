import XCTest
@testable import Typebar

final class WebsiteKeymapInputSourceTests: XCTestCase {
  func testAutomaticDrainKeepsEachPrimitiveOnceWhenTheManualBatchAlreadyFinished() {
    let start = Date(timeIntervalSince1970: 4000)
    var ended = TypingSession(configuration: .words(1, language: .codeSwift), prompt: "\t\tgo()")
    ended.insertBatch("\t\tgo()", at: start)
    XCTAssertEqual(ended.outcome, .completed)
    XCTAssertEqual(ended.keymapInputEvents.map(\.units), Array("\t\tgo()".utf16).map { [$0] })
    var active = TypingSession(configuration: .words(10, language: .codeSwift), prompt: "\t\tgo() tail")
    active.insertBatch("\tX", at: start)
    XCTAssertEqual(active.keymapInputEvents, [
      .init(units: [9], isCorrect: true), .init(units: [88], isCorrect: false), .init(units: [9], isCorrect: false),
    ])
  }

  func testActualFlashRegistryLayerPriorityAndAliasCompletionKeepExactUnitIdentity() throws {
    let env = ProcessInfo.processInfo.environment
    guard let reference = env["TYPEBAR_REFERENCE_ROOT"] ?? env["TYPEBAR_LAYOUT_AUDIT_REFERENCE"] else { throw XCTSkip("Requires pinned reference") }
    struct Snapshot: Decodable { let units: [UInt16]; let tick: Int; let isCorrect: Bool }
    struct Selected: Decodable { let tick: Int; let isCorrect: Bool }
    struct Fixture: Decodable {
      let kind: String, mode: String?
      let units: [UInt16]?, isCorrect: Bool?, legends: [[UInt16]]?
      let expected: [Snapshot], selected: Selected?
    }
    struct Output: Decodable { let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-keymap-matching.mjs").path, reference, "--flash-state"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 12)
    var state = WebsiteKeymapFlashState()
    let replacement = KeyboardGuideKey("replacement", label: "�").withWebsiteLegends(["�", "�", "", ""])
    for f in fixtures {
      if f.kind == "flash", f.mode == "react" {
        state.receive([.init(units: try XCTUnwrap(f.units), isCorrect: try XCTUnwrap(f.isCorrect))])
      } else if f.kind == "complete" { state.complete(legends: try XCTUnwrap(f.legends)) }
      XCTAssertEqual(state.entries, Dictionary(uniqueKeysWithValues: f.expected.map {
        ($0.units, WebsiteKeymapFlashState.Entry(tick: $0.tick, isCorrect: $0.isCorrect))
      }))
      let selected = state.first(for: [[98], [97]])
      XCTAssertEqual(selected?.tick, f.selected?.tick); XCTAssertEqual(selected?.isCorrect, f.selected?.isCorrect)
      if state.entries[[55357]] != nil { XCTAssertNil(replacement.websiteFlash(in: state)) }
    }
    print("Pinned keymap registry/alias-completion transitions: \(fixtures.count)")
  }

  func testActualInsertHandlerProducesEveryNormalizedPrimitiveFlashIncludingExpansionAndSurrogates() throws {
    let env = ProcessInfo.processInfo.environment
    guard let reference = env["TYPEBAR_REFERENCE_ROOT"] ?? env["TYPEBAR_LAYOUT_AUDIT_REFERENCE"] else { throw XCTSkip("Requires pinned reference") }
    struct Event: Decodable { let units: [UInt16]; let isCorrect: Bool }
    struct Fixture: Decodable { let target: String, input: String, language: String, stop: String; let events: [Event] }
    struct Output: Decodable { let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-input-position.mjs").path, reference, "--keymap-fixtures"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 26)
    for f in fixtures {
      var configuration = TestConfiguration.words(100, language: try XCTUnwrap(TypingLanguage(rawValue: f.language)))
      configuration.rules.stopOnErrorMode = try XCTUnwrap(StopOnErrorMode(rawValue: f.stop))
      configuration.rules.blindMode = true
      var session = TypingSession(configuration: configuration, prompt: f.target + " tail")
      session.insertBatch(f.input, at: Date(timeIntervalSince1970: 4000), defersAutomaticInput: true)
      XCTAssertEqual(session.keymapInputEvents, f.events.map { .init(units: $0.units, isCorrect: $0.isCorrect) }, "\(f.target.debugDescription), \(f.input.debugDescription), \(f.stop), \(f.language)")
    }
    print("Pinned primitive keymap input fixtures: \(fixtures.count)")
  }
}
