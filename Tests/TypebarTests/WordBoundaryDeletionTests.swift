import AppKit
import XCTest
@testable import Typebar

final class WordBoundaryDeletionTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 873_300_000)
  private let aliases = [("e\u{301}", "é"), ("é", "e\u{301}"),
    ("a\u{301}\u{323}", "a\u{323}\u{301}"), ("\u{212B}", "Å")]

  private func config(_ rules: InputRules = .init(), noSpace: Bool = false) -> TestConfiguration {
    .init(mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal,
      rules: rules, modifiers: noSpace ? [.noSpaces] : [])
  }

  private func joined(_ rules: InputRules = .init()) -> TypingSession {
    TypingSession(configuration: config(rules, noSpace: true), prompt: "abcdtail",
      noSpaceWordEndIndices: [2, 4, 8], noSpaceTargetWords: ["ab", "cd", "tail"])
  }

  private func delete(_ wholeWord: Bool, from attempt: inout TypingSession, at date: Date) {
    if wholeWord { attempt.deleteWordBackward(at: date) }
    else { attempt.deleteBackward(at: date) }
  }

  func testCanonicalAliasCanBeReopenedWithBackspace() {
    for (target, input) in aliases {
      var attempt = TypingSession(configuration: config(), prompt: target + " tail")
      attempt.insertBatch(input + " ", at: start)
      XCTAssertEqual(attempt.completedWordCount, 1)
      attempt.deleteBackward(at: start.addingTimeInterval(1))
      XCTAssertEqual(Array(attempt.typed.utf16), Array(input.utf16))
      XCTAssertEqual(attempt.completedWordCount, 0)
      XCTAssertEqual(attempt.errors, 1)
    }
  }

  func testCanonicalAliasCanBeClearedWithWordBackward() {
    for (target, input) in aliases {
      var attempt = TypingSession(configuration: config(), prompt: target + " tail")
      attempt.insertBatch(input + " ", at: start)
      attempt.deleteWordBackward(at: start.addingTimeInterval(1))
      XCTAssertEqual(attempt.typed, "")
      XCTAssertEqual(attempt.completedWordCount, 0)
      XCTAssertLessThan(attempt.preciseAccuracy, 100)
    }
  }

  func testExactCorrectCommittedWordsRemainProtected() throws {
    for wholeWord in [false, true] {
      for (target, _) in aliases {
        var attempt = TypingSession(configuration: config(), prompt: target + " tail")
        attempt.insertBatch(target + " ", at: start)
        attempt.deleteBackward(at: start.addingTimeInterval(1))
        delete(wholeWord, from: &attempt, at: start.addingTimeInterval(2))
        XCTAssertEqual(Array(attempt.typed.utf16), Array((target + " ").utf16))
        attempt.bailOut(at: start.addingTimeInterval(3))
        XCTAssertFalse(try XCTUnwrap(attempt.result()).replayEvents.contains { $0.kind == .delete })
      }
    }
  }

  func testCorrectNoSpaceBoundaryProtectsItsPreviousWord() {
    for wholeWord in [false, true] {
      var attempt = joined()
      attempt.insertBatch("ab", at: start)
      delete(wholeWord, from: &attempt, at: start.addingTimeInterval(1))
      XCTAssertEqual(attempt.typed, "ab")
      XCTAssertEqual(attempt.completedWordCount, 1)
      XCTAssertEqual(attempt.nextExpectedCharacter, "c")
    }
  }

  func testIncorrectNoSpaceBoundaryCanBeReopenedOneLetterAtATime() {
    var attempt = joined()
    attempt.insertBatch("abcx", at: start)
    attempt.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.typed, "abc")
    XCTAssertEqual(attempt.completedWordCount, 1)
    attempt.deleteBackward(at: start.addingTimeInterval(2))
    XCTAssertEqual(attempt.typed, "ab")
    attempt.deleteBackward(at: start.addingTimeInterval(3))
    XCTAssertEqual(attempt.typed, "ab", "The preceding correct word cannot be reopened")
  }

  func testWordBackwardClearsOnlyTheIncorrectPreviousNoSpaceWord() {
    var attempt = joined()
    attempt.insertBatch("abcx", at: start)
    attempt.deleteWordBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.typed, "ab")
    XCTAssertEqual(attempt.completedWordCount, 1)
    XCTAssertEqual(attempt.nextExpectedCharacter, "c")
  }

  func testWordBackwardClearsOnlyTheActiveNoSpaceWord() {
    for rules in [InputRules(), .init(freedomMode: true), .init(confidenceMode: .on)] {
      var attempt = joined(rules)
      attempt.insertBatch("abc", at: start)
      attempt.deleteWordBackward(at: start.addingTimeInterval(1))
      XCTAssertEqual(attempt.typed, "ab")
      XCTAssertEqual(attempt.completedWordCount, 1)
      XCTAssertEqual(attempt.nextExpectedCharacter, "c")
    }
  }

  func testFreedomAllowsReopeningCorrectNoSpaceWordsWithoutClearingOtherWords() {
    var attempt = joined(.init(freedomMode: true))
    attempt.insertBatch("abcd", at: start)
    attempt.deleteWordBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.typed, "ab")
    attempt.deleteWordBackward(at: start.addingTimeInterval(2))
    XCTAssertEqual(attempt.typed, "")
    XCTAssertEqual(attempt.completedWordCount, 0)
  }

  func testConfidenceOnBlocksNoSpaceReopeningButAllowsCurrentWordCorrection() {
    for wholeWord in [false, true] {
      var attempt = joined(.init(confidenceMode: .on))
      attempt.insertBatch("ax", at: start)
      delete(wholeWord, from: &attempt, at: start.addingTimeInterval(1))
      XCTAssertEqual(attempt.typed, "ax")
      var current = joined(.init(confidenceMode: .on))
      current.insert("a", at: start)
      delete(wholeWord, from: &current, at: start.addingTimeInterval(1))
      XCTAssertEqual(current.typed, "")
    }
  }

  func testMaximumConfidenceStillBlocksEveryManualDeletion() {
    for text in ["a", "ax", "abc"] {
      for wholeWord in [false, true] {
        var attempt = joined(.init(confidenceMode: .maximum))
        attempt.insertBatch(text, at: start)
        delete(wholeWord, from: &attempt, at: start.addingTimeInterval(1))
        XCTAssertEqual(attempt.typed, text)
      }
    }
  }

  func testCorrectedNoSpaceWordIsProtectedDespiteHistoricalMistakes() {
    var attempt = joined()
    attempt.insertBatch("ax", at: start)
    attempt.deleteBackward(at: start.addingTimeInterval(1))
    attempt.insert("b", at: start.addingTimeInterval(2))
    XCTAssertTrue(attempt.wordReviews[0].hasInputError)
    attempt.deleteBackward(at: start.addingTimeInterval(3))
    XCTAssertEqual(attempt.typed, "ab")
    XCTAssertLessThan(attempt.preciseAccuracy, 100)
  }

  func testEmptyNoSpaceFieldClearKeepsThePreviousWordProtection() {
    var attempt = TestSessionFactory.make(configuration: .init(mode: .quote, duration: nil,
      wordLimit: nil, difficulty: .normal, rules: .init(), modifiers: [.morseStream]),
      quote: .init(id: "owned-delete-empty", title: "Delete probe", text: "e 中 t",
        language: .english, length: .short))
    attempt.insertBatch("./--", at: start)
    attempt.deleteWordBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.typed, "./")
    attempt.deleteBackward(at: start.addingTimeInterval(2))
    XCTAssertEqual(attempt.typed, "./")
    XCTAssertNil(attempt.nextExpectedCharacter)
  }

  func testFactoryRepeatAndArchiveKeepCorrectedNoSpaceInputAndReplay() throws {
    var attempt = TestSessionFactory.make(configuration: config(noSpace: true),
      quote: .init(id: "owned-delete-quote", title: "Delete probe", text: "ab cd tail",
        language: .english, length: .short))
    let prompt = attempt.prompt
    attempt.insertBatch("abx", at: start)
    attempt.deleteWordBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.typed, "ab")
    attempt.insertBatch("cdtail", at: start.addingTimeInterval(2))
    XCTAssertEqual(attempt.outcome, .completed)
    let result = try XCTUnwrap(attempt.result())
    XCTAssertEqual(result.errorCount, 0)
    XCTAssertLessThan(result.preciseAccuracy, 100)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents,
      through: result.elapsedDuration), "abcdtail")
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [], at: start))
    XCTAssertEqual(archive.results, [result])
    let repeated = attempt.repeatedAttempt()
    XCTAssertEqual(repeated.prompt, prompt)
    XCTAssertEqual(repeated.typed, "")
  }

  @MainActor
  func testUnopenedNativeWordAndCharacterCommandsUseTheSameProtection() {
    var attempt = joined()
    let input = TypingInputView(frame: .zero)
    input.onInsert = { text, forced in attempt.insertBatch(text, forceError: forced, at: self.start) }
    input.onDelete = { attempt.deleteBackward(at: self.start.addingTimeInterval(1)) }
    input.onDeleteWord = { attempt.deleteWordBackward(at: self.start.addingTimeInterval(1)) }
    input.insertText("abc", replacementRange: .init())
    input.doCommand(by: #selector(NSResponder.deleteWordBackward(_:)))
    XCTAssertEqual(attempt.typed, "ab")
    input.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
    XCTAssertEqual(attempt.typed, "ab")
    attempt.synchronizeLiveInputRules(.init(freedomMode: true))
    input.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
    XCTAssertEqual(attempt.typed, "a")
  }

  func testLengthOnlyLegacyNoSpaceMetadataStillBoundsWordDeletion() {
    var attempt = TypingSession(configuration: .words(3, language: .simplifiedChinese),
      prompt: "晨光窗边石桥", noSpaceWordEndIndices: [2, 4, 6])
    attempt.insertBatch("晨光窗", at: start)
    attempt.deleteWordBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.typed, "晨光")
    attempt.deleteBackward(at: start.addingTimeInterval(2))
    XCTAssertEqual(attempt.typed, "晨光")
    attempt.synchronizeLiveInputRules(.init(freedomMode: true))
    attempt.deleteWordBackward(at: start.addingTimeInterval(3))
    XCTAssertEqual(attempt.typed, "")
  }

  func testLiveConfidenceAndFreedomChangesTakeEffectAtTheSameRetainedBoundary() {
    var attempt = joined()
    attempt.insertBatch("ax", at: start)
    attempt.synchronizeLiveInputRules(.init(confidenceMode: .on))
    attempt.deleteWordBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.typed, "ax")
    attempt.synchronizeLiveInputRules(.init(freedomMode: true))
    attempt.deleteWordBackward(at: start.addingTimeInterval(2))
    XCTAssertEqual(attempt.typed, "")
    XCTAssertEqual(attempt.configuration.rules.confidenceMode, .off)
    attempt.insertBatch("ab", at: start.addingTimeInterval(3))
    attempt.synchronizeLiveInputRules(.init())
    attempt.deleteBackward(at: start.addingTimeInterval(4))
    XCTAssertEqual(attempt.typed, "ab")
  }

  func testNoSpaceReopenAfterHundredWordsDoesNotDrawAnotherQuoteTarget() {
    var attempt = TestSessionFactory.make(configuration: config(.init(freedomMode: true), noSpace: true),
      quote: .init(id: "owned-delete-long", title: "Delete long probe",
        text: Array(repeating: "ab", count: 105).joined(separator: " "),
        language: .english, length: .long))
    attempt.insertBatch(String(repeating: "ab", count: 100), at: start)
    XCTAssertEqual(attempt.completedWordCount, 100)
    let generated = attempt.prompt
    attempt.deleteWordBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.typed, String(repeating: "ab", count: 99))
    XCTAssertEqual(attempt.completedWordCount, 99)
    XCTAssertEqual(attempt.prompt, generated)
    attempt.insertBatch(String(repeating: "ab", count: 6), at: start.addingTimeInterval(2))
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.completedWordCount, 105)
    XCTAssertEqual(attempt.errors, 0)
  }
}
