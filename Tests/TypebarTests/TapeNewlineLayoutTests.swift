import AppKit
import XCTest
@testable import Typebar

@MainActor final class TapeNewlineLayoutTests: XCTestCase {
  func testCorrectReturnRemovesItsMarkerAndGapFromTheNextLineIndent() {
    let plan = TapeNewlinePlan.measure(words: [.init(index: 0, width: 48, gap: 12, newlineWidth: 12),
      .init(index: 1, width: 36, gap: 12)], active: 1, viewportWidth: 400)
    XCTAssertEqual(plan.beforeActive, 36)
    XCTAssertEqual(plan.indents[0], 36)
  }

  func testCompletePinnedNewlineScrollMatchesNativeCumulativeLayout() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"],
      ProcessInfo.processInfo.environment["TYPEBAR_LINE_SCROLL_ANIME_ARCHIVE"] != nil else {
      throw XCTSkip("Readiness supplies pinned reference and locked animation archive")
    }
    struct Word: Decodable { let index: Int; let width, gap: Double; let newlineWidth: Double? }
    struct Sample: Decodable { let milliseconds: Int; let indents: [String: Double] }
    struct Fixture: Decodable {
      let active: Int; let smooth: Bool; let viewportWidth, beforeActive: Double
      let words: [Word]; let indents: [String: Double]; let samples: [Sample]
    }
    struct Output: Decodable { let pin: String; let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-tape-newlines.mjs").path, reference, "--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile(), diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0, String(decoding: diagnostics, as: UTF8.self))
    guard process.terminationStatus == 0 else { return }
    let source = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(source.pin, "91bd24bb8513785c7364cbea29296ff7adafac41"); XCTAssertEqual(source.fixtures.count, 60)
    for (index, fixture) in source.fixtures.enumerated() {
      let plan = TapeNewlinePlan.measure(words: fixture.words.map {
        .init(index: $0.index, width: $0.width, gap: $0.gap, newlineWidth: $0.newlineWidth.map { CGFloat($0) })
      }, active: fixture.active, viewportWidth: fixture.viewportWidth)
      XCTAssertEqual(plan.beforeActive, fixture.beforeActive, accuracy: 1e-7, "fixture \(index)")
      // Unvisited far-future fillers retain their previous (initially zero) margin.
      for word in fixture.words where word.newlineWidth != nil {
        XCTAssertEqual(plan.indents[word.index] ?? 0, fixture.indents[String(word.index)] ?? 0,
          accuracy: 1e-7, "fixture \(index), after word \(word.index)")
      }
      var channels: [Int: PromptCaretChannel] = [:]
      for (word, indent) in plan.indents {
        var channel = PromptCaretChannel()
        channel.tapeScroll(to: indent, at: 0, duration: fixture.smooth ? 0.125 : 0)
        channels[word] = channel
      }
      XCTAssertEqual(fixture.samples.count, 5)
      for sample in fixture.samples {
        for word in fixture.words where word.newlineWidth != nil {
          channels[word.index]?.sample(at: Double(sample.milliseconds) / 1000)
          XCTAssertEqual(channels[word.index]?.tapeMargin ?? 0, sample.indents[String(word.index)] ?? 0,
            accuracy: 1e-7, "fixture \(index), word \(word.index), frame \(sample.milliseconds)ms")
        }
      }
    }
  }
}
