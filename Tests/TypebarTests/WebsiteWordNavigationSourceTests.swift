import XCTest
@testable import Typebar

final class WebsiteWordNavigationSourceTests: XCTestCase {
  func testActualHiddenFieldNavigationIncludesEmptyTargets() throws {
    let env = ProcessInfo.processInfo.environment
    guard let reference = env["TYPEBAR_REFERENCE_ROOT"] ?? env["TYPEBAR_LAYOUT_AUDIT_REFERENCE"] else { throw XCTSkip("Requires pinned reference") }
    struct Event: Decodable, Equatable { let completed: Int, total: Int; let wasActive: Bool }
    struct Fixture: Decodable {
      let words: [String], input: String, stop: String
      let finished: Bool, failed: Bool, wordIndex: Int, inputUnits: [UInt16], events: [Event]
    }
    struct Output: Decodable { let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-input-position.mjs").path, reference, "--hidden-word-navigation-fixtures"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 120)
    for f in fixtures {
      var config = TestConfiguration.words(f.words.count)
      config.rules.blindMode = true
      config.rules.stopOnErrorMode = try XCTUnwrap(StopOnErrorMode(rawValue: f.stop))
      config = config.with(modifiers: [.layoutFluid, .noSpaces])
      let prompt = f.words.joined()
      let batch = TransformedPromptBatch(text: prompt, noSpaceTargetWords: f.words)
      var session = TypingSession(configuration: config, prompt: prompt,
        noSpaceWordEndIndices: NoSpaceWordBoundaryPolicy.endIndices(for: batch.noSpaceWordLengths),
        noSpaceTargetWords: f.words)
      session.insertBatch(f.input)
      let context = "\(f.words), \(f.input.debugDescription), \(f.stop)"
      XCTAssertEqual(session.websiteWordNavigationEvents.map { Event(completed: $0.completed, total: $0.total, wasActive: $0.wasActive) }, f.events, context)
      XCTAssertEqual(session.isFinished, f.finished || f.failed, context)
      if !session.isFinished {
        let field = try XCTUnwrap(session.promptCompositionField)
        XCTAssertEqual(field.index, f.wordIndex, context)
        XCTAssertEqual(field.inputUTF16, f.inputUnits, context)
      }
    }
    print("Pinned actual hidden word navigation sequences: \(fixtures.count)")
  }

  func testActualSourceNavigationHooksDoNotInferFinalWordFromCompletedCount() throws {
    let env = ProcessInfo.processInfo.environment
    guard let reference = env["TYPEBAR_REFERENCE_ROOT"] ?? env["TYPEBAR_LAYOUT_AUDIT_REFERENCE"] else { throw XCTSkip("Requires pinned reference") }
    struct Event: Decodable, Equatable { let completed: Int, total: Int; let wasActive: Bool }
    struct Fixture: Decodable {
      let input: String, stop: String, difficulty: String
      let strict: Bool, finished: Bool, failed: Bool
      let wordIndex: Int, inputUnits: [UInt16]
      let events: [Event]
    }
    struct Output: Decodable { let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-input-position.mjs").path, reference, "--word-navigation-fixtures"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 55)
    for f in fixtures {
      var config = TestConfiguration.words(2)
      config.rules.blindMode = true; config.rules.strictSpace = f.strict
      config.rules.stopOnErrorMode = try XCTUnwrap(StopOnErrorMode(rawValue: f.stop))
      config.difficulty = try XCTUnwrap(Difficulty(rawValue: f.difficulty))
      config = config.with(modifiers: [.layoutFluid])
      var session = TypingSession(configuration: config, prompt: "ab cd")
      session.insertBatch(f.input)
      XCTAssertEqual(session.websiteWordNavigationEvents.map { Event(completed: $0.completed, total: $0.total, wasActive: $0.wasActive) }, f.events,
        "\(f.input.debugDescription), \(f.stop), \(f.difficulty), strict=\(f.strict)")
      XCTAssertEqual(session.isFinished, f.finished || f.failed, "Terminal state: \(f.input.debugDescription), \(f.stop), \(f.difficulty), strict=\(f.strict)")
      if !session.isFinished {
        let field = try XCTUnwrap(session.promptCompositionField)
        XCTAssertEqual(field.index, f.wordIndex)
        XCTAssertEqual(field.inputUTF16, f.inputUnits)
      }
    }
    print("Pinned actual word navigation sequences: \(fixtures.count)")
  }
}
