import XCTest
@testable import Typebar

final class InputTextIdentityTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 873_200_000)
  private let aliases = [("e\u{301}", "é"), ("é", "e\u{301}"),
    ("a\u{301}\u{323}", "a\u{323}\u{301}"), ("\u{212B}", "Å")]

  private func config(_ difficulty: Difficulty = .normal, rules: InputRules = .init(),
    modifiers: [TestModifier] = []) -> TestConfiguration {
    .init(mode: .quote, duration: nil, wordLimit: nil, difficulty: difficulty,
      rules: rules, modifiers: modifiers)
  }

  func testExplicitEquivalenceDoesNotIncludeCanonicalUnicodeAliases() {
    for (target, input) in aliases {
      XCTAssertFalse(InputCharacterEquivalence.matches(Character(input), Character(target), language: .english))
      let normalized = InputCharacterEquivalence.normalized(Character(input),
        expected: Character(target), language: .english)
      XCTAssertEqual(Array(String(normalized).utf16), Array(input.utf16))
    }
  }

  func testAcceptedAliasIsPreservedAndCannotFinishWithoutQuickEnd() {
    for (target, input) in aliases {
      var attempt = TypingSession(configuration: config(), prompt: target)
      attempt.insertBatch(input, at: start)
      XCTAssertEqual(Array(attempt.typed.utf16), Array(input.utf16))
      XCTAssertEqual(attempt.outcome, .active)
      XCTAssertEqual(attempt.errors, 1)
      XCTAssertEqual(attempt.characterStats.incorrect, 1)
      XCTAssertEqual(attempt.lastInputWasCorrect, false)
      XCTAssertFalse(attempt.wordReviews[0].isCorrect)
      XCTAssertEqual(attempt.promptGlyphs[0].state, .incorrect)
      XCTAssertNotNil(attempt.promptGlyphs[0].typedCharacter)
      XCTAssertLessThan(attempt.preciseAccuracy, 100)
    }
  }

  func testMasterRejectsTheLastIncorrectUnitOfCanonicalAliases() {
    for (target, input) in aliases {
      var attempt = TypingSession(configuration: config(.master), prompt: target + " tail")
      attempt.insertBatch(input, at: start)
      XCTAssertEqual(attempt.outcome, .failed)
      XCTAssertEqual(Array(attempt.typed.utf16), Array(input.utf16))
      XCTAssertEqual(attempt.lastInputWasCorrect, false)
    }
  }

  func testExpertFailsWhenCanonicalAliasIsCommitted() {
    for (target, input) in aliases {
      var attempt = TypingSession(configuration: config(.expert), prompt: target + " tail")
      attempt.insertBatch(input, at: start)
      XCTAssertEqual(attempt.outcome, .active)
      attempt.insert(" ", at: start.addingTimeInterval(1))
      XCTAssertEqual(attempt.outcome, .failed)
      XCTAssertFalse(attempt.wordReviews[0].isCorrect)
    }
  }

  func testWordStopAndCorrectBeforeAdvanceRetainAnIncorrectCanonicalWord() {
    for configuration in [config(rules: .init(stopOnErrorMode: .word)),
      config(modifiers: [.correctBeforeAdvance])] {
      for (target, input) in aliases {
        var attempt = TypingSession(configuration: configuration, prompt: target + " tail")
        attempt.insertBatch(input, at: start)
        attempt.insert(" ", at: start.addingTimeInterval(1))
        let retained = configuration.rules.stopOnErrorMode == .word ? input + " " : input
        XCTAssertEqual(Array(attempt.typed.utf16), Array(retained.utf16))
        XCTAssertEqual(attempt.completedWordCount, 0)
        XCTAssertEqual(attempt.outcome, .active)
      }
    }
  }

  func testSingleUnitAliasIsStoppedBeforeItCanReplaceTheTarget() {
    for (target, input) in [aliases[0], aliases[3]] {
      var attempt = TypingSession(configuration: config(rules: .init(stopOnErrorMode: .letter)),
        prompt: target + " tail")
      attempt.insert(input, at: start)
      XCTAssertEqual(attempt.typed, "")
      XCTAssertEqual(attempt.preciseAccuracy, 0)
      XCTAssertEqual(attempt.lastInputWasCorrect, false)
      XCTAssertEqual(attempt.outcome, .active)
    }
  }

  func testSingleUnitAliasRunsDeleteOnErrorAndKeepsTheFailedReplayInput() throws {
    for mode in [DeleteOnErrorMode.letter, .word] {
      var attempt = TypingSession(configuration: config(rules: .init(deleteOnErrorMode: mode)),
        prompt: "seed e\u{301} tail")
      attempt.insertBatch("seed ", at: start)
      attempt.insert("é", at: start.addingTimeInterval(1))
      XCTAssertEqual(attempt.typed, "seed ")
      XCTAssertEqual(attempt.lastInputWasCorrect, false)
      attempt.bailOut(at: start.addingTimeInterval(2))
      let result = try XCTUnwrap(attempt.result())
      XCTAssertEqual(result.replayEvents.suffix(2).map(\.kind), [.insert, .delete])
      XCTAssertEqual(result.replayEvents.dropLast().last?.text, "é")
      XCTAssertEqual(result.replayEvents.last?.automatic, true)
      XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents,
        through: result.elapsedDuration), "seed ")
    }
  }

  func testCorrectingAliasRestoresVisibleCorrectnessButNotAttemptAccuracy() {
    var attempt = TypingSession(configuration: config(), prompt: "e\u{301} tail")
    attempt.insert("é", at: start)
    XCTAssertEqual(attempt.errors, 1)
    attempt.deleteBackward(at: start.addingTimeInterval(1))
    attempt.insertBatch("e\u{301} tail", at: start.addingTimeInterval(2))
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.errors, 0)
    XCTAssertLessThan(attempt.preciseAccuracy, 100)
    XCTAssertEqual(attempt.promptGlyphs[0].state, .correct)
    XCTAssertTrue(attempt.wordReviews[0].hasInputError)
    XCTAssertFalse(attempt.wordReviews[0].isCorrect,
      "Word history retains failed attempts even after visible correction")
  }

  func testExactPreparedTargetsStillCompleteInEveryDifficulty() {
    for difficulty in Difficulty.allCases {
      for (target, _) in aliases {
        var attempt = TypingSession(configuration: config(difficulty), prompt: target)
        attempt.insertBatch(target, at: start)
        XCTAssertEqual(attempt.outcome, .completed)
        XCTAssertEqual(attempt.errors, 0)
        XCTAssertEqual(attempt.preciseAccuracy, 100)
        XCTAssertEqual(Array(attempt.typed.utf16), Array(target.utf16))
      }
    }
  }

  func testExplicitPunctuationSpaceAndRussianEquivalencesRemainAccepted() {
    for (target, input, language) in [("’", "'", TypingLanguage.english),
      ("—", "-", .english), ("„", "\"", .english), ("‚", ",", .english),
      ("ё", "e", .russian)] {
      let configuration = TestConfiguration(mode: .quote, duration: nil, wordLimit: nil,
        difficulty: .normal, rules: .init(), language: language)
      var attempt = TypingSession(configuration: configuration, prompt: target)
      attempt.insert(input, at: start)
      XCTAssertEqual(attempt.outcome, .completed)
      XCTAssertEqual(attempt.preciseAccuracy, 100)
      XCTAssertEqual(Array(attempt.typed.utf16), Array(target.utf16))
    }
    var spaces = TypingSession(configuration: config(), prompt: "a b")
    spaces.insertBatch("a\u{3000}b", at: start)
    XCTAssertEqual(spaces.typed, "a b")
    XCTAssertEqual(spaces.outcome, .completed)
  }

  func testCanonicalAliasResultAndReplayPreserveInputRatherThanTargetBytes() throws {
    var attempt = TypingSession(configuration: config(), prompt: "e\u{301} tail")
    attempt.insertBatch("é tail", at: start)
    let result = try XCTUnwrap(attempt.result())
    XCTAssertEqual(result.errorCount, 1)
    XCTAssertLessThan(result.preciseAccuracy, 100)
    let expected = Array("é tail".utf16)
    XCTAssertEqual(Array(TypingReplay.typedText(events: result.replayEvents,
      through: result.elapsedDuration).utf16), expected)
    let portable = try XCTUnwrap(TestResultRecord(result: result).portableResult)
    XCTAssertEqual(Array(portable.replayEvents.first!.text.utf16), Array("é".utf16))
    let restored = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [], at: start))
    XCTAssertEqual(Array(restored.results[0].prompt.utf16), Array("e\u{301} tail".utf16))
    XCTAssertEqual(restored.results[0].errorCount, 1)
  }

  func testSameWidthNoSpaceAliasFailsExpertAtItsActualWordCommit() {
    for difficulty in [Difficulty.expert, .master] {
      var attempt = TypingSession(configuration: config(difficulty, modifiers: [.noSpaces]),
        prompt: "\u{212B}tail", noSpaceWordEndIndices: [1, 5],
        noSpaceTargetWords: ["\u{212B}", "tail"])
      attempt.insertBatch("Å", at: start)
      XCTAssertEqual(Array(attempt.typed.utf16), Array("Å".utf16))
      XCTAssertEqual(attempt.outcome, .failed)
      XCTAssertEqual(attempt.preciseAccuracy, 0)
      XCTAssertFalse(attempt.wordReviews[0].isCorrect)
    }
  }

  func testCustomFinishDoesNotUseSwiftsCanonicalEqualityShortcut() {
    for (target, input) in aliases {
      let configuration = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
        difficulty: .normal, rules: .init(), customTextCompletion: .finish)
      var attempt = TypingSession(configuration: configuration, prompt: target)
      attempt.insertBatch(input, at: start)
      XCTAssertEqual(attempt.outcome, .active)
      XCTAssertEqual(attempt.errors, 1)
    }
  }

  func testCompositionCompletionProbeRequiresExactPreparedFinalWord() {
    for (target, input) in aliases {
      let attempt = TypingSession(configuration: config(), prompt: target)
      XCTAssertFalse(attempt.shouldFinishWithComposition(input, at: start))
      XCTAssertTrue(attempt.shouldFinishWithComposition(target, at: start))
      XCTAssertFalse(attempt.hasStarted)
      XCTAssertEqual(attempt.typed, "")
    }
  }

  func testQuickEndStillFinishesWrongWordsOnlyAtTheirUTF16Length() {
    for (target, input) in aliases {
      var attempt = TypingSession(configuration: config(rules: .init(quickEnd: true)), prompt: target)
      attempt.insertBatch(input, at: start)
      XCTAssertEqual(attempt.outcome, target.utf16.count == input.utf16.count ? .completed : .active)
      XCTAssertEqual(attempt.errors, 1)
      XCTAssertLessThan(attempt.preciseAccuracy, 100)
    }
  }

  func testZenPreservesInputSpellingAndDoesNotApplyTargetEquivalence() {
    for (target, input) in aliases {
      var attempt = TypingSession(configuration: .init(mode: .zen, duration: nil, wordLimit: nil,
        difficulty: .master, rules: .init()), prompt: target)
      attempt.insertBatch(input, at: start)
      XCTAssertEqual(Array(attempt.typed.utf16), Array(input.utf16))
      XCTAssertEqual(attempt.preciseAccuracy, 100)
      XCTAssertEqual(attempt.outcome, .active)
      XCTAssertEqual(attempt.errors, 0)
    }
  }

  func testStandaloneWordReviewRequiresExactIdentityWithoutHistoricalErrors() {
    for (target, input) in aliases {
      let review = TypedWordReview(index: 0, target: target, typed: input)
      XCTAssertFalse(review.hasInputError)
      XCTAssertFalse(review.isCorrect)
    }
  }

  func testExplicitRussianSetDoesNotExpandThroughCanonicalSetMembership() {
    let decomposed = Character("е\u{308}")
    XCTAssertFalse(InputCharacterEquivalence.matches(decomposed, "e", language: .russian))
    let normalized = InputCharacterEquivalence.normalized(decomposed,
      expected: "e", language: .russian)
    XCTAssertEqual(Array(String(normalized).utf16), Array("е\u{308}".utf16))
    XCTAssertTrue(InputCharacterEquivalence.matches("ё", "e", language: .russian))
  }

  func testMasterBatchWithCanonicalReorderingUsesTheLastUnitNotWholeGlyph() throws {
    let target = "a\u{301}\u{323}\u{310}"
    let input = "a\u{323}\u{301}\u{310}"
    var attempt = TypingSession(configuration: config(.master), prompt: target + " tail")
    attempt.insertBatch(input, at: start)
    XCTAssertEqual(attempt.outcome, .active)
    XCTAssertEqual(attempt.lastInputWasCorrect, true)
    XCTAssertEqual(attempt.preciseAccuracy, 50)
    XCTAssertEqual(attempt.errors, 1)
    XCTAssertEqual(Array(attempt.typed.utf16), Array(input.utf16))
    attempt.bailOut(at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(attempt.result())
    XCTAssertEqual(result.inputMetrics?.correctAttempts, 2)
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 4)
    XCTAssertEqual(Array(TypingReplay.typedText(events: result.replayEvents,
      through: result.elapsedDuration).utf16), Array(input.utf16))
  }

  func testMasterBatchWithWrongBaseAndCorrectFinalMarkRemainsActive() {
    var attempt = TypingSession(configuration: config(.master), prompt: "e\u{301} tail")
    attempt.insertBatch("a\u{301}", at: start)
    XCTAssertEqual(attempt.outcome, .active)
    XCTAssertEqual(attempt.lastInputWasCorrect, true)
    XCTAssertEqual(attempt.preciseAccuracy, 50)
    XCTAssertEqual(attempt.errors, 1)
  }

  func testMasterBatchFailsWhenTheUnitPositionMissesDespiteMatchingVisibleGlyph() {
    var attempt = TypingSession(configuration: config(.master), prompt: "🦊a tail")
    attempt.insertBatch("xa", at: start)
    XCTAssertEqual(attempt.outcome, .failed)
    XCTAssertEqual(attempt.lastInputWasCorrect, false)
    XCTAssertEqual(attempt.preciseAccuracy, 0)
    XCTAssertEqual(attempt.typed, "xa")
  }
}
