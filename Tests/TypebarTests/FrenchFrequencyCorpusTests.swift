import XCTest
import CryptoKit
@testable import Typebar

final class FrenchFrequencyCorpusTests: XCTestCase {
  let languages: [TypingLanguage] = [.french1k, .french2k, .french10k]

  func testBasicFrenchDataDoesNotDriftWhenScalePoolsChange() {
    let body = TypingLanguage.french.ownedPracticeWords().joined(separator: "\n") + "\n"
    XCTAssertEqual(SHA256.hash(data: Data(body.utf8)).map { String(format: "%02x", $0) }.joined(),
      "46ffc446cfc460248ea8fae8ca6790eee06094a0e3e101a0dd308a7d92720390")
  }

  func testSharedObservedPrefixesAndAuthoredSectionsStayIndependent() {
    let pools = languages.map { $0.ownedPracticeWords() }
    for smaller in pools.dropLast() {
      XCTAssertEqual(Array(smaller.dropLast(6)), Array(pools[2].prefix(smaller.count - 6)))
      XCTAssertEqual(Array(smaller.suffix(6)), Array(pools[2].suffix(6)))
    }
  }

  func testThreeScalesContainObservedVocabularyAndIndependentExpressions() {
    for (language, count) in zip(languages, [1_394, 2_041, 10_251]) {
      let words = language.ownedPracticeWords()
      XCTAssertEqual(words.count, count); XCTAssertEqual(Set(words).count, count)
      XCTAssertEqual(Array(words.prefix(3)), ["de", "la", "le"])
      XCTAssertTrue(words.contains("être")); XCTAssertTrue(words.contains("France"))
      XCTAssertTrue(words.contains("tout à fait")); XCTAssertTrue(words.contains("peut-être"))
      XCTAssertFalse(words.contains { $0.hasPrefix("qfr") || $0.hasPrefix("wfr") || $0.hasPrefix("xfr") })
    }
  }

  func testAuthoredSectionsProduceActualFieldsAndRepeatWithoutResampling() throws {
    for language in languages {
      let pool = language.ownedPracticeLexicon()
      let rank = try XCTUnwrap(pool.firstIndex(of: "tout à fait"))
      for modifiers: [TestModifier] in [[], [.noSpaces]] {
        var session = TestSessionFactory.make(configuration: .words(3, language: language)
          .with(modifiers: modifiers), nextRandomWordIndex: { rank })
        let expected = modifiers.isEmpty ? "tout à fait" : "toutàfait"
        XCTAssertEqual(session.prompt, expected)
        session.insertBatch(expected, at: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(session.outcome, .completed); XCTAssertEqual(session.errors, 0)
        XCTAssertEqual(session.wordReviews.map(\.target), ["tout", "à", "fait"])
        XCTAssertEqual(session.repeatedAttempt().prompt, expected)
      }
    }
  }

  func testActualFactoryCanSelectTheObservedTailOfEveryScale() {
    for language in languages {
      let words = language.ownedPracticeWords(), rank = words.count - 7
      var session = TestSessionFactory.make(configuration: .words(1, language: language),
        nextRandomWordIndex: { rank })
      XCTAssertEqual(session.prompt, words[rank].lowercased())
      session.insertBatch(session.prompt, at: Date(timeIntervalSince1970: 10))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.repeatedAttempt().prompt, session.prompt)
    }
  }

  func testFiniteAttemptsMayFinishInsideAnAuthoredSection() throws {
    for language in languages {
      let rank = try XCTUnwrap(language.ownedPracticeLexicon().firstIndex(of: "tout à fait"))
      var session = TestSessionFactory.make(configuration: .words(2, language: language),
        nextRandomWordIndex: { rank })
      XCTAssertEqual(session.prompt, "tout à")
      session.insertBatch(session.prompt, at: Date(timeIntervalSince1970: 10))
      XCTAssertEqual(session.outcome, .completed); XCTAssertEqual(session.completedWordCount, 2)
      XCTAssertEqual(session.wordReviews.map(\.target), ["tout", "à"])
      XCTAssertEqual(session.repeatedAttempt().prompt, "tout à")
    }
  }

  func testProperNameAndCompoundAreUsableWithPunctuationEnabled() throws {
    for word in ["France", "peut-être"] {
      let rank = try XCTUnwrap(TypingLanguage.french10k.ownedPracticeLexicon().firstIndex(of: word))
      var configuration = TestConfiguration.words(1, language: .french10k)
      configuration.contentOptions.includePunctuation = true
      var session = TestSessionFactory.make(configuration: configuration,
        nextRandomWordIndex: { rank }, nextRandomContentUnit: { 0.99 })
      XCTAssertTrue(session.prompt.contains(word.prefix(1).uppercased() + word.dropFirst()))
      let prompt = session.prompt
      session.insertBatch(prompt, at: Date(timeIntervalSince1970: 10))
      XCTAssertEqual(session.outcome, .completed); XCTAssertEqual(session.errors, 0)
      XCTAssertEqual(session.repeatedAttempt().prompt, prompt)
    }
  }

  func testLongRealVocabularyAttemptGrowsAndRepeatsCapturedTargets() {
    let words = TypingLanguage.french10k.ownedPracticeWords()
    var index = 4_000
    var session = TestSessionFactory.make(configuration: .words(153, language: .french10k),
      nextRandomWordIndex: { defer { index += 1 }; return index % (words.count - 6) })
    let opening = session.prompt
    session.insert(opening, at: Date(timeIntervalSince1970: 10))
    XCTAssertEqual(session.completedWordCount, 100); XCTAssertEqual(session.outcome, .active)
    session.insert(String(session.prompt.dropFirst(session.typed.count)), at: Date(timeIntervalSince1970: 11))
    XCTAssertEqual(session.completedWordCount, 153); XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
    var repeated = session.repeatedAttempt(); XCTAssertEqual(repeated.prompt, opening)
    repeated.insert(opening, at: Date(timeIntervalSince1970: 12))
    repeated.insert(String(repeated.prompt.dropFirst(repeated.typed.count)), at: Date(timeIntervalSince1970: 13))
    XCTAssertEqual(repeated.outcome, .completed); XCTAssertEqual(repeated.prompt, session.prompt)
  }

  func testOldSyntheticResultsRetainOriginalPromptsAndReplay() throws {
    for (language, prompt) in zip(languages, ["qfrarca qfrboisb", "wfrarca wfrboisb", "xfrarca xfrboisb"]) {
      let result = CompletedTestResult(id: UUID(), configuration: .words(2, language: language),
        outcome: .completed, startedAt: Date(timeIntervalSince1970: 1), finishedAt: Date(timeIntervalSince1970: 5),
        typedCharacterCount: prompt.count, correctCharacterCount: prompt.count, errorCount: 0,
        wpm: 30, rawWpm: 30, accuracy: 100, prompt: prompt,
        replayEvents: [.init(offset: 1, kind: .insert, text: prompt)])
      let restored = try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(result))
      XCTAssertEqual(restored.configuration, result.configuration); XCTAssertEqual(restored.prompt, prompt)
      XCTAssertEqual(restored.replayEvents, result.replayEvents); XCTAssertEqual(restored.wpm, result.wpm)
      XCTAssertEqual(TypingReplay.typedText(events: restored.replayEvents, through: 1), prompt)
    }
  }
}
