import XCTest
@testable import Typebar

final class KazakhCorpusTests: XCTestCase {
  private let legacy = "кітап есік жол жарық көпір таң бет орын бұлт тыныштық тау тұқым дауыс үстел ой сөйлем көзқарас тәжірибе қашықтық қадам сабыр тепе теңдік ауыл жаңбыр жұлдыз дос үміт еңбек өзен".split(separator: " ").map(String.init)

  func testPinnedProvenanceAndAttributionAreReadableFromTheNativeChoice() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["python3", root.appendingPathComponent("Scripts/prepare-kazakh-corpus.py").path, "--check-bundled"]
    try process.run(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let notice = try XCTUnwrap(CorpusLicenseNotice.kazakh.read(resourceDirectory: root.appendingPathComponent("Resources")))
    for text in ["English Wiktionary contributors", "Tatoeba Kazakh contributors", "CC BY 2.0 France", "4575", "51", "тепе"] {
      XCTAssertTrue(notice.contains(text), text)
    }
  }

  func testLongestStandaloneWordsCompleteWithoutLosingKazakhLetters() throws {
    for language in [TypingLanguage.kazakh, .kazakh1k] {
      let words = language.ownedPracticeLexicon()
      let target = try XCTUnwrap(words.filter { $0.allSatisfy(\.isLetter) }.max { $0.utf16.count < $1.utf16.count })
      let index = try XCTUnwrap(words.firstIndex(of: target))
      var session = TestSessionFactory.make(configuration: .words(1, language: language), nextRandomWordIndex: { index })
      XCTAssertEqual(session.prompt, target)
      session.insertBatch(target, at: Date(timeIntervalSinceReferenceDate: 925_100_000))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.errors, 0)
      let result = try XCTUnwrap(session.result())
      XCTAssertEqual(try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(result)), result)
      XCTAssertEqual(result.prompt, target)
      XCTAssertEqual(session.repeatedAttempt().prompt, target)
    }
  }

  func testTwoLiteralPoolsKeepTheirOwnAlphabetsAndOldStarters() {
    for (language, count, maximum, alphabet, hyphens, phrases) in [
      (TypingLanguage.kazakh, 202, 8, "абгдежзийклмнопрстухшыюяіғқңүұәө", 0, 0),
      (.kazakh1k, 990, 16, " -абвгдежзийклмнопрстуфхцчшыьэюяіғқңүұәө", 4, 3),
    ] {
      let words = language.ownedPracticeLexicon()
      XCTAssertEqual(words.count, count)
      XCTAssertEqual(Set(words).count, count)
      XCTAssertEqual(Set(words.joined()), Set(alphabet))
      XCTAssertEqual(words.map(\.utf16.count).min(), 2)
      XCTAssertEqual(words.map(\.utf16.count).max(), maximum)
      XCTAssertEqual(words.filter { $0.contains("-") }.count, hyphens)
      XCTAssertEqual(words.filter { $0.contains(" ") }.count, phrases)
      XCTAssertTrue(Set(legacy).isSubset(of: Set(words)))
      XCTAssertTrue(words.allSatisfy { $0 == $0.precomposedStringWithCanonicalMapping && $0 == $0.lowercased() })
      XCTAssertFalse(words.contains { $0.contains("ԛ") || $0.contains(".") || $0.contains("  ") })
      XCTAssertTrue(words.allSatisfy { $0.split(whereSeparator: { $0 == "-" || $0 == " " }).allSatisfy { $0.allSatisfy(\.isLetter) } })
      if language == .kazakh {
        XCTAssertEqual(Set(words.filter { $0.utf16.count > 7 }), Set(legacy.filter { $0.utf16.count > 7 }))
      }
    }
  }

  func testHyphenatedOptionsStayWholeThroughInputResultAndRepeat() throws {
    let words = TypingLanguage.kazakh1k.ownedPracticeLexicon()
    let candidates = words.filter { $0.contains("-") }
    XCTAssertEqual(candidates.count, 4)
    for target in candidates {
      let index = try XCTUnwrap(words.firstIndex(of: target))
      var session = TestSessionFactory.make(configuration: .words(1, language: .kazakh1k), nextRandomWordIndex: { index })
      XCTAssertEqual(session.prompt, target)
      session.insertBatch(target, at: Date(timeIntervalSinceReferenceDate: 925_100_000))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.errors, 0)
      let result = try XCTUnwrap(session.result())
      XCTAssertEqual(result.prompt, target)
      XCTAssertEqual(try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(result)), result)
      XCTAssertEqual(session.repeatedAttempt().prompt, target)
    }
  }

  func testTwoWordHeadwordsConsumeTwoFactorySlots() throws {
    let words = TypingLanguage.kazakh1k.ownedPracticeLexicon()
    let phrases = words.filter { $0.contains(" ") }
    XCTAssertEqual(phrases.count, 3)
    for target in phrases {
      let index = try XCTUnwrap(words.firstIndex(of: target))
      XCTAssertEqual(target.split(separator: " ").count, 2)
      for limit in 1...2 {
        let expected = target.split(separator: " ").prefix(limit).joined(separator: " ")
        var session = TestSessionFactory.make(configuration: .words(limit, language: .kazakh1k), nextRandomWordIndex: { index })
        XCTAssertEqual(session.prompt, expected)
        session.insertBatch(expected, at: Date(timeIntervalSinceReferenceDate: 925_100_000))
        XCTAssertEqual(session.outcome, .completed)
        XCTAssertEqual(session.errors, 0)
        XCTAssertEqual(session.result()?.prompt, expected)
        XCTAssertEqual(session.repeatedAttempt().prompt, expected)
      }
    }
  }

  func testOldNumberedTargetsRemainUnchangedInReplayAndResults() throws {
    let target = "ԛабв"
    var session = TypingSession(configuration: .words(1, language: .kazakh1k), prompt: target, sourceFields: [target])
    session.insertBatch(target, at: Date(timeIntervalSinceReferenceDate: 925_100_000))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.prompt, target)
    XCTAssertEqual(session.repeatedAttempt().prompt, target)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: result.elapsedDuration), target)
  }
}
