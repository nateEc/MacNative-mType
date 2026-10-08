import Foundation
import XCTest
import XCTVapor
@testable import TypebarServerCore

final class AccountStreakClaimTests: XCTestCase {
  private func save(_ store: AuthStore, token: String, now: Date) async throws {
    _ = try await store.submitResult(.init(id: UUID(), mode: "time", language: "english", durationSeconds: 15,
      wordLimit: nil, wpm: 60, rawWpm: 60, accuracy: 100, consistency: 80, errorCount: 0, eventCount: 75,
      personalBestConfiguration: .init(difficulty: "normal", punctuation: false, numbers: false, lazyMode: false),
      startedAt: now.addingTimeInterval(-15), finishedAt: now), accessToken: token, now: now)
  }

  func testEmptyAndBoundaryResetSnapshotsNeverPretendThatOffsetChoiceSavedAResult() async throws {
    let now = Date.now, store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let owner = try await store.register(.init(email: "empty@example.invalid", password: "a secure password", displayName: "Empty"), now: now)
    let empty = try await store.accountProfileOverview(accessToken: owner.accessToken, now: now)
    let claim = try XCTUnwrap(empty.accountStreakClaim)
    XCTAssertEqual(claim.version, 1); XCTAssertNil(claim.lastResultMilliseconds)
    XCTAssertNil(claim.streakReferenceMilliseconds); XCTAssertNil(claim.dayBoundaryOffsetHours)
    _ = try await store.setStreakDayBoundary(.init(offsetHours: 0), accessToken: owner.accessToken, now: now)
    let chosen = try await store.accountProfileOverview(accessToken: owner.accessToken, now: now)
    XCTAssertNil(chosen.accountStreakClaim?.lastResultMilliseconds)
    XCTAssertEqual(chosen.accountStreakClaim?.dayBoundaryOffsetHours, 0)
    XCTAssertEqual(chosen.accountStreakClaim?.streakReferenceMilliseconds, now.timeIntervalSince1970 * 1000)
    XCTAssertEqual(chosen.completedResultCount, 0)
  }

  func testPrivateClaimSurvivesHistoryDeletionReloadAndReadWithoutPersistentWrites() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-streak-claim-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("store.json"), now = Date.now
    let store = try AuthStore(fileURL: file, bcryptCost: 4)
    let owner = try await store.register(.init(email: "owner@example.invalid", password: "a secure password", displayName: "Owner"), now: now)
    try await save(store, token: owner.accessToken, now: now)
    let later = now.addingTimeInterval(60)
    _ = try await store.setStreakDayBoundary(.init(offsetHours: 0.5), accessToken: owner.accessToken, now: later)
    let before = try await store.accountProfileOverview(accessToken: owner.accessToken, now: later)
    XCTAssertEqual(before.accountStreakClaim?.lastResultMilliseconds, now.timeIntervalSince1970.rounded(.down) * 1000)
    XCTAssertEqual(before.accountStreakClaim?.streakReferenceMilliseconds, later.timeIntervalSince1970 * 1000)
    _ = try await store.deleteResults(.init(currentPassword: "a secure password"), accessToken: owner.accessToken, now: later)
    let bytes = try Data(contentsOf: file), reloaded = try AuthStore(fileURL: file, bcryptCost: 4)
    let after = try await reloaded.accountProfileOverview(accessToken: owner.accessToken, now: later)
    XCTAssertEqual(after.accountStreakClaim, before.accountStreakClaim)
    XCTAssertEqual(after.streak, before.streak); XCTAssertEqual(try Data(contentsOf: file), bytes)
    let publicProfile = try await reloaded.publicProfile(id: owner.user.id, now: later)
    XCTAssertNil(publicProfile.accountStreakClaim)
  }

  func testSuspensionDoesNotHideOwnClaimOrRestorePublicActivity() async throws {
    let now = Date.now, store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let owner = try await store.register(.init(email: "owner@example.invalid", password: "a secure password", displayName: "Owner"), now: now)
    try await save(store, token: owner.accessToken, now: now)
    _ = try await store.setAccountSuspended(userID: owner.user.id, suspended: true, now: now)
    let own = try await store.accountProfileOverview(accessToken: owner.accessToken, now: now)
    let publicProfile = try await store.publicProfile(id: owner.user.id, now: now)
    XCTAssertNotNil(own.accountStreakClaim); XCTAssertNil(publicProfile.accountStreakClaim)
    XCTAssertNil(publicProfile.activity); XCTAssertTrue(own.accountSuspended)
  }

  func testStreakClaimMetadataIsOwnerOnlyEvenWhenPublicActivityIsHidden() async throws {
    let now = Date.now, store = try AuthStore(fileURL: nil, bcryptCost: 4, rankingEnvironment: .development)
    let owner = try await store.register(.init(email: "owner@example.invalid", password: "a secure password", displayName: "Owner"), now: now)
    _ = try await store.submitResult(.init(id: UUID(), mode: "time", language: "english", durationSeconds: 15,
      wordLimit: nil, wpm: 60, rawWpm: 60, accuracy: 100, consistency: 80, errorCount: 0, eventCount: 75,
      personalBestConfiguration: .init(difficulty: "normal", punctuation: false, numbers: false, lazyMode: false),
      startedAt: now.addingTimeInterval(-15), finishedAt: now), accessToken: owner.accessToken, now: now)
    _ = try await store.updateProfile(.init(profileDetails: .init(showActivity: false)), accessToken: owner.accessToken, now: now)
    let app = try await Application.make(.testing)
    do {
      try configure(app, authStore: store)
      try await app.test(.GET, "v1/profiles/me/overview", beforeRequest: {
        $0.headers.bearerAuthorization = .init(token: owner.accessToken)
      }) { response async throws in
        XCTAssertEqual(response.status, .ok)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
        let claim = try XCTUnwrap(json["accountStreakClaim"] as? [String: Any], "Owner needs an independent last completed-result timestamp")
        XCTAssertEqual(try XCTUnwrap(claim["lastResultMilliseconds"] as? Double), now.timeIntervalSince1970.rounded(.down) * 1000, accuracy: 0.001)
        XCTAssertEqual(claim["streakReferenceMilliseconds"] as? Double, claim["lastResultMilliseconds"] as? Double)
        XCTAssertEqual(claim["version"] as? Int, 1)
        XCTAssertNil(claim["dayBoundaryOffsetHours"], "Unset differs from an explicit zero")
        XCTAssertEqual(response.headers.first(name: .cacheControl), "private, no-store")
      }
      try await app.test(.GET, "v1/profiles/\(owner.user.id)?includePrivateActivity=true", beforeRequest: {
        $0.headers.bearerAuthorization = .init(token: owner.accessToken)
      }) { response async throws in
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
        XCTAssertNil(json["accountStreakClaim"]); XCTAssertNil(json["activity"])
      }
      try await app.test(.GET, "v1/profiles?query=Owner") { response async throws in
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
        let profiles = try XCTUnwrap(json["profiles"] as? [[String: Any]])
        XCTAssertEqual(profiles.count, 1); XCTAssertNil(profiles.first?["accountStreakClaim"])
      }
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }
}
