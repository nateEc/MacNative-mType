import Foundation
import Vapor

public struct WeeklyExperienceRewardJob: Content, Equatable, Sendable {
  public enum Status: String, Codable, Sendable { case pending, complete, failed }
  public let key: Int
  public var attempts: Int
  public var nextAttempt: Int
  public var status: Status
  public var lastFailure: String?
  init(key: Int) throws {
    self.key = key; attempts = 0
    nextAttempt = try WeeklyExperienceRewardSchedule(partitionKey:key).dueMilliseconds
    status = .pending; lastFailure = nil
  }
  func validate() throws {
    let due = try WeeklyExperienceRewardSchedule(partitionKey:key).dueMilliseconds
    guard (0...23).contains(attempts), nextAttempt >= due,
      abs(Double(nextAttempt)) <= 9_007_199_254_740_991 else { throw RewardInboxError.invalidState }
    switch status {
    case .pending:
      guard attempts < 23, (attempts == 0) == (lastFailure == nil),
        attempts != 0 || nextAttempt == due else { throw RewardInboxError.invalidState }
    case .complete: guard attempts > 0, lastFailure == nil else { throw RewardInboxError.invalidState }
    case .failed: guard attempts == 23, lastFailure != nil else { throw RewardInboxError.invalidState }
    }
    if let lastFailure, !["emptyRewardBrackets","invalidRewardState"].contains(lastFailure) { throw RewardInboxError.invalidState }
  }
}

struct WeeklyExperienceRewardJobs: Codable {
  let version: Int
  var jobs: [WeeklyExperienceRewardJob]
  init() { version = 1; jobs = [] }
  mutating func schedule(key: Int) throws {
    guard !jobs.contains(where: { $0.key == key }) else { return }
    jobs.append(try .init(key:key))
  }
  func validate(awards: [ExperienceAwardRecord]) throws {
    let keys = Set(jobs.map(\.key))
    guard version == 1, keys.count == jobs.count else { throw RewardInboxError.invalidState }
    for job in jobs { try job.validate() }
    for award in awards where award.weeklyCacheReceipt?.settlementScheduled == true {
      guard let key = award.weeklyPartition?.keyMilliseconds, keys.contains(key) else { throw RewardInboxError.invalidState }
    }
  }
}

/// A single-service actor worker, not a distributed BullMQ replacement.
public actor WeeklyExperienceRewardWorker: LifecycleHandler {
  private let store: AuthStore
  private let intervalNanoseconds: UInt64
  private let logger: Logger
  private var task: Task<Void,Never>?
  private var generation: UInt64 = 0
  public init(store: AuthStore, intervalNanoseconds: UInt64 = 60_000_000_000,
    logger: Logger = .init(label:"typebar.weekly-rewards")) {
    self.store = store; self.intervalNanoseconds = max(1,intervalNanoseconds); self.logger = logger
  }
  public func start() {
    guard task == nil else { return }
    generation &+= 1
    let interval = intervalNanoseconds
    task = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        await self.runOnce()
        do { try await Task.sleep(nanoseconds:interval) } catch { return }
      }
    }
  }
  public func stop() async {
    let previous = task, stoppingGeneration = generation
    previous?.cancel(); await previous?.value
    if generation == stoppingGeneration { task = nil }
  }
  private func runOnce() async {
    do {
      let jobs = try await store.processDueWeeklyExperienceRewards()
      for job in jobs where job.lastFailure != nil {
        logger.error("Weekly reward task failed",metadata:["key":"\(job.key)","attempt":"\(job.attempts)",
          "failure":"\(job.lastFailure ?? "unknown")"])
      }
    } catch { logger.error("Weekly reward persistence failed; pending state retained") }
  }
  public func didBootAsync(_ application: Application) async throws { start() }
  public func shutdownAsync(_ application: Application) async { await stop() }
}
