import XCTest
@testable import Typebar

final class WebsiteKeymapClockQuantizationTests: XCTestCase {
  func testFractionalCreationAndTicksAgainstCompletePinnedWrapperAndEngine() throws {
    let env = ProcessInfo.processInfo.environment
    guard let reference = env["TYPEBAR_REFERENCE_ROOT"] ?? env["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference checkout")
    }
    struct Frame: Decodable { let elapsed: Double, clockTime: Double, progress: Double, foreground: Double }
    struct Fixture: Decodable {
      let rate: Int, warmup: Double, mode: String, startedAt: Double, duration: Double, initial: Double
      let frames: [Frame], completedAt: Double
    }
    struct Output: Decodable { let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-keymap-autoplay.mjs").path,
      reference, "--quantized-clock"]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 60)
    var checked = 0, failures = 0, crossedBoundaries = 0, examples: [String] = []
    for fixture in fixtures {
      XCTAssertEqual(WebsiteKeymapAnimationTiming.initial(duration: fixture.duration / 1000).progress, fixture.initial)
      for frame in fixture.frames {
        let sample = WebsiteKeymapAnimationTiming.sample(startedAt: fixture.startedAt / 1000,
          now: frame.clockTime / 1000, duration: fixture.duration / 1000)
        let completed = frame.elapsed == fixture.completedAt
        if abs(sample.progress - frame.progress) > 1e-8 || abs(sample.progress - frame.foreground) > 1e-8
          || sample.complete != completed {
          failures += 1
          if examples.count < 8 { examples.append("\(fixture.rate)/\(fixture.warmup)/\(fixture.mode) t=\(frame.clockTime) native=\(sample.progress) source=\(frame.progress)") }
        }
        if floor(frame.elapsed) != floor(frame.clockTime) - floor(fixture.startedAt) { crossedBoundaries += 1 }
        checked += 1
      }
    }
    XCTAssertGreaterThan(checked, 1000); XCTAssertGreaterThan(crossedBoundaries, 100)
    XCTAssertEqual(failures, 0, examples.joined(separator: "\n"))
    print("Pinned integer-clock wrapper: \(fixtures.count) combinations / \(checked) actual frames / \(crossedBoundaries) independent rounding boundaries")
  }

  func testDistinctAbsoluteMillisecondBoundariesAndCompletion() {
    // Both spans are 0.25ms; only the second crosses an integer clock boundary.
    let within = WebsiteKeymapAnimationTiming.sample(startedAt: 10.000125, now: 10.000375, duration: 0.25)
    let across = WebsiteKeymapAnimationTiming.sample(startedAt: 10.000875, now: 10.001125, duration: 0.25)
    XCTAssertEqual(within.progress, WebsiteKeymapAnimationTiming.sample(elapsed: 0, duration: 0.25).progress)
    XCTAssertEqual(across.progress, WebsiteKeymapAnimationTiming.sample(elapsed: 0.001, duration: 0.25).progress)
    XCTAssertFalse(WebsiteKeymapAnimationTiming.sample(startedAt: 10.000875, now: 10.237999, duration: 0.25).complete)
    XCTAssertTrue(WebsiteKeymapAnimationTiming.sample(startedAt: 10.000875, now: 10.238125, duration: 0.25).complete)
    XCTAssertTrue(WebsiteKeymapAnimationTiming.initial(duration: 0).complete)
    XCTAssertTrue(WebsiteKeymapAnimationTiming.sample(startedAt: 10.000875, now: 10.000875, duration: 0).complete)
  }
}
