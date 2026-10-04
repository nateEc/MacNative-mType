import XCTest
import SwiftData
@testable import Typebar

final class ResultElapsedTimeTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_800_000_000)

  private func legacy() -> CompletedTestResult {
    .init(id: UUID(), configuration: .words(1), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(16), afkDuration: 2,
      typedCharacterCount: 3, correctCharacterCount: 3, errorCount: 0,
      wpm: 17, rawWpm: 29, accuracy: 77, keyDurationSamples: [0.1],
      prompt: "abc", replayEvents: [.init(offset: 0, kind: .insert, text: "a"),
        .init(offset: 15, kind: .insert, text: "bc")])
  }

  private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
  }

  private func payload(wall: Double = -3_600, seconds: Any = 16, version: Int = 1) throws -> [String: Any] {
    var json = try object(legacy())
    let end = start.addingTimeInterval(wall).timeIntervalSinceReferenceDate
    json["finishedAt"] = end; json["finishedAtReferenceTime"] = end
    json["elapsedTime"] = ["version": version, "seconds": seconds]
    return json
  }

  private func decode(_ json: [String: Any]) throws -> CompletedTestResult {
    let decoder = JSONDecoder()
    decoder.nonConformingFloatDecodingStrategy = .convertFromString(
      positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
    return try decoder.decode(CompletedTestResult.self, from: JSONSerialization.data(withJSONObject: json))
  }

  private func archiveData(_ archive: TypebarArchive) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(archive)
  }

  func testIndependentDurationKeepsCalendarDatesScoresAndTheWholeReplay() throws {
    for wall in [-3_600.0, 3_600, 16] {
      let result = try decode(payload(wall: wall))
      XCTAssertEqual(result.startedAt, start)
      XCTAssertEqual(result.finishedAt, start.addingTimeInterval(wall))
      XCTAssertEqual(result.wallClockDuration, max(0, wall))
      XCTAssertEqual(result.elapsedDuration, 16)
      XCTAssertEqual(result.chartDuration, 16)
      XCTAssertEqual(result.engagedDuration, 14)
      XCTAssertEqual(result.wpm, 17); XCTAssertEqual(result.rawWpm, 29)
      XCTAssertEqual(result.accuracy, 77)
      XCTAssertEqual(result.replayEvents, legacy().replayEvents)
      XCTAssertEqual(ResultInputText.make(for: result), "abc")
      let restored = try decode(object(result))
      XCTAssertEqual(restored, result)
      XCTAssertEqual((try object(restored)["elapsedTime"] as? [String: Double])?["seconds"], 16)
    }
  }

  func testExplicitInvalidMetadataCannotBecomeALegacyResult() throws {
    for seconds: Any in [-1, "NaN", "Infinity", "-Infinity", "bad", Double.greatestFiniteMagnitude] {
      XCTAssertThrowsError(try decode(payload(seconds: seconds)))
    }
    XCTAssertThrowsError(try decode(payload(version: 2)))
    var json = try payload(); json["elapsedTime"] = [:]
    XCTAssertThrowsError(try decode(json))
    json["elapsedTime"] = ["version": 1]
    XCTAssertThrowsError(try decode(json))
    json["elapsedTime"] = ["seconds": 16]
    XCTAssertThrowsError(try decode(json))
  }

  func testTerminalEvidenceBindsToCapturedElapsedTimeNotTheCalendarGap() throws {
    var json = try payload()
    json["outcome"] = TestOutcome.bailedOut.rawValue
    json["terminalTiming"] = ["version": 1, "endMilliseconds": 16_000, "lastKeypressMilliseconds": 15_125]
    let result = try decode(json)
    XCTAssertEqual(result.elapsedDuration, 15.13)
    XCTAssertEqual(result.chartDuration, 15.125)
    XCTAssertEqual(result.engagedDuration, 13.13, accuracy: 0.000001)
    XCTAssertEqual(ResultInputText.make(for: result), "abc")
    json["terminalTiming"] = ["version": 1, "endMilliseconds": 16_100]
    XCTAssertThrowsError(try decode(json))
  }

  @MainActor func testInMemoryPersistenceAndHistoryPreserveTheIndependentBasis() throws {
    let result = try decode(payload())
    let container = try ModelContainer(for: TestResultRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    container.mainContext.insert(TestResultRecord(result: result))
    try container.mainContext.save()
    let record = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).first)
    XCTAssertEqual(record.elapsedDuration, 16)
    XCTAssertEqual(record.chartDuration, 16)
    XCTAssertEqual(ResultMetric(record: record).elapsedSeconds, 16)
    XCTAssertEqual(record.portableResult, result)
    XCTAssertNotNil(try object(try XCTUnwrap(record.portableResult))["elapsedTime"])
  }

  func testArchiveUpgradePreservesIdentityAndTombstones() throws {
    let result = try decode(payload())
    let deleted = UUID()
    let archive = TypebarArchive(version: 1, exportedAt: start, settings: .init(),
      results: [result], deletedResultIDs: [deleted], presets: [], deletedPresetIDs: [deleted],
      deletedSavedTextIDs: [deleted], deletedResultFilterPresetIDs: [deleted])
    XCTAssertEqual(archive.version, 25)
    XCTAssertEqual(archive.deletedResultIDs, [deleted])
    XCTAssertEqual(archive.deletedPresetIDs, [deleted])
    XCTAssertEqual(archive.deletedSavedTextIDs, [deleted])
    XCTAssertEqual(archive.deletedResultFilterPresetIDs, [deleted])
    let restored = try TypebarDataTransfer.importArchive(from: archiveData(archive))
    XCTAssertEqual(restored.results, [result])
    XCTAssertEqual(restored.deletedResultIDs, [deleted])
  }

  func testArchiveCannotHideNewTimingBehindATombstoneOrAnOldVersion() throws {
    let result = try decode(payload())
    let archive = TypebarArchive(exportedAt: start, settings: .init(), results: [result], presets: [])
    for version in [1, 23, 24] {
      var json = try XCTUnwrap(JSONSerialization.jsonObject(with: archiveData(archive)) as? [String: Any])
      json["version"] = version
      json["deletedResultIDs"] = [result.id.uuidString]
      let data = try JSONSerialization.data(withJSONObject: json)
      let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
      XCTAssertThrowsError(try decoder.decode(TypebarArchive.self, from: data))
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: data))
    }
  }

  @MainActor func testPublicationCannotSilentlyDropIndependentDurationWithoutExactCapability() async throws {
    let result = try decode(payload())
    let capabilities = RemoteServiceCapabilities(apiVersion: "v1", service: "typebar",
      capabilities: ["resultConsistency": "available", "resultElapsedTime": "planned"])
    for capability in [nil, capabilities] {
      do {
        _ = try await ResultConsistencyPublication.prepare(result: result, capabilities: capability) { _ in
          XCTFail("Do not calculate or upload an unsupported timing contract"); return 50
        }
        XCTFail("Independent timing must stay local without exact service capability")
      } catch let error as RemoteAccountError {
        guard case .serverMessage = error else { return XCTFail("Unexpected error: \(error)") }
      }
    }
  }

  func testLegacyAbsenceAndScoresAreNotBackfilled() throws {
    let result = legacy()
    XCTAssertNil(try object(result)["elapsedTime"])
    XCTAssertEqual(try decode(object(result)), result)
    XCTAssertEqual(result.elapsedDuration, 16)
    let archive = TypebarArchive(version: 1, exportedAt: start, settings: .init(), results: [result], presets: [])
    XCTAssertEqual(archive.version, 1)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from: archiveData(archive)).results, [result])
  }

  func testZeroAndFractionalDurationAreValidWithoutInventingAClockOrigin() throws {
    for seconds in [0.0, 16.1256789] {
      let result = try decode(payload(seconds: seconds))
      XCTAssertEqual(result.capturedDuration, seconds)
      XCTAssertEqual(result.elapsedDuration, ResultTerminalTiming.round(seconds))
      let timing = try XCTUnwrap(try object(result)["elapsedTime"] as? [String: Double])
      XCTAssertEqual(Set(timing.keys), ["version", "seconds"])
      XCTAssertEqual(timing["seconds"], seconds)
    }
  }

  func testNativeRepresentabilityLimitIsNotAnOrdinaryTestDurationLimit() throws {
    for seconds in [3_601.0, 864_000, ResultElapsedTime.maximumSeconds] {
      XCTAssertEqual(try decode(payload(seconds: seconds)).capturedDuration, seconds)
    }
    XCTAssertThrowsError(try decode(payload(seconds: ResultElapsedTime.maximumSeconds.nextUp)))
    XCTAssertThrowsError(try JSONEncoder().encode(ResultElapsedTime(version: 2, seconds: 16)))
  }

  @MainActor func testCorruptStoredEvidenceKeepsItsBytesAndCannotUseLegacyTime() throws {
    for bad in [Data("{}".utf8), Data(), Data("{\"version\":2,\"seconds\":16}".utf8)] {
      let record = TestResultRecord(result: try decode(payload(wall: 3_600)))
      record.elapsedTimeData = bad
      XCTAssertNil(record.elapsedTime)
      XCTAssertNil(record.portableResult)
      XCTAssertEqual(record.elapsedTimeData, bad)
      XCTAssertEqual(record.capturedDuration, 0)
      XCTAssertEqual(record.elapsedDuration, 0)
      XCTAssertEqual(record.chartDuration, 0)
      XCTAssertEqual(record.wallClockDuration, 3_600)
    }
  }

  @MainActor func testStoredTerminalTailUsesTheMeasuredBasisAndRejectsAConflictingEnd() throws {
    var json = try payload(wall: 3_600)
    json["outcome"] = TestOutcome.bailedOut.rawValue
    json["terminalTiming"] = ["version": 1, "endMilliseconds": 16_000, "lastKeypressMilliseconds": 15_125]
    let result = try decode(json), record = TestResultRecord(result: result)
    XCTAssertEqual(record.portableResult, result)
    XCTAssertEqual(record.capturedDuration, 16)
    XCTAssertEqual(record.elapsedDuration, 15.13)
    XCTAssertEqual(record.chartDuration, 15.125)
    record.terminalTimingData = try JSONEncoder().encode(
      ResultTerminalTiming(version: 1, endMilliseconds: 3_600_000, lastKeypressMilliseconds: 15_125))
    XCTAssertNil(record.terminalTiming)
    XCTAssertNil(record.portableResult)
  }

  @MainActor func testInvalidConstructedMetadataCannotSilentlyDisappearDuringPersistence() throws {
    let result = CompletedTestResult(id: UUID(), configuration: .words(1), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(3_600),
      elapsedTime: .init(seconds: .infinity), typedCharacterCount: 1,
      correctCharacterCount: 1, errorCount: 0, wpm: 1, rawWpm: 1, accuracy: 100)
    XCTAssertThrowsError(try JSONEncoder().encode(result))
    let record = TestResultRecord(result: result)
    XCTAssertNotNil(record.elapsedTimeData)
    XCTAssertNil(record.portableResult)
    XCTAssertEqual(record.elapsedDuration, 0)
  }

  func testCSVExposesMeasuredDurationAndActualDatesWithoutChangingLegacyColumns() throws {
    let result = try decode(payload())
    let rows = ResultCSVExport.csvString(for: [result]).components(separatedBy: "\r\n")
    let values = rows[1].components(separatedBy: ",")
    XCTAssertEqual(values.count, ResultCSVExport.columns.count)
    let fields = Dictionary(uniqueKeysWithValues: zip(ResultCSVExport.columns, values))
    XCTAssertEqual(fields["elapsed_seconds"], "16.00")
    XCTAssertEqual(fields["wall_clock_seconds"], "0.00")
    XCTAssertEqual(fields["engaged_seconds"], "14.00")
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    XCTAssertEqual(fields["started_at"], formatter.string(from: start))
    XCTAssertEqual(fields["finished_at"], formatter.string(from: start.addingTimeInterval(-3_600)))
    XCTAssertFalse(rows[0].contains("prompt"))
    XCTAssertFalse(rows[0].contains("replay"))
  }

  func testArchiveUpgradeRetainsPresetTextThemeLayoutAndFilteredResultIdentity() throws {
    let result = try decode(payload()), id = UUID(), deleted = UUID()
    let preset = NamedPreset(id: id, name: "owned", definition: .init(configuration: .words(1)))
    let archive = TypebarArchive(version: 1, exportedAt: start, settings: .init(),
      deletedCustomThemeIDs: [deleted], deletedCustomKeyboardLayoutIDs: [deleted],
      results: [result], deletedResultIDs: [result.id], presets: [preset],
      savedTexts: [.init(id: id, title: "owned", text: "owned text")])
    XCTAssertEqual(archive.version, 25)
    XCTAssertTrue(archive.results.isEmpty)
    XCTAssertEqual(archive.deletedResultIDs, [result.id])
    XCTAssertEqual(archive.deletedCustomThemeIDs, [deleted])
    XCTAssertEqual(archive.deletedCustomKeyboardLayoutIDs, [deleted])
    XCTAssertEqual(archive.presets.first?.id, id)
    XCTAssertEqual(archive.savedTexts.first?.id, id)
    let restored = try TypebarDataTransfer.importArchive(from: archiveData(archive))
    XCTAssertEqual(restored.presets, archive.presets)
    XCTAssertEqual(restored.savedTexts, archive.savedTexts)
    XCTAssertEqual(restored.deletedResultIDs, [result.id])
  }
}
