import XCTest
@testable import Typebar

final class VietnameseCorpusTests: XCTestCase {
  private let legacy = "sách cửa đường ánh sáng cầu buổi trang nơi mây yên lặng núi hạt giọng bàn ý câu nhìn trải nghiệm khoảng cách bước kiên nhẫn cân bằng làng mưa".split(separator: " ").map(String.init)

  func testBundledCorpusHasPinnedProvenanceAndReadableNativeAttribution() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["python3", root.appendingPathComponent("Scripts/prepare-vietnamese-corpus.py").path, "--check-bundled"]
    try process.run(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let notice = try XCTUnwrap(CorpusLicenseNotice.vietnamese.read(
      resourceDirectory: root.appendingPathComponent("Resources")))
    XCTAssertTrue(notice.contains("English Wiktionary contributors"))
    XCTAssertTrue(notice.contains("wordfreq 3.1.1"))
    XCTAssertTrue(notice.contains("CC BY-SA 4.0"))
    XCTAssertTrue(notice.contains("kiên"))
  }

  func testAllThreeRoutesUseLiteralVietnameseInsteadOfNumberedScalePadding() {
    // Only aggregate counts and typing alphabets come from the pinned source.
    for (language, count, maximum, nonASCII, characters) in [
      (TypingLanguage.vietnamese, 319, 6, 270, "abcdeghiklmnopqrstuvxyàáâãéêìíòóôùúýăđĩũơưạảấầẩậắằẳặẹẻẽếểễệỉịọỏốồổỗộớờởợủứừửữự"),
      (.vietnamese1k, 1000, 7, 870, "abcdeghiklmnopqrstuvxyàáâãèéêìíòóôõùúýăđĩũơưạảấầẩẫậắằẳẵặẹẻẽếềểễệỉịọỏốồổỗộớờởỡợụủứừửữựỳỷỹ"),
      (.vietnamese5k, 5000, 7, 4450, "abcdefghiklmnopqrstuvxyàáâãèéêìíòóôõùúýăđĩũơưạảấầẩẫậắằẳẵặẹẻẽếềểễệỉịọỏốồổỗộớờởỡợụủứừửữựỳỵỷỹ"),
    ] {
      let words = language.ownedPracticeLexicon()
      XCTAssertEqual(words.count, count, language.rawValue)
      XCTAssertEqual(Set(words).count, count, language.rawValue)
      XCTAssertEqual(Set(words.joined()), Set(characters).union(legacy.joined()),
        "Retain authored nhẫn even though the source basic alphabet omits ẫ: \(language.rawValue)")
      XCTAssertEqual(words.map(\.utf16.count).min(), 1)
      XCTAssertEqual(words.map(\.utf16.count).max(), maximum)
      XCTAssertEqual(words.filter { !$0.unicodeScalars.allSatisfy(\.isASCII) }.count, nonASCII)
      XCTAssertTrue(words.allSatisfy { $0 == $0.precomposedStringWithCanonicalMapping
        && $0 == $0.lowercased() && $0.allSatisfy(\.isLetter) })
      XCTAssertFalse(words.contains { $0.contains("ƌ") || $0.contains("ɖ")
        || $0.hasPrefix("qvi") || $0.hasPrefix("xvi") })
      XCTAssertTrue(Set(legacy).isSubset(of: Set(words)), "All 30 authored starters: \(language.rawValue)")
    }
  }

  func testFactoryRetainsLongestLiteralTargetThroughInputResultAndRepeat() throws {
    for language in [TypingLanguage.vietnamese, .vietnamese1k, .vietnamese5k] {
      let words = language.ownedPracticeLexicon()
      let target = try XCTUnwrap(words.max { $0.utf16.count < $1.utf16.count })
      let index = try XCTUnwrap(words.firstIndex(of: target))
      var session = TestSessionFactory.make(configuration: .words(1, language: language),
        nextRandomWordIndex: { index })
      XCTAssertEqual(session.prompt, target)
      session.insertBatch(target, at: Date(timeIntervalSinceReferenceDate: 924_000_000))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.errors, 0)
      let result = try XCTUnwrap(session.result())
      XCTAssertEqual(result.prompt, target)
      XCTAssertEqual(try JSONDecoder().decode(CompletedTestResult.self,
        from: JSONEncoder().encode(result)), result)
      XCTAssertEqual(session.repeatedAttempt().prompt, target)
    }
  }

  func testExistingSyntheticTargetRemainsReplayableRatherThanBeingRewritten() throws {
    let target = "qvilegacy"
    var session = TypingSession(configuration: .words(1, language: .vietnamese1k),
      prompt: target, sourceFields: [target])
    session.insertBatch(target, at: Date(timeIntervalSinceReferenceDate: 924_000_000))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.prompt, target)
    XCTAssertEqual(session.repeatedAttempt().prompt, target)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents,
      through: result.elapsedDuration), target)
  }
}
