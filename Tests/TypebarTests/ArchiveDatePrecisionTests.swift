import XCTest
@testable import Typebar

final class ArchiveDatePrecisionTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 800_000_000.1234567)

  private func result(startingAt date: Date? = nil) throws -> CompletedTestResult {
    let date = date ?? start
    var session = TypingSession(configuration: .words(1), prompt: "ab")
    session.insert("a", at: date)
    session.insert("b", at: date.addingTimeInterval(2.75))
    return try XCTUnwrap(session.result())
  }

  private func archiveRoundTrip(_ result: CompletedTestResult) throws -> CompletedTestResult {
    let data = try TypebarDataTransfer.exportArchive(settings: .init(), results: [result],
      presets: [], at: start)
    return try XCTUnwrap(TypebarDataTransfer.importArchive(from: data).results.first)
  }

  func testArchiveRoundTripPreservesAllResultDatesAtSubsecondPrecision() throws {
    let original = try result()
    let restored = try archiveRoundTrip(original)
    XCTAssertEqual(restored.startedAt, original.startedAt)
    XCTAssertEqual(restored.finishedAt, original.finishedAt)
    XCTAssertEqual(restored.elapsedDuration, original.elapsedDuration)
    XCTAssertTrue(restored == original, "归档不应改变结果日期、精度或回放")
  }

  func testRestoredReplayWindowIncludesTheActualFinalKey() throws {
    let original = try result()
    let restored = try archiveRoundTrip(original)
    XCTAssertEqual(TypingReplay.typedText(events: restored.replayEvents,
      through: restored.elapsedDuration), "ab")
    XCTAssertEqual(restored.replayEvents.last?.offset, restored.elapsedDuration)
  }

  private func archiveObject() throws -> [String: Any] {
    let data = try TypebarDataTransfer.exportArchive(settings: .init(), results: [try result()],
      presets: [], at: start)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  private func data(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object)
  }

  func testArchiveAndResultPreserveReferenceBitsBeforeAndAfterBothEpochs() throws {
    for referenceTime in [-978_307_200.125, -0.125, 0.125, 800_000_000.1234567] {
      let date = Date(timeIntervalSinceReferenceDate: referenceTime)
      let original = try result(startingAt: date)
      let encoded = try TypebarDataTransfer.exportArchive(settings: .init(), results: [original],
        presets: [], at: date)
      let archive = try TypebarDataTransfer.importArchive(from: encoded)
      XCTAssertEqual(archive.exportedAt, date)
      XCTAssertEqual(archive.version, TypebarArchive.currentVersion)
      XCTAssertTrue(archive.results.first == original)
    }
  }

  func testAllLegacyArchiveVersionsRemainReadableWithoutPrecisionMetadata() throws {
    // Independent owned pre-field fixture; never strip a current producer's
    // position/stat metadata to impersonate an older archive.
    let old = CompletedTestResult(id: UUID(), configuration: .words(1), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(2.75), typedCharacterCount: 2,
      correctCharacterCount: 2, errorCount: 0, wpm: 17, rawWpm: 29, accuracy: 77,
      prompt: "ab", replayEvents: [.init(offset: 0, kind: .insert, text: "a"),
        .init(offset: 2.75, kind: .insert, text: "b")])
    let encoded = try TypebarDataTransfer.exportArchive(settings: .init(), results: [old],
      presets: [], at: start)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "exportedAtReferenceTime")
    var records = try XCTUnwrap(object["results"] as? [[String: Any]])
    records[0].removeValue(forKey: "startedAtReferenceTime")
    records[0].removeValue(forKey: "finishedAtReferenceTime")
    object["results"] = records
    for version in 1...12 {
      object["version"] = version
      let archive = try TypebarDataTransfer.importArchive(from: data(object))
      XCTAssertEqual(archive.exportedAt.timeIntervalSinceReferenceDate, 800_000_000)
      let restored = try XCTUnwrap(archive.results.first)
      XCTAssertTrue(restored.replayEvents.allSatisfy { $0.inputField == nil })
      XCTAssertTrue(restored.replayEvents.allSatisfy { $0.inputCorrectness == nil })
      XCTAssertTrue(restored.replayEvents.allSatisfy { $0.inputPosition == nil })
      XCTAssertNil(restored.characterStats.sourceUnits)
      XCTAssertEqual(restored.wpm, 17)
      XCTAssertEqual(restored.rawWpm, 29)
      XCTAssertEqual(restored.accuracy, 77)
      XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: restored.replayEvents), ["ab"])
      XCTAssertEqual(restored.startedAt.timeIntervalSinceReferenceDate, 800_000_000)
      XCTAssertEqual(restored.finishedAt.timeIntervalSinceReferenceDate, 800_000_002)
      XCTAssertEqual(restored.elapsedDuration, 2, "缺失的旧精度不能从回放推算补回")
    }
  }

  func testLegacyDateFieldProjectionStillReadsTheNewArchive() throws {
    struct LegacyResult: Decodable { let startedAt: Date; let finishedAt: Date }
    struct LegacyArchive: Decodable { let exportedAt: Date; let results: [LegacyResult] }
    let encoded = try data(archiveObject())
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let legacy = try decoder.decode(LegacyArchive.self, from: encoded)
    XCTAssertEqual(legacy.exportedAt.timeIntervalSinceReferenceDate, 800_000_000)
    XCTAssertEqual(legacy.results.first?.startedAt.timeIntervalSinceReferenceDate, 800_000_000)
    XCTAssertEqual(legacy.results.first?.finishedAt.timeIntervalSinceReferenceDate, 800_000_002)
  }

  func testMismatchedAndMalformedPrecisionIsRejectedAtEveryDateOwner() throws {
    let original = try archiveObject()
    for key in ["exportedAtReferenceTime", "startedAtReferenceTime", "finishedAtReferenceTime"] {
      for invalid: Any in ["not a time", true, [1, 2], 1.0e308, 1_778_307_200.0] {
        var object = original
        if key == "exportedAtReferenceTime" {
          object[key] = invalid
        } else {
          var records = try XCTUnwrap(object["results"] as? [[String: Any]])
          records[0][key] = invalid
          object["results"] = records
        }
        XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: data(object)), key)
      }
    }
  }

  func testNullPrecisionRemainsUnknownRatherThanInventingAFraction() throws {
    var object = try archiveObject()
    object["exportedAtReferenceTime"] = NSNull()
    var records = try XCTUnwrap(object["results"] as? [[String: Any]])
    records[0]["startedAtReferenceTime"] = NSNull()
    records[0]["finishedAtReferenceTime"] = NSNull()
    object["results"] = records
    let archive = try TypebarDataTransfer.importArchive(from: data(object))
    XCTAssertEqual(archive.exportedAt.timeIntervalSinceReferenceDate, 800_000_000)
    XCTAssertEqual(archive.results.first?.elapsedDuration, 2)
  }

  func testNonfiniteDateCannotBeWrittenAsAValidArchive() {
    for interval in [Double.nan, .infinity, -.infinity] {
      XCTAssertThrowsError(try TypebarDataTransfer.exportArchive(settings: .init(), results: [],
        presets: [], at: Date(timeIntervalSinceReferenceDate: interval)))
    }
  }

  func testPrecisionAtAWholeSecondDistanceIsNotASupplement() throws {
    for offset in [-1.0, 1.0] {
      var object = try archiveObject()
      object["exportedAtReferenceTime"] = 800_000_000 + offset
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: data(object)))
    }
  }

  func testArchiveMergeKeepsSubsecondExportOrdering() throws {
    func imported(at date: Date) throws -> TypebarArchive {
      try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
        settings: .init(), results: [], presets: [], at: date))
    }
    let older = try imported(at: start.addingTimeInterval(0.25))
    let newer = try imported(at: start.addingTimeInterval(0.5))
    XCTAssertLessThan(older.exportedAt, newer.exportedAt)
    XCTAssertEqual(TypebarArchiveConflictMerge.merge(local: older, remote: newer).exportedAt,
      start.addingTimeInterval(0.5))
  }

  func testExistingJSONDateStrategiesPreserveTheOriginalReferenceBits() throws {
    let strategies: [(JSONEncoder.DateEncodingStrategy, JSONDecoder.DateDecodingStrategy)] = [
      (.deferredToDate, .deferredToDate), (.iso8601, .iso8601),
      (.secondsSince1970, .secondsSince1970), (.millisecondsSince1970, .millisecondsSince1970),
    ]
    let original = try result()
    for (encoding, decoding) in strategies {
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = encoding
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = decoding
      XCTAssertTrue(try decoder.decode(CompletedTestResult.self,
        from: encoder.encode(original)) == original)
    }
  }
}
