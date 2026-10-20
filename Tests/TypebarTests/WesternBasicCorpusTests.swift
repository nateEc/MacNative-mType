import XCTest
@testable import Typebar

final class WesternBasicCorpusTests: XCTestCase {
  func testDefaultWesternChoicesHaveTheirFullCandidateCountsAndRealSections() {
    let cases: [(TypingLanguage, Int, Int)] = [(.spanish, 197, 0), (.french, 174, 2), (.german, 200, 2)]
    for (language, expected, sections) in cases {
      let words = language.ownedPracticeWords()
      XCTAssertEqual(words.count, expected, language.rawValue)
      XCTAssertEqual(Set(words.map { $0.lowercased() }).count, expected)
      XCTAssertEqual(words.filter { $0.contains(" ") }.count, sections)
      XCTAssertEqual(language.zipfFrequencySupport, .unknown)
      XCTAssertTrue(words.allSatisfy { $0 == $0.precomposedStringWithCanonicalMapping })
    }
  }

  func testDefaultPolyglotPoolKeepsTheReferenceUnionAndLastOwnerRules() {
    let languages = TypingLanguage.referenceDefaultMixedComponents
    XCTAssertEqual(languages, [.english, .spanish, .french, .german])
    let sources = languages.map { ($0, $0.ownedPracticeLexicon()) }
    let candidates = NativePolyglotCandidates(sources: sources, nextShuffleIndex: { $0 - 1 })
    let pool = candidates.lexicon
    let combined = sources.flatMap { $0.1.materialized() }
    XCTAssertEqual(combined.count, 771)
    XCTAssertEqual(pool.count, Set(combined).count)
    XCTAssertEqual(pool.materialized().sorted(), Set(combined).sorted())
    XCTAssertEqual(candidates.language(for: "in"), .german)
    XCTAssertEqual(candidates.language(for: "de"), .french)
  }

  func testMultiwordCandidatesBecomeActualFiniteAndNoSpaceWordTargets() throws {
    for (language, phrase) in [(TypingLanguage.french, "tout à fait"), (.german, "zu Hause")] {
      let words = phrase.split(separator: " ").map(String.init)
      let rank = try XCTUnwrap(language.ownedPracticeLexicon().firstIndex(of: phrase))
      for modifiers: [TestModifier] in [[], [.noSpaces]] {
        var session = TestSessionFactory.make(configuration: .words(words.count, language: language)
          .with(modifiers: modifiers), nextRandomWordIndex: { rank })
        let expected = words.joined(separator: modifiers.isEmpty ? " " : "")
        XCTAssertEqual(session.prompt, expected)
        session.insertBatch(expected, at: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(session.outcome, .completed)
        XCTAssertEqual(session.completedWordCount, words.count)
        XCTAssertEqual(session.wordReviews.map(\.target), words)
        XCTAssertEqual(session.repeatedAttempt().prompt, expected)
      }
    }
  }

  func testFiniteCountCanEndInsideAMultiwordCandidateWithoutLeakingTheTail() throws {
    let rank = try XCTUnwrap(TypingLanguage.french.ownedPracticeLexicon().firstIndex(of: "tout à fait"))
    var session = TestSessionFactory.make(configuration: .words(2, language: .french),
      nextRandomWordIndex: { rank })
    XCTAssertEqual(session.prompt, "tout à")
    session.insertBatch("tout à", at: Date(timeIntervalSince1970: 10))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.wordReviews.map(\.target), ["tout", "à"])
  }

  func testEachWesternFactoryCanSelectBeyondItsOldStarterPoolAndKeepTheTarget() {
    for language in [TypingLanguage.spanish, .french, .german] {
      let word = language.ownedPracticeLexicon()[30 % language.ownedPracticeLexicon().count]
      let session = TestSessionFactory.make(configuration: .words(1, language: language),
        nextRandomWordIndex: { 30 })
      XCTAssertEqual(session.prompt, language == .german ? word : word.lowercased())
      XCTAssertEqual(session.repeatedAttempt().prompt, session.prompt)
    }
  }

  func testSwissGermanContinuesToDeriveFromTheSameFullGermanPool() {
    XCTAssertEqual(StarterLexicon.swissGermanWords.count, 200)
    XCTAssertEqual(StarterLexicon.swissGermanWords,
      StarterLexicon.germanWords.map { $0.replacingOccurrences(of: "ß", with: "ss") })
  }

  func testOldWesternResultsKeepPromptConfigurationAndReplayAfterTheNewPool() throws {
    for (language, prompt) in [(TypingLanguage.spanish, "árbol camino"), (.french, "arbre chemin"),
      (.german, "abend brücke")] {
      let result = CompletedTestResult(
        id: UUID(), configuration: .words(2, language: language), outcome: .completed,
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
