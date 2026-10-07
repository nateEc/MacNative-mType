import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class PromptLineScrollTests: XCTestCase {
  private final class Document: NSView { override var isFlipped: Bool { true } }
  private let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .medium)
  private let text = AttributedString("amber\nbirch\ncedar\ndelta\nelder\nflint")
  private let starts = [0, 6, 12, 18, 24, 30]

  private func fixture() -> (NSScrollView, PromptAutoScrollView) {
    let scroll = NSScrollView(frame: .init(x: 0, y: 0, width: 360, height: 135))
    let document = Document(frame: .init(x: 0, y: 0, width: 360, height: 500))
    scroll.documentView = document
    let follower = PromptAutoScrollView(frame: document.bounds)
    document.addSubview(follower)
    return (scroll, follower)
  }

  private func update(_ follower: PromptAutoScrollView, row: Int, attempt: UUID,
    smooth: Bool = false, reduced: Bool = false, caret: Int? = nil, frameRate: Int = 1_000) {
    follower.update(text: text, characterOffset: caret ?? starts[row], font: font,
      lineSpacing: 12, isRightToLeft: false,
      lineScroll: .init(attemptID: attempt, activeWordID: starts[row],
        characterOffsets: Dictionary(uniqueKeysWithValues: starts.map { ($0, $0) }),
        smoothScroll: smooth, reducesMotion: reduced, frameRate: frameRate))
    RunLoop.main.run(until: Date().addingTimeInterval(0.005))
  }

  func testFirstWrapStaysStillAndNextWrapKeepsThePreviousLine() {
    let (scroll, follower) = fixture(), attempt = UUID()
    update(follower, row: 0, attempt: attempt)
    update(follower, row: 1, attempt: attempt)
    XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 0.5)
    update(follower, row: 2, attempt: attempt)
    XCTAssertEqual(scroll.contentView.bounds.minY, 45, accuracy: 0.5)
    update(follower, row: 3, attempt: attempt)
    XCTAssertEqual(scroll.contentView.bounds.minY, 90, accuracy: 0.5)
  }

  func testCaretMovementInsideTheWordDoesNotPrematurelyAdvanceTheLine() {
    let (scroll, follower) = fixture(), attempt = UUID()
    update(follower, row: 0, attempt: attempt)
    update(follower, row: 0, attempt: attempt, caret: 12)
    XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 0.5)
  }

  func testSmoothLineScrollMovesOverTimeAndSettlesAtTheSameOrigin() {
    let (scroll, follower) = fixture(), attempt = UUID()
    update(follower, row: 0, attempt: attempt, smooth: true)
    update(follower, row: 1, attempt: attempt, smooth: true)
    update(follower, row: 2, attempt: attempt, smooth: true)
    XCTAssertLessThan(scroll.contentView.bounds.minY, 44)
    RunLoop.main.run(until: Date().addingTimeInterval(0.04))
    XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0)
    XCTAssertLessThan(scroll.contentView.bounds.minY, 45)
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    XCTAssertEqual(scroll.contentView.bounds.minY, 45, accuracy: 0.5)
  }

  func testReducedMotionSettlesImmediatelyDespiteSmoothSetting() {
    let (scroll, follower) = fixture(), attempt = UUID()
    update(follower, row: 0, attempt: attempt, smooth: true, reduced: true)
    update(follower, row: 1, attempt: attempt, smooth: true, reduced: true)
    update(follower, row: 2, attempt: attempt, smooth: true, reduced: true)
    XCTAssertEqual(scroll.contentView.bounds.minY, 45, accuracy: 0.5)
  }

  func testRestartDuringMotionCannotMoveTheNewAttempt() {
    let (scroll, follower) = fixture(), attempt = UUID()
    update(follower, row: 0, attempt: attempt, smooth: true)
    update(follower, row: 1, attempt: attempt, smooth: true)
    update(follower, row: 2, attempt: attempt, smooth: true)
    update(follower, row: 0, attempt: UUID(), smooth: true)
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 0.5)
  }

  func testASecondJumpDuringAnimationSettlesAtTheNewestWord() {
    let (scroll, follower) = fixture(), attempt = UUID()
    for row in 0...2 { update(follower, row: row, attempt: attempt, smooth: true) }
    RunLoop.main.run(until: Date().addingTimeInterval(0.03))
    update(follower, row: 3, attempt: attempt, smooth: true)
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    XCTAssertEqual(scroll.contentView.bounds.minY, 90, accuracy: 0.5)
  }

  func testRemovingFollowerStopsAnInFlightAnimation() {
    let (scroll, follower) = fixture(), attempt = UUID()
    for row in 0...2 { update(follower, row: row, attempt: attempt, smooth: true) }
    RunLoop.main.run(until: Date().addingTimeInterval(0.03))
    let origin = scroll.contentView.bounds.origin
    follower.removeFromSuperview()
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    XCTAssertEqual(scroll.contentView.bounds.origin, origin)
  }

  func testFontChangeRecentersUsingTheNewNativeRowHeight() {
    let (scroll, follower) = fixture(), attempt = UUID()
    for row in 0...3 { update(follower, row: row, attempt: attempt) }
    let larger = NSFont.monospacedSystemFont(ofSize: 40, weight: .medium)
    follower.update(text: text, characterOffset: starts[3], font: larger,
      lineSpacing: 12, isRightToLeft: false, lineScroll: .init(attemptID: attempt,
        activeWordID: starts[3], characterOffsets: Dictionary(uniqueKeysWithValues: starts.map { ($0, $0) }),
        smoothScroll: false, reducesMotion: false))
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    let expected = (NSLayoutManager().defaultLineHeight(for: larger) + 12) * 2
    XCTAssertEqual(scroll.contentView.bounds.minY, expected, accuracy: 0.5)
  }

  func testRTLWordAdvanceUsesTheSameNativeLineGeometry() throws {
    let (scroll, follower) = fixture(), attempt = UUID()
    let arabic = AttributedString("مرحبا\nقلم\nحبر\nورق")
    for offset in [0, 6, 10] {
      follower.update(text: arabic, characterOffset: offset, font: font, lineSpacing: 8,
        isRightToLeft: true, lineScroll: .init(attemptID: attempt, activeWordID: offset,
          characterOffsets: [0: 0, 6: 6, 10: 10], smoothScroll: false, reducesMotion: false))
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    let geometry = try XCTUnwrap(PromptLineScrollGeometry.measure(in: arabic, activeOffset: 10,
      previousOffset: 6, width: 360, font: font, lineSpacing: 8, rightToLeft: true))
    XCTAssertEqual(scroll.contentView.bounds.minY, try XCTUnwrap(geometry.previousWordTop), accuracy: 0.5)
    XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0)
  }

  func testLongNativeTokenKeepsItsCaretReachableWithoutChangingWordIdentity() {
    let (scroll, follower) = fixture(), attempt = UUID()
    follower.frame.size.width = 100
    let long = AttributedString(String(repeating: "x", count: 30))
    for offset in [0, 29] {
      follower.update(text: long, characterOffset: offset, font: font, lineSpacing: 12,
        isRightToLeft: false, lineScroll: .init(attemptID: attempt, activeWordID: 0,
          characterOffsets: [0: 0], smoothScroll: false, reducesMotion: false))
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0)
    let geometry = PromptLineScrollGeometry.measure(in: long, activeOffset: 0,
      previousOffset: 0, width: 100, font: font, lineSpacing: 12, rightToLeft: false, caretOffset: 29)
    XCTAssertLessThanOrEqual(geometry?.caretBottom ?? .infinity,
      scroll.contentView.bounds.maxY + 0.5)
  }

  func testShortProductionViewportCanAdvanceItsLastWordAndLeaveBlankRows() throws {
    let attempt = UUID(), short = AttributedString("amber\nbirch\ncedar")
    let font = self.font, starts = self.starts
    func root(row: Int, smooth: Bool = false, frameRate: Int = 1_000) -> some View {
      PracticePromptViewport(text: short, font: font, lineSpacing: 12,
        isRightToLeft: false, lineCount: 3) {
        Text(short).font(Font(font)).lineSpacing(12)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
          .overlay {
            PromptAutoScrollOverlay(text: short, characterOffset: starts[row], font: font,
              lineSpacing: 12, isRightToLeft: false, lineScroll: .init(attemptID: attempt,
                activeWordID: starts[row], characterOffsets: [0: 0, 6: 6, 12: 12],
                smoothScroll: smooth, reducesMotion: false))
          }
      }.frame(width: 360).environment(\.typebarAnimationFrameRate, frameRate)
    }
    let host = NSHostingView(rootView: root(row: 0))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 360, height: 135),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    defer { window.contentView = nil }
    for row in 0...2 {
      host.rootView = root(row: row)
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.04))
    }
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let scroll = try XCTUnwrap(descendants(host).compactMap { $0 as? NSScrollView }.first)
    XCTAssertEqual(scroll.bounds.height, 135, accuracy: 1)
    XCTAssertEqual(scroll.contentView.bounds.minY, 45, accuracy: 1)
    XCTAssertFalse(window.isVisible)
    host.rootView = root(row: 0)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    for row in 1...2 {
      host.rootView = root(row: row, smooth: true, frameRate: 15)
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 0.5)
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    XCTAssertEqual(scroll.contentView.bounds.minY, 45, accuracy: 1)
    if let directory = ProcessInfo.processInfo.environment["TYPEBAR_LINE_SCROLL_QA_IMAGE_DIRECTORY"],
      let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        .write(to: URL(fileURLWithPath: directory).appendingPathComponent("short-last-word.png"))
    }
  }

  func testWordOffsetsRemainGraphemeBasedAcrossEmojiAndCombiningCharacters() throws {
    let (scroll, follower) = fixture(), attempt = UUID()
    let unicode = AttributedString("🧑🏽‍💻\ne\u{301}\n漢字\nend")
    for offset in [0, 2, 4] {
      follower.update(text: unicode, characterOffset: offset, font: font, lineSpacing: 12,
        isRightToLeft: false, lineScroll: .init(attemptID: attempt, activeWordID: offset,
          characterOffsets: [0: 0, 2: 2, 4: 4], smoothScroll: false, reducesMotion: false))
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    let geometry = try XCTUnwrap(PromptLineScrollGeometry.measure(in: unicode, activeOffset: 4,
      previousOffset: 2, width: 360, font: font, lineSpacing: 12, rightToLeft: false))
    XCTAssertEqual(scroll.contentView.bounds.minY, try XCTUnwrap(geometry.previousWordTop), accuracy: 0.5)
    XCTAssertGreaterThan(geometry.activeTop, try XCTUnwrap(geometry.previousWordTop))
  }

  func testPinnedCompleteLineJumpAndActualAnimationSeekMatchNativePolicy() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference checkout")
    }
    struct Step: Decodable { let activeTop: Double, previousWordTop: Double, expectedOrigin: Double, duration: Double }
    struct Fixture: Decodable { let smooth: Bool, rowHeight: Double, steps: [Step] }
    struct Sample: Decodable { let elapsed: Double, progress: Double }
    struct Evidence: Decodable { let fixtures: [Fixture], curve: [Sample], frameRates: [Int] }
    let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", project.appendingPathComponent("Scripts/check-source-line-scroll.mjs").path,
      reference, "--emit-fixtures"]
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let evidence = try JSONDecoder().decode(Evidence.self, from: data)
    XCTAssertEqual(evidence.fixtures.count, 6)
    XCTAssertEqual(evidence.curve.count, 6)
    XCTAssertEqual(evidence.frameRates, [15, 30, 60, 120, 1_000])
    for rate in evidence.frameRates {
      XCTAssertEqual(1 / PromptLineScrollMotion.frameInterval(frameRate: rate, displayFrameRate: 1_000),
        Double(rate), accuracy: 0.000001)
    }
    for fixture in evidence.fixtures {
      var origin: CGFloat = 0
      XCTAssertEqual(fixture.steps.count, 5)
      for step in fixture.steps {
        origin = PromptLineScrollGeometry(activeTop: CGFloat(step.activeTop),
          previousWordTop: CGFloat(step.previousWordTop), previousLineTop: CGFloat(step.previousWordTop))
          .targetTop(previousTarget: origin, recenter: false)
        XCTAssertEqual(origin, step.expectedOrigin, accuracy: 0.001)
        XCTAssertEqual(step.duration, fixture.smooth && step.previousWordTop > 0 ? PromptLineScrollMotion.duration : 0)
      }
    }
    for sample in evidence.curve {
      XCTAssertEqual(PromptLineScrollMotion.progress(elapsed: sample.elapsed), sample.progress, accuracy: 0.000001)
    }
  }

  func testAnimationProgressClampsBothEnds() {
    XCTAssertEqual(PromptLineScrollMotion.progress(elapsed: -1), 0)
    XCTAssertEqual(PromptLineScrollMotion.progress(elapsed: 1), 1)
  }

  func testAnimationInheritsLowFrameRateAndRetimesWhenTheSettingChanges() {
    let (scroll, follower) = fixture(), attempt = UUID()
    for row in 0...2 { update(follower, row: row, attempt: attempt, smooth: true, frameRate: 15) }
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 0.5)
    update(follower, row: 2, attempt: attempt, smooth: true, frameRate: 30)
    RunLoop.main.run(until: Date().addingTimeInterval(0.04))
    XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0)
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    XCTAssertEqual(scroll.contentView.bounds.minY, 45, accuracy: 0.5)
  }

  func testNativeCadenceRespectsScreenLimitAndKnownFallback() {
    XCTAssertEqual(PromptLineScrollMotion.frameInterval(frameRate: 1_000, displayFrameRate: 120), 1.0 / 120)
    XCTAssertEqual(PromptLineScrollMotion.frameInterval(frameRate: 30, displayFrameRate: 120), 1.0 / 30)
    XCTAssertEqual(PromptLineScrollMotion.frameInterval(frameRate: 15, displayFrameRate: 60), 1.0 / 15)
    XCTAssertEqual(PromptLineScrollMotion.frameInterval(frameRate: 1_000, displayFrameRate: 0), 1.0 / 60)
  }
}
