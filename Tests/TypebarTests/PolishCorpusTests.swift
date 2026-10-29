import CryptoKit
import XCTest
@testable import Typebar

final class PolishCorpusTests: XCTestCase {
  static let scales: [(language: TypingLanguage, hash: String)] = [
    (.polish2k, "439d2edb7220d5bdb9ccd69335256bd08ad55d4668ac72bf65a56f35b44698ca"),
    (.polish5k, "5a9447a72756917745904fa17212f480ed2266f8f613aea1146012ca56a5512c"),
    (.polish10k, "923e5458d5943ab7e53e1f617ae931db19dbc4809a8022c71c4b82d9c71ff685"),
    (.polish20k, "0415a5b8b7c47054cf890a964d7a9d2ddea694ce6bfdbb30320f48ccfa3431e8"),
    (.polish40k, "fa10d471c9d05a754ce77204f120f4f8eda239a1bf9e03d1428681d34538253d"),
    (.polish200k, "1f208ecf7022d1206f9d55408760fbdbcb528c990cd62929d94f118fb8842c50"),
  ]

  private func hash(_ words: [String]) -> String {
    SHA256.hash(data: Data((words.joined(separator: "\n") + "\n").utf8))
      .map { String(format: "%02x", $0) }.joined()
  }

  func testAllSixNativeSelectionsMatchSourceReproducedSpellings() {
    for item in Self.scales {
      let words = item.language.ownedPracticeWords()
      XCTAssertEqual(hash(words), item.hash, item.language.rawValue)
      XCTAssertTrue(words.allSatisfy { $0.allSatisfy { $0.isLetter || $0 == "." } })
      let abbreviations = words.filter { $0.contains(".") }
      XCTAssertEqual(Set(abbreviations), item.language == .polish2k ? Set(["np.", "m.in.", "itd."]) : [])
      XCTAssertEqual(abbreviations.reduce(0) { $0 + $1.filter { $0 == "." }.count },
        item.language == .polish2k ? 4 : 0)
    }
  }

  func testBasicPolishAndDefaultMixedEligibilityRemainUnchanged() {
    let words = TypingLanguage.polish.ownedPracticeWords()
    XCTAssertEqual(words.count, 24)
    XCTAssertEqual(hash(words), "d1ea1c50df63426e521fc1bb5bf5a4fc66697a72df13139f68cf5350b689e711")
    XCTAssertTrue(TypingLanguage.defaultMixedComponents.contains(.polish))
    XCTAssertTrue(Self.scales.allSatisfy { !TypingLanguage.defaultMixedComponents.contains($0.language) })
  }

  func testRealPolishAccentsReachLiteralLazyLatinNoSpacesAndRepeat() throws {
    for item in Self.scales {
      let lexicon = item.language.ownedPracticeLexicon()
      for (word, latin) in [("się", "sie"), ("człowiek", "czlowiek"), ("świat", "swiat")] {
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

  func testLiteralProperNamesRetainThePinnedAsciiCasePolicyAndUnicodeOnlyCapital() throws {
    for language: TypingLanguage in [.polish2k, .polish200k] {
      let lexicon = language.ownedPracticeLexicon()
      for (word, literal, latin) in [("Polska", "polska", "polska"),
        ("Kraków", "kraków", "krakow"), ("Łódź", "Łódź", "Lodz")] {
        let rank = try XCTUnwrap(lexicon.firstIndex(of: word))
        for modifiers: [TestModifier] in [[], [.noSpaces], [.lazyLatin], [.lazyLatin, .noSpaces]] {
          var session = TestSessionFactory.make(configuration: .words(1, language: language).with(modifiers: modifiers),
            nextRandomWordIndex: { rank })
          // The reference lowercases ASCII-capital-bearing words before lazy
          // input. Unicode-only Ł survives, then its lazy expansion keeps case.
          let expected = modifiers.contains(.lazyLatin) ? latin : literal
          XCTAssertEqual(session.prompt, expected)
          session.insertBatch(expected, at: Date(timeIntervalSince1970: 10))
          XCTAssertEqual(session.outcome, .completed)
          XCTAssertEqual(session.errors, 0)
          XCTAssertEqual(session.repeatedAttempt().prompt, expected)
        }
      }
    }
  }

  func testEachCasedPoolRetainsItsOwnLongestLiteralField() {
    for (language, maximum, word): (TypingLanguage, Int, String) in [
      (.polish2k, 10, "Internecie"), (.polish200k, 22, "Południowoafrykańczycy"),
    ] {
      let lexicon = language.ownedPracticeLexicon()
      XCTAssertEqual(lexicon.filter { $0.contains(where: \.isUppercase) }.map(\.count).max(), maximum)
      guard let rank = lexicon.firstIndex(of: word) else {
        XCTFail("Missing literal cased boundary: \(word)")
        continue
      }
      for modifiers: [TestModifier] in [[], [.noSpaces], [.backwards], [.backwards, .noSpaces]] {
        let draw = modifiers.contains(.backwards) ? lexicon.count - 1 - rank : rank
        var session = TestSessionFactory.make(configuration: .words(1, language: language).with(modifiers: modifiers),
          nextRandomWordIndex: { draw })
        let lowercase = word.lowercased()
        let expected = modifiers.contains(.backwards) ? String(lowercase.reversed()) : lowercase
        XCTAssertEqual(session.prompt, expected)
        session.insertBatch(expected, at: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(session.outcome, .completed)
        XCTAssertEqual(session.errors, 0)
        XCTAssertEqual(session.repeatedAttempt().prompt, expected)
      }
    }
  }

  func testAllThreePeriodAbbreviationsSupportInputDeletionNoSpacesBackwardsAndRepeat() throws {
    let lexicon = TypingLanguage.polish2k.ownedPracticeLexicon()
    for word in ["np.", "m.in.", "itd."] {
      let rank = try XCTUnwrap(lexicon.firstIndex(of: word))
      for modifiers: [TestModifier] in [[], [.noSpaces], [.backwards], [.backwards, .noSpaces]] {
        let draw = modifiers.contains(.backwards) ? lexicon.count - 1 - rank : rank
        var session = TestSessionFactory.make(configuration: .words(1, language: .polish2k).with(modifiers: modifiers),
          nextRandomWordIndex: { draw })
        let expected = modifiers.contains(.backwards) ? String(word.reversed()) : word
        XCTAssertEqual(session.prompt, expected)
        session.insertBatch(String(expected.dropLast()), at: Date(timeIntervalSince1970: 10))
        session.deleteBackward(at: Date(timeIntervalSince1970: 11))
        XCTAssertEqual(session.typed, String(expected.dropLast(2)))
        session.insertBatch(String(expected.suffix(2)), at: Date(timeIntervalSince1970: 12))
        XCTAssertEqual(session.outcome, .completed)
        XCTAssertEqual(session.errors, 0)
        XCTAssertEqual(session.wordReviews.count, 1)
        XCTAssertEqual(session.repeatedAttempt().prompt, expected)
      }
    }
  }

  func testEveryLongestLiteralWordSupportsBackwardsAndNoSpaces() throws {
    for item in Self.scales {
      let lexicon = item.language.ownedPracticeLexicon()
      let rank = try XCTUnwrap(lexicon.indices.max { lexicon[$0].count < lexicon[$1].count })
      let word = lexicon[rank]
      if item.language == .polish200k {
        XCTAssertEqual(word, "dziewięćdziesięciodziewięciolatce")
        XCTAssertEqual(word.count, 33)
      }
      for modifiers: [TestModifier] in [[], [.noSpaces], [.backwards], [.backwards, .noSpaces]] {
        let draw = modifiers.contains(.backwards) ? lexicon.count - 1 - rank : rank
        var session = TestSessionFactory.make(configuration: .words(1, language: item.language).with(modifiers: modifiers),
          nextRandomWordIndex: { draw })
        let expected = modifiers.contains(.backwards) ? String(word.reversed()) : word
        XCTAssertEqual(session.prompt, expected)
        session.insertBatch(expected, at: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(session.outcome, .completed)
        XCTAssertEqual(session.errors, 0)
        XCTAssertEqual(session.repeatedAttempt().prompt, expected)
      }
    }
  }

  func testAllSixChoicesContinueBeyondOneHundredWordsAndRepeatCapturedTargets() {
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

  func testHistoricalSyntheticResultsKeepTheirCapturedPromptMetricsAndReplay() throws {
    for item in Self.scales {
      let prompt = "ǫ Qpllasbł- " + String(repeating: "k", count: 33)
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
  func testAllSixScaleChoicesContainActualCommonPolishWords() {
    for language: TypingLanguage in [.polish2k, .polish5k, .polish10k, .polish20k, .polish40k, .polish200k] {
      let words = language.ownedPracticeLexicon()
      for word in ["jest", "się", "człowiek"] {
        XCTAssertNotNil(words.firstIndex(of: word), "\(language.rawValue) is missing \(word)")
      }
    }
  }
}
