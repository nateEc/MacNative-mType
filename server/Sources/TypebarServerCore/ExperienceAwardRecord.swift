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
  var rankingAdmission: RankingAdmission? = nil
  var personalBestConfiguration: ResultPersonalBestConfiguration? = nil
  var speedPrecision: ResultSpeedPrecision? = nil
  var personalBestReceipt: PersonalBestReceipt? = nil
  var accountTagIDs: [UUID]? = nil
  var weeklyPartition: WeeklyExperiencePartition? = nil
  var weeklyCacheReceipt: WeeklyExperienceCacheReceipt? = nil
  var dailyCacheReceipt: DailyLeaderboardCacheReceipt? = nil

  static func legacy(userID: UUID, request: ResultSubmissionRequest, acceptedAt: Date?) -> Self {
    let xp = TypebarExperiencePolicy.points(for: request)
    var record = Self(version: 1, userID: userID, resultID: request.id, finishedAt: request.finishedAt,
      acceptedAt: acceptedAt, award: .init(xp: Double(xp), dailyBonus: nil, breakdown: nil),
      accountCredit: xp, input: nil, configuration: nil, context: nil)
    record.personalBestConfiguration = request.personalBestConfiguration
    record.speedPrecision = request.speedPrecision
    return record
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
    guard accountTagIDs.map({ $0.count <= 15 && Set($0).count == $0.count }) ?? true else {
      throw AccountTagError.invalidState
    }
    try personalBestReceipt?.validate(reward:self)
    if let speedPrecision {
      guard speedPrecision.isValid else { throw ExperienceCalculationError.invalidInput }
      if let input {
        guard input.characterCounts.count == 4, input.durationSeconds > 0,
          abs(speedPrecision.wpm - ResultSpeedPrecision.round(Double(input.characterCounts[0]) / 5 / input.durationSeconds * 60)) <= 0.005001
        else { throw ExperienceCalculationError.invalidInput }
      }
    }
    if let personalBestConfiguration {
      guard personalBestConfiguration.isValid else { throw ExperienceCalculationError.invalidInput }
      if let input, personalBestConfiguration.punctuation != input.punctuation
        || personalBestConfiguration.numbers != input.numbers { throw ExperienceCalculationError.invalidInput }
    }
    try rankingAdmission?.validate()
    try weeklyPartition?.validate(acceptedAt: acceptedAt)
    try weeklyCacheReceipt?.validate(reward: self)
    try dailyCacheReceipt?.validate(reward: self)
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

extension ExperienceAwardRecord {
  private enum CodingKeys: String, CodingKey {
    case version, userID, resultID, finishedAt, acceptedAt, award, accountCredit,
      input, configuration, context, rankingAdmission, weeklyPartition, weeklyCacheReceipt, dailyCacheReceipt
    case personalBestConfiguration
    case speedPrecision
    case personalBestReceipt
    case accountTagIDs
  }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(version: try values.decode(Int.self, forKey: .version),
      userID: try values.decode(UUID.self, forKey: .userID),
      resultID: try values.decode(UUID.self, forKey: .resultID),
      finishedAt: try values.decode(Date.self, forKey: .finishedAt),
      acceptedAt: try values.decodeIfPresent(Date.self, forKey: .acceptedAt),
      award: try values.decode(ExperienceCalculationAward.self, forKey: .award),
      accountCredit: try values.decode(Int.self, forKey: .accountCredit),
      input: try values.decodeIfPresent(ExperienceCalculationInput.self, forKey: .input),
      configuration: try values.decodeIfPresent(ExperienceCalculationConfiguration.self, forKey: .configuration),
      context: try values.decodeIfPresent(ExperienceCalculationContext.self, forKey: .context))
    accountTagIDs = values.contains(.accountTagIDs) ? try values.decode([UUID].self, forKey: .accountTagIDs) : nil
    rankingAdmission = values.contains(.rankingAdmission)
      ? try values.decode(RankingAdmission.self, forKey: .rankingAdmission) : nil
    personalBestConfiguration = values.contains(.personalBestConfiguration)
      ? try values.decode(ResultPersonalBestConfiguration.self, forKey: .personalBestConfiguration) : nil
    speedPrecision = values.contains(.speedPrecision) ? try values.decode(ResultSpeedPrecision.self,forKey:.speedPrecision) : nil
    personalBestReceipt = values.contains(.personalBestReceipt)
      ? try values.decode(PersonalBestReceipt.self,forKey:.personalBestReceipt) : nil
    weeklyPartition = values.contains(.weeklyPartition)
      ? try values.decode(WeeklyExperiencePartition.self, forKey: .weeklyPartition) : nil
    weeklyCacheReceipt = values.contains(.weeklyCacheReceipt)
      ? try values.decode(WeeklyExperienceCacheReceipt.self, forKey: .weeklyCacheReceipt) : nil
    dailyCacheReceipt = values.contains(.dailyCacheReceipt)
      ? try values.decode(DailyLeaderboardCacheReceipt.self, forKey: .dailyCacheReceipt) : nil
  }
}
