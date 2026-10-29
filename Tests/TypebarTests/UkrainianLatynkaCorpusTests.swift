import CryptoKit
import XCTest
@testable import Typebar

final class UkrainianLatynkaCorpusTests: XCTestCase {
  static let choices: [(TypingLanguage, Int)] = [
    (.ukrainianLatin, 199), (.ukrainianLatynka1k, 1_000),
    (.ukrainianLatynka10k, 9_998), (.ukrainianLatynka50k, 49_991),
  ]

  func testEveryChoiceOffersRealWordsInTheDocumentedLatynkaOrthography() {
    for (language, count) in Self.choices {
      let words = language.ownedPracticeWords()
      XCTAssertEqual(words.count, count, language.rawValue)
      for word in ["bereğ", "ïža", "doŝ", "spokij", "jasno", "grunt"] {
        XCTAssertTrue(words.contains(word), "\(language.rawValue): \(word)")
      }
    }
  }

  private func category(_ word: String) -> String {
    let flags = (word.contains(where: \.isUppercase) ? "C" : "")
      + (word.contains(where: \.isPunctuation) ? "P" : "")
      + (word.contains(where: \.isNumber) ? "N" : "")
    return (flags.isEmpty ? "L" : flags) + (word.utf8.allSatisfy { $0 < 128 } ? "A" : "U")
  }

  func testAllPoolsRetainTheirNestedContentsClassBoundariesAndImmutablePins() {
    let shapes: [[String: [Int]]] = [
      ["LA": [143, 1, 13], "LU": [56, 1, 12]],
      ["LA": [696, 1, 16], "LU": [288, 1, 13], "PA": [16, 5, 18]],
      ["LA": [6616, 1, 20], "LU": [3168, 1, 22], "PA": [168, 4, 30], "PU": [46, 5, 21]],
      ["CA": [4, 2, 4], "CPA": [1, 12, 12], "CPU": [2, 7, 8], "CU": [3, 3, 3],
       "LA": [30098, 1, 23], "LU": [17881, 1, 23], "PA": [1216, 4, 31], "PNA": [2, 6, 7], "PU": [784, 5, 30]],
    ]
    let hashes = ["8eff07baf1b2222728f1011dbe898dbd972d84e9ab9cc2479e45f40b667d6fc6",
      "ff6dabf788f058491f9e02fde4c166b1d0fb0fab880a3bfc302f699149f6757d",
      "c928c3906e56656bff3161648019756bc9a64c737c8857cc35d1212cc9fe373c",
      "2a343a00de72aad0a3be1590341b9de96630d444d9736d9f78eb6b76306056a3"]
    var previous = Set<String>()
    for (index, choice) in Self.choices.enumerated() {
      let words = choice.0.ownedPracticeWords()
      XCTAssertEqual(Set(words).count, choice.1)
      XCTAssertTrue(previous.isSubset(of: Set(words)))
      previous = Set(words)
      var groups: [String: [Int]] = [:]
      for word in words { groups[category(word), default: []].append(word.count) }
      XCTAssertEqual(groups.mapValues { [$0.count, $0.min()!, $0.max()!] }, shapes[index])
      let hash = SHA256.hash(data: Data((words.joined(separator: "\n") + "\n").utf8))
        .map { String(format: "%02x", $0) }.joined()
      XCTAssertEqual(hash, hashes[index])
    }
    for character in "ïčğŝšž" {
      XCTAssertTrue(TypingLanguage.ukrainianLatin.ownedPracticeWords().contains { $0.contains(character) })
    }
  }

  private func checkInput(_ language: TypingLanguage, rank: Int, modifiers: [TestModifier],
    file: StaticString = #filePath, line: UInt = #line) {
    let lexicon = language.ownedPracticeLexicon()
    let reverse = modifiers.contains(.backwards)
    let draw = reverse ? lexicon.count - 1 - rank : rank
    let raw = language.presentationText(lexicon[rank])
    // Pinned words-generator.ts lowercases the whole ordinary candidate only
    // when /[A-Z]/ matches and punctuation is off. Corpus case stays intact.
    let original = raw.range(of: "[A-Z]", options: .regularExpression) == nil ? raw : raw.lowercased()
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

  func testEveryPunctuatedFormSupportsInputDeletionNoSpaceBackwardsAndRepeat() {
    for (language, _) in Self.choices {
      let lexicon = language.ownedPracticeLexicon()
      for rank in lexicon.indices where lexicon[rank].contains(where: { $0.isPunctuation || $0.isNumber }) {
        for modifiers: [TestModifier] in [[], [.noSpaces], [.backwards], [.backwards, .noSpaces]] {
          checkInput(language, rank: rank, modifiers: modifiers)
        }
      }
    }
  }

  func testAllBasicFormsAndEachClassLengthBoundarySupportActualInput() {
    for rank in TypingLanguage.ukrainianLatin.ownedPracticeLexicon().indices {
      checkInput(.ukrainianLatin, rank: rank, modifiers: [])
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

  func testAllTenUppercaseFormsFollowOrdinaryCaseRulesButCustomTextStaysLiteral() {
    let language = TypingLanguage.ukrainianLatynka50k
    let lexicon = language.ownedPracticeLexicon()
    let ranks = lexicon.indices.filter { lexicon[$0].contains(where: \.isUppercase) }
    XCTAssertEqual(ranks.count, 10)
    for rank in ranks {
      checkInput(language, rank: rank, modifiers: [])
      checkInput(language, rank: rank, modifiers: [.backwards, .noSpaces])
      let raw = lexicon[rank]
      let configuration = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
        difficulty: .normal, rules: .init(), language: language)
      var session = TestSessionFactory.make(configuration: configuration, customText: raw)
      XCTAssertEqual(session.prompt, raw)
      session.insertBatch(raw, at: Date(timeIntervalSince1970: 10))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.errors, 0)
      XCTAssertEqual(session.repeatedAttempt().prompt, raw)
    }
  }

  func testOriginalCyrillicFormsSourceFrequenciesAndFullNoticesRemainReadable() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Resources")
    let notice = try XCTUnwrap(CorpusLicenseNotice.ukrainianLatynka.read(resourceDirectory: root))
    for text in ["Vakulenko", "Latin practice form", "Cyrillic source", "Wiktionary", "wordfreq", "Creative Commons"] {
      XCTAssertTrue(notice.contains(text), text)
    }
    let rows = try String(contentsOf: root.appendingPathComponent("UkrainianLatynkaCorpusSources.txt"), encoding: .utf8)
      .split(separator: "\n").filter { !$0.hasPrefix("#") }
      .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    XCTAssertEqual(rows.count, 49991)
    var mapped: [String] = []
    for row in rows {
      guard row.count == 7 else { XCTFail("Incomplete adaptation trace"); continue }
      mapped.append(row[0])
      XCTAssertEqual(row[4].replacingOccurrences(of: "\u{0301}", with: ""), row[1])
      XCTAssertTrue(["dictionary", "ru-dictionary", "curated-text"].contains(row[2]))
      XCTAssertTrue(row[5...6].allSatisfy { $0.isEmpty || Int($0) != nil })
    }
    XCTAssertEqual(mapped, TypingLanguage.ukrainianLatynka50k.ownedPracticeWords())
    let boundary = try XCTUnwrap(rows.first { $0[0] == "administratyvno-terytorialjnymy" })
    XCTAssertEqual(boundary[1], "адміністративно-територіальними")
    XCTAssertEqual(boundary[2], "curated-text")
    XCTAssertTrue(boundary[3].contains("oldid=48586475"))
    XCTAssertEqual(boundary[4], boundary[1])
    XCTAssertEqual(boundary[5], "")
  }

  func testOldASCIIBasicAndAllThreeSyntheticPromptsRemainLiteralInArchivesAndReplay() throws {
    let prompts: [(TypingLanguage, String)] = [(.ukrainianLatin, "bereh yizha spokii"),
      (.ukrainianLatynka1k, "q " + String(repeating: "q", count: 18)),
      (.ukrainianLatynka10k, "q " + String(repeating: "q", count: 30)),
      (.ukrainianLatynka50k, "q " + String(repeating: "q", count: 31))]
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
