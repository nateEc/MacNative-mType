import AppKit
import XCTest
@testable import Typebar

final class PromptCaretMotionTests: XCTestCase {
  private func rect(_ y: CGFloat, x: CGFloat = 0) -> CGRect {
    .init(x: x, y: y, width: 12, height: 33)
  }

  func testPositionAndLineChannelsAdvanceIndependentlyWithAutoplayLead() throws {
    var caret = PromptCaretChannel()
    caret.goTo(rect(45), at: 0, duration: 0)
    caret.lineJump(to: -45, at: 0, duration: 0.125, isPace: false)
    caret.goTo(rect(90), at: 0, duration: 0.15)
    caret.sample(at: 0.025)
    let t = 0.037 / 0.15
    XCTAssertEqual(try XCTUnwrap(caret.position).minY,
      45 + 45 * pow(2 * t, 1.25) / 2, accuracy: 1e-8)
    XCTAssertEqual(caret.margin, -45 * PromptLineScrollMotion.progress(elapsed: 0.037), accuracy: 1e-8)
    XCTAssertEqual(try XCTUnwrap(caret.visibleRect).minY,
      try XCTUnwrap(caret.position).minY + caret.margin, accuracy: 1e-8)
    XCTAssertFalse(caret.marginReady)
  }

  func testCompletedMarginSurvivesPrefixRebuildAndFoldsOnlyAtValidGoTo() throws {
    var caret = PromptCaretChannel()
    caret.goTo(rect(90), at: 0, duration: 0)
    caret.lineJump(to: -45, at: 0, duration: 0.125, isPace: false)
    caret.sample(at: 0.2)
    XCTAssertTrue(caret.marginReady)
    XCTAssertEqual(caret.margin, -45)
    let before = caret.visibleRect
    caret.goTo(nil, at: 0.2, duration: 0.15)
    XCTAssertTrue(caret.marginReady, "Missing pruned targets must not consume the folding flag")
    XCTAssertEqual(caret.visibleRect, before)
    caret.goTo(rect(45, x: 12), at: 0.2, duration: 0.15)
    XCTAssertEqual(caret.margin, 0)
    XCTAssertFalse(caret.marginReady)
    XCTAssertEqual(caret.position, before, "The fold itself preserves the presentation position")
    caret.sample(at: 0.4)
    XCTAssertEqual(caret.visibleRect, rect(45, x: 12))
  }

  func testImmediateMainAndPaceLineJumpsHaveDifferentContracts() throws {
    var main = PromptCaretChannel(), pace = PromptCaretChannel()
    main.goTo(rect(90), at: 0, duration: 0)
    pace.goTo(rect(90), at: 0, duration: 0)
    main.lineJump(to: -45, at: 0, duration: 0, isPace: false)
    pace.lineJump(to: -45, at: 0, duration: 0, isPace: true)
    XCTAssertEqual(main.margin, 0)
    XCTAssertFalse(main.marginReady)
    XCTAssertEqual(pace.margin, -45)
    XCTAssertTrue(pace.marginReady)
    XCTAssertEqual(try XCTUnwrap(pace.visibleRect).minY, 45)
  }

  func testReplacementSamplesOldMarginAndOnlyNewestCanComplete() {
    var caret = PromptCaretChannel()
    caret.goTo(rect(135), at: 0, duration: 0)
    caret.lineJump(to: -45, at: 0, duration: 0.125, isPace: false)
    caret.sample(at: 0.04)
    let interrupted = caret.margin
    caret.lineJump(to: -90, at: 0.04, duration: 0.125, isPace: false)
    XCTAssertEqual(caret.margin, interrupted)
    caret.sample(at: 0.12)
    XCTAssertFalse(caret.marginReady)
    XCTAssertLessThan(caret.margin, interrupted)
    caret.sample(at: 0.16)
    XCTAssertTrue(caret.marginReady)
    XCTAssertEqual(caret.margin, -90)
    caret.lineJump(to: -45, at: 0.2, duration: 0.125, isPace: false)
    XCTAssertEqual(caret.margin, 0, "A later line jump clears a ready margin without folding position")
  }

  func testGoToSubtractsUnfinishedMarginAndCancellationFreezesPresentation() throws {
    var caret = PromptCaretChannel()
    caret.goTo(rect(90), at: 0, duration: 0)
    caret.lineJump(to: -45, at: 0, duration: 0.125, isPace: true)
    caret.sample(at: 0.025)
    let margin = caret.margin
    caret.goTo(rect(80), at: 0.025, duration: 0)
    XCTAssertEqual(try XCTUnwrap(caret.position).minY, 80 - margin, accuracy: 1e-8)
    XCTAssertEqual(try XCTUnwrap(caret.visibleRect).minY, 80, accuracy: 1e-8)
    caret.cancel(at: 0.05)
    let frozen = caret.visibleRect
    caret.sample(at: 1)
    XCTAssertEqual(caret.visibleRect, frozen)
    XCTAssertFalse(caret.marginReady)
  }

  func testOverlappedMarginCompletesAtItsAbsoluteDeadlineWithoutAnExtraFrame() {
    for isPace in [false, true] {
      var caret = PromptCaretChannel()
      caret.goTo(rect(135), at: 0, duration: 0)
      caret.lineJump(to: -45, at: 0, duration: 0.125, isPace: isPace)
      caret.sample(at: 0.04)
      caret.lineJump(to: -90, at: 0.04, duration: 0.125, isPace: isPace)
      caret.sample(at: 0.153 - 0.000001)
      XCTAssertFalse(caret.marginReady, "A real frame before the deadline must not finish early")
      caret.sample(at: 0.153)
      XCTAssertTrue(caret.marginReady, "Floating subtraction must not postpone completion one frame")
      XCTAssertEqual(caret.margin, -90)
      caret.lineJump(to: -45, at: 0.153, duration: 0.125, isPace: isPace)
      XCTAssertEqual(caret.margin, 0, "A jump on the completion frame resets the ready margin")
    }
  }

  func testAbsoluteCompletionAcrossSpeedsAndLargeMonotonicClockOrigins() {
    for origin in [0.0, 0.04, 1_000_000.0] {
      for duration in [0.085, 0.1, 0.125, 0.15] {
        for curve: PromptCaretChannel.Curve in [.position, .linear] {
          var caret = PromptCaretChannel()
          caret.goTo(rect(45), at: origin, duration: 0)
          caret.goTo(rect(90, x: 12), at: origin, duration: duration, curve: curve)
          caret.lineJump(to: -45, at: origin, duration: duration, isPace: false)
          let deadline = origin + (duration - PromptLineScrollMotion.autoplayLead)
          caret.sample(at: deadline - 0.000001)
          XCTAssertFalse(caret.marginReady)
          XCTAssertNotEqual(caret.position, rect(90, x: 12))
          caret.sample(at: deadline)
          XCTAssertTrue(caret.marginReady)
          XCTAssertEqual(caret.margin, -45)
          XCTAssertEqual(caret.position, rect(90, x: 12))
        }
      }
    }
  }
}
