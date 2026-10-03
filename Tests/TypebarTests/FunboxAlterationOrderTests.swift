import XCTest
@testable import Typebar

final class FunboxAlterationOrderTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 100)

  private func configuration(_ modifiers: [TestModifier], pipe: Bool = false,
    completion: CustomTextCompletion = .finish) -> TestConfiguration {
    .init(mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal,
      rules: .init(), customTextCompletion: completion,
      customTextSectionLimit: completion == .sections ? 2 : nil,
      customTextPipeDelimiter: pipe, modifiers: modifiers)
  }

  func testBackwardsRunsBeforeCapitalsOnTheReversedFiniteWordPool() {
    var session = TestSessionFactory.make(configuration: configuration([.backwards, .titleCase]),
      customText: "ab cd")
    XCTAssertEqual(session.prompt, "Dc Ba")
    session.insertBatch("Dc Ba", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
  }

  func testBackwardsRunsBeforeThePerWordAlternatingPhase() {
    var session = TestSessionFactory.make(configuration: configuration([.backwards, .alternatingCase]),
      customText: "abcd ef")
    XCTAssertEqual(session.prompt, "fE dCbA")
    session.insertBatch("fE dCbA", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
  }

  func testNoSpaceDoesNotMergeWordsBeforeTheirCapitalisation() {
    var session = TestSessionFactory.make(configuration: configuration([.noSpaces, .titleCase]),
      customText: "ab cd")
    XCTAssertEqual(session.prompt, "AbCd")
    session.insertBatch("AbCd", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.wordReviews.map(\.target), ["Ab", "Cd"])
    XCTAssertEqual(session.errors, 0)
  }

  func testNoSpaceDoesNotCarryTheAlternatingPhaseBetweenWords() {
    var session = TestSessionFactory.make(configuration: configuration([.noSpaces, .alternatingCase]),
      customText: "abc de")
    XCTAssertEqual(session.prompt, "aBcdE")
    session.insertBatch("aBcdE", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.wordReviews.map(\.target), ["aBc", "dE"])
    XCTAssertEqual(session.errors, 0)
  }

  func testMorseRunsBeforeRot13InBothCustomDelimiterPaths() {
    for pipe in [false, true] {
      var session = TestSessionFactory.make(configuration: configuration([.rot13, .morseStream], pipe: pipe),
        customText: pipe ? "a | b" : "a b")
      XCTAssertEqual(session.prompt, ".-/-.../")
      session.insertBatch(".-/-.../", at: start)
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(session.wordReviews.map(\.target), [".-/", "-.../"])
      XCTAssertEqual(session.errors, 0)
    }
  }

  func testDoublingRunsBeforeMessagingAndPreservesInternalNewlineCommit() {
    var session = TestSessionFactory.make(configuration: configuration([.messagingStyle, .doubleCharacters]),
      customText: "Hi! Next.")
    XCTAssertEqual(session.prompt, "hhii!\nnneexxtt")
    session.insertBatch("hhii!\nnneexxtt", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
  }

  func testSectionMessagingKeepsNewlineCommitButRemovesOnlyTheFinalCommit() {
    var session = TestSessionFactory.make(configuration: configuration([.messagingStyle, .doubleCharacters],
      pipe: true, completion: .sections), customText: "Hi! | Next.")
    XCTAssertEqual(session.prompt, "hhii!\nnneexxtt")
    session.insertBatch("hhii!\n", at: start)
    XCTAssertEqual(session.sectionProgress?.completed, 1)
    session.insertBatch("nneexxtt", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
  }

  func testBackwardsReversesCandidateSectionsButNotWordsInsideTheSection() {
    var session = TestSessionFactory.make(configuration: configuration([.backwards], pipe: true,
      completion: .sections), customText: "ab cd | ef gh")
    XCTAssertEqual(session.prompt, "fe hg ba dc")
    session.insertBatch("fe hg ", at: start)
    XCTAssertEqual(session.sectionProgress?.completed, 1)
    session.insertBatch("ba dc", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
  }

  func testUnderscoreRunsAfterReversalWithTheOriginalGenerationBound() {
    var session = TestSessionFactory.make(configuration: configuration([.underscoreSeparators, .backwards],
      pipe: true, completion: .sections), customText: "ab cd | ef gh")
    XCTAssertEqual(session.prompt, "fe_hgba_dc_")
    session.insertBatch("fe_hgba_dc_", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.wordReviews.map(\.target), ["fe_", "hg", "ba_", "dc_"])
    XCTAssertEqual(session.errors, 0)
  }

  func testUnderscoreRunsAfterDoublingWithoutDuplicatingItsSuffix() {
    var session = TestSessionFactory.make(configuration: configuration([.underscoreSeparators, .doubleCharacters],
      pipe: true, completion: .sections), customText: "a b | e t")
    XCTAssertEqual(session.prompt, "aa_bbee_tt_")
    session.insertBatch("aa_bbee_tt_", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.wordReviews.map(\.target), ["aa_", "bb", "ee_", "tt_"])
    XCTAssertEqual(session.errors, 0)
  }

  func testDoublingExcludesAllFourRegexpLineTerminatorsButNotTabs() {
    XCTAssertEqual(TestModifierPolicy.transformed("a\nb\rc\u{2028}d\u{2029}e", modifiers: [.doubleCharacters]),
      "aa\nbb\rcc\u{2028}dd\u{2029}ee")
    XCTAssertEqual(TestModifierPolicy.transformed("a\tb", modifiers: [.doubleCharacters]), "aa\t\tbb")
  }

  func testCapitalsTouchesTheFirstUtf16UnitNotAnAstralLetter() {
    XCTAssertEqual(TestModifierPolicy.transformed("\u{10428}a élan", modifiers: [.titleCase]),
      "\u{10428}a Élan")
  }

  func testNoSpaceMessagingRetainsInternalNewlineWordBoundaries() {
    var session = TestSessionFactory.make(configuration: configuration([.noSpaces, .messagingStyle]),
      customText: "Hi! Next.")
    XCTAssertEqual(session.prompt, "hi\nnext")
    session.insertBatch("hi\nnext", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.wordReviews.map(\.target), ["hi\n", "next"])
    XCTAssertEqual(session.completedWordCount, 2)
    XCTAssertEqual(session.errors, 0)
  }

  func testCanonicalUnderscoreAfterMessagingKeepsItsTargetButReturnNavigatesOnSingleKeyEvents() throws {
    var session = TestSessionFactory.make(configuration: configuration([.underscoreSeparators, .messagingStyle],
      pipe: true, completion: .sections), customText: "Hi! | Next.")
    XCTAssertEqual(session.prompt, "hi\n_next")
    // Source LF is a separator even when another alterText suffix follows
    // it. Separate physical events finish on the last-word commit, before
    // the final t. Whole-event last-word reentry is a separate open contract.
    for (index, character) in "hi\n_next".enumerated() {
      session.insert(String(character), at: start.addingTimeInterval(Double(index) / 10))
    }
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.wordReviews.map(\.target), ["hi\n_", "next"])
    XCTAssertEqual(session.typed, "hi\n_nex")
    XCTAssertEqual(session.wordReviews.map(\.typed), ["hi\n", "_nex"])
    XCTAssertEqual(session.errors, 4)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 7)
    XCTAssertEqual(result.inputMetrics?.correctAttempts, 3)
    XCTAssertEqual(result.inputMetrics?.creditedUnits, 0)
    XCTAssertEqual(result.replayEvents.map { $0.inputField?.index }, [0,0,0,1,1,1,1])
  }

  func testRandomCaseDrawsAfterDoublingForEveryDoubledScalar() {
    var bits = [true, false, false, true].makeIterator()
    let target = TestModifierPolicy.transformedWord("ab", modifiers: [.randomCase, .doubleCharacters],
      nextRandomCaseBit: { bits.next()! })
    XCTAssertEqual(target, "AabB")
    XCTAssertNil(bits.next())
  }

  func testAllCodeLanguagesUseTheSharedCanonicalMorseAndRot13Path() {
    for language in TypingLanguage.allCases.filter(\.isCodeLanguage) {
      var config = configuration([.rot13, .morseStream], pipe: true)
      config.language = language
      var session = TestSessionFactory.make(configuration: config, customText: "a | b")
      session.insertBatch(".-/-.../", at: start)
      XCTAssertEqual(session.outcome, .completed, language.displayName)
      XCTAssertEqual(session.completedWordCount, 2, language.displayName)
      XCTAssertEqual(session.errors, 0, language.displayName)
    }
  }

  func testReversedLongSectionKeepsTheCandidatePoolAndFutureChunksOnRepeat() throws {
    let source = "ab | " + Array(repeating: "ef", count: 110).joined(separator: " ")
    let config = configuration([.backwards, .titleCase], pipe: true, completion: .sections)
    var session = TestSessionFactory.make(configuration: config, customText: source)
    let target = Array(repeating: "Fe", count: 110).joined(separator: " ") + " Ba"
    XCTAssertEqual(session.prompt, Array(repeating: "Fe", count: 100).joined(separator: " ") + " ")
    var repeated = session.repeatedAttempt()
    session.insertBatch(target, at: start)
    repeated.insertBatch(target, at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(repeated.outcome, .completed)
    XCTAssertEqual(session.prompt, repeated.prompt)
    XCTAssertEqual(session.sectionProgress?.completed, 2)
    XCTAssertEqual(session.errors, 0)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 1), target)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
  }
}
