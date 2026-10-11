import XCTest
@testable import Typebar

final class LiveGeneratorDemandTests: XCTestCase {
  private let began = Date(timeIntervalSinceReferenceDate: 917_000_000)

  private func session(limit: Int = 300, published: Int = 100) -> TypingSession {
    let fields = (0..<published).map { "owned\($0) " }
    return TypingSession(configuration: .words(limit).with(modifiers: [.poetryStream]),
      prompt: fields.joined(), sourceFields: fields, streamsLiveContent: true)
  }

  func testSideSectionPublishesBeforeOneRetainedFieldAndPreservesTheRest() {
    let fields = (0..<100).map { "owned\($0) " }
    let retained = (0..<5).map { "retained\($0) " }
    var practice = TypingSession(configuration: .words(300).with(modifiers: [.poetryStream]),
      prompt: fields.joined(), sourceFields: fields,
      externalPromptContinuation: .init(text: retained.joined(), sourceFields: retained),
      streamsLiveContent: true)
    let opening = practice.prompt
    XCTAssertTrue(practice.appendLiveContent(.init(text: "fresh later", noSpaceBoundarySource: nil)))
    XCTAssertEqual(practice.prompt, opening + "fresh later retained0 ",
      "The pinned caller publishes the new section before consuming one old generator field")
    practice.insertBatch("owned0 owned1 ", at: began)
    XCTAssertEqual(practice.prompt, opening + "fresh later retained0 ",
      "The caller does not consume the cache while the future window exceeds one hundred")
    practice.insertBatch("owned2 ", at: began.addingTimeInterval(1))
    XCTAssertEqual(practice.prompt, opening + "fresh later retained0 retained1 ",
      "Only one additional retained field is consumed when forward progress reaches the window bound")
    XCTAssertEqual(practice.completedWordCount, 3)
    XCTAssertEqual(practice.errors, 0)
    XCTAssertFalse(practice.needsLiveContentGeneration)
  }

  func testSideSectionIsNotRejectedBecauseUnpublishedCacheFillsFiniteBudget() {
    let fields = (0..<100).map { "owned\($0) " }
    let retained = (0..<5).map { "retained\($0) " }
    var practice = TypingSession(configuration: .words(105).with(modifiers: [.poetryStream]),
      prompt: fields.joined(), sourceFields: fields,
      externalPromptContinuation: .init(text: retained.joined(), sourceFields: retained),
      streamsLiveContent: true)
    XCTAssertTrue(practice.appendLiveContent(.init(text: "fresh later", noSpaceBoundarySource: nil)),
      "Cached ownership does not mean the finite published budget is exhausted")
    XCTAssertEqual(practice.prompt, fields.joined() + "fresh later retained0 ")
    XCTAssertFalse(practice.isFinished)
  }

  func testSideSectionBypassesBackwardsWhileTheGeneratorTailIsAlreadyAltered() {
    let fields = (0..<100).map { "owned\($0) " }
    var practice = TypingSession(configuration: .words(300).with(modifiers: [.poetryStream, .backwards]),
      prompt: fields.joined(), sourceFields: fields,
      externalPromptContinuation: .init(text: "0deniater 1deniater ",
        sourceFields: ["0deniater ", "1deniater "]), streamsLiveContent: true)
    XCTAssertTrue(practice.appendLiveContent(.init(text: "fresh later", noSpaceBoundarySource: nil)))
    XCTAssertEqual(practice.prompt, fields.joined() + "fresh later 0deniater ",
      "Side publication bypasses alterText, but getNextWord returns its altered generator field")
  }

  func testRepeatRetainsOnlyConsumedGeneratorFieldsNotTheUnusedProviderCache() {
    let fields = (0..<100).map { "owned\($0) " }
    let retained = (0..<5).map { "retained\($0) " }
    var practice = TypingSession(configuration: .words(300).with(modifiers: [.poetryStream]),
      prompt: fields.joined(), sourceFields: fields,
      externalPromptContinuation: .init(text: retained.joined(), sourceFields: retained),
      streamsLiveContent: true)
    practice.insertBatch("owned0 owned1 ", at: began)
    var repeated = practice.repeatedAttempt()
    repeated.insertBatch("owned0 owned1 owned2 ", at: began.addingTimeInterval(1))
    XCTAssertEqual(repeated.prompt, fields.joined() + "retained0 retained1 ")
    XCTAssertTrue(repeated.needsLiveContentGeneration,
      "Missing repeat history must request a new section, not consume the original unused cache")
  }

  func testRepeatExcludesSidePublicationAndUnconsumedGeneratorTail() {
    let fields = (0..<100).map { "owned\($0) " }
    let retained = (0..<5).map { "retained\($0) " }
    var practice = TypingSession(configuration: .words(300).with(modifiers: [.poetryStream]),
      prompt: fields.joined(), sourceFields: fields,
      externalPromptContinuation: .init(text: retained.joined(), sourceFields: retained),
      streamsLiveContent: true)
    XCTAssertTrue(practice.appendLiveContent(.init(text: "fresh later", noSpaceBoundarySource: nil)))
    var repeated = practice.repeatedAttempt()
    repeated.insertBatch("owned0 owned1 ", at: began)
    XCTAssertEqual(repeated.prompt, fields.joined() + "retained0 ")
    XCTAssertTrue(repeated.needsLiveContentGeneration)
    XCTAssertFalse(repeated.prompt.contains("fresh"))
  }

  func testRepeatingAPartialRepeatPreservesPreviouslyGeneratedHistoryInBothFieldModes() {
    for underscore in [false, true] {
      let opening = (0..<100).map { "owned\($0)" }
      let commit = underscore ? "_" : " "
      let modifiers: [TestModifier] = underscore ? [.poetryStream, .underscoreSeparators] : [.poetryStream]
      var practice = TestSessionFactory.make(configuration: TestConfiguration.words(300).with(modifiers: modifiers),
        streamPrompt: opening.joined(separator: " "),
        streamContinuation: .init(text: "retained0 retained1 unused", noSpaceBoundarySource: nil),
        streamsLiveContent: true)
      practice.insertBatch("owned0" + commit + "owned1" + commit, at: began)
      var partialRepeat = practice.repeatedAttempt()
      partialRepeat.insertBatch("owned0" + commit, at: began.addingTimeInterval(1))
      var nextRepeat = partialRepeat.repeatedAttempt()
      nextRepeat.insertBatch("owned0" + commit + "owned1" + commit, at: began.addingTimeInterval(2))
      XCTAssertEqual(nextRepeat.prompt, opening.map { $0 + commit }.joined()
        + "retained0" + commit + "retained1" + commit)
      XCTAssertFalse(nextRepeat.needsLiveContentGeneration,
        "A partial repeat must not erase history retained by the first attempt")
      nextRepeat.insertBatch("owned2" + commit, at: began.addingTimeInterval(3))
      XCTAssertTrue(nextRepeat.needsLiveContentGeneration)
      XCTAssertFalse(nextRepeat.prompt.contains("unused"))
    }
  }

  func testFiniteSideOversupplyFinishesAtPublishedLastFieldNotConfiguredCount() {
    let opening = (0..<100).map { "owned\($0) " }
    let retained = (0..<5).map { "retained\($0) " }
    let side = (0..<10).map { "side\($0)" }
    var practice = TypingSession(configuration: .words(105).with(modifiers: [.poetryStream]),
      prompt: opening.joined(), sourceFields: opening,
      externalPromptContinuation: .init(text: retained.joined(), sourceFields: retained),
      streamsLiveContent: true)
    XCTAssertTrue(practice.appendLiveContent(.init(text: side.joined(separator: " "), noSpaceBoundarySource: nil)))
    let published = practice.prompt
    practice.insertBatch(opening.joined() + side.prefix(5).joined(separator: " "), at: began)
    XCTAssertFalse(practice.isFinished, "The configured count does not truncate a published side section")
    practice.insertBatch(" " + side.dropFirst(5).joined(separator: " ") + " retained0",
      at: began.addingTimeInterval(1))
    XCTAssertEqual(practice.outcome, .completed)
    XCTAssertEqual(practice.completedWordCount, 111)
    XCTAssertEqual(practice.prompt, published, "No more cached fields publish after generation is complete")
    XCTAssertEqual(practice.errors, 0)
  }

  func testNonfinalCachedSectionLastFieldKeepsItsCommitInGeneratorReplay() {
    let opening = (0..<100).map { "owned\($0) " }
    var practice = TypingSession(configuration: .words(110).with(modifiers: [.poetryStream]),
      prompt: opening.joined(), sourceFields: opening,
      externalPromptContinuation: .init(text: "first last", sourceFields: ["first ", "last"]),
      streamsLiveContent: true)
    practice.insertBatch("owned0 owned1 ", at: began)
    XCTAssertEqual(practice.prompt, opening.joined() + "first last ")
    var repeated = practice.repeatedAttempt()
    repeated.insertBatch("owned0 owned1 ", at: began.addingTimeInterval(1))
    XCTAssertEqual(repeated.prompt, opening.joined() + "first last ")
  }

  func testSidePublicationBypassesBritishWordConversion() {
    let configuration = TestConfiguration(mode: .words, duration: nil, wordLimit: 300,
      difficulty: .normal, rules: .init(), englishVariant: .british, modifiers: [.poetryStream])
    let fields = (0..<100).map { "owned\($0) " }
    var practice = TypingSession(configuration: configuration, prompt: fields.joined(),
      sourceFields: fields, streamsLiveContent: true)
    XCTAssertTrue(practice.appendLiveContent(.init(text: "color honor", noSpaceBoundarySource: nil)))
    XCTAssertEqual(practice.prompt, fields.joined() + "color honor")
  }

  func testFinalCachedLineFeedCommitIsRemovedOnlyFromNonemptyField() {
    for terminal in ["last\n", "\n"] {
      let opening = (0..<100).map { "owned\($0) " }
      var practice = TypingSession(configuration: .words(101).with(modifiers: [.poetryStream]),
        prompt: opening.joined(), sourceFields: opening,
        externalPromptContinuation: .init(text: terminal, sourceFields: [terminal]),
        streamsLiveContent: true)
      practice.insertBatch("owned0 ", at: began)
      XCTAssertEqual(practice.prompt, opening.joined() + (terminal == "\n" ? "\n" : "last"))
    }
  }

  func testForwardProgressRequestsGeneratorSectionWithAFullVisibleWindow() {
    for count in [100, 101, 102] {
      var practice = session(published: count)
      XCTAssertFalse(practice.needsLiveContentGeneration)
      practice.insertBatch("owned0 ", at: began)
      XCTAssertEqual(practice.needsLiveContentGeneration, count <= 101)
      XCTAssertFalse(practice.needsLiveContentPrefetch,
        "Generator demand is separate from the twenty-word side pull")
    }
  }

  func testConsumingLastRetainedFieldWaitsUntilTheNextForwardActionToRequest() {
    let fields = (0..<100).map { "owned\($0) " }
    var practice = TypingSession(configuration: .words(300).with(modifiers: [.poetryStream]),
      prompt: fields.joined(), sourceFields: fields,
      externalPromptContinuation: .init(text: "retained ", sourceFields: ["retained "]),
      streamsLiveContent: true)
    practice.insertBatch("owned0 ", at: began)
    XCTAssertFalse(practice.needsLiveContentGeneration)
    practice.insertBatch("owned1 ", at: began.addingTimeInterval(1))
    XCTAssertTrue(practice.needsLiveContentGeneration)
  }

  func testGeneratedSectionPublishesOneFieldAndRetainsItsTailForLaterProgress() throws {
    var practice = session()
    let opening = practice.prompt
    practice.insertBatch("owned0 ", at: began)
    XCTAssertTrue(practice.acceptGeneratedLiveContent(.init(
      text: "north\nsouth e\u{301} tail", noSpaceBoundarySource: nil)))
    XCTAssertEqual(practice.prompt, opening + "north\nsouth ")
    XCTAssertFalse(practice.needsLiveContentGeneration)
    practice.insertBatch("owned1 ", at: began.addingTimeInterval(1))
    XCTAssertEqual(practice.prompt, opening + "north\nsouth e\u{301} ")
    practice.insertBatch("owned2 ", at: began.addingTimeInterval(2))
    XCTAssertEqual(practice.prompt, opening + "north\nsouth e\u{301} tail ")
    XCTAssertFalse(practice.needsLiveContentGeneration)
    XCTAssertEqual(practice.completedWordCount, 3)
    XCTAssertEqual(practice.errors, 0)
    practice.insertBatch("owned3 ", at: began.addingTimeInterval(3))
    XCTAssertTrue(practice.needsLiveContentGeneration)
    var repeated = practice.repeatedAttempt()
    XCTAssertEqual(repeated.prompt, opening)
    repeated.insertBatch("owned0 owned1 owned2 owned3 ", at: began.addingTimeInterval(4))
    XCTAssertEqual(repeated.prompt, practice.prompt)
  }

  func testGeneratedSectionClipsFiniteBudgetAndCompletesOnlyAtTheLastField() {
    var practice = session(limit: 102)
    practice.insertBatch("owned0 ", at: began)
    XCTAssertTrue(practice.acceptGeneratedLiveContent(.init(
      text: "fresh tail discarded", noSpaceBoundarySource: nil)))
    XCTAssertTrue(practice.prompt.hasSuffix("fresh "))
    practice.insertBatch("owned1 ", at: began.addingTimeInterval(1))
    XCTAssertTrue(practice.prompt.hasSuffix("fresh tail"))
    XCTAssertFalse(practice.needsLiveContentGeneration)
    practice.insertBatch((2..<100).map { "owned\($0) " }.joined() + "fresh tai",
      at: began.addingTimeInterval(2))
    XCTAssertFalse(practice.isFinished)
    practice.insertBatch("l", at: began.addingTimeInterval(3))
    XCTAssertEqual(practice.outcome, .completed)
    XCTAssertEqual(practice.completedWordCount, 102)
    XCTAssertEqual(practice.errors, 0)
    XCTAssertFalse(practice.prompt.contains("discarded"))
  }

  func testEmptyOrMismatchedSectionsDoNotConsumeGenerationDemand() {
    var practice = session()
    practice.insertBatch("owned0 ", at: began)
    let prompt = practice.prompt
    XCTAssertFalse(practice.acceptGeneratedLiveContent(.init(text: "", noSpaceBoundarySource: nil)))
    XCTAssertFalse(practice.acceptGeneratedLiveContent(.init(
      text: "fresh", noSpaceBoundarySource: "other words")))
    XCTAssertEqual(practice.prompt, prompt)
    XCTAssertTrue(practice.needsLiveContentGeneration)
  }

  func testPartialFirstInputDoesNotCreateAForwardGenerationDemand() {
    var practice = session()
    practice.insertBatch("o", at: began)
    let prompt = practice.prompt
    XCTAssertTrue(practice.hasStarted)
    XCTAssertEqual(practice.completedWordCount, 0)
    XCTAssertFalse(practice.needsLiveContentGeneration)
    XCTAssertFalse(practice.acceptGeneratedLiveContent(.init(text: "fresh tail", noSpaceBoundarySource: nil)))
    XCTAssertEqual(practice.prompt, prompt)
  }

  func testUnderscoreGenerationKeepsFieldSuffixesAndFiniteCompletion() {
    let opening = (0..<100).map { "owned\($0)" }
    var practice = TestSessionFactory.make(configuration: TestConfiguration.words(102)
      .with(modifiers: [.poetryStream, .underscoreSeparators]),
      streamPrompt: opening.joined(separator: " "), streamsLiveContent: true)
    let original = practice.prompt
    practice.insertBatch("owned0_", at: began)
    XCTAssertTrue(practice.needsLiveContentGeneration)
    XCTAssertTrue(practice.acceptGeneratedLiveContent(.init(text: "fresh tail", noSpaceBoundarySource: nil)))
    XCTAssertEqual(practice.prompt, original + "fresh_")
    XCTAssertFalse(practice.acceptGeneratedLiveContent(.init(text: "must not replace", noSpaceBoundarySource: nil)))
    practice.insertBatch("owned1_", at: began.addingTimeInterval(1))
    XCTAssertEqual(practice.prompt, original + "fresh_tail")
    practice.insertBatch(opening.dropFirst(2).map { $0 + "_" }.joined() + "fresh_tai",
      at: began.addingTimeInterval(2))
    XCTAssertFalse(practice.isFinished)
    practice.insertBatch("l", at: began.addingTimeInterval(3))
    XCTAssertEqual(practice.outcome, .completed)
    XCTAssertEqual(practice.completedWordCount, 102)
    XCTAssertEqual(practice.errors, 0)
    XCTAssertFalse(practice.needsLiveContentGeneration)
  }
}
