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

/// Additive flat wire response: older clients still decode AccountResultResponse.
public struct AccountResultTagEditResponse: Content, Sendable {
  public let result: AccountResultResponse
  public let tagPbs: [UUID]
  public var accountTagIDs: [UUID]? { result.accountTagIDs }
  private enum CodingKeys: String, CodingKey { case tagPbs }
  public init(result: AccountResultResponse, tagPbs: [UUID]) { self.result = result; self.tagPbs = tagPbs }
  public init(from decoder: Decoder) throws {
    result = try AccountResultResponse(from: decoder)
    tagPbs = try decoder.container(keyedBy: CodingKeys.self).decode([UUID].self, forKey: .tagPbs)
    guard tagPbs.count <= 15, Set(tagPbs).count == tagPbs.count,
      Set(tagPbs).isSubset(of: Set(result.accountTagIDs ?? [])) else { throw AccountTagError.invalidState }
  }
  public func encode(to encoder: Encoder) throws {
    try result.encode(to: encoder)
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(tagPbs, forKey: .tagPbs)
  }
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
  /// Bounded to currently retained edited PB groups, not an unbounded event log.
  struct HistoryEditAward: Codable {
    let tagID: UUID
    let source: PersonalBestSnapshot
  }
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
  var historyEditAwards: [HistoryEditAward] = []

  private enum CodingKeys: String, CodingKey { case version, tags, historyEditAwards }
  init() {}
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    version = try values.decode(Int.self, forKey: .version)
    tags = try values.decode([Tag].self, forKey: .tags)
    guard [1, 2].contains(version) else { throw AccountTagError.invalidState }
    historyEditAwards = values.contains(.historyEditAwards) || version == 2
      ? try values.decode([HistoryEditAward].self, forKey: .historyEditAwards) : []
    guard version != 1 || historyEditAwards.isEmpty else { throw AccountTagError.invalidState }
  }

  func validatedIDs(_ ids: [UUID], userID: UUID) throws -> [UUID] {
    let owned = Set(tags.filter { $0.userID == userID }.map(\.id))
    guard ids.count <= 15, Set(ids).count == ids.count, Set(ids).isSubset(of: owned) else {
      throw Abort(.unprocessableEntity, reason: "One or more account tag IDs are invalid.")
    }
    return ids
  }
  @discardableResult mutating func accept(_ candidate: PersonalBestSnapshot, tagIDs: [UUID]) -> [UUID] {
    var awarded: [UUID] = []
    for index in tags.indices where tags[index].userID == candidate.userID && tagIDs.contains(tags[index].id) {
      if let old = tags[index].personalBests.firstIndex(where: { $0.groupKey == candidate.groupKey }) {
        if candidate.effectiveWpm > tags[index].personalBests[old].effectiveWpm {
          tags[index].personalBests[old] = candidate
        } else { continue }
      } else { tags[index].personalBests.append(candidate) }
      let id = tags[index].id
      historyEditAwards.removeAll { $0.tagID == id && $0.source.groupKey == candidate.groupKey }
      awarded.append(id)
    }
    return awarded
  }
  mutating func acceptHistoryEdit(_ source: PersonalBestSnapshot, at milliseconds: Int, tagIDs: [UUID]) throws -> [UUID] {
    let updated = source.recorded(atMilliseconds: milliseconds)
    try updated.validate()
    let ids = accept(updated, tagIDs: tagIDs)
    if !ids.isEmpty {
      version = 2
      historyEditAwards += ids.map { .init(tagID: $0, source: source) }
    }
    return ids
  }
  mutating func remove(id: UUID, clearOnly: Bool) {
    historyEditAwards.removeAll { $0.tagID == id }
    if clearOnly { for index in tags.indices where tags[index].id == id { tags[index].personalBests = [] } }
    else { tags.removeAll { $0.id == id } }
  }
  mutating func purge(userID: UUID) {
    let ids = Set(tags.filter { $0.userID == userID }.map(\.id))
    historyEditAwards.removeAll { ids.contains($0.tagID) }
    tags.removeAll { $0.userID == userID }
  }
  func validate(users: Set<UUID>, awards: [ExperienceAwardRecord]) throws {
    guard [1, 2].contains(version), version != 1 || historyEditAwards.isEmpty,
      Set(tags.map(\.id)).count == tags.count else { throw AccountTagError.invalidState }
    let receipts = Dictionary(uniqueKeysWithValues: awards.map { ("\($0.userID)/\($0.resultID)", $0) })
    var proofKeys = Set<String>()
    for proof in historyEditAwards {
      let source = proof.source
      try source.validate()
      guard proofKeys.insert("\(proof.tagID)/\(source.groupKey)").inserted,
        let tag = tags.first(where: { $0.id == proof.tagID && $0.userID == source.userID }),
        let best = tag.personalBests.first(where: { $0.groupKey == source.groupKey }),
        let recordedAt = best.acceptedAtMilliseconds,
        best == source.recorded(atMilliseconds: recordedAt), source.origin == .accepted,
        let receipt = receipts["\(source.userID)/\(source.resultID)"],
        let input = receipt.rankingAdmission?.input, AccountTagEditAdmission.isEligible(input),
        source.mode == input.mode, source.effectiveAccuracy == input.accuracy,
        source.personalBestConfiguration == receipt.personalBestConfiguration,
        source.speedPrecision == receipt.speedPrecision,
        receipt.acceptedAt.map({ abs(Double(source.acceptedAtMilliseconds!) / 1_000 - $0.timeIntervalSince1970) < 1 }) == true,
        receipt.personalBestReceipt?.candidate.map({ $0 == source }) ?? input.bailedOut
      else { throw AccountTagError.invalidState }
    }
    for owner in users where tags.filter({ $0.userID == owner }).count > 15 { throw AccountTagError.invalidState }
    for tag in tags {
      guard users.contains(tag.userID), AccountTagNamePolicy.isValid(tag.name),
        Set(tag.personalBests.map(\.groupKey)).count == tag.personalBests.count else { throw AccountTagError.invalidState }
      for best in tag.personalBests {
        try best.validate()
        guard best.userID == tag.userID, best.origin == .accepted,
          let receipt = receipts["\(best.userID)/\(best.resultID)"],
          (receipt.accountTagIDs?.contains(tag.id) == true && receipt.personalBestReceipt?.candidate == best)
            || historyEditAwards.contains(where: { $0.tagID == tag.id && $0.source.groupKey == best.groupKey })
        else { throw AccountTagError.invalidState }
      }
    }
  }
}

enum AccountTagEditAdmission {
  /// The actual edit DAL has no BailOut guard; submission PB admission does.
  static func isEligible(_ input: RankingAdmissionInput) -> Bool {
    input.mode != "quote" && !(input.stopOnLetter && input.accuracy < 100)
      && input.modifiers.allSatisfy { ExperienceModifierCatalog.entries[$0]?.allowsPersonalBest == true }
  }
}

extension PersonalBestSnapshot {
  func recorded(atMilliseconds milliseconds: Int) -> Self {
    .init(userID: userID, resultID: resultID, mode: mode, mode2: mode2, language: language,
      wpm: wpm, rawWpm: rawWpm, speedPrecision: speedPrecision, accuracy: accuracy,
      preciseAccuracy: preciseAccuracy, consistency: consistency, personalBestConfiguration: personalBestConfiguration,
      completedAtReferenceTime: completedAtReferenceTime, acceptedAtMilliseconds: milliseconds, origin: origin)
  }
}
