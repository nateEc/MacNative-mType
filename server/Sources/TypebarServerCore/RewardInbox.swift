import Foundation
import Vapor

public enum RewardInboxError: Error, Equatable {
  case disabled, invalidConfiguration, invalidState, invalidRequest, unsafeArithmetic
}

public struct RewardInboxConfiguration: Codable, Equatable, Sendable {
  public let enabled: Bool
  public let maxMail: Int
  public init(enabled: Bool, maxMail: Int) { self.enabled = enabled; self.maxMail = maxMail }
  /// Typebar's deployment choice, not Monkeytype's base or live configuration.
  public static let typebarDefault = Self(enabled:true,maxMail:100)
  public static func fromJSON(_ text: String?) throws -> Self {
    let value = try text.map { try JSONDecoder().decode(Self.self,from:Data($0.utf8)) } ?? .typebarDefault
    try value.validate(); return value
  }
  func validate() throws {
    guard (0...9_007_199_254_740_991).contains(maxMail) else { throw RewardInboxError.invalidConfiguration }
  }
}

public enum InboxReward: Content, Equatable, Sendable {
  case xp(Int)
  case badge(PublicProfileBadge)
  private enum CodingKeys: String, CodingKey { case type, item }
  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy:CodingKeys.self)
    switch try values.decode(String.self,forKey:.type) {
    case "xp": self = .xp(try values.decode(Int.self,forKey:.item))
    case "badge": self = .badge(try values.decode(PublicProfileBadge.self,forKey:.item))
    default: throw RewardInboxError.invalidState
    }
  }
  public func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy:CodingKeys.self)
    switch self {
    case .xp(let xp): try values.encode("xp",forKey:.type); try values.encode(xp,forKey:.item)
    case .badge(let badge): try values.encode("badge",forKey:.type); try values.encode(badge,forKey:.item)
    }
  }
  func validate() throws {
    switch self {
    case .xp(let xp):
      guard abs(Double(xp)) <= 9_007_199_254_740_991 else { throw RewardInboxError.unsafeArithmetic }
    case .badge(let badge):
      guard !badge.id.isEmpty, badge.id.count <= 64, !badge.title.isEmpty, badge.title.count <= 80,
        !badge.systemImage.isEmpty, badge.systemImage.count <= 80 else { throw RewardInboxError.invalidState }
    }
  }
}

public struct RewardMail: Content, Equatable, Sendable, Identifiable {
  public let id: UUID
  public let subject: String
  public let body: String
  public let timestamp: Int
  public var read: Bool
  public var rewards: [InboxReward]
  public init(id: UUID = UUID(), subject: String, body: String, timestamp: Int, read: Bool = false,
    rewards: [InboxReward] = []) {
    self.id = id; self.subject = subject; self.body = body; self.timestamp = timestamp
    self.read = read; self.rewards = rewards
  }
  func validate() throws {
    guard (0...8_640_000_000_000_000).contains(timestamp), !read || rewards.isEmpty else {
      throw RewardInboxError.invalidState
    }
    for reward in rewards { try reward.validate() }
  }
}

public struct RewardInboxResponse: Content, Equatable {
  public let inbox: [RewardMail]
  public let maxMail: Int
}

public struct RewardInboxUpdateRequest: Content, Equatable, Sendable {
  public let mailIdsToMarkRead: [UUID]?
  public let mailIdsToDelete: [UUID]?
  public init(mailIdsToMarkRead: [UUID]? = nil, mailIdsToDelete: [UUID]? = nil) {
    self.mailIdsToMarkRead = mailIdsToMarkRead; self.mailIdsToDelete = mailIdsToDelete
  }
  func validate() throws {
    guard mailIdsToMarkRead?.isEmpty != true, mailIdsToDelete?.isEmpty != true else {
      throw RewardInboxError.invalidRequest
    }
  }
  private struct Key: CodingKey {
    var stringValue: String; var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
  }
  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy:Key.self)
    guard Set(values.allKeys.map(\.stringValue)).isSubset(of:["mailIdsToMarkRead","mailIdsToDelete"]) else {
      throw RewardInboxError.invalidRequest
    }
    let read = Key(stringValue:"mailIdsToMarkRead")!, delete = Key(stringValue:"mailIdsToDelete")!
    self.init(mailIdsToMarkRead:values.contains(read) ? try values.decode([UUID].self,forKey:read) : nil,
      mailIdsToDelete:values.contains(delete) ? try values.decode([UUID].self,forKey:delete) : nil)
    try validate()
  }
  public func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy:Key.self)
    try values.encodeIfPresent(mailIdsToMarkRead,forKey:Key(stringValue:"mailIdsToMarkRead")!)
    try values.encodeIfPresent(mailIdsToDelete,forKey:Key(stringValue:"mailIdsToDelete")!)
  }
}

public struct RewardInboxUpdateResponse: Content {
  public let inbox: [RewardMail]
  public let maxMail: Int
  public let user: AuthUserResponse
}

/// Mail storage and claim credit are independent from deletable result history.
struct RewardInboxState: Codable {
  struct Identity: Hashable { let userID:UUID; let mailID:UUID }
  struct Delivery: Codable {
    let userID:UUID; let mailID:UUID
    var identity:Identity { .init(userID:userID,mailID:mailID) }
  }
  struct OwnedMail: Codable { let userID:UUID; var mail:RewardMail }
  struct Claim: Codable {
    let userID:UUID; let mailID:UUID; let xp:Int; let timestamp:Int
    var identity:Identity { .init(userID:userID,mailID:mailID) }
  }
  struct OwnedBadge: Codable { let userID:UUID; let badge:PublicProfileBadge }
  let version: Int
  var deliveries: [Delivery]
  var mails: [OwnedMail]
  var claims: [Claim]
  var badges: [OwnedBadge]
  init() { version = 1; deliveries = []; mails = []; claims = []; badges = [] }
  func inbox(for userID: UUID) -> [RewardMail] { mails.filter { $0.userID == userID }.map(\.mail) }
  func experience(for userID: UUID) -> Int { claims.filter { $0.userID == userID }.reduce(0) { $0 + $1.xp } }
  func inventory(for userID: UUID) -> [PublicProfileBadge] { badges.filter { $0.userID == userID }.map(\.badge) }
  static func timestamp(_ date: Date) throws -> Int {
    let milliseconds = date.timeIntervalSince1970 * 1_000
    guard milliseconds.isFinite, (0...8_640_000_000_000_000).contains(milliseconds) else { throw RewardInboxError.invalidState }
    return Int(milliseconds.rounded(.towardZero))
  }
  static func adding(_ lhs: Int, _ rhs: Int) throws -> Int {
    let (sum,overflow) = lhs.addingReportingOverflow(rhs)
    guard !overflow, abs(Double(sum)) <= 9_007_199_254_740_991 else { throw RewardInboxError.unsafeArithmetic }
    return sum
  }
  @discardableResult
  mutating func insert(_ mail: RewardMail, for userID: UUID, configuration: RewardInboxConfiguration) throws -> Bool {
    try configuration.validate()
    guard configuration.enabled else { return false }
    try mail.validate()
    guard !mail.read else { throw RewardInboxError.invalidState }
    let identity = Identity(userID:userID,mailID:mail.id)
    guard !deliveries.contains(where: { $0.identity == identity }) else { return false }
    deliveries.append(.init(userID:userID,mailID:mail.id))
    mails.insert(.init(userID:userID,mail:mail),at:0)
    let retained = Set(inbox(for:userID).prefix(configuration.maxMail).map(\.id))
    mails.removeAll { $0.userID == userID && !retained.contains($0.mail.id) }
    return true
  }
  mutating func update(_ request: RewardInboxUpdateRequest, for userID: UUID, totalExperience: Int,
    existingBadges: [PublicProfileBadge], now: Date) throws {
    try request.validate()
    let timestamp = try Self.timestamp(now)
    let deleted = Set(request.mailIdsToDelete ?? [])
    let read = Set(request.mailIdsToMarkRead ?? []).subtracting(deleted)
    let owned = inbox(for:userID)
    // Source reward order is the read selection followed by the delete selection.
    let selected = owned.filter { read.contains($0.id) && !$0.read }
      + owned.filter { deleted.contains($0.id) && !$0.read }
    var gain = 0
    for mail in selected {
      for reward in mail.rewards { if case .xp(let xp) = reward { gain = try Self.adding(gain,xp) } }
    }
    _ = try Self.adding(totalExperience,gain)
    _ = try Self.adding(experience(for:userID),gain)
    var merged = inventory(for:userID), badgeIDs = Set(merged.map(\.id))
    for badge in existingBadges where badgeIDs.insert(badge.id).inserted { merged.append(badge) }
    for mail in selected {
      var xp = 0
      for reward in mail.rewards {
        switch reward {
        case .xp(let value): xp = try Self.adding(xp,value)
        case .badge(let badge): if badgeIDs.insert(badge.id).inserted { merged.append(badge) }
        }
      }
      claims.append(.init(userID:userID,mailID:mail.id,xp:xp,timestamp:timestamp))
    }
    badges.removeAll { $0.userID == userID }
    badges.append(contentsOf:merged.map { .init(userID:userID,badge:$0) })
    var remaining: [(position:Int,mail:RewardMail)] = []
    for (index,mail) in owned.enumerated() where !deleted.contains(mail.id) {
      var value = mail
      if read.contains(mail.id), !mail.read { value.read = true; value.rewards = [] }
      remaining.append((index,value))
    }
    remaining.sort { lhs,rhs in
      if lhs.mail.timestamp != rhs.mail.timestamp { return lhs.mail.timestamp > rhs.mail.timestamp }
      return lhs.position < rhs.position
    }
    mails.removeAll { $0.userID == userID }
    mails.append(contentsOf:remaining.map { OwnedMail(userID:userID,mail:$0.mail) })
  }
  mutating func purge(userID: UUID) {
    deliveries.removeAll { $0.userID == userID }; mails.removeAll { $0.userID == userID }
    claims.removeAll { $0.userID == userID }; badges.removeAll { $0.userID == userID }
  }
  func validate(users: Set<UUID>) throws {
    let receiptIDs = Set(deliveries.map(\.identity)), claimIDs = Set(claims.map(\.identity))
    guard version == 1, receiptIDs.count == deliveries.count, claimIDs.count == claims.count,
      Set(mails.map { Identity(userID:$0.userID,mailID:$0.mail.id) }).count == mails.count,
      deliveries.allSatisfy({ users.contains($0.userID) }), claimIDs.isSubset(of:receiptIDs) else {
      throw RewardInboxError.invalidState
    }
    for mail in mails {
      try mail.mail.validate()
      let identity = Identity(userID:mail.userID,mailID:mail.mail.id)
      guard receiptIDs.contains(identity), mail.mail.read == claimIDs.contains(identity) else { throw RewardInboxError.invalidState }
    }
    for claim in claims {
      guard users.contains(claim.userID), abs(Double(claim.xp)) <= 9_007_199_254_740_991,
        (0...8_640_000_000_000_000).contains(claim.timestamp) else { throw RewardInboxError.invalidState }
    }
    for user in users {
      var sum = 0
      for claim in claims where claim.userID == user { sum = try Self.adding(sum,claim.xp) }
      let inventory = inventory(for:user)
      guard Set(inventory.map(\.id)).count == inventory.count else { throw RewardInboxError.invalidState }
    }
    for badge in badges {
      guard users.contains(badge.userID) else { throw RewardInboxError.invalidState }
      try InboxReward.badge(badge.badge).validate()
    }
  }
}
