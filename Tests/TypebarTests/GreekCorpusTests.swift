import CryptoKit
import XCTest
@testable import Typebar

final class GreekCorpusTests: XCTestCase {
  static let choices: [(TypingLanguage, Int)] = [
    (.greek, 209), (.greek1k, 993), (.greek5k, 4_963),
    (.greek10k, 9_936), (.greek25k, 24_836),
  ]

  func testEveryModernGreekChoiceHasTheRequiredRealModernAlphabetAndSize() {
    let alphabet = Set("αβγδεζηθικλμνξοπρςστυφχψωάέήίόύώΐϊϋ")
    for (language, count) in Self.choices {
      let words = language.ownedPracticeWords()
      XCTAssertEqual(words.count, count, language.rawValue)
      XCTAssertEqual(Set(words).count, count, language.rawValue)
      XCTAssertTrue(words.allSatisfy { !$0.isEmpty && $0.allSatisfy(alphabet.contains) }, language.rawValue)
    }
  }

  func testLiteralNestedPoolsKeepAllCharacterAndLengthBoundariesAndImmutablePins() {
    let hashes = ["b27bc21d93504f5b6e85782aefd8f7b40df76810230748c540e93eaeaabb2e70",
      "e95c78be8ca89cd1f7095a57cf743f076f76b785a4d678182d2f30979a36bdc8",
      "98bf323de9504b0788f99b3b059714f20b909872003aed458a755f1192724a39",
      "2bb83ffcc7cdf25137fd9bea5ce88bd841f8f86263b55f66aebf7b1460f84701",
      "8de592ff5c356f305a527d39a46402766d7e396ee7ec46f299e056adfc74f896"]
    let base = Set("αβγδεζηθικλμνξοπρςστυφχψωάέήίόύώ")
    var previous = Set("πρωί παράθυρο χαρτί ακτή άνεμος άσκηση προσοχή ήρεμος καθαρός λίμνη δρόμος τραπέζι φως ταξίδι υπομονή στιγμή πόλη βροχή σιωπή κατεύθυνση αστέρι σημείωση κήπος ανάσα μικρός χρόνος άνοιξη νησί φίλος βιβλίο".split(separator: " ").map(String.init))
    for (index, choice) in Self.choices.enumerated() {
      let words = choice.0.ownedPracticeWords()
      XCTAssertTrue(previous.isSubset(of: Set(words)))
      previous = Set(words)
      XCTAssertEqual(words.map(\.count).min(), 1)
      XCTAssertEqual(words.map(\.count).max(), [12, 16, 20, 21, 21][index])
      XCTAssertTrue(words.allSatisfy { $0 == $0.precomposedStringWithCanonicalMapping })
      let alphabet = index == 0 ? base : base.union(Set(index == 1 ? "ϊϋ" : "ΐϊϋ"))
      XCTAssertEqual(Set(words.joined()), alphabet)
      let hash = SHA256.hash(data: Data((words.joined(separator: "\n") + "\n").utf8))
        .map { String(format: "%02x", $0) }.joined()
      XCTAssertEqual(hash, hashes[index])
    }
  }

  private func checkInput(_ language: TypingLanguage, rank: Int, modifiers: [TestModifier],
    file: StaticString = #filePath, line: UInt = #line) {
    let lexicon = language.ownedPracticeLexicon()
    let reverse = modifiers.contains(.backwards)
    let original = modifiers.contains(.lazyLatin)
      ? TypingTextNormalizer.lazyLatin(lexicon[rank], language: language) : lexicon[rank]
    let target = reverse ? String(original.reversed()) : original
    let draw = reverse ? lexicon.count - 1 - rank : rank
    var session = TestSessionFactory.make(configuration: .words(1, language: language).with(modifiers: modifiers),
      nextRandomWordIndex: { draw })
    XCTAssertEqual(session.prompt, target, file: file, line: line)
    if target.count > 1 {
      session.insert(String(target.prefix(1)), at: Date(timeIntervalSince1970: 2))
      session.deleteBackward(at: Date(timeIntervalSince1970: 3))
      XCTAssertEqual(session.typed, "", file: file, line: line)
    }
    session.insertBatch(target, at: Date(timeIntervalSince1970: 10))
    XCTAssertEqual(session.outcome, .completed, file: file, line: line)
    XCTAssertEqual(session.errors, 0, file: file, line: line)
    XCTAssertEqual(session.repeatedAttempt().prompt, target, file: file, line: line)
  }

  func testAllBasicWordsSupportRealInputDeletionAndRepeat() {
    for rank in TypingLanguage.greek.ownedPracticeLexicon().indices {
      checkInput(.greek, rank: rank, modifiers: [])
    }
  }

  func testEveryCharacterAndLengthBoundarySupportsNoSpaceBackwardsAndLazyInput() throws {
    for (language, _) in Self.choices {
      let lexicon = language.ownedPracticeLexicon()
      var ranks = Set([try XCTUnwrap(lexicon.indices.min(by: { lexicon[$0].count < lexicon[$1].count })),
                       try XCTUnwrap(lexicon.indices.max(by: { lexicon[$0].count < lexicon[$1].count }))])
      for character in Set(lexicon.materialized().joined()) {
        ranks.insert(try XCTUnwrap(lexicon.indices.first { lexicon[$0].contains(character) }))
      }
      for rank in ranks {
        for modifiers: [TestModifier] in [[], [.noSpaces], [.backwards], [.noSpaces, .backwards], [.lazyLatin]] {
          checkInput(language, rank: rank, modifiers: modifiers)
        }
      }
    }
  }

  func testOriginalDictionaryFormsWholeObservationsAndFullCreditsRemainReadable() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Resources")
    let notice = try XCTUnwrap(CorpusLicenseNotice.greek.read(resourceDirectory: root))
    for text in ["English Wiktionary", "Kaikki.org", "wordfreq", "casefold", "Creative Commons"] {
      XCTAssertTrue(notice.contains(text), text)
    }
    let rows = try String(contentsOf: root.appendingPathComponent("GreekCorpusSources.txt"), encoding: .utf8)
      .split(separator: "\n").filter { !$0.hasPrefix("#") }
      .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    XCTAssertEqual(rows.count, 24836)
    var mapped: [String] = []
    for row in rows {
      guard row.count == 3 else { XCTFail("Incomplete literal source trace"); continue }
      mapped.append(row[0])
      XCTAssertFalse(row[1].isEmpty)
      XCTAssertNotNil(Int(row[2]))
    }
    XCTAssertEqual(mapped, TypingLanguage.greek25k.ownedPracticeWords())
    XCTAssertTrue(mapped.contains("φως"))
    XCTAssertFalse(mapped.contains("φωσ"))
  }

  func testExplicitlyRejectedSourcePairsNeverEnterOrdinaryPracticePools() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Resources")
    let rows = try String(contentsOf: root.appendingPathComponent("GreekCorpusSources.txt"), encoding: .utf8)
      .split(separator: "\n").filter { !$0.hasPrefix("#") }
      .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    for (word, title) in [("βράδι", "βράδυ"), ("οχι", "οχι"), ("παππά", "παππάς"), ("παππάς", "παππάς")] {
      XCTAssertFalse(rows.contains { $0[0] == word && $0[1] == title }, "Rejected source pair: \(word) / \(title)")
    }
  }

  func testOldBasicAndAllFourSyntheticPromptsRemainLiteralThroughArchivesAndReplay() throws {
    for (index, choice) in Self.choices.enumerated() {
      let prompt = index == 0 ? "πρωί παράθυρο" : "ϙ " + String(repeating: "ϙ", count: [12, 16, 20, 21, 21][index])
      let result = CompletedTestResult(id: UUID(), configuration: .words(2, language: choice.0), outcome: .completed,
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
