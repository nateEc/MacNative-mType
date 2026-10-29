import CryptoKit
import XCTest
@testable import Typebar

final class EsperantoCorpusTests: XCTestCase {
  static let scales: [(language: TypingLanguage, system: String, count: Int)] = [
    (.esperanto1k, "native", 1_000), (.esperanto10k, "native", 10_000),
    (.esperanto25k, "native", 24_998), (.esperanto36k, "native", 36_342),
    (.esperantoXSystem1k, "x", 999), (.esperantoXSystem10k, "x", 9_993),
    (.esperantoXSystem25k, "x", 24_970), (.esperantoXSystem36k, "x", 36_296),
    (.esperantoHSystem1k, "h", 999), (.esperantoHSystem10k, "h", 9_969),
    (.esperantoHSystem25k, "h", 24_922), (.esperantoHSystem36k, "h", 36_131),
  ]
  private let hashes: [TypingLanguage: String] = [
    .esperanto1k: "f908922896a841b7aa5d5fc0a300c660fc2e979c3a795721f30a20186776a678",
    .esperanto10k: "fa771b616b83bc8a67b1b817f376e5984e9af012e9c1ca1e1aaae21d2c79363f",
    .esperanto25k: "de4827041de2c52d036d613085d68ebffe3a013a8d52f74182f195d8140f030f",
    .esperanto36k: "896f30594fe50822350c8bcfe9b034f64281da67b7c822cfa7c9552b562fa6ba",
    .esperantoXSystem1k: "4e03d81937f4ca02c2254f52a099ec2644ada80ea5b119595890c163f54a97a8",
    .esperantoXSystem10k: "4494ec342373f6e852627c1fdc70499f32d2d43bf8e778a7506af9656eaf23b3",
    .esperantoXSystem25k: "40032e44a9aacc97fe2764c9c560f438815d9dbef2b0d49fb71adf2a672a4f41",
    .esperantoXSystem36k: "d360213bb5436d94bb6e77e5d0ccad256a42f46d7e81fddc606f3c318c907e78",
    .esperantoHSystem1k: "5e63ef501061b222581f4a1fc414e4f8be8f3ddbdff0f74859be6cb25534d7af",
    .esperantoHSystem10k: "76fe9564b173f7c3bec8de6b06b18112dce431a8c5c0cbda9a0e020b2378e9b8",
    .esperantoHSystem25k: "7169c822caf7c29e4845a48fde25e23f76b0293ab095e52c2c8f2d583f612e17",
    .esperantoHSystem36k: "a589240ce9d68dfba2e378570840c042bfaa49528f6d4f8b85be5c4c1e6a8992",
  ]

  private func hash(_ words: [String]) -> String {
    SHA256.hash(data: Data((words.joined(separator: "\n") + "\n").utf8))
      .map { String(format: "%02x", $0) }.joined()
  }

  func testEveryPublishedPoolMatchesTheReproducedDictionaryAndSpellingSelection() {
    for item in Self.scales {
      let words = item.language.ownedPracticeWords()
      XCTAssertEqual(words.count, item.count)
      XCTAssertEqual(Set(words).count, item.count)
      XCTAssertEqual(hash(words), hashes[item.language])
      XCTAssertTrue(words.allSatisfy { $0 == $0.precomposedStringWithCanonicalMapping
        && $0.unicodeScalars.allSatisfy { CharacterSet.lowercaseLetters.contains($0) } })
      if item.system != "native" { XCTAssertTrue(words.allSatisfy { $0.utf8.allSatisfy { (97...122).contains($0) } }) }
    }
  }

  func testThreeBasicPoolsAndDefaultMixedEligibilityStayUnchanged() {
    for (language, expected): (TypingLanguage, String) in [
      (.esperanto, "722ce89db0d90cef86683c51a943659d5750449218caec427151401147e7187a"),
      (.esperantoXSystem, "05f2ad1a1607d5dc8e9fe020c1e9fb3990a462072a8323af5e31c9912e840231"),
      (.esperantoHSystem, "3c362dd71179154b18b100b58f445416704d7a9143411270fad1108e0f903fc5"),
    ] {
      XCTAssertEqual(language.ownedPracticeWords().count, 35)
      XCTAssertEqual(hash(language.ownedPracticeWords()), expected)
    }
    XCTAssertTrue(Self.scales.allSatisfy { !TypingLanguage.defaultMixedComponents.contains($0.language) })
  }

  func testSixLettersUseActualFactoryInputDeletionLazyEligibilityNoSpacesAndRepeat() throws {
    for item in Self.scales {
      let lexicon = item.language.ownedPracticeLexicon()
      for (native, latin) in [("ĉielo", "cielo"), ("ĝardeno", "gardeno"), ("ĥoro", "horo"),
        ("ĵurnalo", "jurnalo"), ("ŝipo", "sipo"), ("aŭtuno", "autuno")] {
        let word = spelling(native, system: item.system)
        let rank = try XCTUnwrap(lexicon.firstIndex(of: word), item.language.rawValue)
        for modifiers: [TestModifier] in [[], [.noSpaces], [.lazyLatin], [.lazyLatin, .noSpaces]] {
          var session = TestSessionFactory.make(configuration: .words(1, language: item.language).with(modifiers: modifiers),
            nextRandomWordIndex: { rank })
          let lazy = modifiers.contains(.lazyLatin) && item.system == "native"
          let expected = lazy ? latin : word
          XCTAssertEqual(session.configuration.modifiers.contains(.lazyLatin), lazy)
          XCTAssertEqual(session.prompt, expected)
          session.insertBatch(String(expected.dropLast()), at: Date(timeIntervalSince1970: 10))
          session.deleteBackward(at: Date(timeIntervalSince1970: 11))
          XCTAssertEqual(session.typed, String(expected.dropLast(2)))
          session.insertBatch(String(expected.suffix(2)), at: Date(timeIntervalSince1970: 12))
          XCTAssertEqual(session.outcome, .completed)
          XCTAssertEqual(session.errors, 0)
          XCTAssertEqual(session.repeatedAttempt().prompt, expected)
        }
      }
    }
  }

  func testActualLongestFieldsHaveNoPaddingAndSupportBackwardsAndRepeat() throws {
    for item in Self.scales {
      let lexicon = item.language.ownedPracticeLexicon()
      let rank = try XCTUnwrap(lexicon.indices.max { lexicon[$0].count < lexicon[$1].count })
      let word = lexicon[rank]
      if item.language.rawValue.hasSuffix("36k") { XCTAssertEqual(word.count, 19) }
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

  func testEveryChoiceContinuesBeyondOneHundredWordsAndRepeatsItsCapturedTargets() {
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

  func testOldSyntheticPromptsFrozenMetricsAndReplayStayLiteral() throws {
    for item in Self.scales {
      let prompt = "q ĵqabaaa " + String(repeating: "q", count: 40)
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

  private func spelling(_ word: String, system: String) -> String {
    let native = Array("ĉĝĥĵŝŭ")
    let replacements = system == "x" ? ["cx", "gx", "hx", "jx", "sx", "ux"]
      : ["ch", "gh", "hh", "jh", "sh", "u"]
    guard system != "native" else { return word }
    return word.map { character in
      native.firstIndex(of: character).map { replacements[$0] } ?? String(character)
    }.joined()
  }

  func testAllTwelveChoicesContainActualCommonWordsInTheirOwnSpellingSystem() {
    for item in Self.scales {
      let words = item.language.ownedPracticeLexicon()
      for word in ["amiko", "ĉielo", "aŭtuno"] {
        XCTAssertTrue(words.contains(spelling(word, system: item.system)), item.language.rawValue + ": " + word)
      }
    }
  }
}
