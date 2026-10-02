import XCTest
@testable import Typebar

final class RawCommitCreditTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 908_800_000)

  func testWrongReturnForSpaceCannotEarnLiveOrTerminalWholeWordCredit() throws {
    var session = TypingSession(configuration: .words(3), prompt: "é beta\nlast")
    session.insertBatch("é\n", at: start)
    XCTAssertEqual(session.wpm(at: start.addingTimeInterval(1)), 0)
    session.bailOut(at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.wpm, 0)
    XCTAssertEqual(result.inputMetrics?.creditedUnits, 0)
    XCTAssertEqual(result.inputMetrics?.retainedUnits, 2)
    XCTAssertEqual(result.inputMetrics?.correctAttempts, 1)
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 2)
    XCTAssertEqual(result.rawWpm, 12)
    XCTAssertEqual(ResultPerformanceTrace.point(prompt: result.prompt, events: result.replayEvents,
      elapsed: 2, configuration: result.configuration).wpm, result.wpm)
  }

  func testWrongSpaceForReturnDoesNotEraseLaterCorrectWordCredit() throws {
    var session = TypingSession(configuration: .words(3), prompt: "é\nbeta last")
    session.insertBatch("é ", at: start)
    session.insertBatch("beta last", at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.outcome, .completed)
    XCTAssertEqual(result.inputMetrics?.creditedUnits, 9)
    XCTAssertEqual(result.inputMetrics?.retainedUnits, 11)
    XCTAssertEqual(result.wpm, 54)
    XCTAssertEqual(result.rawWpm, 66)
    XCTAssertEqual(ResultPerformanceTrace.point(prompt: result.prompt, events: result.replayEvents,
      elapsed: 2, configuration: result.configuration).wpm, result.wpm)
  }

  func testActualMatchingSpaceAndReturnRetainTheirFullCredit() throws {
    var session = TypingSession(configuration: .words(3), prompt: "é beta\nlast")
    session.insertBatch("é ", at: start)
    session.insertBatch("beta\nlast", at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.outcome, .completed)
    XCTAssertEqual(result.inputMetrics?.creditedUnits, 11)
    XCTAssertEqual(result.wpm, 66)
    XCTAssertEqual(result.rawWpm, 66)
  }

  func testDeletingWrongCommitRestoresPrefixThenCorrectCommitWithoutErasingMistake() throws {
    var session = TypingSession(configuration: .words(3), prompt: "é beta\nlast")
    session.insertBatch("é\n", at: start)
    session.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "é")
    XCTAssertEqual(session.wpm(at: start.addingTimeInterval(2)), 6)
    session.insertBatch(" ", at: start.addingTimeInterval(3))
    session.bailOut(at: start.addingTimeInterval(4))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.inputMetrics?.creditedUnits, 2)
    XCTAssertEqual(result.inputMetrics?.correctAttempts, 2)
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 3)
    XCTAssertEqual(result.wpm, 6)
    XCTAssertEqual(result.rawWpm, 6)
  }

  func testUnconvertedASCIIKeepsItsExistingFullSeparatorComparison() throws {
    var session = TypingSession(configuration: .words(3), prompt: "ab cd\nlast")
    session.insertBatch("ab\n", at: start)
    session.bailOut(at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    XCTAssertTrue(result.replayEvents.allSatisfy { $0.textUTF16 == nil })
    XCTAssertEqual(result.inputMetrics?.creditedUnits, 0)
    XCTAssertEqual(result.wpm, 0)
    XCTAssertEqual(result.rawWpm, 18)
  }

  func testNewCorrectedMetricsSurvivePortableAndFormalArchive() throws {
    var session = TypingSession(configuration: .words(3), prompt: "é\nbeta last")
    session.insertBatch("é ", at: start)
    session.insertBatch("beta last", at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [], at: start))
    for restored in [archive.results[0], try XCTUnwrap(TestResultRecord(result: result).portableResult)] {
      XCTAssertEqual(restored, result)
      XCTAssertEqual(restored.inputMetrics?.creditedUnits, 9)
      XCTAssertEqual(restored.wpm, 54)
      XCTAssertEqual(RemoteResultSubmission(result: restored).wpm, 54)
    }
    XCTAssertEqual(archive.version, 14)
  }

  func testPreFixArchiveFourteenKeepsItsRecordedCreditRatherThanBeingRecomputed() throws {
    let old = CompletedTestResult(id: UUID(), configuration: .words(3), outcome: .bailedOut,
      startedAt: start, finishedAt: start.addingTimeInterval(2), typedCharacterCount: 2,
      correctCharacterCount: 2, errorCount: 1, wpm: 12, rawWpm: 12, accuracy: 50,
      inputMetrics: .init(version: 1, correctAttempts: 1, totalAttempts: 2, creditedUnits: 2, retainedUnits: 2),
      prompt: "é beta\nlast", replayEvents: [
        .init(offset: 0, kind: .insert, units: [233], inputField: .init(index: 0, units: [233]),
          inputCorrectness: [true]),
        .init(offset: 0, kind: .insert, units: [10], inputField: .init(index: 0, units: [233,10]),
          inputCorrectness: [false])])
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [old], presets: [], at: start))
    for restored in [archive.results[0], try XCTUnwrap(TestResultRecord(result: old).portableResult)] {
      XCTAssertEqual(restored, old)
      XCTAssertEqual(restored.inputMetrics?.creditedUnits, 2)
      XCTAssertEqual(restored.wpm, 12)
      XCTAssertEqual(RemoteResultSubmission(result: restored).wpm, 12)
    }
  }
}
