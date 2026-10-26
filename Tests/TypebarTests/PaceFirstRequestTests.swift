import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class PaceFirstRequestTests: XCTestCase {
  func testPinnedFirstRequestsMatchBeforeAnyQueuedTimerDelivery() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires the pinned clean reference")
    }
    struct Fixture: Decodable {
      let speed: Double, origin: Double
      let rawWords: [String]
      let word: Int, letter: Int, requestsAfterWrongCommit: Int
    }
    struct Output: Decodable { let revision: String; let actualModules: Int; let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules",
      root.appendingPathComponent("Scripts/check-source-pace-first-frame.mjs").path, reference]
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let source = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(source.revision, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(source.actualModules, 2); XCTAssertEqual(source.fixtures.count, 48)
    for fixture in source.fixtures {
      let context = "speed=\(fixture.speed), origin=\(fixture.origin), words=\(fixture.rawWords)"
      var progress = try XCTUnwrap(PaceCaretProgress(wpm: fixture.speed,
        catalog: .init(prompt: "", noSpaceWords: fixture.rawWords)))
      progress.start(at: fixture.origin, blind: false)
      let first = try XCTUnwrap(progress.frame(at: fixture.origin, blind: false), context)
      XCTAssertEqual(first.target, .init(word: fixture.word, letter: fixture.letter), context)
      XCTAssertEqual(first.from, .init(word: 0, letter: 0), context)
      XCTAssertEqual(first.sequence, 1, context)
      for _ in 0..<3 {
        XCTAssertEqual(progress.frame(at: fixture.origin, blind: false), first, context)
      }
      XCTAssertFalse(progress.advance(to: fixture.origin, blind: false), context)
      XCTAssertEqual(fixture.requestsAfterWrongCommit, 1)
    }
  }

  func testSameTimestampCommitLeavesCorrectionPendingUntilPaceAdvances() throws {
    let clock = PaceCaretTestClock(); clock.time = 1000
    var session = TypingSession(configuration: .words(100), prompt: "ab cd efg")
    session.configurePace(wpm: 1e100, clock: clock.source)
    session.insertBatch("ax ", at: Date(timeIntervalSince1970: 1_800_000_000))
    XCTAssertEqual(session.typed, "ax ")
    let first = try XCTUnwrap(session.paceCaretFrame())
    XCTAssertEqual(first.target, .init(word: 0, letter: 1))
    XCTAssertEqual(first.from, .init(word: 0, letter: 0))
    XCTAssertEqual(first.sequence, 1)
    XCTAssertEqual(session.paceCaretFrame(), first)
  }

  func testHiddenNativeCaretPresentsFirstTargetWhenItsDeadlineRoundsToStart() throws {
    _ = NSApplication.shared
    let prompt = "ab cd efg", clock = PaceCaretTestClock()
    clock.time = 1000
    var session = TypingSession(configuration: .words(100), prompt: prompt)
    session.configurePace(wpm: 1e100, clock: clock.source)
    session.beginComposition(at: Date(timeIntervalSince1970: 1_800_000_000))
    let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .medium)
    let motion = PromptCaretMotionCoordinator()
    let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 600, height: 200))
    defer { view.stop() }
    var config = PromptCaretNativeView.Configuration(text: AttributedString(prompt),
      mainOffset: nil, paceOffset: nil, mainStyle: .off, paceStyle: .bar,
      font: font, lineSpacing: 12, rightToLeft: false, accent: .yellow, motion: .off,
      reducesMotion: false, frameRate: 15, attemptID: UUID(), coordinator: motion)
    config.paceFrame = {
      guard let frame = session.paceCaretFrame(),
        let from = session.paceCaretGlyphAnchor(for: frame.from),
        let target = session.paceCaretGlyphAnchor(for: frame.target) else { return nil }
      return .init(fromCharacterOffset: from.glyphIndex, targetCharacterOffset: target.glyphIndex,
        fromAfter: from.after, targetAfter: target.after, fraction: frame.fraction,
        stepDuration: frame.stepDuration, sequence: frame.sequence)
    }
    view.update(config); view.layout(); view.present(at: 0)
    let expected = try XCTUnwrap(PromptCaretLayout.rect(in: AttributedString(prompt),
      characterOffset: 1, containerSize: view.bounds.size, font: font, lineSpacing: 12,
      isRightToLeft: false))
    let skipped = try XCTUnwrap(PromptCaretLayout.rect(in: AttributedString(prompt),
      characterOffset: 2, containerSize: view.bounds.size, font: font, lineSpacing: 12,
      isRightToLeft: false))
    XCTAssertEqual(motion.pace.position, expected)
    XCTAssertNotEqual(motion.pace.position, skipped)
    XCTAssertNil(view.window)
  }
}
