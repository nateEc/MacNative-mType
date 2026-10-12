import Foundation
import XCTest
@testable import Typebar

final class SlowWordCopySourceTests: XCTestCase {
  func testEmptySelectedTargetIsNotTheSameAsNoSelectedWords() {
    let reviews = [TypedWordReview(index: 0, target: "", typed: " ")]
    XCTAssertEqual(SlowWordCopyPolicy.words(reviews: reviews, bursts: [0], below: 80), [""])
    XCTAssertEqual(SlowWordCopyPolicy.words(reviews: reviews, bursts: [nil], below: 80), [])
  }

  func testCompletePinnedCallbackMatchesNativeSelectionAndThreshold() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference checkout")
    }
    struct Fixture: Decodable {
      let name: String, zen: Bool, targets: [String], inputs: [String]
      let bursts: [Int?], threshold: Double, expected: [String], defaultThreshold: Double
      let copiedText: String?
    }
    let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", project.appendingPathComponent("Scripts/check-source-slow-word-copy.mjs").path,
      reference, "--emit-fixtures"]
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode([Fixture].self, from: data)
    XCTAssertEqual(fixtures.count, 6)
    let start = Date(timeIntervalSince1970: 1000)
    for item in fixtures {
      let configuration: TestConfiguration = item.zen
        ? .init(mode: .zen, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()) : .words(3)
      let result = CompletedTestResult(id: UUID(), configuration: configuration, outcome: .completed,
        startedAt: start, finishedAt: start.addingTimeInterval(3), typedCharacterCount: 3,
        correctCharacterCount: 3, errorCount: 0, wpm: 12, rawWpm: 12, accuracy: 100,
        prompt: item.targets.joined(separator: " "), replayEvents: item.inputs.enumerated().map { index, text in
          .init(offset: Double(index) / 10, kind: .insert, text: text,
            inputField: .init(index: index, value: text))
        })
      let reviews = item.targets.prefix(item.inputs.count).enumerated().map { index, target in
        TypedWordReview(index: index, target: target, typed: item.inputs[index])
      }
      let words = SlowWordCopyPolicy.words(for: result, reviews: reviews,
        bursts: item.bursts, below: item.threshold)
      XCTAssertEqual(words, item.expected, item.name)
      XCTAssertEqual(words.isEmpty ? nil : words.joined(separator: " "), item.copiedText, item.name)
      XCTAssertEqual(SlowWordCopyPolicy.defaultThreshold(bursts: item.bursts), item.defaultThreshold, item.name)
    }
  }
}
