import XCTest
@testable import Typebar

final class EmbeddedLFNavigationSourceTests: XCTestCase {
  private struct Event: Decodable {
    let payload, value: [UInt16]
    let field, charIndex: Int
    let correct, stopped, commit, last: Bool
  }
  private struct Fixture: Decodable {
    let words, chunks: [String]
    let stop: String
    let started, finished, failed: Bool
    let wordIndex: Int
    let inputUnits: [UInt16]
    let events: [Event]
  }
  private struct Output: Decodable { let fixtures: [Fixture] }

  func testInternalLFNavigationAndCapturedInputAgainstCompletePinnedHandlers() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules",
      root.appendingPathComponent("Scripts/check-source-input-position.mjs").path,
      reference, "--embedded-lf-navigation-fixtures"]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 144)
    let now = Date(timeIntervalSinceReferenceDate: 921_000_000)
    for (index, fixture) in fixtures.enumerated() {
      let rules = InputRules(stopOnErrorMode: try XCTUnwrap(StopOnErrorMode(rawValue: fixture.stop)))
      var session = TypingSession(configuration: .words(fixture.words.count, rules: rules),
        prompt: fixture.words.joined(), sourceFields: fixture.words)
      for chunk in fixture.chunks {
        if session.isFinished { break }
        session.insertBatch(chunk, at: now)
      }
      let label = "fixture=\(index) words=\(fixture.words) chunks=\(fixture.chunks) stop=\(fixture.stop)"
      XCTAssertEqual(session.hasStarted, fixture.started, label)
      XCTAssertEqual(session.outcome == .completed, fixture.finished, label)
      XCTAssertEqual(session.outcome == .failed, fixture.failed, label)
      if !session.isFinished {
        let field = try XCTUnwrap(session.promptCompositionField, label)
        XCTAssertEqual(field.index, fixture.wordIndex, label)
        XCTAssertEqual(field.inputUTF16, fixture.inputUnits, label)
      }
      if !fixture.started {
        XCTAssertTrue(fixture.events.isEmpty, label)
        XCTAssertEqual(session.typed, "", label)
        XCTAssertNil(session.result(), label)
        continue
      }
      session.bailOut(at: now.addingTimeInterval(1))
      let events = try XCTUnwrap(session.result(), label).replayEvents
      XCTAssertEqual(events.count, fixture.events.count, label)
      for (event, source) in zip(events, fixture.events) {
        XCTAssertEqual(event.inputUnits, source.payload, label)
        XCTAssertEqual(event.inputField?.units, source.value, label)
        XCTAssertEqual(event.inputField?.index, source.field, label)
        XCTAssertEqual(event.inputPosition?.charIndex, source.charIndex, label)
        XCTAssertEqual(event.inputPosition?.lastWord, source.last, label)
        XCTAssertEqual(event.inputCorrectness, [source.correct], label)
        XCTAssertEqual(event.isStoppedInsertion, source.stopped, label)
        XCTAssertEqual(event.commitsWord == true, source.commit, label)
      }
    }
  }
}
