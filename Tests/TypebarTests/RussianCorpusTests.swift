import CryptoKit
import XCTest
@testable import Typebar

final class RussianCorpusTests: XCTestCase {
  static let languages: [TypingLanguage] = [
    .russian1k, .russian5k, .russian10k, .russian25k, .russian50k, .russian375k,
  ]

  func testAllSixScalesContainActualCommonRussianWords() {
    for language in Self.languages {
      let words = Set(language.ownedPracticeWords())
      for word in ["человек", "время", "язык", "ещё"] {
        XCTAssertTrue(words.contains(word), "\(language.rawValue) has no actual \(word) practice")
      }
    }
  }

  private func inputClass(_ word: String) -> String {
    let key = (word.contains(where: \.isUppercase) ? "C" : "")
      + (word.contains(where: \.isPunctuation) ? "P" : "") + (word.contains(" ") ? "S" : "")
    return key.isEmpty ? "L" : key
  }

  func testPublishedWordsAreExactAndBasicPoolStaysUnchanged() throws {
    let hashes: [TypingLanguage: String] = [
      .russian1k: "6cb468c0bbbec1e5403e6ea2011a735bf2bbdf9261945e441453494783e9b06e",
      .russian5k: "3ac08a85b31863548b45998f792e9ac9a370ee7a5becce26f2cc7adfd9ca31e4",
      .russian10k: "48e6b00aaf45e31d8f3766f7040b2b3df4a294349987cf633a0628debf766027",
      .russian25k: "664ff8c19ff66c7f60ce197ae4788307e707c1d342736c753a3a46e7b64db07a",
      .russian50k: "78e1c9afc79349cae3f2fbc9bcf60b23a0a06ab70038e93221d091257afd5859",
      .russian375k: "c31c98e6ccff917a88c2bfbd76e45ab9a259ecf44a45edeb1b670b298e63c369",
      .russian: "c1efe8fabc0aaf6ce2f1617e30875220c830a7afd0d5f02134b2c0ffc42494e2",
    ]
    for (language, expected) in hashes {
      let words = language.ownedPracticeWords()
      let actual = SHA256.hash(data: Data((words.joined(separator: "\n") + "\n").utf8))
        .map { String(format: "%02x", $0) }.joined()
      XCTAssertEqual(actual, expected)
    }
    XCTAssertEqual(TypingLanguage.russian.ownedPracticeWords().count, 24)
    XCTAssertTrue(Self.languages.allSatisfy { !TypingLanguage.defaultMixedComponents.contains($0) })
  }

  func testActualInputClassesRetainSeparateLengthsAndFields() throws {
    let expected: [TypingLanguage: [String: [Int]]] = [
      .russian1k: ["C": [2, 6, 6, 1, 6], "L": [993, 1, 15, 1, 15], "P": [1, 6, 6, 1, 6]],
      .russian5k: ["C": [40, 2, 10, 1, 10], "CS": [2, 14, 20, 2, 10], "L": [4927, 1, 17, 1, 17], "P": [2, 3, 9, 1, 9]],
      .russian10k: ["L": [9934, 1, 21, 1, 21], "P": [62, 5, 24, 1, 24]],
      .russian25k: ["C": [1209, 2, 17, 1, 17], "CP": [9, 8, 16, 1, 16], "L": [24306, 1, 24, 1, 24], "P": [513, 3, 34, 1, 34]],
      .russian50k: ["C": [2377, 2, 17, 1, 17], "CP": [19, 8, 18, 1, 18], "L": [48253, 1, 24, 1, 24], "P": [1033, 3, 34, 1, 34]],
      .russian375k: ["L": [376058, 1, 46, 1, 46], "P": [34, 5, 16, 1, 16]],
    ]
    for language in Self.languages {
      let words = language.ownedPracticeWords()
      let groups = Dictionary(grouping: words, by: inputClass)
      let specification = try XCTUnwrap(expected[language])
      XCTAssertEqual(Set(groups.keys), Set(specification.keys))
      for (key, spec) in specification {
        let values = try XCTUnwrap(groups[key])
        XCTAssertEqual([values.count, values.map(\.count).min()!, values.map(\.count).max()!,
          values.map { $0.split(separator: " ").count }.max()!,
          values.flatMap { $0.split(separator: " ").map(\.count) }.max()!], spec, language.rawValue + ": " + key)
      }
      XCTAssertEqual(words.count, Set(words).count)
      XCTAssertFalse(words.contains { $0.contains(where: \.isNumber) })
      XCTAssertTrue(words.allSatisfy { $0 == $0.precomposedStringWithCanonicalMapping })
    }
  }

  func testYoAliasesReachFactoryNoSpacesInputAndRepeat() throws {
    for language in Self.languages {
      let rank = try XCTUnwrap(language.ownedPracticeLexicon().firstIndex(of: "ещё"))
      for modifiers: [TestModifier] in [[], [.noSpaces]] {
        var session = TestSessionFactory.make(configuration: .words(1, language: language).with(modifiers: modifiers),
          nextRandomWordIndex: { rank })
        XCTAssertEqual(session.prompt, "ещё")
        session.insertBatch("eщe", at: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(session.outcome, .completed)
        XCTAssertEqual(session.errors, 0)
        XCTAssertEqual(session.typed, "ещё")
        XCTAssertEqual(session.repeatedAttempt().prompt, "ещё")
      }
    }
  }

  func testCyrillicProperNamesRetainExistingNonAsciiCaseRule() throws {
    for language: TypingLanguage in [.russian1k, .russian5k, .russian25k, .russian50k] {
      let rank = try XCTUnwrap(language.ownedPracticeLexicon().firstIndex(of: "Россия"))
      var session = TestSessionFactory.make(configuration: .words(1, language: language), nextRandomWordIndex: { rank })
      XCTAssertEqual(session.prompt, "Россия")
      session.insertBatch("Россия", at: Date(timeIntervalSince1970: 10))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.errors, 0)
      XCTAssertEqual(session.repeatedAttempt().prompt, "Россия")
    }
  }

  func testEveryPunctuationEntrySupportsActualInputDeletionNoSpacesAndRepeat() {
    for language in Self.languages {
      let lexicon = language.ownedPracticeLexicon()
      for rank in lexicon.indices.filter({ lexicon[$0].contains(where: \.isPunctuation) }) {
        let word = lexicon[rank]
        XCTAssertFalse(word.contains(" "))
        for modifiers: [TestModifier] in [[], [.noSpaces]] {
          var session = TestSessionFactory.make(configuration: .words(1, language: language).with(modifiers: modifiers),
            nextRandomWordIndex: { rank })
          XCTAssertEqual(session.prompt, word)
          session.insertBatch(String(word.dropLast()), at: Date(timeIntervalSince1970: 10))
          session.deleteBackward(at: Date(timeIntervalSince1970: 11))
          XCTAssertEqual(session.typed, String(word.dropLast(2)))
          session.insertBatch(String(word.suffix(2)), at: Date(timeIntervalSince1970: 12))
          XCTAssertEqual(session.outcome, .completed)
          XCTAssertEqual(session.errors, 0)
          XCTAssertEqual(session.repeatedAttempt().prompt, word)
        }
      }
    }
  }

  func testFiveThousandChoiceKeepsBothLiteralPunctuationKindsAndTwoPhrases() {
    let lexicon = TypingLanguage.russian5k.ownedPracticeLexicon()
    XCTAssertEqual(lexicon.filter { $0.contains(".") }.count, 1)
    XCTAssertEqual(lexicon.filter { $0.contains("-") }.count, 1)
    let ranks = lexicon.indices.filter { lexicon[$0].contains(" ") }
    XCTAssertEqual(ranks.count, 2)
    for rank in ranks {
      let fields = lexicon[rank].split(separator: " ").map(String.init)
      XCTAssertEqual(fields.count, 2)
      for modifiers: [TestModifier] in [[], [.noSpaces]] {
        var session = TestSessionFactory.make(configuration: .words(2, language: .russian5k).with(modifiers: modifiers),
          nextRandomWordIndex: { rank })
        let target = fields.joined(separator: modifiers.isEmpty ? " " : "")
        XCTAssertEqual(session.prompt, target)
        session.insertBatch(target, at: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(session.outcome, .completed)
        XCTAssertEqual(session.errors, 0)
        XCTAssertEqual(session.wordReviews.count, 2)
        XCTAssertEqual(session.repeatedAttempt().prompt, target)
      }
      XCTAssertEqual(TestSessionFactory.make(configuration: .words(1, language: .russian5k),
        nextRandomWordIndex: { rank }).prompt, fields[0])
    }
  }

  func testEveryClassLongestFieldSupportsActualInputBackwardsAndRepeat() {
    for language in Self.languages {
      let lexicon = language.ownedPracticeLexicon()
      let groups = Dictionary(grouping: lexicon.indices, by: { inputClass(lexicon[$0]) })
      for indices in groups.values {
        let rank = indices.max { lexicon[$0].count < lexicon[$1].count }!
        let word = lexicon[rank]
        let variants: [[TestModifier]] = word.contains(" ") ? [[], [.noSpaces]] : [[], [.noSpaces], [.backwards]]
        for modifiers in variants {
          let draw = modifiers.contains(.backwards) ? lexicon.count - 1 - rank : rank
          let target = modifiers.contains(.backwards) ? String(word.reversed()) : word
          let expected = modifiers.contains(.noSpaces) ? target.replacingOccurrences(of: " ", with: "") : target
          var session = TestSessionFactory.make(configuration: .words(word.split(separator: " ").count, language: language)
            .with(modifiers: modifiers), nextRandomWordIndex: { draw })
          XCTAssertEqual(session.prompt, expected)
          session.insertBatch(expected, at: Date(timeIntervalSince1970: 10))
          XCTAssertEqual(session.outcome, .completed)
          XCTAssertEqual(session.errors, 0)
          XCTAssertEqual(session.repeatedAttempt().prompt, expected)
        }
      }
    }
  }

  func testAllSixChoicesContinueBeyondOneHundredWordsAndRepeatCapturedTargets() {
    for language in Self.languages {
      var rank = 100
      var session = TestSessionFactory.make(configuration: .words(153, language: language),
        nextRandomWordIndex: { defer { rank += 1 }; return rank })
      let opening = session.prompt
      session.insert(opening, at: Date(timeIntervalSince1970: 10))
      XCTAssertEqual(session.completedWordCount, 100)
      XCTAssertEqual(session.outcome, .active)
      session.insert(String(session.prompt.dropFirst(session.typed.count)), at: Date(timeIntervalSince1970: 11))
      XCTAssertEqual(session.completedWordCount, 153)
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.errors, 0)
      var repeated = session.repeatedAttempt()
      repeated.insert(opening, at: Date(timeIntervalSince1970: 12))
      repeated.insert(String(repeated.prompt.dropFirst(repeated.typed.count)), at: Date(timeIntervalSince1970: 13))
      XCTAssertEqual(repeated.outcome, .completed)
      XCTAssertEqual(repeated.prompt, session.prompt)
    }
  }

  func testOldSyntheticPromptsFrozenMetricsAndReplayStayLiteral() throws {
    for language in Self.languages {
      let prompt = "ѿ ꙉабв- " + String(repeating: "ꙉ", count: 49)
      let result = CompletedTestResult(id: UUID(), configuration: .words(3, language: language), outcome: .completed,
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
}
