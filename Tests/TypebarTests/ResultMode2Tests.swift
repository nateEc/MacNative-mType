import XCTest
import SwiftData
@testable import Typebar

final class ResultMode2Tests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_800_000_000)
  private func source(_ id: String? = "owned-a") throws -> ResultQuoteSource {
    try XCTUnwrap(ResultQuoteSource.make(mode: .quote, sourceIsCommunity: false,
      title: "Same title", selectedQuoteID: id))
  }
  private func result(_ source: ResultQuoteSource?) -> CompletedTestResult {
    .init(id: UUID(), configuration: .init(mode: .quote, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init()), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(15),
      typedCharacterCount: 75, correctCharacterCount: 75, errorCount: 0,
      wpm: 60, rawWpm: 60, accuracy: 100, quoteSource: source, prompt: "private own quote")
  }
  private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
  }
  func testCapturedIdentityDoesNotFollowLaterSelectionOrTitle() throws {
    let first = try source(), second = try source("owned-b")
    let captured = result(first)
    XCTAssertEqual(first.title, second.title)
    XCTAssertNotEqual(first.mode2, second.mode2)
    XCTAssertEqual(captured.quoteSource?.mode2, "typebar:owned-a")
    XCTAssertEqual(try JSONDecoder().decode(CompletedTestResult.self,
      from: JSONEncoder().encode(captured)), captured)
  }
  func testCommunityIdentityHasSeparateCanonicalNamespace() throws {
    let id = UUID()
    let community = try XCTUnwrap(ResultQuoteSource.make(mode: .quote, sourceIsCommunity: true,
      title: "Same title", selectedQuoteID: "community-" + id.uuidString))
    XCTAssertEqual(community.mode2, "community:" + id.uuidString.lowercased())
    let own = try XCTUnwrap(ResultQuoteSource(kind: .typebar, title: "Same title", quoteID: id.uuidString))
    XCTAssertNotEqual(community.mode2, own.mode2)
  }
  func testUTF8KeysAreReversibleCanonicalAndDoNotCollideWithASCIINames() throws {
    let raw = "自有-ü"
    let source = try XCTUnwrap(ResultQuoteSource(kind: .typebar, title: "Own", quoteID: raw))
    let key = try XCTUnwrap(source.mode2)
    XCTAssertEqual(key, "typebar:utf8:e887aae69c892dc3bc")
    XCTAssertNil(ResultQuoteSource(kind: .typebar, title: "Own", quoteID: "utf8:e887aae69c892dc3bc"),
      "Wire encoding is not an admissible raw ID and cannot impersonate the Unicode ID")
    XCTAssertTrue(ResultMode2Policy.isValid(key, mode: "quote"))
    XCTAssertFalse(ResultMode2Policy.isValid("typebar:utf8:6f776e", mode: "quote"), "ASCII must use its one canonical spelling")
    XCTAssertFalse(ResultMode2Policy.isValid("typebar:utf8:ff", mode: "quote"))
    XCTAssertFalse(ResultMode2Policy.isValid("typebar:utf8:e887a", mode: "quote"))
    let ascii = try XCTUnwrap(ResultQuoteSource(kind: .typebar, title: "Own", quoteID: "utf8-e887aae69c892dc3bc"))
    XCTAssertNotEqual(ascii.mode2, key)
    let composed = try XCTUnwrap(ResultQuoteSource(kind: .typebar, title: "Own", quoteID: "ü"))
    let decomposed = try XCTUnwrap(ResultQuoteSource(kind: .typebar, title: "Own", quoteID: "u\u{308}"))
    XCTAssertNotEqual(composed.mode2, decomposed.mode2, "Do not normalize the captured UTF-8 identity")
    let decoded = try JSONDecoder().decode(ResultQuoteSource.self, from: JSONEncoder().encode(source))
    XCTAssertEqual(Array(decoded.quoteID!.utf8), Array(raw.utf8))
  }
  func testOwnedQuoteIdentifiersFitTheBoundedWireDomain() throws {
    for language in TypingLanguage.allCases {
      for length in QuoteLength.allCases {
        for quote in OfflineContent.quotes(for: language, length: length) {
          XCTAssertNotNil(ResultQuoteSource.make(mode: .quote, sourceIsCommunity: false,
            title: quote.title, selectedQuoteID: quote.id), "\(language)/\(quote.id)")
        }
      }
    }
  }
  func testMissingOldIdentityStaysUnknownAndExplicitBadIdentityIsRejected() throws {
    XCTAssertNil(try source(nil).mode2)
    let legacy = result(try source(nil))
    XCTAssertNil(try JSONDecoder().decode(CompletedTestResult.self,
      from: JSONEncoder().encode(legacy)).quoteSource?.quoteID)
    for id: Any in [NSNull(), 7, "", "bad/id", "bad:separator", String(repeating: "a", count: 101)] {
      var json = try object(legacy)
      json["quoteSource"] = ["kind": "typebar", "title": "Same title", "quoteID": id]
      XCTAssertThrowsError(try JSONDecoder().decode(CompletedTestResult.self,
        from: JSONSerialization.data(withJSONObject: json)))
    }
  }
  @MainActor func testOpaqueSwiftDataAndArchiveKeepIdentityWithoutAddingAColumn() throws {
    let value = result(try source())
    let container = try ModelContainer(for: TestResultRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let record = TestResultRecord(result: value)
    container.mainContext.insert(record); try container.mainContext.save()
    XCTAssertEqual(record.portableResult?.quoteSource, value.quoteSource)
    let archive = TypebarArchive(version: 1, exportedAt: start, settings: .init(),
      results: [value], presets: [])
    XCTAssertEqual(archive.version, 27)
    let bytes = try TypebarDataTransfer.exportArchive(settings: .init(), results: [value], presets: [], at: start)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from: bytes).results.first, value)
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    for version in [1, 26] {
      json["version"] = version; json["deletedResultIDs"] = [value.id.uuidString]
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: json)))
    }
  }
  @MainActor func testDamagedOpaqueIdentityKeepsBytesAndCannotBecomePortableLegacy() throws {
    let container = try ModelContainer(for: TestResultRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let record = TestResultRecord(result: result(try source()))
    let bytes = Data(#"{"kind":"typebar","title":"Same title","quoteID":null}"#.utf8)
    record.quoteSourceData = bytes
    container.mainContext.insert(record); try container.mainContext.save()
    XCTAssertNil(record.portableResult)
    record.addTag("unrelated"); try container.mainContext.save()
    XCTAssertEqual(record.quoteSourceData, bytes)
    XCTAssertNil(record.portableResult)
  }
  @MainActor func testExactCapabilityIsRequiredBeforePublicationWork() async throws {
    let value = result(try source())
    for capability in [nil, RemoteServiceCapabilities(apiVersion: "v2", service: "typebar", capabilities: ["resultMode2": "available"]),
      .init(apiVersion: "v1", service: "other", capabilities: ["resultMode2": "available"]),
      .init(apiVersion: "v1", service: "typebar", capabilities: ["resultMode2": "planned"])] {
      do {
        _ = try await ResultConsistencyPublication.prepare(result: value, capabilities: capability) { _ in
          XCTFail("Unsupported identity must fail before metric work"); return 1
        }
        XCTFail("Known identity must not silently disappear")
      } catch { XCTAssertTrue(error is RemoteAccountError) }
    }
    let wire = try await ResultConsistencyPublication.prepare(result: value,
      capabilities: .init(apiVersion: "v1", service: "typebar", capabilities: ["resultMode2": "available"]))
    let json = try object(wire)
    XCTAssertEqual(json["mode2"] as? String, "typebar:owned-a")
    for key in ["quoteSource", "title", "prompt", "replayEvents", "quoteText"] { XCTAssertNil(json[key]) }
    let old = try await ResultConsistencyPublication.prepare(result: result(try source(nil)), capabilities: nil)
    XCTAssertNil(try object(old)["mode2"], "No fabricated title hash or random ID for old results")
  }
  @MainActor func testCapabilityTransportFailureRemainsRetryableAndCancellationPropagates() async throws {
    do {
      _ = try await RemoteResultBailoutPolicy.capabilities(for: .completed, requiresMode2: true) {
        throw URLError(.notConnectedToInternet)
      }
      XCTFail("Transport failure is not unsupported capability")
    } catch { XCTAssertTrue(ResultPublicationRetryPolicy.shouldQueue(error)) }
    do {
      _ = try await RemoteResultBailoutPolicy.capabilities(for: .completed, requiresMode2: true) { throw CancellationError() }
      XCTFail("Cancelled identity publication must stop")
    } catch { XCTAssertTrue(error is CancellationError) }
  }
  func testSelectionAndPageContractsDoNotMergeDifferentQuotesOrClaimOldCapability() throws {
    XCTAssertNotEqual(RemoteLeaderboardSelection(mode: .quote, language: .english, period: .day, mode2: "typebar:a"),
      .init(mode: .quote, language: .english, period: .day, mode2: "typebar:b"))
    let old = try JSONDecoder().decode(RemoteLeaderboardPage.self, from: Data(#"{"entries":[]}"#.utf8))
    XCTAssertNil(old.mode2FilterSupported)
    XCTAssertNoThrow(try RemoteLeaderboardPartitionPolicy.validate(old, mode2: nil))
    XCTAssertThrowsError(try RemoteLeaderboardPartitionPolicy.validate(old, mode2: "typebar:a"))
    let confirmed = try JSONDecoder().decode(RemoteLeaderboardPage.self,
      from: Data(#"{"entries":[],"mode2FilterSupported":true}"#.utf8))
    XCTAssertNoThrow(try RemoteLeaderboardPartitionPolicy.validate(confirmed, mode2: "typebar:a"))
    let entry: [String: Any] = ["id": UUID().uuidString, "rank": 1, "userID": UUID().uuidString,
      "displayName": "Owned", "mode": "quote", "mode2": "typebar:b", "language": "english", "wpm": 60,
      "accuracy": 100, "finishedAt": 0]
    let mismatched = try JSONDecoder().decode(RemoteLeaderboardPage.self,
      from: JSONSerialization.data(withJSONObject: ["entries": [entry], "mode2FilterSupported": true]))
    XCTAssertThrowsError(try RemoteLeaderboardPartitionPolicy.validate(mismatched, mode2: "typebar:a"))
  }
}
