import CryptoKit
import XCTest
@testable import Typebar

final class EnglishFiveLetterCorpusTests: XCTestCase {
  private let languages: [TypingLanguage] = [.englishFiveLetter, .englishFiveLetter1k]
  private let legacy = "amber quiet paper drift cabin cedar flint glass grain shore trail bloom crane field light ocean river stone cloud maple wheat slope spark frame brush clock prism sound green dream swift focus learn write clear paths hands lines shape steps".split(separator: " ").map(String.init)

  func testBothFiveLetterChoicesHaveFullIndependentCandidatePools() {
    let basic = TypingLanguage.englishFiveLetter.ownedPracticeWords()
    let large = TypingLanguage.englishFiveLetter1k.ownedPracticeWords()
    XCTAssertEqual(basic.count, 201)
    XCTAssertEqual(Set(basic).count, 201)
    XCTAssertEqual(large.count, 1_000)
    XCTAssertEqual(Set(large).count, 1_000)
    XCTAssertTrue(Set(basic).isSubset(of: Set(large)))
    let alphabet = Set("abcdefghijklmnopqrstuvwxyz")
    XCTAssertTrue((basic + large).allSatisfy { $0.count == 5 && $0.allSatisfy(alphabet.contains) })
    XCTAssertTrue(Set(legacy).isSubset(of: Set(basic)))
    for (words, expected) in [(basic, "5add56d4ed9ccd3fee407210a9eb7738dda650e822a3003d5bca099f7cf1b957"),
                              (large, "32011a773407ef7cc728597d1d2fef7105af92dce6e561c01a1fba026590a54e")] {
      let hash = SHA256.hash(data: Data((words.joined(separator: "\n") + "\n").utf8))
        .map { String(format: "%02x", $0) }.joined()
      XCTAssertEqual(hash, expected)
    }
  }

  func testEveryLiteralCandidateSupportsActualFactoryDeletionVariantsAndRepeat() {
    for language in languages {
      let words = language.ownedPracticeWords()
      for (index, word) in words.enumerated() {
        for modifiers: [TestModifier] in [[], [.noSpaces], [.backwards]] {
          let reverse = modifiers.contains(.backwards)
          let draw = reverse ? words.count - 1 - index : index
          let expected = reverse ? String(word.reversed()) : word
          var session = TestSessionFactory.make(configuration: .words(1, language: language).with(modifiers: modifiers),
            nextRandomWordIndex: { draw })
          XCTAssertEqual(session.prompt, expected)
          session.insert(String(expected.prefix(1)), at: Date(timeIntervalSince1970: 2))
          session.deleteBackward(at: Date(timeIntervalSince1970: 3))
          XCTAssertEqual(session.typed, "")
          session.insertBatch(expected, at: Date(timeIntervalSince1970: 10))
          XCTAssertEqual(session.outcome, .completed)
          XCTAssertEqual(session.errors, 0)
          XCTAssertEqual(session.repeatedAttempt().prompt, expected)
        }
      }
    }
  }

  func testNoSpaceRetainsTwoFiveLetterFieldsAndExistingLazyEligibility() {
    for language in languages {
      var draw = 0
      var session = TestSessionFactory.make(configuration: .words(2, language: language).with(modifiers: [.noSpaces]),
        nextRandomWordIndex: { defer { draw += 1 }; return draw })
      let expected = language.ownedPracticeWords().prefix(2).joined()
      XCTAssertEqual(session.prompt, expected)
      XCTAssertEqual(expected.count, 10)
      session.insertBatch(expected, at: Date(timeIntervalSince1970: 10))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.wordReviews.count, 2)
      XCTAssertEqual(session.errors, 0)
      let lazy = TestSessionFactory.make(configuration: .words(1, language: language).with(modifiers: [.lazyLatin]),
        nextRandomWordIndex: { 0 })
      XCTAssertEqual(lazy.configuration.modifiers.contains(.lazyLatin), language == .englishFiveLetter)
      XCTAssertEqual(lazy.prompt, language.ownedPracticeWords()[0])
    }
    XCTAssertTrue(TypingLanguage.defaultMixedComponents.contains(.englishFiveLetter))
    XCTAssertFalse(TypingLanguage.defaultMixedComponents.contains(.englishFiveLetter1k))
    XCTAssertTrue(TypingLanguage.mixableLanguages.contains(.englishFiveLetter1k))
  }

  func testWholeTokenSourceRowsAndFullNoticesRemainReadable() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Resources")
    let notice = try XCTUnwrap(CorpusLicenseNotice.englishFiveLetter.read(resourceDirectory: root))
    for credit in ["SCOWL", "wordfreq 3.1.1", LargeEnglishAttribution.sourceName,
                   LargeEnglishAttribution.copyright, "CC BY-SA 4.0", "A band is not a usage count."] {
      XCTAssertTrue(notice.contains(credit), credit)
    }
    let rows = try String(contentsOf: root.appendingPathComponent("EnglishFiveLetterCorpusSources.txt"), encoding: .utf8)
      .split(separator: "\n").filter { !$0.hasPrefix("#") }
      .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    XCTAssertEqual(rows.count, 1000)
    XCTAssertTrue(rows.allSatisfy { $0.count == 3 && $0.dropFirst().allSatisfy { Int($0) != nil } })
    let words = try rows.map { row -> String in
      guard row.count == 3 else { XCTFail("Incomplete source row"); return "" }
      XCTAssertTrue((0...95).contains(try XCTUnwrap(Int(row[1]))))
      XCTAssertGreaterThanOrEqual(try XCTUnwrap(Int(row[2])), 0)
      return row[0]
    }
    XCTAssertEqual(words, TypingLanguage.englishFiveLetter1k.ownedPracticeWords())
  }

  func testHistoricalAuthoredAndSyntheticCapturedPromptsStayLiteralInStorageAndReplay() throws {
    for (language, prompt) in [(TypingLanguage.englishFiveLetter, "amber quiet"),
                               (.englishFiveLetter1k, "qqqqq qzaaa")] {
      let result = CompletedTestResult(id: UUID(), configuration: .words(2, language: language), outcome: .completed,
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
