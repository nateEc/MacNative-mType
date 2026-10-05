import Foundation

public enum DailyLeaderboardCacheError: Error, Equatable {
  case invalidConfiguration, invalidState, unavailable
}

public struct DailyLeaderboardModeRule: Codable, Equatable, Sendable {
  public let language: String
  public let mode: String
  public let mode2: String
  public init(language: String, mode: String, mode2: String) {
    self.language = language; self.mode = mode; self.mode2 = mode2
  }
  func matches(language: String, mode: String, mode2: String) -> Bool {
    zip([self.language,self.mode,self.mode2],[language,mode,mode2]).allSatisfy { pattern, text in
      text.range(of:"^" + pattern + "$",options:.regularExpression) != nil
    }
  }
}

public struct DailyLeaderboardConfiguration: Codable, Equatable, Sendable {
  public let enabled: Bool
  public let expirationTimeInDays: Double
  public let maxResults: Int
  public let validModeRules: [DailyLeaderboardModeRule]
  public let scheduleRewardsModeRules: [DailyLeaderboardModeRule]
  public let topResultsToAnnounce: Int
  public let xpRewardBrackets: [WeeklyExperienceRewardBracket]
  public init(enabled: Bool, expirationTimeInDays: Double, maxResults: Int,
    validModeRules: [DailyLeaderboardModeRule], scheduleRewardsModeRules: [DailyLeaderboardModeRule] = [],
    topResultsToAnnounce: Int = 1, xpRewardBrackets: [WeeklyExperienceRewardBracket] = []) {
    self.enabled = enabled; self.expirationTimeInDays = expirationTimeInDays
    self.maxResults = maxResults; self.validModeRules = validModeRules
    self.scheduleRewardsModeRules = scheduleRewardsModeRules
    self.topResultsToAnnounce = topResultsToAnnounce; self.xpRewardBrackets = xpRewardBrackets
  }
  /// Our deployment default, not an assertion about Monkeytype's live settings.
  public static let typebarDefault = Self(enabled:true,expirationTimeInDays:2,maxResults:1_000,
    validModeRules:[.init(language:".*",mode:"time",mode2:".*"),
      .init(language:".*",mode:"words",mode2:".*")])
  public static func fromJSON(_ json: String?) throws -> Self {
    let value = try json.map { try JSONDecoder().decode(Self.self,from:Data($0.utf8)) } ?? .typebarDefault
    try value.validate(); return value
  }
  func validate() throws {
    guard expirationTimeInDays.isFinite, expirationTimeInDays >= 0,
      expirationTimeInDays <= 9_007_199_254_740_991 / 86_400_000,
      (0...1_000_000).contains(maxResults), (1...9_007_199_254_740_991).contains(topResultsToAnnounce),
      validModeRules.count <= 1_000, scheduleRewardsModeRules.count <= 1_000 else {
      throw DailyLeaderboardCacheError.invalidConfiguration
    }
    for bracket in xpRewardBrackets { try bracket.validate() }
    for rule in validModeRules + scheduleRewardsModeRules {
      for pattern in [rule.language,rule.mode,rule.mode2] {
        guard pattern.utf8.count <= 1_024 else { throw DailyLeaderboardCacheError.invalidConfiguration }
        do { _ = try NSRegularExpression(pattern:"^" + pattern + "$") }
        catch { throw DailyLeaderboardCacheError.invalidConfiguration }
      }
    }
  }
  func expiration(key: Int) throws -> Int {
    try validate()
    let deadline = Double(key) + expirationTimeInDays * 86_400_000
    guard deadline.isFinite, abs(deadline) <= 9_007_199_254_740_991 else {
      throw DailyLeaderboardCacheError.invalidConfiguration
    }
    return Int(floor(deadline / 1_000)) * 1_000
  }
  func accepts(_ entry: DailyLeaderboardCache.Entry) -> Bool {
    validModeRules.contains { $0.matches(language:entry.language,mode:entry.mode,mode2:entry.mode2) }
  }
  func schedulesRewards(for entry: DailyLeaderboardCache.Entry) -> Bool {
    enabled && scheduleRewardsModeRules.contains { $0.matches(language:entry.language,mode:entry.mode,mode2:entry.mode2) }
  }
}

extension DailyLeaderboardConfiguration {
  private enum CodingKeys: String, CodingKey {
    case enabled, expirationTimeInDays, maxResults, validModeRules, scheduleRewardsModeRules, topResultsToAnnounce, xpRewardBrackets
  }
  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy:CodingKeys.self)
    self.init(enabled:try values.decode(Bool.self,forKey:.enabled),
      expirationTimeInDays:try values.decode(Double.self,forKey:.expirationTimeInDays),
      maxResults:try values.decode(Int.self,forKey:.maxResults),
      validModeRules:try values.decode([DailyLeaderboardModeRule].self,forKey:.validModeRules),
      scheduleRewardsModeRules:values.contains(.scheduleRewardsModeRules)
        ? try values.decode([DailyLeaderboardModeRule].self,forKey:.scheduleRewardsModeRules) : [],
      topResultsToAnnounce:values.contains(.topResultsToAnnounce) ? try values.decode(Int.self,forKey:.topResultsToAnnounce) : 1,
      xpRewardBrackets:values.contains(.xpRewardBrackets) ? try values.decode([WeeklyExperienceRewardBracket].self,forKey:.xpRewardBrackets) : [])
  }
}

struct DailyLeaderboardCacheReceipt: Codable {
  let version: Int
  let configuration: DailyLeaderboardConfiguration
  let keyMilliseconds: Int
  let entry: DailyLeaderboardCache.Entry?
  let rank: Int?
  var settlementScheduled: Bool? = nil
  func validate(reward: ExperienceAwardRecord) throws {
    try configuration.validate()
    guard version == 1, let acceptedAt = reward.acceptedAt,
      keyMilliseconds == (try DailyLeaderboardCache.key(at:acceptedAt)),
      rank.map({ $0 > 0 && entry != nil }) ?? true,
      settlementScheduled.map({ $0 == (entry.map(configuration.schedulesRewards) ?? false) }) ?? true
    else { throw DailyLeaderboardCacheError.invalidState }
    if let entry {
      try entry.validate()
      guard configuration.enabled, configuration.accepts(entry),
        reward.rankingAdmission?.decision.speedEligible == true,
        entry.userID == reward.userID, entry.resultID == reward.resultID,
        entry.finishedAt.timeIntervalSince1970 == floor(acceptedAt.timeIntervalSince1970),
        (entry.preciseAccuracy ?? Double(entry.accuracy)) == reward.rankingAdmission?.input.accuracy
      else { throw DailyLeaderboardCacheError.invalidState }
    }
  }
}

extension DailyLeaderboardCacheReceipt {
  private enum CodingKeys: String, CodingKey { case version, configuration, keyMilliseconds, entry, rank, settlementScheduled }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy:CodingKeys.self)
    self.init(version:try values.decode(Int.self,forKey:.version),
      configuration:try values.decode(DailyLeaderboardConfiguration.self,forKey:.configuration),
      keyMilliseconds:try values.decode(Int.self,forKey:.keyMilliseconds),
      entry:values.contains(.entry) ? try values.decode(DailyLeaderboardCache.Entry.self,forKey:.entry) : nil,
      rank:values.contains(.rank) ? try values.decode(Int.self,forKey:.rank) : nil,
      settlementScheduled:values.contains(.settlementScheduled) ? try values.decode(Bool.self,forKey:.settlementScheduled) : nil)
  }
}

/// Acceptance-day scores and immutable winning snapshots, not a history query.
struct DailyLeaderboardCache: Codable {
  struct Entry: Codable, Equatable {
    let userID: UUID
    let resultID: UUID
    let displayName: String
    let language: String
    let mode: String
    let mode2: String
    let wpm: Int
    let accuracy: Int
    let preciseAccuracy: Double?
    let consistency: Double
    let finishedAt: Date
    let profileSnapshot: WeeklyExperienceProfileSnapshot
    var score: Double {
      Self.score(wpm:Double(wpm),accuracy:preciseAccuracy ?? Double(accuracy),
        timestamp:finishedAt.timeIntervalSince1970 * 1_000)
    }
    static func score(wpm: Double, accuracy: Double, timestamp: Double) -> Double {
      let speedComponent = (100_000 + floor(wpm * 100 + 0.5)) * 100_000
      let accuracyComponent = (speedComponent + floor(accuracy * 100 + 0.5)) * 100_000
      let withinDay = timestamp.truncatingRemainder(dividingBy:86_400_000)
      return accuracyComponent + floor((86_400_000 - withinDay) / 1_000)
    }
    func validate() throws {
      try profileSnapshot.validate()
      guard !displayName.isEmpty, displayName.count <= 40, !language.isEmpty, language.count <= 100,
        ["time","words"].contains(mode), let limit = Int(mode2),
        (mode == "time" ? 5...3_600 : 1...1_000).contains(limit),
        (0...600).contains(wpm), (0...100).contains(accuracy),
        preciseAccuracy.map({ $0.isFinite && (0...100).contains($0) }) ?? true,
        consistency.isFinite, consistency >= 0,
        finishedAt.timeIntervalSince1970.isFinite,
        (0...8_640_000_000_000_000).contains(finishedAt.timeIntervalSince1970 * 1_000),
        score.isFinite, score <= 9_007_199_254_740_991
      else { throw DailyLeaderboardCacheError.invalidState }
    }
  }
  struct Bucket: Codable {
    let keyMilliseconds: Int
    let language: String
    let mode: String
    let mode2: String
    var expirationTimeInDays: Double
    var expiresAtMilliseconds: Int
    var entries: [Entry]
    var identity: String { "\(keyMilliseconds)/\(language)/\(mode)/\(mode2)" }
  }
  let version: Int
  var buckets: [Bucket]
  init() { version = 1; buckets = [] }
  static func key(at date: Date) throws -> Int {
    let milliseconds = date.timeIntervalSince1970 * 1_000
    guard milliseconds.isFinite, abs(milliseconds) <= 8_640_000_000_000_000 else {
      throw DailyLeaderboardCacheError.invalidState
    }
    return Int(milliseconds - milliseconds.truncatingRemainder(dividingBy:86_400_000))
  }
  static func ordered(_ entries: [Entry]) -> [Entry] {
    entries.sorted { $0.score != $1.score ? $0.score > $1.score : $0.userID.uuidString > $1.userID.uuidString }
  }
  mutating func expire(at now: Date) {
    buckets.removeAll { Double($0.expiresAtMilliseconds) <= now.timeIntervalSince1970 * 1_000 }
  }
  mutating func purge(userID: UUID) {
    for index in buckets.indices { buckets[index].entries.removeAll { $0.userID == userID } }
    buckets.removeAll { $0.entries.isEmpty }
  }
  mutating func add(_ entry: Entry, configuration: DailyLeaderboardConfiguration, now: Date) throws -> Int? {
    try entry.validate(); try configuration.validate()
    guard configuration.enabled, configuration.accepts(entry) else { return nil }
    let key = try Self.key(at:now), deadline = try configuration.expiration(key:key)
    expire(at:now)
    if !buckets.contains(where: { $0.keyMilliseconds == key && $0.language == entry.language
      && $0.mode == entry.mode && $0.mode2 == entry.mode2 }) {
      buckets.append(.init(keyMilliseconds:key,language:entry.language,mode:entry.mode,mode2:entry.mode2,
        expirationTimeInDays:configuration.expirationTimeInDays,expiresAtMilliseconds:deadline,entries:[]))
    }
    let index = buckets.firstIndex { $0.keyMilliseconds == key && $0.language == entry.language
      && $0.mode == entry.mode && $0.mode2 == entry.mode2 }!
    let existing = buckets[index].entries.firstIndex { $0.userID == entry.userID }
    let changed = existing.map { entry.score > buckets[index].entries[$0].score } ?? true
    if changed {
      if let existing { buckets[index].entries[existing] = entry }
      else { buckets[index].entries.append(entry) }
    }
    // The source evicts ONE lowest member per attempt, even an unchanged write.
    let countBeforeEviction = buckets[index].entries.count
    if countBeforeEviction > configuration.maxResults {
      let removed = Self.ordered(buckets[index].entries).last!.userID
      buckets[index].entries.removeAll { $0.userID == removed }
    }
    // ZCARD is sampled before eviction. A multi-member write never refreshes TTL.
    if countBeforeEviction == 1 {
      buckets[index].expirationTimeInDays = configuration.expirationTimeInDays
      buckets[index].expiresAtMilliseconds = deadline
    }
    if buckets[index].entries.isEmpty || Double(buckets[index].expiresAtMilliseconds) <= now.timeIntervalSince1970 * 1_000 {
      buckets.remove(at:index); return nil
    }
    return changed ? Self.ordered(buckets[index].entries).firstIndex { $0.userID == entry.userID }.map { $0 + 1 } : nil
  }
  func validate(users: Set<UUID>, awards: [ExperienceAwardRecord]) throws {
    guard version == 1, Set(buckets.map(\.identity)).count == buckets.count else {
      throw DailyLeaderboardCacheError.invalidState
    }
    let receipts = Dictionary(uniqueKeysWithValues:awards.compactMap { award in
      award.dailyCacheReceipt.map { ("\(award.userID)/\(award.resultID)",$0) }
    })
    for bucket in buckets {
      let cfg = DailyLeaderboardConfiguration(enabled:true,expirationTimeInDays:bucket.expirationTimeInDays,
        maxResults:0,validModeRules:[])
      guard bucket.keyMilliseconds % 86_400_000 == 0,
        abs(Double(bucket.keyMilliseconds)) <= 8_640_000_000_000_000,
        try cfg.expiration(key:bucket.keyMilliseconds) == bucket.expiresAtMilliseconds,
        !bucket.entries.isEmpty, Set(bucket.entries.map(\.userID)).count == bucket.entries.count else {
        throw DailyLeaderboardCacheError.invalidState
      }
      for entry in bucket.entries {
        try entry.validate()
        guard users.contains(entry.userID), bucket.language == entry.language,
          bucket.mode == entry.mode, bucket.mode2 == entry.mode2,
          let receipt = receipts["\(entry.userID)/\(entry.resultID)"],
          receipt.keyMilliseconds == bucket.keyMilliseconds, receipt.entry == entry else {
          throw DailyLeaderboardCacheError.invalidState
        }
      }
    }
  }
}
