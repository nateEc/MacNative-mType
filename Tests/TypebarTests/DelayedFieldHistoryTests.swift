import XCTest
@testable import Typebar

final class DelayedFieldHistoryTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 907_200_000)

  private func delayedResult(finish: Bool) throws -> CompletedTestResult {
    var input = TypingSession(configuration: .words(2,
      rules: .init(deleteOnErrorMode: .letter), language: .codeSwift), prompt: "a \tb")
    input.insertBatch("a ", at: start, defersAutomaticInput: true)
    input.insertBatch("\t", at: start.addingTimeInterval(1), defersAutomaticInput: true)
    XCTAssertEqual(input.processNextAutomaticInput(for: input.automaticInputAttemptID,
      executedAt: start.addingTimeInterval(3)), [false])
    XCTAssertEqual(input.typed, "a ")
    if finish {
      input.insertBatch("\tb", at: start.addingTimeInterval(4))
      XCTAssertEqual(input.typed, "a \tb")
      XCTAssertEqual(input.outcome, .completed)
    } else {
      input.bailOut(at: start.addingTimeInterval(4))
    }
    return try XCTUnwrap(input.result())
  }

  func testDelayedRecoveryHistoryKeepsThePriorFieldAndSourceSortedSnapshot() throws {
    let result = try delayedResult(finish: false)
    // Source time sorting restores the later manual Tab snapshot, even though
    // the last executed recovery left the current live field empty.
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: result.replayEvents), ["a ", "\t"])
  }

  func testLaterCorrectInputRestoresTheFieldWithoutAFalseGlobalDeletion() throws {
    let result = try delayedResult(finish: true)
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: result.replayEvents), ["a ", "\tb"])
  }

  func testPortableAndFormalArchivePreserveTheSourceFieldHistory() throws {
    let result = try delayedResult(finish: true)
    let portable = try XCTUnwrap(TestResultRecord(result: result).portableResult)
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [], at: start))
    for restored in [portable, archive.results[0]] {
      XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: restored.replayEvents), ["a ", "\tb"])
    }
    XCTAssertEqual(archive.version, TypebarArchive.currentVersion)
  }

  func testCapturedFieldsPreserveOriginalOffsetsAndAutomaticActions() throws {
    let result = try delayedResult(finish: false)
    XCTAssertEqual(result.replayEvents.map(\.offset), [0, 0, 0, 0, 0, 1])
    XCTAssertEqual(result.replayEvents.map(\.automatic), [false, false, true, true, true, false])
    XCTAssertEqual(result.replayEvents.map { $0.inputField?.index }, [0, 0, 1, 1, 1, 1])
    XCTAssertEqual(result.replayEvents.map { $0.inputField?.value }, ["a", "a ", "\t\t", "\t", "", "\t"])
    XCTAssertEqual(result.replayEvents.filter(\.automatic).map(\.kind), [.insert, .delete, .delete])
  }

  func testCorrectCommitsAndManualDeletionCaptureTheDestinationField() throws {
    var input = TypingSession(configuration: .words(3,
      rules: .init(freedomMode: true)), prompt: "ab cd tail")
    input.insertBatch("ab c", at: start)
    input.deleteBackward(at: start)
    input.deleteBackward(at: start)
    input.bailOut(at: start.addingTimeInterval(1))
    let events = try XCTUnwrap(input.result()).replayEvents
    XCTAssertEqual(events.suffix(2).map { $0.inputField?.index }, [1, 0])
    XCTAssertEqual(events.suffix(2).map { $0.inputField?.value }, ["", "ab"])
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: events), ["ab", ""])
  }

  func testRetainedSeparatorsDoNotAdvanceTheRecordedField() throws {
    var input = TypingSession(configuration: .words(2,
      rules: .init(stopOnErrorMode: .word)), prompt: "ab\ncd")
    input.insertBatch("ax\n\n", at: start)
    input.bailOut(at: start.addingTimeInterval(1))
    let events = try XCTUnwrap(input.result()).replayEvents
    XCTAssertEqual(events.map { $0.inputField?.index }, [0, 0, 0, 0])
    XCTAssertEqual(events.last?.inputField?.value, "ax\n\n")
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: events), ["ax\n\n"])
  }

  func testHardWholeWordActionRetainsEveryFieldSnapshot() throws {
    var input = TypingSession(configuration: .words(2,
      rules: .init(deleteOnErrorMode: .wordHard)), prompt: "ab cd")
    input.insertBatch("ab ", at: start)
    input.insertBatch("x", at: start.addingTimeInterval(1))
    input.bailOut(at: start.addingTimeInterval(2))
    let events = try XCTUnwrap(input.result()).replayEvents
    XCTAssertTrue(events.allSatisfy { $0.inputField != nil })
    XCTAssertTrue(events.contains { $0.wordDeletionCount != nil })
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: events), ["", ""])
    XCTAssertEqual(events.last?.inputField, .init(index: 0, value: ""))
  }

  func testStoppedAndBlindInputRecordAcceptedFieldsNotDisplayOverrides() throws {
    for blind in [false, true] {
      var input = TypingSession(configuration: .words(2,
        rules: .init(stopOnErrorMode: .letter, blindMode: blind)), prompt: "ab cd")
      input.insertBatch("ax", at: start)
      input.bailOut(at: start.addingTimeInterval(1))
      let events = try XCTUnwrap(input.result()).replayEvents
      XCTAssertEqual(events.last?.inputStopped, true)
      XCTAssertEqual(events.last?.inputField, .init(index: 0, value: "a"))
      XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: events), ["a"])
    }
  }

  func testKnownNoSpaceFieldsCaptureCommitsAndEmptyNewWordRecovery() throws {
    var input = TypingSession(configuration: .words(3,
      rules: .init(deleteOnErrorMode: .letter)).with(modifiers: [.noSpaces]),
      prompt: "abcdef", noSpaceWordEndIndices: [2, 4, 6])
    input.insertBatch("ab", at: start)
    input.insertBatch("x", at: start.addingTimeInterval(1))
    input.bailOut(at: start.addingTimeInterval(2))
    let events = try XCTUnwrap(input.result()).replayEvents
    XCTAssertEqual(events.map { $0.inputField?.index }, [0, 0, 1, 1])
    XCTAssertEqual(events.map { $0.inputField?.value }, ["a", "ab", "x", ""])
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: events), ["ab", ""])
  }

  func testZenFieldsIncludeActualReturnsAndCommits() throws {
    var input = TypingSession(configuration: .init(mode: .zen, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init()), prompt: "")
    input.insertBatch("a\nb", at: start)
    input.finishZen(at: start.addingTimeInterval(1))
    let events = try XCTUnwrap(input.result()).replayEvents
    XCTAssertEqual(events.map { $0.inputField?.index }, [0, 0, 1])
    XCTAssertEqual(events.map { $0.inputField?.value }, ["a", "a\n", "b"])
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: events), ["a\n", "b"])
  }

  func testUnicodeFieldValuesPreserveCombiningCharactersWithoutReplayingDeletion() throws {
    var input = TypingSession(configuration: .words(2), prompt: "e\u{301} cd")
    input.insertBatch("e", at: start)
    input.insertBatch("\u{301}", at: start)
    input.deleteBackward(at: start)
    input.bailOut(at: start.addingTimeInterval(1))
    let events = try XCTUnwrap(input.result()).replayEvents
    XCTAssertEqual(events[1].inputField?.value, "e\u{301}")
    XCTAssertEqual(events.last?.inputField?.value, "e")
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: events), ["e"])
  }

  func testEqualTimestampSnapshotsKeepStableArrivalOrderWithinEachField() {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "a", inputField: .init(index: 0, value: "a")),
      .init(offset: 0, kind: .insert, text: "x", inputField: .init(index: 1, value: "x")),
      .init(offset: 0, kind: .delete, text: "", inputField: .init(index: 1, value: "")),
      .init(offset: 0, kind: .insert, text: "b", inputField: .init(index: 1, value: "b"))
    ]
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: events), ["a", "b"])
  }

  func testFieldBucketsDoNotAllocatePlaceholdersUpToAnUntrustedIndex() {
    let event = TypingReplayEvent(offset: 0, kind: .insert, text: "a",
      inputField: .init(index: Int.max, value: "a"))
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: [event]), ["a"])
  }

  func testLegacyAndMixedTapesDoNotInventMissingFieldSnapshots() throws {
    let legacy = try JSONDecoder().decode(TypingReplayEvent.self,
      from: Data(#"{"offset":0,"kind":"insert","text":"a "}"#.utf8))
    XCTAssertNil(legacy.inputField)
    let old: [TypingReplayEvent] = [legacy, .init(offset: 1, kind: .delete, text: "")]
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: old), ["a"])
    let mixed = [legacy, TypingReplayEvent(offset: 1, kind: .delete, text: "",
      inputField: .init(index: 1, value: ""))]
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: mixed), ["a"])
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
    XCTAssertNil(object["inputField"])
  }

  func testNegativeDecodedFieldIndexIsRejected() {
    let malformed = Data(#"{"offset":0,"kind":"insert","text":"a","inputField":{"index":-1,"value":"a"}}"#.utf8)
    XCTAssertThrowsError(try JSONDecoder().decode(TypingReplayEvent.self, from: malformed))
  }

  func testArchiveConstructionCannotMislabelFieldTapesAsVersionsOneThroughEleven() throws {
    // Independent owned old field/judgment producer, not stripped new events.
    let result = CompletedTestResult(id: UUID(), configuration: .words(2), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(2), typedCharacterCount: 3,
      correctCharacterCount: 3, errorCount: 0, wpm: 17, rawWpm: 29, accuracy: 77, prompt: "a b",
      replayEvents: [
        .init(offset: 0, kind: .insert, text: "a", inputField: .init(index: 0, value: "a"), inputCorrectness: [true]),
        .init(offset: 1, kind: .insert, text: " ", inputField: .init(index: 0, value: "a "), inputCorrectness: [true]),
        .init(offset: 0.5, kind: .insert, text: "b", automatic: true,
          inputField: .init(index: 1, value: "b"), inputCorrectness: [true])])
    for version in 1...11 {
      let archive = TypebarArchive(version: version, exportedAt: start, settings: .init(),
        results: [result], presets: [])
      XCTAssertEqual(archive.version, 13, "判定日志的最小版本仍为 13，不冒充原始单位日志")
    }
  }

  func testForgedVersionElevenFieldArchiveIsRejectedWithoutDiscardingTheFields() throws {
    let data = try TypebarDataTransfer.exportArchive(settings: .init(),
      results: [delayedResult(finish: true)], presets: [], at: start)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["version"] = 11
    let forged = try JSONSerialization.data(withJSONObject: object)
    XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: forged)) {
      XCTAssertEqual($0 as? DataTransferError, .unsupportedVersion(11))
    }
  }

  func testEmptyEarlierArchiveVersionsRemainReadableWithoutNewFields() throws {
    for version in 1...11 {
      let archive = TypebarArchive(version: version, exportedAt: start, settings: .init(),
        results: [], presets: [])
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      XCTAssertEqual(try TypebarDataTransfer.importArchive(from: encoder.encode(archive)).version, version)
    }
  }

  func testLegacyVersionElevenRecordKeepsItsPrimitiveHistoryAndMetrics() throws {
    let result = CompletedTestResult(id: UUID(), configuration: .words(2), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(4), typedCharacterCount: 4,
      correctCharacterCount: 4, errorCount: 1, wpm: 17, rawWpm: 29, accuracy: 77,
      inputMetrics: .init(version: 1, correctAttempts: 4, totalAttempts: 6, creditedUnits: 4, retainedUnits: 4),
      prompt: "a \tb", replayEvents: [
        .init(offset: 0, kind: .insert, text: "a"), .init(offset: 0, kind: .insert, text: " "),
        .init(offset: 0, kind: .insert, text: "\t", automatic: true),
        .init(offset: 0, kind: .delete, text: "", automatic: true),
        .init(offset: 0, kind: .delete, text: "", automatic: true),
        .init(offset: 1, kind: .insert, text: "\t"), .init(offset: 4, kind: .insert, text: "\t"),
        .init(offset: 4, kind: .insert, text: "b")])
    let old = TypebarArchive(version: 11, exportedAt: start, settings: .init(), results: [result], presets: [])
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    let archive = try TypebarDataTransfer.importArchive(from: encoder.encode(old))
    XCTAssertEqual(archive.version, 11)
    XCTAssertTrue(archive.results[0].replayEvents.allSatisfy { $0.inputField == nil })
    XCTAssertEqual(archive.results[0].inputMetrics, result.inputMetrics)
    XCTAssertEqual(archive.results[0], result)
    XCTAssertNil(archive.results[0].characterStats.sourceUnits)
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: archive.results[0].replayEvents), ["a\t\tb", ""])
  }

  func testLargeKnownNoSpaceInputKeepsFieldIndicesAtEveryBoundary() throws {
    let count = 1_000
    let prompt = String(repeating: "ab", count: count)
    var input = TypingSession(configuration: .words(count).with(modifiers: [.noSpaces]),
      prompt: prompt, noSpaceWordEndIndices: (1...count).map { $0 * 2 })
    input.insertBatch(prompt, at: start)
    let events = try XCTUnwrap(input.result()).replayEvents
    XCTAssertEqual(events.count, count * 2)
    XCTAssertEqual(events.first?.inputField, .init(index: 0, value: "a"))
    XCTAssertEqual(events.last?.inputField, .init(index: count - 1, value: "ab"))
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: events), Array(repeating: "ab", count: count))
    XCTAssertEqual(input.savedTextProgressWordCount, count)
  }
}
