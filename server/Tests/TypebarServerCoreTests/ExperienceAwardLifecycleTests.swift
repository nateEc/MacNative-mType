import Foundation
import XCTest
import XCTVapor
@testable import TypebarServerCore

final class ExperienceAwardLifecycleTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private let password = "a secure password"
  private func request(evidence: Bool = true, id: UUID = UUID(), endingAt end: Date? = nil)
    -> ResultSubmissionRequest {
    let end = end ?? now
    return .init(id: id, mode: "words", language: "english", durationSeconds: nil,
      wordLimit: 25, wpm: 60, rawWpm: 60, accuracy: 100, errorCount: 0, eventCount: 75,
      experienceEvidence: evidence ? .init(characterCounts: [75,0,0,0], scoringUnitBasis: .utf16,
        durationSeconds: 15, afkSeconds: 2.25, punctuation: true, numbers: true,
        modifiers: ["mirrorVisual"]) : nil,
      practiceTiming: .init(version: 1, terminalEngagedMilliseconds: 12_750,
        priorAttemptEngagedMilliseconds: 0),
      inputMetrics: .init(version: 1, correctAttempts: 75, totalAttempts: 75,
        creditedUnits: 75, retainedUnits: 75), startedAt: end.addingTimeInterval(-15), finishedAt: end)
  }
  private func account(_ store: AuthStore) async throws -> AuthSessionResponse {
    try await store.register(.init(email: "award@example.com", password: password,
      displayName: "Award"), now: now)
  }
  private func config(gain: Double = 1, funbox: Double = 0, daily: Double = 0,
    streak: Bool = false) -> ExperienceCalculationConfiguration {
    .init(enabled: true, gainMultiplier: gain, funboxBonus: funbox,
      minimumDailyBonus: daily, maximumDailyBonus: daily, streakEnabled: streak,
      maximumStreakDays: 10, maximumStreakMultiplier: 1)
  }
  private func directory() throws -> URL {
    let value = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-awards-\(UUID())")
    try FileManager.default.createDirectory(at: value, withIntermediateDirectories: false)
    return value
  }
  private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
  }
  private func changed(_ request: ResultSubmissionRequest,
    _ edit: (inout [String: Any]) -> Void) throws -> ResultSubmissionRequest {
    var json = try object(request); edit(&json)
    return try JSONDecoder().decode(ResultSubmissionRequest.self,
      from: JSONSerialization.data(withJSONObject: json))
  }
  func testProductionSubmissionUsesValidatedCompleteEvidence() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4), owner = try await account(store)
    let receipt = try await store.submitResult(request(), accessToken: owner.accessToken, now: now)
    XCTAssertEqual(receipt.experienceGained, 52)
    XCTAssertEqual(receipt.totalExperience, 52)
    XCTAssertEqual(receipt.dailyXpBonus, false)
    XCTAssertEqual(receipt.xpBreakdown, ["base":26,"fullAccuracy":13,"punctuation":10,"numbers":3,"accPenalty":0])
  }
  func testDeletingResultsDoesNotDeleteLifetimeExperienceOrReawardAnID() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4), owner = try await account(store)
    let input = request(evidence: false)
    let first = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    _ = try await store.deleteResults(.init(currentPassword: password), accessToken: owner.accessToken, now: now)
    let afterDelete = try await store.authenticatedUser(for: owner.accessToken, now: now)
    XCTAssertEqual(afterDelete.totalExperience, first.totalExperience)
    let repeated = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    XCTAssertEqual(repeated.totalExperience, first.totalExperience)
    let history = try await store.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    XCTAssertEqual(history.total, 0, "Reward tombstones cannot resurrect deleted history")
  }

  func testAuthoritativeModifierAndEachPriorAttemptReachProductionAward() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4, experienceConfiguration: config(funbox: 0.1))
    let owner = try await account(store)
    let input = try changed(request()) {
      $0["restartCount"] = 1
      $0["incompletePractice"] = ["version":1,"attempts":[["accuracy":100,"seconds":1.5]]]
      $0["practiceTiming"] = ["version":1,"terminalEngagedMilliseconds":12_750,"priorAttemptEngagedMilliseconds":1_500]
    }
    let receipt = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    XCTAssertEqual(receipt.experienceGained, 62)
    XCTAssertEqual(receipt.xpBreakdown?["funbox"], 8)
    XCTAssertEqual(receipt.xpBreakdown?["incomplete"], 2)
    let stats = await store.publicPracticeStats(); XCTAssertEqual(stats.startedTestCount, 2)
  }

  func testFractionalDailyRewardAndIntegralAccountCreditStaySeparateAfterReload() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("store.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4, experienceConfiguration: config(daily: 0.5))
    let owner = try await account(store)
    _ = try await store.submitResult(request(evidence: false, endingAt: now.addingTimeInterval(-86_400)),
      accessToken: owner.accessToken, now: now.addingTimeInterval(-86_400))
    let input = request()
    let receipt = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    XCTAssertEqual(receipt.experienceGained, 52.5); XCTAssertEqual(receipt.totalExperience, 70)
    XCTAssertEqual(receipt.dailyXpBonus, true); XCTAssertEqual(receipt.xpBreakdown?["daily"], 0.5)
    let page = try await store.experienceLeaderboard(now: now)
    XCTAssertEqual(page.entries.first?.totalExperience, 52, "Public score projects the qualified fractional award only")
    let reloaded = try AuthStore(fileURL: file, bcryptCost: 4, experienceConfiguration: config(gain: 100))
    let repeated = try await reloaded.submitResult(input, accessToken: owner.accessToken, now: now)
    XCTAssertEqual(repeated, receipt, "New configuration must never reprice an accepted reward")
    let second = try await reloaded.submitResult(request(), accessToken: owner.accessToken, now: now)
    XCTAssertEqual(second.experienceGained, 5_200)
    XCTAssertEqual(second.totalExperience, 5_270)
    let after = try await reloaded.submitResult(input, accessToken: owner.accessToken, now: now)
    XCTAssertEqual(after.experienceGained, 52.5); XCTAssertEqual(after.totalExperience, 5_270)
    XCTAssertEqual(after.xpBreakdown, receipt.xpBreakdown)
  }

  func testServerTimestampAndStreakContextIgnoreClientBackdating() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("store.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4, experienceConfiguration: config(daily: 0.5, streak: true))
    let owner = try await account(store)
    let first = try await store.submitResult(request(endingAt: now.addingTimeInterval(-3 * 86_400)),
      accessToken: owner.accessToken, now: now)
    XCTAssertEqual(first.experienceGained, 55); XCTAssertEqual(first.dailyXpBonus, false)
    let day2 = now.addingTimeInterval(86_400)
    // Keep the login token alive through the normal refresh operation.
    let session = try await store.login(.init(email: "award@example.com", password: password), now: day2)
    let second = try await store.submitResult(request(endingAt: now.addingTimeInterval(-3 * 86_400)),
      accessToken: session.accessToken, now: day2)
    XCTAssertEqual(second.experienceGained, 57.5); XCTAssertEqual(second.xpBreakdown?["streak"], 5)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    let entries = try XCTUnwrap(json["experienceAwards"] as? [[String: Any]])
    let context = try XCTUnwrap(entries.last?["context"] as? [String: Any])
    XCTAssertEqual(context["nowMilliseconds"] as? Double, day2.timeIntervalSince1970 * 1_000)
    XCTAssertEqual(context["previousResultMilliseconds"] as? Double, now.timeIntervalSince1970 * 1_000)
    XCTAssertEqual(context["streakDays"] as? Double, 2)
  }

  func testDisabledAndZenAwardsHaveZeroCreditAndControllerDefaultMetadata() async throws {
    for zen in [false, true] {
      let disabled = ExperienceCalculationConfiguration(enabled: false, gainMultiplier: 0, funboxBonus: 0,
        minimumDailyBonus: 0, maximumDailyBonus: 0, streakEnabled: false, maximumStreakDays: 0, maximumStreakMultiplier: 0)
      let store = try AuthStore(fileURL: nil, bcryptCost: 4, experienceConfiguration: zen ? config() : disabled)
      let owner = try await account(store)
      let input = zen ? try changed(request()) { $0["mode"] = "zen"; $0.removeValue(forKey: "wordLimit") } : request()
      let receipt = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
      XCTAssertEqual(receipt.experienceGained, 0); XCTAssertEqual(receipt.totalExperience, 0)
      XCTAssertEqual(receipt.dailyXpBonus, false); XCTAssertEqual(receipt.xpBreakdown, [:])
    }
  }

  func testLegacyFileLoadDoesNotWriteOrRecomputeWithNewFormula() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("store.json")
    let old = try AuthStore(fileURL: file, bcryptCost: 4, experienceConfiguration: nil)
    let owner = try await account(old), input = request()
    _ = try await old.submitResult(input, accessToken: owner.accessToken, now: now)
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    json.removeValue(forKey: "experienceAwards")
    json.removeValue(forKey: "weeklyExperienceCache")
    let bytes = try JSONSerialization.data(withJSONObject: json); try bytes.write(to: file, options: .atomic)
    let new = try AuthStore(fileURL: file, bcryptCost: 4, experienceConfiguration: config(gain: 100))
    XCTAssertEqual(try Data(contentsOf: file), bytes, "Loading must not mutate the old backup")
    let duplicate = try await new.submitResult(input, accessToken: owner.accessToken, now: now)
    XCTAssertEqual(duplicate.experienceGained, 18); XCTAssertEqual(duplicate.totalExperience, 18)
    XCTAssertNil(duplicate.xpBreakdown); XCTAssertEqual(try Data(contentsOf: file), bytes)
    let fresh = try await new.submitResult(request(), accessToken: owner.accessToken, now: now)
    XCTAssertEqual(fresh.experienceGained, 5_200); XCTAssertEqual(fresh.totalExperience, 5_218)
    let reload = try AuthStore(fileURL: file, bcryptCost: 4)
    let preserved = try await reload.submitResult(input, accessToken: owner.accessToken, now: now)
    XCTAssertEqual(preserved.experienceGained, 18); XCTAssertEqual(preserved.totalExperience, 5_218)
  }

  func testBadExplicitLedgerRefusesReloadWithoutChangingBytes() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("store.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4), owner = try await account(store)
    _ = try await store.submitResult(request(), accessToken: owner.accessToken, now: now)
    let original = try Data(contentsOf: file)
    for mutation in 0..<11 {
      var json = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
      var entries = try XCTUnwrap(json["experienceAwards"] as? [[String: Any]])
      switch mutation {
      case 0: entries[0]["version"] = 99
      case 1: entries[0]["accountCredit"] = -1
      case 2: entries[0]["accountCredit"] = 53
      case 3: entries.append(entries[0])
      case 4: entries[0]["userID"] = UUID().uuidString
      case 5: entries[0].removeValue(forKey: "context")
      case 6: entries[0]["award"] = ["xp":-1]
      case 7: entries = []
      case 9:
        var results = try XCTUnwrap(json["results"] as? [[String: Any]])
        results[0]["rawWpm"] = Int.max; json["results"] = results
      case 10:
        var results = try XCTUnwrap(json["results"] as? [[String: Any]])
        var evidence = try XCTUnwrap(results[0]["experienceEvidence"] as? [String: Any])
        evidence["punctuation"] = false; results[0]["experienceEvidence"] = evidence; json["results"] = results
      default: break
      }
      json["experienceAwards"] = mutation == 8 ? NSNull() : entries as Any
      let bad = try JSONSerialization.data(withJSONObject: json); try bad.write(to: file, options: .atomic)
      XCTAssertThrowsError(try AuthStore(fileURL: file, bcryptCost: 4))
      XCTAssertEqual(try Data(contentsOf: file), bad)
    }
  }

  func testValidChangedDuplicateNeverReplacesFirstRewardOrReport() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4), owner = try await account(store), input = request()
    let first = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    let different = try changed(input) {
      var report = $0["experienceEvidence"] as! [String: Any]
      report["punctuation"] = false; report["numbers"] = false; report["modifiers"] = ["noQuit"]
      $0["experienceEvidence"] = report
    }
    let repeated = try await store.submitResult(different, accessToken: owner.accessToken, now: now)
    XCTAssertEqual(repeated, first)
    let history = try await store.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    XCTAssertEqual(history.results.first?.experienceEvidence, input.experienceEvidence)
  }

  func testInfiniteTimeAndWordsBailoutRewardsReloadWithoutRejectingZeroLimits() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("store.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4), owner = try await account(store)
    for (mode, limit, evidence) in ["time", "words"].flatMap({ mode in
      [0, 9_007_199_254_740_991].flatMap { limit in [true, false].map { (mode, limit, $0) } }
    }) {
      let input = try changed(request(evidence: evidence)) {
        $0["mode"] = mode; $0["bailedOut"] = true
        $0.removeValue(forKey: "durationSeconds"); $0.removeValue(forKey: "wordLimit")
        $0[mode == "time" ? "durationSeconds" : "wordLimit"] = limit
      }
      let first = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
      XCTAssertEqual(first.experienceGained, evidence ? 52 : 18)
      let reload = try AuthStore(fileURL: file, bcryptCost: 4)
      let repeated = try await reload.submitResult(input, accessToken: owner.accessToken, now: now)
      XCTAssertEqual(repeated, first)
    }
  }

  func testActualPersistenceFailureRollsBackRewardAndRetryAwardsOnce() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("store.json"), backup = dir.appendingPathComponent("backup.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4), owner = try await account(store), input = request()
    try FileManager.default.moveItem(at: file, to: backup)
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
    do { _ = try await store.submitResult(input, accessToken: owner.accessToken, now: now); XCTFail("Rename must fail") }
    catch { }
    let after = try await store.authenticatedUser(for: owner.accessToken, now: now)
    XCTAssertEqual(after.totalExperience, 0)
    let history = try await store.results(.init(), credential: .accessToken(owner.accessToken), now: now)
    XCTAssertEqual(history.total, 0)
    let stats = await store.publicPracticeStats(); XCTAssertEqual(stats.startedTestCount, 0)
    try FileManager.default.removeItem(at: file); try FileManager.default.moveItem(at: backup, to: file)
    let accepted = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    XCTAssertEqual(accepted.totalExperience, 52)
    let reload = try AuthStore(fileURL: file, bcryptCost: 4)
    let repeated = try await reload.submitResult(input, accessToken: owner.accessToken, now: now)
    XCTAssertEqual(repeated, accepted)
  }

  func testConcurrentDuplicatesAreAccountScopedAndAwardExactlyOnce() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4), owner = try await account(store), input = request()
    let instant = now
    async let a = store.submitResult(input, accessToken: owner.accessToken, now: instant)
    async let b = store.submitResult(input, accessToken: owner.accessToken, now: instant)
    let receipts = try await [a,b]
    XCTAssertEqual(receipts[0], receipts[1]); XCTAssertEqual(receipts[0].totalExperience, 52)
    let other = try await store.register(.init(email: "other@example.com", password: password, displayName: "Other"), now: now)
    let independent = try await store.submitResult(input, accessToken: other.accessToken, now: now)
    XCTAssertEqual(independent.totalExperience, 52)
    let stats = await store.publicPracticeStats(); XCTAssertEqual(stats.startedTestCount, 2)
  }

  func testExplicitAccountResetClearsRewardTombstones() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("store.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4), owner = try await account(store), input = request()
    _ = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    let reset = try await store.resetAccount(.init(currentPassword: password), accessToken: owner.accessToken, now: now)
    XCTAssertEqual(reset.totalExperience, 0)
    let reload = try AuthStore(fileURL: file, bcryptCost: 4)
    let fresh = try await reload.submitResult(input, accessToken: owner.accessToken, now: now)
    XCTAssertEqual(fresh.experienceGained, 52); XCTAssertEqual(fresh.totalExperience, 52)
  }

  func testPinnedNumericLongCreditBoundariesDoNotTruncateTheReward() throws {
    for (xp, credit): (Double, Int) in [(0.5,0), (52.5,52), (2_147_483_648.75,2_147_483_648),
      (4_294_967_295.75,4_294_967_295), (4_294_967_296,0), (4_294_967_297.75,1), (9_007_199_254_740_991,4_294_967_295)] {
      XCTAssertEqual(try ExperienceAwardRecord.sourceAccountCredit(xp), credit)
    }
    for xp in [-1, Double.nan, .infinity, 9_007_199_254_740_992] {
      XCTAssertThrowsError(try ExperienceAwardRecord.sourceAccountCredit(xp))
    }
  }

  func testLongLowWordCreditIsUsedByActualSubmissionNotJustHelper() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4,
      experienceConfiguration: config(gain: 4_294_967_297 / 52.0, daily: 0.75))
    let owner = try await account(store)
    _ = try await store.submitResult(request(evidence: false, endingAt: now.addingTimeInterval(-86_400)),
      accessToken: owner.accessToken, now: now.addingTimeInterval(-86_400))
    let receipt = try await store.submitResult(request(), accessToken: owner.accessToken, now: now)
    XCTAssertEqual(receipt.experienceGained, 4_294_967_297.75)
    XCTAssertEqual(receipt.totalExperience, 19)
    let page = try await store.experienceLeaderboard(now: now)
    XCTAssertEqual(page.entries.first?.totalExperience, 4_294_967_297)
  }

  func testDeletionReloadPreservesStreakButClearsPreviousResultDailyContext() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("store.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4, experienceConfiguration: config(daily: 0.5, streak: true))
    let owner = try await account(store), input = request()
    let first = try await store.submitResult(input, accessToken: owner.accessToken, now: now)
    _ = try await store.deleteResults(.init(currentPassword: password), accessToken: owner.accessToken, now: now)
    let reload = try AuthStore(fileURL: file, bcryptCost: 4, experienceConfiguration: config(daily: 0.5, streak: true))
    let retry = try await reload.submitResult(input, accessToken: owner.accessToken, now: now)
    XCTAssertEqual(retry.totalExperience, first.totalExperience)
    let day2 = now.addingTimeInterval(86_400)
    let session = try await reload.login(.init(email: "award@example.com", password: password), now: day2)
    let receipt = try await reload.submitResult(request(endingAt: day2), accessToken: session.accessToken, now: day2)
    XCTAssertEqual(receipt.experienceGained, 57); XCTAssertEqual(receipt.totalExperience, 112)
    XCTAssertEqual(receipt.dailyXpBonus, false); XCTAssertNil(receipt.xpBreakdown?["daily"])
    XCTAssertEqual(receipt.xpBreakdown?["streak"], 5)
  }

  func testAccountDeletionRemovesLedgerWithoutLeavingOrphanRewards() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("store.json")
    let store = try AuthStore(fileURL: file, bcryptCost: 4), owner = try await account(store)
    _ = try await store.submitResult(request(), accessToken: owner.accessToken, now: now)
    try await store.deleteAccount(.init(currentPassword: password), accessToken: owner.accessToken, now: now)
    _ = try AuthStore(fileURL: file, bcryptCost: 4)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    XCTAssertEqual((json["experienceAwards"] as? [Any])?.count, 0)
  }

  func testDeploymentConfigurationIsExplicitStrictAndDefaultsAreOwnChoice() throws {
    XCTAssertEqual(try ExperienceCalculationConfiguration.fromJSON(nil), .typebarDefault)
    XCTAssertEqual(try ExperienceCalculationConfiguration.fromJSON(String(decoding: JSONEncoder().encode(config(daily: 0.5)), as: UTF8.self)), config(daily: 0.5))
    for json in ["null", "{}", "[]", "not JSON"] { XCTAssertThrowsError(try ExperienceCalculationConfiguration.fromJSON(json)) }
    XCTAssertThrowsError(try AuthStore(fileURL: nil, experienceConfiguration: config(gain: -1)))
    XCTAssertThrowsError(try AuthStore(fileURL: nil, experienceConfiguration: config(daily: .infinity)))
  }

  func testActualHTTPReceiptPublishesServerCalculatedAwardAndCapability() async throws {
    let live = Date.now, app = try await Application.make(.testing)
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let owner = try await store.register(.init(email: "route-award@example.com", password: password, displayName: "Route"), now: live)
    let input = request(endingAt: live)
    do {
      try configure(app, authStore: store)
      try await app.test(.GET, "v1/capabilities") { response async throws in
        XCTAssertEqual(try response.content.decode(ServiceCapabilitiesResponse.self).capabilities["resultExperienceAwards"], .available)
      }
      try await app.test(.POST, "v1/results", beforeRequest: { outgoing async throws in
        outgoing.headers.bearerAuthorization = .init(token: owner.accessToken)
        try outgoing.content.encode(input)
      }, afterResponse: { response async throws in
        XCTAssertEqual(response.status, .ok)
        let receipt = try response.content.decode(ResultSubmissionResponse.self)
        XCTAssertEqual(receipt.experienceGained, 52); XCTAssertEqual(receipt.totalExperience, 52)
        XCTAssertEqual(receipt.xpBreakdown?["base"], 26)
      })
      try await app.asyncShutdown()
    } catch { try await app.asyncShutdown(); throw error }
  }
}
