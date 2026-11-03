import XCTest
@testable import Typebar

final class HiGuCorpusTests: XCTestCase {
  private let hindiLegacy = ["पुस्तक", "कलम", "खिड़की", "रास्ता", "रोशनी", "पुल", "सुबह", "कागज़", "बगीचा", "बादल", "शांति", "दीपक", "पहाड़", "बीज", "संगीत", "मेज़", "विचार", "टिप्पणी", "कल्पना", "प्रयास", "दूरी", "कदम", "धैर्य", "संतुलन"]
  private let gujaratiLegacy = ["બારી", "પતંગ", "નદી", "દીવો", "પર્ણ", "રંગ", "ચિત્ર", "ઘડિયાળ", "સફર", "સૂરજ", "વાદળ", "પુલ", "કિનારો", "સંગીત", "પ્રશ્ન", "જવાબ", "કલ્પના", "નોંધપોથી", "પ્રયત્ન", "વિરામ", "હિંમત", "ધીરજ", "સરળતા", "તાલ"]
  // Fixed reference facts are aggregate shapes and character sets, never words.
  private let facts: [(TypingLanguage, Int, Int, Int, Int, String, Int)] = [
    (.hindi, 200, 2, 10, 5, "ँंअआइईउऊएऐकखगचछजटठडणतथदधनपफबभमयरलवशषसह़ािीुूृेैो्", 193),
    (.hindi1k, 999, 1, 12, 6, "ँंःअआइईउऊएऐओऔकखगघचछजझञटठडढणतथदधनपफबभमयरलवशषसह़ािीुूृेैोौ्ॐ", 956),
    (.gujarati, 214, 1, 12, 6, "ંઅઆઈઉએઓકખગઘચછજટઠડણતથદધનપફબભમયરલળવશષસહાિીુૂૃેો્", 199),
    (.gujarati1k, 1004, 1, 19, 12, " ંઃઅઆઇઈઉઊએઐઓઔકખગઘઙચછજઝઞટઠડઢણતથદધનપફબભમયરલળવશષસહાિીુૂૃેૈૉોૌ્", 900),
  ]
  private func marked(_ word: String) -> Bool {
    word.unicodeScalars.contains {
      switch $0.properties.generalCategory {
      case .nonspacingMark, .spacingMark, .enclosingMark: true
      default: false
      }
    }
  }

  func testFourLiteralPoolsRetainKeysMarksAndEveryOldStarter() {
    for (language, count, minimum, maximum, maxG, keys, marks) in facts {
      let words = language.ownedPracticeLexicon()
      let legacy = language == .hindi || language == .hindi1k ? hindiLegacy : gujaratiLegacy
      XCTAssertEqual(words.count, count, language.rawValue)
      XCTAssertEqual(Set(words).count, count)
      XCTAssertEqual(words.map(\.utf16.count).min(), minimum)
      XCTAssertEqual(words.map(\.utf16.count).max(), maximum)
      XCTAssertEqual(words.map(\.count).max(), maxG)
      XCTAssertEqual(Set(words.joined().unicodeScalars), Set((keys + legacy.joined()).unicodeScalars))
      XCTAssertTrue(Set(legacy).isSubset(of: Set(words)))
      XCTAssertEqual(words.filter(marked).count, marks)
      XCTAssertTrue(words.allSatisfy { $0 == $0.precomposedStringWithCanonicalMapping })
      XCTAssertFalse(words.contains { $0.contains("ॹ") || $0.contains("ૹ") })
    }
  }

  func testGujaratiPhraseAndBorderWhitespaceShapesRemainIndependentlyTypeable() throws {
    let words = TypingLanguage.gujarati1k.ownedPracticeLexicon()
    XCTAssertEqual(words.filter { $0.hasPrefix(" ") }.count, 1)
    XCTAssertEqual(words.filter { $0.hasSuffix(" ") }.count, 1)
    XCTAssertFalse(words.contains { $0.contains("  ") })
    XCTAssertEqual(words.filter { $0.filter { $0 == " " }.count == 1 }.count, 28)
    XCTAssertEqual(words.filter { $0.filter { $0 == " " }.count == 2 }.count, 3)
    XCTAssertEqual(words.filter { $0.filter { $0 == " " }.count == 3 }.count, 2)
    for (key, count) in [("mark spaces=0", 868), ("mark spaces=1", 27), ("mark spaces=2", 3), ("mark spaces=3", 2), ("plain spaces=0", 103), ("plain spaces=1", 1)] {
      XCTAssertEqual(words.filter { (marked($0) ? "mark" : "plain") + " spaces=" + String($0.filter { $0 == " " }.count) == key }.count, count, key)
    }
    for predicate in [{ (w: String) in w.hasPrefix(" ") }, { $0.hasSuffix(" ") }, { $0.filter { $0 == " " }.count == 3 }] {
      let target = try XCTUnwrap(words.first(where: predicate))
      let index = try XCTUnwrap(words.firstIndex(of: target))
      // Published generation trims border spaces and consumes one slot per component.
      let expected = target.trimmingCharacters(in: .whitespaces)
      var session = TestSessionFactory.make(configuration: .words(expected.split(separator: " ").count, language: .gujarati1k), nextRandomWordIndex: { index })
      XCTAssertEqual(Array(session.prompt.utf16), Array(expected.utf16))
      session.insertBatch(expected, at: Date(timeIntervalSinceReferenceDate: 925_500_000))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.errors, 0)
      XCTAssertEqual(session.result()?.prompt, expected)
      XCTAssertEqual(session.repeatedAttempt().prompt, expected)
    }
  }

  func testShortestLongestAndCombiningSequencesSurviveResultsAndRepeat() throws {
    for (language, _, _, _, _, _, _) in facts {
      let words = language.ownedPracticeLexicon().sorted { $0.utf16.count < $1.utf16.count }
      let mark = language == .hindi || language == .hindi1k ? "ि" : "િ"
      for target in [try XCTUnwrap(words.first), try XCTUnwrap(words.last), try XCTUnwrap(words.first { $0.unicodeScalars.contains { String($0) == mark } }, "\(language.rawValue): missing scalar \(mark)")] {
        let index = try XCTUnwrap(language.ownedPracticeLexicon().firstIndex(of: target))
        let expected = target.trimmingCharacters(in: .whitespaces)
        var session = TestSessionFactory.make(configuration: .words(expected.split(separator: " ").count, language: language), nextRandomWordIndex: { index })
        XCTAssertEqual(Array(session.prompt.utf16), Array(expected.utf16))
        session.insertBatch(expected, at: Date(timeIntervalSinceReferenceDate: 925_500_000))
        XCTAssertEqual(session.outcome, .completed)
        XCTAssertEqual(session.errors, 0)
        let result = try XCTUnwrap(session.result())
        XCTAssertEqual(try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(result)), result)
        XCTAssertEqual(result.prompt, expected)
        XCTAssertEqual(session.repeatedAttempt().prompt, expected)
      }
    }
  }

  func testOldSyntheticResultsReplayTheirOriginalTargets() throws {
    for (language, target) in [(TypingLanguage.hindi1k, "ॹखगा"), (.gujarati1k, "ૹખગા")] {
      var session = TypingSession(configuration: .words(1, language: language), prompt: target, sourceFields: [target])
      session.insertBatch(target, at: Date(timeIntervalSinceReferenceDate: 925_500_000))
      let result = try XCTUnwrap(session.result())
      XCTAssertEqual(result.prompt, target)
      XCTAssertEqual(session.repeatedAttempt().prompt, target)
      XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: result.elapsedDuration), target)
    }
  }

  func testIndependentSourcesAndCharacterPracticeCreditsAreReadable() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["python3", root.appendingPathComponent("Scripts/prepare-hi-gu-corpora.py").path, "--check-bundled"]
    try process.run(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    for notice in [CorpusLicenseNotice.hindi, .gujarati] {
      let text = try XCTUnwrap(notice.read(resourceDirectory: root.appendingPathComponent("Resources")))
      for credit in ["English Wiktionary contributors", "CC BY-SA 4.0", "Tatoeba", "CC BY 2.0 France", "dictionary-character"] {
        XCTAssertTrue(text.contains(credit), credit)
      }
    }
    let hindi = try XCTUnwrap(CorpusLicenseNotice.hindi.read(resourceDirectory: root.appendingPathComponent("Resources")))
    XCTAssertTrue(hindi.contains("wordfreq/data/small_hi.msgpack.gz"))
    let gujarati = try XCTUnwrap(CorpusLicenseNotice.gujarati.read(resourceDirectory: root.appendingPathComponent("Resources")))
    XCTAssertTrue(gujarati.contains("sentence-fragment"))
    for word in ["ધીરજ", "નોંધપોથી", "પર્ણ", "પુલ", "પ્રયત્ન", "વિરામ", "સરળતા", "હિંમત"] {
      XCTAssertTrue(gujarati.contains(word), word)
    }
  }
}
