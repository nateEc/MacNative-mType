import XCTest
@testable import Typebar

final class RussianBasicCorpusTests: XCTestCase {
  private let legacy = "утро окно бумага берег ветер практика внимание тихо ясно озеро улица стол свет дорога терпение минута город дождь спокойно направление звезда записка сад дыхание".split(separator: " ").map(String.init)

  func testDefaultRussianHasTwoHundredLiteralCandidatesAndBothLengthBoundaries() {
    let words = TypingLanguage.russian.ownedPracticeWords()
    XCTAssertEqual(words.count, 200)
    XCTAssertEqual(Set(words).count, 200)
    XCTAssertEqual(words.map(\.count).min(), 1)
    XCTAssertEqual(words.map(\.count).max(), 12)
    let alphabet = Set("абвгдеёжзийклмнопрстуфхцчшщъыьэюя")
    XCTAssertTrue(words.allSatisfy { !$0.isEmpty && $0.allSatisfy(alphabet.contains) })
    XCTAssertTrue(words.allSatisfy { $0 == $0.precomposedStringWithCanonicalMapping })
    XCTAssertTrue(Set(legacy).isSubset(of: Set(words)))
  }

  func testEveryBasicCandidateSupportsActualFactoryDeletionAndRepeat() {
    let words = TypingLanguage.russian.ownedPracticeWords()
    for (index, word) in words.enumerated() {
      for modifiers: [TestModifier] in [[], [.noSpaces], [.backwards]] {
        let backwards = modifiers.contains(.backwards)
        let draw = backwards ? words.count - 1 - index : index
        let expected = backwards ? String(word.reversed()) : word
        var session = TestSessionFactory.make(configuration: .words(1, language: .russian).with(modifiers: modifiers),
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
    XCTAssertGreaterThan(words.filter { !legacy.contains($0) }.count, 150)
  }

  func testBasicNoticeAndPerWordProvenanceAreReadable() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Resources")
    let notice = try XCTUnwrap(CorpusLicenseNotice.russianBasic.read(resourceDirectory: root))
    XCTAssertTrue(notice.contains("CC BY-SA 4.0"))
    XCTAssertTrue(notice.contains("wordfreq 3.1.1"))
    let rows = try String(contentsOf: root.appendingPathComponent("RussianBasicCorpusSources.txt"), encoding: .utf8)
      .split(separator: "\n").filter { !$0.hasPrefix("#") }.map { $0.split(separator: "\t", omittingEmptySubsequences: false) }
    XCTAssertEqual(rows.count, 200)
    let mappedWords = try rows.map { try XCTUnwrap($0.first).description }
    XCTAssertEqual(mappedWords, TypingLanguage.russian.ownedPracticeWords())
    XCTAssertTrue(rows.allSatisfy { $0.count == 3 && !$0[1].isEmpty && Int($0[2]) != nil })
  }

  func testEarlierAuthoredResultsKeepTheirLiteralPromptMetricsAndReplay() throws {
    let prompt = legacy.prefix(3).joined(separator: " ")
    let result = CompletedTestResult(id: UUID(), configuration: .words(3, language: .russian), outcome: .completed,
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
