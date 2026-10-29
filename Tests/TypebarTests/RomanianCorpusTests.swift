import CryptoKit
import XCTest
@testable import Typebar

final class RomanianCorpusTests: XCTestCase {
  static let scales: [(language: TypingLanguage, hash: String)] = [
    (.romanian1k, "b7b685e85fd22cae3fa4ce2351c671b72d54b804a0274be18d3e7585fd87f947"),
    (.romanian5k, "05c7c8c4867a7af6d447ea51e03bd42127c2e7d35b7e8eee6fd01a017f50094e"),
    (.romanian10k, "ebb014ea9967a28ac31cc55854a68a2964041e7f40e1bfbfdd64c9018255f035"),
    (.romanian25k, "25f1488a0650490e25701757f8c40d678b262dcb63a91fc3713205a58383426f"),
    (.romanian50k, "36da864b637be519f82d6a93539dd588c1bf07213917e52d8a082bad3d8d170f"),
    (.romanian100k, "2a653b427afdec53b178eb27e4d08ed75f25eb6ea7122878f7401cfe4c407478"),
    (.romanian200k, "a96fd69ccafef50040ff5afa56e972de8658a685781b4b388b6e33141e82dfaf"),
  ]

  private func hash(_ words: [String]) -> String {
    SHA256.hash(data: Data((words.joined(separator: "\n") + "\n").utf8))
      .map { String(format: "%02x", $0) }.joined()
  }

  func testAllSevenNativeSelectionsMatchTheirSourceReproducedData() {
    for item in Self.scales {
      let words = item.language.ownedPracticeWords()
      XCTAssertEqual(hash(words), item.hash, item.language.rawValue)
      XCTAssertTrue(words.allSatisfy { $0 == $0.lowercased()
        && $0.allSatisfy { $0.isLetter || $0 == "-" } })
      for word in ["într-o", "s-a", "mi-a", "dă-mi", "n-am", "anti-", "cha-cha-cha-uri"] {
        XCTAssertTrue(words.contains(word), item.language.rawValue)
      }
    }
  }

  func testExistingBasicRomanianAndDefaultMixedChoiceRemainUnchanged() {
    let words = TypingLanguage.romanian.ownedPracticeWords()
    XCTAssertEqual(words.count, 30)
    XCTAssertEqual(hash(words), "f671c8647acd6dc2581e0c94eb6ce739c1d8f4f349435262d1cf2950c7717128")
    XCTAssertTrue(TypingLanguage.defaultMixedComponents.contains(.romanian))
    XCTAssertTrue(Self.scales.allSatisfy { !TypingLanguage.defaultMixedComponents.contains($0.language) })
  }

  func testRomanianCommaBelowAndCircumflexSupportLiteralLazyLatinNoSpacesAndRepeat() throws {
    for item in Self.scales {
      let lexicon = item.language.ownedPracticeLexicon()
      for (word, latin) in [("școală", "scoala"), ("țară", "tara"), ("cuvânt", "cuvant")] {
        let rank = try XCTUnwrap(lexicon.firstIndex(of: word))
        for modifiers: [TestModifier] in [[], [.noSpaces], [.lazyLatin], [.lazyLatin, .noSpaces]] {
          var session = TestSessionFactory.make(configuration: .words(1, language: item.language).with(modifiers: modifiers),
            nextRandomWordIndex: { rank })
          let expected = modifiers.contains(.lazyLatin) ? latin : word
          XCTAssertEqual(session.prompt, expected)
          session.insertBatch(expected, at: Date(timeIntervalSince1970: 10))
          XCTAssertEqual(session.outcome, .completed)
          XCTAssertEqual(session.errors, 0)
          XCTAssertEqual(session.repeatedAttempt().prompt, expected)
        }
      }
    }
  }

  func testAllLiteralHyphenFormsSupportActualInputDeletionNoSpacesAndRepeat() {
    for item in Self.scales {
      let lexicon = item.language.ownedPracticeLexicon()
      let ranks = lexicon.indices.filter { lexicon[$0].contains("-") }
      XCTAssertTrue(ranks.contains { lexicon[$0].hasSuffix("-") })
      XCTAssertTrue(ranks.contains { lexicon[$0].filter { $0 == "-" }.count == 3 })
      for rank in ranks {
        let word = lexicon[rank]
        for modifiers: [TestModifier] in [[], [.noSpaces]] {
          var session = TestSessionFactory.make(configuration: .words(1, language: item.language).with(modifiers: modifiers),
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

  func testEveryScaleLongestLiteralFieldSupportsBackwardsAndNoSpaces() throws {
    for item in Self.scales {
      let lexicon = item.language.ownedPracticeLexicon()
      let rank = try XCTUnwrap(lexicon.indices.max { lexicon[$0].count < lexicon[$1].count })
      let word = lexicon[rank]
      if item.language == .romanian200k {
        XCTAssertEqual(word, "pneumonoultramicroscopicsilicovolcaniconiozelor")
        XCTAssertEqual(word.count, 47)
      }
      for modifiers: [TestModifier] in [[], [.noSpaces], [.backwards], [.backwards, .noSpaces]] {
        let actualRank = modifiers.contains(.backwards) ? lexicon.count - 1 - rank : rank
        var session = TestSessionFactory.make(configuration: .words(1, language: item.language).with(modifiers: modifiers),
          nextRandomWordIndex: { actualRank })
        let expected = modifiers.contains(.backwards) ? String(word.reversed()) : word
        XCTAssertEqual(session.prompt, expected)
        session.insertBatch(expected, at: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(session.outcome, .completed)
        XCTAssertEqual(session.errors, 0)
        XCTAssertEqual(session.wordReviews.count, 1)
        XCTAssertEqual(session.repeatedAttempt().prompt, expected)
      }
    }
  }

  func testAllSevenChoicesContinueBeyondOneHundredWordsAndRepeatCapturedTargets() {
    for item in Self.scales {
      var rank = 100
      var session = TestSessionFactory.make(configuration: .words(153, language: item.language),
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

  func testHistoricalSyntheticResultsKeepCapturedPromptMetricsAndReplay() throws {
    for item in Self.scales {
      let prompt = "ș qromalaă- " + String(repeating: "k", count: 50)
      let result = CompletedTestResult(id: UUID(), configuration: .words(3, language: item.language), outcome: .completed,
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
  func testAllSevenScaleChoicesContainActualCommonRomanianWords() {
    for language: TypingLanguage in [.romanian1k, .romanian5k, .romanian10k,
      .romanian25k, .romanian50k, .romanian100k, .romanian200k] {
      let words = language.ownedPracticeLexicon()
      for word in ["și", "țară", "cuvânt"] {
        XCTAssertNotNil(words.firstIndex(of: word), "\(language.rawValue) is missing \(word)")
      }
    }
  }
}
