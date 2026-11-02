import XCTest
@testable import Typebar

final class TurkishCorpusTests: XCTestCase {
  private let legacy = "sabah pencere kağıt kıyı rüzgar alıştırma odak sakin açık göl sokak masa ışık yolculuk sabır an şehir yağmur sessiz yön yıldız not bahçe nefes".split(separator: " ").map(String.init)

  func testBundledSourceMappingsAndCompleteAttributionArePinnedAndReadable() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["python3", root.appendingPathComponent("Scripts/prepare-turkish-corpus.py").path, "--check-bundled"]
    try process.run(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let notice = try XCTUnwrap(CorpusLicenseNotice.turkish.read(resourceDirectory: root.appendingPathComponent("Resources")))
    for credit in ["English Wiktionary contributors", "wordfreq 3.1.1", "Tatoeba Turkish contributors", "CC BY 2.0 France", "750083", "1062"] {
      XCTAssertTrue(notice.contains(credit), credit)
    }
  }

  func testAllThreePoolsUseLiteralWordsAndPreserveTheirDistinctTypingAlphabets() {
    // Reference-derived information is aggregate only, never reference words.
    for (language, count, maximum, characters, expected) in [
      (TypingLanguage.turkish, 299, 11, " abcdefghiklmnoprstuvyzçöüğış", ["0/0/0": 174, "1/0/0": 124, "0/0/1": 1]),
      (.turkish1k, 1026, 13, " abcdefghijklmnoprstuvyzçöüğış", ["0/0/0": 563, "1/0/0": 462, "0/0/1": 1]),
      (.turkish5k, 5016, 17, " Habcdefghijklmnoprstuvyzçöüğış", ["0/0/0": 2848, "1/0/0": 2131, "0/0/1": 13, "1/0/1": 22, "1/0/2": 1, "1/1/0": 1]),
    ] {
      let words = language.ownedPracticeLexicon()
      XCTAssertEqual(words.count, count, language.rawValue)
      XCTAssertEqual(Set(words).count, count, language.rawValue)
      XCTAssertEqual(Set(words.joined()), Set(characters), language.rawValue)
      XCTAssertEqual(words.map(\.utf16.count).min(), 1)
      XCTAssertEqual(words.map(\.utf16.count).max(), maximum)
      var categories: [String: Int] = [:]
      for word in words {
        let nonASCII = word.unicodeScalars.allSatisfy(\.isASCII) ? 0 : 1
        let upper = word.contains(where: \.isUppercase) ? 1 : 0
        categories["\(nonASCII)/\(upper)/\(word.filter { $0 == " " }.count)", default: 0] += 1
      }
      XCTAssertEqual(categories, expected, language.rawValue)
      XCTAssertTrue(words.allSatisfy { $0 == $0.precomposedStringWithCanonicalMapping
        && $0.split(separator: " ", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isLetter) } })
      XCTAssertFalse(words.contains { $0.hasPrefix("qtr") || $0.hasPrefix("xtr") || $0.contains("ƛ") || $0.contains("Ƶ") })
      XCTAssertTrue(Set(legacy).isSubset(of: Set(words)), language.rawValue)
    }
  }

  func testThreeWordCandidateUsesThreeSlotsWithoutInventingAdjacentSpaces() throws {
    let words = TypingLanguage.turkish5k.ownedPracticeLexicon()
    let target = try XCTUnwrap(words.first { $0.split(separator: " ").count == 3 })
    let index = try XCTUnwrap(words.firstIndex(of: target))
    let components = target.split(separator: " ").map(String.init)
    XCTAssertFalse(target.contains("  "))
    for limit in 1...3 {
      let expected = components.prefix(limit).joined(separator: " ").lowercased()
      var session = TestSessionFactory.make(configuration: .words(limit, language: .turkish5k),
        nextRandomWordIndex: { index })
      XCTAssertEqual(session.prompt, expected)
      session.insertBatch(expected, at: Date(timeIntervalSinceReferenceDate: 925_000_000))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.errors, 0)
      let result = try XCTUnwrap(session.result())
      XCTAssertEqual(result.prompt, expected)
      XCTAssertEqual(try JSONDecoder().decode(CompletedTestResult.self,
        from: JSONEncoder().encode(result)), result)
      XCTAssertEqual(session.repeatedAttempt().prompt, expected)
    }
  }

  func testCapitalizedCandidateRetainsItsLiteralHWhenPunctuationIsEnabled() throws {
    let words = TypingLanguage.turkish5k.ownedPracticeLexicon()
    let target = try XCTUnwrap(words.first { $0.contains(where: \.isUppercase) })
    XCTAssertTrue(target.hasPrefix("H"))
    let index = try XCTUnwrap(words.firstIndex(of: target))
    let plain = TestSessionFactory.make(configuration: .words(1, language: .turkish5k),
      nextRandomWordIndex: { index })
    XCTAssertEqual(plain.prompt, target.lowercased())
    let punctuated = TestSessionFactory.make(configuration: .words(1, language: .turkish5k,
      contentOptions: .init(includePunctuation: true)), nextRandomWordIndex: { index },
      nextRandomContentUnit: { 0.5 })
    XCTAssertTrue(punctuated.prompt.hasPrefix(target))
  }

  func testOldSyntheticTargetRemainsLiteralInResultAndReplay() throws {
    let target = "qtrlegacy"
    var session = TypingSession(configuration: .words(1, language: .turkish1k),
      prompt: target, sourceFields: [target])
    session.insertBatch(target, at: Date(timeIntervalSinceReferenceDate: 925_000_000))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.prompt, target)
    XCTAssertEqual(session.repeatedAttempt().prompt, target)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents,
      through: result.elapsedDuration), target)
  }

  func testLongestStandaloneFormsKeepEveryLetterThroughFactoryInputAndResult() throws {
    for language in [TypingLanguage.turkish, .turkish1k, .turkish5k] {
      let words = language.ownedPracticeLexicon()
      let target = try XCTUnwrap(words.filter { !$0.contains(" ") }.max { $0.utf16.count < $1.utf16.count })
      let index = try XCTUnwrap(words.firstIndex(of: target))
      var session = TestSessionFactory.make(configuration: .words(1, language: language),
        nextRandomWordIndex: { index })
      XCTAssertEqual(session.prompt, target.lowercased())
      session.insertBatch(target.lowercased(), at: Date(timeIntervalSinceReferenceDate: 925_000_000))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.errors, 0)
      let result = try XCTUnwrap(session.result())
      XCTAssertEqual(result.prompt, target.lowercased())
      XCTAssertEqual(try JSONDecoder().decode(CompletedTestResult.self,
        from: JSONEncoder().encode(result)), result)
      XCTAssertEqual(session.repeatedAttempt().prompt, target.lowercased())
    }
  }
}
