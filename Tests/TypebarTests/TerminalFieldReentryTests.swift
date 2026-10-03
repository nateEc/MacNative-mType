import XCTest
@testable import Typebar

final class TerminalFieldReentryTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 909_200_000)
  private func attempt(_ words: [String], rules: InputRules = .init()) -> TypingSession {
    .init(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: rules, modifiers: [.noSpaces]),
      prompt: words.joined(), noSpaceTargetWords: words)
  }
  private func snapshot(_ session: TypingSession) throws -> CompletedTestResult {
    var copy = session
    copy.bailOut(at: start.addingTimeInterval(2))
    return try XCTUnwrap(copy.result())
  }

  func testBulkFinalCommitClearsAndReentersTheSameActualField() throws {
    var session = attempt(["hi\n_","next"])
    session.insertBatch("hi\n_next", at: start)
    XCTAssertEqual(session.outcome, .active)
    XCTAssertEqual(session.typed, "hi\nt")
    XCTAssertEqual(session.completedWordCount, 1)
    XCTAssertEqual(session.wordReviews.map(\.typed), ["hi\n","t"])
    let result = try snapshot(session)
    XCTAssertEqual(result.replayEvents.map { $0.inputField?.index }, [0,0,0,1,1,1,1,1])
    XCTAssertEqual(result.replayEvents.map { $0.inputPosition?.charIndex }, [0,1,2,0,1,2,3,4])
    XCTAssertEqual(result.replayEvents.last?.inputField?.value, "t")
    XCTAssertEqual(result.inputMetrics?.correctAttempts, 3)
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 8)
    XCTAssertEqual(result.inputMetrics?.creditedUnits, 0)
    XCTAssertEqual(result.inputMetrics?.retainedUnits, 4)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 2), "hi\nt")
  }

  func testStoppedKeyAfterTerminalClearLogsEmptySnapshotAndDoesNotFinish() throws {
    var session = attempt(["ab"], rules: .init(stopOnErrorMode: .letter))
    session.insertBatch("abx", at: start)
    XCTAssertEqual(session.outcome, .active)
    XCTAssertEqual(session.typed, "")
    let result = try snapshot(session)
    XCTAssertEqual(result.replayEvents.map { $0.inputField?.index }, [0,0,0])
    XCTAssertEqual(result.replayEvents.map { $0.inputPosition?.charIndex }, [0,1,2])
    XCTAssertEqual(result.replayEvents.last?.inputField?.value, "")
    XCTAssertEqual(result.replayEvents.last?.inputStopped, true)
    XCTAssertEqual(result.inputMetrics?.correctAttempts, 2)
    XCTAssertEqual(result.inputMetrics?.retainedUnits, 0)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 2), "")
  }

  func testNextKeyReadsTheReplacementSnapshotAndCanFinishTheRealWord() throws {
    var session = attempt(["ab"], rules: .init(stopOnErrorMode: .letter))
    session.insertBatch("abx", at: start)
    session.insertBatch("ab", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.typed, "ab")
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.replayEvents.map { $0.inputPosition?.charIndex }, [0,1,2,0,1])
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 5)
    XCTAssertEqual(result.inputMetrics?.correctAttempts, 4)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 2), "ab")
  }

  func testSingleKeysStillFinishOnXBeforeTheTrailingT() throws {
    var session = attempt(["hi\n_","next"])
    for key in "hi\n_next" { session.insert(String(key), at: start) }
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.typed, "hi\n_nex")
    XCTAssertEqual(try XCTUnwrap(session.result()).replayEvents.count, 7)
  }

  func testRepeatedTerminalSubmissionUsesTheReplacementNotTheDiscardedWord() throws {
    var session = attempt(["ab"])
    session.insertBatch("abxy", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.typed, "xy")
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.replayEvents.map { $0.inputPosition?.charIndex }, [0,1,2,1])
    XCTAssertEqual(result.replayEvents.map { $0.inputField?.index }, [0,0,0,0])
    XCTAssertEqual(result.replayEvents.map(\.discardedInputUnits), [nil,nil,2,nil])
    XCTAssertEqual(result.inputMetrics?.correctAttempts, 2)
    XCTAssertEqual(result.inputMetrics?.retainedUnits, 2)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 2), "xy")
  }

  func testSupplementaryTerminalClearingCountsRawUnitsNotGlyphs() throws {
    var session = attempt(["🙂"])
    session.insertBatch("🙂z", at: start)
    XCTAssertEqual(session.outcome, .active)
    XCTAssertEqual(session.typed, "z")
    let result = try snapshot(session)
    XCTAssertEqual(result.replayEvents.map { $0.inputPosition?.charIndex }, [0,1,2])
    XCTAssertEqual(result.replayEvents.last?.discardedInputUnits, 2)
    XCTAssertEqual(result.inputMetrics?.correctAttempts, 2)
    XCTAssertEqual(TypingReplay.typedUTF16(events: result.replayEvents, through: 2), [122])
  }

  func testClearingFusedTerminalTailDoesNotRemoveItsPrecedingSourceField() throws {
    var session = attempt(["a","\u{301}b"])
    session.insertBatch("a\u{301}bx", at: start)
    XCTAssertEqual(session.typed, "ax")
    XCTAssertEqual(session.outcome, .active)
    let result = try snapshot(session)
    XCTAssertEqual(result.replayEvents.last?.inputField?.index, 1)
    XCTAssertEqual(result.replayEvents.last?.inputPosition?.charIndex, 2)
    XCTAssertEqual(result.replayEvents.last?.discardedInputUnits, 2)
    XCTAssertEqual(result.inputMetrics?.creditedUnits, 1)
    XCTAssertEqual(result.inputMetrics?.retainedUnits, 2)
    XCTAssertEqual(TypingReplay.typedUTF16(events: result.replayEvents, through: 2), [97,120])
  }

  func testPreRejectedTrailingSpaceDoesNotFinishAnEarlierBatchCommit() throws {
    var session = attempt(["ab"], rules: .init(freedomMode: true))
    session.insertBatch("ab ", at: start)
    XCTAssertEqual(session.outcome, .active)
    XCTAssertEqual(session.typed, "ab")
    session.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "ab", "An empty first element cannot regress, even in freedom mode")
    XCTAssertEqual(try snapshot(session).replayEvents.count, 2)
  }

  func testTerminalCommitCannotFailMinimumBurstThroughPhantomNavigation() {
    var session = attempt(["ab"], rules: .init(minimumWordBurstWpm: 100,
      minimumWordBurstMode: .fixed))
    session.insert("a", at: start)
    session.insert("b", at: start.addingTimeInterval(10))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 1)
  }

  func testFormalAndPortableRoundTripRequireSeventeenForAContraction() throws {
    var session = attempt(["ab"], rules: .init(stopOnErrorMode: .letter))
    session.insertBatch("abx", at: start)
    let result = try snapshot(session)
    XCTAssertEqual(result.replayEvents.last?.discardedInputUnits, 2)
    let data = try TypebarDataTransfer.exportArchive(settings: .init(), results: [result], presets: [], at: start)
    let archive = try TypebarDataTransfer.importArchive(from: data)
    XCTAssertEqual(archive.version, TypebarArchive.currentVersion)
    XCTAssertEqual(archive.results, [result])
    XCTAssertEqual(TestResultRecord(result: result).portableResult, result)
    // Keep minimum-17 contraction evidence independent of current format-19 stats.
    let minimal = CompletedTestResult(id: UUID(), configuration: .words(1).with(modifiers: [.noSpaces]),
      outcome: .bailedOut, startedAt: start, finishedAt: start.addingTimeInterval(2),
      typedCharacterCount: 0, correctCharacterCount: 0, errorCount: 0, wpm: 0, rawWpm: 0,
      accuracy: 77, prompt: "ab", replayEvents: [
        .init(offset: 0, kind: .insert, units: [97,98], inputField: .init(index: 0, units: [97,98])),
        .init(offset: 1, kind: .insert, units: [120], inputStopped: true,
          inputField: .init(index: 0, units: []), discardedInputUnits: 2)],
      targetWordDirectory: .init(words: ["ab"], noSpace: true))
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    let minimalArchive = TypebarArchive(version: 1, exportedAt: start, settings: .init(), results: [minimal], presets: [])
    XCTAssertEqual(minimalArchive.version, 17)
    let minimalData = try encoder.encode(minimalArchive)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from: minimalData).results, [minimal])
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: minimalData) as? [String: Any])
    for version in 1...16 {
      XCTAssertEqual(TypebarArchive(version: version, exportedAt: start, settings: .init(), results: [minimal], presets: []).version, 17)
      object["version"] = version
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: object))) {
        XCTAssertEqual($0 as? DataTransferError, .unsupportedVersion(version))
      }
    }
  }

  func testLegacySixteenKeepsItsOriginalCumulativeUnitTape() throws {
    let oldEvents: [TypingReplayEvent] = [.init(offset: 0, kind: .insert, units: [97,98],
      inputField: .init(index: 0, units: [97,98]), inputCorrectness: [true,true],
      inputPosition: .init(charIndex: 0, lastWord: true)),
      .init(offset: 1, kind: .insert, units: [120], inputField: .init(index: 1, units: [120]), inputCorrectness: [false])]
    let old = CompletedTestResult(id: UUID(), configuration: .words(1).with(modifiers: [.noSpaces]),
      outcome: .completed, startedAt: start, finishedAt: start.addingTimeInterval(2),
      typedCharacterCount: 3, correctCharacterCount: 2, errorCount: 1, wpm: 19, rawWpm: 29,
      accuracy: 77, prompt: "ab", replayEvents: oldEvents,
      targetWordDirectory: .init(words: ["ab"], noSpace: true))
    let archive = TypebarArchive(version: 16, exportedAt: start, settings: .init(), results: [old], presets: [])
    XCTAssertEqual(archive.version, 16)
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    let restored = try TypebarDataTransfer.importArchive(from: encoder.encode(archive)).results[0]
    XCTAssertEqual(restored, old)
    XCTAssertTrue(restored.replayEvents.allSatisfy { $0.discardedInputUnits == nil })
    XCTAssertEqual(TypingReplay.typedText(events: restored.replayEvents, through: 2), "abx")
  }

  func testMalformedContractionsAreRejectedAndDirectInvalidCountsUseLegacyFallback() throws {
    for count in [0,-1] {
      let event = TypingReplayEvent(offset: 0, kind: .insert, units: [97], inputField: .init(index: 0, units: [97]),
        discardedInputUnits: count)
      XCTAssertNil(event.validatedDiscardedInputUnits)
      XCTAssertThrowsError(try JSONDecoder().decode(TypingReplayEvent.self, from: JSONEncoder().encode(event)))
      XCTAssertEqual(TypingReplay.typedUTF16(events: [event], through: 0), [97])
    }
    for event in [TypingReplayEvent(offset: 0, kind: .insert, text: "a", inputField: .init(index: 0, value: "a"),
      discardedInputUnits: 1), .init(offset: 0, kind: .insert, units: [97], discardedInputUnits: 1)] {
      XCTAssertThrowsError(try JSONDecoder().decode(TypingReplayEvent.self, from: JSONEncoder().encode(event)))
    }
  }
}
