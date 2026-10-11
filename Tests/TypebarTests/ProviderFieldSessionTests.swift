import XCTest
@testable import Typebar

final class ProviderFieldSessionTests: XCTestCase {
  private let began = Date(timeIntervalSinceReferenceDate: 917_000_000)
  private let fields = ["north\nsouth ", "harbor ", "tail"]

  func testEmptyInitialGenerationIsTerminalWithoutAnAttemptResult() {
    let configuration = TestConfiguration.words(4).with(modifiers: [.poetryStream])
    var session = TypingSession(configuration: configuration, prompt: "",
      initializationFailure: "在线内容为空，连续三次无法生成练习。")
    XCTAssertEqual(session.outcome, .failed)
    XCTAssertNotNil(session.generationNotice)
    XCTAssertNil(session.result())
    session.insertBatch("ignored", at: began)
    XCTAssertEqual(session.typed, "")
    XCTAssertEqual(session.configuration, configuration)
    XCTAssertEqual(session.repeatedAttempt().outcome, .failed)
  }

  func testEmptyLiveGenerationFailureRetainsAcceptedTargetsAndReplay() throws {
    let configuration = TestConfiguration.words(4).with(modifiers: [.poetryStream, .noQuit])
    var session = TypingSession(configuration: configuration, prompt: "north harbor ",
      sourceFields: ["north ", "harbor "], streamsLiveContent: true)
    session.insertBatch("north harbor ", at: began)
    XCTAssertTrue(session.isWaitingForLiveContent)
    let originalPrompt = session.prompt
    let originalTyped = session.typed
    session.failLiveContentGeneration(at: began.addingTimeInterval(2))
    XCTAssertEqual(session.outcome, .failed)
    XCTAssertEqual(session.failureReason, .wordGeneration)
    XCTAssertEqual(session.configuration, configuration)
    XCTAssertEqual(session.prompt, originalPrompt)
    XCTAssertEqual(session.typed, originalTyped)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents,
      through: result.elapsedDuration), originalTyped)
    session.insertBatch("ignored", at: began.addingTimeInterval(3))
    XCTAssertEqual(session.typed, originalTyped)
  }

  func testInvalidOpeningMetadataDoesNotChangeLaterSectionTransformation() {
    let configuration = TestConfiguration.words(4).with(modifiers: [.poetryStream])
    var legacy = TypingSession(configuration: configuration, prompt: "north harbor ", streamsLiveContent: true)
    var invalid = TypingSession(configuration: configuration, prompt: "north harbor ",
      sourceFields: ["wrong"], streamsLiveContent: true)
    let next = LivePracticePrompt(text: "third\n tail", noSpaceBoundarySource: nil)
    XCTAssertTrue(legacy.appendLiveContent(next))
    XCTAssertTrue(invalid.appendLiveContent(next))
    XCTAssertEqual(invalid.prompt, legacy.prompt)
  }

  func testNewLiveSectionRetainsFieldsAndRepeatHistory() throws {
    for opening in [["north\nsouth ", "harbor "], ["north\nsouth ", "harbor"]] {
      var session = TypingSession(configuration: TestConfiguration.words(4).with(modifiers: [.poetryStream]),
        prompt: opening.joined(), sourceFields: opening, streamsLiveContent: true)
      session.insertBatch("north\n", at: began)
      XCTAssertTrue(session.appendLiveContent(.init(text: "third\nfourth tail ignored", noSpaceBoundarySource: nil)))
      XCTAssertFalse(session.prompt.contains("ignored"))
      XCTAssertEqual(session.nextExpectedCharacter, "h")
      XCTAssertFalse(session.needsLiveContentPrefetch)
      session.insertBatch("harbor third\ntai", at: began.addingTimeInterval(1))
      XCTAssertFalse(session.isFinished)
      session.insertBatch("l", at: began.addingTimeInterval(2))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.completedWordCount, 4)
      let result = try XCTUnwrap(session.result())
      XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents,
        through: result.elapsedDuration), "north\nharbor third\ntail")
      var repeated = session.repeatedAttempt()
      repeated.insertBatch("north\nharbor third\ntail", at: began.addingTimeInterval(5))
      XCTAssertEqual(repeated.outcome, .completed)
      XCTAssertEqual(repeated.completedWordCount, 4)
    }
  }

  func testMultipleNewSectionsRetainAccumulatedRepeatHistory() {
    let opening = ["north\nsouth ", "harbor"]
    var session = TypingSession(configuration: TestConfiguration.words(6).with(modifiers: [.poetryStream]),
      prompt: opening.joined(), sourceFields: opening, streamsLiveContent: true)
    session.insertBatch("north\n", at: began)
    XCTAssertTrue(session.appendLiveContent(.init(text: "third\nfourth anchor", noSpaceBoundarySource: nil)))
    XCTAssertTrue(session.appendLiveContent(.init(text: "fifth\nsixth tail", noSpaceBoundarySource: nil)))
    XCTAssertFalse(session.needsLiveContentPrefetch)
    session.insertBatch("harbor third\nanchor fifth\ntail", at: began.addingTimeInterval(2))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 6)
    var repeated = session.repeatedAttempt()
    repeated.insertBatch("north\nharbor third\nanchor fifth\ntail", at: began.addingTimeInterval(5))
    XCTAssertEqual(repeated.outcome, .completed)
    XCTAssertEqual(repeated.completedWordCount, 6)
  }

  func testNewSectionRetainsTransformedUppercaseFields() {
    let opening = ["NORTH\nSOUTH ", "HARBOR "]
    var session = TypingSession(configuration: TestConfiguration.words(4).with(modifiers: [.poetryStream, .uppercase]),
      prompt: opening.joined(), sourceFields: opening, streamsLiveContent: true)
    session.insertBatch("NORTH\n", at: began)
    XCTAssertTrue(session.appendLiveContent(.init(text: "third\nfourth tail", noSpaceBoundarySource: nil)))
    XCTAssertTrue(session.prompt.hasSuffix("THIRD\nFOURTH TAIL"))
    session.insertBatch("HARBOR THIRD\nTAIL", at: began.addingTimeInterval(2))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 4)
  }

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
