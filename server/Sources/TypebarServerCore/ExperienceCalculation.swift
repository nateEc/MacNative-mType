import Foundation

// Version-one reward arithmetic. Production resolves the catalog and account
// context before calling this module; historical rewards keep their snapshots.
struct ExperienceIncompleteAttempt: Codable, Equatable, Sendable {
  let accuracy: Double
  let seconds: Double
}

struct ExperienceCalculationInput: Codable, Equatable, Sendable {
  let mode: String
  let accuracy: Double
  let durationSeconds: Double
  let afkSeconds: Double
  let characterCounts: [Int] // correct, incorrect, extra, missed
  let punctuation: Bool
  let numbers: Bool
  let funboxDifficultyLevels: [Double]
  let incompleteSeconds: Double?
  let incompleteAttempts: [ExperienceIncompleteAttempt]?
}

public struct ExperienceCalculationConfiguration: Codable, Equatable, Sendable {
  let enabled: Bool
  let gainMultiplier: Double
  let funboxBonus: Double
  let minimumDailyBonus: Double
  let maximumDailyBonus: Double
  let streakEnabled: Bool
  let maximumStreakDays: Double
  let maximumStreakMultiplier: Double

  public init(enabled: Bool, gainMultiplier: Double, funboxBonus: Double,
    minimumDailyBonus: Double, maximumDailyBonus: Double, streakEnabled: Bool,
    maximumStreakDays: Double, maximumStreakMultiplier: Double) {
    self.enabled = enabled; self.gainMultiplier = gainMultiplier; self.funboxBonus = funboxBonus
    self.minimumDailyBonus = minimumDailyBonus; self.maximumDailyBonus = maximumDailyBonus
    self.streakEnabled = streakEnabled; self.maximumStreakDays = maximumStreakDays
    self.maximumStreakMultiplier = maximumStreakMultiplier
  }

  /// An explicit Typebar deployment choice, NOT Monkeytype's live configuration.
  public static let typebarDefault = Self(enabled: true, gainMultiplier: 1, funboxBonus: 0,
    minimumDailyBonus: 0, maximumDailyBonus: 0, streakEnabled: false,
    maximumStreakDays: 0, maximumStreakMultiplier: 0)

  public static func fromJSON(_ json: String?) throws -> Self {
    let configuration = try json.map { try JSONDecoder().decode(Self.self, from: Data($0.utf8)) }
      ?? .typebarDefault
    try configuration.validateForProduction()
    return configuration
  }

  func validateForProduction() throws {
    guard [gainMultiplier, funboxBonus, minimumDailyBonus, maximumDailyBonus,
      maximumStreakDays, maximumStreakMultiplier].allSatisfy({ $0.isFinite && $0 >= 0
        && $0 <= 9_007_199_254_740_991 }), minimumDailyBonus <= maximumDailyBonus
    else { throw ExperienceCalculationError.invalidConfiguration }
  }
}

struct ExperienceCalculationContext: Codable, Equatable, Sendable {
  let previousResultMilliseconds: Double?
  let nowMilliseconds: Double
  let currentTotalXP: Double
  let streakDays: Double
}

struct ExperienceCalculationAward: Codable, Equatable, Sendable {
  let xp: Double
  let dailyBonus: Bool?
  // Most values are points, but configMultiplier is a factor, not a point sum.
  let breakdown: [String: Double]?
}

enum ExperienceCalculationError: Error, Equatable {
  case invalidInput
  case invalidConfiguration
  case invalidContext
  case unsafeArithmetic
}

enum SourceStyleExperienceCalculator {
  static func calculate(_ input: ExperienceCalculationInput,
    configuration: ExperienceCalculationConfiguration,
    context: ExperienceCalculationContext) throws -> ExperienceCalculationAward {
    // These early exits intentionally omit the two optional response fields.
    guard configuration.enabled, input.mode != "zen" else {
      return .init(xp: 0, dailyBonus: nil, breakdown: nil)
    }
    try validate(input, configuration: configuration, context: context)
    let base = try integerRound((input.durationSeconds - input.afkSeconds) * 2)
    var details: [String: Double] = ["base": base]
    var multiplier = 1.0
    if input.accuracy == 100 {
      multiplier += 0.5
      details["fullAccuracy"] = try integerRound(base * 0.5)
    } else if input.characterCounts.dropFirst().allSatisfy({ $0 == 0 }) {
      multiplier += 0.25
      details["corrected"] = try integerRound(base * 0.25)
    }
    if input.mode == "quote" {
      multiplier += 0.5
      details["quote"] = try integerRound(base * 0.5)
    } else {
      if input.punctuation {
        multiplier += 0.4
        details["punctuation"] = try integerRound(base * 0.4)
      }
      if input.numbers {
        multiplier += 0.1
        details["numbers"] = try integerRound(base * 0.1)
      }
    }
    if configuration.funboxBonus > 0, !input.funboxDifficultyLevels.isEmpty {
      let bonus = input.funboxDifficultyLevels.reduce(0.0) {
        $0 + max($1 * configuration.funboxBonus, 0)
      }
      if bonus > 0 {
        multiplier += bonus
        details["funbox"] = try integerRound(base * bonus)
      }
    }
    if configuration.streakEnabled {
      let upper = configuration.maximumStreakMultiplier
      let mapped = configuration.maximumStreakDays == 0 ? 0
        : context.streakDays * upper / configuration.maximumStreakDays
      guard mapped.isFinite else { throw ExperienceCalculationError.unsafeArithmetic }
      let bounded = upper >= 0 ? min(max(mapped, 0), upper) : max(min(mapped, 0), upper)
      let bonus = try decimalRound(bounded)
      if bonus > 0 {
        multiplier += bonus
        details["streak"] = try integerRound(base * bonus)
      }
    }
    var unfinished = 0.0
    if let attempts = input.incompleteAttempts, !attempts.isEmpty {
      for attempt in attempts {
        unfinished += try integerRound(attempt.seconds * max((attempt.accuracy - 50) / 50, 0))
      }
      details["incomplete"] = unfinished
    } else if let seconds = input.incompleteSeconds, seconds > 0 {
      unfinished = try integerRound(seconds)
      details["incomplete"] = unfinished
    }
    var daily = 0.0
    if let previous = context.previousResultMilliseconds, previous.isFinite,
      dayBoundary(previous) != dayBoundary(context.nowMilliseconds) {
      let proportion = try integerRound(context.currentTotalXP * 0.05)
      daily = max(min(configuration.maximumDailyBonus, proportion), configuration.minimumDailyBonus)
      details["daily"] = daily // A present zero is different from an absent bonus.
    }
    let adjusted = try integerRound(base * multiplier)
    let afterAccuracy = try integerRound(adjusted * ((input.accuracy - 50) / 50))
    details["accPenalty"] = adjusted - afterAccuracy
    if configuration.gainMultiplier != 1 {
      details["configMultiplier"] = configuration.gainMultiplier
    }
    let total = try integerRound((afterAccuracy + unfinished) * configuration.gainMultiplier) + daily
    // Daily configuration permits fractions; preserve the numeric award rather
    // than truncating it to the legacy account's integer representation.
    guard total.isFinite, abs(total) <= 9_007_199_254_740_991 else {
      throw ExperienceCalculationError.unsafeArithmetic
    }
    return .init(xp: total, dailyBonus: daily > 0, breakdown: details)
  }

  private static func validate(_ input: ExperienceCalculationInput,
    configuration: ExperienceCalculationConfiguration, context: ExperienceCalculationContext) throws {
    guard ["time", "words", "quote", "custom"].contains(input.mode),
      input.accuracy.isFinite, (50...100).contains(input.accuracy),
      input.durationSeconds.isFinite, input.durationSeconds >= 0,
      input.afkSeconds.isFinite, (0...input.durationSeconds).contains(input.afkSeconds),
      input.characterCounts.count == 4, input.characterCounts.allSatisfy({ $0 >= 0 }),
      input.funboxDifficultyLevels.allSatisfy(\.isFinite),
      input.incompleteSeconds.map({ $0.isFinite && $0 >= 0 }) ?? true,
      input.incompleteAttempts?.allSatisfy({ $0.seconds.isFinite && $0.seconds >= 0
        && $0.accuracy.isFinite && (0...100).contains($0.accuracy) }) ?? true
    else { throw ExperienceCalculationError.invalidInput }
    guard [configuration.gainMultiplier, configuration.funboxBonus,
      configuration.minimumDailyBonus, configuration.maximumDailyBonus,
      configuration.maximumStreakDays, configuration.maximumStreakMultiplier].allSatisfy(\.isFinite),
      configuration.maximumStreakDays >= 0 else { throw ExperienceCalculationError.invalidConfiguration }
    guard context.nowMilliseconds.isFinite, context.currentTotalXP.isFinite, context.currentTotalXP >= 0,
      context.streakDays.isFinite, context.streakDays >= 0 else { throw ExperienceCalculationError.invalidContext }
  }

  private static func dayBoundary(_ milliseconds: Double) -> Double {
    // Keep signed remainder semantics, independent of the Mac's local timezone.
    milliseconds - milliseconds.truncatingRemainder(dividingBy: 86_400_000)
  }

  private static func integerRound(_ value: Double) throws -> Double {
    guard value.isFinite, abs(value) <= 9_007_199_254_740_991 else {
      throw ExperienceCalculationError.unsafeArithmetic
    }
    let lower = value.rounded(.down)
    // Adding 0.5 before floor loses the distinction just below a half boundary.
    return value - lower >= 0.5 ? lower + 1 : lower
  }

  private static func decimalRound(_ value: Double) throws -> Double {
    guard value.isFinite else { throw ExperienceCalculationError.unsafeArithmetic }
    let magnitude = abs(value)
    if magnitude < 0.05 { return 0 }
    if magnitude >= 4_503_599_627_370_496 { return value }
    // Round the exact binary value to one decimal. Scaling a Double by ten first
    // incorrectly changes values such as 1.15 into an exact half tie.
    let bits = magnitude.bitPattern
    let exponent = Int((bits >> 52) & 0x7ff) - 1023 - 52
    let scaled = ((bits & 0x000f_ffff_ffff_ffff) | (1 << 52)) * 10
    let shift = -exponent // This magnitude interval guarantees 1...57.
    let quotient = scaled >> shift
    let remainder = scaled & ((UInt64(1) << shift) - 1)
    let rounded = quotient + (remainder >= (UInt64(1) << (shift - 1)) ? 1 : 0)
    let result = Double("\(rounded / 10).\(rounded % 10)")!
    return value < 0 ? -result : result
  }
}
