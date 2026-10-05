import Vapor

/// Identifies one leaderboard view whose last observed personal rank should be
/// remembered for the authenticated account. The selection contains only
/// ranking filters and an ordinal rank; it never stores result payloads,
/// credentials, or profile data.
public struct LeaderboardRankMemoryRequest: Content, Equatable {
  public let mode2: String?
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
    rank: Int, mode2: String? = nil
  ) {
    self.kind = kind
    self.scope = scope
    self.period = period
    self.mode = mode
    self.language = language
    self.durationSeconds = durationSeconds
    self.wordLimit = wordLimit
    self.rank = rank
    self.mode2 = mode2
  }
  private enum CodingKeys: String, CodingKey {
    case kind, scope, period, mode, language, durationSeconds, wordLimit, rank, mode2
  }
  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(kind: try values.decode(String.self, forKey: .kind),
      scope: try values.decode(String.self, forKey: .scope), period: try values.decode(String.self, forKey: .period),
      mode: try values.decodeIfPresent(String.self, forKey: .mode), language: try values.decodeIfPresent(String.self, forKey: .language),
      durationSeconds: try values.decodeIfPresent(Int.self, forKey: .durationSeconds), wordLimit: try values.decodeIfPresent(Int.self, forKey: .wordLimit),
      rank: try values.decode(Int.self, forKey: .rank), mode2: values.contains(.mode2) ? try values.decode(String.self, forKey: .mode2) : nil)
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
