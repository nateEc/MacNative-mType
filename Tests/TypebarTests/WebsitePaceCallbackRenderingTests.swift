import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class WebsitePaceCallbackRenderingTests: XCTestCase {
  struct Marker: Decodable { let left: Double, top: Double, width: Double }
  struct Observation: Decodable { let time: Double; let pace: Marker; let hidden: Bool }
  struct Request: Decodable { let time: Double, duration: Double; let word: Int, letter: Int }
  struct Position: Decodable { let time: Double, left: Double, top: Double, width: Double, height: Double }
  struct Fixture: Decodable {
    let firstRAF: Double, style: String
    let observations: [Observation], requests: [Request], resolved: [Position]
  }

  func testCallbackFramesAgainstCompletePinnedCaretRAFAndLockedAnime() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"],
      ProcessInfo.processInfo.environment["TYPEBAR_LINE_SCROLL_ANIME_ARCHIVE"] != nil else {
      throw XCTSkip("Requires pinned reference and locked Anime archive")
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules",
      root.appendingPathComponent("Scripts/check-source-caret-line-composition.mjs").path,
      reference, "--emit-infinite-fixtures"]
    process.standardOutput = pipe
    try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode([Fixture].self, from: data)
    XCTAssertEqual(fixtures.count, 6)
    for fixture in fixtures {
      XCTAssertEqual(fixture.requests.count, 9)
      let clock = PaceCaretTestClock()
      var session = TypingSession(configuration: .words(100), prompt: String(repeating: "aa ", count: 12))
      session.configurePace(wpm: .infinity, clock: clock.source)
      session.beginComposition(at: .now)
      let motion = PromptCaretMotionCoordinator()
      let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 600, height: 400))
      defer { view.stop() }
      let style: TypingCaretStyle = fixture.style == "default" ? .bar : fixture.style == "block" ? .block : .underline
      var target = try XCTUnwrap(fixture.resolved.first)
      var config = PromptCaretNativeView.Configuration(text: AttributedString("aa aa"), mainOffset: nil,
        paceOffset: nil, mainStyle: .off, paceStyle: style,
        font: .monospacedSystemFont(ofSize: 28, weight: .medium), lineSpacing: 12,
        rightToLeft: false, accent: .yellow, motion: .off, reducesMotion: false,
        frameRate: 15, attemptID: session.automaticInputAttemptID, coordinator: motion)
      config.paceUsesSessionCallbacks = true; config.automaticallyPresents = false
      config.glyphRect = { _ in CGRect(x: 0, y: 0, width: 2, height: target.height) }
      // Actual source-resolved boxes are geometry inputs, not inferred from
      // expected rendered samples. Logical requests are checked separately.
      config.fieldPaceRect = { _, _ in CGRect(x: target.left, y: target.top, width: target.width, height: target.height) }
      config.paceFrame = {
        guard let frame = session.paceCaretFrame() else { return nil }
        return .init(fromCharacterOffset: nil, targetCharacterOffset: nil, fromAfter: false,
          targetAfter: false, fraction: 0, stepDuration: frame.stepDuration,
          sequence: frame.sequence, targetGlyphID: 0)
      }
      view.update(config); view.layout()
      XCTAssertNil(view.scheduledTimerIntervals.pace)
      for (index, observation) in fixture.observations.enumerated() {
        clock.time = observation.time / 1000
        if index > 0 { session.deliverPaceCaretTimer(try XCTUnwrap(session.paceCaretPendingTicket)) }
        let expectedRequest = fixture.requests[index], frame = try XCTUnwrap(session.paceCaretFrame())
        XCTAssertEqual(frame.target, .init(word: expectedRequest.word, letter: expectedRequest.letter))
        XCTAssertEqual(frame.stepDuration * 1000, expectedRequest.duration, accuracy: 1e-8)
        guard observation.time >= fixture.firstRAF else { continue }
        target = try XCTUnwrap(fixture.resolved.first { $0.time == observation.time })
        view.present(at: observation.time / 1000)
        let actual = try XCTUnwrap(motion.pace.position)
        XCTAssertEqual(actual.minX, observation.pace.left, accuracy: 1e-8)
        XCTAssertEqual(actual.minY, observation.pace.top, accuracy: 1e-8)
        XCTAssertEqual(actual.width, observation.pace.width, accuracy: 1e-8)
        XCTAssertFalse(observation.hidden)
      }
      XCTAssertNil(view.window)
    }
  }
}
