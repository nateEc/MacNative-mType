import XCTest
@testable import Typebar

final class AzMnCorpusTests: XCTestCase {
  private let azLegacy = "kitab qələm pəncərə yol işıq körpü səhər kağız bağ bulud sakitlik lampa dağ toxum musiqi masa fikir qeyd iş cəhd dost şəhər dəniz kənd vaxt səs sual cavab ümid gələcək".split(separator: " ").map(String.init)
  private let mnLegacy = "ном цонх зам гэрэл гүүр өглөө цаас цэцэрлэг үүл тайван гэр уул үр хөгжим ширээ санаа тэмдэглэл ажил оролдлого найз хот гол салхи цаг дуу асуулт хариулт найдвар ирээдүй алхам".split(separator: " ").map(String.init)

  func testNativeNoticesIncludeSeparateLicensesAndPinnedMappings() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["python3", root.appendingPathComponent("Scripts/prepare-az-mn-corpora.py").path, "--check-bundled"]
    try process.run(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    for notice in [CorpusLicenseNotice.azerbaijani, .mongolian] {
      let text = try XCTUnwrap(notice.read(resourceDirectory: root.appendingPathComponent("Resources")))
      for credit in ["English Wiktionary contributors", "Tatoeba", "CC BY-SA 4.0", "CC BY 2.0 France", "source", "Unicode"] {
        XCTAssertTrue(text.contains(credit), credit)
      }
    }
  }

  func testLongestStandaloneTargetsKeepTheirSpellingInResultAndRepeat() throws {
    for language in [TypingLanguage.azerbaijani, .azerbaijani1k, .mongolian, .mongolian10k] {
      let words = language.ownedPracticeLexicon()
      let target = try XCTUnwrap(words.filter { $0.allSatisfy(\.isLetter) }.max { $0.utf16.count < $1.utf16.count })
      let index = try XCTUnwrap(words.firstIndex(of: target))
      var session = TestSessionFactory.make(configuration: .words(1, language: language), nextRandomWordIndex: { index })
      XCTAssertEqual(session.prompt, target)
      session.insertBatch(target, at: Date(timeIntervalSinceReferenceDate: 925_300_000))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.errors, 0)
      let result = try XCTUnwrap(session.result())
      XCTAssertEqual(result.prompt, target)
      XCTAssertEqual(try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(result)), result)
      XCTAssertEqual(session.repeatedAttempt().prompt, target)
    }
  }

  func testFourPoolsKeepTypingAlphabetsCountsAndOldVocabulary() {
    for (language, count, keys, legacy) in [
      (TypingLanguage.azerbaijani, 199, "abcdefghijklmnopqrstuvxyzçöüğışə", azLegacy),
      (.azerbaijani1k, 989, "abcdefghijklmnopqrstuvxyzçöüğışə\u{0307}", azLegacy),
      (.mongolian, 1085, "абвгдежзийклмнопрстуфхцчшыьэюяёүө", mnLegacy),
      (.mongolian10k, 9219, "ЁАБВГДЕЖЗИЛМНОПРСТУХЦЧШЭЮЯабвгдежзийклмнопрстуфхцчшъыьэюяёҮүӨө", mnLegacy),
    ] {
      let words = language.ownedPracticeLexicon()
      XCTAssertEqual(words.count, count, language.rawValue)
      XCTAssertEqual(Set(words).count, count)
      XCTAssertEqual(Set(words.joined().unicodeScalars), Set(keys.unicodeScalars))
      XCTAssertTrue(Set(legacy).isSubset(of: Set(words)))
      XCTAssertTrue(words.allSatisfy { $0 == $0.precomposedStringWithCanonicalMapping && !$0.contains(where: \.isWhitespace) })
      XCTAssertFalse(words.contains { $0.hasPrefix("qx") || $0.hasPrefix("əx") || $0.contains("ꙮ") || $0.contains("ӿ") })
    }
    let az = TypingLanguage.azerbaijani.ownedPracticeLexicon()
    let large = TypingLanguage.azerbaijani1k.ownedPracticeLexicon()
    XCTAssertEqual(az.filter { !$0.unicodeScalars.allSatisfy(\.isASCII) }.count, 126)
    XCTAssertEqual(large.filter { !$0.unicodeScalars.allSatisfy(\.isASCII) }.count, 668)
    XCTAssertEqual(Set(az.filter { !(3...6).contains($0.utf16.count) }), Set(azLegacy.filter { !(3...6).contains($0.utf16.count) }))
    XCTAssertEqual(Set(large.filter { !(2...7).contains($0.utf16.count) }), Set(azLegacy.filter { !(2...7).contains($0.utf16.count) }))
    let mn = TypingLanguage.mongolian.ownedPracticeLexicon()
    let bigger = TypingLanguage.mongolian10k.ownedPracticeLexicon()
    XCTAssertEqual(mn.map(\.utf16.count).min(), 2)
    XCTAssertEqual(mn.map(\.utf16.count).max(), 15)
    XCTAssertEqual(bigger.map(\.utf16.count).min(), 1)
    XCTAssertEqual(bigger.map(\.utf16.count).max(), 18)
    XCTAssertEqual(bigger.filter { $0.contains(where: \.isUppercase) }.count, 897)
    XCTAssertTrue(Set(mn).isSubset(of: Set(bigger)))
  }

  func testCombiningDotTargetsKeepScalarIdentityInNormalAndLazyInput() throws {
    let words = TypingLanguage.azerbaijani1k.ownedPracticeLexicon()
    let targets = words.filter { $0.unicodeScalars.contains("\u{0307}") }
    XCTAssertEqual(targets.count, 2)
    for target in targets {
      XCTAssertTrue(target.hasPrefix("i\u{0307}"))
      XCTAssertEqual(target.utf16.count, target.count + 1)
      let index = try XCTUnwrap(words.firstIndex(of: target))
      for lazy in [false, true] {
        let config = TestConfiguration.words(1, language: .azerbaijani1k).with(modifiers: lazy ? [.lazyLatin] : [])
        var session = TestSessionFactory.make(configuration: config, nextRandomWordIndex: { index })
        XCTAssertTrue(session.prompt.unicodeScalars.contains("\u{0307}"))
        if !lazy { XCTAssertEqual(Array(session.prompt.utf16), Array(target.utf16)) }
        let expected = session.prompt
        session.insertBatch(expected, at: Date(timeIntervalSinceReferenceDate: 925_300_000))
        XCTAssertEqual(session.outcome, .completed)
        XCTAssertEqual(session.errors, 0)
        let result = try XCTUnwrap(session.result())
        XCTAssertEqual(Array(result.prompt.utf16), Array(expected.utf16))
        XCTAssertEqual(try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(result)), result)
        XCTAssertEqual(Array(session.repeatedAttempt().prompt.utf16), Array(expected.utf16))
      }
    }
  }

  func testCyrillicSourceCaseIsPreservedWithEitherPunctuationSetting() throws {
    let words = TypingLanguage.mongolian10k.ownedPracticeLexicon()
    let upper = words.filter { $0.contains(where: \.isUppercase) }
    XCTAssertEqual(upper.count, 897)
    for target in Array(upper.prefix(2)) + Array(upper.suffix(2)) {
      let index = try XCTUnwrap(words.firstIndex(of: target))
      for punctuation in [false, true] {
        let session = TestSessionFactory.make(configuration: .words(1, language: .mongolian10k,
          contentOptions: .init(includePunctuation: punctuation)), nextRandomWordIndex: { index }, nextRandomContentUnit: { 0.5 })
        XCTAssertTrue(session.prompt.hasPrefix(target), session.prompt)
      }
    }
  }

  func testOldIndexedTargetsAreNotRewrittenInResultsOrReplay() throws {
    for (language, target) in [(TypingLanguage.azerbaijani1k, "qxold"), (.mongolian10k, "ӿабв")] {
      var session = TypingSession(configuration: .words(1, language: language), prompt: target, sourceFields: [target])
      session.insertBatch(target, at: Date(timeIntervalSinceReferenceDate: 925_300_000))
      let result = try XCTUnwrap(session.result())
      XCTAssertEqual(result.prompt, target)
      XCTAssertEqual(session.repeatedAttempt().prompt, target)
      XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: result.elapsedDuration), target)
    }
  }
}
