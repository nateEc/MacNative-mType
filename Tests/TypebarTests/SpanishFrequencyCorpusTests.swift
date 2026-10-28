import XCTest
import CryptoKit
@testable import Typebar

final class SpanishFrequencyCorpusTests: XCTestCase {
  func testSpanish10kContainsRealVocabularyProperNamesAndAnOwnedCompound() {
    let words = TypingLanguage.spanish10k.ownedPracticeWords()
    XCTAssertEqual(words.count, 9_990); XCTAssertEqual(Set(words).count, 9_990)
    XCTAssertFalse(words.contains { $0.lowercased().hasPrefix("wx") })
    XCTAssertTrue(words.contains("porque")); XCTAssertTrue(words.contains("también"))
    XCTAssertTrue(words.contains("España")); XCTAssertTrue(words.contains("México"))
    XCTAssertEqual(words.last, "teórico-práctico")
  }

  func testSpanish10kFactoryRetainsTheSourceRedrawLimitFallbackForACompound() {
    var session = TestSessionFactory.make(configuration: .words(1, language: .spanish10k), nextRandomWordIndex: { 9_989 })
    XCTAssertEqual(session.prompt, "teórico-práctico")
    session.insertBatch(session.prompt, at: Date(timeIntervalSince1970: 10))
    XCTAssertEqual(session.outcome, .completed); XCTAssertEqual(session.errors, 0)
    XCTAssertEqual(session.repeatedAttempt().prompt, "teórico-práctico")
  }

  func testSpanish1kExistingDataDoesNotDriftWhenTheLargerPoolChanges() {
    let body = TypingLanguage.spanish1k.ownedPracticeWords().joined(separator: "\n") + "\n"
    XCTAssertEqual(SHA256.hash(data: Data(body.utf8)).map { String(format: "%02x", $0) }.joined(),
      "19d1313ce798ffcc13d942604a8cb37779da08c0e57ea2303179a0b750d42a0c")
  }

  func testSpanish10kFactoryLowercasesASCIICapitalsWithoutPunctuation() throws {
    let words = TypingLanguage.spanish10k.ownedPracticeWords()
    let index = try XCTUnwrap(words.firstIndex(of: "México"))
    var session = TestSessionFactory.make(configuration: .words(1, language: .spanish10k), nextRandomWordIndex: { index })
    XCTAssertEqual(session.prompt, "méxico"); XCTAssertEqual(session.nextExpectedCharacter, "m")
    session.insertBatch(session.prompt, at: Date(timeIntervalSince1970: 10))
    XCTAssertEqual(session.outcome, .completed); XCTAssertEqual(session.errors, 0)
    XCTAssertEqual(session.repeatedAttempt().prompt, "méxico")
  }

  func testSpanish10kLongAttemptGrowsAcrossTheTailAndRepeatsCapturedWords() {
    let words = TypingLanguage.spanish10k.ownedPracticeWords()
    // Punctuation-off generation lowercases ASCII capitals, including proper
    // names that random continuation may select after the fixed opening.
    let ownedTargets = Set(words.map { $0.lowercased() })
    var index = 9_900
    var session = TestSessionFactory.make(configuration: .words(153, language: .spanish10k),
      nextRandomWordIndex: { defer { index += 1 }; return index % words.count })
    let opening = session.prompt
    XCTAssertEqual(opening.split(separator: " ").first.map(String.init), words[9_900])
    // An advancing draw skips punctuation-bearing entries before admitting a word.
    XCTAssertFalse(opening.contains("teórico-práctico"))
    session.insert(session.prompt, at: Date(timeIntervalSince1970: 10))
    XCTAssertEqual(session.completedWordCount, 100); XCTAssertEqual(session.outcome, .active)
    session.insert(String(session.prompt.dropFirst(session.typed.count)), at: Date(timeIntervalSince1970: 11))
    XCTAssertEqual(session.completedWordCount, 153); XCTAssertEqual(session.outcome, .completed); XCTAssertEqual(session.errors, 0)
    XCTAssertEqual(session.prompt.split(separator: " ").map(String.init).filter { !ownedTargets.contains($0) }, [])
    var replay = session.repeatedAttempt(); XCTAssertEqual(replay.prompt, opening)
    replay.insert(opening, at: Date(timeIntervalSince1970: 12))
    replay.insert(String(replay.prompt.dropFirst(replay.typed.count)), at: Date(timeIntervalSince1970: 13))
    XCTAssertEqual(replay.outcome, .completed); XCTAssertEqual(replay.prompt, session.prompt); XCTAssertEqual(replay.errors, 0)
  }

  func testLegacySpanish10kPromptScoresAndReplayRemainUnchanged() throws {
    let prompt = "wxarcoa wxbosqueb-"
    let result = CompletedTestResult(id: UUID(), configuration: .words(2, language: .spanish10k),
      outcome: .completed, startedAt: Date(timeIntervalSince1970: 1), finishedAt: Date(timeIntervalSince1970: 5),
      typedCharacterCount: prompt.count, correctCharacterCount: prompt.count, errorCount: 0,
      wpm: 30, rawWpm: 30, accuracy: 100, prompt: prompt,
      replayEvents: [.init(offset: 1, kind: .insert, text: prompt)])
    let restored = try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(result))
    XCTAssertEqual(restored.configuration, result.configuration); XCTAssertEqual(restored.prompt, prompt)
    XCTAssertEqual(restored.replayEvents, result.replayEvents); XCTAssertEqual(restored.wpm, result.wpm)
    XCTAssertEqual(TypingReplay.typedText(events: restored.replayEvents, through: 1), prompt)
  }

  func testSpanish1kUsesObservedFrequencyTokensInsteadOfMarkerStrings() {
    let words = TypingLanguage.spanish1k.ownedPracticeWords()
    XCTAssertEqual(words.count, 998)
    XCTAssertEqual(Set(words).count, 998)
    XCTAssertEqual(Array(words.prefix(5)), ["de", "la", "que", "el", "en"])
    XCTAssertFalse(words.contains { $0.hasPrefix("zq") })
    XCTAssertTrue(words.contains("porque"))
    XCTAssertTrue(words.contains("también"))
    XCTAssertFalse(words.contains("tambien"))
    XCTAssertFalse(words.contains("the"))
    let alphabet = Set("abcdefghijklmnopqrstuvwxyzáéíóúüñ".unicodeScalars)
    XCTAssertTrue(words.allSatisfy {
      $0 == $0.precomposedStringWithCanonicalMapping && $0.unicodeScalars.allSatisfy(alphabet.contains)
    })
  }

  func testActualFactorySelectsTheLastFrequencyTokenAndRepeatsItsCapturedTarget() {
    let words = TypingLanguage.spanish1k.ownedPracticeWords()
    var session = TestSessionFactory.make(configuration: .words(1, language: .spanish1k),
      nextRandomWordIndex: { 997 })
    XCTAssertEqual(session.prompt, words[997])
    session.insertBatch(session.prompt, at: Date(timeIntervalSince1970: 10))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.repeatedAttempt().prompt, words[997])
  }

  func testLegacySyntheticHistoryDoesNotGetReplacedWithNewVocabulary() throws {
    let prompt = "zqfarocñ zqjardindñ"
    let result = CompletedTestResult(id: UUID(), configuration: .words(2, language: .spanish1k),
      outcome: .completed, startedAt: Date(timeIntervalSince1970: 1),
      finishedAt: Date(timeIntervalSince1970: 5), typedCharacterCount: prompt.count,
      correctCharacterCount: prompt.count, errorCount: 0, wpm: 30, rawWpm: 30,
      accuracy: 100, prompt: prompt, replayEvents: [.init(offset: 1, kind: .insert, text: prompt)])
    let restored = try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(result))
    XCTAssertEqual(restored.configuration, result.configuration)
    XCTAssertEqual(restored.prompt, prompt)
    XCTAssertEqual(restored.replayEvents, result.replayEvents)
    XCTAssertEqual(restored.wpm, result.wpm)
    XCTAssertEqual(TypingReplay.typedText(events: restored.replayEvents, through: 1), prompt)
  }

  func testLongFiniteAttemptContinuesWithRealTokensAndRepeatsWithoutResampling() {
    let words = TypingLanguage.spanish1k.ownedPracticeWords()
    let owned = Set(words)
    var index = 0
    var session = TestSessionFactory.make(configuration: .words(153, language: .spanish1k),
      nextRandomWordIndex: { defer { index += 1 }; return index % words.count })
    let opening = session.prompt
    session.insert(session.prompt, at: Date(timeIntervalSince1970: 10))
    XCTAssertEqual(session.completedWordCount, 100)
    XCTAssertEqual(session.outcome, .active)
    session.insert(String(session.prompt.dropFirst(session.typed.count)), at: Date(timeIntervalSince1970: 11))
    XCTAssertEqual(session.completedWordCount, 153)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
    XCTAssertTrue(session.prompt.split(separator: " ").allSatisfy { owned.contains(String($0)) })
    var replay = session.repeatedAttempt()
    XCTAssertEqual(replay.prompt, opening)
    replay.insert(opening, at: Date(timeIntervalSince1970: 12))
    XCTAssertEqual(replay.prompt, session.prompt)
    replay.insert(String(replay.prompt.dropFirst(replay.typed.count)), at: Date(timeIntervalSince1970: 13))
    XCTAssertEqual(replay.outcome, .completed)
    XCTAssertEqual(replay.completedWordCount, 153)
    XCTAssertEqual(replay.errors, 0)
  }
}
