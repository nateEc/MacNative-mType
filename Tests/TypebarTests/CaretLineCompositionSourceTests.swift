import Foundation
import XCTest
@testable import Typebar

/// Complete-source contract plus a native first-jump sample comparison.
/// This does not prove all native queue orders or browser pixel equivalence.
@MainActor final class CaretLineCompositionSourceTests: XCTestCase {
  private struct Marker: Decodable {
    let left: Double, top: Double, width: Double, margin: Double, visibleTop: Double
    let ready: Bool
  }
  private struct Sample: Decodable {
    let time: Int, first: Int, wordMargin: Double, activeTop: Double
    let main: Marker, pace: Marker
  }
  private struct Animation: Decodable {
    let id: String, channel: String, duration: Double, ease: String, completed: Bool
  }
  private struct Write: Decodable {
    let time: Int, id: String, top: String?
  }
  private struct Fixture: Decodable {
    let smooth: Bool, motion: SmoothCaretMotion, style: String, overlap: Bool
    let samples: [Sample], beforeRefresh: Sample, afterRefresh: Sample, settled: Sample
    let resets: [Write], animations: [Animation]
  }
  private static var cachedFixtures: [Fixture]?

  private func evidence() throws -> [Fixture] {
    if let fixtures = Self.cachedFixtures { return fixtures }
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference checkout")
    }
    let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules",
      project.appendingPathComponent("Scripts/check-source-caret-line-composition.mjs").path,
      reference, "--emit-fixtures"]
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode([Fixture].self, from: data)
    XCTAssertEqual(fixtures.count, 48)
    Self.cachedFixtures = fixtures
    return fixtures
  }

  func testCompleteSourcePositionChannelsUseNativeSpeedChoicesButDifferentEasings() throws {
    for fixture in try evidence() {
      let positions = fixture.animations.filter { $0.id == "caret" && $0.channel == "position" }
      XCTAssertEqual(positions.count, fixture.motion == .off ? 0 : fixture.overlap ? 3 : 2)
      for animation in positions {
        XCTAssertEqual(animation.duration / 1000, try XCTUnwrap(fixture.motion.duration), accuracy: 1e-9)
        XCTAssertEqual(animation.ease, "inOut(1.25)")
      }
      let pace = fixture.animations.filter { $0.id == "paceCaret" && $0.channel == "position" }
      XCTAssertFalse(pace.isEmpty)
      XCTAssertTrue(pace.allSatisfy { $0.ease == "linear" })
    }
  }

  func testSourceCaretMarginsShareWordsCurveBeforeOverlapWhilePositionIsIndependent() throws {
    for fixture in try evidence() where fixture.smooth {
      let sample = try XCTUnwrap(fixture.samples.first { $0.time == 25 })
      let expected = -45 * PromptLineScrollMotion.progress(
        elapsed: 0.025 + PromptLineScrollMotion.autoplayLead)
      XCTAssertEqual(sample.wordMargin, expected, accuracy: 1e-6)
      XCTAssertEqual(sample.main.margin, expected, accuracy: 1e-6)
      XCTAssertEqual(sample.pace.margin, expected, accuracy: 1e-6)
      XCTAssertEqual(sample.main.visibleTop, sample.main.top + sample.main.margin, accuracy: 1e-9)
      if fixture.motion == .off {
        XCTAssertEqual(sample.main.top, 90 + (fixture.style == "underline" ? 33 : 0))
      } else {
        XCTAssertGreaterThan(sample.main.top, 45 + (fixture.style == "underline" ? 33 : 0))
        XCTAssertLessThan(sample.main.top, 90 + (fixture.style == "underline" ? 33 : 0))
      }
    }
  }

  func testNativeMainChannelsMatchCompleteSourceBeforeOverlapAcrossAllFixtureChoices() throws {
    for fixture in try evidence() {
      var caret = PromptCaretChannel()
      let underline: CGFloat = fixture.style == "underline" ? 33 : 0
      caret.goTo(.init(x: 0, y: 45 + underline, width: 12, height: 33), at: 0, duration: 0)
      caret.lineJump(to: -45, at: 0, duration: fixture.smooth ? 0.125 : 0, isPace: false)
      caret.goTo(.init(x: 0, y: (fixture.smooth ? 90 : 45) + underline, width: 12, height: 33),
        at: 0, duration: fixture.motion.duration ?? 0)
      caret.sample(at: 0.025)
      let source = try XCTUnwrap(fixture.samples.first { $0.time == 25 })
      XCTAssertEqual(try XCTUnwrap(caret.position).minY, source.main.top, accuracy: 1e-8)
      XCTAssertEqual(caret.margin, source.main.margin, accuracy: 1e-8)
      XCTAssertEqual(try XCTUnwrap(caret.visibleRect).minY, source.main.visibleTop, accuracy: 1e-8)
    }
  }

  func testImmediateLineJumpSkipsMainMarginButRetainsPaceMarginUntilItsOwnGoTo() throws {
    for fixture in try evidence() where !fixture.smooth {
      let start = try XCTUnwrap(fixture.samples.first)
      XCTAssertEqual(start.main.margin, 0)
      XCTAssertFalse(start.main.ready)
      XCTAssertEqual(start.pace.margin, -45)
      XCTAssertTrue(start.pace.ready)
      XCTAssertEqual(start.wordMargin, 0)
      XCTAssertEqual(start.first, 1)
      XCTAssertTrue(fixture.animations.filter { $0.channel == "margin" }.isEmpty)
      XCTAssertEqual(fixture.beforeRefresh.main.margin, 0)
    }
  }

  func testSmoothCompletionFoldsAtNextPositionUpdateAndOnlyNewestMarginCompletes() throws {
    for fixture in try evidence() where fixture.smooth {
      let before = fixture.beforeRefresh, after = fixture.afterRefresh
      XCTAssertEqual(before.wordMargin, 0)
      XCTAssertTrue(before.main.ready)
      XCTAssertEqual(before.main.margin, fixture.overlap ? -90 : -45)
      XCTAssertEqual(after.main.margin, 0)
      XCTAssertFalse(after.main.ready)
      let fold = try XCTUnwrap(fixture.resets.last { $0.time == 199 && $0.id == "caret" && $0.top != nil })
      let top = try XCTUnwrap(fold.top?.dropLast(2)).description
      XCTAssertEqual(try XCTUnwrap(Double(top)), before.main.visibleTop, accuracy: 1e-8)
      for id in ["caret", "paceCaret", "words"] {
        let margins = fixture.animations.filter { $0.id == id && $0.channel == "margin" }
        XCTAssertEqual(margins.count, fixture.overlap ? 2 : 1)
        XCTAssertEqual(margins.map(\.completed), fixture.overlap ? [false, true] : [true])
      }
      XCTAssertEqual(fixture.settled.first, fixture.overlap ? 2 : 1)
      XCTAssertEqual(fixture.settled.main.visibleTop, 45 + (fixture.style == "underline" ? 33 : 0))
    }
  }
}
