import XCTest
@testable import Typebar

final class StoppedInputHistoryTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 907_200_000)

  func testStoppedLetterIsLoggedAndCountedButNeverBecomesReplayTextOrSound() throws {
    var input = TypingSession(configuration: .words(1, rules: .init(stopOnErrorMode: .letter)), prompt: "ab")
    input.insertBatch("a", at: start)
    XCTAssertEqual(input.insertBatch("x", at: start.addingTimeInterval(0.2)), [false])
    XCTAssertEqual(input.typed, "a")
    input.insertBatch("b", at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(input.result())
    XCTAssertEqual(result.replayEvents.map(\.text), ["a", "x", "b"])
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 3)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 1), "ab")
    XCTAssertEqual(TypingReplay.inputGlyphs(prompt: result.prompt, events: result.replayEvents,
      through: 1).map(\.character), Array("ab"))
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: result.prompt,
      events: result.replayEvents).map(\.cue), [.click, .click])
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: result.replayEvents), ["ab"])
    let trace = ResultPerformanceTrace.points(prompt: result.prompt, events: result.replayEvents,
      duration: 1, configuration: result.configuration)
    XCTAssertEqual(trace.map(\.errorCount), [1])
    XCTAssertEqual(trace.map(\.burstWpm), [36])
    XCTAssertEqual(trace.map(\.rawWpm), [24])
  }

  func testOppositeShiftRejectionRecordsAnIncorrectAttemptWithoutMovingReplayCursor() throws {
    var input = TypingSession(configuration: .words(1, rules: .init(oppositeShiftMode: .on)), prompt: "a")
    input.insertBatch("a", forceError: true, at: start)
    XCTAssertEqual(input.typed, "")
    input.insertBatch("a", at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(input.result())
    XCTAssertEqual(result.replayEvents.count, 2)
    XCTAssertEqual(result.preciseAccuracy, 50)
    XCTAssertEqual(ResultPerformanceTrace.points(prompt: result.prompt, events: result.replayEvents,
      duration: 1, configuration: result.configuration).map(\.errorCount), [1])
    XCTAssertEqual(TypingReplay.characterSeekOffsets(prompt: result.prompt,
      events: result.replayEvents), [0: 1])
  }

  func testStoppedZenShiftIsCorrectActivityButNotAcceptedText() throws {
    var input = TypingSession(configuration: .init(mode: .zen, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(oppositeShiftMode: .on)), prompt: "")
    input.insertBatch("x", forceError: true, at: start)
    input.insertBatch("a", at: start.addingTimeInterval(0.2))
    input.finishZen(at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(input.result())
    XCTAssertEqual(result.replayEvents.map(\.text), ["x", "a"])
    XCTAssertEqual(result.preciseAccuracy, 100)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 1), "a")
    let trace = ResultPerformanceTrace.points(prompt: result.prompt, events: result.replayEvents,
      duration: 1, configuration: result.configuration)
    XCTAssertEqual(trace.map(\.errorCount), [0])
    XCTAssertEqual(trace.map(\.burstWpm), [24])
    XCTAssertEqual(trace.map(\.rawWpm), [12])
  }

  func testPreInsertionRejectionStillCreatesNoAttemptOrLog() throws {
    var input = TypingSession(configuration: .words(1, rules: .init(stopOnErrorMode: .letter)), prompt: "a")
    XCTAssertEqual(input.insertBatch("\n ", at: start), [])
    XCTAssertFalse(input.hasStarted)
    input.insertBatch("a", at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(input.result())
    XCTAssertEqual(result.replayEvents.map(\.text), ["a"])
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 1)
  }

  func testStoppedWrongLetterStillFailsMasterDifficulty() throws {
    var configuration = TestConfiguration.words(1, rules: .init(stopOnErrorMode: .letter))
    configuration.difficulty = .master
    var input = TypingSession(configuration: configuration, prompt: "ab")
    XCTAssertEqual(input.insertBatch("x", at: start), [false])
    XCTAssertEqual(input.typed, "")
    XCTAssertEqual(input.outcome, .failed)
    XCTAssertEqual(try XCTUnwrap(input.result()).replayEvents.map(\.text), ["x"])
  }

  private func completedStoppedResult() throws -> CompletedTestResult {
    var input = TypingSession(configuration: .words(1, rules: .init(stopOnErrorMode: .letter)), prompt: "ab")
    input.insertBatch("ax", at: start)
    input.insertBatch("b", at: start.addingTimeInterval(1))
    return try XCTUnwrap(input.result())
  }

  private func archiveData(_ archive: TypebarArchive) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(archive)
  }

  func testNewMarkerRoundTripsAndLegacyJSONDoesNotInventStoppedInput() throws {
    let legacy = try JSONDecoder().decode(TypingReplayEvent.self,
      from: Data(#"{"offset":0,"kind":"insert","text":"a"}"#.utf8))
    XCTAssertNil(legacy.inputStopped)
    XCTAssertFalse(legacy.isStoppedInsertion)
    let oldObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy))
      as? [String: Any])
    XCTAssertNil(oldObject["inputStopped"])
    for flag in [true, false] {
      let event = TypingReplayEvent(offset: 0, kind: .insert, text: "x", inputStopped: flag)
      XCTAssertEqual(try JSONDecoder().decode(TypingReplayEvent.self,
        from: JSONEncoder().encode(event)), event)
      XCTAssertEqual(TypingReplay.typedText(events: [event], through: 1), flag ? "" : "x")
    }
  }

  func testPortableRecordAndFormalArchivePreserveStoppedAttempts() throws {
    let result = try completedStoppedResult()
    let portable = try XCTUnwrap(TestResultRecord(result: result).portableResult)
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [], at: start))
    XCTAssertEqual(archive.version, 11)
    for restored in [portable, archive.results[0]] {
      XCTAssertEqual(restored, result)
      XCTAssertEqual(restored.replayEvents.map(\.inputStopped), [nil, true, nil])
      XCTAssertEqual(TypingReplay.typedText(events: restored.replayEvents, through: 1), "ab")
      XCTAssertEqual(ResultPerformanceTrace.points(prompt: restored.prompt,
        events: restored.replayEvents, duration: 1).map(\.errorCount), [1])
    }
  }

  func testArchiveConstructionCannotMislabelStoppedTapeAsLegacyVersion() throws {
    let result = try completedStoppedResult()
    for version in 1...10 {
      let archive = TypebarArchive(version: version, exportedAt: start, settings: .init(),
        results: [result], presets: [])
      XCTAssertEqual(archive.version, 11)
      XCTAssertEqual(try TypebarDataTransfer.importArchive(from: archiveData(archive)).results, [result])
    }
  }

  func testForgedLegacyArchiveWithNewStoppedTapeIsRejectedWithoutDroppingIt() throws {
    let data = try TypebarDataTransfer.exportArchive(settings: .init(),
      results: [completedStoppedResult()], presets: [], at: start)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["version"] = 10
    let forged = try JSONSerialization.data(withJSONObject: object)
    XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: forged)) {
      XCTAssertEqual($0 as? DataTransferError, .unsupportedVersion(10))
    }
  }

  func testAllEarlierArchiveGenerationsRemainReadableWithoutNewMarkers() throws {
    for version in 1...10 {
      let legacy = TypebarArchive(version: version, exportedAt: start, settings: .init(),
        results: [], presets: [])
      XCTAssertEqual(legacy.version, version)
      XCTAssertEqual(try TypebarDataTransfer.importArchive(from: archiveData(legacy)).version, version)
    }
  }

  func testStoppedAttemptDoesNotBecomeADeletionCheckpointOrSeekTarget() {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "a"),
      .init(offset: 0.2, kind: .insert, text: "x", inputStopped: true),
      .init(offset: 0.3, kind: .delete, text: ""),
      .init(offset: 0.4, kind: .insert, text: "ab")
    ]
    XCTAssertEqual(TypingReplay.typedText(events: events, through: 0.3), "")
    XCTAssertEqual(TypingReplay.inputGlyphs(prompt: "ab", events: events, through: 0.3), [])
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: events), ["ab"])
    XCTAssertEqual(TypingReplay.characterSeekOffsets(prompt: "ab", events: events), [0: 0, 1: 0.4])
    XCTAssertEqual(TypingReplay.actions(events: events).map(\.primitiveRange), [0..<1, 2..<3, 3..<4])
    let trace = ResultPerformanceTrace.points(prompt: "ab", events: events, duration: 1)
    XCTAssertEqual(trace.map(\.errorCount), [1])
    XCTAssertEqual(trace.map(\.rawWpm), [24])
  }

  func testStoppedFirstKeyPreservesAnEmptyHistoryFieldWithoutTextOrReplayAction() throws {
    var input = TypingSession(configuration: .words(1, rules: .init(stopOnErrorMode: .letter)), prompt: "ab")
    input.insertBatch("x", at: start)
    input.bailOut(at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(input.result())
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: result.replayEvents), [""])
    XCTAssertEqual(TypingReplay.actions(events: result.replayEvents).count, 0)
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: "ab", events: result.replayEvents), [])
  }

  func testStoppedFirstKeyInNextWordStillTriggersOnlyPriorSubmissionCue() {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "ab "),
      .init(offset: 1, kind: .insert, text: "x", inputStopped: true),
      .init(offset: 2, kind: .insert, text: "c")
    ]
    XCTAssertEqual(TypingReplay.soundCues(prompt: "ab cd", events: events,
      after: 0.5, through: 1.5), [.click])
    XCTAssertEqual(TypingReplay.soundCues(prompt: "ab cd", events: events,
      after: 1.5, through: 2.5), [.click])
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: events), ["ab ", "c"])
  }

  func testWeakSpotIncludesStoppedErrorButDoesNotAdvanceItsTarget() throws {
    let result = try completedStoppedResult()
    XCTAssertEqual(WeakSpotPractice.characterScores(results: [result], language: .english), ["b": 1])
  }

  func testMasterChecksOnlyFinalUnitOfBatchWhileLoggingEarlierStoppedError() throws {
    var configuration = TestConfiguration.words(1, rules: .init(stopOnErrorMode: .letter))
    configuration.difficulty = .master
    var input = TypingSession(configuration: configuration, prompt: "ab")
    XCTAssertEqual(input.insertBatch("xa", at: start), [true])
    XCTAssertEqual(input.outcome, .active)
    input.insertBatch("b", at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(input.result())
    XCTAssertEqual(result.outcome, .completed)
    XCTAssertEqual(result.replayEvents.map(\.inputStopped), [true, nil, nil])
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 3)
  }

  func testEmptyNoSpaceTargetStoppedAttemptIsRecordedAndNotRetained() throws {
    var input = TypingSession(configuration: .words(10, rules: .init(stopOnErrorMode: .letter))
      .with(modifiers: [.noSpaces]), prompt: "ab", noSpaceWordEndIndices: [0, 2],
      noSpaceTargetWords: ["", "ab"])
    input.insertBatch("x", at: start)
    input.bailOut(at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(input.result())
    XCTAssertEqual(result.replayEvents.map(\.inputStopped), [true])
    XCTAssertEqual(result.typedCharacterCount, 0)
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 1)
  }

  func testStoppedSeparatorStillFailsExpertForAnIncompleteWord() throws {
    var configuration = TestConfiguration.words(2, rules: .init(stopOnErrorMode: .letter))
    configuration.difficulty = .expert
    var input = TypingSession(configuration: configuration, prompt: "ab cd")
    input.insertBatch("a", at: start)
    input.insertBatch(" ", at: start.addingTimeInterval(1))
    XCTAssertEqual(input.typed, "a")
    XCTAssertEqual(input.outcome, .failed)
    XCTAssertEqual(input.result()?.replayEvents.last?.inputStopped, true)
  }

  func testOppositeShiftStoppedCommitStillChecksExpertWordButNotShiftAlone() {
    var configuration = TestConfiguration.words(2, rules: .init(oppositeShiftMode: .on))
    configuration.difficulty = .expert
    for (text, expectedOutcome) in [("a", TestOutcome.failed), ("ab", .active)] {
      var input = TypingSession(configuration: configuration, prompt: "ab cd")
      input.insertBatch(text, at: start)
      input.insertBatch(" ", forceError: true, at: start.addingTimeInterval(1))
      XCTAssertEqual(input.typed, text)
      XCTAssertEqual(input.outcome, expectedOutcome)
    }
  }

  func testStoppedNoSpaceFinalLetterStillFailsExpert() {
    var configuration = TestConfiguration.words(2, rules: .init(stopOnErrorMode: .letter))
      .with(modifiers: [.noSpaces])
    configuration.difficulty = .expert
    var input = TypingSession(configuration: configuration, prompt: "abcd",
      noSpaceWordEndIndices: [2, 4], noSpaceTargetWords: ["ab", "cd"])
    input.insertBatch("a", at: start)
    input.insertBatch("x", at: start.addingTimeInterval(1))
    XCTAssertEqual(input.typed, "a")
    XCTAssertEqual(input.outcome, .failed)
  }
}
