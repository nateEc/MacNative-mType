import XCTest
@testable import Typebar

final class FieldReplaySoundTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 907_400_000)

  private func delayedResult(finish: Bool = false) throws -> CompletedTestResult {
    var input = TypingSession(configuration: .words(2,
      rules: .init(deleteOnErrorMode: .letter), language: .codeSwift), prompt: "a \tb")
    input.insertBatch("a ", at: start, defersAutomaticInput: true)
    input.insertBatch("\t", at: start.addingTimeInterval(1), defersAutomaticInput: true)
    XCTAssertEqual(input.processNextAutomaticInput(for: input.automaticInputAttemptID,
      executedAt: start.addingTimeInterval(3)), [false])
    XCTAssertEqual(input.typed, "a ")
    if finish { input.insertBatch("\tb", at: start.addingTimeInterval(4)) }
    else { input.bailOut(at: start.addingTimeInterval(4)) }
    return try XCTUnwrap(input.result())
  }

  func testDelayedTabUsesCapturedInputPositionNotTheEarlierReplayPosition() throws {
    let result = try delayedResult()
    let timeline = TypingReplay.soundTimeline(prompt: result.prompt, events: result.replayEvents)
    XCTAssertEqual(timeline.map(\.offset), [0, 0, 0, 0, 0, 0, 1])
    XCTAssertEqual(timeline.map(\.cue), [.click, .click, .click, .error, .click, .click, .click])
  }

  func testLaterCorrectKeysDoNotInheritAFalseCrossWordDeletion() throws {
    let result = try delayedResult(finish: true)
    XCTAssertEqual(TypingReplay.soundCues(prompt: result.prompt, events: result.replayEvents,
      after: 3.5, through: 4.5), [.click, .click])
  }

  func testDelayedRecoveryActionsRetainTheirOriginalTimeWindow() throws {
    let result = try delayedResult()
    XCTAssertEqual(TypingReplay.soundCues(prompt: result.prompt, events: result.replayEvents,
      after: -1, through: 0), [.click, .click, .click, .error, .click, .click])
    XCTAssertEqual(TypingReplay.soundCues(prompt: result.prompt, events: result.replayEvents,
      after: 0, through: 1), [.click])
  }

  func testWholeWordRegressionHasOnlyOneDestinationActionClick() throws {
    var input = TypingSession(configuration: .words(3, rules: .init(freedomMode: true)),
      prompt: "ab cd tail")
    input.insertBatch("ab cd t", at: start)
    input.deleteWordBackward(at: start.addingTimeInterval(1))
    input.deleteWordBackward(at: start.addingTimeInterval(2))
    input.bailOut(at: start.addingTimeInterval(4))
    XCTAssertEqual(input.typed, "ab ")
    let result = try XCTUnwrap(input.result())
    XCTAssertEqual(TypingReplay.soundCues(prompt: result.prompt, events: result.replayEvents,
      after: 1.5, through: 2.5), [.click])
    XCTAssertEqual(result.replayEvents.last?.inputField, .init(index: 1, value: ""))
  }

  func testGroupedDeletionUsesItsLastSnapshotRatherThanItsFirst() {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "ab ", inputField: .init(index: 0, value: "ab ")),
      .init(offset: 1, kind: .insert, text: "c", inputField: .init(index: 1, value: "c")),
      .init(offset: 2, kind: .delete, text: "", wordDeletionCount: 2,
        inputField: .init(index: 1, value: "")),
      .init(offset: 2, kind: .delete, text: "", inputField: .init(index: 0, value: "ab")),
      .init(offset: 3, kind: .insert, text: " ", inputField: .init(index: 0, value: "ab "))
    ]
    XCTAssertEqual(TypingReplay.soundCues(prompt: "ab cd", events: events,
      after: 1.5, through: 2.5), [.click])
    XCTAssertEqual(TypingReplay.soundCues(prompt: "ab cd", events: events,
      after: 2.5, through: 3.5), [.click])
  }

  func testInvalidGroupedDeletionDoesNotHideSeparateActionClicks() {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "ab", inputField: .init(index: 0, value: "ab")),
      .init(offset: 1, kind: .delete, text: "", wordDeletionCount: 99,
        inputField: .init(index: 0, value: "a")),
      .init(offset: 1, kind: .delete, text: "", inputField: .init(index: 0, value: ""))
    ]
    XCTAssertEqual(TypingReplay.soundCues(prompt: "ab cd", events: events,
      after: 0.5, through: 1.5), [.click, .click])
  }

  func testStoppedFirstInputInTheNextFieldStillEmitsTheSubmission() throws {
    var input = TypingSession(configuration: .words(2, rules: .init(stopOnErrorMode: .letter)),
      prompt: "ab cd")
    input.insertBatch("ab ", at: start)
    input.insertBatch("x", at: start.addingTimeInterval(1))
    input.insertBatch("c", at: start.addingTimeInterval(2))
    input.bailOut(at: start.addingTimeInterval(3))
    let result = try XCTUnwrap(input.result())
    XCTAssertEqual(TypingReplay.soundCues(prompt: result.prompt, events: result.replayEvents,
      after: 0.5, through: 1.5), [.click])
    XCTAssertEqual(TypingReplay.soundCues(prompt: result.prompt, events: result.replayEvents,
      after: 1.5, through: 2.5), [.click])
  }

  func testStoppedRegressionEmitsBackWordButNoStoppedLetter() {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "c", inputField: .init(index: 1, value: "c")),
      .init(offset: 1, kind: .insert, text: "x", inputStopped: true,
        inputField: .init(index: 0, value: "a"))
    ]
    XCTAssertEqual(TypingReplay.soundCues(prompt: "ab cd", events: events,
      after: 0.5, through: 1.5), [.click])
  }

  func testForwardJumpUsesOneSourceTransitionNotOnePerSkippedField() {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "a", inputField: .init(index: 0, value: "a")),
      .init(offset: 0, kind: .insert, text: " ", inputField: .init(index: 0, value: "a ")),
      .init(offset: 1, kind: .insert, text: "c", inputField: .init(index: 2, value: "c"))
    ]
    XCTAssertEqual(TypingReplay.soundCues(prompt: "a b c", events: events,
      after: 0.5, through: 1.5), [.click, .click])
  }

  func testSubmissionLooksUpFinalFieldByIndexNotFirstAppearanceOrder() {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "b", inputField: .init(index: 1, value: "b")),
      .init(offset: 1, kind: .insert, text: "a", inputField: .init(index: 0, value: "a")),
      .init(offset: 1, kind: .insert, text: " ", inputField: .init(index: 0, value: "a ")),
      .init(offset: 2, kind: .insert, text: "b", inputField: .init(index: 1, value: "b"))
    ]
    XCTAssertEqual(TypingReplay.soundCues(prompt: "a b", events: events,
      after: 1.5, through: 2.5), [.click, .click])
  }

  func testCombiningMarkJudgmentsUseCapturedUTF16Positions() throws {
    var input = TypingSession(configuration: .words(2), prompt: "e\u{301} cd")
    input.insertBatch("e", at: start)
    input.insertBatch("\u{301}", at: start.addingTimeInterval(1))
    input.bailOut(at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(input.result())
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: result.prompt,
      events: result.replayEvents).map(\.cue), [.click, .click])
  }

  func testForcedErrorOverridesMatchingCapturedText() {
    let event = TypingReplayEvent(offset: 0, kind: .insert, text: "a", forceError: true,
      inputField: .init(index: 0, value: "a"))
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: "ab", events: [event]).map(\.cue), [.error])
  }

  func testExplicitNoSpaceKeepsTheExistingUnsegmentedTargetPath() throws {
    let configuration = TestConfiguration.words(2).with(modifiers: [.noSpaces])
    var input = TypingSession(configuration: configuration, prompt: "abcd", noSpaceWordEndIndices: [2, 4])
    input.insertBatch("abcd", at: start)
    let result = try XCTUnwrap(input.result())
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: result.prompt, events: result.replayEvents,
      configuration: configuration).map(\.cue), [.click, .click, .click, .click])
    // The flattened saved target also lacks enough fields without config.
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: result.prompt,
      events: result.replayEvents).map(\.cue), [.click, .click, .click, .click])
  }

  func testMixedAndLegacyTapesDoNotGuessTheMissingFieldPositions() throws {
    let events = try delayedResult().replayEvents
    for keepsFirstField in [false, true] {
      let legacy = events.enumerated().map { index, event in
        TypingReplayEvent(offset: event.offset, kind: event.kind, text: event.text,
          forceError: event.forceError, automatic: event.automatic,
          commitsWord: event.commitsWord, wordDeletionCount: event.wordDeletionCount,
          characterDeletionCount: event.characterDeletionCount, inputStopped: event.inputStopped,
          inputField: keepsFirstField && index == 0 ? event.inputField : nil)
      }
      XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: legacy), ["a\t", ""])
      XCTAssertEqual(TypingReplay.soundTimeline(prompt: "a \tb", events: legacy).map(\.cue),
        [.click, .click, .error, .click, .click, .click, .error])
    }
  }

  func testUnknownTargetFieldDoesNotAllocateOrInventMissingTargetWords() {
    for index in [-1, Int.max] {
      let event = TypingReplayEvent(offset: 0, kind: .insert, text: "a",
        inputField: .init(index: index, value: "a"))
      XCTAssertEqual(TypingReplay.soundTimeline(prompt: "ab", events: [event]).map(\.cue), [.click])
    }
  }

  func testZenHasNoTargetMismatchOrUnboundedPlaceholderAllocation() {
    let configuration = TestConfiguration(mode: .zen, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init())
    let event = TypingReplayEvent(offset: 0, kind: .insert, text: "z", forceError: true,
      inputField: .init(index: Int.max, value: "z"))
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: "", events: [event],
      configuration: configuration).map(\.cue), [.click])
  }

  func testPreparedWindowsAndSoundRoutesKeepEveryActionExactlyOnce() throws {
    let result = try delayedResult(finish: true)
    let timeline = TypingReplay.soundTimeline(prompt: result.prompt, events: result.replayEvents)
    let windows: [(Double, Double)] = [(-1, 0), (0, 1), (1, 4), (4, 5)]
    let cues = windows.flatMap { low, high in
      let prepared = TypingReplay.soundCues(in: timeline, after: low, through: high)
      XCTAssertEqual(prepared, TypingReplay.soundCues(prompt: result.prompt,
        events: result.replayEvents, after: low, through: high))
      return prepared
    }
    XCTAssertEqual(cues, timeline.map(\.cue))
    XCTAssertEqual(cues.filter { $0 == .error }.count, 1)
    XCTAssertEqual(TypingReplaySoundRoute.resolve(cue: .error, playsClicks: true, playsErrors: false), .click)
    XCTAssertEqual(TypingReplaySoundRoute.resolve(cue: .error, playsClicks: false, playsErrors: false), .none)
  }

  func testPortableAndFormalArchiveRetainSoundClassificationWithoutMutatingTheTape() throws {
    let result = try delayedResult(finish: true)
    let before = try JSONEncoder().encode(result)
    let portable = try XCTUnwrap(TestResultRecord(result: result).portableResult)
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [], at: start))
    XCTAssertEqual(archive.version, 12)
    for restored in [result, portable, archive.results[0]] {
      XCTAssertEqual(TypingReplay.soundTimeline(prompt: restored.prompt, events: restored.replayEvents).map(\.cue),
        [.click, .click, .click, .error, .click, .click, .click, .click, .click])
      XCTAssertEqual(restored.replayEvents, result.replayEvents)
      XCTAssertEqual(restored.inputMetrics, result.inputMetrics)
    }
    XCTAssertEqual(try JSONDecoder().decode(CompletedTestResult.self, from: before), result)
  }

  func testNonFiniteEventsCannotDisableOrPoisonTheRecordedTimeline() throws {
    let result = try delayedResult()
    let invalid = TypingReplayEvent(offset: .nan, kind: .insert, text: "discarded",
      inputField: .init(index: Int.max, value: "discarded"))
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: result.prompt, events: [invalid] + result.replayEvents),
      TypingReplay.soundTimeline(prompt: result.prompt, events: result.replayEvents))
  }

  func testLargeCapturedTapeKeepsOneSubmissionPerFieldAndWindowCardinality() throws {
    let count = 1_000
    let prompt = Array(repeating: "ab", count: count).joined(separator: " ")
    var input = TypingSession(configuration: .words(count), prompt: prompt)
    input.insertBatch(prompt, at: start)
    let result = try XCTUnwrap(input.result())
    let timeline = TypingReplay.soundTimeline(prompt: prompt, events: result.replayEvents)
    XCTAssertEqual(timeline.count, 4 * count - 2)
    XCTAssertTrue(timeline.allSatisfy { $0.cue == .click && $0.offset == 0 })
    XCTAssertEqual(TypingReplay.soundCues(in: timeline, after: -1, through: 0).count, timeline.count)
    XCTAssertEqual(TypingReplay.soundCues(in: timeline, after: 0, through: 1), [])
  }
}
