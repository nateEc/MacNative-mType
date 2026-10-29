import CryptoKit
import XCTest
@testable import Typebar

final class GermanFrequencyCorpusTests: XCTestCase {
  func testActualGermanChoicesContainAttestedCommonForms() {
    for language: TypingLanguage in [.german1k, .german10k, .german250k] {
      let words = language.ownedPracticeLexicon()
      for word in ["und", "Haus", "Straße", "weiß"] {
        XCTAssertNotNil(words.firstIndex(of: word), "\(language.rawValue) is missing \(word)")
      }
    }
  }

  func testActualNativeDataMatchesTheReproducedLiteralForms() {
    for (language, expected): (TypingLanguage, String) in [
      (.german1k, "d2cea3f886167e249b438177ee00bcc478e89220e1650b6c608e4028a526ca16"),
      (.german10k, "8f7574893ed17df50c58801441f159a0e04d3622bb3c76effe3f21fcc82e94c6"),
      (.german250k, "ca74b2b71791f169de73afc0c29d948ae394117e3bff05a212ae712c34bdcaac"),
    ] {
      let body = language.ownedPracticeWords().joined(separator: "\n") + "\n"
      XCTAssertEqual(SHA256.hash(data: Data(body.utf8)).map { String(format: "%02x", $0) }.joined(), expected)
    }
    let basic = TypingLanguage.german.ownedPracticeWords().joined(separator: "\n") + "\n"
    XCTAssertEqual(SHA256.hash(data: Data(basic.utf8)).map { String(format: "%02x", $0) }.joined(),
      "5096ce3837e415e877b0ac35f88dd10d63b969eee6708c063b9d6c61266f4d91")
  }

  func testLiteralCaseAndEszettReachInputAndLazyLatinWithoutLowercasingTheCorpus() throws {
    for language: TypingLanguage in [.german1k, .german10k, .german250k] {
      let lexicon = language.ownedPracticeLexicon()
      let rank = try XCTUnwrap(lexicon.firstIndex(of: "Straße"))
      for modifiers: [TestModifier] in [[], [.noSpaces], [.lazyLatin], [.lazyLatin, .noSpaces]] {
        var session = TestSessionFactory.make(configuration: .words(1, language: language).with(modifiers: modifiers),
          nextRandomWordIndex: { rank })
        let expected = modifiers.contains(.lazyLatin) ? "Strasse" : "Straße"
        XCTAssertEqual(session.prompt, expected)
        session.insertBatch(expected, at: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(session.outcome, .completed)
        XCTAssertEqual(session.errors, 0)
        XCTAssertEqual(session.repeatedAttempt().prompt, expected)
      }
      XCTAssertEqual(lexicon[rank], "Straße")
    }
  }

  func testExistingLongFormsSupportInputBackwardsAndRepeatAtEveryLengthBound() throws {
    for (language, word): (TypingLanguage, String) in [(.german1k, "unterschiedlichen"),
      (.german10k, "Weltgesundheitsorganisation"), (.german250k, "Elektrizitätsversorgungsunternehmen")] {
      let lexicon = language.ownedPracticeLexicon()
      let rank = try XCTUnwrap(lexicon.firstIndex(of: word))
      for modifiers: [TestModifier] in [[], [.noSpaces], [.backwards], [.backwards, .noSpaces]] {
        let actualRank = modifiers.contains(.backwards) ? lexicon.count - 1 - rank : rank
        var session = TestSessionFactory.make(configuration: .words(1, language: language).with(modifiers: modifiers),
          nextRandomWordIndex: { actualRank })
        let expected = modifiers.contains(.backwards) ? String(word.reversed()) : word
        XCTAssertEqual(session.prompt, expected)
        session.insertBatch(expected, at: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(session.outcome, .completed)
        XCTAssertEqual(session.errors, 0)
        XCTAssertEqual(session.repeatedAttempt().prompt, expected)
      }
    }
  }

  func testAllLiteralPunctuationExamplesRemainActualTypeableWords() throws {
    for language: TypingLanguage in [.german1k, .german10k] {
      let lexicon = language.ownedPracticeLexicon()
      let words = lexicon.filter { $0.contains(where: \.isPunctuation) }
      XCTAssertEqual(words.count, language == .german1k ? 3 : 25)
      for word in words {
        let rank = try XCTUnwrap(lexicon.firstIndex(of: word))
        for modifiers: [TestModifier] in [[], [.noSpaces]] {
          var session = TestSessionFactory.make(configuration: .words(1, language: language).with(modifiers: modifiers),
            nextRandomWordIndex: { rank })
          XCTAssertEqual(session.prompt, word)
          session.insertBatch(word, at: Date(timeIntervalSince1970: 10))
          XCTAssertEqual(session.outcome, .completed)
          XCTAssertEqual(session.errors, 0)
          XCTAssertEqual(session.repeatedAttempt().prompt, word)
        }
      }
    }
  }

  func testEveryMultiwordCandidateSupportsFiniteBoundariesNoSpacesAndRepeat() throws {
    for language: TypingLanguage in [.german1k, .german10k] {
      let lexicon = language.ownedPracticeLexicon()
      let phrases = lexicon.filter { $0.contains(" ") }
      XCTAssertEqual(phrases.count, language == .german1k ? 8 : 40)
      for phrase in phrases {
        let fields = phrase.split(separator: " ").map(String.init)
        let rank = try XCTUnwrap(lexicon.firstIndex(of: phrase))
        for modifiers: [TestModifier] in [[], [.noSpaces]] {
          var session = TestSessionFactory.make(configuration: .words(fields.count, language: language).with(modifiers: modifiers),
            nextRandomWordIndex: { rank })
          let expected = fields.joined(separator: modifiers.isEmpty ? " " : "")
          XCTAssertEqual(session.prompt, expected)
          session.insertBatch(expected, at: Date(timeIntervalSince1970: 10))
          XCTAssertEqual(session.outcome, .completed)
          XCTAssertEqual(session.completedWordCount, fields.count)
          XCTAssertEqual(session.wordReviews.map(\.target), fields)
          XCTAssertEqual(session.repeatedAttempt().prompt, expected)
        }
        var truncated = TestSessionFactory.make(configuration: .words(1, language: language), nextRandomWordIndex: { rank })
        XCTAssertEqual(truncated.prompt, fields[0])
        truncated.insertBatch(fields[0], at: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(truncated.outcome, .completed)
        XCTAssertEqual(truncated.wordReviews.map(\.target), [fields[0]])
      }
    }
  }

  func testLargeFiniteContinuationAndRepeatKeepTheActualCapturedForms() {
    var rank = 100_000
    var session = TestSessionFactory.make(configuration: .words(153, language: .german250k),
      nextRandomWordIndex: { defer { rank += 1 }; return rank })
    let opening = session.prompt
    session.insert(opening, at: Date(timeIntervalSince1970: 10))
    XCTAssertEqual(session.completedWordCount, 100)
    XCTAssertEqual(session.outcome, .active)
    session.insert(String(session.prompt.dropFirst(session.typed.count)), at: Date(timeIntervalSince1970: 11))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 153)
    var repeated = session.repeatedAttempt()
    repeated.insert(opening, at: Date(timeIntervalSince1970: 12))
    repeated.insert(String(repeated.prompt.dropFirst(repeated.typed.count)), at: Date(timeIntervalSince1970: 13))
    XCTAssertEqual(repeated.outcome, .completed)
    XCTAssertEqual(repeated.prompt, session.prompt)
  }

  func testOldSyntheticResultsRetainCapturedTextAndFrozenMetrics() throws {
    let prompt = "wx " + String(repeating: "w", count: 27) + " Wgduferb"
    let result = CompletedTestResult(id: UUID(), configuration: .words(3, language: .german10k), outcome: .completed,
      startedAt: Date(timeIntervalSince1970: 1), finishedAt: Date(timeIntervalSince1970: 5),
      typedCharacterCount: prompt.count, correctCharacterCount: prompt.count, errorCount: 0,
      wpm: 30, rawWpm: 30, accuracy: 100, prompt: prompt,
      replayEvents: [.init(offset: 1, kind: .insert, text: prompt)])
    let restored = try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(result))
    XCTAssertEqual(restored, result)
    XCTAssertEqual(TestResultRecord(result: restored).portableResult, result)
    XCTAssertEqual(TypingReplay.typedText(events: restored.replayEvents, through: 1), prompt)
  }
}
