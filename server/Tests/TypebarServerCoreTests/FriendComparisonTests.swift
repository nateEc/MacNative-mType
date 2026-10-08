import Foundation
import XCTest
import XCTVapor
@testable import TypebarServerCore

final class FriendComparisonTests: XCTestCase {
  func testConnectionsIncludesTokenOwnersPublicComparisonWithoutPrivateOverview() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let owner = try await store.register(.init(email: "owned@example.invalid", password: "a secure password", displayName: "Owner"))
    let response = try await store.connections(accessToken: owner.accessToken)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(response)) as? [String: Any])
    struct LegacyResponse: Decodable { let connections: [ConnectionResponse] }
    XCTAssertTrue(try JSONDecoder().decode(LegacyResponse.self, from: JSONEncoder().encode(response)).connections.isEmpty)
    let comparison = try XCTUnwrap(json["ownerProfile"] as? [String: Any])
    XCTAssertEqual(comparison["id"] as? String, owner.user.id.uuidString)
    XCTAssertEqual(comparison["completedResultCount"] as? Int, 0)
    XCTAssertEqual(comparison["startedTestCount"] as? Int, 0)
    for key in ["activity", "accountStreakClaim", "allTimeLbs", "email", "accessToken", "passwordHash"] {
      XCTAssertNil(comparison[key], key)
    }
    XCTAssertTrue(response.connections.isEmpty, "Self comparison is not an actionable connection")
    do { _ = try await store.connections(accessToken: "invalid-owned-token"); XCTFail("Must authenticate") }
    catch { /* Authentication rejected before projecting an owner. */ }
  }

  func testOwnerComparisonUsesLifetimeLedgerAfterDeletionWithoutWritingStore() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-friend-comparison-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("owned.json"), now = Date.now
    let store = try AuthStore(fileURL: file, bcryptCost: 4)
    let owner = try await store.register(.init(email: "owned@example.invalid", password: "a secure password", displayName: "Owner"), now: now)
    _ = try await store.submitResult(.init(id: UUID(), mode: "time", language: "english", durationSeconds: 15,
      wordLimit: nil, wpm: 60, rawWpm: 60, accuracy: 100, consistency: 80, errorCount: 0, eventCount: 75,
      personalBestConfiguration: .init(difficulty: "normal", punctuation: false, numbers: false, lazyMode: false),
      startedAt: now.addingTimeInterval(-15), finishedAt: now), accessToken: owner.accessToken, now: now)
    _ = try await store.updateProfile(.init(profileDetails: .init(showActivity: false)), accessToken: owner.accessToken, now: now)
    let beforeResponse = try await store.connections(accessToken: owner.accessToken, now: now)
    let before = try XCTUnwrap(beforeResponse.ownerProfile)
    _ = try await store.deleteResults(.init(currentPassword: "a secure password"), accessToken: owner.accessToken, now: now)
    let bytes = try Data(contentsOf: file)
    let afterResponse = try await store.connections(accessToken: owner.accessToken, now: now)
    let after = try XCTUnwrap(afterResponse.ownerProfile)
    XCTAssertEqual(after.completedResultCount, 1); XCTAssertEqual(after.startedTestCount, before.startedTestCount)
    XCTAssertEqual(after.totalTypingSeconds, before.totalTypingSeconds)
    XCTAssertEqual(after.totalExperience, before.totalExperience)
    XCTAssertEqual(after.personalBestSnapshots, before.personalBestSnapshots)
    XCTAssertNil(after.activity); XCTAssertNil(after.accountStreakClaim)
    XCTAssertEqual(try Data(contentsOf: file), bytes)
  }

  func testHTTPComparisonIdentityCannotBeChosenByQueryAndIsNotCacheable() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let owner = try await store.register(.init(email: "owned@example.invalid", password: "a secure password", displayName: "Owner"))
    let other = try await store.register(.init(email: "other@example.invalid", password: "a secure password", displayName: "Other"))
    let app = try await Application.make(.testing)
    do {
      try configure(app, authStore: store)
      for session in [owner, other] {
        try await app.test(.GET, "v1/connections?ownerID=\(other.user.id)", beforeRequest: {
          $0.headers.bearerAuthorization = .init(token: session.accessToken)
        }) { response async throws in
          XCTAssertEqual(response.status, .ok)
          XCTAssertEqual(response.headers.first(name: .cacheControl), "private, no-store")
          let value = try response.content.decode(ConnectionsResponse.self)
          XCTAssertEqual(value.ownerProfile?.id, session.user.id); XCTAssertTrue(value.connections.isEmpty)
        }
      }
      try await app.test(.GET, "v1/connections") { response async throws in XCTAssertEqual(response.status, .unauthorized) }
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }
}
