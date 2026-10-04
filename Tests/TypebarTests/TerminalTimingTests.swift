import XCTest
import SwiftData
@testable import Typebar

final class TerminalTimingTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_800_000_000)

  private func input(last: Double = 15) -> TypingSession {
    let config = TestConfiguration(mode: .zen, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init())
    var value = TestSessionFactory.make(configuration: config)
    value.recordPhysicalKeyEvent(keyCode: 0, isKeyDown: true, isRepeat: false, at: start)
    value.insertBatch("a", at: start)
    value.recordPhysicalKeyEvent(keyCode: 11, isKeyDown: true, isRepeat: false,
      at: start.addingTimeInterval(last))
    value.insertBatch("b", at: start.addingTimeInterval(last))
    return value
  }

  func testCommandZenFinishUsesPhysicalTailTrimWithoutChangingRealDates() throws {
    var value = input()
    value.finishZen(at: start.addingTimeInterval(16))
    let result = try XCTUnwrap(value.result())
    XCTAssertEqual(result.preciseWpm, 1.6, accuracy: 0.00001)
    XCTAssertEqual(result.preciseRawWpm, 1.6, accuracy: 0.00001)
    XCTAssertEqual(result.elapsedDuration, 15)
    XCTAssertEqual(result.finishedAt, start.addingTimeInterval(16))
  }

  func testTrimmedBoundariesDoNotInventTrailingAfk() throws {
    var value = input()
    value.finishZen(at: start.addingTimeInterval(21.99999))
    let result = try XCTUnwrap(value.result())
    XCTAssertEqual(result.outcome, .completed)
    XCTAssertEqual(result.afkDuration, 13)
    XCTAssertEqual(result.engagedDuration, 2)
  }

  private func finish(_ input: TypingSession, at offset: Double = 16) throws -> CompletedTestResult {
    var value = input
    value.finishZen(at: start.addingTimeInterval(offset))
    return try XCTUnwrap(value.result())
  }

  private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
  }

  func testPhysicalEnterBeforeFinishPreservesTheRealSixteenSecondDenominator() throws {
    var value = input()
    value.recordPhysicalKeyEvent(keyCode: 36, isKeyDown: true, isRepeat: false,
      at: start.addingTimeInterval(16))
    let result = try finish(value)
    XCTAssertEqual(result.elapsedDuration, 16)
    XCTAssertEqual(result.preciseWpm, 1.5)
    XCTAssertEqual(result.afkDuration, 13)
    XCTAssertEqual(result.engagedDuration, 3)
  }

  func testRepeatReleaseAndExcludedPhysicalKeysCannotPostponeTheLastDown() throws {
    for (code, down, repeated): (UInt16, Bool, Bool) in [(0,true,true), (11,false,false),
      (56,true,false), (51,true,false), (76,true,false), (123,true,false)] {
      var value = input()
      value.recordPhysicalKeyEvent(keyCode: code, isKeyDown: down, isRepeat: repeated,
        at: start.addingTimeInterval(16))
      let result = try finish(value)
      XCTAssertEqual(result.elapsedDuration, 15, "code \(code)")
      XCTAssertEqual(result.terminalTiming?.lastKeypressMilliseconds, 15_000)
    }
    XCTAssertTrue(TerminalPhysicalActivity.tracks(123, modifiers: [.arrowStream]))
    XCTAssertTrue(TerminalPhysicalActivity.tracks(76, modifiers: [.accountingStream]))
    XCTAssertFalse(TerminalPhysicalActivity.tracks(123, modifiers: []))
    XCTAssertFalse(TerminalPhysicalActivity.tracks(76, modifiers: []))
  }

  func testStrictSevenSecondBoundaryAndHundredthMillisecondRounding() throws {
    let clipped = try finish(input(), at: 21.99999)
    let untrimmed = try finish(input(), at: 22)
    XCTAssertEqual(clipped.elapsedDuration, 15)
    XCTAssertEqual(clipped.outcome, .completed)
    XCTAssertEqual(untrimmed.elapsedDuration, 22)
    XCTAssertEqual(untrimmed.outcome, .invalidAFK)
    let carried = ResultTerminalTiming(version: 1, endMilliseconds: 21_999.996,
      lastKeypressMilliseconds: 15_000)
    XCTAssertEqual(carried.boundaryDuration, 21.999996)
  }

  func testScalarDurationRoundsButCustomAndChartBoundariesRetainMilliseconds() {
    let timing = ResultTerminalTiming(version: 1, endMilliseconds: 16_000,
      lastKeypressMilliseconds: 15_127.89)
    XCTAssertEqual(timing.duration(mode: .zen), 15.13)
    XCTAssertEqual(timing.duration(mode: .words), 15.13)
    XCTAssertEqual(timing.duration(mode: .custom), 15.12789, accuracy: 0.0000001)
    XCTAssertEqual(timing.boundaryDuration, 15.12789, accuracy: 0.0000001)
    XCTAssertTrue(ResultTerminalTiming.round(Double.greatestFiniteMagnitude).isFinite)
  }

  func testMissingObservationStaysMissingButObservedExcludedKeysHaveAnEmptyTrace() throws {
    var unobserved = TestSessionFactory.make(configuration: input().configuration)
    unobserved.insertBatch("a", at: start)
    unobserved.insertBatch("b", at: start.addingTimeInterval(15))
    let oldPath = try finish(unobserved)
    XCTAssertNil(oldPath.terminalTiming)
    XCTAssertEqual(oldPath.elapsedDuration, 16)
    unobserved.recordPhysicalKeyEvent(keyCode: 56, isKeyDown: true, isRepeat: false,
      at: start.addingTimeInterval(15.5))
    let observed = try finish(unobserved)
    XCTAssertNotNil(observed.terminalTiming)
    XCTAssertNil(observed.terminalTiming?.lastKeypressMilliseconds)
    XCTAssertEqual(observed.elapsedDuration, 16)
  }

  func testPhysicalCleanupKeepsOnlyTheLastPrestartDownAndDropsPostEndDowns() throws {
    var trace = TerminalPhysicalActivity()
    for offset in [-2.0,-1,15,17] {
      trace.record(code: 0, down: true, isRepeat: false,
        at: start.addingTimeInterval(offset), modifiers: [])
    }
    XCTAssertEqual(trace.offsets(startedAt: start, finishedAt: start.addingTimeInterval(16)), [-1_000,15_000])
    XCTAssertEqual(trace.snapshot(startedAt: start, finishedAt: start.addingTimeInterval(16))?.duration(mode: .zen), 15)
    var prestartOnly = TerminalPhysicalActivity()
    prestartOnly.record(code: 0, down: true, isRepeat: false, at: start.addingTimeInterval(-1), modifiers: [])
    let safe = try XCTUnwrap(prestartOnly.snapshot(startedAt: start, finishedAt: start.addingTimeInterval(1)))
    XCTAssertEqual(safe.boundaryDuration, 0, "Native protects negative duration; this degenerate branch is not full source parity")
  }

  func testStoppedInsertCountsForTrailingAfkWithoutBecomingRetainedText() throws {
    let config = TestConfiguration(mode: .zen, duration: nil, wordLimit: nil, difficulty: .normal,
      rules: .init(strictSpace: true, oppositeShiftMode: .on))
    var value = TestSessionFactory.make(configuration: config)
    value.recordPhysicalKeyEvent(keyCode: 0, isKeyDown: true, isRepeat: false, at: start)
    value.insertBatch("a", at: start)
    value.recordPhysicalKeyEvent(keyCode: 49, isKeyDown: true, isRepeat: false, at: start.addingTimeInterval(15))
    value.insertBatch(" ", forceError: true, at: start.addingTimeInterval(15))
    let result = try finish(value)
    XCTAssertEqual(result.outcome, .completed)
    XCTAssertEqual(result.replayEvents.last?.inputStopped, true)
    XCTAssertEqual(ResultInputText.make(for: result), "a")
    XCTAssertEqual(result.afkDuration, 13)
  }

  func testBailoutUsesMeasuredClockButOrdinaryCompletedTestsKeepWallClock() throws {
    var value = TypingSession(configuration: .words(2), prompt: "ab cd")
    value.recordPhysicalKeyEvent(keyCode: 0, isKeyDown: true, isRepeat: false, at: start)
    value.insertBatch("a", at: start)
    value.recordPhysicalKeyEvent(keyCode: 11, isKeyDown: true, isRepeat: false, at: start.addingTimeInterval(15))
    value.insertBatch("b", at: start.addingTimeInterval(15))
    value.bailOut(at: start.addingTimeInterval(16))
    let result = try XCTUnwrap(value.result())
    XCTAssertEqual(result.outcome, .bailedOut)
    XCTAssertEqual(result.elapsedDuration, 15)
    XCTAssertEqual(result.wallClockDuration, 16)
    var normal = TypingSession(configuration: .words(1), prompt: "ab")
    normal.recordPhysicalKeyEvent(keyCode: 0, isKeyDown: true, isRepeat: false, at: start)
    normal.insertBatch("a", at: start)
    normal.recordPhysicalKeyEvent(keyCode: 11, isKeyDown: true, isRepeat: false, at: start.addingTimeInterval(15))
    normal.insertBatch("b", at: start.addingTimeInterval(15))
    XCTAssertNil(try XCTUnwrap(normal.result()).terminalTiming)
  }

  func testActiveRestartAccountingDoesNotFinishOrMutateTheAttempt() throws {
    let value = input()
    XCTAssertEqual(value.activeEngagedDuration(at: start.addingTimeInterval(16)), 2)
    XCTAssertEqual(value.outcome, .active)
    XCTAssertFalse(value.isFinished)
    XCTAssertNil(value.result())
    XCTAssertEqual(try finish(value).engagedDuration, 2)
  }

  func testSaveEligibilityUsesMeasuredDurationInsteadOfTheUntrimmedEndDate() throws {
    let result = try finish(input(last: 14.994))
    XCTAssertEqual(result.outcome, .completed)
    XCTAssertEqual(result.wallClockDuration, 16)
    XCTAssertEqual(result.elapsedDuration, 14.99)
    XCTAssertEqual(ResultEligibilityPolicy.assessment(for: result, samePromptRepeat: false), .ineligible(.tooShort))
    XCTAssertFalse(ResultTerminalTiming(version: 1, endMilliseconds: 16_000, lastKeypressMilliseconds: 15_000)
      .isValid(wallClockDuration: 16, mode: .words, outcome: .completed))
  }

  func testTimingTrimNeverClipsTheInputTapeOrCopyText() throws {
    var value = input()
    value.insertBatch("c", at: start.addingTimeInterval(15.5))
    let result = try finish(value)
    XCTAssertEqual(result.elapsedDuration, 15)
    XCTAssertEqual(result.replayEvents.last?.offset, 15.5)
    XCTAssertEqual(ResultInputText.make(for: result), "abc")
    let restored = try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(result))
    XCTAssertEqual(restored.replayEvents, result.replayEvents)
    XCTAssertEqual(ResultInputText.make(for: restored), "abc")
  }

  func testPortableRoundTripAndMalformedVersionClockOrLastDownReject() throws {
    let result = try finish(input(last: 15.12789), at: 16.875)
    XCTAssertEqual(try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(result)), result)
    for (key, bad): (String, Any) in [("version",2), ("endMilliseconds",16_877),
      ("lastKeypressMilliseconds",16_876), ("endMilliseconds",-1)] {
      var json = try object(result)
      var timing = try XCTUnwrap(json["terminalTiming"] as? [String: Any])
      timing[key] = bad; json["terminalTiming"] = timing
      XCTAssertThrowsError(try JSONDecoder().decode(CompletedTestResult.self,
        from: JSONSerialization.data(withJSONObject: json)))
    }
    for state in [TestOutcome.active, .abandoned] {
      var json = try object(result); json["outcome"] = state.rawValue
      XCTAssertThrowsError(try JSONDecoder().decode(CompletedTestResult.self,
        from: JSONSerialization.data(withJSONObject: json)))
    }
  }

  @MainActor func testInMemoryEntityAndHistoryUseEvidenceWithoutBackfillingLegacy() throws {
    let result = try finish(input())
    let container = try ModelContainer(for: TestResultRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    container.mainContext.insert(TestResultRecord(result: result))
    try container.mainContext.save()
    let record = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).first)
    XCTAssertEqual(record.portableResult, result)
    XCTAssertEqual(record.elapsedDuration, 15)
    XCTAssertEqual(record.chartDuration, 15)
    XCTAssertEqual(ResultMetric(record: record).elapsedSeconds, 15)
    record.terminalTimingData = Data("{}".utf8)
    XCTAssertNil(record.portableResult, "Malformed evidence must not be exported as a legacy result")
    let old = legacy()
    let oldRecord = TestResultRecord(result: old)
    XCTAssertNil(oldRecord.terminalTimingData)
    XCTAssertEqual(oldRecord.elapsedDuration, 16)
    XCTAssertEqual(oldRecord.portableResult, old)
  }

  private func legacy() -> CompletedTestResult {
    .init(id: UUID(), configuration: input().configuration, outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(16), typedCharacterCount: 2,
      correctCharacterCount: 2, errorCount: 0, wpm: 17, rawWpm: 29, accuracy: 77,
      prompt: "", replayEvents: [.init(offset: 0, kind: .insert, text: "a"), .init(offset: 15, kind: .insert, text: "b")])
  }

  func testArchiveTwentyThreeIsRequiredOnlyWhenEvidenceIsPresent() throws {
    let result = try finish(input())
    XCTAssertEqual(TypebarArchive(version: 22, exportedAt: start, settings: .init(), results: [result], presets: []).version, 23)
    let data = try TypebarDataTransfer.exportArchive(settings: .init(), results: [result], presets: [])
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from: data).results.first, result)
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    json["version"] = 22
    XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: json))) {
      XCTAssertEqual($0 as? DataTransferError, .unsupportedVersion(22))
    }
    let old = legacy()
    let oldArchive = TypebarArchive(version: 22, exportedAt: start, settings: .init(), results: [old], presets: [])
    XCTAssertEqual(oldArchive.version, 22)
    XCTAssertEqual(try JSONDecoder().decode(TypebarArchive.self, from: JSONEncoder().encode(oldArchive)).results.first, old)
    XCTAssertNil(try object(old)["terminalTiming"])
  }

  func testLocalAndRemoteCSVSeparateMeasuredAndWallTimeWithoutExposingText() throws {
    let result = try finish(input())
    let local = ResultCSVExport.csvString(for: [result]).components(separatedBy: "\r\n")[1].components(separatedBy: ",")
    XCTAssertEqual(local.count, ResultCSVExport.columns.count)
    let localFields = Dictionary(uniqueKeysWithValues: zip(ResultCSVExport.columns, local))
    XCTAssertEqual(localFields["elapsed_seconds"], "15.00")
    XCTAssertEqual(localFields["wall_clock_seconds"], "16.00")
    XCTAssertEqual(localFields["terminal_timing_version"], "1")
    var json: [String: Any] = ["id": UUID().uuidString, "mode": "zen", "language": "english",
      "wpm": 32, "rawWpm": 32, "accuracy": 100, "errorCount": 0, "eventCount": 40,
      "tags": [], "startedAt": 100, "finishedAt": 116,
      "terminalTiming": ["version":1, "endMilliseconds":16_875, "lastKeypressMilliseconds":15_125]]
    let remote = try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: json))
    XCTAssertEqual(remote.elapsedDuration, 15.13)
    let row = RemoteResultCSVExport.csvString(for: [remote]).components(separatedBy: "\r\n")[1].components(separatedBy: ",")
    XCTAssertEqual(row.count, RemoteResultCSVExport.columns.count)
    let remoteFields = Dictionary(uniqueKeysWithValues: zip(RemoteResultCSVExport.columns, row))
    XCTAssertEqual(remoteFields["elapsed_seconds"], "15.13")
    XCTAssertEqual(remoteFields["wall_clock_seconds"], "16.00")
    XCTAssertFalse(RemoteResultCSVExport.columns.contains("replayEvents"))
    json["terminalTiming"] = ["version":1, "endMilliseconds":18_000, "lastKeypressMilliseconds":15_000]
    XCTAssertThrowsError(try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: json)))
  }

  @MainActor func testPublicationRequiresExactCapabilityAndRetainsAnonymousEvidence() async throws {
    let result = try finish(input())
    for capabilities in [nil, RemoteServiceCapabilities(apiVersion: "v2", service: "typebar", capabilities: ["resultTerminalTiming":"available"]),
      RemoteServiceCapabilities(apiVersion: "v1", service: "other", capabilities: ["resultTerminalTiming":"available"]),
      RemoteServiceCapabilities(apiVersion: "v1", service: "typebar", capabilities: ["resultTerminalTiming":"partial"])] {
      do {
        _ = try await ResultConsistencyPublication.prepare(result: result, capabilities: capabilities)
        XCTFail("Missing support must never silently drop the new denominator")
      } catch is RemoteAccountError {}
    }
    let supported = RemoteServiceCapabilities(apiVersion: "v1", service: "typebar", capabilities: ["resultTerminalTiming":"available"])
    let wire = try await ResultConsistencyPublication.prepare(result: result, capabilities: supported)
    XCTAssertEqual(wire.terminalTiming, result.terminalTiming)
    let json = try object(wire)
    for privateKey in ["prompt", "replayEvents", "keyCode", "characters", "lastKey"] { XCTAssertNil(json[privateKey]) }
    let old = try await ResultConsistencyPublication.prepare(result: legacy(), capabilities: nil)
    XCTAssertNil(old.terminalTiming)
    XCTAssertEqual(old.wpm, 17)
    let malformed = CompletedTestResult(id: UUID(), configuration: result.configuration, outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(16),
      terminalTiming: .init(version: 9, endMilliseconds: 16_000, lastKeypressMilliseconds: 15_000),
      typedCharacterCount: 2, correctCharacterCount: 2, errorCount: 0, wpm: 2, rawWpm: 2, accuracy: 100,
      prompt: "", replayEvents: result.replayEvents)
    do {
      _ = try await ResultConsistencyPublication.prepare(result: malformed, capabilities: supported)
      XCTFail("Invalid in-memory evidence must fail before submission too")
    } catch is RemoteAccountError {}
  }
}
