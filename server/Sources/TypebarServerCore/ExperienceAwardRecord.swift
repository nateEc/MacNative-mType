import Foundation

/// Account-scoped, immutable reward tombstone. It survives history deletion,
/// but not an explicit account reset/deletion. No text, replay or key identity.
struct ExperienceAwardRecord: Codable {
  let version: Int
  let userID: UUID
  let resultID: UUID
  let finishedAt: Date
  let acceptedAt: Date?
  let award: ExperienceCalculationAward
  let accountCredit: Int
  let input: ExperienceCalculationInput?
  let configuration: ExperienceCalculationConfiguration?
  let context: ExperienceCalculationContext?

  static func legacy(userID: UUID, request: ResultSubmissionRequest, acceptedAt: Date?) -> Self {
    let xp = TypebarExperiencePolicy.points(for: request)
    return .init(version: 1, userID: userID, resultID: request.id, finishedAt: request.finishedAt,
      acceptedAt: acceptedAt, award: .init(xp: Double(xp), dailyBonus: nil, breakdown: nil),
      accountCredit: xp, input: nil, configuration: nil, context: nil)
  }

  /// The pinned backend uses BSON 6.8's numeric Long constructor (high=0),
  /// not Long.fromNumber. Preserve its unsigned low-word credit independently
  /// from the numeric receipt/weekly reward. The caller rejects negative XP.
  static func sourceAccountCredit(_ xp: Double) throws -> Int {
    guard xp.isFinite, (0...9_007_199_254_740_991).contains(xp) else {
      throw ExperienceCalculationError.unsafeArithmetic
    }
    return Int(xp.rounded(.towardZero).truncatingRemainder(dividingBy: 4_294_967_296))
  }

  func validate() throws {
    guard version == 1, finishedAt.timeIntervalSince1970.isFinite,
      acceptedAt.map({ $0.timeIntervalSince1970.isFinite }) ?? true,
      award.xp.isFinite, (0...9_007_199_254_740_991).contains(award.xp), accountCredit >= 0 else {
      throw ExperienceCalculationError.invalidInput
    }
    if let configuration, let context, let input {
      try configuration.validateForProduction()
      guard acceptedAt != nil, context.nowMilliseconds.isFinite,
        context.previousResultMilliseconds.map(\.isFinite) ?? true,
        context.currentTotalXP.isFinite, (0...9_007_199_254_740_991).contains(context.currentTotalXP),
        context.streakDays.isFinite, context.streakDays >= 0,
        finishedAt.timeIntervalSince1970 * 1_000 == context.nowMilliseconds,
        try SourceStyleExperienceCalculator.calculate(input, configuration: configuration, context: context) == award,
        try Self.sourceAccountCredit(award.xp) == accountCredit else {
        throw ExperienceCalculationError.invalidInput
      }
    } else {
      guard configuration == nil, context == nil, input == nil,
        award.dailyBonus == nil, award.breakdown == nil, Double(accountCredit) == award.xp else {
        throw ExperienceCalculationError.invalidInput
      }
    }
  }
}
