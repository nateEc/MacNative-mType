import XCTest
@testable import Typebar

final class WebsiteKeymapAutoplaySourceTests: XCTestCase {
  func testCompletePinnedWrapperAutoplayFramesMatchNativeProgressAndCompletion() throws {
    let env = ProcessInfo.processInfo.environment
    guard let reference = env["TYPEBAR_REFERENCE_ROOT"] ?? env["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference checkout")
    }
    struct Frame: Decodable { let elapsed: Double, progress: Double, foreground: Double }
    struct Fixture: Decodable {
      let rate: Int, warmup: Int, mode: String, duration: Double, initial: Double
      let frames: [Frame], completedAt: Double
    }
    struct Output: Decodable { let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-keymap-autoplay.mjs").path, reference]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 45)
    var failures = 0, checked = 0, examples: [String] = []
    for fixture in fixtures {
      let initial = WebsiteKeymapAnimationTiming.sample(elapsed: 0, duration: fixture.duration / 1000)
      XCTAssertEqual(initial.progress, fixture.initial)
      XCTAssertEqual(initial.complete, fixture.completedAt == 0)
      if fixture.duration > 0 { XCTAssertFalse(fixture.frames.isEmpty) }
      for frame in fixture.frames {
        let sample = WebsiteKeymapAnimationTiming.sample(elapsed: frame.elapsed / 1000, duration: fixture.duration / 1000)
        if abs(sample.progress - frame.progress) > 0.000_000_01 || abs(sample.progress - frame.foreground) > 0.000_000_01
          || sample.complete != (frame.elapsed == fixture.completedAt) {
          failures += 1
          if examples.count < 5 {
            examples.append("\(fixture.rate)/\(fixture.warmup)/\(fixture.mode) t=\(frame.elapsed) native=\(sample.progress) source=\(frame.progress)")
          }
        }
        checked += 1
      }
      XCTAssertTrue(WebsiteKeymapAnimationTiming.sample(elapsed: fixture.completedAt / 1000,
        duration: fixture.duration / 1000).complete)
    }
    XCTAssertGreaterThan(checked, 1000)
    XCTAssertEqual(failures, 0, examples.joined(separator: "\n"))
    print("Pinned complete wrapper autoplay: \(fixtures.count) combinations / \(checked) actual engine frames")
  }
}
