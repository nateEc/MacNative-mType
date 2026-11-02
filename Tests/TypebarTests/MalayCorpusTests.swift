import XCTest
@testable import Typebar

final class MalayCorpusTests: XCTestCase {
  func testBundledCorpusHasPinnedProvenanceAndAttribution() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["python3", root.appendingPathComponent("Scripts/prepare-malay-corpus.py").path, "--check-bundled"]
    try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
  }

  func testBothPoolsUseLiteralFormsAndPreserveTypingKeysAndLegacyWords() {
    for (language, count, characters) in [
      (TypingLanguage.malay, 228, "abcdefghijklmnoprstuwy"),
      (.malay1k, 1000, " -Sabcdefghijklmnoprstuvwyz"),
    ] {
      let words = language.ownedPracticeLexicon()
      XCTAssertEqual(words.count, count)
      XCTAssertEqual(Set(words).count, count)
      XCTAssertEqual(Set(words.joined()), Set(characters))
      XCTAssertFalse(words.contains { $0.hasPrefix("qz") || $0.allSatisfy { $0 == "q" } || $0.hasSuffix("-") })
      for word in ["tingkap", "latihan", "harapan", "catatan", "seketika", "nafas"] {
        XCTAssertTrue(words.contains(word), "\(language.rawValue): \(word)")
      }
    }
  }

  func testActualFactorySplitsPhraseAndPreservesHyphenCapitalAndLongInput() throws {
    let words = TypingLanguage.malay1k.ownedPracticeLexicon()
    let targets = [try XCTUnwrap(words.first(where: { $0.contains(" ") })),
      try XCTUnwrap(words.first(where: { $0.contains("-") })),
      try XCTUnwrap(words.first(where: { $0.contains(where: \.isUppercase) })),
      try XCTUnwrap(words.max { $0.count < $1.count })]
    for target in targets {
      let index = try XCTUnwrap(words.firstIndex(of: target))
      let components = target.split(separator: " ").map(String.init)
      let expected = components.joined(separator: " ").lowercased()
      var session = TestSessionFactory.make(configuration: .words(components.count,
        rules: .init(stopOnErrorMode: .letter), language: .malay1k), nextRandomWordIndex: { index })
      XCTAssertEqual(session.prompt, expected)
      if components.count > 1 {
        let single = TestSessionFactory.make(configuration: .words(1, language: .malay1k), nextRandomWordIndex: { index })
        XCTAssertEqual(single.prompt, components[0].lowercased(), "The source consumes a candidate section across word slots")
      }
      session.insertBatch(expected, at: Date(timeIntervalSinceReferenceDate: 923_000_000))
      XCTAssertEqual(session.outcome, .completed, target)
      XCTAssertEqual(session.errors, 0, target)
      let result = try XCTUnwrap(session.result(), target)
      XCTAssertEqual(result.prompt, expected)
      XCTAssertEqual(try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(result)), result)
      XCTAssertEqual(session.repeatedAttempt().prompt, expected)
    }
    let capital = try XCTUnwrap(words.first(where: { $0.contains(where: \.isUppercase) }))
    let capitalIndex = try XCTUnwrap(words.firstIndex(of: capital))
    let punctuated = TestSessionFactory.make(configuration: .words(1, language: .malay1k,
      contentOptions: .init(includePunctuation: true)), nextRandomWordIndex: { capitalIndex }, nextRandomContentUnit: { 0.5 })
    XCTAssertTrue(punctuated.prompt.contains(where: \.isUppercase), "Punctuation enables source uppercase practice")
  }
}
