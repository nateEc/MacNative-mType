import Foundation
import XCTest
import XCTVapor
@testable import TypebarServerCore

final class AccountProfileOverviewTests: XCTestCase {
  func testAuthenticatedOverviewKeepsOwnersHiddenActivityPrivateAndUsesTokenIdentity() async throws {
    let now = Date.now
    let store = try AuthStore(fileURL: nil, bcryptCost: 4, rankingEnvironment: .development)
    let owner = try await store.register(.init(email: "owner@example.invalid", password: "a secure password", displayName: "Owner"), now: now)
    let other = try await store.register(.init(email: "other@example.invalid", password: "a secure password", displayName: "Other"), now: now)
    _ = try await store.submitResult(.init(id: UUID(), mode: "time", language: "english", durationSeconds: 15,
      wordLimit: nil, wpm: 60, rawWpm: 60, accuracy: 100, consistency: 80, errorCount: 0, eventCount: 75,
      personalBestConfiguration: .init(difficulty: "normal", punctuation: false, numbers: false, lazyMode: false),
      startedAt: now.addingTimeInterval(-15), finishedAt: now), accessToken: owner.accessToken, now: now)
    _ = try await store.updateProfile(.init(profileDetails: .init(bio: "Owned bio", showActivity: false)),
      accessToken: owner.accessToken, now: now)
    let app = try await Application.make(.testing)
    do {
      try configure(app, authStore: store)
      for (session, count) in [(owner, 1), (other, 0)] {
        try await app.test(.GET, "v1/profiles/me/overview?id=\(other.user.id)", beforeRequest: {
          $0.headers.bearerAuthorization = .init(token: session.accessToken)
        }) { response async throws in
          XCTAssertEqual(response.status, .ok)
          guard response.status == .ok else { return }
          XCTAssertEqual(response.headers.first(name: .cacheControl), "private, no-store")
          let profile = try response.content.decode(PublicProfileResponse.self)
          XCTAssertEqual(profile.id, session.user.id); XCTAssertEqual(profile.completedResultCount, count)
          if count == 1 {
            XCTAssertEqual(profile.activity?.testsByDays.compactMap { $0 }.reduce(0, +), 1)
            XCTAssertFalse(profile.profileDetails.showActivity)
            XCTAssertEqual(profile.personalBestSnapshots?.count, 1)
            XCTAssertEqual(profile.allTimeLbs?.time["15"]?["english"]?.rank, 1)
          }
          let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
          for key in ["email", "accessToken", "passwordHash", "replayEvents"] { XCTAssertNil(json[key]) }
        }
      }
      try await app.test(.GET, "v1/profiles/\(owner.user.id)?includePrivateActivity=true", beforeRequest: {
        $0.headers.bearerAuthorization = .init(token: owner.accessToken)
      }) { response async throws in
        XCTAssertEqual(response.status, .ok)
        XCTAssertNil(try response.content.decode(PublicProfileResponse.self).activity)
      }
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }

  func testOverviewRequiresAuthenticationAndRejectsInvalidToken() async throws {
    let app = try await Application.make(.testing)
    do {
      try configure(app, authStore: AuthStore(fileURL: nil, bcryptCost: 4))
      try await app.test(.GET, "v1/profiles/me/overview") { response async throws in
        XCTAssertEqual(response.status, .unauthorized)
      }
      try await app.test(.GET, "v1/profiles/me/overview", beforeRequest: {
        $0.headers.bearerAuthorization = .init(token: "invalid-owned-test-token")
      }) { response async throws in XCTAssertEqual(response.status, .unauthorized) }
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }

  func testOwnerReadPreservesLifetimeAndPersonalBestsAfterHistoryDeletionWithoutWriting() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-owner-overview-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("store.json"), now = Date.now
    let store = try AuthStore(fileURL: file, bcryptCost: 4, rankingEnvironment: .development)
    let owner = try await store.register(.init(email: "owner@example.invalid", password: "a secure password", displayName: "Owner"), now: now)
    _ = try await store.submitResult(.init(id: UUID(), mode: "time", language: "english", durationSeconds: 15,
      wordLimit: nil, wpm: 60, rawWpm: 60, accuracy: 100, consistency: 80, errorCount: 0, eventCount: 75,
      personalBestConfiguration: .init(difficulty: "normal", punctuation: false, numbers: false, lazyMode: false),
      startedAt: now.addingTimeInterval(-15), finishedAt: now), accessToken: owner.accessToken, now: now)
    _ = try await store.updateProfile(.init(profileDetails: .init(showActivity: false)), accessToken: owner.accessToken, now: now)
    let before = try await store.accountProfileOverview(accessToken: owner.accessToken, now: now)
    _ = try await store.deleteResults(.init(currentPassword: "a secure password"), accessToken: owner.accessToken, now: now)
    let bytes = try Data(contentsOf: file)
    let after = try await store.accountProfileOverview(accessToken: owner.accessToken, now: now)
    XCTAssertEqual(after.completedResultCount, before.completedResultCount)
    XCTAssertEqual(after.startedTestCount, before.startedTestCount)
    XCTAssertEqual(after.totalTypingSeconds, before.totalTypingSeconds)
    XCTAssertEqual(after.activity, before.activity); XCTAssertEqual(after.streak, before.streak)
    XCTAssertEqual(after.personalBestSnapshots, before.personalBestSnapshots)
    XCTAssertEqual(after.allTimeLbs, before.allTimeLbs)
    XCTAssertEqual(try Data(contentsOf: file), bytes, "Reading the overview must not persist or migrate state")
    let history = try await store.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    XCTAssertEqual(history.total, 0)
  }

  func testSuspendedOwnerCanReadOwnActivityAndPBWithoutRestoringPublicVisibilityOrRanks() async throws {
    let now = Date.now, store = try AuthStore(fileURL: nil, bcryptCost: 4, rankingEnvironment: .development)
    let owner = try await store.register(.init(email: "owner@example.invalid", password: "a secure password", displayName: "Owner"), now: now)
    _ = try await store.submitResult(.init(id: UUID(), mode: "time", language: "english", durationSeconds: 15,
      wordLimit: nil, wpm: 60, rawWpm: 60, accuracy: 100, consistency: 80, errorCount: 0, eventCount: 75,
      personalBestConfiguration: .init(difficulty: "normal", punctuation: false, numbers: false, lazyMode: false),
      startedAt: now.addingTimeInterval(-15), finishedAt: now), accessToken: owner.accessToken, now: now)
    _ = try await store.setAccountSuspended(userID: owner.user.id, suspended: true, now: now)
    let own = try await store.accountProfileOverview(accessToken: owner.accessToken, now: now)
    let publicProfile = try await store.publicProfile(id: owner.user.id, now: now)
    XCTAssertNotNil(own.activity); XCTAssertEqual(own.personalBestSnapshots?.count, 1)
    XCTAssertTrue(own.accountSuspended); XCTAssertNil(own.allTimeLbs)
    XCTAssertNil(publicProfile.activity); XCTAssertNil(publicProfile.allTimeLbs)
  }
}
