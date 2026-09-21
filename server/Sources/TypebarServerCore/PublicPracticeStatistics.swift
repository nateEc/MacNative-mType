import Vapor

/// Anonymous, service-wide practice totals derived only from results that may
/// participate in Typebar's public surfaces. It contains no account identity,
/// text, input, replay, or credential data.
public struct PublicPracticeStatsResponse: Content, Equatable, Sendable {
  public let completedResultCount: Int
  public let startedTestCount: Int
  public let totalTypingSeconds: Int

  public init(completedResultCount: Int, startedTestCount: Int, totalTypingSeconds: Int) {
    self.completedResultCount = completedResultCount
    self.startedTestCount = startedTestCount
    self.totalTypingSeconds = totalTypingSeconds
  }
}

public struct PublicSpeedDistributionBucket: Content, Equatable, Sendable {
  public let lowerBound: Int
  public let count: Int

  public init(lowerBound: Int, count: Int) {
    self.lowerBound = lowerBound
    self.count = count
  }
}

/// A compact, anonymous distribution of each public account's best English
/// sixty-second time result. Empty buckets are omitted so clients can render
/// their own zero-filled intervals without receiving synthetic records.
public struct PublicSpeedDistributionResponse: Content, Equatable, Sendable {
  public let bucketSize: Int
  public let buckets: [PublicSpeedDistributionBucket]

  public init(bucketSize: Int, buckets: [PublicSpeedDistributionBucket]) {
    self.bucketSize = bucketSize
    self.buckets = buckets
  }
}
