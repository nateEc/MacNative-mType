import XCTest
@testable import Typebar

final class WebsiteConfigMemoryLifecycleTests: XCTestCase {
  func testActualPinnedRestartCancelsPreviewTimerBeforeInputAndNativeSessionMatches() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct State: Decodable { let wordsVisible: Bool; let timerVisible: Bool }
    struct Fixture: Decodable {
      let mode: String, count: Int, keymapMode: String, resultPage: Bool
      let beforeStart: State, afterStart: State, restoredWordsVisible: Bool
    }
    struct Output: Decodable { let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-memory-lifecycle.mjs").path, reference]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 120)
    let zero = Date(timeIntervalSince1970: 100)
    for fixture in fixtures {
      let mode = try XCTUnwrap(TestMode(rawValue: fixture.mode))
      let configuration = TestConfiguration(mode: mode, duration: nil,
        wordLimit: mode == .words ? fixture.count : nil, difficulty: .normal,
        rules: .init(), modifiers: [.memory])
      let prompt = (0..<fixture.count).map { "owned\($0)" }.joined(separator: " ")
      var session = TypingSession(configuration: configuration, prompt: prompt)
      XCTAssertEqual(session.promptGlyphs.allSatisfy { $0.state != .hidden }, fixture.beforeStart.wordsVisible)
      XCTAssertFalse(fixture.beforeStart.timerVisible, "Real restart UI clears the handler's timer")
      XCTAssertFalse(session.tick(at: zero.addingTimeInterval(100_000)))
      XCTAssertFalse(session.hasStarted)
      XCTAssertEqual(session.elapsedSeconds(at: zero.addingTimeInterval(100_000)), 0)
      XCTAssertTrue(session.promptGlyphs.allSatisfy { $0.state != .hidden }, "Idle preview must not acquire an invented timeout")
      session.insert("o", at: zero.addingTimeInterval(100_001))
      XCTAssertTrue(session.hasStarted); XCTAssertFalse(session.isFinished)
      XCTAssertEqual(session.promptGlyphs.allSatisfy { $0.state != .hidden }, fixture.afterStart.wordsVisible)
      XCTAssertTrue(session.promptGlyphs.allSatisfy { $0.state == .hidden })
      XCTAssertFalse(fixture.afterStart.timerVisible)
      session.deleteBackward(at: zero.addingTimeInterval(100_002))
      XCTAssertTrue(session.hasStarted, "Deleting the first character does not restart preview")
      XCTAssertTrue(session.promptGlyphs.allSatisfy { $0.state == .hidden })
      let repeated = session.repeatedAttempt()
      XCTAssertFalse(repeated.hasStarted)
      XCTAssertEqual(repeated.prompt, prompt)
      XCTAssertEqual(repeated.promptGlyphs.allSatisfy { $0.state != .hidden }, fixture.restoredWordsVisible)
      XCTAssertEqual(repeated.configuration, configuration)
    }
  }
}
