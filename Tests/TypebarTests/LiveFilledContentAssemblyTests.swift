import XCTest
@testable import Typebar

@MainActor final class LiveFilledContentAssemblyTests: XCTestCase {
  func testFilledTextAndMetadataMatchIndependentInitializerWithOversupply() async throws {
    let firstTokens = ["e\u{301}", "", "👩🏽‍💻"]
    let nextTokens = (0..<301).map { ["中文", "سلام", "two\nlines", ""][$0 % 4] }
    for source: LivePracticeContentSource in [.poetry, .encyclopedia] {
      for separator in [" ", "", "\n"] {
        let first = LivePracticeContent(source: source, title: "First", byline: "A",
          tokens: firstTokens, separator: separator)
        var fetches = 0
        var batches: [Int] = []
        let result = await first.fillingInitialPrompt(for: .words(201), showAllLines: true,
          didAssemble: { batches.append($0) }) {
          fetches += 1
          return .init(source: source, title: "Next", byline: "B",
            tokens: nextTokens, separator: separator)
        }
        let actual = try XCTUnwrap(result)
        let expected = LivePracticeContent(source: source, title: "First / Next", byline: "A / B",
          tokens: firstTokens + nextTokens, separator: separator)
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(Array(actual.text.utf8), Array(expected.text.utf8))
        XCTAssertEqual(batches, [100, 200, 300, 304])
        XCTAssertEqual(fetches, 1)
        XCTAssertEqual(actual.continuationDescriptor(for: .words(304)),
          expected.continuationDescriptor(for: .words(304)))
      }
    }
  }

  func testRetainedContentDoesNotFetchOrReassemble() async throws {
    let content = LivePracticeContent(source: .poetry, title: "Owned", byline: nil,
      tokens: Array(repeating: "harbor", count: 100_002), separator: " ")
    let result = await content.fillingInitialPrompt(for: .words(100_001), showAllLines: true,
      didAssemble: { _ in XCTFail("Retained text must not be rejoined") }) {
      XCTFail("Retained tokens already cover the budget"); return nil
    }
    XCTAssertEqual(try XCTUnwrap(result), content)
  }

  func testCancellationDuringFirstOrFinalAssemblyBatchNeverReturnsFilledContent() async {
    for cancelledBatch in [100, 301] {
      var batches: [Int] = []
      let task = Task { @MainActor in
        await LivePracticeContent(source: .poetry, title: "First", byline: nil,
          tokens: ["first"], separator: " ")
          .fillingInitialPrompt(for: .words(201), showAllLines: true,
            didAssemble: { count in
              batches.append(count)
              if count == cancelledBatch { withUnsafeCurrentTask { $0?.cancel() } }
            }) {
            .init(source: .poetry, title: "Next", byline: nil,
              tokens: Array(repeating: "harbor", count: 300), separator: " ")
          }
      }
      let result = await task.value
      XCTAssertNil(result)
      XCTAssertEqual(batches, cancelledBatch == 100 ? [100] : [100, 200, 300, 301])
    }
  }
}
