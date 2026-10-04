import Foundation

public enum WeeklyExperienceCacheError: Error, Equatable {
  case invalidConfiguration, invalidState, unavailable
}

public struct WeeklyExperienceLeaderboardConfiguration: Codable, Equatable, Sendable {
  public let enabled: Bool
  public let expirationTimeInDays: Double
  public let xpRewardBrackets: [WeeklyExperienceRewardBracket]
  public init(enabled: Bool, expirationTimeInDays: Double,
    xpRewardBrackets: [WeeklyExperienceRewardBracket] = []) {
    self.enabled = enabled; self.expirationTimeInDays = expirationTimeInDays
    self.xpRewardBrackets = xpRewardBrackets
  }
  /// A Typebar deployment default, not Monkeytype's live configuration.
  public static let typebarDefault = Self(enabled:true,expirationTimeInDays:15)
  public static func fromJSON(_ json: String?) throws -> Self {
    let value = try json.map { try JSONDecoder().decode(Self.self,from:Data($0.utf8)) } ?? .typebarDefault
    try value.validate(); return value
  }
  func validate() throws {
    for bracket in xpRewardBrackets { try bracket.validate() }
    guard expirationTimeInDays.isFinite, expirationTimeInDays >= 0,
      expirationTimeInDays <= 9_007_199_254_740_991 / Double(WeeklyExperiencePartition.day)
    else { throw WeeklyExperienceCacheError.invalidConfiguration }
  }
  func expiration(key: Int) throws -> Int {
    try validate()
    let milliseconds = Double(key) + expirationTimeInDays * Double(WeeklyExperiencePartition.day)
    guard milliseconds.isFinite, abs(milliseconds) <= 9_007_199_254_740_991 else {
      throw WeeklyExperienceCacheError.invalidConfiguration
    }
    return Int(floor(milliseconds / 1_000)) * 1_000
  }
}

extension WeeklyExperienceLeaderboardConfiguration {
  private enum CodingKeys: String, CodingKey { case enabled, expirationTimeInDays, xpRewardBrackets }
  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy:CodingKeys.self)
    self.init(enabled:try values.decode(Bool.self,forKey:.enabled),
      expirationTimeInDays:try values.decode(Double.self,forKey:.expirationTimeInDays),
      xpRewardBrackets:values.contains(.xpRewardBrackets)
        ? try values.decode([WeeklyExperienceRewardBracket].self,forKey:.xpRewardBrackets) : [])
  }
}

/// Presence distinguishes cache-managed rewards from unknown legacy sources.
/// A disabled/rejected reward stays managed and can never be replayed into a cache.
struct WeeklyExperienceCacheReceipt: Codable {
  let version: Int
  let configuration: WeeklyExperienceLeaderboardConfiguration
  let timeTypedSeconds: Double
  let rank: Int?
  func validate(reward: ExperienceAwardRecord) throws {
    try configuration.validate()
    guard version == 1, reward.weeklyPartition != nil,
      timeTypedSeconds.isFinite, (0...9_007_199_254_740_991).contains(timeTypedSeconds),
      rank.map({ $0 > 0 }) ?? true,
      (rank != nil) == (configuration.enabled && reward.award.xp > 0
        && reward.rankingAdmission?.decision.weeklyExperienceEligible == true)
    else { throw WeeklyExperienceCacheError.invalidState }
  }
}

/// A known-empty snapshot differs from a pre-snapshot entry with unknown origin.
struct WeeklyExperienceProfileSnapshot: Codable {
  let version: Int
  let selectedBadge: PublicProfileBadge?
  let discordAvatar: PublicDiscordAvatarResponse?
  func validate() throws {
    guard version == 1 else { throw WeeklyExperienceCacheError.invalidState }
    if let badge = selectedBadge {
      guard !badge.id.isEmpty, badge.id.count <= 64, !badge.title.isEmpty, badge.title.count <= 80,
        !badge.systemImage.isEmpty, badge.systemImage.count <= 80
      else { throw WeeklyExperienceCacheError.invalidState }
    }
    if let avatar = discordAvatar {
      let hex = avatar.avatarHash.hasPrefix("a_") ? String(avatar.avatarHash.dropFirst(2)) : avatar.avatarHash
      guard !avatar.subject.isEmpty, avatar.subject.count <= 255,
        hex.count == 32, hex.allSatisfy({ "0123456789abcdef".contains($0) })
      else { throw WeeklyExperienceCacheError.invalidState }
    }
  }
}

/// Mutable leaderboard cache independent of the immutable account reward ledger.
/// Expiry removes a bucket; purge removes a member without touching its reward.
struct WeeklyExperienceCache: Codable {
  struct Entry: Codable {
    let userID: UUID
    var score: Double
    var displayName: String
    var timeTypedSeconds: Double
    var lastActivityMilliseconds: Int
    var profileSnapshot: WeeklyExperienceProfileSnapshot? = nil
  }
  struct Bucket: Codable {
    let keyMilliseconds: Int
    var expirationTimeInDays: Double
    var expiresAtMilliseconds: Int
    var entries: [Entry]
  }
  let version: Int
  var buckets: [Bucket]
  init() { version = 1; buckets = [] }

  mutating func expire(at now: Date) {
    let milliseconds = now.timeIntervalSince1970 * 1_000
    buckets.removeAll { Double($0.expiresAtMilliseconds) <= milliseconds }
  }
  mutating func purge(userID: UUID) {
    for index in buckets.indices { buckets[index].entries.removeAll { $0.userID == userID } }
    buckets.removeAll { $0.entries.isEmpty }
  }

  mutating func add(userID: UUID, displayName: String, xp: Double, seconds: Double,
    partition: WeeklyExperiencePartition, configuration: WeeklyExperienceLeaderboardConfiguration,
    now: Date, profileSnapshot: WeeklyExperienceProfileSnapshot? = nil) throws -> Int {
    try configuration.validate()
    try profileSnapshot?.validate()
    guard configuration.enabled, xp.isFinite, xp > 0, seconds.isFinite, seconds >= 0 else {
      throw WeeklyExperienceCacheError.invalidState
    }
    let deadline = try configuration.expiration(key:partition.keyMilliseconds)
    expire(at:now)
    if !buckets.contains(where: { $0.keyMilliseconds == partition.keyMilliseconds }) {
      buckets.append(.init(keyMilliseconds:partition.keyMilliseconds,
        expirationTimeInDays:configuration.expirationTimeInDays,expiresAtMilliseconds:deadline,entries:[]))
    }
    let index = buckets.firstIndex { $0.keyMilliseconds == partition.keyMilliseconds }!
    if let member = buckets[index].entries.firstIndex(where: { $0.userID == userID }) {
      buckets[index].entries[member].score += xp
      buckets[index].entries[member].timeTypedSeconds += seconds
      buckets[index].entries[member].displayName = displayName
      buckets[index].entries[member].lastActivityMilliseconds = partition.acceptedMilliseconds
      buckets[index].entries[member].profileSnapshot = profileSnapshot
    } else {
      buckets[index].entries.append(.init(userID:userID,score:xp,displayName:displayName,
        timeTypedSeconds:seconds,lastActivityMilliseconds:partition.acceptedMilliseconds,profileSnapshot:profileSnapshot))
    }
    let entry = buckets[index].entries.first { $0.userID == userID }!
    guard entry.score <= 9_007_199_254_740_991, entry.timeTypedSeconds <= 9_007_199_254_740_991 else {
      throw WeeklyExperienceCacheError.invalidState
    }
    // The pinned Lua applies EXPIREAT whenever ZCARD == 1, not just once.
    if buckets[index].entries.count == 1 {
      buckets[index].expirationTimeInDays = configuration.expirationTimeInDays
      buckets[index].expiresAtMilliseconds = deadline
    }
    let ordered = buckets[index].entries.sorted {
      $0.score != $1.score ? $0.score > $1.score : $0.userID.uuidString > $1.userID.uuidString
    }
    let rank = ordered.firstIndex { $0.userID == userID }! + 1
    if Double(buckets[index].expiresAtMilliseconds) <= now.timeIntervalSince1970 * 1_000 {
      buckets.remove(at:index)
      // Lua's null ZREVRANK becomes null + 1 in the source service.
      return 1
    }
    return rank
  }

  func validate(users: Set<UUID>, awards: [ExperienceAwardRecord]) throws {
    guard version == 1, Set(buckets.map(\.keyMilliseconds)).count == buckets.count else {
      throw WeeklyExperienceCacheError.invalidState
    }
    let byUser = Dictionary(grouping:awards.filter { $0.weeklyCacheReceipt?.rank != nil },by:\.userID)
    for bucket in buckets {
      let configuration = WeeklyExperienceLeaderboardConfiguration(enabled:true,
        expirationTimeInDays:bucket.expirationTimeInDays)
      guard bucket.keyMilliseconds % WeeklyExperiencePartition.day == 0,
        abs(Double(bucket.keyMilliseconds)) <= 8_640_000_000_000_000,
        try configuration.expiration(key:bucket.keyMilliseconds) == bucket.expiresAtMilliseconds,
        !bucket.entries.isEmpty, Set(bucket.entries.map(\.userID)).count == bucket.entries.count else {
        throw WeeklyExperienceCacheError.invalidState
      }
      for entry in bucket.entries {
        try entry.profileSnapshot?.validate()
        let contributions = (byUser[entry.userID] ?? []).filter { $0.weeklyPartition?.keyMilliseconds == bucket.keyMilliseconds }
        guard users.contains(entry.userID), !entry.displayName.isEmpty, entry.displayName.count <= 40,
          entry.score.isFinite, entry.score > 0, entry.score <= 9_007_199_254_740_991,
          entry.timeTypedSeconds.isFinite, (0...9_007_199_254_740_991).contains(entry.timeTypedSeconds),
          abs(Double(entry.lastActivityMilliseconds)) <= 8_640_000_000_000_000,
          entry.score <= contributions.reduce(0.0,{ $0 + $1.award.xp }),
          entry.timeTypedSeconds <= contributions.reduce(0.0,{ $0 + $1.weeklyCacheReceipt!.timeTypedSeconds }),
          contributions.contains(where: { $0.weeklyPartition?.acceptedMilliseconds == entry.lastActivityMilliseconds })
        else { throw WeeklyExperienceCacheError.invalidState }
      }
    }
  }
}

extension WeeklyExperienceCache.Entry {
  private enum CodingKeys: String, CodingKey {
    case userID, score, displayName, timeTypedSeconds, lastActivityMilliseconds, profileSnapshot
  }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy:CodingKeys.self)
    self.init(userID:try values.decode(UUID.self,forKey:.userID),
      score:try values.decode(Double.self,forKey:.score),
      displayName:try values.decode(String.self,forKey:.displayName),
      timeTypedSeconds:try values.decode(Double.self,forKey:.timeTypedSeconds),
      lastActivityMilliseconds:try values.decode(Int.self,forKey:.lastActivityMilliseconds),
      profileSnapshot:values.contains(.profileSnapshot)
        ? try values.decode(WeeklyExperienceProfileSnapshot.self,forKey:.profileSnapshot) : nil)
  }
}
