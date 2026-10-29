import XCTest
@testable import Typebar

final class NorwegianBasicCorpusTests: XCTestCase {
  private let languages: [TypingLanguage] = [.norwegianBokmal, .norwegianNynorsk]

  func testDefaultWrittenStandardsHaveTheirSeparateFullCandidateBounds() {
    for (language, count, maximum): (TypingLanguage, Int, Int) in [
      (.norwegianBokmal, 200, 9), (.norwegianNynorsk, 250, 10),
    ] {
      let words = language.ownedPracticeWords()
      XCTAssertEqual(words.count, count)
      XCTAssertEqual(Set(words).count, count)
      XCTAssertEqual(words.map(\.count).min(), 1)
      XCTAssertEqual(words.map(\.count).max(), maximum)
      let alphabet = Set("abcdefghijklmnopqrstuvwxyzæøå")
      XCTAssertTrue(words.allSatisfy { !$0.isEmpty && $0.allSatisfy(alphabet.contains) })
      XCTAssertTrue(words.allSatisfy { $0 == $0.precomposedStringWithCanonicalMapping })
    }
  }

  func testEveryLiteralCandidateSupportsFactoryDeletionNoSpacesBackwardsAndRepeat() {
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
          if expected.count > 1 {
            session.insert(String(expected.prefix(1)), at: Date(timeIntervalSince1970: 2))
            session.deleteBackward(at: Date(timeIntervalSince1970: 3))
            XCTAssertEqual(session.typed, "")
          }
          session.insertBatch(expected, at: Date(timeIntervalSince1970: 10))
          XCTAssertEqual(session.outcome, .completed)
          XCTAssertEqual(session.errors, 0)
          XCTAssertEqual(session.repeatedAttempt().prompt, expected)
        }
      }
    }
  }

  func testNordicLettersAndEachStandardsOwnSpellingsReachLazyInput() throws {
    for language in languages {
      let pairs = language == .norwegianBokmal
        ? [("språk", "sprak"), ("lærer", "laerer"), ("øvelse", "ovelse")]
        : [("språk", "sprak"), ("lærar", "laerar"), ("øving", "oving")]
      for (word, latin) in pairs {
        let rank = try XCTUnwrap(language.ownedPracticeLexicon().firstIndex(of: word))
        for modifiers: [TestModifier] in [[.lazyLatin], [.lazyLatin, .noSpaces]] {
          var session = TestSessionFactory.make(configuration: .words(1, language: language).with(modifiers: modifiers),
            nextRandomWordIndex: { rank })
          XCTAssertEqual(session.prompt, latin)
          session.insertBatch(latin, at: Date(timeIntervalSince1970: 10))
          XCTAssertEqual(session.outcome, .completed)
          XCTAssertEqual(session.errors, 0)
          XCTAssertEqual(session.typed, latin)
          XCTAssertEqual(session.repeatedAttempt().prompt, latin)
        }
      }
    }
  }

  func testSourceRowsKeepSeparateStandardsAndPositiveWholeCounts() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Resources")
    let notice = try XCTUnwrap(CorpusLicenseNotice.norwegianBasic.read(resourceDirectory: root))
    XCTAssertTrue(notice.contains("CC BY 4.0")); XCTAssertTrue(notice.contains("CC0 1.0"))
    let rows = try String(contentsOf: root.appendingPathComponent("NorwegianBasicCorpusSources.txt"), encoding: .utf8)
      .split(separator: "\n").filter { !$0.hasPrefix("#") }
      .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    XCTAssertEqual(rows.count, 450)
    for (language, source) in [(TypingLanguage.norwegianBokmal, "nob"), (.norwegianNynorsk, "nno")] {
      let ownRows = rows.filter { $0.first == source }
      XCTAssertTrue(ownRows.allSatisfy { $0.count == 5 && $0.dropFirst(2).allSatisfy { Int($0) != nil } })
      let words = try ownRows.map { row -> String in
        guard row.count == 5 else { XCTFail("Incomplete source row"); return "" }
        XCTAssertGreaterThan(try XCTUnwrap(Int(row[4])), 0)
        return row[1]
      }
      XCTAssertEqual(words, language.ownedPracticeWords())
    }
  }

  func testHistoricalAuthoredWordsOutsideFreshBoundsRemainLiteralInStorageAndReplay() throws {
    for (language, prompt) in [(TypingLanguage.norwegianBokmal, "oppmerksomhet tålmodighet"),
                               (.norwegianNynorsk, "andning morgon")] {
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
