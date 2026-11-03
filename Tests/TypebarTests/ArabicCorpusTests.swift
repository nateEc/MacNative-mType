import XCTest
@testable import Typebar

final class ArabicCorpusTests: XCTestCase {
  private func marked(_ word: String) -> Bool {
    word.unicodeScalars.contains {
      switch $0.properties.generalCategory {
      case .nonspacingMark, .spacingMark, .enclosingMark: true
      default: false
      }
    }
  }

  func testRawPoolsRetainCompleteUnitHistogramsKeysAndVowelCoverage() {
    for (language, histogram, keys, marks, maxG) in [
      (TypingLanguage.arabic, [3: 3, 4: 4, 5: 7, 6: 19, 7: 32, 8: 34, 9: 38, 10: 26, 11: 15, 12: 9, 13: 7, 14: 3, 15: 1, 16: 1], "ءأؤإئابةتثجحخدذرزسشصضطظعغفقكلمنهوىيًٌٍَُِّْ", 198, 9),
      (.arabic10k, [2: 1, 3: 3, 4: 23, 5: 80, 6: 258, 7: 585, 8: 999, 9: 1318, 10: 1720, 11: 1358, 12: 1130, 13: 888, 14: 396, 15: 303, 16: 126, 17: 39, 18: 25, 19: 18, 20: 7, 21: 4], " Hءآأؤإئابةتثجحخدذرزسشصضطظعغفقكلمنهوىيًٌٍَُِّْی", 8988, 15),
    ] {
      let words = language.ownedPracticeLexicon()
      XCTAssertEqual(words.count, histogram.values.reduce(0, +))
      XCTAssertEqual(Set(words).count, words.count)
      XCTAssertEqual(Dictionary(grouping: words, by: { $0.utf16.count }).mapValues(\.count), histogram)
      XCTAssertEqual(Set(words.joined().unicodeScalars), Set(keys.unicodeScalars))
      XCTAssertEqual(words.filter(marked).count, marks)
      XCTAssertEqual(words.map(\.count).min(), 2)
      XCTAssertEqual(words.map(\.count).max(), maxG)
      XCTAssertTrue(words.allSatisfy { word in
        language == .arabic10k ? word.hasPrefix(" ") && word.filter({ $0 == " " }).count == 1
          : !word.contains(" ")
      })
    }
  }

  func testNewDrawsDoNotUseTheOldNumberedArabicScaleAlphabet() {
    let words = TypingLanguage.arabic10k.ownedPracticeLexicon()
    XCTAssertFalse(words.contains { $0.contains("ڗ") || $0.contains("Z") })
    XCTAssertEqual(words.filter { $0.contains("H") }, [" Hی"])
  }

  func testMarkedRawEntriesAreTrimmedOnceAndCompleteThroughTheActualFactory() throws {
    for language in [TypingLanguage.arabic, .arabic10k] {
      let words = language.ownedPracticeLexicon()
      var targets = [try XCTUnwrap(words.first(where: marked)),
        try XCTUnwrap(words.max(by: { $0.utf16.count < $1.utf16.count }))]
      targets.append(try XCTUnwrap(words.min(by: { $0.utf16.count < $1.utf16.count })))
      if language == .arabic10k {
        targets.append(try XCTUnwrap(words.first(where: { $0.contains("H") })))
      }
      for target in targets {
        let index = try XCTUnwrap(words.firstIndex(of: target))
        var session = TestSessionFactory.make(configuration: .words(1, language: language),
          nextRandomWordIndex: { index })
        // Pinned ordinary words generation lowercases ASCII outside the
        // German/code/Klingon exceptions when punctuation is disabled.
        let expected = target.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        XCTAssertEqual(Array(session.prompt.utf16), Array(expected.utf16))
        session.insertBatch(expected, at: Date(timeIntervalSinceReferenceDate: 925_900_000))
        let result = try XCTUnwrap(session.result())
        XCTAssertEqual(session.errors, 0)
        XCTAssertEqual(session.outcome, .completed)
        XCTAssertEqual(Array(result.prompt.utf16), Array(expected.utf16))
        XCTAssertEqual(session.repeatedAttempt().prompt, expected)
        XCTAssertEqual(try JSONDecoder().decode(CompletedTestResult.self,
          from: JSONEncoder().encode(result)), result)
      }
    }
  }

  func testPriorTargetsRemainUsableWithoutRegenerationOrUnicodeRewriting() throws {
    for (language, target) in [(TypingLanguage.arabic, "جَبَل"), (.arabic, "بِذرة"),
      (.arabic, "إيقاع"), (.arabic, "صَبْر"), (.arabic10k, "Zڗ")] {
      var session = TypingSession(configuration: .words(1, language: language),
        prompt: target, sourceFields: [target])
      session.insertBatch(target, at: Date(timeIntervalSinceReferenceDate: 925_900_000))
      let result = try XCTUnwrap(session.result())
      XCTAssertEqual(session.errors, 0)
      XCTAssertEqual(Array(result.prompt.utf16), Array(target.utf16))
      XCTAssertEqual(Array(session.repeatedAttempt().prompt.utf16), Array(target.utf16))
    }
    for target in ["جَبَل", "بِذرة", "إيقاع", "صَبْر"] {
      XCTAssertTrue(TypingLanguage.arabic10k.ownedPracticeLexicon().contains(" " + target))
      XCTAssertFalse(TypingLanguage.arabic.ownedPracticeLexicon().contains(target))
    }
  }
}
