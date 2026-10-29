import CryptoKit
import XCTest
@testable import Typebar

final class SpanishLargeCorpusTests: XCTestCase {
  private func hash(_ words: [String]) -> String {
    SHA256.hash(data: Data((words.joined(separator: "\n") + "\n").utf8))
      .map { String(format: "%02x", $0) }.joined()
  }

  func testNativeSelectionHasReproducedContentAndPreservesCharacterCapabilities() {
    let words = TypingLanguage.spanish650k.ownedPracticeWords()
    XCTAssertEqual(words.count, 646_579)
    XCTAssertEqual(Set(words).count, words.count)
    XCTAssertEqual(hash(words), "7e514588116a662b6260954c1287a68b16a2c50cad1e0b2eb62657edb98989b1")
    XCTAssertEqual(words.map(\.count).min(), 1)
    XCTAssertEqual(words.map(\.count).max(), 26)
    XCTAssertEqual(words.filter { $0.allSatisfy(\.isLetter) }.map(\.count).max(), 24)
    XCTAssertEqual(words.filter { $0.contains(where: \.isUppercase) }.count, 3)
    XCTAssertEqual(words.filter { $0.unicodeScalars.contains { !$0.isASCII } }.count, 238_831)
    XCTAssertEqual(words.filter { $0.contains(" ") }.count, 162)
    XCTAssertEqual(words.filter { $0.contains(where: \.isPunctuation) }.count, 77)
    XCTAssertFalse(words.contains { $0.contains(where: \.isNumber) })
    XCTAssertEqual(Set(words.flatMap { $0.filter(\.isPunctuation) }), Set("-‒():/"))
  }

  func testSmallSpanishSelectionsRemainByteIdentical() {
    for (language, expected): (TypingLanguage, String) in [
      (.spanish, "045c77f0e18261722b37d2d529ff3f1dd02343075cb5e0f009679747c1d4efd1"),
      (.spanish1k, "19d1313ce798ffcc13d942604a8cb37779da08c0e57ea2303179a0b750d42a0c"),
      (.spanish10k, "46260083fb8ca03525017f56025c73ec2186b122ecd416ae7a7aa0af74b7f854"),
    ] {
      XCTAssertEqual(hash(language.ownedPracticeWords()), expected, language.rawValue)
    }
  }

  func testAccentedInputLazyLatinAndProperNamePolicyReachTheActualFactory() throws {
    let lexicon = TypingLanguage.spanish650k.ownedPracticeLexicon()
    // The pinned lazy-mode table retains Spanish ñ; it is not generic folding.
    for (word, latin) in [("niño", "niño"), ("corazón", "corazon"), ("México", "mexico")] {
      let rank = try XCTUnwrap(lexicon.firstIndex(of: word))
      for modifiers: [TestModifier] in [[], [.noSpaces], [.lazyLatin], [.lazyLatin, .noSpaces]] {
        var session = TestSessionFactory.make(configuration: .words(1, language: .spanish650k).with(modifiers: modifiers),
          nextRandomWordIndex: { rank })
        let expected = modifiers.contains(.lazyLatin) ? latin : word.lowercased()
        XCTAssertEqual(session.prompt, expected)
        session.insertBatch(expected, at: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(session.outcome, .completed)
        XCTAssertEqual(session.errors, 0)
        XCTAssertEqual(session.repeatedAttempt().prompt, expected)
      }
    }
  }

  func testEveryLiteralMultiwordCandidateSupportsFiniteBoundariesNoSpacesAndRepeat() {
    let lexicon = TypingLanguage.spanish650k.ownedPracticeLexicon()
    let ranks = lexicon.indices.filter { lexicon[$0].contains(" ") }
    XCTAssertEqual(ranks.count, 162)
    for rank in ranks {
      let fields = lexicon[rank].split(separator: " ").map(String.init)
      for modifiers: [TestModifier] in [[], [.noSpaces]] {
        var session = TestSessionFactory.make(configuration: .words(fields.count, language: .spanish650k).with(modifiers: modifiers),
          nextRandomWordIndex: { rank })
        let expected = fields.joined(separator: modifiers.isEmpty ? " " : "")
        XCTAssertEqual(session.prompt, expected)
        session.insertBatch(expected, at: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(session.outcome, .completed)
        XCTAssertEqual(session.errors, 0)
        XCTAssertEqual(session.wordReviews.map(\.target), fields)
        XCTAssertEqual(session.repeatedAttempt().prompt, expected)
      }
      var truncated = TestSessionFactory.make(configuration: .words(1, language: .spanish650k), nextRandomWordIndex: { rank })
      XCTAssertEqual(truncated.prompt, fields[0])
      truncated.insertBatch(fields[0], at: Date(timeIntervalSince1970: 10))
      XCTAssertEqual(truncated.outcome, .completed)
      XCTAssertEqual(truncated.wordReviews.map(\.target), [fields[0]])
    }
  }

  func testEveryPunctuationCandidateIncludingEditorialTypographySupportsDeletionAndRepeat() {
    let lexicon = TypingLanguage.spanish650k.ownedPracticeLexicon()
    let ranks = lexicon.indices.filter { lexicon[$0].contains(where: \.isPunctuation) }
    XCTAssertEqual(ranks.count, 77)
    for rank in ranks {
      let word = lexicon[rank]
      for modifiers: [TestModifier] in [[], [.noSpaces]] {
        var session = TestSessionFactory.make(configuration: .words(1, language: .spanish650k).with(modifiers: modifiers),
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

  func testTwentySixCharacterLabelIsOneActualFieldAndSupportsBackwards() throws {
    let word = "neurorretroalimentaciones:"
    XCTAssertEqual(word.count, 26)
    let lexicon = TypingLanguage.spanish650k.ownedPracticeLexicon()
    let rank = try XCTUnwrap(lexicon.firstIndex(of: word))
    for modifiers: [TestModifier] in [[], [.noSpaces], [.backwards], [.backwards, .noSpaces]] {
      let actualRank = modifiers.contains(.backwards) ? lexicon.count - 1 - rank : rank
      var session = TestSessionFactory.make(configuration: .words(1, language: .spanish650k).with(modifiers: modifiers),
        nextRandomWordIndex: { actualRank })
      let expected = modifiers.contains(.backwards) ? String(word.reversed()) : word
      XCTAssertEqual(session.prompt, expected)
      session.insertBatch(expected, at: Date(timeIntervalSince1970: 10))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.wordReviews.count, 1)
      XCTAssertEqual(session.repeatedAttempt().prompt, expected)
    }
  }

  func testLongFiniteContinuationAndRepeatKeepCapturedTargets() {
    var rank = 100_000
    var session = TestSessionFactory.make(configuration: .words(153, language: .spanish650k),
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

  func testHistoricalSyntheticResultsKeepTheirCapturedPromptMetricsAndReplay() throws {
    let prompt = "á " + String(repeating: "v", count: 26) + " qzvlunañ-"
    let result = CompletedTestResult(id: UUID(), configuration: .words(3, language: .spanish650k), outcome: .completed,
      startedAt: Date(timeIntervalSince1970: 1), finishedAt: Date(timeIntervalSince1970: 5),
      typedCharacterCount: prompt.count, correctCharacterCount: prompt.count, errorCount: 0,
      wpm: 30, rawWpm: 30, accuracy: 100, prompt: prompt,
      replayEvents: [.init(offset: 1, kind: .insert, text: prompt)])
    let restored = try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(result))
    XCTAssertEqual(restored, result)
    XCTAssertEqual(TestResultRecord(result: restored).portableResult, result)
    XCTAssertEqual(TypingReplay.typedText(events: restored.replayEvents, through: 1), prompt)
  }
  func testLargeSpanishPoolContainsActualCommonAndAccentedWords() {
    let words = TypingLanguage.spanish650k.ownedPracticeLexicon()
    for word in ["el", "niño", "corazón"] {
      XCTAssertNotNil(words.firstIndex(of: word), "Spanish 650k is missing \(word)")
    }
  }
}
