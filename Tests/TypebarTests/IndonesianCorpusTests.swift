import XCTest
@testable import Typebar

final class IndonesianCorpusTests: XCTestCase {
  func testAllThreePoolsContainLiteralFormsInsteadOfNumberedPadding() {
    for (language, count) in [(TypingLanguage.indonesian, 310), (.indonesian1k, 1_020), (.indonesian10k, 13_769)] {
      let words = language.ownedPracticeLexicon()
      XCTAssertEqual(words.count, count, language.rawValue)
      XCTAssertEqual(Set(words).count, count, language.rawValue)
      let characters = language == .indonesian ? "abcdefghijklmnoprstuwy"
        : language == .indonesian1k ? "-ITabcdefghijklmnoprstuvwyz" : "-abcdefghijklmnopqrstuvwxyz"
      XCTAssertEqual(Set(words.joined()), Set(characters), "Typing key coverage: \(language.rawValue)")
      XCTAssertFalse(words.contains { $0.hasPrefix("qz") || $0 == "qx" || $0.allSatisfy { $0 == "q" } }, language.rawValue)
      for legacy in ["kesabaran", "sejenak", "hening", "perjalanan", "napas"] {
        XCTAssertTrue(words.contains(legacy), "\(language.rawValue): \(legacy)")
      }
    }
  }

  func testBundledCorpusHasPinnedProvenanceAndAttribution() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["python3", root.appendingPathComponent("Scripts/prepare-indonesian-corpus.py").path, "--check-bundled"]
    try process.run(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
  }

  func testLongHyphenatedAndCapitalizedFieldsKeepInputResultsAndRepeatTargets() throws {
    let now = Date(timeIntervalSinceReferenceDate: 922_000_000)
    for language in [TypingLanguage.indonesian, .indonesian1k, .indonesian10k] {
      let words = language.ownedPracticeLexicon()
      var targets = [try XCTUnwrap(words.max { $0.count < $1.count })]
      if let hyphen = words.first(where: { $0.contains("-") }) { targets.append(hyphen) }
      if let capital = words.first(where: { $0.contains(where: \.isUppercase) }) { targets.append(capital) }
      for target in targets {
        var session = TypingSession(configuration: .words(1, language: language), prompt: target, sourceFields: [target])
        session.insertBatch(target, at: now)
        XCTAssertEqual(session.outcome, .completed, target)
        XCTAssertEqual(session.errors, 0, target)
        let result = try XCTUnwrap(session.result(), target)
        XCTAssertEqual(result.prompt, target)
        XCTAssertEqual(try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(result)), result)
        XCTAssertEqual(session.repeatedAttempt().prompt, target)
      }
    }
    var old = TypingSession(configuration: .words(1, language: .indonesian10k), prompt: "qzlegacy", sourceFields: ["qzlegacy"])
    old.insertBatch("qzlegacy", at: now)
    XCTAssertEqual(old.outcome, .completed)
    XCTAssertEqual(old.repeatedAttempt().prompt, "qzlegacy", "Updating content must not rewrite an existing target")
  }
}
