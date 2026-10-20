import XCTest
@testable import Typebar

final class WeakSpotDrillWordCountTests: XCTestCase {
  private func result(language: TypingLanguage, prompt: String, mistaken: Character) -> CompletedTestResult {
    let typed = String(prompt.map { $0 == mistaken ? Character("x") : $0 })
    let errors = prompt.filter { $0 == mistaken }.count
    return .init(id: UUID(), configuration: .words(prompt.split(separator: " ").count, language: language),
      outcome: .completed, startedAt: Date(timeIntervalSince1970: 1), finishedAt: Date(timeIntervalSince1970: 10),
      typedCharacterCount: prompt.count, correctCharacterCount: prompt.count - errors, errorCount: errors,
      wpm: 0, rawWpm: 20, accuracy: 0, prompt: prompt,
      replayEvents: [.init(offset: 1, kind: .insert, text: typed)])
  }

  func testHistoryDrillButtonsProduceTheirActualRequestedWordCountWithPhraseSuggestions() throws {
    let cases: [(TypingLanguage, String, Character)] = [(.french, "tout à fait", "à"), (.german, "zu Hause", "H")]
    for (language, phrase, mistaken) in cases {
      let results = [result(language: language, prompt: phrase, mistaken: mistaken)]
      let report = try XCTUnwrap(WeakSpotPractice.report(results: results, language: language,
        englishVariant: .american))
      XCTAssertTrue(report.suggestedWords.contains { $0.contains(" ") },
        "Fixture must exercise a real phrase among the ranked suggestions")
      let fields = report.suggestedWords.flatMap { $0.split(separator: " ").map(String.init) }
      for count in [-1, 0, 1, 2, 10, 25, 50] {
        let prompt = try XCTUnwrap(WeakSpotPractice.prompt(results: results, language: language,
          englishVariant: .american, wordCount: count))
        let expected = (0..<max(1, count)).map { fields[$0 % fields.count] }
        XCTAssertEqual(prompt.split(separator: " ").map(String.init), expected,
          "\(language), request \(count): preserve ranked section order and truncate at the actual word limit")
      }
    }
  }

  func testSingleWordSuggestionsKeepTheirExistingSequence() throws {
    let results = [result(language: .english, prompt: "amber harbor", mistaken: "m")]
    let report = try XCTUnwrap(WeakSpotPractice.report(results: results, language: .english,
      englishVariant: .american))
    XCTAssertFalse(report.suggestedWords.contains { $0.contains(" ") })
    let expected = (0..<50).map { report.suggestedWords[$0 % report.suggestedWords.count] }
    XCTAssertEqual(WeakSpotPractice.prompt(results: results, language: .english,
      englishVariant: .american, wordCount: 50), expected.joined(separator: " "))
  }

  func testHistoryDrillConsumerCompletesAndRepeatsAtTheSelectedLimit() throws {
    let results = [result(language: .french, prompt: "tout à fait", mistaken: "à")]
    for count in [10, 25, 50] {
      let prompt = try XCTUnwrap(WeakSpotPractice.prompt(results: results, language: .french,
        englishVariant: .american, wordCount: count))
      let configuration = TestConfiguration(mode: .custom, duration: nil,
        wordLimit: prompt.split(separator: " ").count, difficulty: .normal,
        rules: .init(), language: .french, customTextCompletion: .words,
        customTextOrdering: .inOrder)
      var session = TestSessionFactory.make(configuration: configuration, customText: prompt)
      XCTAssertEqual(session.prompt, prompt)
      session.insertBatch(prompt, at: Date(timeIntervalSince1970: 10))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.completedWordCount, count)
      XCTAssertEqual(session.repeatedAttempt().prompt, prompt)
    }
  }

  func testEmptyHistoryStillCannotStartADrill() {
    XCTAssertNil(WeakSpotPractice.prompt(results: [], language: .french,
      englishVariant: .american, wordCount: 25))
  }
}
