import XCTest
@testable import Typebar

final class WordPracticeCandidatePoolTests: XCTestCase {
  func testEntryKeepsWeightedCandidatesInsteadOfExpandingTheCompletionLimit() throws {
    let candidates = ["amber", "amber", "left a|b", "e\u{301}"]
    let practice = try XCTUnwrap(WordPracticeText.sectionedPractice(
      segments: candidates, selectedTargetCount: 2))
    XCTAssertEqual(practice.sections.map { Array($0.utf16) }, candidates.map { Array($0.utf16) })
    XCTAssertEqual(practice.sectionCount, 10)
    XCTAssertEqual(practice.ordering, .shuffled)
    XCTAssertEqual(Array(practice.text.utf16), Array(candidates.joined(separator: " | ").utf16))
  }

  func testACompletionLimitSmallerThanThePoolDoesNotDiscardCandidates() throws {
    let candidates = (0..<12).map { "candidate\($0)" }
    let practice = try XCTUnwrap(WordPracticeText.sectionedPractice(
      segments: candidates, selectedTargetCount: 1))
    XCTAssertEqual(practice.sections, candidates)
    XCTAssertEqual(practice.sectionCount, 5)
  }

  func testWeightedBagsCompleteAcrossChunksAndRepeatTheActualGeneratedAttempt() throws {
    let practice = try XCTUnwrap(WordPracticeText.sectionedPractice(
      segments: ["amber", "amber", "cabin"], selectedTargetCount: 30))
    let configuration = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), customTextCompletion: .sections,
      customTextSectionLimit: practice.sectionCount, customTextOrdering: practice.ordering,
      customTextPipeDelimiter: true)
    var session = TestSessionFactory.make(configuration: configuration, customText: practice.text,
      preparedCustomSections: practice.sections, nextRandomWordIndex: { 0 })
    let opening = session.prompt
    let start = Date(timeIntervalSince1970: 1_000)
    XCTAssertTrue(session.usesIncrementalPromptExtension)
    for _ in 0..<10 where session.outcome != .completed {
      session.insertBatch(String(session.prompt.dropFirst(session.typed.count)), at: start)
    }
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.sectionProgress?.completed, 150)
    let targets = session.wordReviews.map(\.target)
    XCTAssertEqual(targets.count, 150)
    for offset in stride(from: 0, to: targets.count, by: 3) {
      XCTAssertEqual(Array(targets[offset..<min(offset + 3, targets.count)]).sorted(), ["amber", "amber", "cabin"])
    }
    var repeated = session.repeatedAttempt()
    XCTAssertEqual(repeated.prompt, opening)
    repeated.insertBatch(session.prompt, at: start.addingTimeInterval(1))
    XCTAssertEqual(repeated.outcome, .completed)
    XCTAssertEqual(repeated.wordReviews.map(\.target), targets)
  }

  func testSingleCandidateRepeatsWithoutChangingStoredSourceAndInvalidCountsAreRejected() throws {
    let practice = try XCTUnwrap(WordPracticeText.sectionedPractice(segments: ["only"], selectedTargetCount: 2))
    XCTAssertEqual(practice.sections, ["only"])
    XCTAssertEqual(practice.sectionCount, 10)
    XCTAssertNil(WordPracticeText.sectionedPractice(segments: [], selectedTargetCount: 2))
    XCTAssertNil(WordPracticeText.sectionedPractice(segments: ["only"], selectedTargetCount: 0))
    XCTAssertNil(WordPracticeText.sectionedPractice(segments: ["only"], selectedTargetCount: -1))
    XCTAssertNil(WordPracticeText.sectionedPractice(segments: ["only"], selectedTargetCount: Int.max))
  }
}
