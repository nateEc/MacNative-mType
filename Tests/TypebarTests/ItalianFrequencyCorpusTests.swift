import XCTest
import CryptoKit
@testable import Typebar

final class ItalianFrequencyCorpusTests: XCTestCase {
  private let languages: [TypingLanguage] = [.italian1k, .italian7k]

  func testBasicItalianPoolKeepsItsExistingData() {
    let body = TypingLanguage.italian.ownedPracticeWords().joined(separator: "\n") + "\n"
    XCTAssertEqual(SHA256.hash(data: Data(body.utf8)).map { String(format: "%02x", $0) }.joined(),
      "a62740b4e493c568d143e5b4f4e8b1aa18eb7b820e13be3ddc1a38a9365dd954")
  }

  func testScalePoolsContainObservedItalianInsteadOfSyntheticMarkers() {
    for (language, (count, maximum)) in zip(languages, zip([1_159, 7_154], [14, 18])) {
      let words = language.ownedPracticeWords()
      XCTAssertEqual(words.count, count); XCTAssertEqual(Set(words).count, count)
      XCTAssertEqual(Array(words.prefix(3)), ["di", "e", "che"])
      for word in ["grazie", "perché", "ciao", "famiglia", "Italia", "Roma"] {
        XCTAssertTrue(words.contains(word), "\(language) \(word)")
      }
      XCTAssertTrue(words.allSatisfy { !$0.isEmpty && $0.count <= maximum })
      XCTAssertFalse(words.contains { $0.lowercased().hasPrefix("qit") || $0.hasPrefix("ìq") })
      let expected = language == .italian1k
        ? "3147482398398803f2f7416671cc5d7a931fbb2d428a3a89711424424c52257f"
        : "75bcab23bddf0011805707c681ca1152194b5d88321cbd7a7f6fdf07888d1dfd"
      XCTAssertEqual(SHA256.hash(data: Data((words.joined(separator: "\n") + "\n").utf8))
        .map { String(format: "%02x", $0) }.joined(), expected)
    }
  }

  func testItalianScaleSelectionRespectsEachLengthBound() {
    let larger = TypingLanguage.italian7k.ownedPracticeWords()
    XCTAssertEqual(TypingLanguage.italian1k.ownedPracticeWords(), Array(larger.filter { $0.count <= 14 }.prefix(1_159)))
  }

  func testObservedAccentWordIsSelectableAndTypedInOrdinaryAndNoSpaceModes() throws {
    for language in languages {
      let rank = try XCTUnwrap(language.ownedPracticeLexicon().firstIndex(of: "perché"))
      for modifiers: [TestModifier] in [[], [.noSpaces]] {
        var session = TestSessionFactory.make(configuration: .words(1, language: language).with(modifiers: modifiers),
          nextRandomWordIndex: { rank })
        XCTAssertEqual(session.prompt, "perché")
        session.insertBatch("perché", at: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(session.outcome, .completed); XCTAssertEqual(session.errors, 0)
        XCTAssertEqual(session.repeatedAttempt().prompt, "perché")
      }
    }
  }

  func testLongAttemptGrowsAndRepeatsItsCapturedRealTargets() {
    var rank = 2_000
    var session = TestSessionFactory.make(configuration: .words(153, language: .italian7k),
      nextRandomWordIndex: { defer { rank += 1 }; return rank % 7_154 })
    let opening = session.prompt
    session.insert(opening, at: Date(timeIntervalSince1970: 10))
    XCTAssertEqual(session.completedWordCount, 100); XCTAssertEqual(session.outcome, .active)
    session.insert(String(session.prompt.dropFirst(session.typed.count)), at: Date(timeIntervalSince1970: 11))
    XCTAssertEqual(session.outcome, .completed); XCTAssertEqual(session.completedWordCount, 153); XCTAssertEqual(session.errors, 0)
    var repeated = session.repeatedAttempt()
    XCTAssertEqual(repeated.prompt, opening)
    repeated.insert(opening, at: Date(timeIntervalSince1970: 12))
    repeated.insert(String(repeated.prompt.dropFirst(repeated.typed.count)), at: Date(timeIntervalSince1970: 13))
    XCTAssertEqual(repeated.outcome, .completed); XCTAssertEqual(repeated.prompt, session.prompt)
  }

  func testEditedProperNameCanBeSelectedWithPunctuationAndReplayed() throws {
    for language in languages {
      let rank = try XCTUnwrap(language.ownedPracticeLexicon().firstIndex(of: "Italia"))
      var config = TestConfiguration.words(1, language: language)
      config.contentOptions.includePunctuation = true
      var session = TestSessionFactory.make(configuration: config, nextRandomWordIndex: { rank }, nextRandomContentUnit: { 0.99 })
      XCTAssertTrue(session.prompt.contains("Italia"))
      let prompt = session.prompt
      session.insertBatch(prompt, at: Date(timeIntervalSince1970: 10))
      XCTAssertEqual(session.outcome, .completed); XCTAssertEqual(session.errors, 0)
      XCTAssertEqual(session.repeatedAttempt().prompt, prompt)
    }
  }

  func testOldSyntheticResultPromptsAndMetricsSurvivePersistence() throws {
    for (language, length) in zip(languages, [14, 18]) {
      let prompt = "q " + String(repeating: "q", count: length)
      let result = CompletedTestResult(id: UUID(), configuration: .words(2, language: language), outcome: .completed,
        startedAt: Date(timeIntervalSince1970: 1), finishedAt: Date(timeIntervalSince1970: 5),
        typedCharacterCount: prompt.count, correctCharacterCount: prompt.count, errorCount: 0,
        wpm: 30, rawWpm: 30, accuracy: 100, prompt: prompt, replayEvents: [.init(offset: 1, kind: .insert, text: prompt)])
      let restored = try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(result))
      XCTAssertEqual(restored, result)
      XCTAssertEqual(TestResultRecord(result: result).portableResult, result)
      XCTAssertEqual(TypingReplay.typedText(events: restored.replayEvents, through: 1), prompt)
    }
  }
}
