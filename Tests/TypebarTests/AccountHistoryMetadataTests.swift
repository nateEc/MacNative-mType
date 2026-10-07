import Foundation
import XCTest
@testable import Typebar

final class AccountHistoryMetadataTests: XCTestCase {
  private let scope = ResultPublicationScope(endpoint: "https://owned.invalid", userID: UUID())
  private func result(mode: TestMode = .quote, prompt: String = "A short original quotation.",
    actualLength: QuoteLength? = nil) -> CompletedTestResult {
    let start = Date(timeIntervalSinceReferenceDate: 900_000_000)
    var config = TestConfiguration(mode: mode, duration: mode == .time ? 15 : nil,
      wordLimit: mode == .words ? 25 : nil, difficulty: .normal, rules: .init())
    config.quoteLength = .all
    return .init(id: UUID(), configuration: config, outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(15), typedCharacterCount: 75,
      correctCharacterCount: 75, errorCount: 0, wpm: 60, rawWpm: 60, accuracy: 100,
      quoteSource: actualLength.flatMap { .init(kind: .community, title: "Owned quote", actualLength: $0) },
      prompt: prompt, replayEvents: [])
  }
  private func json<T: Encodable>(_ value: T) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
  }
  private func row(pb: Bool?, length: String? = nil, mode: TestMode = .quote) throws -> RemoteAccountResult {
    var object = try json(RemoteResultSubmission(result: result(mode: mode)))
    object["historicalPersonalBest"] = pb
    object["quoteLength"] = length
    return try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: object))
  }

  func testKnownHistoricalFlagsAreNotRecomputedFromCurrentCrownsAndUnknownIsNotFalse() throws {
    let yes = try row(pb: true), no = try row(pb: false), unknown = try row(pb: nil)
    let rows = [yes, no, unknown]
    for (selection, expected) in [(ResultHistoryPersonalBestFilter.all, rows), (.only, [yes]),
      (.excluded, [no]), (.noMatches, [])] {
      XCTAssertEqual(AccountHistoryQuery.matching(rows, scope: scope,
        filter: .init(personalBestFilter: selection)).map(\.id), expected.map(\.id))
    }
    XCTAssertEqual(try json(yes)["historicalPersonalBest"] as? Bool, true)
    XCTAssertEqual(try json(no)["historicalPersonalBest"] as? Bool, false)
    XCTAssertNil(try json(unknown)["historicalPersonalBest"])
  }

  func testQuoteLengthFiltersActualClassificationAndUnknownOnlyWhenRestricted() throws {
    let short = try row(pb: nil, length: "short"), long = try row(pb: nil, length: "long")
    let unknown = try row(pb: nil), time = try row(pb: nil, mode: .time)
    let rows = [short, long, unknown, time]
    XCTAssertEqual(AccountHistoryQuery.matching(rows, scope: scope, filter: .init()).count, 4)
    XCTAssertEqual(AccountHistoryQuery.matching(rows, scope: scope,
      filter: .init(quoteLengths: [.short])).map(\.id), [short.id, time.id])
    XCTAssertEqual(AccountHistoryQuery.matching(rows, scope: scope,
      filter: .init(quoteLength: .long)).map(\.id), [long.id])
    XCTAssertEqual(try json(short)["quoteLength"] as? String, "short")
  }

  @MainActor func testNegotiatedPublicationUsesSelectedQuoteSnapshotNotPartialPromptAndSurvivesRestore() async throws {
    let caps = RemoteServiceCapabilities(apiVersion: "v1", service: "typebar",
      capabilities: ["resultHistoryMetadata": "available"])
    let saved = result(prompt: "partial", actualLength: .long)
    let archive = TypebarArchive(version: 1, exportedAt: saved.finishedAt, settings: .init(), results: [saved], presets: [])
    XCTAssertEqual(archive.version, 32)
    for input in [saved, try XCTUnwrap(TestResultRecord(result: saved).portableResult),
      try XCTUnwrap(TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
        settings: .init(), results: [saved], presets: [], at: saved.finishedAt)).results.first)] {
      let wire = try await ResultConsistencyPublication.prepare(result: input, capabilities: caps)
      let object = try json(wire)
      XCTAssertEqual(object["quoteLength"] as? String, "long")
      XCTAssertNil(object["historicalPersonalBest"], "PB is owned exclusively by the service")
      XCTAssertNil(object["prompt"]); XCTAssertNil(object["replayEvents"])
    }
    let legacy = try await ResultConsistencyPublication.prepare(result: result(prompt: String(repeating: "x", count: 500)), capabilities: caps)
    XCTAssertNil(try json(legacy)["quoteLength"], "Even a complete-looking old prompt cannot prove its selected catalogue group")
    for mode in [TestMode.time, .words, .custom, .zen] {
      let wire = try await ResultConsistencyPublication.prepare(result: result(mode: mode), capabilities: caps)
      XCTAssertNil(try json(wire)["quoteLength"])
    }
  }

  @MainActor func testOnlyExactCapabilityPublishesCapturedLengthAndLegacyServicesStayUsable() async throws {
    for caps in [nil, RemoteServiceCapabilities(apiVersion: "v2", service: "typebar", capabilities: ["resultHistoryMetadata": "available"]),
      .init(apiVersion: "v1", service: "other", capabilities: ["resultHistoryMetadata": "available"]),
      .init(apiVersion: "v1", service: "typebar", capabilities: ["resultHistoryMetadata": "partial"]),
      .init(apiVersion: "v1", service: "typebar", capabilities: ["resultHistoryMetadata": "planned"])] {
      let wire = try await ResultConsistencyPublication.prepare(result: result(actualLength: .extended), capabilities: caps)
      XCTAssertNil(try json(wire)["quoteLength"])
    }
  }

  func testQuoteSnapshotRejectsAllNullAndForeignModeWithoutSilentLoss() throws {
    XCTAssertNil(ResultQuoteSource(kind: .typebar, title: "Owned", actualLength: .all))
    for bad: Any in [NSNull(), "all", 1, "unknown"] {
      var object = try json(result(actualLength: .short))
      var source = try XCTUnwrap(object["quoteSource"] as? [String: Any]); source["actualLength"] = bad
      object["quoteSource"] = source
      XCTAssertThrowsError(try JSONDecoder().decode(CompletedTestResult.self, from: JSONSerialization.data(withJSONObject: object)))
    }
    var time = try json(result(mode: .time))
    time["quoteSource"] = ["kind": "typebar", "title": "Owned", "actualLength": "short"]
    XCTAssertThrowsError(try JSONDecoder().decode(CompletedTestResult.self, from: JSONSerialization.data(withJSONObject: time)))
  }

  func testArchiveCannotDowngradeQuoteClassificationEvenBehindTombstone() throws {
    let saved = result(actualLength: .extended)
    let archive = TypebarArchive(exportedAt: saved.finishedAt, settings: .init(), results: [saved], presets: [])
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(archive)) as? [String: Any])
    for version in [1, 27, 31] {
      object["version"] = version; object["deletedResultIDs"] = [saved.id.uuidString]
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: object)))
    }
    let legacy = TypebarArchive(version: 27, exportedAt: saved.finishedAt, settings: .init(), results: [result()], presets: [])
    XCTAssertEqual(legacy.version, 27)
  }

  func testCSVAppendsMetadataPreservingFalseAndUnknownWithoutPrompt() throws {
    let rows = try [row(pb: true, length: "short"), row(pb: false, length: "long"), row(pb: nil)]
    let lines = RemoteResultCSVExport.csvString(for: rows).components(separatedBy: "\r\n")
    XCTAssertEqual(Array(RemoteResultCSVExport.columns[30..<32]), ["historical_personal_best", "quote_length"])
    XCTAssertEqual(Array(lines[1].components(separatedBy: ",")[30..<32]), ["true", "short"])
    XCTAssertEqual(Array(lines[2].components(separatedBy: ",")[30..<32]), ["false", "long"])
    XCTAssertEqual(Array(lines[3].components(separatedBy: ",")[30..<32]), ["", ""])
  }

  @MainActor func testPortableQuoteContextCannotBeSilentlyDiscarded() throws {
    let record = TestResultRecord(result: result(mode: .time))
    let bytes = try JSONEncoder().encode(XCTUnwrap(ResultQuoteSource(kind: .community, title: "Owned", actualLength: .short)))
    record.quoteSourceData = bytes
    XCTAssertNil(record.portableResult, "A valid classification in a foreign mode is corrupt, not legacy unknown")
    record.addTag("owned")
    XCTAssertEqual(record.quoteSourceData, bytes)
  }

  func testMalformedPresentMetadataIsRejectedInsteadOfBecomingLegacyUnknown() throws {
    let base = try json(RemoteResultSubmission(result: result()))
    for value: Any in [NSNull(), "all", "unsupported", 0, true] {
      var object = base; object["quoteLength"] = value
      XCTAssertThrowsError(try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: object)))
    }
    for value: Any in [NSNull(), "false", 1, []] {
      var object = base; object["historicalPersonalBest"] = value
      XCTAssertThrowsError(try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: object)))
    }
    var time = try json(RemoteResultSubmission(result: result(mode: .time))); time["quoteLength"] = "short"
    XCTAssertThrowsError(try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: time)))
  }
}
