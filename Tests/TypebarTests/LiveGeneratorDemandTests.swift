import XCTest
@testable import Typebar

final class LiveGeneratorDemandTests: XCTestCase {
  private let began = Date(timeIntervalSinceReferenceDate: 917_000_000)

  private func session(limit: Int = 300, published: Int = 100) -> TypingSession {
    let fields = (0..<published).map { "owned\($0) " }
    return TypingSession(configuration: .words(limit).with(modifiers: [.poetryStream]),
      prompt: fields.joined(), sourceFields: fields, streamsLiveContent: true)
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
    XCTAssertTrue(practice.needsLiveContentGeneration)
    XCTAssertEqual(practice.completedWordCount, 3)
    XCTAssertEqual(practice.errors, 0)
    var repeated = practice.repeatedAttempt()
    XCTAssertEqual(repeated.prompt, opening)
    repeated.insertBatch("owned0 owned1 owned2 ", at: began.addingTimeInterval(3))
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
