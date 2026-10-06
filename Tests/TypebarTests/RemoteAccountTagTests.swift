import Foundation
import XCTest
@testable import Typebar

final class RemoteAccountTagTests: XCTestCase {
  @MainActor func testSelectedTagCapabilityTransportFailureRemainsRetryable() async throws {
    for failure: Error in [URLError(.notConnectedToInternet),
      RemoteAccountError.serverResponse(statusCode: 503, message: "temporary")] {
      do {
        _ = try await RemoteResultBailoutPolicy.capabilities(for: .completed, requiresAccountTags: true) { throw failure }
        XCTFail("Selected stable IDs must not be silently downgraded")
      } catch { XCTAssertTrue(ResultPublicationRetryPolicy.shouldQueue(error)) }
    }
    do {
      _ = try await RemoteResultBailoutPolicy.capabilities(for: .completed, requiresAccountTags: true) { throw CancellationError() }
      XCTFail("Cancellation must propagate")
    } catch { XCTAssertTrue(error is CancellationError) }
    let missing = try await RemoteResultBailoutPolicy.capabilities(for: .completed, requiresAccountTags: true) {
      throw RemoteAccountError.serverResponse(statusCode: 404, message: "legacy")
    }
    XCTAssertThrowsError(try RemoteAccountTagPolicy.prepare(ids: [UUID()], capabilities: missing))
    let legacy = try await RemoteResultBailoutPolicy.capabilities(for: .completed) {
      throw RemoteAccountError.serverResponse(statusCode: 503, message: "legacy")
    }
    XCTAssertNil(try RemoteAccountTagPolicy.prepare(ids: [], capabilities: legacy))
  }
  func testDirectoryNamesMatchCanonicalASCIIAndUIWhitespaceNormalization() {
    XCTAssertEqual(RemoteAccountTagPolicy.normalizedName("  desk \t chair  "), "desk_chair")
    for name in ["a", "Desk-1", "desk_chair", String(repeating: "a", count: 16)] { XCTAssertTrue(RemoteAccountTagPolicy.isValidName(name)) }
    for name in ["", "_a", "a_", "a__b", "a-_b", "a.b", "é", "中文", String(repeating: "a", count: 17)] { XCTAssertFalse(RemoteAccountTagPolicy.isValidName(name)) }
  }
  func testSubmissionIdentityRequiresExactCapabilityAndDoesNotUseLocalText() throws {
    let ids = [UUID()]
    XCTAssertNil(try RemoteAccountTagPolicy.prepare(ids: [], capabilities: nil))
    let valid = RemoteServiceCapabilities(apiVersion: "v1", service: "typebar", capabilities: ["accountTags": "available"])
    XCTAssertEqual(try RemoteAccountTagPolicy.prepare(ids: ids, capabilities: valid), ids)
    for cap: RemoteServiceCapabilities? in [nil,
      .init(apiVersion: "v2", service: "typebar", capabilities: ["accountTags": "available"]),
      .init(apiVersion: "v1", service: "other", capabilities: ["accountTags": "available"]),
      .init(apiVersion: "v1", service: "typebar", capabilities: ["accountTags": "partial"])] {
      XCTAssertThrowsError(try RemoteAccountTagPolicy.prepare(ids: ids, capabilities: cap))
    }
    XCTAssertThrowsError(try RemoteAccountTagPolicy.prepare(ids: [ids[0], ids[0]], capabilities: valid))
  }
  func testPostingSelectionsSurviveReloadAndArePartitionedByAccountAndEndpoint() throws {
    let suite = "TypebarTests.tag-selection.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let first = ResultPublicationScope(endpoint: "https://owned.example", userID: UUID())
    let other = ResultPublicationScope(endpoint: "https://owned.example", userID: UUID())
    let server = ResultPublicationScope(endpoint: "https://other.example", userID: first.userID)
    let ids = [UUID(), UUID()], store = RemoteAccountTagSelectionStore(defaults: defaults)
    try store.set(ids, for: first)
    let reopened = RemoteAccountTagSelectionStore(defaults: defaults)
    XCTAssertEqual(try reopened.ids(for: first), ids)
    XCTAssertEqual(try reopened.ids(for: other), []); XCTAssertEqual(try reopened.ids(for: server), [])
    XCTAssertThrowsError(try store.set(Array(repeating: ids[0], count: 16), for: first))
    XCTAssertEqual(try reopened.ids(for: first), ids)
  }
  private func decodeList(_ root: [String: Any]) throws -> RemoteAccountTagList {
    try JSONDecoder().decode(RemoteAccountTagList.self, from: JSONSerialization.data(withJSONObject: root))
  }
  private func tag(_ id: UUID = UUID(), name: String = "desk") -> [String: Any] {
    ["id": id.uuidString, "name": name, "personalBestLedgerVersion": 1, "personalBests": []]
  }
  func testSameNamesHaveDistinctIDsAndKnownEmptyIsRetained() throws {
    let first = UUID(), second = UUID()
    let parsed = try decodeList(["version": 1, "tags": [tag(first), tag(second)]])
    XCTAssertEqual(parsed.tags.map(\.id), [first, second]); XCTAssertEqual(parsed.tags.map(\.name), ["desk", "desk"])
    XCTAssertTrue(parsed.tags.allSatisfy { $0.personalBests.isEmpty })
  }
  func testMalformedDirectoryCannotBecomeEmptyFallback() throws {
    let id = UUID()
    for root: [String: Any] in [["version": 2, "tags": []], ["version": 1, "tags": NSNull()],
      ["version": 1, "tags": [tag(id), tag(id)]], ["version": 1, "tags": [tag(name: "bad_")]],
      ["version": 1, "tags": (0..<16).map { _ in tag() }]] { XCTAssertThrowsError(try decodeList(root)) }
    var unknown = tag(); unknown["personalBestLedgerVersion"] = 2
    XCTAssertThrowsError(try decodeList(["version": 1, "tags": [unknown]]))
  }
  func testNativeHistoryAndCSVRetainStableIDsWithoutConvertingLegacyNames() throws {
    let id = UUID(), resultID = UUID()
    var json: [String: Any] = ["id": resultID.uuidString, "mode": "time", "language": "english",
      "durationSeconds": 15, "wpm": 60, "rawWpm": 70, "accuracy": 98, "consistency": 80,
      "errorCount": 1, "eventCount": 75, "tags": ["owned legacy name"], "startedAt": 100, "finishedAt": 115]
    func decoded() throws -> RemoteAccountResult {
      try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: json))
    }
    let legacy = try decoded(); XCTAssertNil(legacy.accountTagIDs)
    json["accountTagIDs"] = [id.uuidString]
    let native = try decoded(); XCTAssertEqual(native.accountTagIDs, [id]); XCTAssertEqual(native.tags, legacy.tags)
    let encoded = try JSONEncoder().encode(native)
    XCTAssertEqual(try JSONDecoder().decode(RemoteAccountResult.self, from: encoded).accountTagIDs, [id])
    let csv = RemoteResultCSVExport.csvString(for: [native])
    XCTAssertTrue(csv.contains("account_tag_ids")); XCTAssertTrue(csv.contains(id.uuidString))
    for malformed: Any in [NSNull(), "bad", [id.uuidString, id.uuidString]] {
      json["accountTagIDs"] = malformed; XCTAssertThrowsError(try decoded())
    }
  }
}
