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

  func testPendingContinuationRetainsProviderFieldsAndRepeatBoundaries() throws {
    let opening = ["north\nsouth ", "harbor "]
    let continuation = ["third\nfourth ", "tail"]
    var session = TypingSession(configuration: TestConfiguration.words(4).with(modifiers: [.poetryStream]),
      prompt: opening.joined(), sourceFields: opening,
      externalPromptContinuation: .init(text: continuation.joined(), sourceFields: continuation),
      streamsLiveContent: true)
    session.insertBatch("north\nharbor ", at: began)
    XCTAssertEqual(session.completedWordCount, 2)
    XCTAssertEqual(session.nextExpectedCharacter, "t")
    session.insertBatch("third\n", at: began.addingTimeInterval(1))
    XCTAssertEqual(session.completedWordCount, 3)
    XCTAssertEqual(session.nextExpectedCharacter, "t")
    session.insertBatch("tai", at: began.addingTimeInterval(2))
    XCTAssertFalse(session.isFinished)
    session.insertBatch("l", at: began.addingTimeInterval(3))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 4)
    XCTAssertEqual(session.wordReviews.count, 4)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents,
      through: result.elapsedDuration), "north\nharbor third\ntail")
    var repeated = session.repeatedAttempt()
    repeated.insertBatch("north\nharbor third\n", at: began.addingTimeInterval(5))
    XCTAssertEqual(repeated.completedWordCount, 3)
    XCTAssertEqual(repeated.nextExpectedCharacter, "t")
    repeated.insertBatch("tail", at: began.addingTimeInterval(6))
    XCTAssertEqual(repeated.outcome, .completed)
    XCTAssertEqual(repeated.completedWordCount, 4)
  }

  func testPendingLineFeedTerminatedFieldsFillBudgetWithoutExtraPrefetch() {
    let opening = ["north ", "harbor "]
    let continuation = ["third\n", "tail"]
    var session = TypingSession(configuration: TestConfiguration.words(4).with(modifiers: [.poetryStream]),
      prompt: opening.joined(), sourceFields: opening,
      externalPromptContinuation: .init(text: continuation.joined(), sourceFields: continuation),
      streamsLiveContent: true)
    XCTAssertFalse(session.needsLiveContentPrefetch)
    session.insertBatch("north harbor third\n", at: began)
    XCTAssertEqual(session.completedWordCount, 3)
    XCTAssertEqual(session.nextExpectedCharacter, "t")
    XCTAssertFalse(session.needsLiveContentPrefetch)
    session.insertBatch("tail", at: began.addingTimeInterval(2))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 4)
    XCTAssertEqual(session.errors, 0)
  }
}
