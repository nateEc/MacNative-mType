import CryptoKit
import XCTest
@testable import Typebar

final class UkrainianCorpusTests: XCTestCase {
  static let choices: [(TypingLanguage, Int)] = [
    (.ukrainian, 199), (.ukrainian1k, 1_000), (.ukrainian10k, 9_998), (.ukrainian50k, 49_991),
  ]
  private let hashes = ["28b34fa6d3f7f668f35903344be277114bc6f26b635540943411ab7c8444e37b",
    "1351d532f43780a71936fa9376e4f4a82f6635edc66d6cb4717d2d70d4e10e00",
    "83a0d65d93552dba877b7991c5f41db9ea4068a1fbd73d6454ae5140d814690e",
    "5b535a7733aa9417ec7ffaad719a21c0356c070d08e30a4baa50f6b1a61c0624"]

  func testCyrillicChoicesHaveLiteralModernUkrainianCandidates() {
    let alphabet = Set("абвгґдеєжзиіїйклмнопрстуфхцчшщьюяАБВГҐДЕЄЖЗИІЇЙКЛМНОПРСТУФХЦЧШЩЬЮЯ0123456789'-")
    var previous = Set("ранок вікно папір берег вітер вправа увага спокій ясно озеро вулиця стіл світло дорога терпіння хвилина місто дощ тиша напрямок зірка нотатка сад подих їжа єдність ґрунт".split(separator: " ").map(String.init))
    for (index, item) in Self.choices.enumerated() {
      let (language, count) = item
      let words = language.ownedPracticeWords()
      XCTAssertEqual(words.count, count, language.rawValue)
      XCTAssertEqual(Set(words).count, count, language.rawValue)
      XCTAssertTrue(words.allSatisfy { !$0.isEmpty && $0.allSatisfy(alphabet.contains) }, language.rawValue)
      XCTAssertTrue(words.allSatisfy { $0 == $0.precomposedStringWithCanonicalMapping })
      XCTAssertTrue(previous.isSubset(of: Set(words)))
      previous = Set(words)
      let hash = SHA256.hash(data: Data((words.joined(separator: "\n") + "\n").utf8)).map { String(format: "%02x", $0) }.joined()
      XCTAssertEqual(hash, hashes[index])
    }
  }

  private func checkInput(_ language: TypingLanguage, rank: Int, modifiers: [TestModifier],
    file: StaticString = #filePath, line: UInt = #line) {
    let lexicon = language.ownedPracticeLexicon()
    let reverse = modifiers.contains(.backwards)
    let draw = reverse ? lexicon.count - 1 - rank : rank
    let original = language.presentationText(lexicon[rank])
    let target = reverse ? String(original.reversed()) : original
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
    XCTAssertEqual(session.wordReviews.count, 1, file: file, line: line)
    XCTAssertEqual(session.repeatedAttempt().prompt, target, file: file, line: line)
  }

  func testEveryPunctuatedAndNumericFormSupportsActualDeletionVariantsAndRepeat() {
    for (language, _) in Self.choices.dropFirst() {
      let lexicon = language.ownedPracticeLexicon()
      for rank in lexicon.indices where lexicon[rank].contains(where: { $0.isPunctuation || $0.isNumber }) {
        for modifiers: [TestModifier] in [[], [.noSpaces], [.backwards], [.backwards, .noSpaces]] {
          checkInput(language, rank: rank, modifiers: modifiers)
        }
      }
    }
  }

  func testAllBasicWordsAndEachClassLengthBoundarySupportActualInput() {
    for rank in TypingLanguage.ukrainian.ownedPracticeLexicon().indices {
      checkInput(.ukrainian, rank: rank, modifiers: [])
    }
    for (language, _) in Self.choices {
      let lexicon = language.ownedPracticeLexicon()
      var groups: [String: [Int]] = [:]
      for rank in lexicon.indices { groups[category(lexicon[rank]), default: []].append(rank) }
      for ranks in groups.values {
        for rank in Set([ranks.min(by: { lexicon[$0].count < lexicon[$1].count })!,
                         ranks.max(by: { lexicon[$0].count < lexicon[$1].count })!]) {
          for modifiers: [TestModifier] in [[], [.noSpaces], [.backwards]] {
            checkInput(language, rank: rank, modifiers: modifiers)
          }
        }
      }
    }
  }

  private func category(_ word: String) -> String {
    let key = (word.contains(where: \.isUppercase) ? "C" : "")
      + (word.contains(where: \.isPunctuation) ? "P" : "")
      + (word.contains(where: \.isNumber) ? "N" : "")
    return key.isEmpty ? "L" : key
  }

  func testAllClassCountsAndLengthBoundsRemainPinnedWhileThe50kCombinationGapIsExplicit() {
    let specs: [[String: [Int]]] = [
      ["L": [199, 1, 12]],
      ["L": [985, 1, 16], "P": [15, 4, 18]],
      ["L": [9788, 1, 22], "P": [210, 4, 30]],
      ["L": [48004, 1, 23], "P": [1975, 4, 31], "C": [7, 2, 4], "PN": [2, 6, 7], "CP": [3, 7, 12]],
    ]
    for (index, item) in Self.choices.enumerated() {
      var groups: [String: [Int]] = [:]
      for word in item.0.ownedPracticeWords() { groups[category(word), default: []].append(word.count) }
      XCTAssertEqual(groups.mapValues { [$0.count, $0.min()!, $0.max()!] }, specs[index])
    }
    for (language, apostrophes, hyphens) in [(TypingLanguage.ukrainian1k, 13, 2), (.ukrainian10k, 130, 85), (.ukrainian50k, 660, 1370)] {
      let words = language.ownedPracticeWords()
      XCTAssertEqual(words.reduce(0) { $0 + $1.filter { $0 == "'" }.count }, apostrophes)
      XCTAssertEqual(words.reduce(0) { $0 + $1.filter { $0 == "-" }.count }, hyphens)
    }
    // Reference 50k totals are 661 / 1371. No source-supported double-apostrophe
    // plus hyphen token was found; its quota is explicitly not fabricated.
    XCTAssertFalse(TypingLanguage.ukrainian50k.ownedPracticeWords().contains {
      $0.filter { $0 == "'" }.count == 2 && $0.contains("-")
    })
  }

  func testOriginalFormTraceWholeObservationsAndFullNoticesAreReadable() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Resources")
    let notice = try XCTUnwrap(CorpusLicenseNotice.ukrainian.read(resourceDirectory: root))
    for text in ["English and Russian Wiktionary", "U+0301", "Creative Commons Attribution-ShareAlike 4.0", "wordfreq 3.1.1", "not full downloaded articles"] {
      XCTAssertTrue(notice.contains(text), text)
    }
    let rows = try String(contentsOf: root.appendingPathComponent("UkrainianCorpusSources.txt"), encoding: .utf8)
      .split(separator: "\n").filter { !$0.hasPrefix("#") }
      .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    XCTAssertEqual(rows.count, 49991)
    var mapped: [String] = [], traces: [String: [String]] = [:]
    for row in rows {
      guard row.count == 6 else { XCTFail("Incomplete adaptation trace"); continue }
      XCTAssertEqual(row[3].replacingOccurrences(of: "\u{0301}", with: ""), row[0])
      XCTAssertTrue(["dictionary", "ru-dictionary", "curated-text"].contains(row[1]))
      XCTAssertTrue(row[4...5].allSatisfy { $0.isEmpty || Int($0) != nil })
      mapped.append(row[0]); traces[row[0]] = row
    }
    XCTAssertEqual(mapped, TypingLanguage.ukrainian50k.ownedPracticeWords())
    XCTAssertEqual(rows.filter { $0[1] == "curated-text" }.count, 3)
    for word in TypingLanguage.ukrainian.ownedPracticeWords() {
      let row = try XCTUnwrap(traces[word]); XCTAssertEqual(row[3], word); XCTAssertFalse(row[4].isEmpty)
    }
  }

  func testOldStarterAndAllThreeSyntheticPromptsMetricsAndReplayRemainLiteral() throws {
    let prompts: [(TypingLanguage, String)] = [(.ukrainian, "ранок вікно"),
      (.ukrainian1k, "ꙮ " + String(repeating: "ꙑ", count: 18)),
      (.ukrainian10k, "ꙙ " + String(repeating: "ꙓ", count: 30)),
      (.ukrainian50k, "ꙛ " + String(repeating: "ꙕ", count: 31))]
    for (language, prompt) in prompts {
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
