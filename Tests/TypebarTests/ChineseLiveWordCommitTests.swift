import XCTest
@testable import Typebar

final class ChineseLiveWordCommitTests: XCTestCase {
  private let languages: [TypingLanguage] = [.simplifiedChinese, .traditionalChinese, .jyutping]
  private let began = Date(timeIntervalSinceReferenceDate: 917_100_000)
  private let prompt = "海港有船 天气晴朗"

  func testPrematureSpaceCommitsSourceFieldAndRetainsIncorrectReplay() throws {
    for language in languages {
      let configuration = TestConfiguration.words(2, rules: .init(freedomMode: true), language: language)
        .with(modifiers: [.referenceStream])
      var session = TestSessionFactory.make(configuration: configuration,
        streamPrompt: prompt, streamsLiveContent: true, showAllLines: true)
      session.insertBatch("海 ", at: began)
      XCTAssertEqual(session.completedWordCount, 1)
      XCTAssertEqual(session.nextExpectedCharacter, "天")
      XCTAssertEqual(session.errors, 1)
      XCTAssertEqual(session.wordReviews.first, .init(index: 0, target: "海港有船", typed: "海"))
      XCTAssertFalse(session.isFinished)
      session.insertBatch("天气晴朗", at: began.addingTimeInterval(2))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.completedWordCount, 2)
      let result = try XCTUnwrap(session.result())
      XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents,
        through: result.elapsedDuration), "海 天气晴朗")
      XCTAssertEqual(session.repeatedAttempt().prompt, prompt)
    }
  }

  func testDeletingPrematureCommitReturnsToTheOriginalSourceWord() {
    for language in languages {
      let configuration = TestConfiguration.words(2, rules: .init(freedomMode: true), language: language)
        .with(modifiers: [.referenceStream])
      var session = TestSessionFactory.make(configuration: configuration,
        streamPrompt: prompt, streamsLiveContent: true, showAllLines: true)
      session.insertBatch("海 ", at: began)
      session.deleteBackward(at: began.addingTimeInterval(1))
      XCTAssertEqual(session.typed, "海")
      XCTAssertEqual(session.completedWordCount, 0)
      XCTAssertEqual(session.nextExpectedCharacter, "港")
      session.insertBatch("港有船 天气晴朗", at: began.addingTimeInterval(2))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.completedWordCount, 2)
      XCTAssertEqual(session.typed, prompt)
    }
  }

  func testExpertFailsAtIncorrectSpaceSubmissionRatherThanWaitingForFinalTarget() {
    for language in languages {
      let configuration = TestConfiguration(mode: .words, duration: nil, wordLimit: 2,
        difficulty: .expert, rules: .init(), language: language, modifiers: [.referenceStream])
      var session = TestSessionFactory.make(configuration: configuration,
        streamPrompt: prompt, streamsLiveContent: true, showAllLines: true)
      session.insertBatch("海", at: began)
      XCTAssertFalse(session.isFinished)
      session.insertBatch(" ", at: began.addingTimeInterval(1))
      XCTAssertTrue(session.isFinished)
      XCTAssertEqual(session.outcome, .failed)
    }
  }
}
