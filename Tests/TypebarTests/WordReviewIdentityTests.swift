import XCTest
@testable import Typebar

final class WordReviewIdentityTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 918_300_000)
  private let composed = "é"
  private let decomposed = "e\u{301}"

  private func aliasAttempt() -> TypingSession {
    var session = TypingSession(configuration: .words(2), prompt: "\(composed) \(decomposed)")
    session.insertBatch("x y ", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.missedWordErrorCountsByWord, [1, 2])
    return session
  }

  func testNoSpaceLoneSurrogateProjectionIsNotACorrectLiteralReplacementTarget() throws {
    var session = TypingSession(configuration: TestConfiguration.words(2).with(modifiers: [.noSpaces]),
      prompt: "�b", noSpaceTargetWords: ["�", "b"])
    session.insertBatch("🙂", at: start)
    XCTAssertEqual(session.outcome, .completed)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.replayEvents.first?.inputField?.valueUTF16, [55357])
    XCTAssertEqual(result.inputMetrics?.correctAttempts, 0)
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 2)
    XCTAssertEqual(session.wordReviews.first?.typed, "�")
    XCTAssertEqual(session.wordReviews.first?.target, "�")
    XCTAssertEqual(session.wordReviews.first?.isCorrect, false)
    XCTAssertEqual(session.wordReviews.first?.hasInputError, true)
  }

  func testLiteralReplacementInputStillMatchesItsActualTarget() {
    var session = TypingSession(configuration: TestConfiguration.words(2).with(modifiers: [.noSpaces]),
      prompt: "�b", noSpaceTargetWords: ["�", "b"])
    session.insertBatch("�b", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertTrue(session.wordReviews.allSatisfy(\.isCorrect))
    XCTAssertTrue(session.wordReviews.allSatisfy { !$0.hasInputError })
  }

  func testCorrectUnfinishedEmojiPrefixDoesNotBecomeAHistoricalMistake() {
    var session = TypingSession(configuration: TestConfiguration.words(1).with(modifiers: [.noSpaces]),
      prompt: "🙂b", noSpaceTargetWords: ["🙂b"])
    session.insertBatch("🙂", at: start)
    XCTAssertEqual(session.outcome, .active)
    XCTAssertEqual(session.wordReviews.first?.hasInputError, false)
    XCTAssertTrue(session.missedWords.isEmpty)
  }

  func testCanonicalAliasesKeepSeparateMissedWordWeightsAndSpellings() throws {
    let session = aliasAttempt()
    let counts = session.missedWordErrorCounts
    XCTAssertEqual(counts.map { Array($0.word.utf16) }, [Array(composed.utf16), Array(decomposed.utf16)])
    XCTAssertEqual(counts.map(\.count), [1, 2])
    let plan = try XCTUnwrap(MissedWordPracticePlan.make(errorCounts: counts))
    XCTAssertEqual(plan.selectedWords.map { Array($0.utf16) }, [Array(decomposed.utf16), Array(composed.utf16)])
  }

  func testContextualPlanDoesNotTreatAnUnmissedCanonicalAliasAsMissed() throws {
    var session = TypingSession(configuration: .words(2, rules: .init(stopOnErrorMode: .letter)),
      prompt: "\(composed) \(decomposed)")
    session.insertBatch("\(composed) x", at: start)
    session.insertBatch(decomposed, at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.missedWordErrorCountsByWord, [0, 1])
    let plan = try XCTUnwrap(ContextualMissedWordPracticePlan.make(reviews: session.wordReviews,
      errorCounts: session.missedWordErrorCountsByWord))
    XCTAssertEqual(plan.selectedTargetCount, 1)
    XCTAssertEqual(plan.phrases.map { Array($0.utf16) }, [Array("\(composed) \(decomposed)".utf16)])
  }

  func testContextualWeightsUseExactSourceKeysInsteadOfCanonicalMerging() throws {
    let session = aliasAttempt()
    let plan = try XCTUnwrap(ContextualMissedWordPracticePlan.make(reviews: session.wordReviews,
      errorCounts: session.missedWordErrorCountsByWord))
    let expected = ["\(composed) \(decomposed)", "\(composed) \(decomposed)", composed]
    XCTAssertEqual(plan.phrases.map { Array($0.utf16) }, expected.map { Array($0.utf16) })
  }

  func testActuallyIdenticalTargetsStillAggregateTheirErrors() {
    var session = TypingSession(configuration: .words(2), prompt: "\(decomposed) \(decomposed)")
    session.insertBatch("x y ", at: start)
    XCTAssertEqual(session.missedWordErrorCountsByWord, [2, 2])
    XCTAssertEqual(session.missedWordErrorCounts.count, 1)
    XCTAssertEqual(session.missedWordErrorCounts.first?.count, 4)
    XCTAssertEqual(session.missedWordErrorCounts.first.map { Array($0.word.utf16) }, Array(decomposed.utf16))
  }

  func testCombinedMissedAndSlowPlanDoesNotReadmitAnUnselectedCanonicalAlias() throws {
    let targets = [composed] + (0..<9).map { "owned\($0)" } + [decomposed]
    let missed = try XCTUnwrap(MissedWordPracticePlan.make(errorCounts: targets.map { .init(word: $0, count: 1) }))
    let slow = SlowWordPracticePlan(selectedWords: ["slow"], exerciseWords: ["slow"])
    let plan = try XCTUnwrap(MissedAndSlowWordPracticePlan.make(missed: missed, slow: slow))
    let expected = Array(targets.prefix(10)) + ["slow"]
    XCTAssertEqual(plan.selectedTargetCount, 11)
    XCTAssertEqual(plan.exerciseWords.map { Array($0.utf16) }, expected.map { Array($0.utf16) })
  }

  func testSelectedSpellingsSurviveActualSectionedPracticeCompletionAndRepeat() throws {
    let missed = try XCTUnwrap(MissedWordPracticePlan.make(errorCounts: aliasAttempt().missedWordErrorCounts))
    let practice = try XCTUnwrap(WordPracticeText.sectionedPractice(segments: missed.exerciseWords,
      selectedTargetCount: missed.selectedWords.count, random: { 0 }))
    let sections = CustomTextPolicy.sections(in: practice.text, preservesSourceSpelling: true)
    XCTAssertEqual(Set(sections.map { Array($0.utf16) }).count, 2)
    let configuration = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), customTextCompletion: .sections,
      customTextSectionLimit: practice.sectionCount, customTextOrdering: .inOrder,
      customTextPipeDelimiter: true)
    var exercise = TestSessionFactory.make(configuration: configuration, customText: practice.text,
      customTextIsPrepared: true)
    XCTAssertEqual(Array(exercise.prompt.utf16), Array(sections.joined(separator: " ").utf16))
    exercise.insertBatch(exercise.prompt, at: start)
    XCTAssertEqual(exercise.outcome, .completed)
    XCTAssertEqual(exercise.wordReviews.map { Array($0.target.utf16) }, sections.map { Array($0.utf16) })
    XCTAssertTrue(exercise.wordReviews.allSatisfy(\.isCorrect))
    var repeated = exercise.repeatedAttempt()
    XCTAssertEqual(Array(repeated.prompt.utf16), Array(exercise.prompt.utf16))
    repeated.insertBatch(repeated.prompt, at: start.addingTimeInterval(1))
    XCTAssertEqual(repeated.outcome, .completed)
    XCTAssertTrue(repeated.wordReviews.allSatisfy(\.isCorrect))
  }

  func testCustomSectionPreparationPreservesSpellingsWhileKeepingWhitespaceRules() {
    let sections = CustomSectionWordStream.sourceSections(from: "\(decomposed)\u{00A0} x\r\nz | \(composed)", usesPipe: true,
      preservesSourceSpelling: true)
    let expected = ["\(decomposed) x\n z", composed]
    XCTAssertEqual(sections.map { Array($0.utf16) }, expected.map { Array($0.utf16) })
  }

  func testRandomSectionsDoNotRetryForADifferentCanonicalSpelling() throws {
    let configuration = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), customTextCompletion: .sections,
      customTextSectionLimit: 2, customTextOrdering: .random, customTextPipeDelimiter: true)
    var stream = try XCTUnwrap(CustomSectionWordStream(source: "\(composed) | \(decomposed) | other | tail",
      configuration: configuration, preservesSourceSpelling: true))
    var calls = 0
    let chunk = stream.nextChunk(random: { calls += 1; return calls == 1 ? 0 : 1 })
    XCTAssertEqual(calls, 2)
    XCTAssertEqual(Array(chunk.text.utf16), Array("\(composed) \(decomposed)".utf16))
  }

  func testRandomWordsCompareExactKeysAfterTheirExistingCasePolicy() {
    var calls = 0
    let words = CustomTextOrderPolicy.randomWords(from: [composed, decomposed, "other", "tail"], count: 2,
      random: { calls += 1; return calls == 1 ? 0 : 1 })
    XCTAssertEqual(calls, 2)
    XCTAssertEqual(words.map { Array($0.utf16) }, [Array(composed.utf16), Array(decomposed.utf16)])
  }

  func testSectionFirstWordAvoidanceKeepsExactNormalizedKeys() {
    XCTAssertFalse(CustomTextOrderPolicy.avoidsRecentFirstWord(in: "\(decomposed) tail",
      previous: [composed], lazyLanguage: nil))
    XCTAssertTrue(CustomTextOrderPolicy.avoidsRecentFirstWord(in: "\(decomposed) tail",
      previous: [decomposed], lazyLanguage: nil))
  }

  func testOrdinaryEditorPreparationStillAppliesReferenceNFC() {
    let source = "\(decomposed) | \(composed)"
    XCTAssertEqual(CustomTextPolicy.sections(in: source).map { Array($0.utf16) },
      [Array(composed.utf16), Array(composed.utf16)])
    let configuration = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), customTextCompletion: .sections,
      customTextSectionLimit: 2, customTextOrdering: .inOrder, customTextPipeDelimiter: true)
    let editor = TestSessionFactory.make(configuration: configuration, customText: source)
    let prepared = TestSessionFactory.make(configuration: configuration, customText: source, customTextIsPrepared: true)
    XCTAssertEqual(Array(editor.prompt.utf16), Array("\(composed) \(composed)".utf16))
    XCTAssertEqual(Array(prepared.prompt.utf16), Array("\(decomposed) \(composed)".utf16))
  }
}
