import Vapor

/// Identifies one leaderboard view whose last observed personal rank should be
/// remembered for the authenticated account. The selection contains only
/// ranking filters and an ordinal rank; it never stores result payloads,
/// credentials, or profile data.
public struct LeaderboardRankMemoryRequest: Content, Equatable {
  public let kind: String
  public let scope: String
  public let period: String
  public let mode: String?
  public let language: String?
  public let durationSeconds: Int?
  public let wordLimit: Int?
  public let rank: Int

  public init(
    kind: String, scope: String, period: String, mode: String? = nil,
    language: String? = nil, durationSeconds: Int? = nil, wordLimit: Int? = nil,
    rank: Int
  ) {
    self.kind = kind
    self.scope = scope
    self.period = period
    self.mode = mode
    self.language = language
    self.durationSeconds = durationSeconds
    self.wordLimit = wordLimit
    self.rank = rank
  }
}

/// Returned atomically with a successful rank-memory update. A missing value
/// means this account has not previously checked this exact leaderboard view.
public struct LeaderboardRankMemoryResponse: Content, Equatable {
  public let previousRank: Int?

  public init(previousRank: Int?) {
    self.previousRank = previousRank
  }
}
