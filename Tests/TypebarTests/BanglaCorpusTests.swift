import XCTest
@testable import Typebar

final class BanglaCorpusTests: XCTestCase {
  private let legacy = ["আলো", "নদী", "পাতা", "ঘুড়ি", "মেঘ", "বই", "কলম", "জানালা", "সেতু", "বাগান", "সকাল", "সুর", "চিঠি", "পথ", "তারা", "ছবি", "প্রশ্ন", "উত্তর", "কল্পনা", "বিরতি", "সাহস", "ধৈর্য", "ছন্দ", "যাত্রা"]
  private let letterKeys = "।অআইঈউঊঋএঐওঔকখগঘঙচছজঝঞটঠডঢণতথদধনপফবভমযরলশষসহ়্ৎ০১২৩৪৫৬৭৮৯৳"
  private func marked(_ word: String) -> Bool {
    word.unicodeScalars.contains {
      switch $0.properties.generalCategory {
      case .nonspacingMark, .spacingMark, .enclosingMark: true
      default: false
      }
    }
  }

  func testLiteralWordPoolsRetainFullLengthsKeysAndPunctuationCategories() {
    // Reference facts are complete aggregate distributions, never word values.
    for (language, histogram, keys, categories, maxG) in [
      (TypingLanguage.bangla, [1: 3, 2: 23, 3: 60, 4: 64, 5: 29, 6: 15, 7: 5], "।ঁংঃঅআইউএঐওকখগচছজঝটঠডণতথদধনপফবভমযরলশষসহ়ািীুেো্", ["plain/true": 1, "mark/false": 176, "plain/false": 22], 4),
      (.bangla10k, [1: 5, 2: 211, 3: 866, 4: 1624, 5: 2190, 6: 1797, 7: 1300, 8: 831, 9: 454, 10: 242, 11: 116, 12: 59, 13: 23, 14: 11, 15: 2, 16: 3], "-.।ঁংঃঅআইঈউঊঋএঐওঔকখগঘঙচছজঝঞটঠডঢণতথদধনপফবভমযরলশষসহ়ািীুূৃেৈোৌ্ৎ", ["plain/true": 1, "mark/false": 9378, "plain/false": 341, "mark/true": 14], 8),
    ] {
      let words = language.ownedPracticeLexicon()
      XCTAssertEqual(words.count, histogram.values.reduce(0, +))
      XCTAssertEqual(Set(words).count, words.count)
      XCTAssertEqual(Dictionary(grouping: words, by: { $0.utf16.count }).mapValues(\.count), histogram)
      XCTAssertEqual(Set(words.joined().unicodeScalars), Set((keys + legacy.joined()).unicodeScalars))
      XCTAssertTrue(Set(legacy).isSubset(of: Set(words)))
      XCTAssertEqual(words.map(\.count).min(), 1)
      XCTAssertEqual(words.map(\.count).max(), maxG)
      XCTAssertTrue(words.allSatisfy { $0 == $0.precomposedStringWithCanonicalMapping && !$0.contains(where: \.isWhitespace) })
      XCTAssertFalse(words.contains { $0.contains("ৱ") })
      XCTAssertEqual(Dictionary(grouping: words, by: { (marked($0) ? "mark" : "plain") + "/" + String($0.contains(where: \.isPunctuation)) }).mapValues(\.count), categories)
    }
  }

  func testLetterPoolCoversAllDigitsAndCanonicalNuktaWithoutArtificialGlyphs() throws {
    let words = TypingLanguage.banglaLetters.ownedPracticeLexicon()
    XCTAssertEqual(words.count, 62)
    XCTAssertEqual(Set(words).count, 62)
    XCTAssertEqual(Set(words.joined().unicodeScalars), Set(letterKeys.unicodeScalars))
    XCTAssertEqual(Dictionary(grouping: words, by: { $0.utf16.count }).mapValues(\.count), [1: 56, 2: 3, 3: 2, 4: 1])
    XCTAssertEqual(Dictionary(grouping: words, by: \.count).mapValues(\.count), [1: 61, 2: 1])
    XCTAssertTrue(words.allSatisfy { Array($0.utf16) == Array($0.precomposedStringWithCanonicalMapping.utf16) })
    for target in ["০", "১", "২", "৩", "৪", "৫", "৬", "৭", "৮", "৯", "ড়", "ঢ়", "য়", "কর্ম", "৳", "।"] {
      let index = try XCTUnwrap(words.firstIndex(of: target), "missing \(target)")
      var session = TestSessionFactory.make(configuration: .words(1, language: .banglaLetters), nextRandomWordIndex: { index })
      XCTAssertEqual(Array(session.prompt.utf16), Array(target.utf16))
      session.insertBatch(target, at: Date(timeIntervalSinceReferenceDate: 925_700_000))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.errors, 0)
      XCTAssertEqual(Array(try XCTUnwrap(session.result()).prompt.utf16), Array(target.utf16))
      XCTAssertEqual(Array(session.repeatedAttempt().prompt.utf16), Array(target.utf16))
    }
  }

  func testDandaHyphensAndAbbreviationsRemainLiteralInActualFactoryAndResults() throws {
    for language in [TypingLanguage.bangla, .bangla10k] {
      let words = language.ownedPracticeLexicon(), targets = words.filter { $0.contains(where: \.isPunctuation) }
      XCTAssertEqual(targets.count, language == .bangla ? 1 : 15)
      XCTAssertTrue(targets.contains("।"))
      for target in targets {
        let index = try XCTUnwrap(words.firstIndex(of: target))
        var session = TestSessionFactory.make(configuration: .words(1, language: language), nextRandomWordIndex: { index })
        XCTAssertEqual(session.prompt, target)
        session.insertBatch(target, at: Date(timeIntervalSinceReferenceDate: 925_700_000))
        XCTAssertEqual(session.outcome, .completed)
        XCTAssertEqual(session.errors, 0)
        XCTAssertEqual(session.result()?.prompt, target)
        XCTAssertEqual(session.repeatedAttempt().prompt, target)
      }
    }
  }

  func testLongestAndVowelSequencesKeepRawTargetUnitsThroughResults() throws {
    for language in [TypingLanguage.bangla, .bangla10k] {
      let entries = language.ownedPracticeLexicon(), words = entries.sorted { $0.utf16.count < $1.utf16.count }
      let targets: [String] = [try XCTUnwrap(words.last), try XCTUnwrap(words.first(where: { word in
        word.unicodeScalars.contains(where: { $0.value == 0x09BF })
      }), "missing Bengali vowel sign I")]
      for target in targets {
        let index = try XCTUnwrap(entries.firstIndex(of: target))
        var session = TestSessionFactory.make(configuration: .words(1, language: language), nextRandomWordIndex: { index })
        XCTAssertEqual(Array(session.prompt.utf16), Array(target.utf16))
        session.insertBatch(target, at: Date(timeIntervalSinceReferenceDate: 925_700_000))
        let result = try XCTUnwrap(session.result())
        XCTAssertEqual(session.outcome, .completed)
        XCTAssertEqual(session.errors, 0)
        XCTAssertEqual(try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(result)), result)
        XCTAssertEqual(Array(result.prompt.utf16), Array(target.utf16))
      }
    }
  }

  func testStoredSyntheticAndRetiredLetterTargetsKeepTheirOriginalEncoding() throws {
    for (language, target) in [(TypingLanguage.bangla10k, "ৱকা"), (.banglaLetters, "\u{09DC}"), (.banglaLetters, "\u{09DD}"), (.banglaLetters, "\u{09DF}"), (.banglaLetters, "ঌ"), (.banglaLetters, "ৠ"), (.banglaLetters, "ৡ"), (.banglaLetters, "কা"), (.banglaLetters, "গি"), (.banglaLetters, "সু"), (.banglaLetters, "ক্ষা")] {
      var session = TypingSession(configuration: .words(1, language: language), prompt: target, sourceFields: [target])
      session.insertBatch(target, at: Date(timeIntervalSinceReferenceDate: 925_700_000))
      let result = try XCTUnwrap(session.result())
      XCTAssertEqual(Array(result.prompt.utf16), Array(target.utf16))
      XCTAssertEqual(Array(session.repeatedAttempt().prompt.utf16), Array(target.utf16))
      XCTAssertEqual(Array(TypingReplay.typedText(events: result.replayEvents, through: result.elapsedDuration).utf16), Array(target.utf16))
    }
  }

  func testPinnedProvenanceAndUnicodeLicenseChoicesAreReadable() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["python3", root.appendingPathComponent("Scripts/prepare-bangla-corpus.py").path, "--check-bundled"]
    try process.run(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let text = try XCTUnwrap(CorpusLicenseNotice.bangla.read(resourceDirectory: root.appendingPathComponent("Resources")))
    for credit in ["English Wiktionary contributors", "Tatoeba Bengali contributors", "CC BY-SA 4.0", "CC BY 2.0 France", "Unicode License V3", "UnicodeNotice.txt", "wordfreq/data/large_bn.msgpack.gz", "ছন্দ", "বিরতি", "সুর"] {
      XCTAssertTrue(text.contains(credit), credit)
    }
    let rows = try String(contentsOf: root.appendingPathComponent("Resources/BanglaCorpusSources.txt"), encoding: .utf8)
    XCTAssertTrue(rows.contains("কর্ম\tdictionary\tকর্ম\tকর্ম\tnoun"))
    XCTAssertTrue(rows.contains("U+09A1,U+09BC"))
    XCTAssertTrue(rows.contains("U+09EF"))
  }
}
