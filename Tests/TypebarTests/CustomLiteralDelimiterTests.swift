import XCTest
@testable import Typebar

final class CustomLiteralDelimiterTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 100)

  private func configuration(_ completion: CustomTextCompletion = .sections,
    limit: Int = 2, pipe: Bool = true, modifiers: [TestModifier] = [.morseStream]) -> TestConfiguration {
    .init(mode: .custom, duration: nil, wordLimit: completion == .words ? limit : nil,
      difficulty: .normal, rules: .init(), customTextCompletion: completion,
      customTextSectionLimit: completion == .sections ? limit : nil,
      customTextOrdering: .inOrder, customTextPipeDelimiter: pipe, modifiers: modifiers)
  }

  func testLiteralPipeSeparatesACombiningMarkFromItsDelimiter() {
    XCTAssertEqual(CustomSectionWordStream.sourceSections(from: "a|\u{301}b|c", usesPipe: true),
      ["a", "\u{301}b", "c"])
  }

  func testLiteralSpaceSeparatesACombiningMarkFromItsDelimiter() {
    XCTAssertEqual(CustomSectionWordStream.sourceSections(from: "a \u{301}b c", usesPipe: false),
      ["a", "\u{301}b", "c"])
  }

  func testPipeEdgeSpacesAreTrimmedWithoutDiscardingTheFollowingMark() {
    XCTAssertEqual(CustomSectionWordStream.sourceSections(from: "a| \u{301}b  | c", usesPipe: true),
      ["a", "\u{301}b", "c"])
  }

  func testFusedTargetsRejectOffsetsAndEmptyMorseWordsRetainTheirIdentity() throws {
    var fused = try XCTUnwrap(CustomSectionWordStream(source: "a \u{301}b",
      configuration: configuration(.finish, modifiers: [.noSpaces])))
    let fusedChunk = fused.nextChunk()
    XCTAssertEqual(fusedChunk.text, "a\u{301}b")
    XCTAssertTrue(fusedChunk.noSpaceWordLengths.isEmpty)
    XCTAssertEqual(fusedChunk.noSpaceTargetWords.map { Array($0.utf16) }, [[97], [769,98]])
    var empty = try XCTUnwrap(CustomSectionWordStream(source: "中 a", configuration: configuration(.finish)))
    let emptyChunk = empty.nextChunk()
    XCTAssertEqual(emptyChunk.text, ".-/")
    XCTAssertEqual(emptyChunk.noSpaceWordLengths, [0, 3])
    XCTAssertEqual(emptyChunk.noSpaceTargetWords, ["", ".-/"])
    XCTAssertEqual(NoSpaceWordBoundaryPolicy.endIndices(for: emptyChunk.noSpaceWordLengths), [0, 3])
  }

  func testAllMappedSpaceScalarsStillSplitBeforeACombiningMark() {
    for value: UInt32 in Array(0x2000...0x200A) + [0x202F, 0x205F, 0x00A0] {
      let space = String(UnicodeScalar(value)!)
      XCTAssertEqual(CustomSectionWordStream.sourceSections(from: "a\(space)\u{301}b", usesPipe: false),
        ["a", "\u{301}b"], "U+\(String(value, radix: 16))")
    }
  }

  func testNewlineScalarsKeepTheirCommitAndTheNextWordsCombiningMark() {
    for newline in ["\n", "\r", "\r\n"] {
      XCTAssertEqual(CustomSectionWordStream.sourceSections(from: "a\(newline)\u{301}b", usesPipe: false),
        ["a\n", "\u{301}b"])
    }
  }

  func testConsecutiveMixedNewlinesKeepSeparateCommitBearingWords() {
    XCTAssertEqual(CustomSectionWordStream.sourceSections(from: "  a \r\n \r \n b  ", usesPipe: false),
      ["a\n", "\n", "\n", "b"])
  }

  func testCanonicalCompositionDoesNotMoveTheLeadingMarkAcrossThePipe() {
    XCTAssertEqual(CustomSectionWordStream.sourceSections(from: "cafe\u{301}  |\u{301}b", usesPipe: true),
      ["café", "\u{301}b"])
  }

  func testRecentFirstWordComparisonUsesTheLiteralCommitBeforeTheMark() {
    XCTAssertTrue(CustomTextOrderPolicy.avoidsRecentFirstWord(in: "a \u{301}b", previous: ["A!"], lazyLanguage: nil))
    XCTAssertFalse(CustomTextOrderPolicy.avoidsRecentFirstWord(in: "a\tb c", previous: ["a"], lazyLanguage: nil))
    XCTAssertTrue(CustomTextOrderPolicy.avoidsRecentFirstWord(in: "a\tb c", previous: ["a\tb"], lazyLanguage: nil))
  }

  func testRandomSectionCandidateRetriesItsRecentLiteralFirstWord() throws {
    var config = configuration(.words, limit: 3, modifiers: [])
    config.customTextOrdering = .random
    var cursor = try XCTUnwrap(CustomSectionWordStream(source: "x y|a \u{301}b|c d|e f",
      configuration: config))
    var choices = [0, 1, 1, 2].makeIterator()
    var draws = 0
    let chunk = cursor.nextChunk(random: { draws += 1; return choices.next()! })
    XCTAssertEqual(draws, 4)
    XCTAssertEqual(chunk.text, "x y a \u{301}b c d")
  }

  func testOtherWhitespaceAndZeroWidthScalarsRemainWordContent() {
    for value: UInt32 in [0x09, 0x0B, 0x0C, 0x85, 0x2028, 0x2029, 0x200B, 0x200D, 0x2060, 0xFEFF] {
      let word = "a\(String(UnicodeScalar(value)!))b"
      XCTAssertEqual(CustomSectionWordStream.sourceSections(from: word + " c", usesPipe: false),
        [word, "c"], "U+\(String(value, radix: 16))")
    }
  }

  func testMorsePipeCountsTheActualWordsRatherThanTheDelimiterGraphemes() {
    var attempt = TestSessionFactory.make(configuration: configuration(), customText: "a \u{301}b|c")
    XCTAssertEqual(attempt.prompt, ".-/-.../-.-./")
    attempt.insertBatch(".-/-.../-.-./", at: start)
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.completedWordCount, 3)
    XCTAssertEqual(attempt.sectionProgress?.completed, 2)
    XCTAssertEqual(attempt.wordReviews.map(\.target), [".-/", "-.../", "-.-./"])
    XCTAssertEqual(attempt.errors, 0)
  }

  func testMorseSpaceSectionsCompleteEachLiteralSourceWord() {
    var attempt = TestSessionFactory.make(configuration: configuration(limit: 3, pipe: false),
      customText: "a \u{301}b c")
    attempt.insertBatch(".-/", at: start)
    XCTAssertEqual(attempt.sectionProgress?.completed, 1)
    attempt.insertBatch("-.../-.-./", at: start.addingTimeInterval(1))
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.sectionProgress?.completed, 3)
    XCTAssertEqual(attempt.completedWordCount, 3)
    XCTAssertEqual(attempt.errors, 0)
  }

  func testMorseWordBudgetUsesTheTwoLiteralPipeCandidates() {
    var attempt = TestSessionFactory.make(configuration: configuration(.words), customText: "a|\u{301}b")
    XCTAssertEqual(attempt.prompt, ".-/-.../")
    attempt.insertBatch(".-/-.../", at: start)
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.completedWordCount, 2)
    XCTAssertEqual(attempt.wordReviews.map(\.target), [".-/", "-.../"])
    XCTAssertEqual(attempt.errors, 0)
  }

  func testBackwardsRetainsTheMarkButNotTheLiteralPipeInItsTargets() {
    var attempt = TestSessionFactory.make(configuration: configuration(modifiers: [.noSpaces, .backwards]),
      customText: "a|\u{301}b")
    XCTAssertEqual(attempt.prompt, "b\u{301}a")
    attempt.insertBatch("b\u{301}a", at: start)
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.completedWordCount, 2)
    XCTAssertEqual(attempt.sectionProgress?.completed, 2)
    XCTAssertEqual(attempt.wordReviews.map(\.target), ["b\u{301}", "a"])
    XCTAssertEqual(attempt.errors, 0)
  }

  func testCombiningSourceWordsRemainBoundedTo100ThenContinueAndRepeat() throws {
    let source = Array(repeating: "\u{301}a", count: 102).joined(separator: " ")
    var attempt = TestSessionFactory.make(configuration: configuration(.finish), customText: source)
    let initial = String(repeating: ".-/", count: 100)
    let target = String(repeating: ".-/", count: 102)
    XCTAssertEqual(attempt.prompt, initial)
    XCTAssertTrue(attempt.usesIncrementalPromptExtension)
    var repeated = attempt.repeatedAttempt()
    attempt.insertBatch(target, at: start)
    repeated.insertBatch(target, at: start)
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.completedWordCount, 102)
    XCTAssertEqual(attempt.wordReviews.map(\.target), Array(repeating: ".-/", count: 102))
    XCTAssertEqual(attempt.prompt, target)
    XCTAssertEqual(attempt.errors, 0)
    XCTAssertEqual(repeated.wordReviews, attempt.wordReviews)
    XCTAssertEqual(repeated.outcome, .completed)
    let result = try XCTUnwrap(attempt.result())
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 1), target)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
  }
}
