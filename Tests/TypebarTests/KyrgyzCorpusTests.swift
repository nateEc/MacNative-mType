import XCTest
@testable import Typebar

final class KyrgyzCorpusTests: XCTestCase {
  private let legacy = "салам мен сен биз китеп калем үй жол жарык убакыт суу деңиз күн түн ай дос эртең бүгүн көз барак ой иш баштоо кадам сөз суроо жооп тоо".split(separator: " ").map(String.init)

  func testNativeAttributionIncludesBothLicensesAndPinnedSourceMappings() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["python3", root.appendingPathComponent("Scripts/prepare-kyrgyz-corpus.py").path, "--check-bundled"]
    try process.run(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let notice = try XCTUnwrap(CorpusLicenseNotice.kyrgyz.read(resourceDirectory: root.appendingPathComponent("Resources")))
    for value in ["English Wiktionary contributors", "Tatoeba Kyrgyz contributors", "CC BY-SA 4.0", "CC BY 2.0 France", "809", "31", "кадам", "tatoeba-literal"] {
      XCTAssertTrue(notice.contains(value), value)
    }
  }

  func testLongestStandaloneFormsKeepAllLettersThroughResultAndRepeat() throws {
    for language in [TypingLanguage.kyrgyz, .kyrgyz1k] {
      let words = language.ownedPracticeLexicon()
      let target = try XCTUnwrap(words.filter { $0.allSatisfy(\.isLetter) }.max { $0.utf16.count < $1.utf16.count })
      let index = try XCTUnwrap(words.firstIndex(of: target)), expected = target
      var session = TestSessionFactory.make(configuration: .words(1, language: language), nextRandomWordIndex: { index })
      XCTAssertEqual(session.prompt, expected)
      session.insertBatch(expected, at: Date(timeIntervalSinceReferenceDate: 925_200_000))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.errors, 0)
      XCTAssertEqual(session.result()?.prompt, expected)
      XCTAssertEqual(session.repeatedAttempt().prompt, expected)
    }
  }

  func testCapitalizedSourceOptionsKeepTheirCaseInBothPunctuationModes() throws {
    let words = TypingLanguage.kyrgyz1k.ownedPracticeLexicon()
    let targets = words.filter { $0.contains(where: \.isUppercase) }
    XCTAssertEqual(targets.count, 2)
    for target in targets {
      let index = try XCTUnwrap(words.firstIndex(of: target))
      // Pinned words-generator folds only entries containing ASCII A-Z;
      // Cyrillic М/О alone keep their source case even with punctuation off.
      for punctuation in [false, true] {
        let session = TestSessionFactory.make(configuration: .words(1, language: .kyrgyz1k,
          contentOptions: .init(includePunctuation: punctuation)), nextRandomWordIndex: { index }, nextRandomContentUnit: { 0.5 })
        XCTAssertTrue(session.prompt.hasPrefix(target), session.prompt)
      }
    }
  }

  func testLiteralPoolsKeepCompleteAlphabetsAndJointCategories() {
    for (language, count, maximum, alphabet, expected) in [
      (TypingLanguage.kyrgyz, 234, 9, "-абгдежзийклмнопрстучшыэюяңүө", ["0/0/0": 233, "0/0/1": 1]),
      (.kyrgyz1k, 849, 13, " ,-МОабвгдежзийклмнопрстуфхцчшыьэюяңүө", ["0/0/0": 827, "0/1/0": 10, "0/0/1": 10, "1/0/0": 1, "1/0/1": 1]),
    ] {
      let words = language.ownedPracticeLexicon()
      XCTAssertEqual(words.count, count)
      XCTAssertEqual(Set(words).count, count)
      XCTAssertEqual(Set(words.joined()), Set(alphabet))
      XCTAssertEqual(words.map(\.utf16.count).min(), 2)
      XCTAssertEqual(words.map(\.utf16.count).max(), maximum)
      XCTAssertTrue(Set(legacy).isSubset(of: Set(words)))
      var categories: [String: Int] = [:]
      for word in words {
        let upper = word.contains(where: \.isUppercase) ? 1 : 0
        let punctuation = word.contains(where: \.isPunctuation) ? 1 : 0
        categories["\(upper)/\(word.filter { $0 == " " }.count)/\(punctuation)", default: 0] += 1
      }
      XCTAssertEqual(categories, expected)
      XCTAssertFalse(words.contains { $0.contains("ԝ") || $0.contains("Ө") || $0.contains(".") || $0.contains("  ") })
      XCTAssertTrue(words.allSatisfy { $0 == $0.precomposedStringWithCanonicalMapping && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines) })
      if language == .kyrgyz1k {
        XCTAssertEqual(words.filter { $0.contains("-") }.count, 8)
        XCTAssertEqual(words.filter { $0.contains(",") }.count, 3)
        XCTAssertEqual(Set(words.filter { $0.contains(where: \.isUppercase) }.joined().filter(\.isUppercase)), Set("МО"))
      }
    }
  }

  func testLiteralHyphensAndCommasSurviveFactoryInputAndResult() throws {
    let words = TypingLanguage.kyrgyz1k.ownedPracticeLexicon()
    let targets = words.filter { $0.contains("-") || $0.contains(",") }
    XCTAssertEqual(targets.count, 11)
    XCTAssertEqual(targets.filter { $0.contains(",") }.count, 3)
    for target in targets {
      let index = try XCTUnwrap(words.firstIndex(of: target))
      var session = TestSessionFactory.make(configuration: .words(1, language: .kyrgyz1k), nextRandomWordIndex: { index })
      XCTAssertEqual(session.prompt, target)
      session.insertBatch(target, at: Date(timeIntervalSinceReferenceDate: 925_200_000))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.errors, 0)
      let result = try XCTUnwrap(session.result())
      XCTAssertEqual(result.prompt, target)
      XCTAssertEqual(try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(result)), result)
      XCTAssertEqual(session.repeatedAttempt().prompt, result.prompt)
    }
  }

  func testTwoWordOptionsConsumeSeparateSlotsWithoutSyntheticSpaces() throws {
    let words = TypingLanguage.kyrgyz1k.ownedPracticeLexicon()
    let targets = words.filter { $0.contains(" ") }
    XCTAssertEqual(targets.count, 10)
    for target in targets {
      let index = try XCTUnwrap(words.firstIndex(of: target))
      XCTAssertEqual(target.split(separator: " ").count, 2)
      for limit in 1...2 {
        let expected = target.split(separator: " ").prefix(limit).joined(separator: " ")
        var session = TestSessionFactory.make(configuration: .words(limit, language: .kyrgyz1k), nextRandomWordIndex: { index })
        XCTAssertEqual(session.prompt, expected)
        session.insertBatch(expected, at: Date(timeIntervalSinceReferenceDate: 925_200_000))
        XCTAssertEqual(session.outcome, .completed)
        XCTAssertEqual(session.errors, 0)
        XCTAssertEqual(session.result()?.prompt, expected)
        XCTAssertEqual(session.repeatedAttempt().prompt, expected)
      }
    }
  }

  func testOldMarkerTargetIsNotRewrittenByNewCorpus() throws {
    let target = "ԝабв"
    var session = TypingSession(configuration: .words(1, language: .kyrgyz1k), prompt: target, sourceFields: [target])
    session.insertBatch(target, at: Date(timeIntervalSinceReferenceDate: 925_200_000))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.prompt, target)
    XCTAssertEqual(session.repeatedAttempt().prompt, target)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: result.elapsedDuration), target)
  }
}
