import Foundation
import Vapor

public struct AccountTagNameRequest: Content, Sendable {
  public let name: String
  public init(name: String) { self.name = name }
}
public struct AccountTagResponse: Content, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let name: String
  public let personalBestLedgerVersion: Int
  public let personalBests: [PublicProfileBestResponse]
}
public struct AccountTagListResponse: Content, Sendable {
  public let version: Int
  public let tags: [AccountTagResponse]
}
public struct AccountTagDeletionResponse: Content, Sendable { public let deleted: Bool }
public struct AccountResultTagIDsRequest: Content, Sendable {
  public let tagIDs: [UUID]
  public init(tagIDs: [UUID]) { self.tagIDs = tagIDs }
}

enum AccountTagError: Error { case invalidState }

enum AccountTagNamePolicy {
  static func isValid(_ name: String) -> Bool {
    let bytes = Array(name.utf8)
    guard (1...16).contains(bytes.count) else { return false }
    var previousWasLetter = false
    for byte in bytes {
      let letter = (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
      if letter { previousWasLetter = true }
      else {
        guard previousWasLetter, byte == 45 || byte == 95 else { return false }
        previousWasLetter = false
      }
    }
    return previousWasLetter
  }
}

/// Private account directory. Display names are not identities; duplicate names
/// remain separate. Neither deleting history nor public PB clear mutates tags.
struct AccountTagDirectory: Codable {
  struct Tag: Codable {
    let id: UUID
    let userID: UUID
    var name: String
    var personalBests: [PersonalBestSnapshot] = []
    var response: AccountTagResponse {
      .init(id: id, name: name, personalBestLedgerVersion: 1, personalBests: personalBests.map(\.response))
    }
  }
  var version = 1
  var tags: [Tag] = []

  func validatedIDs(_ ids: [UUID], userID: UUID) throws -> [UUID] {
    let owned = Set(tags.filter { $0.userID == userID }.map(\.id))
    guard ids.count <= 15, Set(ids).count == ids.count, Set(ids).isSubset(of: owned) else {
      throw Abort(.unprocessableEntity, reason: "One or more account tag IDs are invalid.")
    }
    return ids
  }
  mutating func accept(_ candidate: PersonalBestSnapshot, tagIDs: [UUID]) {
    for index in tags.indices where tags[index].userID == candidate.userID && tagIDs.contains(tags[index].id) {
      if let old = tags[index].personalBests.firstIndex(where: { $0.groupKey == candidate.groupKey }) {
        if candidate.effectiveWpm > tags[index].personalBests[old].effectiveWpm {
          tags[index].personalBests[old] = candidate
        }
      } else { tags[index].personalBests.append(candidate) }
    }
  }
  func validate(users: Set<UUID>, awards: [ExperienceAwardRecord]) throws {
    guard version == 1, Set(tags.map(\.id)).count == tags.count else { throw AccountTagError.invalidState }
    let receipts = Dictionary(uniqueKeysWithValues: awards.map { ("\($0.userID)/\($0.resultID)", $0) })
    for owner in users where tags.filter({ $0.userID == owner }).count > 15 { throw AccountTagError.invalidState }
    for tag in tags {
      guard users.contains(tag.userID), AccountTagNamePolicy.isValid(tag.name),
        Set(tag.personalBests.map(\.groupKey)).count == tag.personalBests.count else { throw AccountTagError.invalidState }
      for best in tag.personalBests {
        try best.validate()
        guard best.userID == tag.userID, best.origin == .accepted,
          let receipt = receipts["\(best.userID)/\(best.resultID)"],
          receipt.accountTagIDs?.contains(tag.id) == true,
          receipt.personalBestReceipt?.candidate == best else { throw AccountTagError.invalidState }
      }
    }
  }
}
