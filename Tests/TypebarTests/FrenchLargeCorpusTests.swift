import CryptoKit
import XCTest
@testable import Typebar

final class FrenchLargeCorpusTests: XCTestCase {
  func testActualLargeFrenchPoolContainsRealCommonAndAccentedForms() {
    let words = TypingLanguage.french600k.ownedPracticeLexicon()
    for word in ["le", "être", "cœur"] {
      XCTAssertNotNil(words.firstIndex(of: word), "French 600k is missing \(word)")
    }
  }

  private func hash(_ words: [String]) -> String {
    SHA256.hash(data: Data((words.joined(separator: "\n") + "\n").utf8))
      .map { String(format: "%02x", $0) }.joined()
  }

  func testNativeLargeDataMatchesTheSourceReproducedSelectionAndCharacterPractice() {
    let words = TypingLanguage.french600k.ownedPracticeWords()
    XCTAssertEqual(words.count, 633_941)
    XCTAssertEqual(Set(words).count, 633_941)
    XCTAssertEqual(hash(words), "79b3b724dff36403f2a73b7f8434df803757cadebba39f835e29e659eb11996f")
    XCTAssertEqual(words.map(\.count).min(), 1)
    XCTAssertEqual(words.map(\.count).max(), 33)
    XCTAssertEqual(words.filter { $0.unicodeScalars.contains { !$0.isASCII } }.count, 323_380)
    XCTAssertTrue(words.allSatisfy { $0 == $0.lowercased() && !$0.contains(" ") })
    let punctuated = words.filter { $0.contains(where: \.isPunctuation) }
    XCTAssertEqual(punctuated.count, 34)
    XCTAssertTrue(punctuated.allSatisfy { $0.filter { $0 == "'" }.count == 1 })
    XCTAssertTrue(words.allSatisfy { $0.allSatisfy { $0.isLetter || $0 == "'" } })
  }

  func testExistingSmallFrenchDataRemainByteIdentical() {
    for (language, expected): (TypingLanguage, String) in [
      (.french, "46ffc446cfc460248ea8fae8ca6790eee06094a0e3e101a0dd308a7d92720390"),
      (.french1k, "d9fd31cd3db01863048d4581d53a9722a7ae43c790b16e8997efa65119325817"),
      (.french2k, "7c54c1c6a8c4f267cd23f1ffff3d0d588314fd043d4a8cbb2d0a13a41eb2dc0e"),
      (.french10k, "b2226fad15799531dd7d4e04dda3ce1283fb21896a799b5612be446c5d5ceb9e"),
    ] {
      XCTAssertEqual(hash(language.ownedPracticeWords()), expected, language.rawValue)
    }
  }

  func testAccentsLigaturesAndLazyLatinReachActualInputAndRepeat() throws {
    let lexicon = TypingLanguage.french600k.ownedPracticeLexicon()
    for (word, latin) in [("cœur", "coeur"), ("être", "etre"), ("école", "ecole")] {
      let rank = try XCTUnwrap(lexicon.firstIndex(of: word))
      for modifiers: [TestModifier] in [[], [.noSpaces], [.lazyLatin], [.lazyLatin, .noSpaces]] {
        var session = TestSessionFactory.make(configuration: .words(1, language: .french600k).with(modifiers: modifiers),
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

  func testAllThirtyFourObservedAsciiApostropheFormsAreTypeableWithoutTypographySubstitution() throws {
    let lexicon = TypingLanguage.french600k.ownedPracticeLexicon()
    let ranks = lexicon.indices.filter { lexicon[$0].contains("'") }
    XCTAssertEqual(ranks.count, 34)
    XCTAssertNotNil(lexicon.firstIndex(of: "aujourd'hui"))
    for rank in ranks {
      let word = lexicon[rank]
      for modifiers: [TestModifier] in [[], [.noSpaces]] {
        var session = TestSessionFactory.make(configuration: .words(1, language: .french600k).with(modifiers: modifiers),
          nextRandomWordIndex: { rank })
        XCTAssertEqual(session.prompt, word)
        XCTAssertFalse(session.prompt.contains("’"))
        session.insertBatch(word, at: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(session.outcome, .completed)
        XCTAssertEqual(session.errors, 0)
        XCTAssertEqual(session.repeatedAttempt().prompt, word)
      }
    }
  }

  func testRealThirtyThreeCharacterFormSupportsBackwardsNoSpacesAndRepeat() throws {
    let word = "cyclopentanoperhydrophénanthrènes"
    let lexicon = TypingLanguage.french600k.ownedPracticeLexicon()
    let rank = try XCTUnwrap(lexicon.firstIndex(of: word))
    XCTAssertEqual(word.count, 33)
    for modifiers: [TestModifier] in [[], [.noSpaces], [.backwards], [.backwards, .noSpaces]] {
      let actualRank = modifiers.contains(.backwards) ? lexicon.count - 1 - rank : rank
      var session = TestSessionFactory.make(configuration: .words(1, language: .french600k).with(modifiers: modifiers),
        nextRandomWordIndex: { actualRank })
      let expected = modifiers.contains(.backwards) ? String(word.reversed()) : word
      XCTAssertEqual(session.prompt, expected)
      session.insertBatch(expected, at: Date(timeIntervalSince1970: 10))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.errors, 0)
      XCTAssertEqual(session.repeatedAttempt().prompt, expected)
    }
  }

  func testLargeFiniteContinuationAndRepeatKeepCapturedRealTargets() {
    var rank = 100_000
    var session = TestSessionFactory.make(configuration: .words(153, language: .french600k),
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

  func testLegacySyntheticHistoryKeepsCapturedPromptAndFrozenMetrics() throws {
    let prompt = "ǿ " + String(repeating: "q", count: 33) + " qvfrcielcé"
    let result = CompletedTestResult(id: UUID(), configuration: .words(3, language: .french600k), outcome: .completed,
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
