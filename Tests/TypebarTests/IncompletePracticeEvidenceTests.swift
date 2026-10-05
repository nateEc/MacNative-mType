import Foundation
import SwiftData
import XCTest
@testable import Typebar

final class IncompletePracticeEvidenceTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 913_000_000.875)

  private func legacy() -> CompletedTestResult {
    .init(id: UUID(), configuration: .words(25), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(15),
      typedCharacterCount: 100, correctCharacterCount: 100, errorCount: 0,
      wpm: 80, rawWpm: 80, accuracy: 100, restartCount: 1,
      priorAttemptEngagedDuration: 1.5, prompt: "owned prompt")
  }

  private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
  }

  private func decode(_ value: [String: Any]) throws -> CompletedTestResult {
    try JSONDecoder().decode(CompletedTestResult.self, from: JSONSerialization.data(withJSONObject: value))
  }

  func testUnknownIncompleteEvidenceCannotSilentlyBecomeLegacyAbsence() throws {
    var json = try object(legacy())
    json["incompletePractice"] = ["version": 2, "attempts": [["accuracy": 100, "seconds": 1.5]]]
    XCTAssertThrowsError(try decode(json))
  }

  func testIncompleteEvidenceCannotDisagreeWithRestartCountOrCarriedDuration() throws {
    var json = try object(legacy())
    for attempts in [[], [["accuracy": 100.0, "seconds": 100.0]]] {
      json["incompletePractice"] = ["version": 1, "attempts": attempts]
      XCTAssertThrowsError(try decode(json))
    }
  }

  func testArchiveHasAnExplicitNewFormatBoundaryForIncompleteEvidence() throws {
    let archive = TypebarArchive(version: 1, exportedAt: start, settings: .init(),
      results: [try evidence()], presets: [])
    XCTAssertEqual(archive.version, 26, "Incomplete evidence alone still requires the version 26 boundary")
    XCTAssertGreaterThanOrEqual(TypebarArchive.currentVersion, archive.version)
  }

  private func evidence(_ value: CompletedTestResult? = nil, accuracy: Double = 66.67,
    seconds: Double = 1.5) throws -> CompletedTestResult {
    var json = try object(value ?? legacy())
    json["incompletePractice"] = ["version": 1, "attempts": [["accuracy": accuracy, "seconds": seconds]]]
    return try decode(json)
  }

  func testLiveRestartCapturesRoundedAccuracyAndSecondsWithoutChangingRawAggregate() throws {
    var elapsed = 0.0
    var session = TypingSession(configuration: .words(25), prompt: "abcdef").withElapsedClock(.init { elapsed })
    session.insert("a", at: start)
    elapsed = 0.5; session.insert("x", at: start.addingTimeInterval(-3_600))
    elapsed = 1.005; session.insert("c", at: start.addingTimeInterval(3_600))
    let raw = session.activeEngagedDuration(at: start)
    XCTAssertEqual(session.preciseAccuracy, 200.0 / 3, accuracy: 0.000001)
    XCTAssertEqual(raw, 1.005, accuracy: 0.000001)
    var ledger = PriorAttemptLedger()
    ledger.recordRestart(engagedDuration: raw, accuracy: session.preciseAccuracy, savingEnabled: true)
    let value = try XCTUnwrap(ledger.incompletePractice)
    XCTAssertEqual(value.attempts, [.init(accuracy: 66.67, seconds: 1.01)])
    XCTAssertEqual(ledger.restartCount, 1)
    XCTAssertEqual(ledger.priorAttemptEngagedDuration, raw)
    XCTAssertTrue(value.isValid(restartCount: ledger.restartCount, engagedDuration: raw))
    XCTAssertFalse(session.isFinished)
  }

  func testIdleRestartCapturesOnlyEngagedSeconds() throws {
    var elapsed = 0.0
    var session = TypingSession(configuration: .timed(seconds: 60), prompt: "abc").withElapsedClock(.init { elapsed })
    session.insert("a", at: start)
    elapsed = 20
    var ledger = PriorAttemptLedger()
    ledger.recordRestart(engagedDuration: session.activeEngagedDuration(at: start),
      accuracy: session.preciseAccuracy, savingEnabled: true)
    XCTAssertLessThan(ledger.priorAttemptEngagedDuration, 20)
    XCTAssertEqual(try XCTUnwrap(ledger.incompletePractice).summedSeconds, ledger.priorAttemptEngagedDuration)
    XCTAssertFalse(session.isFinished)
  }

  func testTerminalFailureRepeatAndIdleCaptureTheAttemptAccuracy() throws {
    for (outcome, eligibility, repeated) in [(TestOutcome.failed, ResultEligibility.ineligible(.testFailed), false),
      (.completed, .ineligible(.samePromptRepeat), false), (.invalidAFK, .ineligible(.inactivity), true),
      (.bailedOut, .ineligible(.samePromptRepeat), true)] {
      var ledger = PriorAttemptLedger()
      ledger.recordTerminalAttempt(engagedDuration: 1.505, outcome: outcome, eligibility: eligibility,
        savingEnabled: true, samePromptRepeat: repeated, accuracy: 33.333333)
      XCTAssertEqual(ledger.restartCount, 1)
      XCTAssertEqual(ledger.incompletePractice?.attempts, [.init(accuracy: 33.33, seconds: 1.51)])
      XCTAssertEqual(ledger.priorAttemptEngagedDuration, 1.505)
    }
  }

  func testSavingDisabledAndUncarriedTerminalsDoNotChangeEvidence() {
    var ledger = PriorAttemptLedger()
    ledger.recordRestart(engagedDuration: 100, accuracy: 0, savingEnabled: false)
    for outcome in [TestOutcome.completed, .invalidAFK, .abandoned, .active] {
      ledger.recordTerminalAttempt(engagedDuration: 100, outcome: outcome, eligibility: .eligible,
        savingEnabled: true, accuracy: 0)
    }
    XCTAssertEqual(ledger.incompletePractice, .empty)
    XCTAssertEqual(ledger.restartCount, 0)
    XCTAssertEqual(ledger.priorAttemptEngagedDuration, 0)
  }

  func testZeroAccuracyAndZeroDurationAreExplicitNotUnknown() {
    var ledger = PriorAttemptLedger()
    ledger.recordRestart(engagedDuration: 0, accuracy: 0, savingEnabled: true)
    XCTAssertEqual(ledger.incompletePractice?.attempts, [.init(accuracy: 0, seconds: 0)])
    XCTAssertEqual(ledger.restartCount, 1)
  }

  func testMixedUnknownHistoryNeverInventsAccuracyOrPartialArray() {
    var ledger = PriorAttemptLedger()
    ledger.recordRestart(engagedDuration: 1, accuracy: 75, savingEnabled: true)
    ledger.recordRestart(engagedDuration: 2, savingEnabled: true)
    ledger.recordRestart(engagedDuration: 3, accuracy: 100, savingEnabled: true)
    XCTAssertNil(ledger.incompletePractice)
    XCTAssertEqual(ledger.restartCount, 3)
    XCTAssertEqual(ledger.priorAttemptEngagedDuration, 6)
    ledger.clearAfterPersistingResult()
    XCTAssertEqual(ledger.incompletePractice, .empty)
    XCTAssertEqual(ledger.restartCount, 0)
    XCTAssertEqual(ledger.priorAttemptEngagedDuration, 0)
  }

  func testInvalidCaptureDoesNotBecomePerfectOrLoseLegacyCount() {
    for (seconds, accuracy) in [(1.0, Double.nan), (1, -1), (1, 101),
      (Double.infinity, 100), (-1, 100)] {
      var ledger = PriorAttemptLedger()
      ledger.recordRestart(engagedDuration: seconds, accuracy: accuracy, savingEnabled: true)
      XCTAssertNil(ledger.incompletePractice)
      XCTAssertEqual(ledger.restartCount, 1)
    }
  }

  func testSnapshotsAreValueIsolatedAndAttemptsAreNotCollapsed() throws {
    var ledger = PriorAttemptLedger()
    ledger.recordRestart(engagedDuration: 0.5, accuracy: 100, savingEnabled: true)
    let first = try XCTUnwrap(ledger.incompletePractice)
    ledger.recordRestart(engagedDuration: 0.5, accuracy: 100, savingEnabled: true)
    XCTAssertEqual(first.attempts.count, 1)
    XCTAssertEqual(ledger.incompletePractice?.attempts.count, 2)
    XCTAssertEqual(ledger.priorAttemptEngagedDuration, 1)
    ledger.clearAfterPersistingResult()
    XCTAssertEqual(first.attempts, [.init(accuracy: 100, seconds: 0.5)])
  }

  func testFinalSessionResultKeepsTheWholePriorSnapshotAfterClearingLedger() throws {
    var elapsed = 0.0
    var ledger = PriorAttemptLedger()
    ledger.recordRestart(engagedDuration: 1.5, accuracy: 66.66666, savingEnabled: true)
    var session = TypingSession(configuration: .init(mode: .quote, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init()), prompt: "ab").withElapsedClock(.init { elapsed })
    session.insert("a", at: start); elapsed = 1.5; session.insert("b", at: start.addingTimeInterval(-3_600))
    let result = try XCTUnwrap(session.result(restartCount: ledger.restartCount,
      priorAttemptEngagedDuration: ledger.priorAttemptEngagedDuration, incompletePractice: ledger.incompletePractice))
    ledger.clearAfterPersistingResult()
    XCTAssertEqual(result.incompletePractice?.attempts, [.init(accuracy: 66.67, seconds: 1.5)])
    XCTAssertEqual(result.restartCount, 1)
    XCTAssertEqual(result.priorAttemptEngagedDuration, 1.5)
    XCTAssertEqual(try decode(object(result)), result)
  }

  func testLegacyAbsenceIsPreservedAcrossJSONAndPortableStorage() throws {
    let old = legacy()
    XCTAssertNil(old.incompletePractice)
    XCTAssertNil(try object(old)["incompletePractice"])
    XCTAssertEqual(try decode(object(old)), old)
    let record = TestResultRecord(result: old)
    XCTAssertNil(record.incompletePracticeData)
    XCTAssertEqual(record.portableResult, old)
    XCTAssertEqual(old.accuracy, 100)
    XCTAssertEqual(old.priorAttemptEngagedDuration, 1.5)
  }

  func testMalformedExplicitEvidenceAndMissingBindingCannotDowngrade() throws {
    for marker: Any in [NSNull(), [:], ["version": 1], ["attempts": []],
      ["version": 1, "attempts": [["accuracy": -1, "seconds": 1.5]]],
      ["version": 1, "attempts": [["accuracy": 101, "seconds": 1.5]]],
      ["version": 1, "attempts": [["accuracy": 50, "seconds": -1]]],
      ["version": 1, "attempts": [["accuracy": 50]]]] {
      var json = try object(legacy()); json["incompletePractice"] = marker
      XCTAssertThrowsError(try decode(json))
    }
    for key in ["restartCount", "priorAttemptEngagedDuration"] {
      var json = try object(try evidence()); json.removeValue(forKey: key)
      XCTAssertThrowsError(try decode(json))
      json[key] = NSNull(); XCTAssertThrowsError(try decode(json))
      json[key] = -1; XCTAssertThrowsError(try decode(json))
    }
  }

  func testRoundingToleranceIsBoundedPerAttemptAndZeroCountRequiresZeroTime() {
    let value = ResultIncompletePractice(attempts: [.init(accuracy: 100, seconds: 1.01)])
    XCTAssertTrue(value.isValid(restartCount: 1, engagedDuration: 1.005))
    XCTAssertFalse(value.isValid(restartCount: 1, engagedDuration: 1.004))
    XCTAssertFalse(value.isValid(restartCount: 0, engagedDuration: 1.01))
    XCTAssertFalse(ResultIncompletePractice.empty.isValid(restartCount: 0, engagedDuration: 1e-10))
  }

  @MainActor func testInMemoryStoreRecreatesTheSnapshotAndRetainsCorruptExplicitBytes() throws {
    let result = try evidence()
    let container = try ModelContainer(for: TestResultRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    container.mainContext.insert(TestResultRecord(result: result))
    try container.mainContext.save()
    let record = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).first)
    XCTAssertEqual(record.portableResult, result)
    XCTAssertNotNil(record.incompletePracticeData)
    let bytes = Data("{}".utf8)
    record.incompletePracticeData = bytes
    record.addTag("owned")
    try container.mainContext.save()
    XCTAssertEqual(record.incompletePracticeData, bytes)
    XCTAssertNil(record.incompletePractice)
    XCTAssertNil(record.portableResult)
    XCTAssertEqual(record.priorAttemptEngagedDuration, 1.5)
    XCTAssertEqual(record.wpm, 80)
  }

  func testInvalidConstructorEvidenceIsNotExportedOrDroppedDuringStorage() throws {
    let old = legacy()
    let invalid = CompletedTestResult(id: old.id, configuration: old.configuration,
      outcome: old.outcome, startedAt: old.startedAt, finishedAt: old.finishedAt,
      typedCharacterCount: 100, correctCharacterCount: 100, errorCount: 0, wpm: 80, rawWpm: 80,
      accuracy: 100, restartCount: 1, priorAttemptEngagedDuration: 1.5,
      incompletePractice: .init(version: 2, attempts: [.init(accuracy: 100, seconds: 1.5)]))
    XCTAssertThrowsError(try JSONEncoder().encode(invalid))
    let record = TestResultRecord(result: invalid)
    XCTAssertNotNil(record.incompletePracticeData)
    XCTAssertNil(record.portableResult)
  }

  func testStoredEvidenceNeedsRawBindingsAndNeverUsesNormalizedFallbacks() throws {
    let result = try evidence()
    for kind in 0..<4 {
      let record = TestResultRecord(result: result)
      let bytes = try XCTUnwrap(record.incompletePracticeData)
      switch kind {
      case 0: record.storedRestartCount = nil
      case 1: record.storedPriorAttemptEngagedDuration = nil
      case 2: record.storedRestartCount = -1
      default: record.storedPriorAttemptEngagedDuration = -1
      }
      XCTAssertNil(record.incompletePractice)
      XCTAssertNil(record.portableResult)
      record.addTag("owned")
      XCTAssertEqual(record.incompletePracticeData, bytes)
      XCTAssertEqual(record.wpm, result.wpm)
    }
  }

  private func archiveData(_ archive: TypebarArchive) throws -> Data {
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(archive)
  }

  func testArchiveUpgradePreservesSnapshotAndAllTombstoneFamilies() throws {
    let result = try evidence(), deleted = UUID()
    let archive = TypebarArchive(version: 1, exportedAt: start, settings: .init(),
      deletedCustomThemeIDs: [deleted], deletedCustomKeyboardLayoutIDs: [deleted], results: [result],
      deletedResultIDs: [deleted], presets: [], deletedPresetIDs: [deleted],
      deletedSavedTextIDs: [deleted], deletedResultFilterPresetIDs: [deleted])
    XCTAssertEqual(archive.version, 26)
    let restored = try TypebarDataTransfer.importArchive(from: archiveData(archive))
    XCTAssertEqual(restored.results, [result])
    XCTAssertEqual(restored.deletedCustomThemeIDs, [deleted])
    XCTAssertEqual(restored.deletedCustomKeyboardLayoutIDs, [deleted])
    XCTAssertEqual(restored.deletedResultIDs, [deleted])
    XCTAssertEqual(restored.deletedPresetIDs, [deleted])
    XCTAssertEqual(restored.deletedSavedTextIDs, [deleted])
    XCTAssertEqual(restored.deletedResultFilterPresetIDs, [deleted])
  }

  func testOlderArchiveCannotHideNewEvidenceBehindATombstone() throws {
    let result = try evidence()
    let archive = TypebarArchive(exportedAt: start, settings: .init(), results: [result], presets: [])
    for version in [1, 23, 24, 25] {
      var json = try XCTUnwrap(JSONSerialization.jsonObject(with: archiveData(archive)) as? [String: Any])
      json["version"] = version; json["deletedResultIDs"] = [result.id.uuidString]
      let data = try JSONSerialization.data(withJSONObject: json)
      let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
      XCTAssertThrowsError(try decoder.decode(TypebarArchive.self, from: data))
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: data))
    }
  }

  func testEveryOlderArchiveVersionKeepsMissingEvidenceMissing() throws {
    for version in 1...25 {
      let archive = TypebarArchive(version: version, exportedAt: start, settings: .init(),
        results: [legacy()], presets: [])
      XCTAssertEqual(archive.version, version)
      let restored = try TypebarDataTransfer.importArchive(from: archiveData(archive))
      XCTAssertEqual(restored.results.first, legacyWithID(restored.results.first!.id))
      XCTAssertNil(restored.results.first?.incompletePractice)
    }
  }

  private func legacyWithID(_ id: UUID) -> CompletedTestResult {
    .init(id: id, configuration: .words(25), outcome: .completed, startedAt: start,
      finishedAt: start.addingTimeInterval(15), typedCharacterCount: 100, correctCharacterCount: 100,
      errorCount: 0, wpm: 80, rawWpm: 80, accuracy: 100, restartCount: 1,
      priorAttemptEngagedDuration: 1.5, prompt: "owned prompt")
  }
}
