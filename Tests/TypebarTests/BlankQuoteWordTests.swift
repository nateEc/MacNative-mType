import XCTest
@testable import Typebar

final class BlankQuoteWordTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
  private func session(_ text: String = "ab\r\n \n cd", rules: InputRules = .init(),
    modifiers: [TestModifier] = []) -> TypingSession {
    TestSessionFactory.make(configuration: .init(mode: .quote, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: rules, modifiers: modifiers),
      quote: .init(id: "owned-blank-probe", title: "Blank probe", text: text,
        language: .english, length: .short))
  }

  func testBlankLineIsARealSubmittedSlotAndTheFinalWordCompletes() throws {
    var attempt = session()
    XCTAssertEqual(attempt.prompt, "ab\n\ncd")
    attempt.insert("ab\n", at: start)
    XCTAssertEqual(attempt.nextExpectedCharacter, "\n")
    attempt.insert("\n", at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.completedWordCount, 2)
    XCTAssertEqual(attempt.wordReviews.map(\.target), ["ab", ""])
    XCTAssertTrue(attempt.wordReviews.allSatisfy(\.isCorrect))
    attempt.insert("cd", at: start.addingTimeInterval(2))
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.completedWordCount, 3)
    XCTAssertEqual(attempt.errors, 0)
    XCTAssertEqual(attempt.wordReviews.map(\.target), ["ab", "", "cd"])
    XCTAssertEqual(attempt.wordReviews.map(\.typed), ["ab", "", "cd"])
    let result = try XCTUnwrap(attempt.result())
    XCTAssertEqual(result.correctCharacterCount, 6)
    XCTAssertEqual(result.characterStats, .init(matched: 6, incorrect: 0, extra: 0, missed: 0,
      sourceUnits: .classify(input: Array("ab\n\ncd".utf16), target: Array("ab\n\ncd".utf16), creditsPartial: false)))
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 2), result.prompt)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from:
      TypebarDataTransfer.exportArchive(settings: .init(), results: [result], presets: [], at: start)).results, [result])
    var repeated = attempt.repeatedAttempt()
    repeated.insertBatch("ab\n\ncd", at: start)
    XCTAssertEqual(repeated.outcome, .completed)
    XCTAssertEqual(repeated.wordReviews.map(\.target), ["ab", "", "cd"])
  }

  func testCorrectBeforeAdvanceAllowsACorrectEmptySlotWithoutSkippingTheFinalWord() {
    var attempt = session(modifiers: [.correctBeforeAdvance])
    attempt.insert("ab\n", at: start)
    attempt.insert("\n", at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.typed, "ab\n\n")
    XCTAssertEqual(attempt.nextExpectedCharacter, "c")
    attempt.insert("cd", at: start.addingTimeInterval(2))
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.errors, 0)
  }

  func testWordStopRetainsWrongBlankInputThenAllowsItsCorrection() {
    var rules = InputRules()
    rules.stopOnErrorMode = .word
    var attempt = session(rules: rules)
    attempt.insert("ab\n", at: start)
    attempt.insert("x", at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.nextExpectedCharacter, "\n", "空槽中的额外字母不能进入下一词")
    attempt.insert("\n", at: start.addingTimeInterval(2))
    XCTAssertEqual(attempt.typed, "ab\nx\n")
    XCTAssertEqual(attempt.nextExpectedCharacter, "\n")
    attempt.deleteBackward(at: start.addingTimeInterval(3))
    attempt.deleteBackward(at: start.addingTimeInterval(3))
    XCTAssertEqual(attempt.typed, "ab\n")
    attempt.insert("\ncd", at: start.addingTimeInterval(4))
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.errors, 0)
    XCTAssertEqual(attempt.missedWordErrorCountsByWord, [0, 2, 0])
    XCTAssertEqual(attempt.wordReviews.map(\.target), ["ab", "", "cd"])
    XCTAssertEqual(attempt.wordReviews.map(\.hasInputError), [false, true, false])
  }

  func testDefaultBackspaceCanReopenAnIncorrectBlankEvenIfItsTextEqualsTheNextWord() {
    var attempt = session("ab\n\ncd ef")
    attempt.insert("ab\ncd\n", at: start)
    XCTAssertEqual(attempt.nextExpectedCharacter, "c")
    attempt.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.typed, "ab\ncd", "不是把空槽的 cd 与下一词 cd 比较后锁定")
    attempt.deleteBackward(at: start.addingTimeInterval(1))
    attempt.deleteBackward(at: start.addingTimeInterval(1))
    attempt.insert("\ncd ", at: start.addingTimeInterval(2))
    let submitted = attempt.typed
    attempt.deleteBackward(at: start.addingTimeInterval(3))
    XCTAssertEqual(attempt.typed, submitted, "正确提交的非空词仍受默认 confidence 保护")
    attempt.insert("ef", at: start.addingTimeInterval(4))
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.wordReviews.map(\.target), ["ab", "", "cd", "ef"])
  }

  func testFinalTypoRemainsEditableAndHistoricalErrorsStayOnTheRightSlot() {
    var attempt = session()
    attempt.insert("ab\n\ncx", at: start)
    XCTAssertFalse(attempt.isFinished)
    XCTAssertEqual(attempt.wordReviews.map(\.target), ["ab", "", "cd"])
    XCTAssertEqual(attempt.missedWordErrorCountsByWord, [0, 0, 1])
    XCTAssertEqual(attempt.missedWords, ["cd"])
    attempt.deleteBackward(at: start.addingTimeInterval(1))
    attempt.insert("d", at: start.addingTimeInterval(2))
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.errors, 0)
    XCTAssertEqual(attempt.wordReviews.map(\.hasInputError), [false, false, true])
  }

  func testForcedPhysicalErrorOnTheCorrectFinalGlyphDoesNotBecomeCompletion() {
    var attempt = session()
    attempt.insert("ab\n\nc", at: start)
    attempt.insert("d", forceError: true, at: start.addingTimeInterval(1))
    XCTAssertFalse(attempt.isFinished)
    XCTAssertEqual(attempt.errors, 1)
    attempt.deleteBackward(at: start.addingTimeInterval(2))
    attempt.insert("d", at: start.addingTimeInterval(3))
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.errors, 0)
  }

  func testQuickEndStillUsesTheRealFinalWordLengthAfterBlankSlots() {
    var rules = InputRules()
    rules.quickEnd = true
    var attempt = session(rules: rules)
    attempt.insert("ab\n\ncx", at: start)
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.errors, 1)
    XCTAssertEqual(attempt.wordReviews.map(\.target), ["ab", "", "cd"])
  }

  func testMultipleEmptySlotsAndUnicodeWordsCompleteInSingleAndSeparateEvents() {
    for (source, target, words) in [
      ("ab\n\n\ncd", "ab\n\n\ncd", ["ab", "", "", "cd"]),
      ("e\u{301}\r\n \r\n z", "e\u{301}\n\nz", ["e\u{301}", "", "z"]),
      ("🦉\n \n map", "🦉\n\nmap", ["🦉", "", "map"])
    ] {
      for isBatch in [true, false] {
        var attempt = session(source)
        if isBatch { attempt.insertBatch(target, at: start) }
        else { for (index, character) in target.enumerated() {
          attempt.insert(String(character), at: start.addingTimeInterval(Double(index) / 10))
        } }
        XCTAssertEqual(attempt.outcome, .completed, source)
        XCTAssertEqual(attempt.errors, 0, source)
        XCTAssertEqual(attempt.completedWordCount, words.count, source)
        XCTAssertEqual(attempt.wordReviews.map(\.target), words, source)
        XCTAssertTrue(attempt.wordReviews.allSatisfy(\.isCorrect), source)
      }
    }
  }

  func testBlankSlotOwnsItsExtraGlyphAndErrorPresentation() {
    var attempt = session()
    attempt.insert("ab\nx", at: start)
    let words = attempt.promptWordPresentations
    XCTAssertEqual(words.map(\.range), [0..<2, 3..<3, 4..<6])
    XCTAssertEqual(words.map(\.phase), [.committed, .active, .future])
    XCTAssertEqual(words.map(\.hasInputError), [false, true, false])
    XCTAssertEqual(words.map(\.extraGlyphIndices), [[], [6], []])
    attempt.insert("\n", at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.promptWordPresentations.map(\.hasCommitError), [false, true, false])
    XCTAssertEqual(attempt.wordReviews.map(\.target), ["ab", ""])
    XCTAssertEqual(attempt.wordReviews.map(\.typed), ["ab", "x"])
  }
}
