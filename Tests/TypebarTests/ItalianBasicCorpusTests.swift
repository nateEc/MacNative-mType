import XCTest
@testable import Typebar

final class ItalianBasicCorpusTests: XCTestCase {
  func testBasicItalianContainsAFullIndependentVocabulary() {
    let words = TypingLanguage.italian.ownedPracticeWords()
    XCTAssertEqual(words.count, 199)
    XCTAssertEqual(Set(words).count, 199)
    XCTAssertTrue(words.contains("perché"))
    XCTAssertTrue(words.contains("città"))
    XCTAssertTrue(words.allSatisfy { !$0.contains(" ") && $0 == $0.precomposedStringWithCanonicalMapping })
  }

  func testActualFactoryCanSelectBeyondTheOldSampleAndRepeatItsTarget() {
    let words = TypingLanguage.italian.ownedPracticeWords()
    guard words.count == 199 else { return XCTFail("The full pool must be connected before testing its last candidate") }
    var session = TestSessionFactory.make(configuration: .words(1, language: .italian),
      nextRandomWordIndex: { 198 })
    XCTAssertEqual(session.prompt, words[198])
    session.insertBatch(session.prompt, at: Date(timeIntervalSince1970: 10))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 1)
    XCTAssertEqual(session.repeatedAttempt().prompt, words[198])
  }

  func testDefaultPolyglotDoesNotGainAnExtraLanguage() {
    XCTAssertEqual(TypingLanguage.referenceDefaultMixedComponents, [.english, .spanish, .french, .german])
  }

  func testOldItalianHistoryKeepsItsCapturedTextAndReplay() throws {
    let prompt = "albero strada"
    let result = CompletedTestResult(id: UUID(), configuration: .words(2, language: .italian),
      outcome: .completed, startedAt: Date(timeIntervalSince1970: 1),
      finishedAt: Date(timeIntervalSince1970: 5), typedCharacterCount: prompt.count,
      correctCharacterCount: prompt.count, errorCount: 0, wpm: 30, rawWpm: 30,
      accuracy: 100, prompt: prompt, replayEvents: [.init(offset: 1, kind: .insert, text: prompt)])
    let restored = try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(result))
    XCTAssertEqual(restored.configuration, result.configuration)
    XCTAssertEqual(restored.prompt, prompt)
    XCTAssertEqual(restored.replayEvents, result.replayEvents)
    XCTAssertEqual(restored.wpm, result.wpm)
    XCTAssertEqual(TypingReplay.typedText(events: restored.replayEvents, through: 1), prompt)
  }
}
