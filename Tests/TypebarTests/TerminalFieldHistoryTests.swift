import XCTest
import SwiftData
@testable import Typebar

final class TerminalFieldHistoryTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 909_300_000)
  private func session(_ words: [String] = ["ab", "cd"]) -> TypingSession {
    .init(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(freedomMode: true), modifiers: [.noSpaces]),
      prompt: words.joined(), noSpaceTargetWords: words)
  }
  private func result(_ input: TypingSession) throws -> CompletedTestResult {
    var copy = input; copy.bailOut(at: start.addingTimeInterval(4))
    return try XCTUnwrap(copy.result())
  }

  func testTerminalRetreatSeparatesAcceptedTextSavedHistoryAndScoring() throws {
    var input = session(); input.insertBatch("abcd ", at: start)
    input.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(input.typed, "a")
    XCTAssertEqual(input.wpm(at: start.addingTimeInterval(1)), 24)
    XCTAssertEqual(input.rawWpm(at: start.addingTimeInterval(1)), 36)
    let saved = try result(input)
    XCTAssertEqual(saved.inputMetrics?.creditedUnits, 2)
    XCTAssertEqual(saved.inputMetrics?.retainedUnits, 3)
    XCTAssertEqual(saved.typedCharacterCount, 3)
    XCTAssertEqual(saved.correctCharacterCount, 2)
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: saved.replayEvents), ["a", ""])
    XCTAssertEqual(input.wordReviews.map(\.typed), ["a", ""])
    XCTAssertEqual(TypingReplay.typedText(events: saved.replayEvents, through: 2), "a")
  }

  func testEqualTimeRetreatDoesNotAbandonTheFutureHistory() throws {
    var input = session(); input.insertBatch("abcd ", at: start)
    input.deleteBackward(at: start)
    let saved = try result(input)
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: saved.replayEvents), ["a", "cd"])
    XCTAssertEqual(saved.inputMetrics?.creditedUnits, 2)
    XCTAssertEqual(saved.inputMetrics?.retainedUnits, 3)
  }

  func testRetiredSupplementaryFieldUsesUnitsForSpeedAndGlyphsForNativeCounts() throws {
    var input = session(["ab", "🙂"]); input.insertBatch("ab🙂 ", at: start)
    input.deleteBackward(at: start.addingTimeInterval(1))
    let saved = try result(input)
    XCTAssertEqual(saved.inputMetrics?.creditedUnits, 2)
    XCTAssertEqual(saved.inputMetrics?.retainedUnits, 3)
    XCTAssertEqual(saved.typedCharacterCount, 2)
    XCTAssertEqual(saved.correctCharacterCount, 1)
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFieldUTF16(events: saved.replayEvents), [[97], []])
  }

  func testWholeWordRetreatKeepsTheFutureScoreDespiteEmptySavedHistory() throws {
    var input = session(); input.insertBatch("abcd ", at: start)
    input.deleteWordBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(input.typed, "")
    let saved = try result(input)
    XCTAssertEqual(saved.inputMetrics?.creditedUnits, 2)
    XCTAssertEqual(saved.inputMetrics?.retainedUnits, 2)
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: saved.replayEvents), ["", ""])
  }

  func testReentryReplacesTheRetiredBucketAndRestoresSavedHistory() throws {
    var input = session(); input.insertBatch("abcd ", at: start)
    input.deleteBackward(at: start.addingTimeInterval(1))
    input.insertBatch("b", at: start.addingTimeInterval(2))
    input.insertBatch("c", at: start.addingTimeInterval(3))
    let saved = try result(input)
    XCTAssertEqual(saved.inputMetrics?.creditedUnits, 3)
    XCTAssertEqual(saved.inputMetrics?.retainedUnits, 3)
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: saved.replayEvents), ["ab", "c"])
    XCTAssertNil(saved.replayEvents.last?.clearedNextWord)
  }

  func testNewClearRequiresEighteenAndSurvivesBothArchiveBoundaries() throws {
    var input = session(); input.insertBatch("abcd ", at: start)
    input.deleteWordBackward(at: start.addingTimeInterval(1))
    let saved = try result(input)
    XCTAssertEqual(saved.replayEvents.filter { $0.clearedNextWord == true }.count, 1)
    XCTAssertNotNil(saved.replayEvents.first { $0.wordDeletionCount != nil }?.clearedNextWord)
    let data = try TypebarDataTransfer.exportArchive(settings: .init(), results: [saved], presets: [], at: start)
    let restored = try TypebarDataTransfer.importArchive(from: data)
    XCTAssertEqual(restored.version, 18)
    XCTAssertEqual(restored.results, [saved])
    XCTAssertEqual(TestResultRecord(result: saved).portableResult, saved)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    for version in 1...17 {
      XCTAssertEqual(TypebarArchive(version: version, exportedAt: start, settings: .init(), results: [saved], presets: []).version, 18)
      object["version"] = version
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: object))) {
        XCTAssertEqual($0 as? DataTransferError, .unsupportedVersion(version))
      }
    }
  }

  func testGenuineSeventeenContractionNeverInfersAbandonmentOrRescores() throws {
    let events: [TypingReplayEvent] = [.init(offset: 0, kind: .insert, units: [97,98], inputField: .init(index: 0, units: [97,98])),
      .init(offset: 0, kind: .insert, units: [99,100], inputField: .init(index: 1, units: [99,100])),
      .init(offset: 1, kind: .delete, units: [], inputField: .init(index: 0, units: [97]), discardedInputUnits: 2)]
    let old = CompletedTestResult(id: UUID(), configuration: .words(2).with(modifiers: [.noSpaces]),
      outcome: .bailedOut, startedAt: start, finishedAt: start.addingTimeInterval(2),
      typedCharacterCount: 1, correctCharacterCount: 1, errorCount: 0, wpm: 19, rawWpm: 29,
      accuracy: 77, inputMetrics: .init(version: 1, correctAttempts: 4, totalAttempts: 4, creditedUnits: 1, retainedUnits: 1),
      prompt: "abcd", replayEvents: events, targetWordDirectory: .init(words: ["ab","cd"], noSpace: true))
    let archive = TypebarArchive(version: 17, exportedAt: start, settings: .init(), results: [old], presets: [])
    XCTAssertEqual(archive.version, 17)
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    let restored = try TypebarDataTransfer.importArchive(from: encoder.encode(archive)).results[0]
    XCTAssertEqual(restored, old)
    XCTAssertTrue(restored.replayEvents.allSatisfy { $0.clearedNextWord == nil })
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: restored.replayEvents), ["a", "cd"])
    XCTAssertEqual(TypingReplay.typedText(events: restored.replayEvents, through: 2), "a")
  }

  func testInvalidAbandonmentMarkersAreRejectedWithoutIndexSizedAllocation() throws {
    let invalid: [TypingReplayEvent] = [.init(offset: 1, kind: .delete, units: [], inputField: .init(index: 0, units: []), clearedNextWord: false),
      .init(offset: 1, kind: .insert, units: [97], inputField: .init(index: 0, units: [97]), clearedNextWord: true),
      .init(offset: 1, kind: .delete, text: "", inputField: .init(index: 0, value: ""), clearedNextWord: true),
      .init(offset: 1, kind: .delete, units: [], clearedNextWord: true),
      .init(offset: 1, kind: .delete, units: [], inputField: .init(index: Int.max, units: []), clearedNextWord: true)]
    for event in invalid {
      XCTAssertFalse(event.validatedClearedNextWord)
      XCTAssertThrowsError(try JSONDecoder().decode(TypingReplayEvent.self, from: JSONEncoder().encode(event)))
    }
  }

  func testSourceTimeCacheKeepsNewerSnapshotsAndFirstBucketOrder() {
    var cache = RecordedInputFieldStats()
    cache.record(.init(offset: 2, kind: .insert, units: [99,100], inputField: .init(index: 1, units: [99,100])))
    cache.record(.init(offset: 0, kind: .insert, units: [97,98], inputField: .init(index: 0, units: [97,98])))
    cache.record(.init(offset: 1, kind: .insert, units: [120], inputField: .init(index: 1, units: [120])))
    cache.record(.init(offset: 3, kind: .delete, units: [], inputField: .init(index: 0, units: [97]), clearedNextWord: true))
    let counts = cache.counts(targets: .init("abcd", noSpaceWords: ["ab","cd"]), creditsActivePrefix: true)
    XCTAssertEqual(counts.credit.inputUnits, 2)
    XCTAssertEqual(counts.rawUnits, 3)
    XCTAssertEqual(cache.history(1), [])
  }

  func testExistingDirectoryCurveAgreesWithLiveSpeedNotClearedHistory() throws {
    var input = session(); input.insertBatch("abcd ", at: start)
    input.deleteBackward(at: start.addingTimeInterval(1))
    let saved = try result(input)
    let point = ResultPerformanceTrace.point(prompt: saved.prompt, events: saved.replayEvents,
      elapsed: 1, configuration: saved.configuration, targetWordDirectory: saved.targetWordDirectory)
    XCTAssertEqual(point.wpm, input.wpm(at: start.addingTimeInterval(1)))
    XCTAssertEqual(point.rawWpm, input.rawWpm(at: start.addingTimeInterval(1)))
    XCTAssertEqual(point.burstWpm, 48)
    XCTAssertEqual(point.errorCount, 0)
  }

  func testOrdinaryEmptyFieldRegressionDoesNotInventAnAbandonmentMarker() throws {
    var input = session(); input.insertBatch("abc", at: start)
    input.deleteBackward(at: start.addingTimeInterval(1))
    input.deleteBackward(at: start.addingTimeInterval(2))
    let saved = try result(input)
    XCTAssertTrue(saved.replayEvents.allSatisfy { $0.clearedNextWord == nil })
    XCTAssertEqual(saved.inputMetrics?.creditedUnits, 1)
    XCTAssertEqual(saved.inputMetrics?.retainedUnits, 1)
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: saved.replayEvents), ["a", ""])
  }

  func testStoppedReentryWritesAnEmptyBucketRatherThanRevivingItsRetiredScore() throws {
    var input = TypingSession(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(stopOnErrorMode: .letter, freedomMode: true), modifiers: [.noSpaces]),
      prompt: "abcd", noSpaceTargetWords: ["ab","cd"])
    input.insertBatch("abcd ", at: start)
    input.deleteBackward(at: start.addingTimeInterval(1))
    input.insertBatch("b", at: start.addingTimeInterval(2))
    input.insertBatch("x", at: start.addingTimeInterval(3))
    let saved = try result(input)
    XCTAssertEqual(saved.inputMetrics?.creditedUnits, 2)
    XCTAssertEqual(saved.inputMetrics?.retainedUnits, 2)
    XCTAssertEqual(saved.inputMetrics?.totalAttempts, 6)
    XCTAssertEqual(saved.inputMetrics?.correctAttempts, 5)
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: saved.replayEvents), ["ab", ""])
    XCTAssertEqual(saved.replayEvents.last?.inputStopped, true)
  }

  @MainActor func testInMemoryEntityKeepsClearFlagsAndBothMetricContracts() throws {
    var input = session(); input.insertBatch("abcd ", at: start)
    input.deleteBackward(at: start.addingTimeInterval(1))
    let saved = try result(input)
    let container = try ModelContainer(for: TestResultRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    container.mainContext.insert(TestResultRecord(result: saved)); try container.mainContext.save()
    let fetched = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).first?.portableResult)
    XCTAssertEqual(fetched, saved)
    XCTAssertEqual(fetched.replayEvents.last?.clearedNextWord, true)
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: fetched.replayEvents), ["a", ""])
    XCTAssertEqual(fetched.inputMetrics?.creditedUnits, 2)
  }
}
