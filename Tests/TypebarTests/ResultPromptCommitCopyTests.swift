import XCTest
@testable import Typebar

final class ResultPromptCommitCopyTests: XCTestCase {
  private func result(prompt: String, fields: [String]) -> CompletedTestResult {
    let start = Date(timeIntervalSince1970: 1000)
    return .init(id: UUID(), configuration: .timed(seconds: 30), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(3), typedCharacterCount: 10,
      correctCharacterCount: 9, errorCount: 1, wpm: 20, rawWpm: 22, accuracy: 90,
      prompt: prompt, replayEvents: fields.enumerated().map { index, field in
        .init(offset: Double(index) / 10, kind: .insert, text: field,
          inputField: .init(index: index, value: field))
      })
  }

  func testReachedTargetKeepsItsSourceCommitInsteadOfTypedMisspelling() {
    let value = result(prompt: "harbor\nriver future", fields: ["wrong\n"])
    XCTAssertEqual(ResultPromptText.make(for: value, reviews: [
      .init(index: 0, target: "harbor", typed: "wrong", hasInputError: true),
    ]), "harbor\n")
  }

  func testBlankFieldsTabsAndPartialFinalWordKeepOriginalStructure() {
    let value = result(prompt: "harbor\n\nri\tver next future", fields: ["harbor\n", "\n", "ri"])
    XCTAssertEqual(ResultPromptText.make(for: value, reviews: [
      .init(index: 0, target: "harbor", typed: "harbor"),
      .init(index: 1, target: "", typed: ""),
      .init(index: 2, target: "ri\tver", typed: "ri"),
    ]), "harbor\n\nri\tver ")
  }

  func testInputHistoryBoundsCopyEvenWhenReviewsIncludeFutureTargets() {
    let value = result(prompt: "朝 harbor future", fields: ["朝 "])
    XCTAssertEqual(ResultPromptText.make(for: value, reviews: [
      .init(index: 0, target: "朝", typed: "朝"),
      .init(index: 1, target: "harbor", typed: ""),
    ]), "朝 ")
    XCTAssertEqual(ResultPromptText.make(for: result(prompt: "e\u{301}", fields: ["x"]),
      reviews: [] )?.utf16.map { $0 }, [0x65, 0x301])
  }

  func testLegacyReviewFallbackKeepsSourceCommitButEmptyHistoryCopiesNothing() {
    let value = result(prompt: "harbor\nfuture", fields: [])
    XCTAssertEqual(ResultPromptText.make(for: value, reviews: [
      .init(index: 0, target: "harbor", typed: "x"),
    ]), "harbor\n")
    XCTAssertNil(ResultPromptText.make(for: value, reviews: []))
  }
}
