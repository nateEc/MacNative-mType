import AppKit
import XCTest
@testable import Typebar

/// Complete-source contract and shared-input native channel trace comparison.
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
  private struct Trace: Decodable {
    let type: String, time: Double
    let id: String?
    let left: Double?, top: Double?, width: Double?, height: Double?, duration: Double?, margin: Double?
    let linear: Bool?
    let rendered: Bool?
    let main: Marker?, pace: Marker?
  }
  private struct Fixture: Decodable {
    let frameInterval: Int
    let smooth: Bool, motion: SmoothCaretMotion, style: String, overlap: Bool
    let samples: [Sample], beforeRefresh: Sample, afterRefresh: Sample, settled: Sample
    let resets: [Write], animations: [Animation]
    let trace: [Trace]
  }
  private static var cachedFixtures: [Bool: [Fixture]] = [:]

  private func evidence(sparse: Bool = false) throws -> [Fixture] {
    if let fixtures = Self.cachedFixtures[sparse] { return fixtures }
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference checkout")
    }
    let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules",
      project.appendingPathComponent("Scripts/check-source-caret-line-composition.mjs").path,
      reference, sparse ? "--emit-sparse-fixtures" : "--emit-fixtures"]
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode([Fixture].self, from: data)
    XCTAssertEqual(fixtures.count, sparse ? 144 : 48)
    Self.cachedFixtures[sparse] = fixtures
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

  func testNativeChannelsReplayEveryRecordedSourceFrameAndResolvedRequest() throws {
    for fixture in try evidence() { try replay(fixture) }
  }

  func testIndependentSourceRequestsBetweenSparseFramesPreserveRenderedState() throws {
    for fixture in try evidence(sparse: true) { try replay(fixture) }
  }

  private func replay(_ fixture: Fixture) throws {
    var main = PromptCaretChannel(), pace = PromptCaretChannel()
    let height: CGFloat = fixture.style == "underline" ? 2 : 33
    let initial = CGRect(x: 0, y: 0, width: 2, height: height)
    main.goTo(initial, at: 0, duration: 0); pace.goTo(initial, at: 0, duration: 0)
    var samples = 0
    for event in fixture.trace {
      let time = event.time / 1000
      switch event.type {
      case "frame":
        if event.rendered == true { main.sample(at: time); pace.sample(at: time) }
      case "position":
        let target = CGRect(x: try XCTUnwrap(event.left), y: try XCTUnwrap(event.top),
          width: try XCTUnwrap(event.width), height: try XCTUnwrap(event.height))
        let duration = try XCTUnwrap(event.duration) / 1000
        if event.id == "caret" { main.goTo(target, at: time, duration: duration) }
        else { pace.goTo(target, at: time, duration: duration, curve: event.linear == true ? .linear : .position) }
      case "margin":
        if event.id == "caret" {
          main.lineJump(to: try XCTUnwrap(event.margin), at: time,
            duration: try XCTUnwrap(event.duration) / 1000, isPace: false)
        } else {
          pace.lineJump(to: try XCTUnwrap(event.margin), at: time,
            duration: try XCTUnwrap(event.duration) / 1000, isPace: true)
        }
      case "sample":
        samples += 1
        let label = "\(fixture.frameInterval)ms/\(fixture.smooth)/\(fixture.motion)/\(fixture.style)/\(fixture.overlap) @\(event.time)"
        try compare(main, source: XCTUnwrap(event.main), label: "main \(label)")
        try compare(pace, source: XCTUnwrap(event.pace), label: "pace \(label)")
      default: XCTFail("Unknown source event \(event.type)")
      }
    }
    XCTAssertEqual(samples, fixture.overlap ? 403 : 402)
  }

  private func compare(_ native: PromptCaretChannel, source: Marker, label: String) throws {
    let rect = try XCTUnwrap(native.position)
    // Stop at the first differing coordinate in a replay, retaining a bounded
    // diagnostic instead of flooding thousands of derivative assertions.
    let values: [(String, Double, Double)] = [("left", rect.minX, source.left),
      ("top", rect.minY, source.top), ("width", rect.width, source.width),
      ("margin", native.margin, source.margin),
      ("visibleTop", try XCTUnwrap(native.visibleRect).minY, source.visibleTop)]
    for (name, actual, expected) in values {
      guard actual.isFinite, expected.isFinite, abs(actual - expected) <= 1e-6 else {
        XCTFail("\(label) \(name): native \(actual), source \(expected)")
        throw NSError(domain: "CaretTraceMismatch", code: 1)
      }
    }
    XCTAssertEqual(native.marginReady, source.ready, label)
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
