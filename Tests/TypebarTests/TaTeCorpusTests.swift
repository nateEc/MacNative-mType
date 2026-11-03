import XCTest
@testable import Typebar

final class TaTeCorpusTests: XCTestCase {
  private let tamilLegacy = ["புத்தகம்", "பேனா", "சாளரம்", "பாதை", "ஒளி", "பாலம்", "காலை", "காகிதம்", "தோட்டம்", "மேகம்", "அமைதி", "விளக்கு", "மலை", "விதை", "இசை", "மேசை", "சிந்தனை", "குறிப்பு", "யோசனை", "முயற்சி", "தூரம்", "அடி", "பொறுமை", "சமநிலை"]
  private let oldSeeds = ["அகா", "நீளமானபயிற்சி", "இசை நடை"]
  private let teluguLegacy = ["పుస్తకం", "కలం", "కిటికీ", "దారి", "వెలుగు", "వంతెన", "ఉదయం", "కాగితం", "తోట", "మేఘం", "శాంతి", "దీపం", "కొండ", "విత్తనం", "సంగీతం", "బల్ల", "ఆలోచన", "గమనిక", "ఊహ", "ప్రయత్నం", "దూరం", "అడుగు", "సహనం", "సమతుల్యం"]
  // Only aggregate counts and character sets come from the pinned reference.
  private let facts: [(TypingLanguage, Int, Int, Int, Int, String, Int)] = [
    (.tamil, 366, 2, 17, 10, "அஆஇஉஊஎஏஒஓகஙசஜடணதநனபமயரறலளழவஷஸாிீுூெேைொோ்", 363),
    (.tamil1k, 951, 1, 19, 11, "ஃஅஆஇஈஉஊஎஏஐஒஓகஙசஜஞடணதநனபமயரறலளழவஷஸாிீுூெேைொோௌ்", 942),
    (.tamilOld, 460, 3, 13, 8, " அஆஇஉஊஎஏஐஒஓஔகஙசஜஞடணதநனபமயரறலளழவஷஸாிீுூெேைொோ்", 459),
    (.telugu, 201, 1, 15, 8, " ంఅఆఇఈఉఎఏఒకఖగఘచజటఠడణతథదధనపఫబభమయరలళవశషసహాిీుూెేైొోౌ్", 193),
    (.telugu1k, 901, 1, 18, 9, " ంఅఆఇఈఉఊఎఏఐఒఓకఖగఘచజటఠడణతథదధనపఫబభమయరలళవశషసహాిీుూృెేైొోౌ్", 879),
  ]
  private func marked(_ word: String) -> Bool {
    word.unicodeScalars.contains {
      switch $0.properties.generalCategory {
      case .nonspacingMark, .spacingMark, .enclosingMark: true
      default: false
      }
    }
  }

  func testFivePoolsRetainLiteralKeysCombiningMarksAndOldContent() {
    for (language, count, minimum, maximum, maxG, keys, marks) in facts {
      let words = language.ownedPracticeLexicon()
      let legacy = language == .telugu || language == .telugu1k ? teluguLegacy : tamilLegacy
      XCTAssertEqual(words.count, count, language.rawValue)
      XCTAssertEqual(Set(words).count, count)
      XCTAssertEqual(words.map(\.utf16.count).min(), minimum)
      XCTAssertEqual(words.map(\.utf16.count).max(), maximum)
      XCTAssertEqual(words.map(\.count).min(), language == .tamilOld ? 2 : 1)
      XCTAssertEqual(words.map(\.count).max(), maxG)
      XCTAssertEqual(Set(words.joined().unicodeScalars), Set((keys + legacy.joined()).unicodeScalars))
      XCTAssertEqual(words.filter(marked).count, marks)
      XCTAssertTrue(Set(legacy).isSubset(of: Set(words)))
      if language == .tamilOld { XCTAssertTrue(Set(oldSeeds).isSubset(of: Set(words))) }
      XCTAssertTrue(words.allSatisfy { $0 == $0.precomposedStringWithCanonicalMapping })
      XCTAssertFalse(words.contains { $0.contains("ஶ") || $0.contains("ఴ") })
    }
  }

  func testPhraseCategoriesAndActualFactoryWordSlotsRemainIntact() throws {
    for (language, categories) in [(TypingLanguage.tamilOld, ["mark spaces=0": 458, "plain spaces=0": 1, "mark spaces=1": 1]), (.telugu, ["mark spaces=0": 192, "plain spaces=0": 8, "mark spaces=1": 1]), (.telugu1k, ["mark spaces=0": 874, "plain spaces=0": 22, "mark spaces=1": 4, "mark spaces=2": 1])] {
      let words = language.ownedPracticeLexicon()
      for (key, count) in categories {
        XCTAssertEqual(words.filter { (marked($0) ? "mark" : "plain") + " spaces=" + String($0.filter { $0 == " " }.count) == key }.count, count, language.rawValue + key)
      }
      XCTAssertFalse(words.contains { $0.hasPrefix(" ") || $0.hasSuffix(" ") || $0.contains("  ") })
      for target in words.filter({ $0.contains(" ") }) {
        let index = try XCTUnwrap(words.firstIndex(of: target))
        for limit in 1...target.split(separator: " ").count {
          let expected = target.split(separator: " ").prefix(limit).joined(separator: " ")
          var session = TestSessionFactory.make(configuration: .words(limit, language: language), nextRandomWordIndex: { index })
          XCTAssertEqual(session.prompt, expected)
          session.insertBatch(expected, at: Date(timeIntervalSinceReferenceDate: 925_600_000))
          XCTAssertEqual(session.outcome, .completed)
          XCTAssertEqual(session.errors, 0)
          XCTAssertEqual(session.result()?.prompt, expected)
          XCTAssertEqual(session.repeatedAttempt().prompt, expected)
        }
      }
    }
  }

  func testShortestLongestAndVowelSequencesKeepRawUnitsThroughResults() throws {
    for (language, _, _, _, _, _, _) in facts {
      let entries = language.ownedPracticeLexicon(), words = entries.sorted { $0.utf16.count < $1.utf16.count }
      let vowel = language == .telugu || language == .telugu1k ? "ి" : "ி"
      for target in [try XCTUnwrap(words.first), try XCTUnwrap(words.last), try XCTUnwrap(words.first { $0.unicodeScalars.contains { String($0) == vowel } }, "\(language.rawValue): missing scalar \(vowel)")] {
        let index = try XCTUnwrap(entries.firstIndex(of: target))
        var session = TestSessionFactory.make(configuration: .words(target.split(separator: " ").count, language: language), nextRandomWordIndex: { index })
        XCTAssertEqual(Array(session.prompt.utf16), Array(target.utf16))
        session.insertBatch(target, at: Date(timeIntervalSinceReferenceDate: 925_600_000))
        XCTAssertEqual(session.outcome, .completed)
        XCTAssertEqual(session.errors, 0)
        let result = try XCTUnwrap(session.result())
        XCTAssertEqual(result.prompt, target)
        XCTAssertEqual(try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(result)), result)
        XCTAssertEqual(session.repeatedAttempt().prompt, target)
      }
    }
  }

  func testHistoricalTargetsAreNotRewrittenByNewVocabulary() throws {
    for (language, target) in [(TypingLanguage.tamil1k, "ஶகா"), (.telugu1k, "ఴకా"), (.tamilOld, "அகம்ஃ")] {
      var session = TypingSession(configuration: .words(1, language: language), prompt: target, sourceFields: [target])
      session.insertBatch(target, at: Date(timeIntervalSinceReferenceDate: 925_600_000))
      let result = try XCTUnwrap(session.result())
      XCTAssertEqual(result.prompt, target)
      XCTAssertEqual(session.repeatedAttempt().prompt, target)
      XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: result.elapsedDuration), target)
    }
  }

  func testPinnedSourcesCharacterEntriesAndNativeNoticesAreReadable() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["python3", root.appendingPathComponent("Scripts/prepare-ta-te-corpora.py").path, "--check-bundled"]
    try process.run(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    for notice in [CorpusLicenseNotice.tamil, .telugu] {
      let text = try XCTUnwrap(notice.read(resourceDirectory: root.appendingPathComponent("Resources")))
      for credit in ["English Wiktionary contributors", "Tatoeba", "CC BY-SA 4.0", "CC BY 2.0 France", "dictionary-character"] {
        XCTAssertTrue(text.contains(credit), credit)
      }
    }
    let tamil = try XCTUnwrap(CorpusLicenseNotice.tamil.read(resourceDirectory: root.appendingPathComponent("Resources")))
    XCTAssertTrue(tamil.contains("wordfreq/data/small_ta.msgpack.gz"))
    for word in oldSeeds { XCTAssertTrue(tamil.contains(word), word) }
    let telugu = try XCTUnwrap(CorpusLicenseNotice.telugu.read(resourceDirectory: root.appendingPathComponent("Resources")))
    XCTAssertTrue(telugu.contains("sentence-fragment"))
    XCTAssertTrue(telugu.contains("గమనిక"))
    XCTAssertTrue(telugu.contains("సమతుల్యం"))
  }
}
