import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class WebsitePaceStyleAdmissionTests: XCTestCase {
  struct Marker: Decodable { let left: Double, top: Double }
  struct Observation: Decodable { let time: Double; let style: String; let pace: Marker }
  struct Request: Decodable { let time: Double, duration: Double; let word: Int, letter: Int }
  struct Position: Decodable { let time: Double, left: Double, top: Double, width: Double, height: Double }
  struct Geometry: Decodable {
    let word: Int, letter: Int
    let style: String
    let left: Double, top: Double, width: Double, height: Double
  }
  struct Fixture: Decodable {
    let firstRAF: Double, startsOff: Bool
    let observations: [Observation], requests: [Request], resolved: [Position], geometryRequests: [Geometry]
  }

  func testDefaultOffTransitionsAgainstCompletePinnedCaretAndRAF() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"],
      ProcessInfo.processInfo.environment["TYPEBAR_LINE_SCROLL_ANIME_ARCHIVE"] != nil else {
      throw XCTSkip("Requires pinned reference and locked Anime archive")
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules",
      root.appendingPathComponent("Scripts/check-source-caret-line-composition.mjs").path,
      reference, "--emit-style-fixtures"]
    process.standardOutput = pipe
    try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode([Fixture].self, from: data)
    XCTAssertEqual(fixtures.count, 3)
    for fixture in fixtures {
      XCTAssertEqual(fixture.requests.count, 3)
      XCTAssertEqual(fixture.geometryRequests.count, 6)
      let context = "firstRAF=\(fixture.firstRAF), startsOff=\(fixture.startsOff)"
      let clock = PaceCaretTestClock()
      var style: TypingCaretStyle = fixture.startsOff ? .off : .bar
      var session = TypingSession(configuration: .words(100), prompt: String(repeating: "aa ", count: 12))
      session.configurePace(wpm: 300, clock: clock.source, style: style)
      session.beginComposition(at: .now)
      var time = 0.0
      var geometryRevision: UInt64 = 0
      var resolutions: [(Double, Double)] = []
      let motion = PromptCaretMotionCoordinator()
      let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 600, height: 400))
      defer { view.stop() }
      func configuration() -> PromptCaretNativeView.Configuration {
        var config = PromptCaretNativeView.Configuration(text: AttributedString("aa aa"), mainOffset: nil,
          paceOffset: nil, mainStyle: .off, paceStyle: style,
          font: .monospacedSystemFont(ofSize: 28, weight: .medium), lineSpacing: 12,
          rightToLeft: false, accent: .yellow, motion: .off, reducesMotion: false,
          frameRate: 15, attemptID: session.automaticInputAttemptID, coordinator: motion)
        config.paceUsesSessionCallbacks = true; config.automaticallyPresents = false
        config.paceIsVisible = { session.paceCaretIsVisible }
        config.geometryRevision = geometryRevision
        config.glyphRect = { _ in CGRect(x: 0, y: 0, width: 2, height: 33) }
        config.paceFrame = {
          guard let frame = session.paceCaretPresentationFrame() else { return nil }
          return .init(fromCharacterOffset: nil, targetCharacterOffset: nil, fromAfter: false,
            targetAfter: false, fraction: 0, stepDuration: frame.stepDuration,
            sequence: frame.sequence, targetGlyphID: 0)
        }
        config.fieldPaceRect = { _, _ in
          guard let frame = session.paceCaretPresentationFrame(), let geometry = fixture.geometryRequests.first(where: {
            $0.word == frame.target.word && $0.letter == frame.target.letter
              && $0.style == (style == .off ? "off" : "default")
          }) else { XCTFail("Missing independently queried geometry"); return nil }
          resolutions.append((time, geometry.left))
          return CGRect(x: geometry.left, y: geometry.top, width: geometry.width, height: geometry.height)
        }
        return config
      }
      view.update(configuration()); view.layout()
      for observation in fixture.observations {
        time = observation.time; clock.time = time / 1000
        let nextStyle: TypingCaretStyle = observation.style == "off" ? .off : .bar
        if style != nextStyle {
          style = nextStyle; session.synchronizePaceCaretStyle(style)
          geometryRevision += 1
          view.update(configuration()); view.layout()
        }
        if time > 0, fixture.requests.contains(where: { $0.time == time }) {
          XCTAssertTrue(session.deliverPaceCaretTimer(try XCTUnwrap(session.paceCaretPendingTicket)))
        }
        if time >= fixture.firstRAF {
          view.present(at: time / 1000)
          if style.drawsMarker {
            let actual = try XCTUnwrap(motion.pace.position, context)
            XCTAssertEqual(actual.minX, observation.pace.left, accuracy: 1e-8, "\(context), time=\(time)")
            XCTAssertEqual(actual.minY, observation.pace.top, accuracy: 1e-8, context)
            XCTAssertTrue(view.hasVisiblePaceMarker, "Revealing is visible even before a new accepted request")
          } else { XCTAssertFalse(view.hasVisiblePaceMarker) }
        }
      }
      XCTAssertEqual(resolutions.count, fixture.resolved.count, context)
      for (actual, expected) in zip(resolutions, fixture.resolved) {
        XCTAssertEqual(actual.0, expected.time, context)
        XCTAssertEqual(actual.1, expected.left, context)
      }
      XCTAssertNil(view.scheduledTimerIntervals.pace)
      XCTAssertNil(view.window)
    }
  }
}
