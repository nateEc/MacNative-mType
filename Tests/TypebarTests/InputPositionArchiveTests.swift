import XCTest
import SwiftData
@testable import Typebar

final class InputPositionArchiveTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 909_100_000)

  private func currentResult() throws -> CompletedTestResult {
    var session = TestSessionFactory.make(configuration: .init(mode: .custom, duration: nil,
      wordLimit: nil, difficulty: .normal, rules: .init(stopOnErrorMode: .letter), modifiers: [.noSpaces]),
      customText: "🙂x tail")
    session.insertBatch("🙃", at: start)
    session.deleteBackward(at: start.addingTimeInterval(1))
    session.bailOut(at: start.addingTimeInterval(2))
    return try XCTUnwrap(session.result())
  }

  private func encode(_ archive: TypebarArchive) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(archive)
  }

  func testPortableAndFormalArchiveKeepPositionsSnapshotsAndFixedScores() throws {
    let result = try currentResult()
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [], at: start))
    XCTAssertEqual(archive.version, TypebarArchive.currentVersion)
    for restored in [archive.results[0], try XCTUnwrap(TestResultRecord(result: result).portableResult)] {
      XCTAssertEqual(restored, result)
      XCTAssertEqual(restored.replayEvents.map { $0.inputPosition?.charIndex }, [0,1,nil])
      XCTAssertEqual(restored.replayEvents.map { $0.inputPosition?.lastWord }, [false,false,nil])
      XCTAssertEqual(restored.replayEvents.map { $0.inputField?.valueUTF16 }, [[55357],[55357],[]])
      XCTAssertEqual(restored.inputMetrics, result.inputMetrics)
    }
  }

  @MainActor func testInMemorySwiftDataSaveFetchPreservesPositionsInTheExistingPayload() throws {
    let result = try currentResult()
    let container = try ModelContainer(for: TestResultRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    container.mainContext.insert(TestResultRecord(result: result))
    try container.mainContext.save()
    let fetched = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).first)
    XCTAssertEqual(fetched.portableResult, result)
    XCTAssertEqual(fetched.replayEvents.map { $0.inputPosition?.charIndex }, [0,1,nil])
  }

  func testNewPositionsCannotBeConstructedOrImportedUnderAnyEarlierArchiveVersion() throws {
    let result = try currentResult()
    let data = try TypebarDataTransfer.exportArchive(settings: .init(), results: [result], presets: [], at: start)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    for version in 1...15 {
      XCTAssertEqual(TypebarArchive(version: version, exportedAt: start, settings: .init(),
        results: [result], presets: []).version, 16)
      object["version"] = version
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: object))) {
        XCTAssertEqual($0 as? DataTransferError, .unsupportedVersion(version))
      }
    }
  }

  func testGenuineLegacyOneThroughFifteenDoNotInventPositionsOrRescore() throws {
    let old = CompletedTestResult(id: UUID(), configuration: .words(1), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(2), typedCharacterCount: 1,
      correctCharacterCount: 1, errorCount: 0, wpm: 17, rawWpm: 29, accuracy: 77,
      prompt: "🙂", replayEvents: [.init(offset: 0, kind: .insert, text: "🙂")])
    for version in 1...15 {
      let archive = TypebarArchive(version: version, exportedAt: start, settings: .init(), results: [old], presets: [])
      XCTAssertEqual(archive.version, version)
      let restored = try TypebarDataTransfer.importArchive(from: encode(archive)).results[0]
      XCTAssertEqual(restored, old)
      XCTAssertNil(restored.replayEvents[0].inputPosition)
      XCTAssertEqual(TypingReplay.typedText(events: restored.replayEvents, through: 2), "🙂")
      XCTAssertEqual(TestResultRecord(result: restored).portableResult, old)
    }
  }

  func testGenuineFifteenWithRawFieldsAndDirectoryRemainsFifteen() throws {
    // Owned version-15 fixture, not a current session stripped and relabeled.
    let events: [TypingReplayEvent] = [.init(offset: 0, kind: .insert, units: [97],
      inputField: .init(index: 0, units: [97]), inputCorrectness: [true])]
    let old = CompletedTestResult(id: UUID(), configuration: .words(2).with(modifiers: [.noSpaces]),
      outcome: .bailedOut, startedAt: start, finishedAt: start.addingTimeInterval(2),
      typedCharacterCount: 1, correctCharacterCount: 1, errorCount: 0, wpm: 17, rawWpm: 29,
      accuracy: 77, prompt: "ab", replayEvents: events,
      targetWordDirectory: .init(words: ["a","b"], noSpace: true))
    let archive = TypebarArchive(version: 15, exportedAt: start, settings: .init(), results: [old], presets: [])
    XCTAssertEqual(archive.version, 15)
    let restored = try TypebarDataTransfer.importArchive(from: encode(archive)).results[0]
    XCTAssertEqual(restored, old)
    XCTAssertNil(restored.replayEvents[0].inputPosition)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encode(archive)) as? [String: Any])
    for version in 1...14 {
      object["version"] = version
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: object)))
    }
  }

  func testDirectInvalidPositionIsNeverValidatedOrSilentlyImported() throws {
    for event in [TypingReplayEvent(offset: 0, kind: .insert, text: "a",
      inputField: .init(index: 0, value: "a"), inputPosition: .init(charIndex: -1, lastWord: true)),
      .init(offset: 0, kind: .delete, text: "", inputField: .init(index: 0, value: ""),
        inputPosition: .init(charIndex: 0, lastWord: true)),
      .init(offset: 0, kind: .insert, text: "", inputField: .init(index: 0, value: ""),
        inputPosition: .init(charIndex: 0, lastWord: true))] {
      XCTAssertNil(event.validatedInputPosition)
      XCTAssertThrowsError(try JSONDecoder().decode(TypingReplayEvent.self, from: JSONEncoder().encode(event)))
    }
  }

  func testPositionCannotBeReconstructedFromAShorterStoppedSnapshot() throws {
    let event = TypingReplayEvent(offset: 0, kind: .insert, units: [120], inputStopped: true,
      inputField: .init(index: 0, units: []), inputCorrectness: [false],
      inputPosition: .init(charIndex: 2, lastWord: true))
    let restored = try JSONDecoder().decode(TypingReplayEvent.self, from: JSONEncoder().encode(event))
    XCTAssertEqual(restored.validatedInputPosition?.charIndex, 2)
    XCTAssertEqual(restored.inputField?.units, [])
    XCTAssertEqual(TypingReplay.typedUTF16(events: [restored], through: 0), [])
  }
}
