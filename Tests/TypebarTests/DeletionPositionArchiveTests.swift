import XCTest
import SwiftData
@testable import Typebar

final class DeletionPositionArchiveTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 909_600_000)
  private func owned(_ events: [TypingReplayEvent], stats: ResultCharacterStats? = nil) -> CompletedTestResult {
    .init(id: UUID(), configuration: .words(2), outcome: .bailedOut,
      startedAt: start, finishedAt: start.addingTimeInterval(2), typedCharacterCount: 1,
      correctCharacterCount: 1, errorCount: 0, wpm: 17, rawWpm: 29, accuracy: 77,
      characterStats: stats, prompt: "ab tail", replayEvents: events)
  }
  private func current() throws -> CompletedTestResult {
    var input = TypingSession(configuration: .words(2), prompt: "abcd tail")
    input.insertBatch("abc", at: start); input.deleteWordBackward(at: start.addingTimeInterval(1))
    input.bailOut(at: start.addingTimeInterval(2)); return try XCTUnwrap(input.result())
  }
  private func encode(_ archive: TypebarArchive) throws -> Data {
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(archive)
  }

  func testFormalAndPortableBoundariesPreserveGroupedPositionWithoutRescoring() throws {
    let saved = try current()
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [saved], presets: [], at: start))
    XCTAssertEqual(archive.version, 20)
    for restored in [archive.results[0], try XCTUnwrap(TestResultRecord(result: saved).portableResult)] {
      XCTAssertEqual(restored, saved)
      XCTAssertEqual(restored.replayEvents.compactMap(\.deletionCharIndex), [3])
      XCTAssertEqual(TypingReplay.actions(events: restored.replayEvents).last?.primitives.last?.deletionCharIndex, 3)
      XCTAssertEqual(TypingReplay.typedText(events: restored.replayEvents, through: 2), "")
    }
  }

  @MainActor func testInMemoryEntityKeepsPositionInTheExistingReplayPayload() throws {
    let saved = try current()
    let container = try ModelContainer(for: TestResultRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    container.mainContext.insert(TestResultRecord(result: saved)); try container.mainContext.save()
    let fetched = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).first)
    XCTAssertEqual(fetched.portableResult, saved)
    XCTAssertEqual(fetched.replayEvents.compactMap(\.deletionCharIndex), [3])
  }

  func testDeletionOnlyMetadataRequiresTwentyAndCannotMasqueradeAsAnyOldVersion() throws {
    let saved = owned([.init(offset: 0, kind: .insert, text: "ab"),
      .init(offset: 1, kind: .delete, text: "", inputField: .init(index: 0, value: "a"), deletionCharIndex: 2)])
    XCTAssertNil(saved.characterStats.sourceUnits)
    let data = try TypebarDataTransfer.exportArchive(settings: .init(), results: [saved], presets: [], at: start)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    for version in 1...19 {
      XCTAssertEqual(TypebarArchive(version: version, exportedAt: start, settings: .init(), results: [saved], presets: []).version, 20)
      object["version"] = version
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: object))) {
        XCTAssertEqual($0 as? DataTransferError, .unsupportedVersion(version))
      }
    }
  }

  func testGenuineOneThroughNineteenDoNotBackfillPositionsOrRescore() throws {
    let saved = owned([.init(offset: 0, kind: .insert, text: "ab"), .init(offset: 1, kind: .delete, text: "")])
    for version in 1...19 {
      let archive = TypebarArchive(version: version, exportedAt: start, settings: .init(), results: [saved], presets: [])
      XCTAssertEqual(archive.version, version)
      let restored = try TypebarDataTransfer.importArchive(from: encode(archive)).results[0]
      XCTAssertEqual(restored, saved)
      XCTAssertTrue(restored.replayEvents.allSatisfy { $0.deletionCharIndex == nil })
      XCTAssertEqual(restored.wpm, 17); XCTAssertEqual(restored.rawWpm, 29); XCTAssertEqual(restored.accuracy, 77)
      XCTAssertEqual(TypingReplay.typedText(events: restored.replayEvents, through: 2), "a")
    }
  }

  func testOwnedNineteenClassifiedDeletionRemainsNineteenWithoutPositionInference() throws {
    let saved = owned([.init(offset: 0, kind: .insert, units: [97,98], inputField: .init(index: 0, units: [97,98])),
      .init(offset: 1, kind: .delete, units: [], inputField: .init(index: 0, units: [97]))],
      stats: .init(matched: 1, incorrect: 0, extra: 0, missed: 0,
        sourceUnits: .classify(input: [97], target: [97,98], creditsPartial: true)))
    let archive = TypebarArchive(version: 1, exportedAt: start, settings: .init(), results: [saved], presets: [])
    XCTAssertEqual(archive.version, 19)
    let restored = try TypebarDataTransfer.importArchive(from: encode(archive)).results[0]
    XCTAssertEqual(restored, saved)
    XCTAssertNil(restored.replayEvents.last?.deletionCharIndex)
    XCTAssertEqual(restored.characterStats.sourceUnits?.correctWord, 1)
  }

  func testMalformedPositionsAreRejectedAndLargeDiagnosticScalarNeverDrivesReplay() throws {
    let invalid: [TypingReplayEvent] = [
      .init(offset: 0, kind: .delete, text: "", inputField: .init(index: 0, value: ""), deletionCharIndex: -1),
      .init(offset: 0, kind: .insert, text: "a", inputField: .init(index: 0, value: "a"), deletionCharIndex: 0),
      .init(offset: 0, kind: .delete, text: "", deletionCharIndex: 0),
      .init(offset: 0, kind: .delete, text: "a", inputField: .init(index: 0, value: ""), deletionCharIndex: 1),
      .init(offset: 0, kind: .delete, text: "", inputField: .init(index: -1, value: ""), deletionCharIndex: 0)]
    for event in invalid {
      XCTAssertNil(event.validatedDeletionCharIndex)
      XCTAssertThrowsError(try JSONDecoder().decode(TypingReplayEvent.self, from: JSONEncoder().encode(event)))
    }
    let base: [String: Any] = ["offset": 0, "kind": "delete", "text": "", "inputField": ["index": 0, "value": ""]]
    for position: Any in [true, "0", 0.5] {
      var object = base; object["deletionCharIndex"] = position
      XCTAssertThrowsError(try JSONDecoder().decode(TypingReplayEvent.self, from: JSONSerialization.data(withJSONObject: object)))
    }
    let large = TypingReplayEvent(offset: 1, kind: .delete, text: "", inputField: .init(index: 0, value: "a"), deletionCharIndex: Int.max)
    let restored = try JSONDecoder().decode(TypingReplayEvent.self, from: JSONEncoder().encode(large))
    XCTAssertEqual(restored.validatedDeletionCharIndex, Int.max)
    XCTAssertEqual(TypingReplay.typedText(events: [.init(offset: 0, kind: .insert, text: "ab"), restored], through: 1), "a")
  }
}
