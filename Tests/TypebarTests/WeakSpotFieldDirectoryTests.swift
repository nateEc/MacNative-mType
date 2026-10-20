import XCTest
@testable import Typebar

final class WeakSpotFieldDirectoryTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 918_000_000)

  private func completed(source: String, typed: String) throws -> CompletedTestResult {
    var session = TestSessionFactory.make(configuration: .init(mode: .custom, duration: nil,
      wordLimit: nil, difficulty: .normal, rules: .init(), modifiers: [.noSpaces]), customText: source)
    session.insertBatch(typed, at: start)
    XCTAssertEqual(session.outcome, .completed)
    let result = try XCTUnwrap(session.result())
    XCTAssertNotNil(result.targetWordDirectory)
    return result
  }

  func testNoSpaceHistoryUsesBothCapturedWordsAndSupplementaryUnitJudgments() throws {
    let result = try completed(source: "🙂a b", typed: "🙃ax")
    XCTAssertEqual(result.targetWordDirectory?.words, ["🙂a", "b"])
    XCTAssertEqual(result.errorCount, 2)
    let scores = WeakSpotPractice.characterScores(results: [result], language: .english)
    XCTAssertEqual(scores["🙂"], 1, "Only the wrong low surrogate is a mistake")
    XCTAssertEqual(scores["b"], 1, "The second captured field must not disappear")
    XCTAssertNil(scores["a"])
    let report = try XCTUnwrap(WeakSpotPractice.report(results: [result], language: .english,
      englishVariant: .american))
    XCTAssertEqual(report.totalMistakeCount, 2)
    XCTAssertTrue(report.characters.contains { $0.character == "b" && $0.mistakeCount == 1 })
  }

  func testFusedDisplayDoesNotMergeTheTargetCharactersOfSeparateFields() throws {
    let result = try completed(source: "a \u{301}b", typed: "a\u{301}x")
    XCTAssertEqual(result.prompt, "a\u{301}b")
    XCTAssertEqual(result.targetWordDirectory?.words, ["a", "\u{301}b"])
    let scores = WeakSpotPractice.characterScores(results: [result], language: .english)
    XCTAssertEqual(scores["b"], 1)
    XCTAssertEqual(scores.count, 1)
  }

  func testExplicitOrdinaryDirectoryKeepsACommitJoinedToAMarkInItsSourceField() throws {
    var session = TypingSession(configuration: .words(2), prompt: "a \u{301}b",
      sourceFields: ["a ", "\u{301}b"])
    session.insertBatch("a \u{301}x ", at: start)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.outcome, .completed)
    // Keep the portable reader fixture explicit. Actual ordinary production
    // capture is independently covered by OrdinaryTargetDirectoryTests.
    let captured = replacingDirectory(result, with: .init(words: ["a ", "\u{301}b"], noSpace: false))
    XCTAssertEqual(WeakSpotPractice.characterScores(results: [captured], language: .english), ["b": 1])
  }

  private func replacingDirectory(_ result: CompletedTestResult,
    with directory: ResultTargetWordDirectory?) -> CompletedTestResult {
    .init(id: result.id, configuration: result.configuration, outcome: result.outcome,
      startedAt: result.startedAt, finishedAt: result.finishedAt,
      typedCharacterCount: result.typedCharacterCount, correctCharacterCount: result.correctCharacterCount,
      errorCount: result.errorCount, wpm: result.wpm, rawWpm: result.rawWpm,
      accuracy: result.accuracy, prompt: result.prompt, replayEvents: result.replayEvents,
      targetWordDirectory: directory)
  }

  func testUnknownOrInvalidNoSpaceDirectoryDoesNotInventCharacterOwnership() throws {
    let result = try completed(source: "🙂a b", typed: "🙃ax")
    let invalid: [ResultTargetWordDirectory?] = [nil,
      .init(words: ["🙂a", "b"], noSpace: false),
      .init(words: ["🙂a", "c"], noSpace: true),
      .init(words: [], noSpace: true)]
    for directory in invalid {
      let incomplete = replacingDirectory(result, with: directory)
      XCTAssertTrue(WeakSpotPractice.characterScores(results: [incomplete], language: .english).isEmpty)
      XCTAssertNil(WeakSpotPractice.report(results: [incomplete], language: .english,
        englishVariant: .american))
    }
  }

  func testCompletedDirectoryAndScoresSurvivePortableRoundTrip() throws {
    let result = try completed(source: "🙂a b", typed: "🙃ax")
    let data = try JSONEncoder().encode(result)
    let restored = try JSONDecoder().decode(CompletedTestResult.self, from: data)
    XCTAssertEqual(restored.targetWordDirectory, result.targetWordDirectory)
    XCTAssertEqual(restored.replayEvents, result.replayEvents)
    XCTAssertEqual(restored.errorCount, result.errorCount)
    XCTAssertEqual(restored.wpm, result.wpm)
    XCTAssertEqual(WeakSpotPractice.report(results: [restored], language: .english,
      englishVariant: .american), WeakSpotPractice.report(results: [result], language: .english,
        englishVariant: .american))
  }

  func testEmptyCapturedSlotDoesNotShiftLaterOwnership() {
    let configuration = TestConfiguration.words(3).with(modifiers: [.noSpaces])
    let result = CompletedTestResult(id: UUID(), configuration: configuration, outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(2), typedCharacterCount: 2,
      correctCharacterCount: 1, errorCount: 1, wpm: 0, rawWpm: 0, accuracy: 50, prompt: "ab",
      replayEvents: [
        .init(offset: 0, kind: .insert, units: [97], inputField: .init(index: 0, units: [97]), inputCorrectness: [true]),
        .init(offset: 1, kind: .insert, units: [120], inputField: .init(index: 2, units: [120]), inputCorrectness: [false])
      ], targetWordDirectory: .init(words: ["a", "", "b"], noSpace: true))
    XCTAssertEqual(WeakSpotPractice.characterScores(results: [result], language: .english), ["b": 1])
  }

  func testOrdinaryUnitHistoryWithoutDirectoryRetainsItsExistingFallback() throws {
    var session = TypingSession(configuration: .words(2), prompt: "é b")
    session.insertBatch("é x ", at: start)
    let result = try XCTUnwrap(session.result())
    let withoutDirectory = replacingDirectory(result, with: nil)
    XCTAssertEqual(WeakSpotPractice.characterScores(results: [withoutDirectory], language: .english), ["b": 1])
  }
}
