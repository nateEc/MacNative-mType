import XCTest
@testable import Typebar

final class CustomFunboxWordTargetsTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 100)
  private let cycle = ".-/-..././-/"

  private func configuration(_ completion: CustomTextCompletion, limit: Int = 2,
    pipe: Bool = true, ordering: CustomTextOrdering = .inOrder,
    language: TypingLanguage = .english, modifier: TestModifier = .morseStream) -> TestConfiguration {
    .init(mode: .custom, duration: completion == .time ? TimeInterval(limit) : nil,
      wordLimit: completion == .words ? limit : nil, difficulty: .normal, rules: .init(),
      language: language, customTextCompletion: completion,
      customTextSectionLimit: completion == .sections ? limit : nil,
      customTextOrdering: ordering, customTextPipeDelimiter: pipe, modifiers: [modifier])
  }

  func testMorsePipeFiniteTextHasNoCommitSpacesAndPreservesThreeWordTargets() {
    var session = TestSessionFactory.make(configuration: configuration(.finish), customText: "a b | e")
    XCTAssertEqual(session.prompt, ".-/-..././")
    session.insertBatch(".-/-..././", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
    XCTAssertEqual(session.wordReviews.map(\.target), [".-/", "-.../", "./"])
  }

  func testMorseSectionProgressCommitsAtTheOriginalWordAndSectionEnds() {
    var session = TestSessionFactory.make(configuration: configuration(.sections, limit: 3),
      customText: "a b | e t")
    XCTAssertEqual(session.prompt, cycle + ".-/-.../")
    session.insertBatch(".-/", at: start)
    XCTAssertEqual(session.sectionProgress?.completed, 0)
    session.insertBatch("-.../", at: start)
    XCTAssertEqual(session.sectionProgress?.completed, 1)
    session.insertBatch("./-/.-/-.../", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.sectionProgress?.completed, 3)
    XCTAssertEqual(session.errors, 0)
  }

  func testMorsePipeWordBudgetEndsAtWordThreeDespiteWholeSectionPrefetch() {
    var session = TestSessionFactory.make(configuration: configuration(.words, limit: 3),
      customText: "a b | e t")
    XCTAssertEqual(session.prompt, cycle + ".-/-.../")
    session.insertBatch(".-/-..././", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 3)
    XCTAssertEqual(session.errors, 0)
  }

  func testMorseSpaceDelimitedSectionsCountWordsWithoutRequiringSpaces() {
    var session = TestSessionFactory.make(configuration: configuration(.sections, limit: 3, pipe: false),
      customText: "a b e")
    XCTAssertEqual(session.prompt, ".-/-..././")
    session.insertBatch(".-/", at: start)
    XCTAssertEqual(session.sectionProgress?.completed, 1)
    session.insertBatch("-..././", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.sectionProgress?.completed, 3)
  }

  func testEveryCodeLanguageKeepsMorseTargetsAndWordLimits() {
    for language in TypingLanguage.allCases.filter(\.isCodeLanguage) {
      var session = TestSessionFactory.make(configuration: configuration(.words, limit: 3,
        language: language), customText: "a b | e t")
      session.insertBatch(".-/-..././", at: start)
      XCTAssertEqual(session.outcome, .completed, language.displayName)
      XCTAssertEqual(session.completedWordCount, 3, language.displayName)
      XCTAssertEqual(session.errors, 0, language.displayName)
    }
  }

  func testTimedMorsePipeTextCrossesChunksAndFinishesOnItsClock() {
    var session = TestSessionFactory.make(configuration: configuration(.time, limit: 120),
      customText: "a b | e t")
    XCTAssertEqual(session.prompt, String(repeating: cycle, count: 25))
    session.insertBatch(String(repeating: cycle, count: 30), at: start)
    XCTAssertEqual(session.completedWordCount, 120)
    XCTAssertEqual(session.errors, 0)
    XCTAssertFalse(session.isFinished)
    session.insertBatch(".-/", at: start.addingTimeInterval(119))
    session.tick(at: start.addingTimeInterval(120))
    XCTAssertEqual(session.outcome, .completed)
  }

  func testInfiniteMorseSectionsKeepTheirCountsReplayAndPortableResult() throws {
    var session = TestSessionFactory.make(configuration: configuration(.sections, limit: 0),
      customText: "a b | e t")
    session.insertBatch(String(repeating: cycle, count: 50), at: start)
    XCTAssertFalse(session.isFinished)
    XCTAssertEqual(session.completedWordCount, 200)
    XCTAssertEqual(session.sectionProgress?.completed, 100)
    XCTAssertEqual(session.sectionProgress?.total, 0)
    XCTAssertEqual(session.errors, 0)
    session.bailOut(at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.outcome, .bailedOut)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 1), session.typed)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
  }

  func testMorsePartialSectionEndsAt101WordsWithoutAHiddenSpace() {
    var session = TestSessionFactory.make(configuration: configuration(.words, limit: 101),
      customText: Array(repeating: "e", count: 110).joined(separator: " ") + " | b")
    XCTAssertEqual(session.prompt, String(repeating: "./", count: 100))
    session.insertBatch(String(repeating: "./", count: 101), at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 101)
    XCTAssertEqual(session.wordReviews.count, 101)
    XCTAssertEqual(session.prompt, String(repeating: "./", count: 101))
    XCTAssertEqual(session.errors, 0)
  }

  func testRandomAndShuffledMorseRepeatsKeepFutureChunksAndHiddenBoundaries() {
    for ordering in [CustomTextOrdering.random, .shuffled] {
      var original = TestSessionFactory.make(configuration: configuration(.time, limit: 120,
        ordering: ordering), customText: "a b | e t | b e | t a")
      var repeated = original.repeatedAttempt()
      for _ in 0..<3 {
        let input = String(original.prompt.dropFirst(original.typed.count))
        original.insertBatch(input, at: start)
        repeated.insertBatch(input, at: start)
        XCTAssertEqual(original.prompt, repeated.prompt)
        XCTAssertEqual(original.completedWordCount, repeated.completedWordCount)
      }
      XCTAssertGreaterThan(original.completedWordCount, 100)
      XCTAssertEqual(original.errors, 0)
      XCTAssertFalse(original.isFinished)
    }
  }

  func testMorseNormalizesCanonicalAccentsButDoesNotFoldFullwidthSymbols() {
    XCTAssertEqual(MorseTextPolicy.transformed("ＡéＥ"), "./")
    XCTAssertEqual(MorseTextPolicy.transformed("１2３"), "..---/")
    XCTAssertEqual(MorseTextPolicy.transformed("café"), "-.-./.-/..-././")
    XCTAssertEqual(MorseTextPolicy.transformed("cafe\u{301}"), "-.-./.-/..-././")
  }

  func testMorseMixedWidthWordsKeepOnlyTheirSupportedAsciiTargets() {
    var session = TestSessionFactory.make(configuration: configuration(.finish), customText: "aＡ | éＢ")
    XCTAssertEqual(session.prompt, ".-/./")
    session.insertBatch(".-/./", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.wordReviews.map(\.target), [".-/", "./"])
    XCTAssertEqual(session.errors, 0)
  }

  func testSwissGermanPresentationRunsBeforeMorseWhileGermanDoesNotExpandSharpS() {
    for (language, target) in [(TypingLanguage.swissGerman, "--/.-/.../..././"), (.german, "--/.-/./")] {
      var session = TestSessionFactory.make(configuration: configuration(.sections, language: language),
        customText: "maß | e")
      XCTAssertEqual(session.prompt, target)
      session.insertBatch(target, at: start)
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.errors, 0)
    }
  }

  func testUnderscoreWordBudgetDoesNotRequireASuffixOnWordThree() {
    var session = TestSessionFactory.make(configuration: configuration(.words, limit: 3,
      modifier: .underscoreSeparators), customText: "a b | e t")
    XCTAssertEqual(session.prompt, "a_b_et_a_b_")
    session.insertBatch("a_b_e", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 3)
    XCTAssertEqual(session.wordReviews.map(\.target), ["a_", "b_", "e"])
    XCTAssertEqual(session.errors, 0)
  }

  func testUnderscoreSectionPrefetchKeepsTheSuffixAsTargetRatherThanCommit() {
    var session = TestSessionFactory.make(configuration: configuration(.sections,
      modifier: .underscoreSeparators), customText: "a b | e t")
    XCTAssertEqual(session.prompt, "a_be_t_")
    session.insertBatch("a_b", at: start)
    XCTAssertEqual(session.sectionProgress?.completed, 1)
    session.insertBatch("e_t_", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.wordReviews.map(\.target), ["a_", "b", "e_", "t_"])
    XCTAssertEqual(session.errors, 0)
  }

  func testUnderscoreContinuationUsesGlobalWordIndexAndRequiresTheFinalTargetSuffix() {
    let opening = String(repeating: "e_", count: 99) + "e"
    var session = TestSessionFactory.make(configuration: configuration(.words, limit: 101,
      modifier: .underscoreSeparators), customText: Array(repeating: "e", count: 110).joined(separator: " ") + " | b")
    XCTAssertEqual(session.prompt, opening)
    session.insertBatch(opening + "e_", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 101)
    XCTAssertEqual(session.wordReviews.last?.target, "e_")
    XCTAssertEqual(session.errors, 0)
  }

  func testFinitePipeUnderscoresPreserveTheSourceGenerationBound() {
    var session = TestSessionFactory.make(configuration: configuration(.finish,
      modifier: .underscoreSeparators), customText: "a b | e t")
    XCTAssertEqual(session.prompt, "a_be_t_")
    session.insertBatch("a_be_t_", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
  }

  func testMorseStillRejectsWhitespaceWithoutTurningItIntoAnInputAttempt() {
    var session = TestSessionFactory.make(configuration: configuration(.sections), customText: "a | e")
    session.insertBatch(" ", at: start)
    XCTAssertFalse(session.hasStarted)
    XCTAssertEqual(session.typed, "")
    XCTAssertEqual(session.errors, 0)
    session.insertBatch(".-/", at: start)
    session.insertBatch(" ", at: start)
    XCTAssertEqual(session.typed, ".-/")
    session.insertBatch("./", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
  }

  func testUnderscoreFinalSuffixMustBeTypedAndSurvivesReplayAndRecord() throws {
    var session = TestSessionFactory.make(configuration: configuration(.sections,
      modifier: .underscoreSeparators), customText: "a b | e t")
    session.insertBatch("a_be_t", at: start)
    XCTAssertFalse(session.isFinished)
    XCTAssertEqual(session.sectionProgress?.completed, 1)
    session.insertBatch("_", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.sectionProgress?.completed, 2)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(session.wordReviews.last?.target, "t_")
    XCTAssertEqual(result.prompt, "a_be_t_")
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 1), "a_be_t_")
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
  }

  func testUnderscoreTimedAndInfiniteRepeatsKeepGlobalContinuationTargets() {
    for completion in [CustomTextCompletion.time, .sections] {
      let config = configuration(completion, limit: completion == .time ? 120 : 0,
        modifier: .underscoreSeparators)
      var session = TestSessionFactory.make(configuration: config, customText: "e")
      var repeated = session.repeatedAttempt()
      let opening = String(repeating: "e_", count: 99) + "e"
      XCTAssertEqual(session.prompt, opening)
      session.insertBatch(opening, at: start)
      repeated.insertBatch(opening, at: start)
      XCTAssertEqual(session.completedWordCount, 100)
      XCTAssertEqual(session.prompt, opening + String(repeating: "e_", count: 100))
      let continuation = String(repeating: "e_", count: 100)
      session.insertBatch(continuation, at: start)
      repeated.insertBatch(continuation, at: start)
      XCTAssertEqual(session.prompt, repeated.prompt)
      XCTAssertEqual(session.completedWordCount, 200)
      XCTAssertEqual(session.errors, 0)
      XCTAssertFalse(session.isFinished)
    }
  }

  func testUnderscoreTargetParticipatesInTheFollowingWordAlteration() {
    for (modifier, target, words) in [
      (TestModifier.backwards, "_ab_e_t", ["_a", "b", "_e", "_t"]),
      (.doubleCharacters, "aa__bbee__tt__", ["aa__", "bb", "ee__", "tt__"]),
    ] {
      let config = configuration(.sections, modifier: .underscoreSeparators)
        .with(modifiers: [.underscoreSeparators, modifier])
      XCTAssertEqual(config.modifiers, [.underscoreSeparators, modifier])
      var session = TestSessionFactory.make(configuration: config, customText: "a b | e t")
      XCTAssertEqual(session.prompt, target)
      session.insertBatch(target, at: start)
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.wordReviews.map(\.target), words)
      XCTAssertEqual(session.errors, 0)
    }
  }

  func testFiniteSpaceDelimitedMorseSharesTheCanonicalAndLanguagePolicies() {
    var session = TestSessionFactory.make(configuration: configuration(.finish, pipe: false,
      language: .swissGerman), customText: "maß Ａé")
    XCTAssertEqual(session.prompt, "--/.-/.../..././")
    session.insertBatch(session.prompt, at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 2)
    XCTAssertEqual(session.wordReviews.map(\.target), ["--/.-/.../.../", "./"])
    XCTAssertEqual(session.errors, 0)
  }

  func testMorseDoesNotTransliterateCompatibilityLettersOrLigatures() {
    XCTAssertEqual(MorseTextPolicy.transformed("ﬃøłœße"), "./")
    XCTAssertEqual(MorseTextPolicy.transformed("e\u{1AB0}a"), "./.-/")
  }
}
