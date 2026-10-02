import XCTest
@testable import Typebar

final class RecordedUnitJudgmentTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 907_800_000)

  private func attempt(_ text: String, prompt: String) throws -> CompletedTestResult {
    var session = TypingSession(configuration: .words(1), prompt: prompt)
    session.insertBatch(text, at: start)
    session.bailOut(at: start.addingTimeInterval(2))
    return try XCTUnwrap(session.result())
  }

  func testNormalizedAcceptedQuoteIsRecordedAndReplayedAsCorrect() throws {
    let result = try attempt("'", prompt: "’x")
    XCTAssertEqual(result.replayEvents[0].inputField?.value, "’")
    XCTAssertEqual(result.replayEvents[0].text, "’")
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 2), "’")
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: result.prompt, events: result.replayEvents))
    XCTAssertEqual(plan.frame(through: 2).presentation.glyphs.map(\.state), [.correct, .pending])
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: result.prompt, events: result.replayEvents).map(\.cue), [.click])
  }

  func testDifferentEmojiRetainsSeparateCorrectHighAndIncorrectLowSurrogateActions() throws {
    let result = try attempt("🙃", prompt: "🙂x")
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: result.prompt, events: result.replayEvents))
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: result.prompt, events: result.replayEvents).map(\.cue), [.click, .error])
    XCTAssertEqual(plan.frame(through: 2).presentation.glyphs.map(\.state), [.correct, .incorrect])
    XCTAssertEqual(plan.frame(through: 2).position, 2)
  }

  func testCombinedInputReplaysEveryCorrectUTF16UnitNotOneGraphemeAction() throws {
    let result = try attempt("e\u{301}", prompt: "e\u{301}x")
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: result.prompt, events: result.replayEvents))
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: result.prompt, events: result.replayEvents).map(\.cue), [.click, .click])
    XCTAssertEqual(plan.frame(through: 2).presentation.glyphs.map(\.state), [.correct, .correct, .pending])
    XCTAssertEqual(plan.frame(through: 2).position, 2)
  }

  func testSeparateCombiningMarkKeepsItsOwnRecordedTextAndJudgment() throws {
    var session = TypingSession(configuration: .words(1), prompt: "e\u{301}x")
    session.insertBatch("e", at: start)
    session.insertBatch("\u{301}", at: start.addingTimeInterval(1))
    session.bailOut(at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.replayEvents.map(\.text), ["e", "\u{301}"])
    XCTAssertEqual(result.replayEvents.map(\.inputCorrectness), [[true], [true]])
    XCTAssertNoThrow(try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(result)))
  }

  private func removingJudgments(_ result: CompletedTestResult) throws -> CompletedTestResult {
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any])
    let events = try XCTUnwrap(object["replayEvents"] as? [[String: Any]])
    object["replayEvents"] = events.map { event in
      var old = event
      old.removeValue(forKey: "inputCorrectness")
      return old
    }
    return try JSONDecoder().decode(CompletedTestResult.self, from: JSONSerialization.data(withJSONObject: object))
  }

  func testCapturedJudgmentsAreNotASingleWholeGlyphOrLastUnitBoolean() throws {
    for (text, target, expected) in [("🙃", "🙂x", [true, false]),
      ("a\u{301}", "e\u{301}x", [false, true]), ("e\u{301}", "e\u{301}x", [true, true])] {
      let result = try attempt(text, prompt: target)
      XCTAssertEqual(result.replayEvents.compactMap(\.inputCorrectness).flatMap { $0 }, expected)
      XCTAssertEqual(result.inputMetrics?.totalAttempts, 2)
      XCTAssertEqual(result.inputMetrics?.correctAttempts, expected.filter { $0 }.count)
    }
  }

  func testForcedMismatchRecordsAllUnitsIncorrect() throws {
    var input = TypingSession(configuration: .words(1), prompt: "🙂x")
    input.insertBatch("🙂", forceError: true, at: start)
    input.bailOut(at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(input.result())
    XCTAssertEqual(result.replayEvents.map(\.inputCorrectness), [[false], [false]])
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: result.prompt, events: result.replayEvents).map(\.cue), [.error, .error])
  }

  func testStoppedUnitJudgmentIsRecordedButNotPlayedOrAccepted() throws {
    var input = TypingSession(configuration: .words(1, rules: .init(stopOnErrorMode: .letter)), prompt: "ab")
    input.insertBatch("x", at: start)
    input.insertBatch("a", at: start.addingTimeInterval(1))
    input.bailOut(at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(input.result())
    XCTAssertEqual(result.replayEvents.map(\.inputCorrectness), [[false], [true]])
    XCTAssertEqual(result.replayEvents.map(\.inputStopped), [true, nil])
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 2), "a")
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: result.prompt, events: result.replayEvents).map(\.cue), [.click])
  }

  func testZenStoppedOppositeShiftRemainsCorrectActivityWithoutLetterActions() throws {
    var input = TypingSession(configuration: .init(mode: .zen, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(oppositeShiftMode: .on)), prompt: "")
    input.insertBatch("🙂", forceError: true, at: start)
    input.insertBatch("a", at: start.addingTimeInterval(1))
    input.finishZen(at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(input.result())
    XCTAssertEqual(result.replayEvents.map(\.inputCorrectness), [[true], [true], [true]])
    XCTAssertEqual(result.replayEvents.map(\.inputStopped), [true, true, nil])
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: result.prompt, events: result.replayEvents,
      configuration: result.configuration).map(\.cue), [.click])
    XCTAssertEqual(result.preciseAccuracy, 100)
  }

  func testDeletesHaveNoInsertionJudgmentsAndDoNotLeakThePreviousAttempt() throws {
    var input = TypingSession(configuration: .words(3, rules: .init(freedomMode: true)), prompt: "ab cd tail")
    input.insertBatch("ab c", at: start)
    input.deleteWordBackward(at: start.addingTimeInterval(1))
    input.deleteWordBackward(at: start.addingTimeInterval(2))
    input.insertBatch("d", at: start.addingTimeInterval(3))
    input.bailOut(at: start.addingTimeInterval(4))
    let events = try XCTUnwrap(input.result()).replayEvents
    XCTAssertTrue(events.filter { $0.kind == .delete }.allSatisfy { $0.inputCorrectness == nil })
    XCTAssertTrue(events.filter { $0.kind == .insert }.allSatisfy { $0.validatedInputCorrectness != nil })
    XCTAssertEqual(events.last?.inputCorrectness, [false])
  }

  func testDelayedAutomaticJudgmentKeepsTheOriginalTimestampAndInputOrderSnapshot() throws {
    var input = TypingSession(configuration: .words(2, rules: .init(deleteOnErrorMode: .letter), language: .codeSwift),
      prompt: "a \tb")
    input.insertBatch("a ", at: start, defersAutomaticInput: true)
    input.insertBatch("\t", at: start.addingTimeInterval(1), defersAutomaticInput: true)
    XCTAssertEqual(input.processNextAutomaticInput(for: input.automaticInputAttemptID,
      executedAt: start.addingTimeInterval(3)), [false])
    input.bailOut(at: start.addingTimeInterval(4))
    let result = try XCTUnwrap(input.result())
    XCTAssertEqual(result.replayEvents.map(\.inputCorrectness), [[true], [true], [false], nil, nil, [true]])
    XCTAssertEqual(result.replayEvents.map(\.offset), [0, 0, 0, 0, 0, 1])
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: result.prompt, events: result.replayEvents).map(\.cue),
      [.click, .click, .click, .error, .click, .click, .click])
  }

  func testKnownNoSpaceStillUsesRecordedUnitSoundsWithoutGuessingReplayTargets() throws {
    let configuration = TestConfiguration.words(2).with(modifiers: [.noSpaces])
    var input = TypingSession(configuration: configuration, prompt: "🙂ab", noSpaceWordEndIndices: [1, 3])
    input.insertBatch("🙂", at: start)
    input.bailOut(at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(input.result())
    XCTAssertEqual(result.replayEvents[0].inputCorrectness, [true, true])
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: result.prompt, events: result.replayEvents,
      configuration: configuration).map(\.cue), [.click, .click])
    XCTAssertNil(FieldReplayPlan.make(prompt: result.prompt, events: result.replayEvents, configuration: configuration))
  }

  func testRecordJudgmentIsAuthoritativeEvenWhenTextAndConfigWouldGuessOtherwise() throws {
    let event = TypingReplayEvent(offset: 0, kind: .insert, text: "x", forceError: true,
      inputField: .init(index: 0, value: "x"), inputCorrectness: [true])
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: "a", events: [event]))
    XCTAssertEqual(plan.frame(through: 0).presentation.glyphs.map(\.state), [.correct])
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: "a", events: [event]).map(\.cue), [.click])
  }

  func testSubmissionStillUsesFinalFieldTextNotAllRecordedLetterJudgments() throws {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "x", inputField: .init(index: 0, value: "x"), inputCorrectness: [true]),
      .init(offset: 0, kind: .insert, text: " ", inputField: .init(index: 0, value: "x "), inputCorrectness: [true]),
      .init(offset: 1, kind: .insert, text: "b", inputField: .init(index: 1, value: "b"), inputCorrectness: [true])]
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: "a b", events: events))
    XCTAssertEqual(plan.frame(through: 1).presentation.errorIndices, [0, 1])
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: "a b", events: events).map(\.cue), [.click, .click, .error, .click])
  }

  func testUnitSeekRetainsTheUnplayedLowSurrogateActionAtTheSameTime() throws {
    let result = try attempt("🙃", prompt: "🙂x")
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: result.prompt, events: result.replayEvents))
    let seek = try XCTUnwrap(plan.seek(.init(word: 0, position: 1)))
    XCTAssertEqual(seek.frame.nextActionIndex, 1)
    XCTAssertEqual(seek.nextOffset, 0)
    var frame = seek.frame
    XCTAssertEqual(plan.advance(&frame, through: 0), [.error])
    XCTAssertEqual(plan.advance(&frame, through: 0), [])
    XCTAssertEqual(frame, plan.frame(through: 0))
  }

  func testLoneSurrogateExtraUsesSafeDisplayTextWithoutChangingRetainedInput() throws {
    let result = try attempt("🙂", prompt: "ab")
    let frame = try XCTUnwrap(FieldReplayPlan.make(prompt: result.prompt, events: result.replayEvents)).frame(through: 0)
    XCTAssertEqual(frame.presentation.glyphs.map(\.state), [.incorrect, .incorrect])
    let extra = TypingReplayEvent(offset: 0, kind: .insert, text: "🙂", inputField: .init(index: 0, value: "🙂"),
      inputCorrectness: [false, false])
    let short = try XCTUnwrap(FieldReplayPlan.make(prompt: "a", events: [extra])).frame(through: 0)
    XCTAssertEqual(short.presentation.text, "a�")
    XCTAssertEqual(short.presentation.glyphs.map(\.state), [.incorrect, .extra])
    XCTAssertEqual(TypingReplay.typedText(events: [extra], through: 0), "🙂")
  }

  func testLegacyAndMixedMetadataKeepTheExistingPerEventDerivation() {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "e\u{301}", inputField: .init(index: 0, value: "e\u{301}")),
      .init(offset: 1, kind: .insert, text: "x", inputField: .init(index: 0, value: "e\u{301}x"), inputCorrectness: [true])]
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: "e\u{301}x", events: events).map(\.cue), [.click, .click])
    XCTAssertEqual(FieldReplayPresentation.glyphs(prompt: "e\u{301}x", events: events, through: 1).map(\.state),
      [.correct, .correct, .pending])
  }

  func testMissingLegacyMetadataIsNotEncodedOrGuessed() throws {
    let legacy = try JSONDecoder().decode(TypingReplayEvent.self,
      from: Data(#"{"offset":0,"kind":"insert","text":"'"}"#.utf8))
    XCTAssertNil(legacy.inputCorrectness)
    let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
    XCTAssertNil(encoded["inputCorrectness"])
    XCTAssertEqual(TypingReplay.typedText(events: [legacy], through: 0), "'")
  }

  func testMalformedJudgmentShapesAndDeleteMetadataAreRejectedOnDecode() {
    let invalid = [
      #"{"offset":0,"kind":"insert","text":"a","inputCorrectness":[]}"#,
      #"{"offset":0,"kind":"insert","text":"a","inputCorrectness":[true,false]}"#,
      #"{"offset":0,"kind":"insert","text":"🙂","inputCorrectness":[true]}"#,
      #"{"offset":0,"kind":"insert","text":"","inputCorrectness":[]}"#,
      #"{"offset":0,"kind":"delete","text":"a","inputCorrectness":[true]}"#,
      #"{"offset":0,"kind":"insert","text":"a","inputCorrectness":[0]}"#]
    for json in invalid { XCTAssertThrowsError(try JSONDecoder().decode(TypingReplayEvent.self, from: Data(json.utf8))) }
  }

  func testInvalidDirectJudgmentMetadataUsesExistingPlaybackRatherThanIndexingIt() {
    for judgments in [[], [true, false]] {
      let event = TypingReplayEvent(offset: 0, kind: .insert, text: "a", inputField: .init(index: 0, value: "a"),
        inputCorrectness: judgments)
      XCTAssertNil(event.validatedInputCorrectness)
      XCTAssertEqual(TypingReplay.soundTimeline(prompt: "ab", events: [event]).map(\.cue), [.click])
    }
  }

  func testCurrentPortableAndArchivePreserveTextJudgmentsAndScores() throws {
    let original = try attempt("🙃", prompt: "🙂x")
    let portable = try XCTUnwrap(TestResultRecord(result: original).portableResult)
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [original], presets: [], at: start))
    XCTAssertEqual(archive.version, TypebarArchive.currentVersion)
    for result in [portable, archive.results[0]] {
      XCTAssertEqual(result, original)
      XCTAssertEqual(result.replayEvents.map(\.inputCorrectness), [[true], [false]])
      XCTAssertEqual(TypingReplay.soundTimeline(prompt: result.prompt, events: result.replayEvents).map(\.cue), [.click, .error])
    }
  }

  func testGenuineArchiveTwelveKeepsItsPreviousOneActionProjectionAndMetrics() throws {
    // Explicit owned archive-12 fixture, not stripped metadata from a new
    // unit session: its insertion was genuinely one legacy glyph primitive.
    let old = CompletedTestResult(id: UUID(), configuration: .words(1), outcome: .bailedOut,
      startedAt: start, finishedAt: start.addingTimeInterval(2), typedCharacterCount: 1,
      correctCharacterCount: 0, errorCount: 1, wpm: 0, rawWpm: 12, accuracy: 50,
      inputMetrics: .init(version: 1, correctAttempts: 1, totalAttempts: 2, creditedUnits: 0, retainedUnits: 2),
      prompt: "🙂x", replayEvents: [.init(offset: 0, kind: .insert, text: "🙃",
        inputField: .init(index: 0, value: "🙃"))])
    let archive = TypebarArchive(version: 12, exportedAt: start, settings: .init(), results: [old], presets: [])
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    let decoded = try TypebarDataTransfer.importArchive(from: encoder.encode(archive))
    XCTAssertEqual(decoded.version, 12)
    XCTAssertNil(decoded.results[0].replayEvents[0].inputCorrectness)
    XCTAssertEqual(decoded.results[0], old)
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: old.prompt, events: old.replayEvents).map(\.cue), [.error])
    XCTAssertEqual(FieldReplayPresentation.glyphs(prompt: old.prompt, events: old.replayEvents, through: 2).map(\.state),
      [.incorrect, .pending])
  }

  func testArchiveConstructionCannotMislabelJudgmentsAsAnyEarlierVersion() throws {
    // ASCII still produces genuine archive-13 metadata; never downgrade a
    // converted Unicode session by stripping its raw fields or units.
    let original = try attempt("a", prompt: "ab")
    for version in 1...12 {
      XCTAssertEqual(TypebarArchive(version: version, exportedAt: start, settings: .init(), results: [original], presets: []).version, 13)
    }
    let fieldsOnly = try removingJudgments(original)
    for version in 1...11 {
      XCTAssertEqual(TypebarArchive(version: version, exportedAt: start, settings: .init(), results: [fieldsOnly], presets: []).version, 12)
    }
  }

  func testForgedEarlierArchiveCannotDiscardNewJudgments() throws {
    let data = try TypebarDataTransfer.exportArchive(settings: .init(), results: [attempt("a", prompt: "ab")], presets: [], at: start)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    for version in 1...12 {
      object["version"] = version
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: object))) {
        XCTAssertEqual($0 as? DataTransferError, .unsupportedVersion(version))
      }
    }
  }

  func testThousandNativeEmojiWordsCaptureAndReplayEveryUnitWithoutChangingCounts() throws {
    let prompt = Array(repeating: "🙂", count: 1_000).joined(separator: " ")
    var input = TypingSession(configuration: .words(1_000), prompt: prompt)
    input.insertBatch(prompt, at: start)
    let result = try XCTUnwrap(input.result())
    XCTAssertEqual(result.replayEvents.count, 2_999)
    XCTAssertEqual(result.replayEvents.compactMap(\.inputCorrectness).flatMap { $0 }.count, 2_999)
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 2_999)
    XCTAssertEqual(TypingReplay.soundTimeline(prompt: result.prompt, events: result.replayEvents).count, 3_998)
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: result.prompt, events: result.replayEvents))
    XCTAssertEqual(plan.actions.count, 3_998)
    XCTAssertEqual(plan.frame(through: 0).presentation.glyphs.count, 1_999)
    XCTAssertTrue(plan.frame(through: 0).presentation.glyphs.allSatisfy { $0.state == .correct })
  }
}
