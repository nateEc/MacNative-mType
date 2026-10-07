import AppKit
import XCTest
@testable import Typebar

@MainActor final class PromptPrefixBaselineTests: XCTestCase {
  private final class Document: NSView { override var isFlipped: Bool { true } }
  private let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .medium)

  private func fixture() -> (NSScrollView, PromptAutoScrollView) {
    let scroll = NSScrollView(frame: .init(x: 0, y: 0, width: 420, height: 360))
    let document = Document(frame: .init(x: 0, y: 0, width: 420, height: 1200))
    scroll.documentView = document
    let follower = PromptAutoScrollView(frame: document.bounds)
    document.addSubview(follower)
    return (scroll, follower)
  }

  private func update(_ follower: PromptAutoScrollView, text: String, active: Int,
    offsets: [Int: Int], retained: Int = 0, attempt: UUID, smooth: Bool,
    pump: Bool = true,
    notify: @escaping (PromptWordRetirement) -> Void) {
    follower.update(text: AttributedString(text), characterOffset: offsets[active], font: font,
      lineSpacing: 12, isRightToLeft: false, lineScroll: .init(attemptID: attempt,
        activeWordID: active, characterOffsets: offsets, smoothScroll: smooth, reducesMotion: false,
        words: (retained..<4).map { .init(index: $0, glyphID: $0 * 3) },
        firstRetainedWordIndex: retained, onRetire: notify, followsWordReflow: true))
    if pump { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
  }

  private func finish() { RunLoop.main.run(until: Date().addingTimeInterval(0.16)) }

  func testMultirowPrefixRebuildResetsOriginWithoutRecenteringOrInventingWordUpdate() {
    for smooth in [false, true] {
      let (scroll, follower) = fixture(), attempt = UUID()
      var retired: [Int] = []
      let notify: (PromptWordRetirement) -> Void = { retired.append($0.firstRetainedWordIndex) }
      update(follower, text: "aa\nbb cc dd", active: 0, offsets: [0: 0, 3: 3, 6: 6, 9: 9],
        attempt: attempt, smooth: smooth, notify: notify)
      update(follower, text: "aa\nbb cc dd", active: 6, offsets: [0: 0, 3: 3, 6: 6, 9: 9],
        attempt: attempt, smooth: smooth, notify: notify)
      // Owned TextKit layout: earlier content grows by two rows. Stable word
      // IDs model the same active field, not a new updateActiveElement call.
      update(follower, text: "aa\nbb\nxx\nyy cc dd", active: 6,
        offsets: [0: 0, 3: 3, 6: 12, 9: 15], attempt: attempt, smooth: smooth, notify: notify)
      finish()
      XCTAssertEqual(retired, [1], "smooth=\(smooth)")
      update(follower, text: "bb\nxx\nyy cc dd", active: 6,
        offsets: [3: 0, 6: 9, 9: 12], retained: 1, attempt: attempt, smooth: smooth, notify: notify)
      finish()
      XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 0.5, "smooth=\(smooth)")
      XCTAssertEqual(retired, [1], "Prefix rebuilding is not updateWordLetters")
      follower.removeFromSuperview()
    }
  }

  func testMultirowSameWordFollowupKeepsImmediateAnchorButUsesSmoothCompletionAnchor() {
    for smooth in [false, true] {
      let (scroll, follower) = fixture(), attempt = UUID()
      var retired: [Int] = []
      let notify: (PromptWordRetirement) -> Void = { retired.append($0.firstRetainedWordIndex) }
      update(follower, text: "aa\nbb cc dd", active: 0, offsets: [0: 0, 3: 3, 6: 6, 9: 9],
        attempt: attempt, smooth: smooth, notify: notify)
      update(follower, text: "aa\nbb cc dd", active: 6, offsets: [0: 0, 3: 3, 6: 6, 9: 9],
        attempt: attempt, smooth: smooth, notify: notify)
      update(follower, text: "aa\nbb\nxx\nyy cc dd", active: 6,
        offsets: [0: 0, 3: 3, 6: 12, 9: 15], attempt: attempt, smooth: smooth, notify: notify)
      finish()
      update(follower, text: "bb\nxx\nyy cc dd", active: 6,
        offsets: [3: 0, 6: 9, 9: 12], retained: 1, attempt: attempt, smooth: smooth, notify: notify)
      finish()
      update(follower, text: "bb\nxx\nyy cx dd", active: 6,
        offsets: [3: 0, 6: 9, 9: 12], retained: 1, attempt: attempt, smooth: smooth, notify: notify)
      finish()
      XCTAssertEqual(retired, smooth ? [1] : [1, 2], "smooth=\(smooth)")
      withExtendedLifetime(scroll) { follower.removeFromSuperview() }
    }
  }

  func testOrdinaryWordAdvanceKeepsItsPreRemovalAnchorOnImmediatePath() {
    for smooth in [false, true] {
      let (scroll, follower) = fixture(), attempt = UUID()
      var retired: [Int] = []
      let notify: (PromptWordRetirement) -> Void = { retired.append($0.firstRetainedWordIndex) }
      let text = "aa\nbb cc\ndd ee ff"
      let offsets = [0: 0, 3: 3, 6: 6, 9: 9]
      for active in [0, 6, 9] {
        update(follower, text: text, active: active, offsets: offsets,
          attempt: attempt, smooth: smooth, notify: notify)
      }
      finish()
      XCTAssertEqual(retired, [1])
      update(follower, text: "bb cc\ndd ee ff", active: 9,
        offsets: [3: 0, 6: 3, 9: 6], retained: 1, attempt: attempt, smooth: smooth, notify: notify)
      finish()
      update(follower, text: "bb cc\nxx\ndd ee ff", active: 9,
        offsets: [3: 0, 6: 3, 9: 9], retained: 1, attempt: attempt, smooth: smooth, notify: notify)
      finish()
      XCTAssertEqual(retired, smooth ? [1, 3] : [1], "smooth=\(smooth)")
      withExtendedLifetime(scroll) { follower.removeFromSuperview() }
    }
  }

  func testRealWordUpdateCoalescedAfterPrefixRebuildIsNotDropped() {
    let (scroll, follower) = fixture(), attempt = UUID()
    var retired: [Int] = []
    let notify: (PromptWordRetirement) -> Void = { retired.append($0.firstRetainedWordIndex) }
    update(follower, text: "aa\nbb cc dd", active: 0, offsets: [0: 0, 3: 3, 6: 6, 9: 9],
      attempt: attempt, smooth: false, notify: notify)
    update(follower, text: "aa\nbb cc dd", active: 6, offsets: [0: 0, 3: 3, 6: 6, 9: 9],
      attempt: attempt, smooth: false, notify: notify)
    update(follower, text: "aa\nbb\nxx\nyy cc dd", active: 6,
      offsets: [0: 0, 3: 3, 6: 12, 9: 15], attempt: attempt, smooth: false, notify: notify)
    XCTAssertEqual(retired, [1])
    update(follower, text: "bb\nxx\nyy cc dd", active: 6,
      offsets: [3: 0, 6: 9, 9: 12], retained: 1, attempt: attempt, smooth: false, pump: false, notify: notify)
    update(follower, text: "bb\nxx\nyy cx dd", active: 6,
      offsets: [3: 0, 6: 9, 9: 12], retained: 1, attempt: attempt, smooth: false, notify: notify)
    XCTAssertEqual(retired, [1, 2])
    withExtendedLifetime(scroll) { follower.removeFromSuperview() }
  }

  func testCoalescedWordAdvanceRunsAfterPrefixCoordinatesReset() {
    for smooth in [false, true] {
      let (scroll, follower) = fixture(), attempt = UUID()
      var retired: [Int] = []
      let notify: (PromptWordRetirement) -> Void = { retired.append($0.firstRetainedWordIndex) }
      for active in [0, 3, 6] {
        update(follower, text: "aa\nbb\ncc\ndd", active: active,
          offsets: [0: 0, 3: 3, 6: 6, 9: 9], attempt: attempt, smooth: smooth, notify: notify)
      }
      finish()
      XCTAssertEqual(retired, [1])
      update(follower, text: "bb\ncc\ndd", active: 6,
        offsets: [3: 0, 6: 3, 9: 6], retained: 1, attempt: attempt, smooth: smooth, pump: false, notify: notify)
      update(follower, text: "bb\ncc\ndd", active: 9,
        offsets: [3: 0, 6: 3, 9: 6], retained: 1, attempt: attempt, smooth: smooth, notify: notify)
      finish()
      XCTAssertEqual(retired, [1, 2], "smooth=\(smooth)")
      withExtendedLifetime(scroll) { follower.removeFromSuperview() }
    }
  }

  func testPinnedComposedCallbacksKeepDifferentAnchorsAndFollowupDecisions() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference checkout")
    }
    struct Snapshot: Decodable { let first: Int, top: Double, baseline: Double, margin: Double }
    struct Fixture: Decodable { let scenario: String, smooth: Bool, afterFirst: Snapshot, afterFollowup: Snapshot }
    let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules",
      project.appendingPathComponent("Scripts/check-source-prefix-baseline.mjs").path, reference, "--emit-fixtures"]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode([Fixture].self, from: data)
    XCTAssertEqual(fixtures.count, 8)
    for fixture in fixtures {
      XCTAssertEqual(fixture.afterFirst.margin, 0)
      XCTAssertEqual(fixture.afterFollowup.margin, 0)
      switch fixture.scenario {
      case "multirow":
        XCTAssertEqual(fixture.afterFirst.top, 90)
        XCTAssertEqual(fixture.afterFirst.baseline, fixture.smooth ? 90 : 45)
        XCTAssertEqual(fixture.afterFollowup.first, fixture.smooth ? 1 : 2)
      case "advance":
        XCTAssertEqual(fixture.afterFirst.top, 45)
        XCTAssertEqual(fixture.afterFirst.baseline, fixture.smooth ? 45 : 90)
        XCTAssertEqual(fixture.afterFollowup.first, fixture.smooth ? 3 : 1)
      case "first":
        XCTAssertEqual(fixture.afterFirst.first, 0)
        XCTAssertEqual(fixture.afterFirst.baseline, 45)
        XCTAssertEqual(fixture.afterFollowup.first, 1)
      case "nextActive":
        XCTAssertEqual(fixture.afterFirst.top, 45)
        XCTAssertEqual(fixture.afterFirst.baseline, fixture.smooth ? 45 : 90)
        XCTAssertEqual(fixture.afterFollowup.first, 3)
      default: XCTFail("Unexpected fixture")
      }
    }
  }
}
