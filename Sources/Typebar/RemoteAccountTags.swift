import Foundation

enum RemoteAccountTagPolicy {
  static func normalizedName(_ value: String) -> String { value.split(whereSeparator: \.isWhitespace).joined(separator: "_") }
  static func isValidName(_ name: String) -> Bool {
    let bytes = Array(name.utf8)
    guard (1...16).contains(bytes.count) else { return false }
    var previousWasLetter = false
    for byte in bytes {
      if (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) { previousWasLetter = true }
      else {
        guard previousWasLetter, byte == 45 || byte == 95 else { return false }
        previousWasLetter = false
      }
    }
    return previousWasLetter
  }
  static func validateIDs(_ ids: [UUID]) throws {
    guard ids.count <= 15, Set(ids).count == ids.count else { throw RemoteAccountError.unexpectedResponse }
  }
  static func prepare(ids: [UUID], capabilities: RemoteServiceCapabilities?) throws -> [UUID]? {
    try validateIDs(ids)
    guard !ids.isEmpty else { return nil }
    guard capabilities?.supportsAccountTags == true else {
      throw RemoteAccountError.serverMessage("当前自建服务不支持账户标签 ID；请先升级服务，本机成绩保留。")
    }
    return ids
  }
}

struct RemoteAccountTag: Codable, Identifiable, Sendable {
  let id: UUID
  let name: String
  let personalBestLedgerVersion: Int
  let personalBests: [RemotePublicProfileBest]
  var displayName: String { name.replacingOccurrences(of: "_", with: " ") }
  private enum CodingKeys: String, CodingKey { case id, name, personalBestLedgerVersion, personalBests }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    name = try values.decode(String.self, forKey: .name)
    personalBestLedgerVersion = try values.decode(Int.self, forKey: .personalBestLedgerVersion)
    personalBests = try values.decode([RemotePublicProfileBest].self, forKey: .personalBests)
    guard personalBestLedgerVersion == 1, RemoteAccountTagPolicy.isValidName(name),
      Set(personalBests.map(\.groupKey)).count == personalBests.count,
      personalBests.allSatisfy({ $0.mode != "quote" && $0.personalBestOrigin == "accepted" && $0.acceptedAtMilliseconds != nil })
    else { throw RemoteAccountError.unexpectedResponse }
    for best in personalBests { try best.validateLedgerSnapshot() }
  }
}
struct RemoteAccountTagList: Decodable, Sendable {
  let version: Int
  let tags: [RemoteAccountTag]
  private enum CodingKeys: String, CodingKey { case version, tags }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    version = try values.decode(Int.self, forKey: .version)
    tags = try values.decode([RemoteAccountTag].self, forKey: .tags)
    guard version == 1 else { throw RemoteAccountError.unexpectedResponse }
    try RemoteAccountTagPolicy.validateIDs(tags.map(\.id))
  }
}
struct RemoteAccountTagNameRequest: Encodable, Sendable { let name: String }
struct RemoteAccountResultTagIDsRequest: Encodable, Sendable { let tagIDs: [UUID] }
struct RemoteAccountTagDeletion: Decodable, Sendable { let deleted: Bool }

/// Device-local posting selection, partitioned by authenticated account/server.
/// Names, credentials and PB payloads are never cached in defaults here.
struct RemoteAccountTagSelectionStore {
  let defaults: UserDefaults
  private func key(_ scope: ResultPublicationScope) -> String { "typebar.account-tag-selection.v1.\(scope.serverID).\(scope.userID)" }
  func ids(for scope: ResultPublicationScope) throws -> [UUID] {
    guard let raw = defaults.object(forKey: key(scope)) else { return [] }
    guard let strings = raw as? [String], strings.count <= 15 else { throw RemoteAccountError.unexpectedResponse }
    let ids = strings.compactMap(UUID.init(uuidString:))
    guard ids.count == strings.count else { throw RemoteAccountError.unexpectedResponse }
    try RemoteAccountTagPolicy.validateIDs(ids)
    return ids
  }
  func set(_ ids: [UUID], for scope: ResultPublicationScope) throws {
    try RemoteAccountTagPolicy.validateIDs(ids)
    defaults.set(ids.map(\.uuidString), forKey: key(scope))
  }
}
