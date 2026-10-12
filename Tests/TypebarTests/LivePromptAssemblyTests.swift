import XCTest
@testable import Typebar

@MainActor final class LivePromptAssemblyTests: XCTestCase {
  func testCooperativeDescriptorMatchesExactSynchronousSemantics() async throws {
    for separator in [" ", "", "\n"] {
      let content = LivePracticeContent(source: .encyclopedia, title: "Owned", byline: nil,
        tokens: ["e\u{301}", "👩🏽‍💻", "中文", "سلام", "", "two\nlines"], separator: separator)
      for configuration in [TestConfiguration.words(201), .words(0), .timed(seconds: 30)] {
        for whole in [false, true] {
          let actual = try await content.preparingPromptDescriptor(for: configuration, showAllLines: whole)
          let expected = content.promptDescriptor(for: configuration, showAllLines: whole)
          XCTAssertEqual(Array(actual.text.utf8), Array(expected.text.utf8))
          XCTAssertEqual(actual.noSpaceBoundarySource.map { Array($0.utf8) },
            expected.noSpaceBoundarySource.map { Array($0.utf8) })
        }
      }
    }
  }

  func testFullBudgetAboveOldCeilingIsPreserved() async throws {
    let content = LivePracticeContent(source: .poetry, title: "Owned", byline: nil,
      tokens: ["north", "harbor"], separator: " ")
    let configuration = TestConfiguration.words(100_001)
    let actual = try await content.preparingPromptDescriptor(for: configuration, showAllLines: true)
    XCTAssertEqual(Array(actual.text.utf8), Array(content.promptDescriptor(for: configuration, showAllLines: true).text.utf8))
    XCTAssertEqual(actual.text.split(separator: " ").count, 100_001)
  }

  func testCancellationAtFirstAndLastBatchNeverPublishesDescriptor() async {
    for limit in [100, 301, OfficialTestLimitInput.maximumValue] {
      let content = LivePracticeContent(source: .poetry, title: "Owned", byline: nil,
        tokens: ["north"], separator: " ")
      var counts: [Int] = []
      let task = Task { @MainActor in
        try await content.preparingPromptDescriptor(for: .words(limit), showAllLines: true,
          didAssemble: { counts.append($0); withUnsafeCurrentTask { $0?.cancel() } })
      }
      do { _ = try await task.value; XCTFail("Cancelled descriptor must not publish") }
      catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
      XCTAssertEqual(counts, [100])
    }
  }
}
