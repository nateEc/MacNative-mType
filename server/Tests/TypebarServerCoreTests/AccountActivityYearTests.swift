import Foundation
import XCTest
import XCTVapor
@testable import TypebarServerCore

final class AccountActivityYearTests: XCTestCase {
  func testAnnualActivityIsAuthenticatedPrivateAndIndependentOfPublicVisibility() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4), now = Date.now
    let owner = try await store.register(.init(email: "year-owner@example.invalid", password: "a secure password", displayName: "Owner"), now: now)
    let other = try await store.register(.init(email: "year-other@example.invalid", password: "a secure password", displayName: "Other"), now: now)
    _ = try await store.submitResult(.init(id: UUID(), mode: "time", language: "english", durationSeconds: 15,
      wordLimit: nil, wpm: 60, rawWpm: 60, accuracy: 100, errorCount: 0, eventCount: 75,
      startedAt: now.addingTimeInterval(-15), finishedAt: now), accessToken: owner.accessToken, now: now)
    _ = try await store.updateProfile(.init(profileDetails: .init(showActivity: false)), accessToken: owner.accessToken, now: now)
    let app = try await Application.make(.testing)
    do {
      try configure(app, authStore: store)
      try await app.test(.GET, "v1/profiles/me/activity?id=\(other.user.id)", beforeRequest: {
        $0.headers.bearerAuthorization = .init(token: owner.accessToken)
      }) { response async throws in
        XCTAssertEqual(response.status, .ok)
        guard response.status == .ok else { return }
        XCTAssertEqual(response.headers.first(name: .cacheControl), "private, no-store")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
        XCTAssertEqual(json["id"] as? String, owner.user.id.uuidString)
        let years = try XCTUnwrap(json["activityByYear"] as? [String: [Any]])
        XCTAssertEqual(years.values.flatMap { $0 }.compactMap { $0 as? Int }.reduce(0, +), 1)
        XCTAssertEqual(json["practiceHistoryComplete"] as? Bool, true)
        for key in ["email", "accessToken", "passwordHash", "replayEvents", "profileDetails"] { XCTAssertNil(json[key]) }
      }
      try await app.test(.GET, "v1/profiles/\(owner.user.id)") { response async throws in
        XCTAssertNil(try response.content.decode(PublicProfileResponse.self).activity)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
        XCTAssertNil(json["activityByYear"])
      }
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }

  func testAnnualActivityRejectsMissingOrInvalidAuthentication() async throws {
    let app = try await Application.make(.testing)
    do {
      try configure(app, authStore: AuthStore(fileURL: nil, bcryptCost: 4))
      try await app.test(.GET, "v1/profiles/me/activity") { response async throws in
        XCTAssertEqual(response.status, .unauthorized)
      }
      try await app.test(.GET, "v1/profiles/me/activity", beforeRequest: {
        $0.headers.bearerAuthorization = .init(token: "owned-invalid-token")
      }) { response async throws in XCTAssertEqual(response.status, .unauthorized) }
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }

  func testAnnualLedgerSurvivesHistoryDeletionAndDiskReloadWithoutReadWrites() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-years-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("store.json"), password = "a secure password", email = "years@example.invalid"
    let dates = [1_704_067_200.0, 1_709_164_800, 1_735_603_200, 1_767_139_200].map(Date.init(timeIntervalSince1970:))
    let store = try AuthStore(fileURL: file, bcryptCost: 4)
    _ = try await store.register(.init(email: email, password: password, displayName: "Owner"), now: dates[0])
    var session: AuthSessionResponse?
    for date in dates {
      let login = try await store.login(.init(email: email, password: password), now: date)
      _ = try await store.submitResult(.init(id: UUID(), mode: "time", language: "english", durationSeconds: 15,
        wordLimit: nil, wpm: 60, rawWpm: 60, accuracy: 100, errorCount: 0, eventCount: 75,
        startedAt: date.addingTimeInterval(-15), finishedAt: date), accessToken: login.accessToken, now: date)
      session = login
    }
    let owner = try XCTUnwrap(session), now = try XCTUnwrap(dates.last)
    let before = try await store.accountActivityYears(accessToken: owner.accessToken, now: now)
    XCTAssertEqual(before.activityByYear["2024"]?.count, 366)
    XCTAssertEqual(before.activityByYear["2024"]?[0], 1)
    XCTAssertEqual(before.activityByYear["2024"]?[59], 1)
    XCTAssertEqual(before.activityByYear["2024"]?[365], 1)
    XCTAssertEqual(before.activityByYear["2025"]?.last, 1)
    _ = try await store.deleteResults(.init(currentPassword: password), accessToken: owner.accessToken, now: now)
    let reloaded = try AuthStore(fileURL: file, bcryptCost: 4), bytes = try Data(contentsOf: file)
    let after = try await reloaded.accountActivityYears(accessToken: owner.accessToken, now: now)
    XCTAssertEqual(after, before); XCTAssertEqual(try Data(contentsOf: file), bytes)
    let history = try await reloaded.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    XCTAssertEqual(history.total, 0)
  }

  func testSuspendedOwnerStillReadsPrivateYearsWhileDifferentOwnerGetsEmpty() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4), now = Date.now
    let owner = try await store.register(.init(email: "suspended@example.invalid", password: "a secure password", displayName: "Owner"), now: now)
    let other = try await store.register(.init(email: "other@example.invalid", password: "a secure password", displayName: "Other"), now: now)
    _ = try await store.submitResult(.init(id: UUID(), mode: "time", language: "english", durationSeconds: 15,
      wordLimit: nil, wpm: 60, rawWpm: 60, accuracy: 100, errorCount: 0, eventCount: 75,
      startedAt: now.addingTimeInterval(-15), finishedAt: now), accessToken: owner.accessToken, now: now)
    _ = try await store.setAccountSuspended(userID: owner.user.id, suspended: true, now: now)
    let own = try await store.accountActivityYears(accessToken: owner.accessToken, now: now)
    let theirs = try await store.accountActivityYears(accessToken: other.accessToken, now: now)
    XCTAssertEqual(own.activityByYear.values.flatMap { $0 }.compactMap { $0 }.reduce(0,+), 1)
    XCTAssertEqual(own.id, owner.user.id); XCTAssertEqual(theirs.id, other.user.id); XCTAssertTrue(theirs.activityByYear.isEmpty)
    XCTAssertTrue(theirs.practiceHistoryComplete)
  }
}
