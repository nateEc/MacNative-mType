import Foundation
import Vapor

public struct DailyLeaderboardRewardJob: Content, Equatable, Sendable {
  public enum Status: String, Codable, Sendable { case pending, complete, failed }
  public let key: Int
  public let modeRule: DailyLeaderboardModeRule
  public var attempts: Int
  public var nextAttempt: Int
  public var status: Status
  public var lastFailure: String?
  var identity: String { "\(key)/\(modeRule.language)/\(modeRule.mode)/\(modeRule.mode2)" }
  static let maximumAttempts = 23
  static let retryDelayMilliseconds = 3_600_000
  static func due(key: Int) throws -> Int {
    guard key >= 0, key % 86_400_000 == 0, key <= 8_640_000_000_000_000 - 86_460_000 else {
      throw RewardInboxError.invalidState
    }
    return key + 86_460_000
  }
  init(key: Int, modeRule: DailyLeaderboardModeRule) throws {
    self.key = key; self.modeRule = modeRule; attempts = 0
    nextAttempt = try Self.due(key:key); status = .pending; lastFailure = nil
  }
  func validate() throws {
    let due = try Self.due(key:key)
    guard !modeRule.language.isEmpty, modeRule.language.count <= 100,
      ResultMode2Policy.isValid(modeRule.mode2, mode: modeRule.mode),
      (0...Self.maximumAttempts).contains(attempts), nextAttempt >= due,
      nextAttempt <= 9_007_199_254_740_991 else { throw RewardInboxError.invalidState }
    switch status {
    case .pending:
      guard attempts < Self.maximumAttempts, (attempts == 0) == (lastFailure == nil),
        attempts != 0 || nextAttempt == due else { throw RewardInboxError.invalidState }
    case .complete: guard attempts > 0, lastFailure == nil else { throw RewardInboxError.invalidState }
    case .failed: guard attempts == Self.maximumAttempts, lastFailure != nil else { throw RewardInboxError.invalidState }
    }
    guard lastFailure == nil || lastFailure == "invalidRewardState" else { throw RewardInboxError.invalidState }
  }
}

struct DailyLeaderboardRewardJobs: Codable {
  let version: Int
  var jobs: [DailyLeaderboardRewardJob]
  init() { version = 1; jobs = [] }
  mutating func schedule(key: Int, entry: DailyLeaderboardCache.Entry) throws {
    let job = try DailyLeaderboardRewardJob(key:key,
      modeRule:.init(language:entry.language,mode:entry.mode,mode2:entry.mode2))
    guard !jobs.contains(where: { $0.identity == job.identity }) else { return }
    try job.validate(); jobs.append(job)
  }
  func validate(awards: [ExperienceAwardRecord]) throws {
    let identities = Set(jobs.map(\.identity))
    guard version == 1, identities.count == jobs.count else { throw RewardInboxError.invalidState }
    for job in jobs { try job.validate() }
    for award in awards where award.dailyCacheReceipt?.settlementScheduled == true {
      let receipt = award.dailyCacheReceipt!
      guard let entry = receipt.entry,
        identities.contains("\(receipt.keyMilliseconds)/\(entry.language)/\(entry.mode)/\(entry.mode2)")
      else { throw RewardInboxError.invalidState }
    }
  }
}

/// The daily worker has a positive announcement page even with no XP brackets.
/// It uses settlement-time configuration and immutable winning cache snapshots.
enum DailyLeaderboardSettlementPlanner {
  struct Placement {
    let entry: DailyLeaderboardCache.Entry
    let rank: Int
    let rewardExperience: Int?
    let announce: Bool
  }
  static func prepare(entries: [DailyLeaderboardCache.Entry], configuration: DailyLeaderboardConfiguration,
    inboxEnabled: Bool) throws -> [Placement] {
    try configuration.validate()
    guard configuration.enabled else { return [] }
    guard Set(entries.map(\.userID)).count == entries.count else { throw RewardInboxError.invalidState }
    for entry in entries { try entry.validate() }
    let pageSize = max(configuration.topResultsToAnnounce,configuration.xpRewardBrackets.map(\.maxRank).max() ?? 0)
    return try DailyLeaderboardCache.ordered(entries).prefix(pageSize).enumerated().map { index, entry in
      let rank = index + 1
      let reward = inboxEnabled ? try WeeklyExperienceSettlementPlanner.reward(for:rank,brackets:configuration.xpRewardBrackets) : nil
      return .init(entry:entry,rank:rank,rewardExperience:reward.map { Int($0.rounded(.toNearestOrAwayFromZero)) },
        announce:rank <= configuration.topResultsToAnnounce)
    }
  }
}
