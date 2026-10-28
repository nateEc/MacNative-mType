import XCTest
import CryptoKit
@testable import Typebar

final class ItalianLargeCorpusTests: XCTestCase {
  private let languages: [TypingLanguage] = [.italian60k, .italian280k]

  func testLargeChoicesContainObservedWordsAndNoSyntheticPadding() {
    let expected = [
      (60_442, 18, "b8d8cb17833a65b0d4d909b84a3a30599b1ea7fe0be6cf0e4f28a07d18884461"),
      (279_833, 23, "0ad46947455d19f60fb56b14c79fdcde719f77103eb44fb44f01662e91c11a17"),
    ]
    for (language, (count, maximum, hash)) in zip(languages, expected) {
      let words = language.ownedPracticeWords()
      XCTAssertEqual(words.count, count); XCTAssertEqual(Set(words).count, count)
      XCTAssertEqual(Array(words.prefix(3)), ["di", "e", "che"])
      XCTAssertTrue(words.contains("perché")); XCTAssertTrue(words.contains("Italia"))
      XCTAssertEqual(words.map(\.count).max(), maximum)
      XCTAssertFalse(words.contains { $0.lowercased().hasPrefix("qit") || $0.hasPrefix("ìq") })
      XCTAssertEqual(SHA256.hash(data: Data((words.joined(separator: "\n") + "\n").utf8))
        .map { String(format: "%02x", $0) }.joined(), hash)
    }
    XCTAssertEqual(languages[0].ownedPracticeWords().last, "C#")
    XCTAssertEqual(languages[1].ownedPracticeWords().last, "esaminatelo")
  }

  func testLargePoolRetainsTheExistingSmallPoolsAsBoundedFrequencyPrefixes() {
    let largest = TypingLanguage.italian280k.ownedPracticeWords()
    XCTAssertEqual(TypingLanguage.italian1k.ownedPracticeWords(), Array(largest.filter { $0.count <= 14 }.prefix(1_159)))
    XCTAssertEqual(TypingLanguage.italian7k.ownedPracticeWords(), Array(largest.filter { $0.count <= 18 }.prefix(7_154)))
    let medium = TypingLanguage.italian60k.ownedPracticeWords()
    XCTAssertEqual(Array(medium.prefix(60_423)), Array(largest.filter { $0.count <= 18 }.prefix(60_423)))
    XCTAssertEqual(Array(medium.suffix(2)), ["C++", "C#"])
    XCTAssertEqual(medium.suffix(19).filter { $0.contains("'") }.count, 17)
  }

  func testLowFrequencyAccentedWordCanBeTypedWithAndWithoutSpaces() throws {
    let language = TypingLanguage.italian280k
    let rank = try XCTUnwrap(language.ownedPracticeLexicon().firstIndex(of: "erutterà"))
    XCTAssertGreaterThan(rank, 60_442)
    for modifiers: [TestModifier] in [[], [.noSpaces], [.lazyLatin], [.lazyLatin, .noSpaces]] {
      var session = TestSessionFactory.make(configuration: .words(1, language: language).with(modifiers: modifiers),
        nextRandomWordIndex: { rank })
      let expected = modifiers.contains(.lazyLatin) ? "eruttera" : "erutterà"
      XCTAssertEqual(session.prompt, expected)
      session.insertBatch(expected, at: Date(timeIntervalSince1970: 10))
      XCTAssertEqual(session.outcome, .completed); XCTAssertEqual(session.errors, 0)
      XCTAssertEqual(session.repeatedAttempt().prompt, session.prompt)
    }
  }

  func testProperNameRemainsSelectableThroughPunctuationAndRepeat() throws {
    for language in languages {
      let rank = try XCTUnwrap(language.ownedPracticeLexicon().firstIndex(of: "Italia"))
      var configuration = TestConfiguration.words(1, language: language)
      configuration.contentOptions.includePunctuation = true
      var session = TestSessionFactory.make(configuration: configuration,
        nextRandomWordIndex: { rank }, nextRandomContentUnit: { 0.99 })
      XCTAssertTrue(session.prompt.contains("Italia"))
      let prompt = session.prompt
      session.insertBatch(prompt, at: Date(timeIntervalSince1970: 10))
      XCTAssertEqual(session.outcome, .completed); XCTAssertEqual(session.errors, 0)
      XCTAssertEqual(session.repeatedAttempt().prompt, prompt)
    }
  }

  func testObservedElisionAndEditorialSymbolsKeepTheirInputAndRepeatPaths() throws {
    let language = TypingLanguage.italian60k
    for word in ["com'è", "C++", "C#"] {
      let rank = try XCTUnwrap(language.ownedPracticeLexicon().firstIndex(of: word))
      for modifiers: [TestModifier] in [[], [.noSpaces]] {
        var configuration = TestConfiguration.words(1, language: language).with(modifiers: modifiers)
        configuration.contentOptions.includePunctuation = true
        var session = TestSessionFactory.make(configuration: configuration,
          nextRandomWordIndex: { rank }, nextRandomContentUnit: { 0.99 })
        XCTAssertTrue(session.prompt.lowercased().contains(word.lowercased()))
        let prompt = session.prompt
        session.insertBatch(prompt, at: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(session.outcome, .completed); XCTAssertEqual(session.errors, 0)
        XCTAssertEqual(session.repeatedAttempt().prompt, prompt)
      }
    }
  }

  func testLargePoolLongAttemptsContinueAndRepeatTheirActualCapturedTargets() {
    for language in languages {
      var rank = language.ownedPracticeLexicon().count - 200
      var session = TestSessionFactory.make(configuration: .words(153, language: language),
        nextRandomWordIndex: { defer { rank += 1 }; return rank })
      let opening = session.prompt
      session.insert(opening, at: Date(timeIntervalSince1970: 10))
      XCTAssertEqual(session.completedWordCount, 100); XCTAssertEqual(session.outcome, .active)
      session.insert(String(session.prompt.dropFirst(session.typed.count)), at: Date(timeIntervalSince1970: 11))
      XCTAssertEqual(session.completedWordCount, 153); XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.errors, 0)
      var repeated = session.repeatedAttempt()
      XCTAssertEqual(repeated.prompt, opening)
      repeated.insert(opening, at: Date(timeIntervalSince1970: 12))
      repeated.insert(String(repeated.prompt.dropFirst(repeated.typed.count)), at: Date(timeIntervalSince1970: 13))
      XCTAssertEqual(repeated.outcome, .completed); XCTAssertEqual(repeated.prompt, session.prompt)
    }
  }

  func testOldLargeSyntheticResultsKeepTheirCapturedPromptsAndMetrics() throws {
    for language in languages {
      let prompt = "qitcabc qitdabc"
      let result = CompletedTestResult(id: UUID(), configuration: .words(2, language: language), outcome: .completed,
        startedAt: Date(timeIntervalSince1970: 1), finishedAt: Date(timeIntervalSince1970: 5),
        typedCharacterCount: prompt.count, correctCharacterCount: prompt.count, errorCount: 0,
        wpm: 30, rawWpm: 30, accuracy: 100, prompt: prompt, replayEvents: [.init(offset: 1, kind: .insert, text: prompt)])
      let restored = try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(result))
      XCTAssertEqual(restored, result); XCTAssertEqual(TestResultRecord(result: result).portableResult, result)
      XCTAssertEqual(TypingReplay.typedText(events: restored.replayEvents, through: 1), prompt)
    }
  }
}
