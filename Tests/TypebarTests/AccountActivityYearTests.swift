import Foundation
import XCTest
@testable import Typebar

final class AccountActivityYearTests: XCTestCase {
  func testOwnerProfileUsesAnnualSelectorWhilePublicCalendarStaysReadOnly() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let text = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/CloudSyncView.swift"), encoding: .utf8)
    XCTAssertTrue(text.contains("AccountActivityCalendarView(profile: profile, account: account)"),
      "Owner activity needs the annual selector, not the public recent-only calendar")
  }

  private func response(_ id: UUID = UUID(), years: [String: [Int?]] = ["2024": [3,nil,7]], complete: Bool = true) throws -> RemoteAccountActivityYears {
    try JSONDecoder().decode(RemoteAccountActivityYears.self, from: JSONEncoder().encode(Fixture(id: id,
      activityByYear: years, practiceHistoryComplete: complete)))
  }
  private struct Fixture: Encodable { let id: UUID; let activityByYear: [String: [Int?]]; let practiceHistoryComplete: Bool }

  func testAnnualProjectionKeepsUTCLeapDayDecember31AndMissingDistinctFromIncomplete() throws {
    var counts = Array<Int?>(repeating: nil, count: 366)
    counts[0] = 3; counts[59] = 7; counts[365] = 9
    let value = try response(years: ["2024": counts], complete: false)
    let activity = try XCTUnwrap(AccountActivityYearPolicy.activity(year: 2024, from: value))
    let cells = ActivityHeatmap.cells(completedTestsByDay: activity.testsByDays.map { $0 ?? 0 }, endingAt: activity.lastDay,
      calendar: AccountActivityYearPolicy.utc)
    XCTAssertEqual(cells.count, 366); XCTAssertEqual(activity.dayBoundaryOffsetHours, 0)
    XCTAssertEqual(cells[0].day.timeIntervalSince1970, 1_704_067_200)
    XCTAssertEqual(AccountActivityYearPolicy.utc.component(.day, from: cells[59].day), 29)
    XCTAssertEqual(AccountActivityYearPolicy.utc.component(.month, from: cells[59].day), 2)
    XCTAssertEqual(AccountActivityYearPolicy.utc.component(.year, from: cells[365].day), 2024)
    XCTAssertEqual(ActivityHeatmap.completedTestCount(in: cells), 19)
    XCTAssertNil(AccountActivityYearPolicy.activity(year: 2023, from: value))
    XCTAssertFalse(value.practiceHistoryComplete)
    let short = try XCTUnwrap(AccountActivityYearPolicy.activity(year: 2025, from: response(years: ["2025": [2]])))
    XCTAssertEqual(short.testsByDays.count, 365); XCTAssertEqual(short.testsByDays[0], 2); XCTAssertNil(short.testsByDays[364])
  }

  func testCurrentYearSnapshotPadsFutureDaysAndDoesNotCarryPreviousYear() throws {
    let first = Date(timeIntervalSince1970: 1_704_067_200)
    let snapshot = RemotePublicProfileActivity(lastDay: first.addingTimeInterval(86400), testsByDays: [9,3,nil])
    let value = try XCTUnwrap(AccountActivityYearPolicy.currentYearActivity(snapshot, year: 2024))
    XCTAssertEqual(value.testsByDays.count, 366); XCTAssertEqual(value.testsByDays[0], 3)
    XCTAssertNil(value.testsByDays[1]); XCTAssertNil(value.testsByDays[365])
    XCTAssertEqual(value.testsByDays.compactMap { $0 }.reduce(0,+), 3)
    let prior = RemotePublicProfileActivity(lastDay: first.addingTimeInterval(-86400), testsByDays: [7])
    XCTAssertEqual(AccountActivityYearPolicy.currentYearActivity(prior, year: 2024)?.testsByDays.compactMap { $0 }, [])
    XCTAssertNil(AccountActivityYearPolicy.currentYearActivity(nil, year: 2024))
  }

  func testYearOptionsDescendToJoinYearAndRejectInvalidOrFutureJoinDates() {
    let calendar = AccountActivityYearPolicy.utc
    XCTAssertEqual(AccountActivityYearPolicy.years(joinedAt: Date(timeIntervalSince1970: 1_704_067_200),
      now: Date(timeIntervalSince1970: 1_800_000_000), calendar: calendar), [2027,2026,2025,2024])
    XCTAssertTrue(AccountActivityYearPolicy.years(joinedAt: .distantFuture, now: .now, calendar: calendar).isEmpty)
    XCTAssertTrue(AccountActivityYearPolicy.years(joinedAt: Date(timeIntervalSince1970: .nan), calendar: calendar).isEmpty)
  }

  func testAnnualDecoderRejectsNoncanonicalYearsWrongLengthAndUnsafeCounts() throws {
    for years: [String: [Int?]] in [["02024": [1]], ["1969": [1]], ["10000": [1]], ["2025": Array(repeating: nil, count: 366)],
      ["2024": [-1]], ["2024": [9_007_199_254_740_992]]] {
      XCTAssertThrowsError(try response(years: years))
    }
    XCTAssertNoThrow(try response(years: [:]))
  }

  func testCalendarIntensityUsesSparseActivityNotEmptyDayZeros() {
    XCTAssertEqual(ProfileActivityCalendarPresentation.levels([nil,nil,7,nil]), [0,0,2,0])
    XCTAssertEqual(ProfileActivityCalendarPresentation.levels([nil,0,7,nil]), [0,0,4,0])
    XCTAssertEqual(ProfileActivityCalendarPresentation.levels([nil,nil]), [0,0])
  }

  @MainActor private func session(_ body: (AccountSession) async throws -> Void) async throws {
    let suite = "TypebarTests.activity-years.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let account = AccountSession(defaults: defaults)
    account.currentUser = .init(id: UUID(), email: "owned@example.invalid", displayName: "Owner", totalExperience: 500)
    try await body(account)
  }

  @MainActor func testActualLoaderCachesOnlyCurrentViewScopeAndRecentDoesNotFetch() async throws {
    try await session { account in
      let user = try XCTUnwrap(account.currentUser), loader = AccountActivityYearLoader()
      let key = AccountActivityYearKey(account: account, profileID: user.id, completedCount: 10, revision: UUID())
      let response = try self.response(user.id)
      var calls = 0
      func fetch() async throws -> RemoteAccountActivityYears { calls += 1; return response }
      await loader.load(.init(key: key, year: nil), account: account, fetch: fetch)
      XCTAssertEqual(calls, 0); XCTAssertNil(loader.loaded)
      await loader.load(.init(key: key, year: 2024), account: account, fetch: fetch)
      await loader.load(.init(key: key, year: 2025), account: account, fetch: fetch)
      await loader.load(.init(key: key, year: nil), account: account, fetch: fetch)
      XCTAssertEqual(calls, 1); XCTAssertEqual(loader.loaded?.response.id, user.id)
      let fresh = AccountActivityYearKey(account: account, profileID: user.id, completedCount: 11, revision: key.revision)
      await loader.load(.init(key: fresh, year: 2024), account: account, fetch: fetch)
      XCTAssertEqual(calls, 2); XCTAssertEqual(loader.loaded?.key, fresh)
      XCTAssertEqual(account.currentUser, user); XCTAssertNil(account.lastAccountResult)
      XCTAssertTrue(account.remoteResults.isEmpty); XCTAssertFalse(account.isWorking); XCTAssertNil(account.statusMessage)
    }
  }

  @MainActor func testCurrentYearUsesLoadedSnapshotWithoutAnnualNetwork() async throws {
    try await session { account in
      let id = try XCTUnwrap(account.currentUser?.id), loader = AccountActivityYearLoader()
      let key = AccountActivityYearKey(account: account, profileID: id, completedCount: 10, revision: UUID())
      let year = AccountActivityYearPolicy.utc.component(.year, from: .now)
      var calls = 0
      await loader.load(.init(key: key, year: year), account: account) { calls += 1; return try self.response(id) }
      XCTAssertEqual(calls, 0, "Current year must stay available from the loaded profile while offline")
      XCTAssertNil(loader.loaded); XCTAssertNil(loader.failure)
    }
  }

  @MainActor func testScopedAnnualReadRejectsWrongUserExpiredScopeAndSessionOrServerABA() async throws {
    try await session { account in
      let scope = try XCTUnwrap(account.resultPublicationScope), user = try XCTUnwrap(account.currentUser), endpoint = account.endpoint
      for kind in 0...2 {
        do {
          _ = try await account.loadAccountActivityYears(scope: scope) {
            if kind == 0 { return try self.response() }
            if kind == 1 { account.currentUser = nil; account.currentUser = user }
            if kind == 2 {
              XCTAssertTrue(account.updateEndpoint("https://other-owned.invalid")); XCTAssertTrue(account.updateEndpoint(endpoint))
              account.currentUser = user
            }
            return try self.response(user.id)
          }
          XCTFail("Wrong identity and ABA must not display annual data")
        } catch let error as RemoteAccountError {
          if kind == 0 { guard case .unexpectedResponse = error else { return XCTFail("\(error)") } }
          else { guard case .accountScopeChanged = error else { return XCTFail("\(error)") } }
        }
      }
      account.currentUser = nil
      var calls = 0
      do { _ = try await account.loadAccountActivityYears(scope: scope) { calls += 1; return try self.response(user.id) }; XCTFail() }
      catch let error as RemoteAccountError { guard case .accountScopeChanged = error else { return XCTFail("\(error)") } }
      XCTAssertEqual(calls, 0)
    }
  }

  @MainActor func testActualLoaderClearsSnapshotOnLogoutAndCannotReuseOldSessionKey() async throws {
    try await session { account in
      let user = try XCTUnwrap(account.currentUser), loader = AccountActivityYearLoader(), revision = UUID()
      let key = AccountActivityYearKey(account: account, profileID: user.id, completedCount: 10, revision: revision)
      let value = try self.response(user.id)
      await loader.load(.init(key: key, year: 2024), account: account) { value }
      XCTAssertNotNil(loader.loaded)
      account.currentUser = nil; account.currentUser = user
      XCTAssertFalse(key.isCurrent(account))
      await loader.load(.init(key: key, year: 2024), account: account) { XCTFail("Stale session must not fetch"); return value }
      XCTAssertNil(loader.loaded)
      let fresh = AccountActivityYearKey(account: account, profileID: user.id, completedCount: 10, revision: revision)
      XCTAssertNotEqual(key, fresh)
      await loader.load(.init(key: fresh, year: 2024), account: account) { value }
      XCTAssertEqual(loader.loaded?.key, fresh)
    }
  }

  @MainActor func testActualLoaderFailureRetryCancellationAndOlderYearRequestCannotPublish() async throws {
    try await session { account in
      let id = try XCTUnwrap(account.currentUser?.id), loader = AccountActivityYearLoader()
      let key = AccountActivityYearKey(account: account, profileID: id, completedCount: 10, revision: UUID())
      let request = AccountActivityYearRequest(key: key, year: 2024), value = try self.response(id)
      await loader.load(request, account: account) { throw URLError(.notConnectedToInternet) }
      XCTAssertEqual(loader.failure?.request, request); XCTAssertNil(loader.loaded)
      await loader.load(request, account: account) { value }
      XCTAssertNil(loader.failure); XCTAssertNotNil(loader.loaded)
      let fresh = AccountActivityYearRequest(key: .init(account: account, profileID: id, completedCount: 11, revision: UUID()), year: 2025)
      await loader.load(fresh, account: account) {
        await loader.load(.init(key: fresh.key, year: nil), account: account) { XCTFail("Recent must not fetch"); return value }
        return value
      }
      XCTAssertNil(loader.loaded); XCTAssertNil(loader.failure)
      let cancelled = Task { @MainActor in
        await loader.load(fresh, account: account) { withUnsafeCurrentTask { $0?.cancel() }; return value }
      }
      await cancelled.value
      XCTAssertNil(loader.loaded); XCTAssertNil(loader.failure)
    }
  }

  func testYearProjectionMatchesCompletePinnedCalendarAndRecordsHistoricalGetterDefect() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"],
      ProcessInfo.processInfo.environment["TYPEBAR_PRACTICE_SOURCE_DEPENDENCIES"] != nil else { throw XCTSkip("Readiness supplies fixed reference and date dependencies") }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe(), diagnostics = Pipe()
    process.executableURL = .init(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-account-activity-years.mjs").path, reference, "--emit-fixtures"]
    process.environment = ProcessInfo.processInfo.environment.merging(["TZ": "UTC"]) { _, new in new }
    process.standardOutput = output; process.standardError = diagnostics; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile(), errors = diagnostics.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0, String(decoding: errors, as: UTF8.self))
    struct Source: Decodable {
      struct Row: Decodable { let year: Int; let counts: [Int?]; let start: Double; let end: Double; let total: Int; let visible: [Int?]; let levels: [Int] }
      struct Snapshot: Decodable { let year: Int; let counts: [Int?]; let lastDay: Double; let visible: [Int?] }
      let fixtures: [Row]; let currentSnapshots: [Snapshot]; let historicalDayShift: Bool; let historicalFullYearRollover: Bool
    }
    let source = try JSONDecoder().decode(Source.self, from: data)
    XCTAssertEqual(source.fixtures.count, 46); XCTAssertTrue(source.historicalDayShift); XCTAssertTrue(source.historicalFullYearRollover)
    for row in source.fixtures {
      let actual = try XCTUnwrap(AccountActivityYearPolicy.activity(year: row.year, from: response(years: [String(row.year): row.counts])))
      XCTAssertEqual(actual.testsByDays, row.visible)
      XCTAssertEqual(ProfileActivityCalendarPresentation.levels(actual.testsByDays), row.levels)
      XCTAssertEqual(actual.testsByDays.compactMap { $0 }.reduce(0,+), row.total)
      XCTAssertEqual(actual.lastDay.timeIntervalSince1970, floor(row.end / 86_400_000) * 86_400)
      XCTAssertEqual(actual.lastDay.timeIntervalSince1970 - Double(actual.testsByDays.count-1) * 86_400, row.start / 1_000)
    }
    XCTAssertEqual(source.currentSnapshots.count, 4)
    for row in source.currentSnapshots {
      let snapshot = RemotePublicProfileActivity(lastDay: Date(timeIntervalSince1970: row.lastDay / 1000), testsByDays: row.counts)
      XCTAssertEqual(AccountActivityYearPolicy.currentYearActivity(snapshot, year: row.year)?.testsByDays, row.visible)
    }
  }
}
