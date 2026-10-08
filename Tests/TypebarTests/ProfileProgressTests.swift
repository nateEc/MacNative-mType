import Foundation
import XCTest
@testable import Typebar

final class ProfileProgressTests: XCTestCase {
  private let day = 86_400_000.0
  private let today = 1_799_971_200_000.0 // 2027-01-15 UTC day boundary.
  private func state(last: Double?, reference: Double? = nil, offset: Double? = nil, now: Double? = nil) -> AccountStreakClaimPresentation {
    .init(claim: .init(lastResultMilliseconds: last, streakReferenceMilliseconds: reference,
      dayBoundaryOffsetHours: offset), now: Date(timeIntervalSince1970: (now ?? today) / 1000))
  }

  func testIntegerLevelThresholdsAndSafeDomain() throws {
    for level in [2, 3, 10, 100, 10_000, 1_000_000, 19_000_000] {
      let steps = level - 1, threshold = steps * 100 + 49 * steps * (steps - 1) / 2
      let before = try XCTUnwrap(ProfileLevelProgress(totalXP: threshold - 1))
      XCTAssertEqual(before.level, level - 1); XCTAssertEqual(before.remainingXP, 1)
      let at = try XCTUnwrap(ProfileLevelProgress(totalXP: threshold))
      XCTAssertEqual(at.level, level); XCTAssertEqual(at.earnedXP, 0)
      XCTAssertEqual(at.requiredXP, 100 + 49 * steps); XCTAssertEqual(at.percentText, "0.00%")
      XCTAssertEqual(ProfileLevelProgress(totalXP: threshold + 1)?.earnedXP, 1)
    }
    XCTAssertEqual(ProfileLevelProgress(totalXP: 0)?.level, 1)
    XCTAssertEqual(ProfileLevelProgress(totalXP: 99)?.percentText, "99.00%")
    XCTAssertEqual(ProfileLevelProgress(totalXP: 249)?.level, 3)
    XCTAssertNil(ProfileLevelProgress(totalXP: -1)); XCTAssertNil(ProfileLevelProgress(totalXP: 9_007_199_254_740_992))
    let maximum = try XCTUnwrap(ProfileLevelProgress(totalXP: 9_007_199_254_740_991))
    XCTAssertGreaterThanOrEqual(maximum.earnedXP, 0); XCTAssertGreaterThan(maximum.remainingXP, 0)
    XCTAssertTrue((0..<1).contains(maximum.fraction))
  }

  func testClaimIsVisibleOnlyInCurrentOwnersAccountOverview() {
    let owner = UUID(), other = UUID()
    for isOverview in [false, true] { for user in [nil, owner, other] {
      XCTAssertEqual(AccountStreakClaimPresentation.isVisible(profileID: owner,
        isAccountOverview: isOverview, userID: user), isOverview && user == owner)
    } }
  }

  func testVersionedClaimRejectsUnsafeValuesAndRoundTripsUnsetVersusExplicitZero() throws {
    for offset in [nil, -11, -0.5, 0, 0.5, 12] as [Double?] {
      let claim = RemoteAccountStreakClaim(lastResultMilliseconds: today, streakReferenceMilliseconds: today,
        dayBoundaryOffsetHours: offset)
      XCTAssertEqual(try JSONDecoder().decode(RemoteAccountStreakClaim.self, from: JSONEncoder().encode(claim)), claim)
    }
    for claim in [RemoteAccountStreakClaim(version: 2, lastResultMilliseconds: nil, streakReferenceMilliseconds: nil, dayBoundaryOffsetHours: nil),
      .init(lastResultMilliseconds: -1, streakReferenceMilliseconds: nil, dayBoundaryOffsetHours: nil),
      .init(lastResultMilliseconds: nil, streakReferenceMilliseconds: 8_640_000_000_000_001, dayBoundaryOffsetHours: nil),
      .init(lastResultMilliseconds: nil, streakReferenceMilliseconds: nil, dayBoundaryOffsetHours: 0.25),
      .init(lastResultMilliseconds: nil, streakReferenceMilliseconds: nil, dayBoundaryOffsetHours: 12.5)] {
      XCTAssertFalse(claim.isValid)
      XCTAssertThrowsError(try JSONDecoder().decode(RemoteAccountStreakClaim.self, from: JSONEncoder().encode(claim)))
    }
    XCTAssertFalse(RemoteAccountStreakClaim(lastResultMilliseconds: .nan, streakReferenceMilliseconds: nil, dayBoundaryOffsetHours: nil).isValid)
  }

  func testOldProfileWithoutClaimRemainsDecodableAndNewMetadataDoesNotChangeProfileIdentity() throws {
    let id = UUID()
    var object: [String: Any] = ["id": id.uuidString, "displayName": "Owned", "joinedAt": 0,
      "completedResultCount": 0, "bestWPM": 0]
    func decode() throws -> RemotePublicProfile {
      try JSONDecoder().decode(RemotePublicProfile.self, from: JSONSerialization.data(withJSONObject: object))
    }
    XCTAssertNil(try decode().accountStreakClaim)
    object["accountStreakClaim"] = ["version": 1, "lastResultMilliseconds": today]
    let profile = try decode()
    XCTAssertEqual(profile.id, id); XCTAssertEqual(profile.accountStreakClaim?.lastResultMilliseconds, today)
    XCTAssertNil(profile.accountStreakClaim?.dayBoundaryOffsetHours)
    object["accountStreakClaim"] = ["version": 99]
    XCTAssertThrowsError(try decode())
  }

  func testClaimTransitionsAtDayBoundaryWithoutRecalculatingStoredStreak() {
    XCTAssertEqual(state(last: today).status, .claimed)
    XCTAssertEqual(state(last: today).hasSavedToday, true)
    XCTAssertEqual(state(last: today, now: today + day - 1).status, .claimed)
    XCTAssertEqual(state(last: today, now: today + day).status, .available)
    XCTAssertEqual(state(last: today, now: today + day).hasSavedToday, false)
    XCTAssertEqual(state(last: today, now: today + 2 * day).status, .expired)
    XCTAssertEqual(state(last: today, now: today + 2 * day).lostAtMilliseconds, today + 2 * day)
    XCTAssertEqual(state(last: today, now: today + 2 * day).nextBoundaryMilliseconds, today + 3 * day)
    for offset in [-11.0, -0.5, 0, 0.5, 12] {
      let boundary = today + offset * 3_600_000
      XCTAssertEqual(state(last: boundary - 1, offset: offset, now: boundary - 1).status, .claimed)
      XCTAssertEqual(state(last: boundary - 1, offset: offset, now: boundary).status, .available)
      XCTAssertEqual(state(last: boundary, offset: offset, now: boundary).nextBoundaryMilliseconds, boundary + day)
    }
  }

  func testDayBoundaryResetIsNotMistakenForASavedResult() {
    let empty = state(last: nil, reference: today, offset: 0)
    XCTAssertEqual(empty.status, .noSavedResult); XCTAssertEqual(empty.hasSavedToday, false)
    XCTAssertTrue(empty.referenceDiffersFromLastSave); XCTAssertNil(empty.lostAtMilliseconds)
    let reset = state(last: today - 3 * day, reference: today, offset: 0.5, now: today + 3_600_000)
    XCTAssertEqual(reset.status, .available); XCTAssertEqual(reset.hasSavedToday, false)
    XCTAssertTrue(reset.referenceDiffersFromLastSave)
    XCTAssertEqual(state(last: nil).status, .noSavedResult)
    XCTAssertEqual(state(last: today, reference: today).referenceDiffersFromLastSave, false)
  }

  func testMissingInvalidAndFutureMetadataDoNotInventClaimState() {
    XCTAssertEqual(AccountStreakClaimPresentation(claim: nil, now: .now).status, .unavailable)
    let future = state(last: today + 1)
    XCTAssertEqual(future.status, .clockMismatch); XCTAssertNil(future.hasSavedToday)
    XCTAssertNil(future.nextBoundaryMilliseconds); XCTAssertNil(future.lostAtMilliseconds)
    XCTAssertEqual(state(last: today, reference: today + 1).status, .clockMismatch)
    XCTAssertEqual(state(last: today, offset: 0.25).status, .unavailable)
    XCTAssertEqual(state(last: today, now: -1).status, .unavailable)
  }

  func testCountdownRoundingClampingAndExpiredElapsedTime() {
    for (value, text) in [(0.0, "0 秒"), (-1, "0 秒"), (1, "1 秒"), (60_001, "1 分钟 1 秒"),
      (3_600_000, "1 小时 0 分钟"), (86_400_000, "1 天 0 小时")] {
      XCTAssertEqual(AccountStreakClaimPresentation.duration(milliseconds: value), text)
    }
    XCTAssertEqual(AccountStreakClaimPresentation.duration(milliseconds: .infinity), "未知")
    let value = state(last: today - 2 * day, now: today + 6 * 3_600_000)
    XCTAssertEqual(value.status, .expired)
    XCTAssertEqual(AccountStreakClaimPresentation.duration(milliseconds: today + 6 * 3_600_000 - (value.lostAtMilliseconds ?? 0)), "6 小时 0 分钟")
  }

  func testNativeProgressAndClaimsAgainstCompletePinnedSourceWithRecordedCorrections() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Readiness supplies pinned reference and date-fns runtime")
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = .init(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-profile-progress.mjs").path, reference, "--emit-fixtures"]
    var environment = ProcessInfo.processInfo.environment; environment["TZ"] = "UTC"; process.environment = environment
    process.standardOutput = output; process.standardError = errors; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile(), diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0, String(decoding: diagnostics, as: UTF8.self))
    struct Fixtures: Decodable {
      struct Level: Decodable {
        struct Expected: Decodable { let level: Int; let earnedXP: Int; let requiredXP: Int }
        struct Actual: Decodable { let level: Int; let levelCurrentXp: Double; let levelMaxXp: Double }
        let xp: Int; let actual: Actual; let expected: Expected
        let totalText: String; let earnedText: String; let requiredText: String
      }
      struct Streak: Decodable { let now: Double; let last: Double; let offset: Double?; let owner: Bool; let state: String; let boundary: Double; let text: String }
      struct Expired: Decodable { let now: Double; let last: Double; let actualText: String; let trueExpiredMilliseconds: Double }
      let referenceCommit: String; let levelFixtures: [Level]; let levelDefects: [Level]
      let streakFixtures: [Streak]; let expiredDefect: Expired
    }
    let fixtures = try JSONDecoder().decode(Fixtures.self, from: data)
    XCTAssertEqual(fixtures.referenceCommit, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(fixtures.levelFixtures.count, 33); XCTAssertEqual(fixtures.streakFixtures.count, 144)
    XCTAssertTrue(fixtures.levelDefects.contains { $0.actual.levelCurrentXp < 0 })
    for fixture in fixtures.levelFixtures {
      let value = try XCTUnwrap(ProfileLevelProgress(totalXP: fixture.xp))
      XCTAssertEqual(value.level, fixture.expected.level); XCTAssertEqual(value.earnedXP, fixture.expected.earnedXP)
      XCTAssertEqual(value.requiredXP, fixture.expected.requiredXP)
      XCTAssertEqual(ExperiencePresentation.compact(value.totalXP), fixture.totalText)
      XCTAssertEqual(ExperiencePresentation.compact(value.earnedXP), fixture.earnedText)
      XCTAssertEqual(ExperiencePresentation.compact(value.requiredXP), fixture.requiredText)
      let differs = value.level != fixture.actual.level || Double(value.earnedXP) != fixture.actual.levelCurrentXp || Double(value.requiredXP) != fixture.actual.levelMaxXp
      XCTAssertEqual(differs, fixtures.levelDefects.contains { $0.xp == fixture.xp })
    }
    let owner = UUID()
    for fixture in fixtures.streakFixtures {
      XCTAssertEqual(AccountStreakClaimPresentation.isVisible(profileID: owner, isAccountOverview: fixture.owner, userID: owner), fixture.owner)
      if !fixture.owner { XCTAssertEqual(fixture.text, ""); continue }
      let value = state(last: fixture.last, offset: fixture.offset, now: fixture.now)
      if fixture.last > fixture.now { XCTAssertEqual(value.status, .clockMismatch); continue }
      let expected: AccountStreakClaimPresentation.Status = fixture.state == "claimed" ? .claimed : fixture.state == "available" ? .available : .expired
      XCTAssertEqual(value.status, expected); XCTAssertEqual(value.nextBoundaryMilliseconds, fixture.boundary)
      XCTAssertEqual(value.hasSavedToday, fixture.state == "claimed")
    }
    let defect = fixtures.expiredDefect, corrected = state(last: defect.last, offset: 0, now: defect.now)
    XCTAssertEqual(defect.now - (corrected.lostAtMilliseconds ?? 0), defect.trueExpiredMilliseconds)
    XCTAssertTrue(defect.actualText.contains("18 hours")); XCTAssertEqual(defect.trueExpiredMilliseconds, 6 * 3_600_000)
  }

  func testProfileProgressAndOwnerClaimHaveRealNativeIntegration() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let profile = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/CloudSyncView.swift"), encoding: .utf8)
    let account = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/RemoteAccount.swift"), encoding: .utf8)
    XCTAssertTrue(profile.contains("ProfileLevelProgressView("))
    XCTAssertTrue(profile.contains("AccountStreakClaimView("))
    XCTAssertTrue(account.contains("accountStreakClaim"))
  }
}
