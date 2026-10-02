import XCTest
@testable import Typebar

final class ReplayActionSoundTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 875_100_000)

  private func result(_ input: TypingSession) throws -> CompletedTestResult {
    var ended = input
    ended.bailOut(at: start.addingTimeInterval(5))
    return try XCTUnwrap(ended.result())
  }

  private func cues(_ result: CompletedTestResult, after: TimeInterval = 0.5,
    through: TimeInterval = 1.5) -> [TypingReplaySoundCue] {
    TypingReplay.soundCues(prompt: result.prompt, events: result.replayEvents, after: after, through: through)
  }

  func testAutomaticIndentHasItsOwnClickAndThePriorWordSubmissionClick() throws {
    var input = TypingSession(configuration: .words(3, language: .codeSwift), prompt: "ab\n\tgo()\ntail")
    input.insertBatch("ab", at: start)
    input.insertBatch("\n", at: start.addingTimeInterval(1))
    XCTAssertEqual(input.typed, "ab\n\t")
    XCTAssertEqual(cues(try result(input)), [.click, .click, .click])
  }

  func testAutomaticWordErrorDeletionPlaysOneActionClick() throws {
    var input = TypingSession(configuration: .words(2, rules: .init(deleteOnErrorMode: .word)), prompt: "ab cd")
    input.insertBatch("a", at: start)
    input.insertBatch("x", at: start.addingTimeInterval(1))
    XCTAssertEqual(input.typed, "")
    XCTAssertEqual(cues(try result(input)), [.error, .click])
  }

  func testAutomaticLetterErrorDeletionPlaysBothDistinctClicks() throws {
    var input = TypingSession(configuration: .words(2, rules: .init(deleteOnErrorMode: .letter)), prompt: "ab cd")
    input.insertBatch("a", at: start)
    input.insertBatch("x", at: start.addingTimeInterval(1))
    XCTAssertEqual(input.typed, "")
    XCTAssertEqual(cues(try result(input)), [.error, .click, .click])
  }

  func testHardRecoveryKeepsSubmissionAttemptAndBothAutomaticActions() throws {
    for mode in [DeleteOnErrorMode.wordHard, .letterHard] {
      var input = TypingSession(configuration: .words(2, rules: .init(deleteOnErrorMode: mode)), prompt: "ab cd")
      input.insertBatch("ab ", at: start)
      input.insertBatch("x", at: start.addingTimeInterval(1))
      // The final previous field is empty for word-hard and ab for letter-hard,
      // so both historical submissions are errors against the committed target ab-space.
      XCTAssertEqual(cues(try result(input)), [.error, .error, .click, .click])
    }
  }

  func testForwardTransitionHasSubmissionAndNextLetterAtTheNextInputTime() throws {
    var input = TypingSession(configuration: .words(2), prompt: "ab cd")
    input.insertBatch("ab ", at: start)
    input.insertBatch("c", at: start.addingTimeInterval(1))
    XCTAssertEqual(cues(try result(input)), [.click, .click])
  }

  func testWrongWordSubmissionIsSeparateFromCorrectlyPositionedSeparator() throws {
    var input = TypingSession(configuration: .words(2), prompt: "ab cd")
    input.insertBatch("ax", at: start)
    input.insertBatch(" ", at: start.addingTimeInterval(1))
    input.insertBatch("c", at: start.addingTimeInterval(2))
    let ended = try result(input)
    XCTAssertEqual(cues(ended), [.click])
    XCTAssertEqual(cues(ended, after: 1.5, through: 2.5), [.error, .click])
  }

  func testEarlySeparatorIsAnIncorrectKeyEvenWithoutAPriorMistake() throws {
    var input = TypingSession(configuration: .words(2), prompt: "ab cd")
    input.insertBatch("a", at: start)
    input.insertBatch(" ", at: start.addingTimeInterval(1))
    XCTAssertEqual(cues(try result(input)), [.error])
  }

  func testSubmissionUsesTheFinalCorrectedFieldRatherThanItsEarlierSpelling() throws {
    var input = TypingSession(configuration: .words(2, rules: .init(freedomMode: true)), prompt: "ab cd")
    input.insertBatch("ax ", at: start)
    input.insertBatch("c", at: start.addingTimeInterval(1))
    input.deleteWordBackward(at: start.addingTimeInterval(2))
    input.deleteWordBackward(at: start.addingTimeInterval(2.1))
    input.insertBatch("ab ", at: start.addingTimeInterval(3))
    input.insertBatch("c", at: start.addingTimeInterval(4))
    XCTAssertEqual(cues(try result(input)), [.click, .click])
  }

  func testLaterClearedOrWrongFieldChangesItsHistoricalSubmissionCue() throws {
    var input = TypingSession(configuration: .words(2, rules: .init(freedomMode: true)), prompt: "ab cd")
    input.insertBatch("ab ", at: start)
    input.insertBatch("c", at: start.addingTimeInterval(1))
    input.deleteWordBackward(at: start.addingTimeInterval(2))
    input.deleteWordBackward(at: start.addingTimeInterval(2.1))
    input.insertBatch("ax ", at: start.addingTimeInterval(3))
    input.insertBatch("c", at: start.addingTimeInterval(4))
    XCTAssertEqual(cues(try result(input)), [.error, .click])
  }

  func testZenContextMakesItsOwnLettersAndSubmissionsCorrect() throws {
    let configuration = TestConfiguration(mode: .zen, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init())
    var input = TypingSession(configuration: configuration, prompt: "")
    input.insertBatch("ab ", at: start)
    input.insertBatch("z", at: start.addingTimeInterval(1))
    let ended = try result(input)
    XCTAssertEqual(TypingReplay.soundCues(prompt: ended.prompt, events: ended.replayEvents,
      after: 0.5, through: 1.5, configuration: ended.configuration), [.click, .click])
  }

  func testPreparedTimelineAndDirectQueriesAgreeAcrossPlaybackWindows() throws {
    var input = TypingSession(configuration: .words(2, rules: .init(deleteOnErrorMode: .wordHard)), prompt: "ab cd")
    input.insertBatch("ab ", at: start)
    input.insertBatch("x", at: start.addingTimeInterval(1))
    input.insertBatch("ab c", at: start.addingTimeInterval(2))
    let ended = try result(input)
    let timeline = TypingReplay.soundTimeline(prompt: ended.prompt, events: ended.replayEvents)
    for (lower, upper) in [(-1.0, 0.0), (0, 1), (1, 1), (1, 2), (2, 3), (2, 1), (0.5, 2.5)] {
      XCTAssertEqual(TypingReplay.soundCues(in: timeline, after: lower, through: upper),
        TypingReplay.soundCues(prompt: ended.prompt, events: ended.replayEvents, after: lower, through: upper))
    }
    let split = TypingReplay.soundCues(in: timeline, after: -1, through: 0)
      + TypingReplay.soundCues(in: timeline, after: 0, through: 1)
      + TypingReplay.soundCues(in: timeline, after: 1, through: 2)
    XCTAssertEqual(split, timeline.map(\.cue))
    XCTAssertEqual(TypingReplay.soundCues(in: timeline, after: 1, through: 1), [])
  }

  func testSoundPreparationDoesNotChangeReplayStatsArchiveOrStoredFields() throws {
    var input = TypingSession(configuration: .words(2, rules: .init(deleteOnErrorMode: .word)), prompt: "ab cd")
    input.insertBatch("a", at: start)
    input.insertBatch("x", at: start.addingTimeInterval(1))
    input.insertBatch("ab cd", at: start.addingTimeInterval(2))
    let ended = try XCTUnwrap(input.result())
    let encoded = try JSONEncoder().encode(ended)
    let trace = ResultPerformanceTrace.points(prompt: ended.prompt, events: ended.replayEvents, duration: 2)
    _ = TypingReplay.soundTimeline(prompt: ended.prompt, events: ended.replayEvents, configuration: ended.configuration)
    XCTAssertEqual(try JSONDecoder().decode(CompletedTestResult.self, from: encoded), ended)
    XCTAssertEqual(ResultPerformanceTrace.points(prompt: ended.prompt, events: ended.replayEvents, duration: 2), trace)
    let portable = try XCTUnwrap(TestResultRecord(result: ended).portableResult)
    let imported = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [ended], presets: [], at: start))
    for restored in [ended, portable, imported.results[0]] {
      XCTAssertEqual(cues(restored), [.error, .click])
      XCTAssertEqual(restored.replayEvents, ended.replayEvents)
      XCTAssertEqual(TypingReplay.typedText(events: restored.replayEvents, through: 2), "ab cd")
      XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: restored.replayEvents), ["ab ", "cd"])
    }
  }

  func testRetainedSeparatorDoesNotInventANewWordSubmission() {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "ax"),
      .init(offset: 1, kind: .insert, text: " ", commitsWord: false),
      .init(offset: 2, kind: .insert, text: "b")
    ]
    XCTAssertEqual(TypingReplay.soundCues(prompt: "ab cd", events: events, after: 1.5, through: 2.5), [.error])
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: events), ["ax b"])
  }

  func testSeparateSameTimeBackspacesRemainAudibleAndNonFiniteEventsDoNotPoisonOrder() {
    let events: [TypingReplayEvent] = [
      .init(offset: .nan, kind: .insert, text: "unrecordable"),
      .init(offset: 0, kind: .insert, text: "ab"),
      .init(offset: 1, kind: .delete, text: ""),
      .init(offset: 1, kind: .delete, text: "")
    ]
    XCTAssertEqual(TypingReplay.soundCues(prompt: "ab cd", events: events, after: 0.5, through: 1.5), [.click, .click])
    XCTAssertTrue(TypingReplay.soundTimeline(prompt: "ab cd", events: events).allSatisfy { $0.offset.isFinite })
  }

  func testEmptyLegacyInsertDoesNotConsumeAnUnplayedSubmission() {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "ab "),
      .init(offset: 0.5, kind: .insert, text: ""),
      .init(offset: 1, kind: .insert, text: "c")
    ]
    XCTAssertEqual(TypingReplay.soundCues(prompt: "ab cd", events: events, after: 0.25, through: 0.75), [])
    XCTAssertEqual(TypingReplay.soundCues(prompt: "ab cd", events: events, after: 0.75, through: 1.25), [.click, .click])
  }

  func testPreparedLargeTapeServesNarrowWindowsWithoutChangingCueCardinality() {
    let count = 2_000
    let prompt = Array(repeating: "ab", count: count).joined(separator: " ")
    let events = prompt.enumerated().map { TypingReplayEvent(offset: Double($0.offset) / 100,
      kind: .insert, text: String($0.element)) }
    let timeline = TypingReplay.soundTimeline(prompt: prompt, events: events)
    XCTAssertEqual(timeline.count, 4 * count - 2)
    XCTAssertTrue(timeline.allSatisfy { $0.cue == .click })
    for index in 0..<100 {
      let lower = Double(index) / 100
      let expected = timeline.filter { $0.offset > lower && $0.offset <= lower + 0.01 }.map(\.cue)
      XCTAssertEqual(TypingReplay.soundCues(in: timeline, after: lower, through: lower + 0.01), expected)
    }
  }

  func testSubmissionComparesFinalFieldWithExactSpelling() {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "é "),
      .init(offset: 1, kind: .insert, text: "c")
    ]
    XCTAssertEqual(TypingReplay.soundCues(prompt: "e\u{301} cd", events: events, after: 0.5, through: 1.5), [.error, .click])
  }
}
