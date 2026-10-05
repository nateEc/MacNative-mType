import Foundation
import CoreFoundation

enum RemoteInboxReward: Codable, Equatable, Sendable {
  case xp(Int)
  case badge(RemotePublicProfileBadge)
  private enum CodingKeys: String, CodingKey { case type, item }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy:CodingKeys.self)
    switch try values.decode(String.self,forKey:.type) {
    case "xp":
      let value = try values.decode(Int.self,forKey:.item)
      guard abs(Double(value)) <= 9_007_199_254_740_991 else { throw RemoteAccountError.unexpectedResponse }
      self = .xp(value)
    case "badge":
      let badge = try values.decode(RemotePublicProfileBadge.self,forKey:.item)
      guard !badge.id.isEmpty, badge.id.count <= 64, !badge.title.isEmpty, badge.title.count <= 80,
        !badge.systemImage.isEmpty, badge.systemImage.count <= 80 else { throw RemoteAccountError.unexpectedResponse }
      self = .badge(badge)
    default: throw RemoteAccountError.unexpectedResponse
    }
  }
  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy:CodingKeys.self)
    switch self {
    case .xp(let value): try values.encode("xp",forKey:.type); try values.encode(value,forKey:.item)
    case .badge(let badge): try values.encode("badge",forKey:.type); try values.encode(badge,forKey:.item)
    }
  }
  var label: String {
    switch self {
    case .xp(let value): "\(value) XP"
    case .badge(let badge): badge.title
    }
  }
}

struct RemoteRewardMail: Codable, Equatable, Sendable, Identifiable {
  let id: UUID
  let subject: String
  let body: String
  let timestamp: Int
  let read: Bool
  let rewards: [RemoteInboxReward]
  var unclaimed: Bool { !read && !rewards.isEmpty }
  var statusLabel: String { unclaimed ? "待领取" : read ? "已读" : "未读" }
  var date: Date { Date(timeIntervalSince1970:Double(timestamp)/1_000) }
  private enum CodingKeys: String, CodingKey { case id, subject, body, timestamp, read, rewards }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy:CodingKeys.self)
    id = try values.decode(UUID.self,forKey:.id)
    subject = try values.decode(String.self,forKey:.subject)
    body = try values.decode(String.self,forKey:.body)
    timestamp = try values.decode(Int.self,forKey:.timestamp)
    read = try values.decode(Bool.self,forKey:.read)
    rewards = try values.decode([RemoteInboxReward].self,forKey:.rewards)
    guard (0...8_640_000_000_000_000).contains(timestamp), !read || rewards.isEmpty else {
      throw RemoteAccountError.unexpectedResponse
    }
  }
}

struct RemoteRewardInbox: Decodable, Equatable, Sendable {
  let inbox: [RemoteRewardMail]
  let maxMail: Int
  private enum CodingKeys: String, CodingKey { case inbox, maxMail }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy:CodingKeys.self)
    inbox = try values.decode([RemoteRewardMail].self,forKey:.inbox)
    maxMail = try values.decode(Int.self,forKey:.maxMail)
    guard (0...9_007_199_254_740_991).contains(maxMail), Set(inbox.map(\.id)).count == inbox.count else {
      throw RemoteAccountError.unexpectedResponse
    }
  }
}

struct RemoteRewardInboxUpdate: Encodable, Sendable {
  let mailIdsToMarkRead: [UUID]?
  let mailIdsToDelete: [UUID]?
  init(mailIdsToMarkRead: [UUID]? = nil, mailIdsToDelete: [UUID]? = nil) {
    self.mailIdsToMarkRead = mailIdsToMarkRead; self.mailIdsToDelete = mailIdsToDelete
  }
}

struct RemoteRewardInboxUpdateResponse: Decodable, Sendable {
  let mailbox: RemoteRewardInbox
  let user: RemoteAccountUser
  private enum CodingKeys: String, CodingKey { case user }
  init(from decoder: Decoder) throws {
    mailbox = try .init(from:decoder)
    user = try decoder.container(keyedBy:CodingKeys.self).decode(RemoteAccountUser.self,forKey:.user)
  }
}

enum RewardInboxPresentation {
  static func ordered(_ inbox: [RemoteRewardMail], locale: Locale = .current) -> [RemoteRewardMail] {
    let comparisonLocale = locale as NSLocale
    return inbox.enumerated().sorted { lhs,rhs in
      if lhs.element.timestamp != rhs.element.timestamp { return lhs.element.timestamp > rhs.element.timestamp }
      // Normalize comparison operands only; do not alter visible mail text.
      // Foundation's String.compare wrapper differs for Chinese accent order.
      let left = lhs.element.subject.precomposedStringWithCanonicalMapping
      let right = rhs.element.subject.precomposedStringWithCanonicalMapping
      let comparison = CFStringCompareWithOptionsAndLocale(left as CFString,right as CFString,
        CFRange(location:0,length:left.utf16.count),[],comparisonLocale)
      if comparison.rawValue != 0 { return comparison.rawValue < 0 }
      return lhs.offset < rhs.offset
    }.map(\.element)
  }
  static func claimable(_ inbox: [RemoteRewardMail]) -> [UUID] { inbox.filter(\.unclaimed).map(\.id) }
  static func deletable(_ inbox: [RemoteRewardMail]) -> [UUID] {
    claimable(inbox).isEmpty ? inbox.map(\.id) : []
  }
}

enum RewardInboxScopePolicy {
  static func accepts(requested: ResultPublicationScope?, current: ResultPublicationScope?, returnedUserID: UUID? = nil) -> Bool {
    guard let requested, current == requested else { return false }
    return returnedUserID == nil || returnedUserID == requested.userID
  }
}
