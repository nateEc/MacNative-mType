import Foundation

public struct WeeklyExperienceRewardBracket: Codable, Equatable, Sendable {
  public let minRank: Int
  public let maxRank: Int
  public let minReward: Int
  public let maxReward: Int
  public init(minRank: Int, maxRank: Int, minReward: Int, maxReward: Int) {
    self.minRank = minRank; self.maxRank = maxRank
    self.minReward = minReward; self.maxReward = maxReward
  }
  func validate() throws {
    guard [minRank,maxRank,minReward,maxReward].allSatisfy({ (0...9_007_199_254_740_991).contains($0) })
    else { throw WeeklyExperienceCacheError.invalidConfiguration }
    // The pinned schema permits reversed intervals and rising rewards.
  }
}

extension WeeklyExperienceRewardBracket {
  private struct Key: CodingKey {
    var stringValue: String; var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
  }
  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy:Key.self)
    guard Set(values.allKeys.map(\.stringValue)) == Set(["minRank","maxRank","minReward","maxReward"]) else {
      throw WeeklyExperienceCacheError.invalidConfiguration
    }
    self.init(minRank:try values.decode(Int.self,forKey:Key(stringValue:"minRank")!),
      maxRank:try values.decode(Int.self,forKey:Key(stringValue:"maxRank")!),
      minReward:try values.decode(Int.self,forKey:Key(stringValue:"minReward")!),
      maxReward:try values.decode(Int.self,forKey:Key(stringValue:"maxReward")!))
  }
}

enum WeeklyExperienceSettlementError: Error, Equatable {
  case emptyRewardBrackets, invalidEntry, invalidClock
}

/// A source-aligned descriptor, not a running or durable queue.
struct WeeklyExperienceRewardSchedule: Equatable {
  static let maximumAttempts = 23
  static let retryDelayMilliseconds = 3_600_000
  let partitionKey: Int
  let dueMilliseconds: Int
  var identity: String { "weekly-experience:\(partitionKey)" }
  init(partitionKey: Int) throws {
    guard partitionKey % WeeklyExperiencePartition.day == 0,
      abs(Double(partitionKey)) <= 8_640_000_000_000_000 else {
      throw WeeklyExperienceSettlementError.invalidClock
    }
    self.partitionKey = partitionKey
    dueMilliseconds = partitionKey + WeeklyExperiencePartition.week + 60_000
  }
  func delayMilliseconds(at now: Date) throws -> Int {
    let value = now.timeIntervalSince1970 * 1_000
    guard value.isFinite, abs(value) <= 8_640_000_000_000_000 else {
      throw WeeklyExperienceSettlementError.invalidClock
    }
    // Preserve the source's raw negative delay; dispatch policy belongs to the queue.
    let delay = dueMilliseconds - Int(value.rounded(.towardZero))
    guard abs(Double(delay)) <= 9_007_199_254_740_991 else { throw WeeklyExperienceSettlementError.invalidClock }
    return delay
  }
}

/// Unclaimed mail candidates only. No account XP, storage or delivery mutation.
struct WeeklyExperienceRewardCandidate: Equatable {
  let userID: UUID
  let rank: Int
  let totalExperience: Double
  let timeTypedSeconds: Double
  let rewardExperience: Int
}

enum WeeklyExperienceSettlementPlanner {
  static func reward(for rank: Int, brackets: [WeeklyExperienceRewardBracket]) throws -> Double? {
    guard rank >= 0, rank <= 9_007_199_254_740_991 else { throw WeeklyExperienceSettlementError.invalidEntry }
    var highest: Double?
    for bracket in brackets {
      try bracket.validate()
      guard rank >= bracket.minRank, rank <= bracket.maxRank else { continue }
      let reward: Double
      if bracket.minRank == bracket.maxRank { reward = Double(bracket.maxReward) }
      else {
        // Match the pinned JS operation order before clamping and final mail rounding.
        let value = Double(rank - bracket.minRank) * Double(bracket.minReward - bracket.maxReward)
          / Double(bracket.maxRank - bracket.minRank) + Double(bracket.maxReward)
        reward = min(Double(max(bracket.minReward,bracket.maxReward)),
          max(Double(min(bracket.minReward,bracket.maxReward)),value))
      }
      highest = max(highest ?? reward,reward)
    }
    return highest
  }

  static func queryPageSize(configuration: WeeklyExperienceLeaderboardConfiguration) throws -> Int? {
    try configuration.validate()
    guard configuration.enabled else { return nil }
    guard let maxRank = configuration.xpRewardBrackets.map(\.maxRank).max() else {
      // The source's length < 0 guard does not protect Math.max(...[]) = -Infinity.
      throw WeeklyExperienceSettlementError.emptyRewardBrackets
    }
    return maxRank
  }

  static func prepare(entries: [WeeklyExperienceCache.Entry],
    configuration: WeeklyExperienceLeaderboardConfiguration, inboxEnabled: Bool
  ) throws -> [WeeklyExperienceRewardCandidate] {
    guard let pageSize = try queryPageSize(configuration:configuration) else { return [] }
    guard Set(entries.map(\.userID)).count == entries.count,
      entries.allSatisfy({ $0.score.isFinite && $0.score > 0 && $0.score <= 9_007_199_254_740_991
        && $0.timeTypedSeconds.isFinite && (0...9_007_199_254_740_991).contains($0.timeTypedSeconds) }) else {
      throw WeeklyExperienceSettlementError.invalidEntry
    }
    let ordered = entries.sorted {
      $0.score != $1.score ? $0.score > $1.score : $0.userID.uuidString > $1.userID.uuidString
    }
    var candidates: [WeeklyExperienceRewardCandidate] = []
    for (index,entry) in ordered.enumerated() where index < pageSize {
      guard let raw = try reward(for:index + 1,brackets:configuration.xpRewardBrackets) else { continue }
      candidates.append(.init(userID:entry.userID,rank:index + 1,
        totalExperience:WeeklyExperiencePublicScore.project(entry.score),timeTypedSeconds:entry.timeTypedSeconds,
        rewardExperience:Int(raw.rounded(.toNearestOrAwayFromZero))))
    }
    // Inbox disabled suppresses DAL insertion, not the preceding worker query.
    return inboxEnabled ? candidates : []
  }
}
