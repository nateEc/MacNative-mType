import XCTest
@testable import Typebar

final class ProviderFieldSessionTests: XCTestCase {
  private let began = Date(timeIntervalSinceReferenceDate: 917_000_000)
  private let fields = ["north\nsouth ", "harbor ", "tail"]

  func testOrdinaryLineFeedCommitsWholeProviderFieldAndSkipsItsRemainder() throws {
    var session = TypingSession(configuration: .words(3), prompt: fields.joined(), sourceFields: fields)
    session.insertBatch("north\n", at: began)
    XCTAssertEqual(session.completedWordCount, 1)
    XCTAssertEqual(session.nextExpectedCharacter, "h")
    XCTAssertFalse(session.isFinished)
    session.insertBatch("harbor tai", at: began.addingTimeInterval(1))
    XCTAssertFalse(session.isFinished)
    session.insertBatch("l", at: began.addingTimeInterval(2))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 3)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(session.wordReviews.count, 3)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents,
      through: result.elapsedDuration), "north\nharbor tail")
    var repeated = session.repeatedAttempt()
    repeated.insertBatch("north\n", at: began.addingTimeInterval(5))
    XCTAssertEqual(repeated.nextExpectedCharacter, "h")
    repeated.insertBatch("harbor tail", at: began.addingTimeInterval(6))
    XCTAssertEqual(repeated.outcome, .completed)
    XCTAssertEqual(repeated.completedWordCount, 3)
  }

  func testWordAndLetterStopRetainInternalLineFeedInCurrentProviderField() throws {
    for stop in [StopOnErrorMode.word, .letter] {
      var session = TypingSession(configuration: .words(3, rules: .init(stopOnErrorMode: stop)),
        prompt: fields.joined(), sourceFields: fields)
      session.insertBatch("north\n", at: began)
      XCTAssertEqual(session.completedWordCount, 0)
      XCTAssertEqual(session.nextExpectedCharacter, "s")
      XCTAssertEqual(session.typed, "north\n")
      XCTAssertFalse(session.isFinished)
      session.insertBatch("south harbor tai", at: began.addingTimeInterval(1))
      XCTAssertFalse(session.isFinished)
      session.insertBatch("l", at: began.addingTimeInterval(2))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.completedWordCount, 3)
      XCTAssertEqual(session.errors, 0)
      XCTAssertEqual(session.wordReviews.count, 3)
      let result = try XCTUnwrap(session.result())
      XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents,
        through: result.elapsedDuration), fields.joined())
      var repeated = session.repeatedAttempt()
      repeated.insertBatch("north\n", at: began.addingTimeInterval(5))
      XCTAssertEqual(repeated.completedWordCount, 0)
      XCTAssertEqual(repeated.nextExpectedCharacter, "s")
      repeated.insertBatch("south harbor tail", at: began.addingTimeInterval(6))
      XCTAssertEqual(repeated.outcome, .completed)
      XCTAssertEqual(repeated.completedWordCount, 3)
      XCTAssertEqual(repeated.errors, 0)
    }
  }

  func testAbsentOrInvalidSourceFieldsKeepLegacyLineFeedBoundaries() {
    let metadataCases: [[String]?] = [nil, ["wrong"]]
    for metadata in metadataCases {
      var session = TypingSession(configuration: .words(3, rules: .init(stopOnErrorMode: .letter)),
        prompt: fields.joined(), sourceFields: metadata)
      session.insertBatch("north\n", at: began)
      XCTAssertEqual(session.completedWordCount, 1)
      XCTAssertEqual(session.nextExpectedCharacter, "s")
    }
  }
}
