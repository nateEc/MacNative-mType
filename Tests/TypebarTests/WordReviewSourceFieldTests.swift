import XCTest
@testable import Typebar

final class WordReviewSourceFieldTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 918_200_000)

  func testFusedCommitKeepsTheSecondReviewAndItsErrorWeight() {
    var session = TypingSession(configuration: .words(2), prompt: "a \u{301}b")
    session.insertBatch("a \u{301}x ", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.wordReviews.map(\.target), ["a", "\u{301}b"])
    XCTAssertEqual(session.wordReviews.map(\.typed), ["a", "\u{301}x"])
    let metrics = session.result()?.inputMetrics
    XCTAssertEqual(metrics.map { $0.totalAttempts - $0.correctAttempts }, 2,
      "The incorrect final commit remains a second attempted error")
    XCTAssertEqual(session.missedWordErrorCountsByWord, [0, 2])
    XCTAssertEqual(session.missedWordErrorCounts, [.init(word: "\u{301}b", count: 2)])
    let plan = ContextualMissedWordPracticePlan.make(reviews: session.wordReviews,
      errorCounts: session.missedWordErrorCountsByWord)
    XCTAssertNotNil(plan)
    XCTAssertEqual(plan?.phrases, ["a \u{301}b", "a \u{301}b"])
  }

  func testStoppedThenCorrectedErrorStillBelongsToTheSecondSourceWord() {
    var session = TypingSession(configuration: .words(2, rules: .init(stopOnErrorMode: .letter)),
      prompt: "a \u{301}b")
    session.insertBatch("a \u{301}x", at: start)
    session.insert("b", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.wordReviews.map(\.target), ["a", "\u{301}b"])
    XCTAssertEqual(session.wordReviews.map(\.typed), ["a", "\u{301}b"])
    XCTAssertEqual(session.wordReviews.map(\.hasInputError), [false, true])
    XCTAssertEqual(session.missedWordErrorCountsByWord, [0, 1])
  }

  func testProviderInternalReturnDoesNotCreateAnExtraReviewTarget() {
    let fields = ["north\nsouth ", "harbor ", "tail"]
    var session = TypingSession(configuration: .words(3), prompt: fields.joined(), sourceFields: fields)
    session.insert("x", at: start)
    session.bailOut(at: start.addingTimeInterval(2))
    XCTAssertEqual(session.wordReviews.map(\.target), ["north\nsouth"])
    XCTAssertEqual(session.wordReviews.map(\.typed), ["x"])
    XCTAssertEqual(session.missedWordErrorCountsByWord, [1, 0, 0])
    XCTAssertEqual(session.missedWords, ["north\nsouth"])
  }

  func testASCIIToUnitTransitionKeepsEarlierErrorsAndCorrectedSupplementaryAttempts() {
    var session = TypingSession(configuration: .words(3, rules: .init(freedomMode: true)), prompt: "ab cd ef")
    session.insert("xb ", at: start)
    session.insertBatch("🙂", at: start.addingTimeInterval(1))
    session.deleteWordBackward(at: start.addingTimeInterval(2))
    session.insert("cd ef", at: start.addingTimeInterval(3))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.wordReviews.map(\.target), ["ab", "cd", "ef"])
    XCTAssertEqual(session.wordReviews.map(\.typed), ["xb", "cd", "ef"])
    XCTAssertEqual(session.missedWordErrorCountsByWord, [1, 2, 0])
    XCTAssertTrue(session.wordReviews[1].hasInputError)
    XCTAssertEqual(session.preciseAccuracy, 70)
  }

  func testRepeatStartsNewFieldErrorWeights() {
    var session = TypingSession(configuration: .words(2), prompt: "a \u{301}b")
    session.insertBatch("a \u{301}x ", at: start)
    var repeated = session.repeatedAttempt()
    repeated.insertBatch("a \u{301}b", at: start.addingTimeInterval(1))
    XCTAssertEqual(repeated.outcome, .completed)
    XCTAssertEqual(repeated.missedWordErrorCountsByWord, [0, 0])
    XCTAssertTrue(repeated.wordReviews.allSatisfy(\.isCorrect))
    XCTAssertEqual(session.missedWordErrorCountsByWord, [0, 2])
  }
}
