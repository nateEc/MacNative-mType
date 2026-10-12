import XCTest
@testable import Typebar

@MainActor final class LiveContinuationAssemblyTests: XCTestCase {
  func testContinuationMatchesIndependentSynchronousSliceAcrossBudgets() async throws {
    let tokens = (0..<1002).map { ["e\u{301}", "👩🏽‍💻", "中文", "سلام", "", "two\nlines"][$0 % 6] }
    for separator in [" ", "", "\n"] {
      let content = LivePracticeContent(source: .encyclopedia, title: "Owned", byline: nil,
        tokens: tokens, separator: separator)
      for configuration in [TestConfiguration.words(301), .words(1001), .words(0),
        .timed(seconds: 30), .words(1001).with(modifiers: [.focusNextWord])] {
        for whole in [false, true] {
          let actual = try await content.preparingContinuationDescriptor(for: configuration, showAllLines: whole)
          let expected = content.continuationDescriptor(for: configuration, showAllLines: whole)
          XCTAssertEqual(actual?.text.utf8.map { $0 }, expected?.text.utf8.map { $0 })
          XCTAssertEqual(actual?.noSpaceBoundarySource?.utf8.map { $0 },
            expected?.noSpaceBoundarySource?.utf8.map { $0 })
        }
      }
    }
  }

  func testLargeRetainedTailIsNotTruncated() async throws {
    let content = LivePracticeContent(source: .poetry, title: "Owned", byline: nil,
      tokens: (0..<100_002).map { "owned\($0)" }, separator: " ")
    let configuration = TestConfiguration.words(0)
    let actual = try await content.preparingContinuationDescriptor(for: configuration)
    XCTAssertEqual(actual, content.continuationDescriptor(for: configuration))
    XCTAssertTrue(try XCTUnwrap(actual).text.hasSuffix("owned100001"))
  }

  func testFirstAndFinalBatchCancellationDoesNotReturnTail() async throws {
    let content = LivePracticeContent(source: .poetry, title: "Owned", byline: nil,
      tokens: Array(repeating: "harbor", count: 1001), separator: " ")
    let configuration = TestConfiguration.words(0)
    let total = try XCTUnwrap(content.continuationDescriptor(for: configuration)).text.split(separator: " ").count
    for cancelAt in [100, total] {
      var batches: [Int] = []
      let task = Task { @MainActor in
        try await content.preparingContinuationDescriptor(for: configuration, didAssemble: {
          batches.append($0)
          if $0 == cancelAt { withUnsafeCurrentTask { $0?.cancel() } }
        })
      }
      do { _ = try await task.value; XCTFail("Cancelled continuation must not be returned") }
      catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
      XCTAssertEqual(batches.last, cancelAt)
    }
  }

  func testNoTailRemainsNilWithoutAssembly() async throws {
    let content = LivePracticeContent(source: .poetry, title: "Owned", byline: nil,
      tokens: ["harbor"], separator: " ")
    let result = try await content.preparingContinuationDescriptor(for: .words(1), showAllLines: true,
      didAssemble: { _ in XCTFail("No remaining tokens to assemble") })
    XCTAssertNil(result)
  }
}
