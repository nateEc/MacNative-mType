import CryptoKit
import XCTest
@testable import Typebar

final class EnglishLargeCorpusTests: XCTestCase {
  func testAFirstLargeFactoryLookupUsesTheActualWords() {
    let began = ContinuousClock.now
    let session = TestSessionFactory.make(configuration: .words(1, language: .english450k),
      nextRandomWordIndex: { 0 })
    XCTAssertEqual(session.prompt, "the")
    print("English450k first native factory lookup: \(began.duration(to: .now))")
  }

  func testActualLargePoolUsesReproducedIndependentWords() {
    let words = TypingLanguage.english450k.ownedPracticeWords()
    XCTAssertEqual(words.count, 450_029)
    XCTAssertEqual(Set(words).count, 450_029)
    XCTAssertTrue(words.contains("the"))
    XCTAssertTrue(words.contains("people"))
    XCTAssertFalse(words.contains(String(repeating: "u", count: 31)))
    XCTAssertEqual(SHA256.hash(data: Data((words.joined(separator: "\n") + "\n").utf8))
      .map { String(format: "%02x", $0) }.joined(),
      "5ed42403f79db93db4db581fe3388d3992e7f648b630c8a14408a451176bbd59")
  }

  func testLargeChoiceKeepsItsCharacterPracticeShape() {
    let words = TypingLanguage.english450k.ownedPracticeWords()
    XCTAssertEqual(words.map(\.count).min(), 1)
    XCTAssertEqual(words.map(\.count).max(), 31)
    XCTAssertTrue(words.allSatisfy { $0.unicodeScalars.allSatisfy(\.isASCII) })
    XCTAssertEqual(words.filter { $0.contains(where: \.isUppercase) }.count, 33_021)
    XCTAssertEqual(words.filter { !$0.allSatisfy(\.isLetter) }.count, 176)
    XCTAssertTrue(words.contains { $0.contains("'") })
    XCTAssertTrue(words.contains { $0.contains("-") })
    XCTAssertTrue(words.contains { $0.hasSuffix(".") })
  }

  func testExistingSmallEnglishChoicesRemainByteIdentical() {
    let expected: [(TypingLanguage, String)] = [
      (.english, "b7d07c46c1aa84730b088a0bf0713688208d9367c803117865dd707624e3f60e"),
      (.english1k, "aa12bbbbf1228329b0340e783530e616321b3ad8b3c201b469c04d105def5362"),
      (.english5k, "d41944a639f6635a01408cf29c233a5cb749961cd07bd4c0fa782a5076400934"),
      (.english10k, "0a28013ab4dba0ad9bf0394810e217b87e8dd37c95b18eff9a77effcad1c2e96"),
      (.english25k, "d4693d1d418416e5d5594c041f76c2df54dcad0856754610e5feb33909c1b3e4"),
    ]
    for (language, hash) in expected {
      let body = language.ownedPracticeWords().joined(separator: "\n") + "\n"
      XCTAssertEqual(SHA256.hash(data: Data(body.utf8)).map { String(format: "%02x", $0) }.joined(), hash,
        language.rawValue)
    }
  }

  func testRealTailWordSupportsActualInputBackwardsAndNoSpaces() throws {
    let lexicon = TypingLanguage.english450k.ownedPracticeLexicon()
    XCTAssertEqual(lexicon[450_028], "zythum")
    for modifiers: [TestModifier] in [[], [.noSpaces], [.backwards], [.backwards, .noSpaces]] {
      // Backwards reverses the candidate pool before rank selection as well
      // as reversing the selected word's UTF-16 units.
      let rank = modifiers.contains(.backwards) ? 0 : 450_028
      var session = TestSessionFactory.make(configuration: .words(1, language: .english450k)
        .with(modifiers: modifiers), nextRandomWordIndex: { rank })
      let expected = modifiers.contains(.backwards) ? "muhtyz" : "zythum"
      XCTAssertEqual(session.prompt, expected)
      session.insertBatch(expected, at: Date(timeIntervalSince1970: 10))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.errors, 0)
      XCTAssertEqual(session.repeatedAttempt().prompt, expected)
    }
  }

  func testLiteralPunctuationAndCaseReachInputAndRepeat() throws {
    let lexicon = TypingLanguage.english450k.ownedPracticeLexicon()
    for (word, expected) in [("it's", "It's"), ("broad-minded", "Broad-minded"), ("e.g.", "E.g."), ("AND", "AND")] {
      let rank = try XCTUnwrap(lexicon.firstIndex(of: word))
      for modifiers: [TestModifier] in [[], [.noSpaces]] {
        var configuration = TestConfiguration.words(1, language: .english450k).with(modifiers: modifiers)
        configuration.contentOptions.includePunctuation = true
        var session = TestSessionFactory.make(configuration: configuration, nextRandomWordIndex: { rank },
          nextRandomContentUnit: { XCTFail("An English opening must not draw extra punctuation"); return 0.99 })
        XCTAssertEqual(session.prompt, expected)
        session.insertBatch(expected, at: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(session.outcome, .completed)
        XCTAssertEqual(session.errors, 0)
        XCTAssertEqual(session.repeatedAttempt().prompt, expected)
      }
    }
  }

  func testFiniteLargeAttemptContinuesAndRepeatsCapturedTargets() {
    var rank = 100_000
    var session = TestSessionFactory.make(configuration: .words(153, language: .english450k),
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
    XCTAssertEqual(repeated.prompt, opening)
    repeated.insert(opening, at: Date(timeIntervalSince1970: 12))
    repeated.insert(String(repeated.prompt.dropFirst(repeated.typed.count)), at: Date(timeIntervalSince1970: 13))
    XCTAssertEqual(repeated.outcome, .completed)
    XCTAssertEqual(repeated.prompt, session.prompt)
  }

  func testChoiceIdentityLocaleAndUnsupportedZipfRemainStable() throws {
    let language = TypingLanguage.english450k
    XCTAssertEqual(language.zipfFrequencySupport, .unsupported)
    XCTAssertEqual(language.speechLocaleIdentifier, "en-US")
    XCTAssertEqual(LivePracticeContentService.wikipediaLanguageCode(for: language), "en")
    let configuration = TestConfiguration.words(25, language: language)
    let preset = SavedTestPreset(configuration: configuration, quoteID: nil, customText: nil)
    XCTAssertEqual(try TestConfigurationShare.preset(from: TestConfigurationShare.link(for: preset)), preset)
    XCTAssertEqual(try JSONDecoder().decode(TestConfiguration.self,
      from: JSONEncoder().encode(configuration)), configuration)
  }

  func testOldSyntheticLargeHistoryKeepsItsPromptReplayAndMetrics() throws {
    let prompt = "b " + String(repeating: "u", count: 31) + " yucairnc"
    let configuration = TestConfiguration.words(3, language: .english450k)
    let result = CompletedTestResult(id: UUID(), configuration: configuration, outcome: .completed,
      startedAt: Date(timeIntervalSince1970: 1), finishedAt: Date(timeIntervalSince1970: 5),
      typedCharacterCount: prompt.count, correctCharacterCount: prompt.count, errorCount: 0,
      wpm: 30, rawWpm: 30, accuracy: 100, prompt: prompt,
      replayEvents: [.init(offset: 1, kind: .insert, text: prompt)])
    let restored = try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(result))
    XCTAssertEqual(restored, result)
    XCTAssertEqual(TestResultRecord(result: restored).portableResult, result)
    XCTAssertEqual(TypingReplay.typedText(events: restored.replayEvents, through: 1), prompt)
    XCTAssertEqual(TypingReplay.replayTargetFields(prompt: restored.prompt, configuration: configuration,
      targetWordDirectory: nil), ["b ", String(repeating: "u", count: 31) + " ", "yucairnc"])
  }
}
