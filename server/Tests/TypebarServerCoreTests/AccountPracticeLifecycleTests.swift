import Foundation
import XCTest
@testable import TypebarServerCore

final class AccountPracticeLifecycleTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private let password = "a secure password"
  private func account(_ store: AuthStore) async throws -> AuthSessionResponse {
    try await store.register(.init(email: "practice@example.com", password: password,
      displayName: "Practice"), now: now)
  }
  private func directory() throws -> URL {
    let value = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-practice-\(UUID())")
    try FileManager.default.createDirectory(at: value, withIntermediateDirectories: false)
    return value
  }
  private func request(id: UUID = UUID(), endingAt end: Date? = nil, restarts: Int = 0)
    -> ResultSubmissionRequest {
    let end = end ?? now
    return .init(id: id, mode: "words", language: "english", durationSeconds: nil,
      wordLimit: 25, wpm: 60, rawWpm: 60, accuracy: 100, errorCount: 0, eventCount: 75,
      restartCount: restarts,
      experienceEvidence: .init(characterCounts: [75,0,0,0], scoringUnitBasis: .utf16,
        durationSeconds: 15, afkSeconds: 2.25, punctuation: false, numbers: false, modifiers: []),
      practiceTiming: .init(version: 1, terminalEngagedMilliseconds: 12_750,
        priorAttemptEngagedMilliseconds: restarts == 0 ? 0 : 1_500),
      inputMetrics: .init(version: 1, correctAttempts: 75, totalAttempts: 75,
        creditedUnits: 75, retainedUnits: 75), startedAt: end.addingTimeInterval(-15), finishedAt: end)
  }
  func testHistoryDeletionRetainsCountersActivityStreakAndWeeklyEligibility() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4, minimumLeaderboardTypingSeconds: 10)
    let owner = try await account(store), input = request(restarts: 1)
    _ = try await store.submitResult(request(), accessToken: owner.accessToken, now: now)
    _ = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    let before = try await store.publicProfile(id: owner.user.id, now: now)
    _ = try await store.deleteResults(.init(currentPassword: password), accessToken: owner.accessToken, now: now)
    _ = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    let after = try await store.publicProfile(id: owner.user.id, now: now)
    XCTAssertEqual(after.completedResultCount, before.completedResultCount)
    XCTAssertEqual(after.startedTestCount, before.startedTestCount)
    XCTAssertEqual(after.totalTypingSeconds, before.totalTypingSeconds)
    XCTAssertEqual(after.activity, before.activity)
    XCTAssertEqual(after.streak, before.streak)
    let board = try await store.experienceLeaderboard(now: now)
    XCTAssertEqual(board.entries.count, 1)
    let page = try await store.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    XCTAssertEqual(page.total, 0)
  }
  func testActivityUsesSubmissionDayAndSourceSparse372DayProjection() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4), owner = try await account(store)
    for back in [1, 2] {
      _ = try await store.submitResult(request(endingAt: now.addingTimeInterval(-Double(back) * 86_400)),
        accessToken: owner.accessToken, now: now)
    }
    let profile = try await store.publicProfile(id: owner.user.id, now: now)
    XCTAssertEqual(profile.activity?.testsByDays.count, 372)
    XCTAssertEqual(profile.activity?.testsByDays.last, 2)
    XCTAssertEqual(profile.streak, .init(currentDays: 1, longestDays: 1))
  }
  func testStreakReadDoesNotResetBeforeNextResultAndActivityVisibilityDoesNotHideStreak() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4), owner = try await account(store)
    _ = try await store.submitResult(request(), accessToken: owner.accessToken, now: now)
    _ = try await store.updateProfile(.init(profileDetails: .init(showActivity: false)), accessToken: owner.accessToken, now: now)
    let profile = try await store.publicProfile(id: owner.user.id, now: now.addingTimeInterval(3 * 86_400))
    XCTAssertNil(profile.activity)
    XCTAssertEqual(profile.streak, .init(currentDays: 1, longestDays: 1))
  }
  func testDeletionAndReloadPreserveLifetimeAndNeverReawardRetries() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("store.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4), owner = try await account(store), input = request(restarts: 2)
    _ = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    let before = try await store.publicProfile(id: owner.user.id, now: now)
    XCTAssertEqual(before.totalTypingSeconds, 14.25)
    XCTAssertEqual(before.startedTestCount, 3)
    XCTAssertEqual(before.practiceHistoryComplete, true)
    _ = try await store.deleteResults(.init(currentPassword: password), accessToken: owner.accessToken, now: now)
    let reloaded = try AuthStore(fileURL: file, bcryptCost: 4)
    _ = try await reloaded.submitResult(input, accessToken: owner.accessToken, now: now)
    let after = try await reloaded.publicProfile(id: owner.user.id, now: now)
    XCTAssertEqual(after.completedResultCount, 1)
    XCTAssertEqual(after.startedTestCount, 3)
    XCTAssertEqual(after.totalTypingSeconds, 14.25)
    XCTAssertEqual(after.activity, before.activity)
    XCTAssertEqual(after.streak, before.streak)
  }
  func testSubmissionStreakTimestampUsesSourceWholeSecondAdmissionClock() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("store.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4), owner = try await account(store)
    let fractional = now.addingTimeInterval(0.875)
    _ = try await store.submitResult(request(endingAt: fractional), accessToken: owner.accessToken, now: fractional)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    let entries = try XCTUnwrap(json["accountPractice"] as? [Any])
    let record = try XCTUnwrap(entries[1] as? [String: Any])
    XCTAssertEqual(record["lastResultMilliseconds"] as? Double, now.timeIntervalSince1970 * 1_000)
  }
  func testMissingLegacyStateMigratesOnlyKnownEvidenceWithoutWritingOnLoad() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("store.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4), owner = try await account(store)
    _ = try await store.submitResult(request(restarts: 1), accessToken: owner.accessToken, now: now)
    _ = try await store.deleteResults(.init(currentPassword: password), accessToken: owner.accessToken, now: now)
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    json.removeValue(forKey: "accountPractice")
    let legacy = try JSONSerialization.data(withJSONObject: json); try legacy.write(to: file, options: .atomic)
    let reloaded = try AuthStore(fileURL: file, bcryptCost: 4)
    let profile = try await reloaded.publicProfile(id: owner.user.id, now: now)
    XCTAssertEqual(profile.completedResultCount, 1)
    XCTAssertEqual(profile.startedTestCount, 2)
    XCTAssertEqual(profile.totalTypingSeconds, 14.25, "Frozen report can recover measured time, not unknown reports")
    XCTAssertEqual(profile.practiceHistoryComplete, false)
    XCTAssertEqual(try Data(contentsOf: file), legacy)
    _ = try await reloaded.submitResult(request(), accessToken: owner.accessToken, now: now)
    let again = try AuthStore(fileURL: file, bcryptCost: 4)
    let saved = try await again.publicProfile(id: owner.user.id, now: now)
    XCTAssertEqual(saved.completedResultCount, 2)
    XCTAssertEqual(saved.practiceHistoryComplete, false)
  }
  func testLegacyTombstoneWithoutTimeIsDisclosedAsIncompleteNotGuessedFromXP() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("store.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4, experienceConfiguration: nil), owner = try await account(store)
    _ = try await store.submitResult(request(), accessToken: owner.accessToken, now: now)
    _ = try await store.deleteResults(.init(currentPassword: password), accessToken: owner.accessToken, now: now)
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    json.removeValue(forKey: "accountPractice")
    try JSONSerialization.data(withJSONObject: json).write(to: file, options: .atomic)
    let reloaded = try AuthStore(fileURL: file, bcryptCost: 4), profile = try await reloaded.publicProfile(id: owner.user.id, now: now)
    XCTAssertEqual(profile.completedResultCount, 1); XCTAssertEqual(profile.totalTypingSeconds, 0)
    XCTAssertEqual(profile.practiceHistoryComplete, false)
  }
  func testMalformedExplicitStateRejectsReloadWithoutReplacingBytes() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("store.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4), owner = try await account(store)
    _ = try await store.submitResult(request(), accessToken: owner.accessToken, now: now)
    let original = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    for mutation in 0..<12 {
      var json = original
      var entries = try XCTUnwrap(json["accountPractice"] as? [Any])
      var record = try XCTUnwrap(entries[1] as? [String: Any])
      switch mutation {
      case 0: json["accountPractice"] = NSNull()
      case 1: record["version"] = 2
      case 2: record["completedTests"] = 0
      case 3: record["startedTests"] = Int.max
      case 4: record["typingSeconds"] = -1
      case 5: record["activityByYear"] = ["2027": [2]]
      case 6: record["activityByYear"] = ["2027": [1, NSNull()]]
      case 7: entries[0] = UUID().uuidString
      case 8: record["maximumStreakLength"] = -1
      case 9: entries += entries
      case 10: record["activityByYear"] = ["2027": [1]]
      case 11: record["typingSeconds"] = 0
      default: break
      }
      if mutation != 0 { entries[1] = record; json["accountPractice"] = entries }
      let bad = try JSONSerialization.data(withJSONObject: json); try bad.write(to: file, options: .atomic)
      XCTAssertThrowsError(try AuthStore(fileURL: file, bcryptCost: 4), "Mutation \(mutation)")
      XCTAssertEqual(try Data(contentsOf: file), bad)
    }
  }
  func testActualWriteFailureRollsBackPracticeAndRetryCountsExactlyOnce() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("store.json"), backup = dir.appendingPathComponent("backup.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4), owner = try await account(store), input = request()
    try FileManager.default.moveItem(at: file, to: backup)
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
    do { _ = try await store.submitResult(input, accessToken: owner.accessToken, now: now); XCTFail("Write must fail") } catch { }
    let failed = try await store.publicProfile(id: owner.user.id, now: now)
    XCTAssertEqual(failed.completedResultCount, 0); XCTAssertEqual(failed.startedTestCount, 0)
    XCTAssertEqual(failed.totalTypingSeconds, 0); XCTAssertNil(failed.activity)
    try FileManager.default.removeItem(at: file); try FileManager.default.moveItem(at: backup, to: file)
    _ = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    _ = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    let reloaded = try AuthStore(fileURL: file, bcryptCost: 4), saved = try await reloaded.publicProfile(id: owner.user.id, now: now)
    XCTAssertEqual(saved.completedResultCount, 1); XCTAssertEqual(saved.totalTypingSeconds, 12.75)
  }
  func testGapResetsOnlyOnSubmissionAndOffsetSetterPreservesStreakLength() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4), owner = try await account(store)
    _ = try await store.submitResult(request(), accessToken: owner.accessToken, now: now)
    let next = now.addingTimeInterval(86_400)
    let token = try await store.login(.init(email: "practice@example.com", password: password), now: next)
    _ = try await store.submitResult(request(endingAt: next), accessToken: token.accessToken, now: next)
    _ = try await store.setStreakDayBoundary(.init(offsetHours: 0.5), accessToken: token.accessToken, now: next)
    let before = try await store.publicProfile(id: owner.user.id, now: next)
    XCTAssertEqual(before.streak, .init(currentDays: 2, longestDays: 2))
    XCTAssertEqual(before.activity?.dayBoundaryOffsetHours, 0)
    let later = next.addingTimeInterval(3 * 86_400)
    let laterToken = try await store.login(.init(email: "practice@example.com", password: password), now: later)
    let idle = try await store.publicProfile(id: owner.user.id, now: later)
    XCTAssertEqual(idle.streak, before.streak)
    _ = try await store.submitResult(request(endingAt: later), accessToken: laterToken.accessToken, now: later)
    let after = try await store.publicProfile(id: owner.user.id, now: later)
    XCTAssertEqual(after.streak, .init(currentDays: 1, longestDays: 2))
  }
  func testBoundaryCandidateValidationFailureDoesNotConsumeTheOneTimeChoice() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("store.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4), owner = try await account(store)
    let before = try Data(contentsOf: file)
    do {
      _ = try await store.setStreakDayBoundary(.init(offsetHours: 0.5), accessToken: owner.accessToken,
        now: Date(timeIntervalSince1970: -1))
      XCTFail("Out-of-envelope clock must reject the candidate")
    } catch let error as ExperienceCalculationError { XCTAssertEqual(error, .invalidInput) }
    let user = try await store.authenticatedUser(for: owner.accessToken, now: now)
    XCTAssertNil(user.streakDayBoundaryOffsetHours)
    XCTAssertEqual(try Data(contentsOf: file), before)
    let saved = try await store.setStreakDayBoundary(.init(offsetHours: 0.5), accessToken: owner.accessToken, now: now)
    XCTAssertEqual(saved.streakDayBoundaryOffsetHours, 0.5)
  }
  func testAccountResetAndDeletionRemoveLifetimeState() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("store.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4), owner = try await account(store)
    _ = try await store.submitResult(request(), accessToken: owner.accessToken, now: now)
    _ = try await store.resetAccount(.init(currentPassword: password), accessToken: owner.accessToken, now: now)
    let reloaded = try AuthStore(fileURL: file, bcryptCost: 4), reset = try await reloaded.publicProfile(id: owner.user.id, now: now)
    XCTAssertEqual(reset.completedResultCount, 0); XCTAssertEqual(reset.startedTestCount, 0)
    XCTAssertEqual(reset.totalTypingSeconds, 0); XCTAssertEqual(reset.practiceHistoryComplete, true)
    XCTAssertEqual(reset.streak, .init(currentDays: 0, longestDays: 0)); XCTAssertNil(reset.activity)
    try await reloaded.deleteAccount(.init(currentPassword: password), accessToken: owner.accessToken, now: now)
    XCTAssertNoThrow(try AuthStore(fileURL: file, bcryptCost: 4))
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    XCTAssertEqual((json["accountPractice"] as? [Any])?.count, 0)
  }
}
