import CryptoKit
import XCTest
@testable import Typebar

final class PortugueseCorpusTests: XCTestCase {
  static let scales: [(language: TypingLanguage, hash: String)] = [
    (.portuguese1k, "e3f9296e5b671b9127a3586aaa4c2ad39c8a8696049d9fce1e2ce7ca417a602d"),
    (.portuguese3k, "a82e622f7a7a5e808400c213619bdea465b2c0c690d2065b6e87f3adaf2c2093"),
    (.portuguese5k, "dd71b9f65f0ffb65207a2f2d5d7b8acabce3f89912c6ca435a556978a3c09987"),
    (.portuguese320k, "1adb29311d8997310143b9d642f727dcb9684f8ca4f25a3f161ade8bb0de08e3"),
    (.portuguese550k, "6bd8bc1ff80c65b514193c8838f4f8af3fc731af7ddd9238f5ddfb43bf7aa4d0"),
  ]

  private func hash(_ words: [String]) -> String {
    SHA256.hash(data: Data((words.joined(separator: "\n") + "\n").utf8))
      .map { String(format: "%02x", $0) }.joined()
  }

  func testAllFiveNativeSelectionsMatchReproducedContentWithoutControlsOrDollarFiller() {
    for item in Self.scales {
      let words = item.language.ownedPracticeWords()
      XCTAssertEqual(hash(words), item.hash, item.language.rawValue)
      XCTAssertTrue(words.allSatisfy { !$0.contains("$")
        && !$0.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) } })
      if [.portuguese320k, .portuguese550k].contains(item.language) {
        XCTAssertTrue(words.contains("m²"))
        XCTAssertTrue(words.contains("m³"))
        XCTAssertTrue(words.contains("anti-"))
        XCTAssertTrue(words.contains("pré-"))
      }
    }
  }

  func testBasicAndAccentsOnlyPortugueseRemainByteIdentical() {
    for (language, count, expected): (TypingLanguage, Int, String) in [
      (.portuguese, 24, "1f3326b664e11f1d4a2c58dfda8dc53a279283bdadf012b5bec9bc4111ffa53d"),
      (.portugueseAccents, 67, "7b9406656ff32e493c90a942a5aefb7437f54edbf46d2e2180b359ee4c26ed4e"),
    ] {
      let words = language.ownedPracticeWords()
      XCTAssertEqual(words.count, count)
      XCTAssertEqual(hash(words), expected)
    }
    XCTAssertTrue(TypingLanguage.defaultMixedComponents.contains(.portuguese))
    XCTAssertTrue(Self.scales.allSatisfy { !TypingLanguage.defaultMixedComponents.contains($0.language) })
  }

  func testAccentsAndExistingLazyInputEligibilityReachActualFactoryAndRepeat() throws {
    for item in Self.scales {
      let lexicon = item.language.ownedPracticeLexicon()
      for (word, latin) in [("não", "nao"), ("coração", "coracao"), ("pessoa", "pessoa")] {
        let rank = try XCTUnwrap(lexicon.firstIndex(of: word))
        for modifiers: [TestModifier] in [[], [.noSpaces], [.lazyLatin], [.lazyLatin, .noSpaces]] {
          let configuration = TestConfiguration.words(1, language: item.language).with(modifiers: modifiers)
          let lazy = modifiers.contains(.lazyLatin) && item.language.supportsLazyLatinInput
          XCTAssertEqual(configuration.modifiers.contains(.lazyLatin), modifiers.contains(.lazyLatin))
          var session = TestSessionFactory.make(configuration: configuration, nextRandomWordIndex: { rank })
          XCTAssertEqual(session.configuration.modifiers.contains(.lazyLatin), lazy)
          let expected = lazy ? latin : word
          XCTAssertEqual(session.prompt, expected)
          session.insertBatch(expected, at: Date(timeIntervalSince1970: 10))
          XCTAssertEqual(session.outcome, .completed)
          XCTAssertEqual(session.errors, 0)
          XCTAssertEqual(session.repeatedAttempt().prompt, expected)
        }
      }
    }
  }

  func testAllLiteralPunctuationCandidatesSupportActualInputDeletionNoSpacesAndRepeat() {
    for item in Self.scales {
      let lexicon = item.language.ownedPracticeLexicon()
      let ranks = lexicon.indices.filter { lexicon[$0].contains(where: \.isPunctuation) }
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

  func testEveryMultiwordHeadwordSupportsFiniteTruncationNoSpacesAndRepeat() {
    for item in Self.scales {
      let lexicon = item.language.ownedPracticeLexicon()
      for rank in lexicon.indices.filter({ lexicon[$0].contains(" ") }) {
        let fields = lexicon[rank].split(separator: " ").map(String.init)
        for modifiers: [TestModifier] in [[], [.noSpaces]] {
          var session = TestSessionFactory.make(configuration: .words(fields.count, language: item.language).with(modifiers: modifiers),
            nextRandomWordIndex: { rank })
          let expected = fields.joined(separator: modifiers.isEmpty ? " " : "")
          XCTAssertEqual(session.prompt, expected)
          session.insertBatch(expected, at: Date(timeIntervalSince1970: 10))
          XCTAssertEqual(session.outcome, .completed)
          XCTAssertEqual(session.errors, 0)
          XCTAssertEqual(session.wordReviews.map(\.target), fields)
          XCTAssertEqual(session.repeatedAttempt().prompt, expected)
        }
        var truncated = TestSessionFactory.make(configuration: .words(1, language: item.language),
          nextRandomWordIndex: { rank })
        XCTAssertEqual(truncated.prompt, fields[0])
        truncated.insertBatch(fields[0], at: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(truncated.outcome, .completed)
        XCTAssertEqual(truncated.wordReviews.map(\.target), [fields[0]])
      }
    }
  }

  func testObservedNumericTokenAndDeclaredUnitExamplesAreActualSingleFields() throws {
    for (language, words): (TypingLanguage, [String]) in [
      (.portuguese5k, ["2d"]), (.portuguese320k, ["m²", "m³"]), (.portuguese550k, ["m²", "m³"]),
    ] {
      let lexicon = language.ownedPracticeLexicon()
      for word in words {
        let rank = try XCTUnwrap(lexicon.firstIndex(of: word))
        for modifiers: [TestModifier] in [[], [.noSpaces], [.backwards], [.backwards, .noSpaces]] {
          let draw = modifiers.contains(.backwards) ? lexicon.count - 1 - rank : rank
          var session = TestSessionFactory.make(configuration: .words(1, language: language).with(modifiers: modifiers),
            nextRandomWordIndex: { draw })
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

  func testLiteralProperNameUsesExistingAsciiCaseRule() throws {
    let lexicon = TypingLanguage.portuguese5k.ownedPracticeLexicon()
    let rank = try XCTUnwrap(lexicon.firstIndex(of: "Portugal"))
    var session = TestSessionFactory.make(configuration: .words(1, language: .portuguese5k),
      nextRandomWordIndex: { rank })
    XCTAssertEqual(session.prompt, "portugal")
    session.insertBatch("portugal", at: Date(timeIntervalSince1970: 10))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
    XCTAssertEqual(session.repeatedAttempt().prompt, "portugal")
  }

  func testRealLongestLetterAndPunctuationFieldsSupportBackwardsAndNoSpaces() throws {
    for item in Self.scales {
      let lexicon = item.language.ownedPracticeLexicon()
      let letter = try XCTUnwrap(lexicon.indices.filter { lexicon[$0].allSatisfy(\.isLetter) }
        .max { lexicon[$0].count < lexicon[$1].count })
      let punctuated = try XCTUnwrap(lexicon.indices.filter { lexicon[$0].contains(where: \.isPunctuation) }
        .max { lexicon[$0].count < lexicon[$1].count })
      for rank in [letter, punctuated] {
        let word = lexicon[rank]
        if [.portuguese320k, .portuguese550k].contains(item.language) {
          XCTAssertEqual(word.count, rank == letter ? 33 : 41)
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
  }

  func testAllFiveChoicesContinuePastOneHundredWordsAndRepeatCapturedTargets() {
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

  func testOldSyntheticPromptsSymbolsMetricsAndReplayAreNotRewritten() throws {
    for item in Self.scales {
      let prompt = "ǭǭ Qptmarbã7$ " + String(repeating: "t", count: 38)
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
  func testAllFiveScaleChoicesContainActualCommonPortugueseWords() {
    for language: TypingLanguage in [.portuguese1k, .portuguese3k, .portuguese5k,
      .portuguese320k, .portuguese550k] {
      let words = language.ownedPracticeLexicon()
      for word in ["não", "coração", "pessoa"] {
        XCTAssertNotNil(words.firstIndex(of: word), "\(language.rawValue) is missing \(word)")
      }
    }
  }
}
