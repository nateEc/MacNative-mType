import XCTest
@testable import Typebar

final class ShortExternalPreviewTests: XCTestCase {
  func testShortExternalSourceRetainsFiniteBudgetThroughContinuation() throws {
    for modifiers: [TestModifier] in [[], [.underscoreSeparators]] {
      for limit in [4, 6, 7, 8, 9, 10] {
        for showAllLines in [false, true] {
          try checkFiniteContinuation(modifiers: modifiers, limit: limit, showAllLines: showAllLines)
        }
      }
    }
  }

  private func checkFiniteContinuation(modifiers: [TestModifier], limit: Int, showAllLines: Bool) throws {
      let configuration = TestConfiguration.words(limit).with(modifiers: modifiers)
      var session = TestSessionFactory.make(configuration: configuration,
        streamPrompt: "quiet harbor morning", showAllLines: showAllLines)
      XCTAssertEqual(session.generationNotice != nil, showAllLines)
      XCTAssertEqual(session.configuration.wordLimit, limit)
      let separator = modifiers.isEmpty ? " " : "_"
      let target = (0..<limit).map { ["quiet", "harbor", "morning"][$0 % 3] }
        .joined(separator: separator)
      let start = Date(timeIntervalSinceReferenceDate: 917_000_000)
      session.insertBatch(String(target.dropLast()), at: start)
      XCTAssertFalse(session.isFinished)
      session.insertBatch(String(target.suffix(1)), at: start.addingTimeInterval(2))
      XCTAssertEqual(session.outcome, .completed, "modifiers=\(modifiers) prompt=\(session.prompt) typed=\(session.typed)")
      XCTAssertEqual(session.completedWordCount, limit)
      XCTAssertEqual(session.errors, 0)
      XCTAssertEqual(session.prompt, target)
      let result = try XCTUnwrap(session.result())
      XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: result.elapsedDuration), target)
      XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
      var repeated = session.repeatedAttempt()
      repeated.insertBatch(target, at: start)
      XCTAssertEqual(repeated.outcome, .completed)
      XCTAssertEqual(repeated.completedWordCount, limit)
      XCTAssertEqual(repeated.errors, 0)
  }
}
