import XCTest
@testable import Typebar

final class ZenSlowWordCopyTests: XCTestCase {
  func testRealZenSessionExportsSlowCommittedAndActiveInputWithCommitCharacters() throws {
    let start = Date(timeIntervalSince1970: 1000)
    var session = TestSessionFactory.make(configuration: .init(mode: .zen, duration: nil,
      wordLimit: nil, difficulty: .normal, rules: .init()))
    for (offset, text) in [(0.0, "a"), (1.0, "b"), (1.1, " "), (2.0, "c"), (3.0, "d")] {
      session.insertBatch(text, at: start.addingTimeInterval(offset))
    }
    session.finishZen(at: start.addingTimeInterval(4))
    let value = try XCTUnwrap(session.result())
    XCTAssertFalse(session.wordReviews.isEmpty,
      "Zen currently supplies target-shaped reviews; export must still use its recorded input fields")
    XCTAssertNotEqual(SlowWordCopyPolicy.words(reviews: session.wordReviews,
      bursts: session.wordBurstHistory, below: 1000), ["ab ", "cd"])
    XCTAssertTrue(SlowWordCopyPolicy.hasInputWords(for: value, reviews: session.wordReviews))
    XCTAssertEqual(SlowWordCopyPolicy.words(for: value, reviews: session.wordReviews,
      bursts: session.wordBurstHistory, below: 1000), ["ab ", "cd"])
  }

  private func result(zen: Bool = true) -> CompletedTestResult {
    let start = Date(timeIntervalSince1970: 1000)
    return .init(id: UUID(), configuration: zen
      ? .init(mode: .zen, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init())
      : .words(10), outcome: .completed, startedAt: start,
      finishedAt: start.addingTimeInterval(3), typedCharacterCount: 10,
      correctCharacterCount: 10, errorCount: 0, wpm: 20, rawWpm: 20,
      accuracy: 100, prompt: "unused target", replayEvents: [
        .init(offset: 0, kind: .insert, text: "朝 ", inputField: .init(index: 0, value: "朝 ")),
        .init(offset: 1, kind: .insert, text: "river\n", inputField: .init(index: 1, value: "river\n")),
        .init(offset: 2, kind: .insert, text: "tail", inputField: .init(index: 2, value: "tail")),
        .init(offset: 4, kind: .insert, text: "late", inputField: .init(index: 3, value: "late")),
      ])
  }

  func testZenUsesRecordedInputFieldsIncludingCommitCharacters() {
    XCTAssertTrue(SlowWordCopyPolicy.hasInputWords(for: result(), reviews: []))
    XCTAssertEqual(SlowWordCopyPolicy.words(for: result(), reviews: [],
      bursts: [30, 80, 0, 10], below: 80), ["朝 ", "tail"])
    XCTAssertEqual(SlowWordCopyPolicy.words(for: result(), reviews: [],
      bursts: [30, 79, nil], below: 80), ["朝 ", "river\n"])
  }

  func testOrdinaryModeStillUsesTargetsAndMissingBurstsAreNotSlow() {
    XCTAssertFalse(SlowWordCopyPolicy.hasInputWords(for: result(zen: false), reviews: []))
    let reviews = [TypedWordReview(index: 0, target: "target", typed: "wrong"),
      TypedWordReview(index: 1, target: "next", typed: "next")]
    XCTAssertEqual(SlowWordCopyPolicy.words(for: result(zen: false), reviews: reviews,
      bursts: [10, nil], below: 80), ["target"])
    for threshold in [0.0, -.infinity, .infinity, .nan] {
      XCTAssertTrue(SlowWordCopyPolicy.words(for: result(), reviews: [],
        bursts: [10, 20, 30], below: threshold).isEmpty)
    }
  }
}
