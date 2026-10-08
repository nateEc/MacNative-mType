import Foundation
import XCTest
@testable import Typebar

final class FriendComparisonTests: XCTestCase {
  private func profile(name: String = "Owned", xp: Int = 100, completed: Int = 2, started: Int = 3,
    seconds: Double = 90, days: Int = 2, legacy: Bool = false, bests: [[String: Any]] = []) throws -> RemotePublicProfile {
    var object: [String: Any] = ["id": UUID().uuidString, "displayName": name, "joinedAt": 0,
      "completedResultCount": completed, "bestWPM": 0, "personalBests": bests,
      "startedTestCount": started, "totalExperience": xp, "totalTypingSeconds": seconds,
      "streak": ["currentDays": days, "longestDays": 12]]
    if !legacy { object["practiceHistoryComplete"] = true }
    return try JSONDecoder().decode(RemotePublicProfile.self, from: JSONSerialization.data(withJSONObject: object))
  }
  private func best(_ speed: Double, seconds: Int = 15, language: String = "english") -> [String: Any] {
    ["id": UUID().uuidString, "mode": "time", "durationSeconds": seconds, "language": language,
      "wpm": Int(speed.rounded()), "preciseWpm": speed, "accuracy": 99, "preciseAccuracy": 98.75,
      "consistency": 80.25, "finishedAt": 0]
  }
  private func snapshot(_ profiles: [RemotePublicProfile], owner: RemotePublicProfile? = nil) -> ConnectionsSnapshot {
    .init(connections: profiles.enumerated().map { index, profile in
      .init(id: profile.id, profile: profile, relation: .friend, updatedAt: .init(timeIntervalSince1970: Double(index)))
    }, blockedProfiles: [], ownerProfile: owner)
  }

  func testFriendBestsChooseLaterWholeTieAcrossLanguagesAndKeepZero() throws {
    let zero = best(0), first = best(60.49), last = best(60.49, language: "spanish"), minute = best(80, seconds: 60)
    let row = FriendComparisonRow(profile: try profile(bests: [zero, first, last, minute]), connectedAt: nil, isOwner: false)
    XCTAssertEqual(row.best(seconds: 15)?.id.uuidString, last["id"] as? String)
    XCTAssertEqual(row.best(seconds: 15)?.language, "spanish")
    XCTAssertEqual(row.best(seconds: 15)?.preciseAccuracy, 98.75)
    XCTAssertEqual(row.best(seconds: 60)?.id.uuidString, minute["id"] as? String)
    let onlyZero = FriendComparisonRow(profile: try profile(bests: [zero]), connectedAt: nil, isOwner: false)
    XCTAssertEqual(onlyZero.best(seconds: 15)?.effectiveWpm, 0)
    XCTAssertNil(onlyZero.best(seconds: 60))
    var unknown = first; unknown["mode2"] = "unknown"
    XCTAssertNil(FriendComparisonRow(profile: try profile(bests: [unknown]), connectedAt: nil, isOwner: false).best(seconds: 15))
  }

  func testAllEightColumnsSortCanonicalValuesAndRetainEqualInputOrder() throws {
    let low = try profile(name: "Alpha", xp: 0, completed: 0, started: 20, seconds: 0, days: 1,
      bests: [best(0), best(1, seconds: 60)])
    let high = try profile(name: "Zulu", xp: 100, completed: 3, seconds: 300, days: 10,
      bests: [best(60.49), best(80, seconds: 60)])
    let value = snapshot([low, high])
    for column in FriendComparisonColumn.allCases {
      XCTAssertEqual(FriendComparisonPolicy.rows(value, sort: [.init(column: column, descending: false)]).map(\.id), [low.id, high.id], column.rawValue)
      XCTAssertEqual(FriendComparisonPolicy.rows(value, sort: [.init(column: column, descending: true)]).map(\.id), [high.id, low.id], column.rawValue)
    }
    XCTAssertEqual(FriendComparisonPolicy.rows(snapshot([high, low, high]), sort: [.init(column: .name, descending: true)]).map(\.id), [high.id, high.id, low.id])
  }

  func testOwnerComparisonIsNotActionableAndLegacyDataRemainsUnknown() throws {
    let owner = try profile(), old = try profile(legacy: true)
    let value = snapshot([old], owner: owner)
    try value.validate(ownerID: owner.id)
    let rows = FriendComparisonPolicy.rows(value, sort: [])
    XCTAssertEqual(rows.map(\.id), [old.id, owner.id]); XCTAssertEqual(rows.map(\.isOwner), [false, true])
    XCTAssertFalse(rows[0].hasStatistics); XCTAssertNil(rows[0].level)
    XCTAssertEqual(rows[1].level, 2)
    for direction in [false, true] {
      XCTAssertEqual(FriendComparisonPolicy.rows(value, sort: [.init(column: .experience, descending: direction)]).map(\.id), [owner.id, old.id])
    }
    XCTAssertFalse(value.allows(.remove(owner.id), ownerID: owner.id))
    XCTAssertThrowsError(try value.validate(ownerID: UUID()))
    let oldResponse = try JSONDecoder().decode(RemoteConnectionsResponse.self, from: Data("{\"connections\":[]}".utf8))
    XCTAssertNil(oldResponse.ownerProfile)
  }

  func testSortCycleMultiColumnPersistenceAndInvalidSavedPreferences() {
    var sort = FriendComparisonSort.toggled([], column: .experience, adding: false)
    XCTAssertEqual(sort, [.init(column: .experience, descending: true)])
    sort = FriendComparisonSort.toggled(sort, column: .name, adding: true)
    XCTAssertEqual(sort.count, 2); XCTAssertFalse(sort[1].descending)
    XCTAssertEqual(FriendComparisonSort.decode(FriendComparisonSort.encode(sort)), sort)
    sort = FriendComparisonSort.toggled(sort, column: .experience, adding: true)
    XCTAssertFalse(sort[0].descending)
    sort = FriendComparisonSort.toggled(sort, column: .experience, adding: true)
    XCTAssertEqual(sort.map(\.column), [.name])
    XCTAssertTrue(FriendComparisonSort.toggled(sort, column: .name, adding: false)[0].descending)
    for text in ["invalid", "[{\"column\":\"unknown\",\"descending\":true}]", "[{\"column\":\"name\",\"descending\":true},{\"column\":\"name\",\"descending\":false}]"] {
      XCTAssertTrue(FriendComparisonSort.decode(text).isEmpty)
    }
  }

  func testComparisonRejectsPrivateOwnerPayloadAndExcludesRequestsAndBlocks() throws {
    let owner = try profile(), friend = try profile(), incoming = try profile(), blocked = try profile()
    let value = ConnectionsSnapshot(connections: [(friend, RemoteConnectionRelation.friend),
      (incoming, .incomingRequest), (blocked, .friend)].map {
        .init(id: $0.0.id, profile: $0.0, relation: $0.1, updatedAt: .init(timeIntervalSince1970: 0))
      }, blockedProfiles: [blocked], ownerProfile: owner)
    try value.validate(ownerID: owner.id)
    XCTAssertEqual(FriendComparisonPolicy.rows(value, sort: []).map(\.id), [friend.id, owner.id])
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(owner)) as? [String: Any])
    json["accountStreakClaim"] = ["version": 1, "lastResultMilliseconds": 1_800_000_000_000]
    let privateOwner = try JSONDecoder().decode(RemotePublicProfile.self, from: JSONSerialization.data(withJSONObject: json))
    XCTAssertThrowsError(try snapshot([], owner: privateOwner).validate(ownerID: owner.id))
    let alpha = try profile(name: "Alpha"), zulu = try profile(name: "Zulu")
    let sorted = FriendComparisonPolicy.rows(snapshot([zulu, alpha]), sort: [
      .init(column: .experience, descending: true), .init(column: .name, descending: false)])
    XCTAssertEqual(sorted.map(\.id), [alpha.id, zulu.id])
  }

  func testCompletionAndStreakPreserveSourceEdgeCasesWithoutUnsafeDefaults() {
    XCTAssertEqual(FriendComparisonPolicy.streak(nil), "—")
    XCTAssertEqual(FriendComparisonPolicy.streak(1), "—")
    XCTAssertEqual(FriendComparisonPolicy.streak(0), "0 天")
    XCTAssertEqual(FriendComparisonPolicy.streak(2), "2 天")
    XCTAssertEqual(FriendComparisonPolicy.ratio(completed: 2, started: 3), "完成 66% · 每次完成对应重启 0.5 次")
    XCTAssertEqual(FriendComparisonPolicy.ratio(completed: 0, started: 3), "完成 0% · 每次完成对应重启 ∞ 次")
    XCTAssertEqual(FriendComparisonPolicy.ratio(completed: 0, started: 0), "完成比例未知")
  }

  func testPinnedFriendReducersAndFormattingOnOwnedInputs() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else { throw XCTSkip("Readiness supplies pinned reference") }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = .init(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-friend-comparison.mjs").path, reference, "--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile(), diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0, String(decoding: diagnostics, as: UTF8.self))
    struct Fixture: Decodable { let profile: RemotePublicProfile; let top15: UUID?; let top60: UUID? }
    let fixtures = try JSONDecoder().decode([Fixture].self, from: data)
    XCTAssertEqual(fixtures.count, 18)
    for fixture in fixtures {
      let row = FriendComparisonRow(profile: fixture.profile, connectedAt: nil, isOwner: false)
      XCTAssertEqual(row.best(seconds: 15)?.id, fixture.top15)
      XCTAssertEqual(row.best(seconds: 60)?.id, fixture.top60)
    }
  }
}
