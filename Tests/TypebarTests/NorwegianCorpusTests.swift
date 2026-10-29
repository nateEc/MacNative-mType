import CryptoKit
import XCTest
@testable import Typebar

final class NorwegianCorpusTests: XCTestCase {
  static let scales: [(language: TypingLanguage, source: String, count: Int)] = [
    (.norwegianBokmal1k, "nob", 1_000), (.norwegianBokmal5k, "nob", 5_000),
    (.norwegianBokmal10k, "nob", 10_000), (.norwegianBokmal150k, "nob", 142_938),
    (.norwegianBokmal600k, "nob", 614_970), (.norwegianNynorsk1k, "nno", 1_000),
    (.norwegianNynorsk5k, "nno", 5_000), (.norwegianNynorsk10k, "nno", 9_939),
    (.norwegianNynorsk100k, "nno", 104_745), (.norwegianNynorsk400k, "nno", 410_719),
  ]
  private let hashes: [TypingLanguage: String] = [
    .norwegianBokmal1k: "71c77536bb8cabae3c88fe7817f1a685128e46125de681c2720d432378965503",
    .norwegianBokmal5k: "38f046c5316414f64ee26dbb7be801e86ec99a71b6d2654a868bcf7a54774504",
    .norwegianBokmal10k: "26601ab18b0f0128dd1128c879484585e1b436c6018542dddc4f3a52fc93966c",
    .norwegianBokmal150k: "5659747f47fe0d973cff8c3f68f50b7e13e1543be0810bc5515a41ef9a661585",
    .norwegianBokmal600k: "02cd79baf255e3ac0eb6083e04913308f29e8748248f7a0b47800b803751c2cb",
    .norwegianNynorsk1k: "3dd6492ff1452021407e8bacd1e90aa6494bc2d729aba93a70347d7279654f6e",
    .norwegianNynorsk5k: "1b141756f4a003c72bdf14d14ca2f70e729fa8c3e51364c52d7d4dde1b6f6096",
    .norwegianNynorsk10k: "c8bece4c9860fd2866f097de136492f6a7f63195ee233960f12e238dc16bde43",
    .norwegianNynorsk100k: "87b730a75d488900c09616669d837a0da6f781cf2a831d8566b6b864ef439a8f",
    .norwegianNynorsk400k: "afc6cfa11c22854eb2369a99603791d2f18351b9378131f258469b36be05005b",
  ]

  private func hash(_ words: [String]) -> String {
    SHA256.hash(data: Data((words.joined(separator: "\n") + "\n").utf8))
      .map { String(format: "%02x", $0) }.joined()
  }

  private func presented(_ word: String) -> String {
    word.utf8.contains { (65...90).contains($0) } ? word.lowercased() : word
  }

  private func inputClass(_ word: String) -> String {
    let mask = (word.contains(where: \.isUppercase) ? "C" : "")
      + (word.contains(where: \.isPunctuation) ? "P" : "")
      + (word.contains(" ") ? "S" : "") + (word.contains(where: \.isNumber) ? "N" : "")
    return mask.isEmpty ? "L" : mask
  }

  func testAllTenNativePoolsMatchReproducedLiteralDataWithoutUnsafeCharacters() {
    for item in Self.scales {
      let words = item.language.ownedPracticeWords()
      XCTAssertEqual(words.count, item.count)
      XCTAssertEqual(Set(words).count, item.count)
      XCTAssertEqual(hash(words), hashes[item.language])
      XCTAssertTrue(words.allSatisfy { $0 == $0.precomposedStringWithCanonicalMapping
        && !$0.hasPrefix("-") && !$0.hasSuffix("-")
        && !$0.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) } })
    }
  }

  func testBasicWrittenStandardsKeepSeparatePinnedLiteralData() {
    for (language, count, expected): (TypingLanguage, Int, String) in [
      (.norwegianBokmal, 200, "ba611dc8083aa620a694367dd100485efa0a31ce27046a4de6f4f26412b0d72c"),
      (.norwegianNynorsk, 250, "06230a76ca39678135559e1645cddf377eb2caee9ca95eae9b40da6633e621b1"),
    ] {
      XCTAssertEqual(language.ownedPracticeWords().count, count)
      XCTAssertEqual(hash(language.ownedPracticeWords()), expected)
    }
    XCTAssertTrue(Self.scales.allSatisfy { !TypingLanguage.defaultMixedComponents.contains($0.language) })
  }

  func testNordicLettersReachActualFactoryLazyInputAndRepeatInBothStandards() throws {
    for item in Self.scales {
      let lexicon = item.language.ownedPracticeLexicon()
      let pairs = item.source == "nob" ? [("språk", "sprak"), ("lærer", "laerer"), ("øvelse", "ovelse")]
        : [("språk", "sprak"), ("lærar", "laerar"), ("øving", "oving")]
      for (word, latin) in pairs {
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

  func testEveryLiteralPunctuationEntrySupportsActualDeletionNoSpacesAndRepeat() {
    for item in Self.scales {
      let lexicon = item.language.ownedPracticeLexicon()
      for rank in lexicon.indices.filter({ lexicon[$0].contains(where: \.isPunctuation) }) {
        let word = presented(lexicon[rank]), fields = word.split(separator: " ").count
        for modifiers: [TestModifier] in [[], [.noSpaces]] {
          var session = TestSessionFactory.make(configuration: .words(fields, language: item.language).with(modifiers: modifiers),
            nextRandomWordIndex: { rank })
          let expected = modifiers.isEmpty ? word : word.replacingOccurrences(of: " ", with: "")
          XCTAssertEqual(session.prompt, expected)
          session.insertBatch(String(expected.dropLast()), at: Date(timeIntervalSince1970: 10))
          session.deleteBackward(at: Date(timeIntervalSince1970: 11))
          XCTAssertEqual(session.typed, String(expected.dropLast(2)))
          session.insertBatch(String(expected.suffix(2)), at: Date(timeIntervalSince1970: 12))
          XCTAssertEqual(session.outcome, .completed)
          XCTAssertEqual(session.errors, 0)
          XCTAssertEqual(session.wordReviews.count, fields)
          XCTAssertEqual(session.repeatedAttempt().prompt, expected)
        }
      }
    }
  }

  func testEveryLiteralNumericEntryRemainsOneFieldWithNumbersOptionOff() {
    for item in Self.scales {
      let lexicon = item.language.ownedPracticeLexicon()
      for rank in lexicon.indices.filter({ lexicon[$0].contains(where: \.isNumber) }) {
        let word = presented(lexicon[rank])
        XCTAssertFalse(word.contains(" "))
        for modifiers: [TestModifier] in [[], [.noSpaces], [.backwards], [.backwards, .noSpaces]] {
          let draw = modifiers.contains(.backwards) ? lexicon.count - 1 - rank : rank
          var session = TestSessionFactory.make(configuration: .words(1, language: item.language).with(modifiers: modifiers),
            nextRandomWordIndex: { draw })
          XCTAssertFalse(session.configuration.contentOptions.includeNumbers)
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
  }

  func testAllNynorskPhrasesRetainTheirFieldsAndFiniteTruncation() {
    let lexicon = TypingLanguage.norwegianNynorsk400k.ownedPracticeLexicon()
    let ranks = lexicon.indices.filter { lexicon[$0].contains(" ") }
    XCTAssertEqual(ranks.count, 19)
    for rank in ranks {
      let fields = presented(lexicon[rank]).split(separator: " ").map(String.init)
      for modifiers: [TestModifier] in [[], [.noSpaces]] {
        var session = TestSessionFactory.make(configuration: .words(fields.count, language: .norwegianNynorsk400k)
          .with(modifiers: modifiers), nextRandomWordIndex: { rank })
        let expected = fields.joined(separator: modifiers.isEmpty ? " " : "")
        XCTAssertEqual(session.prompt, expected)
        session.insertBatch(expected, at: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(session.outcome, .completed)
        XCTAssertEqual(session.errors, 0)
        XCTAssertEqual(session.wordReviews.count, fields.count)
        XCTAssertEqual(session.repeatedAttempt().prompt, expected)
      }
      XCTAssertEqual(TestSessionFactory.make(configuration: .words(1, language: .norwegianNynorsk400k),
        nextRandomWordIndex: { rank }).prompt, fields[0])
    }
  }

  func testPerClassLongestFieldsAndActualCaseRuleSupportInputBackwardsAndRepeat() throws {
    let critical: [TypingLanguage: [String: Int]] = [
      .norwegianBokmal10k: ["C": 8, "L": 28],
      .norwegianBokmal150k: ["CP": 17, "P": 26, "L": 30, "PN": 16],
      .norwegianBokmal600k: ["C": 23, "CP": 29, "P": 28, "L": 33, "CN": 3, "CPN": 17, "N": 3, "PN": 18],
      .norwegianNynorsk100k: ["C": 5, "CP": 19, "P": 29, "L": 28, "PN": 17],
      .norwegianNynorsk400k: ["C": 23, "CP": 22, "P": 31, "L": 31, "CN": 3, "CPN": 17,
        "N": 3, "PN": 19, "PS": 23, "S": 12],
    ]
    for (language, bounds) in critical {
      let lexicon = language.ownedPracticeLexicon()
      var longest: [String: Int] = [:]
      for rank in lexicon.indices {
        let key = inputClass(lexicon[rank])
        if longest[key].map({ lexicon[$0].count < lexicon[rank].count }) ?? true { longest[key] = rank }
      }
      for (key, length) in bounds {
        let rank = try XCTUnwrap(longest[key])
        let word = presented(lexicon[rank])
        XCTAssertEqual(word.count, length, language.rawValue + ": " + key)
        let variants: [[TestModifier]] = word.contains(" ") ? [[], [.noSpaces]]
          : [[], [.noSpaces], [.backwards], [.backwards, .noSpaces]]
        for modifiers in variants {
          let draw = modifiers.contains(.backwards) ? lexicon.count - 1 - rank : rank
          var session = TestSessionFactory.make(configuration: .words(word.split(separator: " ").count, language: language)
            .with(modifiers: modifiers), nextRandomWordIndex: { draw })
          let target = modifiers.contains(.backwards) ? String(word.reversed()) : word
          let expected = modifiers.contains(.noSpaces) ? target.replacingOccurrences(of: " ", with: "") : target
          XCTAssertEqual(session.prompt, expected)
          session.insertBatch(expected, at: Date(timeIntervalSince1970: 10))
          XCTAssertEqual(session.outcome, .completed)
          XCTAssertEqual(session.errors, 0)
          XCTAssertEqual(session.repeatedAttempt().prompt, expected)
        }
      }
    }
  }

  func testUnicodeOnlyCapitalsKeepTheirCaseWhileAsciiCapitalWordsLowercase() throws {
    for language: TypingLanguage in [.norwegianBokmal600k, .norwegianNynorsk400k] {
      let lexicon = language.ownedPracticeLexicon()
      let rank = try XCTUnwrap(lexicon.indices.first { lexicon[$0].contains(where: \.isUppercase)
        && !lexicon[$0].utf8.contains { (65...90).contains($0) } })
      XCTAssertEqual(TestSessionFactory.make(configuration: .words(1, language: language),
        nextRandomWordIndex: { rank }).prompt, lexicon[rank])
    }
  }

  func testAllTenChoicesContinueBeyondOneHundredWordsAndRepeatTheirCapturedTargets() {
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

  func testOldSyntheticPromptsFrozenMetricsAndReplayRemainLiteral() throws {
    for item in Self.scales {
      let prompt = "ǿ Qnbnordaaaaaø-7 " + String(repeating: "n", count: item.source == "nob" ? 33 : 31)
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

  func testAllTenChoicesContainActualNorwegianWordsFromTheirOwnWrittenStandard() {
    for item in Self.scales {
      let lexicon = item.language.ownedPracticeLexicon()
      for word in [item.source == "nob" ? "ikke" : "ikkje", "menneske", "språk"] {
        XCTAssertTrue(lexicon.contains(word), item.language.rawValue + ": " + word)
      }
    }
  }
}
