import AppKit
import XCTest
@testable import Typebar

@MainActor final class TapeLineMotionCompositionTests: XCTestCase {
  private struct Marker: Decodable {
    let x, y, width, vertical, horizontal, correction: Double
    let verticalReady, horizontalReady: Bool
  }
  private struct Trace: Decodable {
    let type: String, time: Double
    let id: String?, reason: String?
    let x, y, width, height, wordsX, wordsY, value, duration: Double?
    let rendered: Bool?, leadingFiller: Bool?
    let main, pace: Marker?
  }
  private struct Fixture: Decodable {
    let rtl, smooth, independent, overlap: Bool
    let mode, style: String
    let trace: [Trace]
  }
  private struct Evidence: Decodable { let pin: String; let fixtures: [Fixture] }
  private static var cached: Evidence?

  private func evidence() throws -> Evidence {
    if let cached = Self.cached { return cached }
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"],
      ProcessInfo.processInfo.environment["TYPEBAR_LINE_SCROLL_ANIME_ARCHIVE"] != nil else {
      throw XCTSkip("Requires pinned reference checkout and locked Anime.js archive")
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent(
      "Scripts/check-source-tape-line-composition.mjs").path, reference, "--emit-fixtures"]
    process.standardOutput = output; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw NSError(domain: "TapeLineSourceProbe", code: Int(process.terminationStatus),
        userInfo: [NSLocalizedDescriptionKey: "Pinned source probe failed; see its stderr before decoding fixtures"])
    }
    let evidence = try JSONDecoder().decode(Evidence.self, from: data)
    XCTAssertEqual(evidence.pin, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(evidence.fixtures.count, 128)
    Self.cached = evidence
    return evidence
  }

  func testCompleteSourceVerticalAndTapeCompositionMatchesAllNativeMotionChannels() throws {
    for (index, fixture) in try evidence().fixtures.enumerated() {
      let motion = PromptCaretMotionCoordinator(); motion.prepare(attemptID: UUID())
      for event in fixture.trace {
        let time = event.time / 1000
        switch event.type {
        case "frame": if event.rendered == true { motion.sample(at: time) }
        case "line": motion.lineJump(to: try XCTUnwrap(event.value), duration: try XCTUnwrap(event.duration) / 1000, at: time)
        case "scroll": motion.tapeScroll(to: try XCTUnwrap(event.value), duration: try XCTUnwrap(event.duration) / 1000, at: time)
        case "retire": motion.tapeWordsRemoved(width: try XCTUnwrap(event.value))
        case "wordsReset": motion.wordsDidFinish(at: time)
        case "position":
          let main = event.id == "caret"
          // Shared source boxes, captured before either margin is folded.
          // Remove only words transforms, then use the actual native owner to
          // compose its independently presented channels again.
          let rect = CGRect(x: try XCTUnwrap(event.x) - (main ? 0 : try XCTUnwrap(event.wordsX)),
            y: try XCTUnwrap(event.y) - XCTUnwrap(event.wordsY),
            width: try XCTUnwrap(event.width), height: try XCTUnwrap(event.height))
          let duration = try XCTUnwrap(event.duration) / 1000
          if main { motion.positionMain(at: rect, time: time, duration: duration) }
          else { motion.positionPace(at: rect, time: time, duration: duration) }
        case "sample":
          let label = "fixture \(index)/\(fixture.rtl)/\(fixture.mode)/\(fixture.smooth)/\(fixture.style)/\(fixture.independent)/\(fixture.overlap) @\(event.time)"
          try equal(motion.wordsMargin, XCTUnwrap(event.wordsY), label + " wordsY")
          try equal(motion.wordsTapeMargin, XCTUnwrap(event.wordsX), label + " wordsX")
          try compare(motion.main, XCTUnwrap(event.main), label + " main")
          try compare(motion.pace, XCTUnwrap(event.pace), label + " pace")
        default: XCTFail("Unknown source event \(event.type)")
        }
      }
    }
  }

  func testSourceWaitsForVerticalCompletionThenRemovesOnlyTheLeadingFiller() throws {
    for fixture in try evidence().fixtures {
      let events = fixture.trace
      let resets = events.filter { $0.type == "wordsReset" }
      XCTAssertEqual(resets.count, fixture.smooth ? 1 : 0)
      if fixture.smooth {
        let reset = try XCTUnwrap(resets.first)
        XCTAssertEqual(reset.time, fixture.overlap ? 373 : 313)
        let sample = try XCTUnwrap(events.first { $0.reason == "vertical-completion" })
        XCTAssertEqual(sample.wordsY, 0); XCTAssertTrue(sample.leadingFiller == true)
        XCTAssertNotEqual(sample.wordsX, 0, "Vertical completion must retain the presented horizontal state")
        let during = events.filter { $0.type == "scroll" && $0.time >= 200 && $0.time < reset.time }
        XCTAssertEqual(during.count, fixture.independent ? 1 : 0)
        if fixture.independent { XCTAssertEqual(during.first?.time, 250) }
      }
      let retired = events.filter { $0.type == "retire" }
      XCTAssertEqual(retired.count, fixture.overlap && !fixture.smooth ? 2 : 1)
      XCTAssertEqual(retired.compactMap(\.value).reduce(0, +), (fixture.rtl ? -1 : 1) * (fixture.overlap ? 72 : 36))
      XCTAssertEqual(retired.last?.time, fixture.overlap ? (fixture.smooth ? 373 : 260) : (fixture.smooth ? 313 : 200))
    }
  }

  private func equal(_ actual: Double, _ expected: Double, _ label: String) throws {
    guard actual.isFinite, expected.isFinite, abs(actual - expected) <= 1e-6 else {
      XCTFail("\(label): native \(actual), source \(expected)")
      throw NSError(domain: "TapeLineTraceMismatch", code: 1)
    }
  }
  private func compare(_ native: PromptCaretChannel, _ source: Marker, _ label: String) throws {
    let rect = try XCTUnwrap(native.position)
    for (name, actual, expected) in [("x", rect.minX, source.x), ("y", rect.minY, source.y),
      ("width", rect.width, source.width), ("vertical", native.margin, source.vertical),
      ("horizontal", native.tapeMargin, source.horizontal), ("correction", native.cumulativeTapeCorrection, source.correction)] {
      try equal(actual, expected, label + " " + name)
    }
    XCTAssertEqual(native.marginReady, source.verticalReady, label)
    XCTAssertEqual(native.tapeMarginReady, source.horizontalReady, label)
  }

  private final class Document: NSView { override var isFlipped: Bool { true } }
  private func followerFixture() -> (NSScrollView, PromptAutoScrollView) {
    let scroll = NSScrollView(frame: .init(x: 0, y: 0, width: 360, height: 135))
    let document = Document(frame: .init(x: 0, y: 0, width: 360, height: 500))
    scroll.documentView = document
    let follower = PromptAutoScrollView(frame: document.bounds); document.addSubview(follower)
    return (scroll, follower)
  }
  private func update(_ follower: PromptAutoScrollView, row: Int, attempt: UUID,
    motion: PromptCaretMotionCoordinator, notify: @escaping (PromptWordRetirement) -> Void) {
    let starts = [0, 6, 12, 18, 24, 30]
    follower.update(text: AttributedString("amber\nbirch\ncedar\ndelta\nelder\nflint"), characterOffset: starts[row],
      font: .monospacedSystemFont(ofSize: 28, weight: .medium), lineSpacing: 12, isRightToLeft: false,
      lineScroll: .init(attemptID: attempt, activeWordID: starts[row],
        characterOffsets: Dictionary(uniqueKeysWithValues: starts.map { ($0, $0) }), smoothScroll: true, reducesMotion: false,
        words: starts.enumerated().map { .init(index: $0.offset, glyphID: $0.element) }, onRetire: notify, caretMotion: motion))
    follower.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.005))
  }

  func testActualNativeFollowerCompletionKeepsTheIndependentRunningTapeWithoutAWindow() {
    for sign: CGFloat in [-1, 1] { for overlap in [false, true] {
      let (scroll, follower) = followerFixture(), motion = PromptCaretMotionCoordinator(), reference = PromptCaretMotionCoordinator()
      defer { follower.cancelCaretMotion(); follower.stopLineScroll(); follower.removeFromSuperview(); scroll.documentView = nil }
      let attempt = UUID(); var retired: [PromptWordRetirement] = []
      update(follower, row: 0, attempt: attempt, motion: motion) { retired.append($0) }
      motion.tapeScroll(to: sign * 36, duration: 0, at: ProcessInfo.processInfo.systemUptime)
      reference.tapeScroll(to: sign * 36, duration: 0, at: ProcessInfo.processInfo.systemUptime)
      for row in 1...2 { update(follower, row: row, attempt: attempt, motion: motion) { retired.append($0) } }
      if overlap { update(follower, row: 3, attempt: attempt, motion: motion) { retired.append($0) } }
      XCTAssertTrue(retired.isEmpty)
      let requestTime = ProcessInfo.processInfo.systemUptime
      for owner in [motion, reference] { owner.tapeScroll(to: sign * 72, duration: 1, at: requestTime) }
      RunLoop.main.run(until: Date().addingTimeInterval(0.19))
      XCTAssertEqual(retired, [.init(attemptID: attempt, firstRetainedWordIndex: overlap ? 2 : 1)])
      XCTAssertEqual(scroll.contentView.bounds.minY, overlap ? 90 : 45, accuracy: 0.5)
      XCTAssertEqual(motion.wordsMargin, 0); XCTAssertTrue(motion.isAnimatingTape)
      XCTAssertEqual(motion.wordsTapeMargin, sign * 36, "The follower completion itself does not present the tape")
      let presented = ProcessInfo.processInfo.systemUptime
      motion.sample(at: presented); reference.sample(at: presented)
      XCTAssertEqual(motion.wordsTapeMargin, reference.wordsTapeMargin, accuracy: 1e-7)
      XCTAssertTrue(motion.isAnimatingTape)
    } }
  }

  func testActualFollowerRestartCancelsOldRetirementAndCannotClearNewAttemptTape() {
    let (scroll, follower) = followerFixture(), motion = PromptCaretMotionCoordinator(), old = UUID(), next = UUID()
    defer { follower.cancelCaretMotion(); follower.stopLineScroll(); follower.removeFromSuperview(); scroll.documentView = nil }
    var retired: [PromptWordRetirement] = []
    for row in 0...2 { update(follower, row: row, attempt: old, motion: motion) { retired.append($0) } }
    update(follower, row: 0, attempt: next, motion: motion) { retired.append($0) }
    motion.tapeScroll(to: 81, duration: 0, at: ProcessInfo.processInfo.systemUptime)
    RunLoop.main.run(until: Date().addingTimeInterval(0.19))
    XCTAssertTrue(retired.isEmpty); XCTAssertEqual(motion.wordsMargin, 0)
    XCTAssertEqual(motion.wordsTapeMargin, 81); XCTAssertEqual(scroll.contentView.bounds.minY, 0)
  }
  func testVerticalWordsCompletionKeepsSettledTapeAndIndependentCaretChannels() throws {
    for sign: CGFloat in [-1, 1] {
      let motion = PromptCaretMotionCoordinator()
      motion.prepare(attemptID: UUID())
      motion.positionMain(at: .init(x: 100, y: 90, width: 2, height: 32), time: 0, duration: 0)
      motion.positionPace(at: .init(x: 160, y: 135, width: 12, height: 32), time: 0, duration: 0)
      motion.tapeScroll(to: sign * 36, duration: 0, at: 0)
      motion.lineJump(to: -45, duration: 0.125, at: 1)
      motion.sample(at: 1.113)
      motion.reportProgrammaticScroll(45)
      let main = motion.main.visibleRect, pace = motion.pace.visibleRect
      motion.wordsDidFinish(at: 1.113)
      XCTAssertEqual(motion.wordsMargin, 0)
      XCTAssertEqual(motion.wordsTapeMargin, sign * 36, "Deleting an old row must not clear the independent tape origin")
      XCTAssertEqual(motion.main.visibleRect, main); XCTAssertEqual(motion.pace.visibleRect, pace)
      XCTAssertTrue(motion.main.marginReady); XCTAssertTrue(motion.pace.marginReady)
      XCTAssertEqual(motion.programmaticScroll, 45)
    }
  }

  func testVerticalWordsCompletionDoesNotSampleCancelOrRestartRunningTape() {
    for sign: CGFloat in [-1, 1] {
      let motion = PromptCaretMotionCoordinator(), reference = PromptCaretMotionCoordinator()
      for owner in [motion, reference] {
        owner.prepare(attemptID: UUID())
        owner.tapeScroll(to: sign * 36, duration: 0, at: 0)
        owner.lineJump(to: -45, duration: 0.125, at: 1)
        owner.sample(at: 1.05)
        owner.tapeScroll(to: sign * 72, duration: 0.125, at: 1.05)
        owner.sample(at: 1.08)
      }
      let presented = motion.wordsTapeMargin
      motion.wordsDidFinish(at: 1.113)
      XCTAssertEqual(motion.wordsTapeMargin, presented, "Completion is not a presentation tick")
      XCTAssertTrue(motion.isAnimatingTape)
      XCTAssertEqual(motion.wordsMargin, 0)
      for time in [1.113, 1.14, 1.163, 1.2] {
        motion.sample(at: time); reference.sample(at: time)
        XCTAssertEqual(motion.wordsTapeMargin, reference.wordsTapeMargin, accuracy: 1e-7)
        XCTAssertEqual(motion.isAnimatingTape, reference.isAnimatingTape)
        XCTAssertEqual(motion.wordsMargin, 0, "A finished vertical tween cannot reappear on a later frame")
      }
    }
  }

  func testNewLineStartsAtZeroButRestartStillClearsBothAxes() {
    let motion = PromptCaretMotionCoordinator(), attempt = UUID()
    motion.prepare(attemptID: attempt)
    motion.tapeScroll(to: -36, duration: 0, at: 0)
    motion.lineJump(to: -45, duration: 0.125, at: 0)
    motion.sample(at: 0.05); motion.wordsDidFinish(at: 0.05)
    motion.lineJump(to: -90, duration: 0.125, at: 1)
    motion.sample(at: 1.025)
    XCTAssertEqual(motion.wordsMargin, -90 * PromptLineScrollMotion.progress(elapsed: 0.037), accuracy: 1e-7)
    XCTAssertEqual(motion.wordsTapeMargin, -36)
    motion.prepare(attemptID: UUID())
    XCTAssertEqual(motion.wordsMargin, 0); XCTAssertEqual(motion.wordsTapeMargin, 0)
    XCTAssertFalse(motion.isAnimatingTape)
    XCTAssertNil(motion.main.visibleRect); XCTAssertNil(motion.pace.visibleRect)
  }
}
