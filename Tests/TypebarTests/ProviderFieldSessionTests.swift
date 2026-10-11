import XCTest
@testable import Typebar

final class ProviderFieldSessionTests: XCTestCase {
  private let began = Date(timeIntervalSinceReferenceDate: 917_000_000)
  private let fields = ["north\nsouth ", "harbor ", "tail"]

  func testTakingFirstFieldRetainsLiteralBoundariesWithoutResampling() throws {
    let cases: [(TransformedPromptBatch, [String])] = [
      (.init(text: "north\nsouth e\u{301} 🙂", sourceFields: ["north\nsouth ", "e\u{301} ", "🙂"]),
        ["north\nsouth ", "e\u{301} ", "🙂"]),
      (.init(text: "🇺🇸e\u{301}", noSpaceTargetWords: ["🇺", "🇸", "e\u{301}"],
        sourceFields: ["🇺", "🇸", "e\u{301}"]), ["🇺", "🇸", "e\u{301}"]),
      (.init(text: "north\nsouth e\u{301} 🙂"), ["north\nsouth ", "e\u{301} ", "🙂"]),
    ]
    for (batch, expected) in cases {
      var pending: TransformedPromptBatch? = batch
      var output = ""
      for field in expected {
        let next = try XCTUnwrap(pending?.takingFirstField())
        XCTAssertTrue(next.first.text.utf16.elementsEqual(field.utf16))
        if batch.sourceFields != nil { XCTAssertEqual(next.first.sourceFields, [field]) }
        if !batch.noSpaceTargetWords.isEmpty { XCTAssertEqual(next.first.noSpaceTargetWords, [field]) }
        output += next.first.text
        pending = next.remaining
      }
      XCTAssertNil(pending)
      XCTAssertTrue(output.utf16.elementsEqual(batch.text.utf16))
    }
    XCTAssertNil(TransformedPromptBatch(text: "").takingFirstField())
  }

  func testLiveUnderscoreGeneratorTailKeepsNoSpaceFieldsAndFiniteLastSuffix() {
    let opening = (0..<100).map { "owned\($0)" }
    let tail = ["next", "e\u{301}", "tail"]
    var session = TestSessionFactory.make(configuration: TestConfiguration.words(103)
      .with(modifiers: [.poetryStream, .underscoreSeparators]),
      streamPrompt: opening.joined(separator: " "),
      streamContinuation: .init(text: tail.joined(separator: " "), noSpaceBoundarySource: nil),
      streamsLiveContent: true)
    let original = opening.map { $0 + "_" }.joined()
    XCTAssertEqual(session.prompt, original)
    let renderedTail = ["next_", "e\u{301}_", "tail"]
    for i in 0..<3 {
      session.insertBatch(opening[i] + "_", at: began.addingTimeInterval(Double(i)))
      XCTAssertEqual(session.prompt, original + renderedTail.prefix(i + 1).joined())
      XCTAssertEqual(session.completedWordCount, i + 1)
    }
    session.insertBatch(opening.dropFirst(3).map { $0 + "_" }.joined() + renderedTail.joined(),
      at: began.addingTimeInterval(4))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 103)
    XCTAssertEqual(session.errors, 0)
    XCTAssertFalse(session.prompt.hasSuffix("_"))
  }

  func testNonLiveExternalContinuationKeepsItsExistingBatchBoundary() {
    var session = TypingSession(configuration: .words(4), prompt: "north harbor ",
      sourceFields: ["north ", "harbor "],
      externalPromptContinuation: .init(text: "third tail", sourceFields: ["third ", "tail"]))
    session.insertBatch("north ", at: began)
    XCTAssertEqual(session.prompt, "north harbor ")
    session.insertBatch("harbor ", at: began.addingTimeInterval(1))
    XCTAssertEqual(session.prompt, "north harbor third tail")
    session.insertBatch("third tail", at: began.addingTimeInterval(2))
    XCTAssertEqual(session.outcome, .completed)
  }

  func testNewSectionAfterPartialTailConsumptionDoesNotDuplicateFieldsOrRepeatHistory() {
    for underscore in [false, true] {
      let modifiers: [TestModifier] = underscore ? [.poetryStream, .underscoreSeparators] : [.poetryStream]
      let opening = (0..<100).map { "owned\($0)" }
      let tail = ["next", "e\u{301}", "tail"]
      var session = TestSessionFactory.make(configuration: TestConfiguration.words(105).with(modifiers: modifiers),
        streamPrompt: opening.joined(separator: " "),
        streamContinuation: .init(text: tail.joined(separator: " "), noSpaceBoundarySource: nil),
        streamsLiveContent: true)
      let commit = underscore ? "_" : " "
      let first = opening[0] + commit
      session.insertBatch(first, at: began)
      XCTAssertTrue(session.prompt.hasSuffix(tail[0] + commit))
      XCTAssertTrue(session.appendLiveContent(.init(text: "anchor last ignored", noSpaceBoundarySource: nil)))
      let generatedPrefix = (opening + [tail[0]]).map { $0 + commit }.joined()
      let sideText = ["anchor", "last", "ignored"].joined(separator: underscore ? "" : " ")
      let expected = generatedPrefix + sideText + (underscore ? "" : " ") + tail[1] + (underscore ? "_" : "")
      XCTAssertEqual(session.prompt, expected,
        "A side section publishes raw fields before consuming one old generator field")
      XCTAssertTrue(session.prompt.contains("ignored"))
      XCTAssertFalse(session.prompt.hasSuffix(tail[2]), "The remaining cache does not drain after the finite published budget is reached")
      session.insertBatch(String(expected.dropFirst(first.count)), at: began.addingTimeInterval(1))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.completedWordCount, 105)
      XCTAssertEqual(session.errors, 0)
      var repeated = session.repeatedAttempt()
      repeated.insertBatch(opening.prefix(3).map { $0 + commit }.joined(), at: began.addingTimeInterval(2))
      XCTAssertTrue(repeated.needsLiveContentGeneration)
      XCTAssertEqual(repeated.prompt, (opening + Array(tail.prefix(2))).map { $0 + commit }.joined())
      XCTAssertTrue(repeated.acceptGeneratedLiveContent(.init(text: "anchor last ignored", noSpaceBoundarySource: nil)))
      let repeatedWords = opening + Array(tail.prefix(2)) + ["anchor", "last", "ignored"]
      let repeatExpected = repeatedWords.dropLast().map { $0 + commit }.joined() + repeatedWords.last!
      let repeatPrefix = opening.prefix(3).map { $0 + commit }.joined()
      repeated.insertBatch(String(repeatExpected.dropFirst(repeatPrefix.count)), at: began.addingTimeInterval(3))
      XCTAssertEqual(repeated.outcome, .completed)
      XCTAssertEqual(repeated.completedWordCount, 105)
      XCTAssertEqual(repeated.errors, 0)
    }
  }

  func testLiveGeneratorTailPublishesOneFieldPerForwardCommitAndRepeatsExactly() throws {
    let opening = (0..<100).map { "owned\($0) " }
    let tail = ["north\nsouth ", "e\u{301} ", "tail"]
    var session = TypingSession(configuration: TestConfiguration.words(103).with(modifiers: [.poetryStream]),
      prompt: opening.joined(), sourceFields: opening,
      externalPromptContinuation: .init(text: tail.joined(), sourceFields: tail), streamsLiveContent: true)
    let original = session.prompt
    for i in 0..<3 {
      session.insertBatch(opening[i], at: began.addingTimeInterval(Double(i)))
      XCTAssertEqual(session.prompt, original + tail.prefix(i + 1).joined(),
        "A forward commit publishes one retained source field, not none or the whole tail")
      XCTAssertEqual(session.completedWordCount, i + 1)
    }
    let remainingInput = opening.dropFirst(3).joined() + "north\ne\u{301} tail"
    session.insertBatch(remainingInput, at: began.addingTimeInterval(4))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 103)
    XCTAssertEqual(session.wordReviews.count, 103)
    XCTAssertEqual(session.errors, 0)
    let result = try XCTUnwrap(session.result())
    let accepted = opening.joined() + "north\ne\u{301} tail"
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: result.elapsedDuration), accepted)
    var repeated = session.repeatedAttempt()
    repeated.insertBatch(opening[0], at: began.addingTimeInterval(5))
    XCTAssertEqual(repeated.prompt, original + tail[0])
    repeated.insertBatch(opening.dropFirst().joined() + "north\ne\u{301} tail", at: began.addingTimeInterval(6))
    XCTAssertEqual(repeated.outcome, .completed)
    XCTAssertEqual(repeated.errors, 0)
  }

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

  func testNewLiveSectionRetainsRawFieldsButRepeatRequiresNewGeneration() throws {
    for opening in [["north\nsouth ", "harbor "], ["north\nsouth ", "harbor"]] {
      var session = TypingSession(configuration: TestConfiguration.words(4).with(modifiers: [.poetryStream]),
        prompt: opening.joined(), sourceFields: opening, streamsLiveContent: true)
      session.insertBatch("north\n", at: began)
      XCTAssertTrue(session.appendLiveContent(.init(text: "third\nfourth tail ignored", noSpaceBoundarySource: nil)))
      XCTAssertTrue(session.prompt.contains("ignored"), "A side section is not clipped to the remaining global budget")
      XCTAssertEqual(session.nextExpectedCharacter, "h")
      XCTAssertFalse(session.needsLiveContentPrefetch)
      session.insertBatch("harbor third\ntail ignore", at: began.addingTimeInterval(1))
      XCTAssertFalse(session.isFinished)
      session.insertBatch("d", at: began.addingTimeInterval(2))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.completedWordCount, 5)
      let result = try XCTUnwrap(session.result())
      XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents,
        through: result.elapsedDuration), "north\nharbor third\ntail ignored")
      var repeated = session.repeatedAttempt()
      repeated.insertBatch("north\nharbor ", at: began.addingTimeInterval(5))
      XCTAssertEqual(repeated.outcome, .active)
      XCTAssertTrue(repeated.needsLiveContentGeneration)
      XCTAssertFalse(repeated.prompt.contains("ignored"), "Direct side publication bypasses saved generator returns")
      XCTAssertTrue(repeated.acceptGeneratedLiveContent(.init(text: "third\nfourth tail", noSpaceBoundarySource: nil)))
      // The manually authored opening can omit its final commit. Blind input
      // was rejected while waiting; explicitly submit it after content arrives.
      if !repeated.typed.hasSuffix(" ") { repeated.insertBatch(" ", at: began.addingTimeInterval(6)) }
      repeated.insertBatch("third\ntail", at: began.addingTimeInterval(6))
      XCTAssertEqual(repeated.outcome, .completed)
      XCTAssertEqual(repeated.completedWordCount, 4)
    }
  }

  func testMultipleSideSectionsDoNotAccumulateGeneratorRepeatHistory() {
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
    repeated.insertBatch("north\nharbor ", at: began.addingTimeInterval(5))
    XCTAssertTrue(repeated.needsLiveContentGeneration)
    XCTAssertEqual(repeated.completedWordCount, 2)
    XCTAssertFalse(repeated.prompt.contains("third"))
    XCTAssertTrue(repeated.acceptGeneratedLiveContent(.init(text: "third\nfourth anchor fifth\nsixth tail", noSpaceBoundarySource: nil)))
    if !repeated.typed.hasSuffix(" ") { repeated.insertBatch(" ", at: began.addingTimeInterval(6)) }
    repeated.insertBatch("third\nanchor fifth\ntail", at: began.addingTimeInterval(6))
    XCTAssertEqual(repeated.outcome, .completed)
    XCTAssertEqual(repeated.completedWordCount, 6)
  }

  func testSideSectionBypassesUppercaseButRetainsItsSourceFields() {
    let opening = ["NORTH\nSOUTH ", "HARBOR "]
    var session = TypingSession(configuration: TestConfiguration.words(4).with(modifiers: [.poetryStream, .uppercase]),
      prompt: opening.joined(), sourceFields: opening, streamsLiveContent: true)
    session.insertBatch("NORTH\n", at: began)
    XCTAssertTrue(session.appendLiveContent(.init(text: "third\nfourth tail", noSpaceBoundarySource: nil)))
    XCTAssertTrue(session.prompt.hasSuffix("third\nfourth tail"))
    session.insertBatch("HARBOR third\ntail", at: began.addingTimeInterval(2))
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

  func testUnpublishedLineFeedFieldsDoNotSuppressSidePrefetch() {
    let opening = ["north ", "harbor "]
    let continuation = ["third\n", "tail"]
    var session = TypingSession(configuration: TestConfiguration.words(4).with(modifiers: [.poetryStream]),
      prompt: opening.joined(), sourceFields: opening,
      externalPromptContinuation: .init(text: continuation.joined(), sourceFields: continuation),
      streamsLiveContent: true)
    XCTAssertTrue(session.needsLiveContentPrefetch, "The pinned side caller counts published fields, not cached ownership")
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
