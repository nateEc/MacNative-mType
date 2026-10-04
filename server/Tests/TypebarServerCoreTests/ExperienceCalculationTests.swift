import Foundation
import XCTest
@testable import TypebarServerCore

final class ExperienceCalculationTests: XCTestCase {
  private func input(mode: String = "time", accuracy: Double = 100, duration: Double = 15,
    afk: Double = 0, counts: [Int] = [100, 0, 0, 0], punctuation: Bool = false,
    numbers: Bool = false, levels: [Double] = [], incomplete: Double? = nil,
    attempts: [ExperienceIncompleteAttempt]? = nil) -> ExperienceCalculationInput {
    .init(mode: mode, accuracy: accuracy, durationSeconds: duration, afkSeconds: afk,
      characterCounts: counts, punctuation: punctuation, numbers: numbers,
      funboxDifficultyLevels: levels, incompleteSeconds: incomplete, incompleteAttempts: attempts)
  }

  // Owned enabled configuration. Never infer the site's live deployment values.
  private func configuration(enabled: Bool = true, gain: Double = 1, funbox: Double = 0,
    minimum: Double = 0, maximum: Double = 0, streak: Bool = false,
    days: Double = 0, streakMultiplier: Double = 0) -> ExperienceCalculationConfiguration {
    .init(enabled: enabled, gainMultiplier: gain, funboxBonus: funbox,
      minimumDailyBonus: minimum, maximumDailyBonus: maximum,
      streakEnabled: streak, maximumStreakDays: days, maximumStreakMultiplier: streakMultiplier)
  }

  private func context(previous: Double? = nil, now: Double = 172_800_000,
    total: Double = 0, streak: Double = 0) -> ExperienceCalculationContext {
    .init(previousResultMilliseconds: previous, nowMilliseconds: now,
      currentTotalXP: total, streakDays: streak)
  }

  private func calculate(_ value: ExperienceCalculationInput? = nil,
    config: ExperienceCalculationConfiguration? = nil,
    account: ExperienceCalculationContext? = nil) throws -> ExperienceCalculationAward {
    try SourceStyleExperienceCalculator.calculate(value ?? input(),
      configuration: config ?? configuration(), context: account ?? context())
  }

  func testReferenceBaselineRequiresEngagedBaseAndFullAccuracyBonus() throws {
    let request = ResultSubmissionRequest(id: UUID(), mode: "time", language: "english",
      durationSeconds: 15, wordLimit: nil, wpm: 80, rawWpm: 80, accuracy: 100,
      errorCount: 0, eventCount: 100, startedAt: Date(timeIntervalSince1970: 0),
      finishedAt: Date(timeIntervalSince1970: 15))
    let award = try calculate()
    XCTAssertEqual(award.xp, 45)
    XCTAssertEqual(award.breakdown, ["base": 30, "fullAccuracy": 15, "accPenalty": 0])
    XCTAssertEqual(award.dailyBonus, false)
    XCTAssertEqual(TypebarExperiencePolicy.points(for: request), 18,
      "Retain the established legacy path until a versioned service cutover exists")
  }

  func testDisabledAndZenOmitBreakdownAndDailyFields() throws {
    for award in [try calculate(config: configuration(enabled: false)),
      try calculate(input(mode: "zen"))] {
      XCTAssertEqual(award, .init(xp: 0, dailyBonus: nil, breakdown: nil))
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(award)) as? [String: Any])
      XCTAssertEqual(Set(json.keys), ["xp"])
    }
  }

  func testEarlyExitDoesNotEvaluateUnusableInputs() throws {
    let unusable = input(accuracy: .nan, duration: .infinity, counts: [])
    XCTAssertEqual(try calculate(unusable, config: configuration(enabled: false)).xp, 0)
    XCTAssertEqual(try calculate(input(mode: "zen", accuracy: .nan)).xp, 0)
  }

  func testAFKIsRemovedBeforeBaseRounding() throws {
    let award = try calculate(input(afk: 2.5))
    XCTAssertEqual(award.xp, 38)
    XCTAssertEqual(award.breakdown, ["base": 25, "fullAccuracy": 13, "accPenalty": 0])
    XCTAssertEqual(try calculate(input(afk: 15)).xp, 0)
  }

  func testCorrectedBonusIsExclusiveWithPerfectAccuracyAndUsesRetainedCounts() throws {
    let corrected = try calculate(input(accuracy: 75))
    XCTAssertEqual(corrected.xp, 19)
    XCTAssertEqual(corrected.breakdown, ["base": 30, "corrected": 8, "accPenalty": 19])
    for counts in [[100, 1, 0, 0], [100, 0, 1, 0], [100, 0, 0, 1]] {
      XCTAssertEqual(try calculate(input(accuracy: 75, counts: counts)).xp, 15)
    }
    let perfect = try calculate(input(counts: [0, 1, 1, 1]))
    XCTAssertEqual(perfect.breakdown?["fullAccuracy"], 15)
    XCTAssertNil(perfect.breakdown?["corrected"])
    XCTAssertNotNil(try calculate(input(accuracy: 99.999)).breakdown?["corrected"])
  }

  func testQuoteExcludesPunctuationAndNumbersBonuses() throws {
    let award = try calculate(input(mode: "quote", punctuation: true, numbers: true))
    XCTAssertEqual(award.xp, 60)
    XCTAssertEqual(award.breakdown, ["base": 30, "fullAccuracy": 15, "quote": 15, "accPenalty": 0])
  }

  func testNonQuoteModifiersAreAdditiveNotCompounded() throws {
    for mode in ["time", "words", "custom"] {
      let award = try calculate(input(mode: mode, punctuation: true, numbers: true))
      XCTAssertEqual(award.xp, 60)
      XCTAssertEqual(award.breakdown, ["base": 30, "fullAccuracy": 15, "punctuation": 12,
        "numbers": 3, "accPenalty": 0])
    }
  }

  func testFunboxBonusClampsEachDifficultyContributionBeforeSumming() throws {
    let award = try calculate(input(levels: [-100, 0, 1, 3]), config: configuration(funbox: 0.1))
    XCTAssertEqual(award.xp, 57)
    XCTAssertEqual(award.breakdown?["funbox"], 12)
    XCTAssertNil(try calculate(input(levels: [0]), config: configuration(funbox: 0.1)).breakdown?["funbox"])
    XCTAssertNil(try calculate(input(levels: [3]), config: configuration(funbox: -1)).breakdown?["funbox"])
  }

  func testStreakUsesExactBinaryDecimalRoundingNotScaledHalfRounding() throws {
    for (value, bonusPoints, total) in [(0.15, 20.0, 320.0), (0.25, 60, 360),
      (1.15, 220, 520), (1.25, 260, 560), (2.55, 500, 800)] {
      let award = try calculate(input(duration: 100), config: configuration(streak: true,
        days: 1, streakMultiplier: value), account: context(streak: 1))
      XCTAssertEqual(award.breakdown?["streak"], bonusPoints)
      XCTAssertEqual(award.xp, total)
    }
  }

  func testStreakClampZeroRangeAndDisabledRules() throws {
    let config = configuration(streak: true, days: 7, streakMultiplier: 1)
    XCTAssertEqual(try calculate(config: config, account: context(streak: 700)).breakdown?["streak"], 30)
    XCTAssertNil(try calculate(config: config, account: context(streak: 0)).breakdown?["streak"])
    XCTAssertNil(try calculate(config: configuration(streak: true, days: 0, streakMultiplier: 1),
      account: context(streak: 7)).breakdown?["streak"])
    XCTAssertNil(try calculate(config: configuration(days: 7, streakMultiplier: 1),
      account: context(streak: 7)).breakdown?["streak"])
    XCTAssertNil(try calculate(config: configuration(streak: true, days: 7, streakMultiplier: -1),
      account: context(streak: 7)).breakdown?["streak"])
  }

  func testIncompleteAttemptsOverrideAggregateAndRoundEachAttempt() throws {
    let attempts = [ExperienceIncompleteAttempt(accuracy: 100, seconds: 1.5),
      .init(accuracy: 75, seconds: 1.5), .init(accuracy: 49, seconds: 20)]
    let award = try calculate(input(accuracy: 75, counts: [100, 1, 0, 0], incomplete: 900, attempts: attempts))
    XCTAssertEqual(award.xp, 18)
    XCTAssertEqual(award.breakdown, ["base": 30, "incomplete": 3, "accPenalty": 15])
    let separate = try calculate(input(attempts: [.init(accuracy: 100, seconds: 0.5),
      .init(accuracy: 100, seconds: 0.5)]))
    XCTAssertEqual(separate.breakdown?["incomplete"], 2)
  }

  func testIncompleteFallbackAndExplicitZeroHaveDifferentBreakdownPresence() throws {
    for attempts: [ExperienceIncompleteAttempt]? in [nil, []] {
      XCTAssertEqual(try calculate(input(incomplete: 1.5, attempts: attempts)).breakdown?["incomplete"], 2)
      XCTAssertNil(try calculate(input(incomplete: 0, attempts: attempts)).breakdown?["incomplete"])
    }
    let award = try calculate(input(incomplete: 100, attempts: [.init(accuracy: 0, seconds: 100)]))
    XCTAssertEqual(award.breakdown?["incomplete"], 0)
  }

  func testFinalAccuracyPenaltyDoesNotAlsoPenalizePriorAttempts() throws {
    let award = try calculate(input(accuracy: 50, incomplete: 10))
    XCTAssertEqual(award.xp, 10)
    XCTAssertEqual(award.breakdown?["accPenalty"], 38)
  }

  func testFirstAndSameDayResultsHaveNoDailyEntryButOtherDaysDo() throws {
    let config = configuration(minimum: 10, maximum: 100)
    XCTAssertNil(try calculate(config: config).breakdown?["daily"])
    for previous in [172_800_000.0, 259_199_999] {
      XCTAssertNil(try calculate(config: config, account: context(previous: previous)).breakdown?["daily"])
    }
    for previous in [172_799_999.0, 259_200_000] {
      let award = try calculate(config: config, account: context(previous: previous, total: 1000))
      XCTAssertEqual(award.xp, 95)
      XCTAssertEqual(award.dailyBonus, true)
      XCTAssertEqual(award.breakdown?["daily"], 50)
    }
  }

  func testDailyMinimumMaximumAndFractionalConfigurationArePreserved() throws {
    for (total, expected) in [(0.0, 10.0), (1000, 50), (1_000_000, 100)] {
      XCTAssertEqual(try calculate(config: configuration(minimum: 10, maximum: 100),
        account: context(previous: 86_400_000, total: total)).breakdown?["daily"], expected)
    }
    XCTAssertEqual(try calculate(config: configuration(minimum: 0.25, maximum: 0.25),
      account: context(previous: 86_400_000)).xp, 45.25)
    XCTAssertEqual(try calculate(config: configuration(minimum: 100, maximum: 10),
      account: context(previous: 86_400_000)).breakdown?["daily"], 100)
  }

  func testPresentZeroDailyBonusIsNotOmittedAndIsNotAwarded() throws {
    let award = try calculate(account: context(previous: 86_400_000))
    XCTAssertEqual(award.breakdown?["daily"], 0)
    XCTAssertEqual(award.dailyBonus, false)
    for previous in [Double.nan, .infinity, -.infinity] {
      XCTAssertNil(try calculate(account: context(previous: previous)).breakdown?["daily"])
    }
  }

  func testDayBoundaryUsesSignedRemainderNotLocalCalendarOrFloor() throws {
    XCTAssertNil(try calculate(account: context(previous: -1, now: 0)).breakdown?["daily"])
    XCTAssertNotNil(try calculate(account: context(previous: -86_400_001, now: 0)).breakdown?["daily"])
  }

  func testGainMultiplierAppliesAfterAccuracyAndPriorAttemptsButBeforeDaily() throws {
    let award = try calculate(input(accuracy: 75, counts: [100, 1, 0, 0], incomplete: 1.5),
      config: configuration(gain: 0.5, minimum: 10, maximum: 100),
      account: context(previous: 86_400_000))
    XCTAssertEqual(award.xp, 19) // round((15 + 2) * 0.5) + 10
    XCTAssertEqual(award.breakdown?["configMultiplier"], 0.5)
    XCTAssertEqual(try calculate(config: configuration(gain: 0, minimum: 10),
      account: context(previous: 86_400_000)).xp, 10)
    XCTAssertNil(try calculate().breakdown?["configMultiplier"])
  }

  func testIntegerRoundingPreservesHalfNeighborsAndNegativeTie() throws {
    for (duration, base) in [(0.24999999999999997, 0.0), (0.25, 1.0), (0.25000000000000006, 1.0)] {
      XCTAssertEqual(try calculate(input(duration: duration)).breakdown?["base"], base)
    }
    let award = try calculate(input(accuracy: 50, incomplete: 1), config: configuration(gain: -0.5))
    XCTAssertEqual(award.xp, 0, "Math.round(-0.5) must not become Swift's -1")
    XCTAssertEqual(try calculate(config: configuration(gain: -1)).xp, -45,
      "The calculator models the function; rejecting negative awards belongs to the future service adapter")
  }

  func testBreakdownIsNotAnArithmeticLedger() throws {
    let award = try calculate(input(duration: 1.5), config: configuration(gain: 1.5))
    XCTAssertEqual(award.xp, 8)
    XCTAssertEqual(award.breakdown, ["base": 3, "fullAccuracy": 2, "accPenalty": 0, "configMultiplier": 1.5])
    let data = try JSONEncoder().encode(award)
    XCTAssertEqual(try JSONDecoder().decode(ExperienceCalculationAward.self, from: data), award)
  }

  func testInvalidInputsAndUnsafeArithmeticThrowRatherThanTrapOrInventFallback() throws {
    for invalid in [input(mode: "unknown"), input(accuracy: .nan), input(accuracy: 49.99),
      input(accuracy: 100.01), input(duration: -1), input(duration: .infinity), input(afk: -1),
      input(afk: 16), input(counts: []), input(counts: [0, -1, 0, 0]), input(levels: [.nan]),
      input(incomplete: -1), input(attempts: [.init(accuracy: 101, seconds: 1)]),
      input(attempts: [.init(accuracy: 100, seconds: .infinity)])] {
      XCTAssertThrowsError(try calculate(invalid)) { XCTAssertEqual($0 as? ExperienceCalculationError, .invalidInput) }
    }
    for invalid in [configuration(gain: .nan), configuration(days: -1), configuration(funbox: .infinity)] {
      XCTAssertThrowsError(try calculate(config: invalid)) { XCTAssertEqual($0 as? ExperienceCalculationError, .invalidConfiguration) }
    }
    for invalid in [context(now: .nan), context(total: -1), context(streak: -.infinity)] {
      XCTAssertThrowsError(try calculate(account: invalid)) { XCTAssertEqual($0 as? ExperienceCalculationError, .invalidContext) }
    }
    for invalid in [input(duration: Double.greatestFiniteMagnitude), input(incomplete: 1e16)] {
      XCTAssertThrowsError(try calculate(invalid)) { XCTAssertEqual($0 as? ExperienceCalculationError, .unsafeArithmetic) }
    }
    XCTAssertThrowsError(try calculate(config: configuration(streak: true, days: 1,
      streakMultiplier: Double.greatestFiniteMagnitude), account: context(streak: 2)))
  }

  func testExistingServiceSubmissionDuplicateAndDiskReloadKeepLegacyXP() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-XP-legacy-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("store.json")
    let now = Date(timeIntervalSince1970: 42_000)
    let store = try AuthStore(fileURL: file, bcryptCost: 4, minimumLeaderboardTypingSeconds: 0)
    let account = try await store.register(.init(email: "xp-legacy@example.com", password: "a secure password",
      displayName: "Legacy XP"), now: now)
    let request = ResultSubmissionRequest(id: UUID(), mode: "time", language: "english",
      durationSeconds: 15, wordLimit: nil, wpm: 80, rawWpm: 80, accuracy: 100,
      errorCount: 0, eventCount: 100, startedAt: now.addingTimeInterval(-15), finishedAt: now)
    let accepted = try await store.submitResult(request, accessToken: account.accessToken, now: now)
    XCTAssertTrue(accepted.accepted)
    XCTAssertEqual(accepted.experienceGained, 18)
    XCTAssertEqual(accepted.totalExperience, 18)
    XCTAssertEqual(try calculate().xp, 45)
    let reloaded = try AuthStore(fileURL: file, bcryptCost: 4, minimumLeaderboardTypingSeconds: 0)
    let duplicate = try await reloaded.submitResult(request, accessToken: account.accessToken, now: now)
    XCTAssertTrue(duplicate.accepted, "Existing idempotent receipts acknowledge the authoritative saved result")
    XCTAssertEqual(duplicate.experienceGained, 18)
    XCTAssertEqual(duplicate.totalExperience, 18)
    let page = try await reloaded.results(.init(), credential: .accessToken(account.accessToken), now: now)
    XCTAssertEqual(page.total, 1)
    XCTAssertEqual(page.results.first?.id, request.id)
  }

  func testDifferentialAgainstActualPinnedXPFunction() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Set TYPEBAR_REFERENCE_ROOT to execute the read-only source differential; readiness gate does so")
    }
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Scripts/check-source-experience-calculation.mjs")
    let process = Process(), output = Pipe(), errors = Pipe()
    let node = ProcessInfo.processInfo.environment["TYPEBAR_XP_SOURCE_NODE"]
    process.executableURL = URL(fileURLWithPath: node ?? "/usr/bin/env")
    process.arguments = (node == nil ? ["node"] : []) + ["--experimental-vm-modules", script.path, reference, "--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0, String(decoding: errorData, as: UTF8.self))
    struct Fixture: Decodable {
      let label: String
      let input: ExperienceCalculationInput
      let configuration: ExperienceCalculationConfiguration
      let context: ExperienceCalculationContext
      let award: ExperienceCalculationAward
    }
    struct Document: Decodable { let referenceCommit: String; let fixtures: [Fixture] }
    let document = try JSONDecoder().decode(Document.self, from: data)
    XCTAssertEqual(document.referenceCommit, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertGreaterThanOrEqual(document.fixtures.count, 2100)
    for fixture in document.fixtures {
      let actual = try SourceStyleExperienceCalculator.calculate(fixture.input,
        configuration: fixture.configuration, context: fixture.context)
      XCTAssertEqual(actual, fixture.award, fixture.label)
    }
  }
}
