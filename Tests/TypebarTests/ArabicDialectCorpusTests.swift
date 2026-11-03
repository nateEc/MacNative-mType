import XCTest
@testable import Typebar

final class ArabicDialectCorpusTests: XCTestCase {
  private func category(_ word: String) -> String {
    let marked = word.unicodeScalars.contains {
      switch $0.properties.generalCategory {
      case .nonspacingMark, .spacingMark, .enclosingMark: true
      default: false
      }
    }
    return "\(word.filter { $0 == " " }.count)/\(word.hasPrefix(" "))/\(marked)"
  }

  func testDialectPoolsRetainFullUnitLengthsKeysAndJointSpacingCategories() {
    for (language, histogram, keys, categories, maxG) in [
      (TypingLanguage.arabicEgypt, [2: 15, 3: 83, 4: 71, 5: 21, 6: 13, 7: 1, 8: 6], " ءابةتجحخدرزسشصضطعغفقكلمنهوىي", ["0/false/false": 203, "1/false/false": 7], 8),
      (.arabicEgypt1k, [2: 46, 3: 253, 4: 304, 5: 301, 6: 115, 7: 69, 8: 32, 9: 9, 10: 3, 11: 1, 12: 2, 13: 3, 14: 2, 16: 1], " ءأإئابةتثجحخدذرزسشصضطظعغفقكلمنهوىي", ["0/false/false": 1078, "1/false/false": 55, "2/false/false": 6, "3/false/false": 1, "1/true/false": 1], 16),
      (.arabicMorocco, [2: 12, 3: 56, 4: 91, 5: 48, 6: 17, 7: 4, 8: 1], " آأئابةتثجحخدرزسشصضطعغـفقكلمنهوىيًّ", ["0/false/false": 221, "0/false/true": 5, "1/false/true": 1, "1/false/false": 2], 7),
    ] {
      let words = language.ownedPracticeLexicon()
      XCTAssertEqual(words.count, histogram.values.reduce(0, +))
      XCTAssertEqual(Set(words).count, words.count)
      XCTAssertEqual(Dictionary(grouping: words, by: { $0.utf16.count }).mapValues(\.count), histogram)
      XCTAssertEqual(Set(words.joined().unicodeScalars), Set(keys.unicodeScalars))
      XCTAssertEqual(Dictionary(grouping: words, by: category).mapValues(\.count), categories)
      XCTAssertEqual(words.map(\.count).min(), 2)
      XCTAssertEqual(words.map(\.count).max(), maxG)
      XCTAssertFalse(words.contains { $0.contains("ڗ") })
    }
  }

  func testObservedPhrasesAndLeadingEntryKeepAllComponentsInTheActualFactory() throws {
    for language in [TypingLanguage.arabicEgypt, .arabicEgypt1k, .arabicMorocco] {
      let words = language.ownedPracticeLexicon()
      var targets = [try XCTUnwrap(words.first(where: { $0.contains(" ") })),
        try XCTUnwrap(words.max(by: { $0.utf16.count < $1.utf16.count }))]
      if language == .arabicEgypt1k {
        targets.append(try XCTUnwrap(words.first(where: { $0.filter { $0 == " " }.count == 3 })))
        targets.append(try XCTUnwrap(words.first(where: { $0.hasPrefix(" ") })))
      }
      if language == .arabicMorocco {
        targets.append(try XCTUnwrap(words.first(where: { $0.contains("ـ") })))
        targets.append(try XCTUnwrap(words.first(where: {
          $0.contains(" ") && $0.unicodeScalars.contains(where: { $0.value == 0x0651 })
        })))
      }
      for target in targets {
        let index = try XCTUnwrap(words.firstIndex(of: target))
        let components = target.split(whereSeparator: \.isWhitespace).map(String.init)
        let expected = components.joined(separator: " ")
        var continuation = GeneratedCandidateContinuation(
          configuration: .words(components.count, language: language),
          batchTokenCount: 1, sourceWords: [target])
        var reconstructed = ""
        for _ in components.indices {
          XCTAssertTrue(continuation.hasRemaining)
          reconstructed += continuation.nextChunk(nextRandomWordIndex: { 0 }).transformed
        }
        XCTAssertFalse(continuation.hasRemaining)
        XCTAssertEqual(reconstructed, expected)
        var session = TestSessionFactory.make(configuration: .words(components.count, language: language),
          nextRandomWordIndex: { index })
        XCTAssertEqual(Array(session.prompt.utf16), Array(expected.utf16))
        session.insertBatch(expected, at: Date(timeIntervalSinceReferenceDate: 925_950_000))
        let result = try XCTUnwrap(session.result())
        XCTAssertEqual(session.outcome, .completed)
        XCTAssertEqual(session.errors, 0)
        XCTAssertEqual(result.prompt, expected)
        XCTAssertEqual(session.repeatedAttempt().prompt, expected)
        XCTAssertEqual(try JSONDecoder().decode(CompletedTestResult.self,
          from: JSONEncoder().encode(result)), result)
      }
    }
  }

  func testStoredSyntheticTargetStillCompletesWithoutRegeneration() throws {
    let target = "ڗڗ"
    var session = TypingSession(configuration: .words(1, language: .arabicEgypt1k),
      prompt: target, sourceFields: [target])
    session.insertBatch(target, at: Date(timeIntervalSinceReferenceDate: 925_950_000))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(session.errors, 0)
    XCTAssertEqual(result.prompt, target)
    XCTAssertEqual(session.repeatedAttempt().prompt, target)
  }
}
