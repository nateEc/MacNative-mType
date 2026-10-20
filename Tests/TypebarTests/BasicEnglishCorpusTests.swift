import XCTest
@testable import Typebar

final class BasicEnglishCorpusTests: XCTestCase {
  func testDefaultPoolHasTwoHundredShortFrequencyOrderedDictionaryWords() {
    let words = TypingLanguage.english.ownedPracticeWords()
    XCTAssertEqual(words.count, 200)
    XCTAssertEqual(Set(words).count, 200)
    XCTAssertEqual(Array(words.prefix(7)), ["the", "to", "and", "of", "a", "in", "I"])
    XCTAssertTrue(words.allSatisfy { $0.count <= 8 && ($0.count > 1 || ["a", "I"].contains($0)) })
    XCTAssertTrue(words.allSatisfy { $0 == $0.lowercased() || $0 == "I" })
    XCTAssertEqual(TypingLanguage.english.zipfFrequencySupport, .supported)
    XCTAssertTrue(words.contains("people"))
  }

  func testDefaultFactoryUsesTheNewPoolAndCanReachItsLastEntry() {
    let words = TypingLanguage.english.ownedPracticeWords()
    var rank = 0
    let session = TestSessionFactory.make(configuration: .words(3), nextRandomWordIndex: {
      defer { rank += 1 }; return rank
    })
    XCTAssertEqual(session.prompt, "the to and")
    let tail = TestSessionFactory.make(configuration: .words(1), nextRandomWordIndex: { 199 })
    XCTAssertEqual(tail.prompt, words.last?.lowercased())
    XCTAssertEqual(tail.repeatedAttempt().prompt, tail.prompt)
  }

  func testBritishChoiceUsesTheSameSizedBaseInsteadOfASixteenWordSpecialtyList() {
    let american = TypingLanguage.english.ownedPracticeWords()
    let british = TypingLanguage.english.ownedPracticeWords(englishVariant: .british)
    XCTAssertEqual(british.count, 200)
    XCTAssertEqual(british, american.map { BritishEnglishPolicy.transformed($0,
      context: .init(configuration: .words(1, englishVariant: .british))) })
    let session = TestSessionFactory.make(configuration: .words(1, englishVariant: .british),
      nextRandomWordIndex: { 0 })
    XCTAssertEqual(session.prompt, "the")
  }

  func testPigLatinAuthoredCorpusIsNotChangedByTheDefaultEnglishCutover() {
    XCTAssertEqual(StarterLexicon.pigLatinWords, [
      "amber", "harbor", "quiet", "copper", "lantern", "paper", "window", "drift",
      "meadow", "signal", "summer", "orchard", "canyon", "violet", "planet", "moss",
      "ripple", "thunder", "willow", "tangent", "pocket", "marble", "voyage", "bright",
    ].map(PigLatinPolicy.transform))
  }

  func testOldDefaultAndBritishResultsKeepTheirCapturedPromptAndReplay() throws {
    for (variant, prompt) in [(EnglishVariant.american, "amber harbor"), (.british, "colour favour")] {
      let result = CompletedTestResult(
        id: UUID(), configuration: .words(2, englishVariant: variant), outcome: .completed,
        startedAt: Date(timeIntervalSince1970: 1), finishedAt: Date(timeIntervalSince1970: 5),
        typedCharacterCount: prompt.count, correctCharacterCount: prompt.count,
        errorCount: 0, wpm: 30, rawWpm: 30, accuracy: 100, prompt: prompt,
        replayEvents: [.init(offset: 1, kind: .insert, text: prompt)])
      let restored = try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(result))
      XCTAssertEqual(restored.prompt, prompt)
      XCTAssertEqual(restored.configuration, result.configuration)
      XCTAssertEqual(restored.replayEvents, result.replayEvents)
      XCTAssertEqual(TypingReplay.typedText(events: restored.replayEvents, through: 1), prompt)
    }
  }
}
