import XCTest
@testable import Typebar

final class NoSpaceResultPromptCopyTests: XCTestCase {
  private func result(words: [String], prompt: String = "northharborriver",
    field: Int = 0, input: String = "n") -> CompletedTestResult {
    let start = Date(timeIntervalSince1970: 1000)
    return .init(id: UUID(), configuration: TestConfiguration.words(3).with(modifiers: [.noSpaces]),
      outcome: .completed, startedAt: start, finishedAt: start.addingTimeInterval(3),
      typedCharacterCount: input.count, correctCharacterCount: input.count, errorCount: 0,
      wpm: 20, rawWpm: 20, accuracy: 100, prompt: prompt,
      replayEvents: (0...field).map { index in
        .init(offset: Double(index) / 10, kind: .insert, text: index == field ? input : "north",
          inputField: .init(index: index, value: index == field ? input : "north"))
      }, targetWordDirectory: .init(words: words, noSpace: true))
  }

  func testPartialInputCopiesEntireSavedTargetNotInputLength() {
    XCTAssertEqual(ResultPromptText.make(for: result(words: ["north", "harbor", "river"]),
      reviews: []), "north")
    XCTAssertEqual(ResultPromptText.make(for: result(words: ["north", "harbor", "river"],
      field: 1, input: "h"), reviews: []), "northharbor")
  }

  func testMismatchedSavedDirectoryIsNotUsedToInventTargetBoundaries() {
    XCTAssertNil(ResultPromptText.make(for: result(words: ["wrong", "directory"]), reviews: []))
  }

  func testSavedBoundaryCanSplitAVisibleGraphemeWithoutNormalization() {
    let value = result(words: ["e", "\u{301}x"], prompt: "e\u{301}x")
    XCTAssertEqual(ResultPromptText.make(for: value, reviews: [])?.utf16.map { $0 }, [0x65])
  }

  func testEmptySavedTargetStillOccupiesItsInputFieldIdentity() {
    let value = result(words: ["", "north", "harbor", "river"], field: 1, input: "n")
    XCTAssertEqual(ResultPromptText.make(for: value, reviews: []), "north")
  }

  func testActualNoSpaceSessionCopiesFullReachedSavedWord() throws {
    let start = Date(timeIntervalSince1970: 1000)
    let configuration = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), modifiers: [.noSpaces])
    var session = TestSessionFactory.make(configuration: configuration, customText: "north harbor river")
    session.insertBatch("n", at: start)
    session.bailOut(at: start.addingTimeInterval(2))
    let value = try XCTUnwrap(session.result())
    XCTAssertEqual(value.targetWordDirectory?.words, ["north", "harbor", "river"])
    XCTAssertEqual(ResultPromptText.make(for: value, reviews: session.wordReviews), "north")
  }
}
