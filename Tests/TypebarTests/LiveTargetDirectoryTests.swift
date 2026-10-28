import SwiftData
import XCTest
@testable import Typebar

@MainActor final class LiveTargetDirectoryTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 918_200_000)

  private func grownResult() async throws -> CompletedTestResult {
    func raw(_ limit: Double) throws -> WebsiteCustomTextSettings {
      try .init(value: .object([
        "text": .array([.string("aa bb cc dd ee ff gg hh ii"), .string("jj")]), "mode": .string("repeat"),
        "limit": .object(["mode": .string("word"), "value": .number(limit)]), "pipeDelimiter": .bool(false)]))
    }
    let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"custom","funbox":["no_quit"]}"#,
      pointsPerRem: 16, context: .init())
    var session = try await WebsiteConfigSessionBuilder.prepare(draft: draft, scope: .init(websiteCustomText: raw(2))).session
    session.insertBatch("a", at: start)
    XCTAssertTrue(try session.synchronizeWebsiteCustomText(raw(7.5)))
    for _ in 0..<100 where !session.isFinished {
      session.insertBatch(session.nextExpectedCharacter.map(String.init) ?? " ", at: start.addingTimeInterval(1))
    }
    XCTAssertEqual(session.outcome, .completed)
    return try XCTUnwrap(session.result())
  }

  func testLiveGrowthKeepsActualNoCommitTargetAcrossPortableAndArchiveRestore() async throws {
    let result = try await grownResult()
    let directory = try XCTUnwrap(result.targetWordDirectory)
    XCTAssertEqual(directory.words, ["aa ", "bb", "cc ", "dd ", "ee ", "ff ", "gg ", "hh"])
    XCTAssertTrue(directory.matches(prompt: result.prompt, noSpace: false))
    XCTAssertEqual(result.prompt, "aa bb cc dd ee ff gg hh")
    for restored in [try XCTUnwrap(TestResultRecord(result: result).portableResult),
      try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
        settings: .init(), results: [result], presets: [], at: start)).results[0]] {
      XCTAssertEqual(restored, result)
      XCTAssertEqual(restored.targetWordDirectory?.words, directory.words)
      XCTAssertEqual(ResultPromptText.make(for: restored, reviews: []), directory.words.joined())
      let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: restored.prompt, events: restored.replayEvents,
        configuration: restored.configuration, targetWordDirectory: restored.targetWordDirectory))
      XCTAssertEqual(plan.initialFrame.presentation.text, result.prompt)
      XCTAssertEqual(plan.initialFrame.fields[1].letters.map(\.text).joined(), "bb")
      XCTAssertEqual(plan.frame(through: restored.capturedDuration).presentation.text, result.prompt)
      let point = ResultPerformanceTrace.point(prompt: restored.prompt, events: restored.replayEvents,
        elapsed: restored.capturedDuration, configuration: restored.configuration, targetWordDirectory: restored.targetWordDirectory)
      XCTAssertEqual(point.wpm, restored.wpm); XCTAssertEqual(point.rawWpm, restored.rawWpm)
      XCTAssertTrue(WeakSpotPractice.characterScores(results: [restored], language: .english).isEmpty)
    }
  }

  func testDisplayGapValidationIsStrictAndDoesNotNormalizeOrInventTargets() throws {
    let directory = ResultTargetWordDirectory(words: ["aa ", "bb", "cc"], noSpace: false, displayGaps: [1])
    XCTAssertTrue(directory.matches(prompt: "aa bb cc", noSpace: false))
    XCTAssertFalse(directory.matches(prompt: "aa bbcc", noSpace: false))
    XCTAssertEqual(directory.words.joined(), "aa bbcc")
    for indices in [[Int](), [-1], [3], [1,1], [1,0], [0]] {
      let data = try JSONSerialization.data(withJSONObject: ["words": directory.words, "noSpace": false, "displayGaps": indices])
      XCTAssertThrowsError(try JSONDecoder().decode(ResultTargetWordDirectory.self, from: data))
    }
    for invalid in [ResultTargetWordDirectory(words: ["bb"], noSpace: true, displayGaps: [0]),
      .init(words: [], noSpace: true), .init(words: [""], noSpace: false, displayGaps: [0]),
      .init(words: ["bb\n"], noSpace: false, displayGaps: [0])] {
      XCTAssertThrowsError(try JSONEncoder().encode(invalid))
    }
    let unicode = ResultTargetWordDirectory(words: ["e\u{301}", "x"], noSpace: false, displayGaps: [0])
    XCTAssertTrue(unicode.matches(prompt: "e\u{301} x", noSpace: false))
    XCTAssertFalse(unicode.matches(prompt: "é x", noSpace: false))
    let legacy = ResultTargetWordDirectory(words: ["oak ", "elm"], noSpace: false)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
    XCTAssertNil(object["displayGaps"])
    XCTAssertEqual(try JSONDecoder().decode(ResultTargetWordDirectory.self, from: JSONEncoder().encode(legacy)), legacy)
  }

  func testArchiveVersionGatePrecedesTombstonesAndLegacyArchivesRemainReadable() async throws {
    let result = try await grownResult()
    let data = try TypebarDataTransfer.exportArchive(settings: .init(), results: [result], presets: [], at: start)
    var root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(root["version"] as? Int, 39)
    root["version"] = 38; root["deletedResultIDs"] = [result.id.uuidString]
    XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: root)))
    let promoted = TypebarArchive(version: 15, exportedAt: start, settings: .init(), results: [result],
      deletedResultIDs: [result.id], presets: [])
    XCTAssertEqual(promoted.version, 39); XCTAssertTrue(promoted.results.isEmpty)
    let old = try ordinaryResult()
    let legacy = TypebarArchive(version: 38, exportedAt: start, settings: .init(), results: [old], presets: [])
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    let restored = try TypebarDataTransfer.importArchive(from: encoder.encode(legacy))
    XCTAssertEqual(restored.version, 38); XCTAssertEqual(restored.results, [old])
  }

  private func ordinaryResult() throws -> CompletedTestResult {
    var session = TypingSession(configuration: .words(2), prompt: "oak elm")
    session.insertBatch("o", at: start); session.insertBatch("ak elm", at: start.addingTimeInterval(1))
    return try XCTUnwrap(session.result())
  }

  func testColdSwiftDataRestoreKeepsNewDirectoryAndNeverRewritesLegacyBlob() async throws {
    let result = try await grownResult(), old = try ordinaryResult()
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-live-directory-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    let location = folder.appendingPathComponent("history.store")
    let oldBytes: Data = try autoreleasepool {
      let container = try ModelContainer(for: TestResultRecord.self, configurations: ModelConfiguration(url: location, cloudKitDatabase: .none))
      let context = ModelContext(container); context.autosaveEnabled = false
      let prior = TestResultRecord(result: old)
      context.insert(prior); context.insert(TestResultRecord(result: result)); try context.save()
      return try XCTUnwrap(prior.targetWordDirectoryData)
    }
    try autoreleasepool {
      let container = try ModelContainer(for: TestResultRecord.self, configurations: ModelConfiguration(url: location, cloudKitDatabase: .none))
      let context = ModelContext(container); context.autosaveEnabled = false
      let records = try context.fetch(FetchDescriptor<TestResultRecord>())
      let prior = try XCTUnwrap(records.first { $0.id == old.id })
      let current = try XCTUnwrap(records.first { $0.id == result.id })
      XCTAssertEqual(prior.portableResult, old); XCTAssertEqual(current.portableResult, result)
      XCTAssertEqual(current.targetWordDirectory?.displayGaps, [1])
      XCTAssertEqual(prior.targetWordDirectoryData, oldBytes); XCTAssertFalse(context.hasChanges)
    }
  }

  func testCorruptOrMismatchedDirectoryBlocksPortableAndWorkerOutputWithoutChangingBlob() async throws {
    let result = try await grownResult(), record = TestResultRecord(result: try await grownResult())
    let directory = try XCTUnwrap(result.targetWordDirectory)
    for gaps in [[-1], [1,1], [0], [2], [7]] {
      let data = try JSONSerialization.data(withJSONObject: ["words": directory.words,
        "noSpace": false, "displayGaps": gaps])
      record.targetWordDirectoryData = data
      XCTAssertNil(record.portableResult)
      let worker = ResultWPMConsistencyInput(prompt: result.prompt, duration: result.capturedDuration,
        configurationData: record.configurationData, replayEventsData: record.replayEventsData,
        targetWordDirectoryData: data, sourceScoringBasis: result.characterStats.sourceUnitBasis)
      XCTAssertNil(worker.calculate()); XCTAssertEqual(record.targetWordDirectoryData, data)
    }
  }
}
