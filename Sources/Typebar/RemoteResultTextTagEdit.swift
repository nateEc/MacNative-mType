import Foundation

/// Scope and generation of mutable service metadata, not a completion receipt.
struct ResultTextTagEditRead {
  let scope: ResultPublicationScope
  let revision: UInt64
  let lastGeneration: UInt64
  let nonce: UUID
  let previous: RemoteAccountResult
}

enum RemoteResultTextTagEditPolicy {
  static func requestedTags(_ values: [String]) throws -> [String] {
    let invalid = RemoteAccountError.serverMessage("文字标签最多 \(ResultTagPolicy.maximumCount) 个，每个为 1–\(ResultTagPolicy.maximumLength) 个字符，不能留空或重复。")
    guard values.count <= ResultTagPolicy.maximumCount else { throw invalid }
    var seen = Set<String>()
    return try values.map { value in
      let tag = value.trimmingCharacters(in: .whitespacesAndNewlines)
      let key = tag.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
      guard !tag.isEmpty, tag.count <= ResultTagPolicy.maximumLength, seen.insert(key).inserted
      else { throw invalid }
      return tag
    }
  }
  static func confirmedMetadata(_ response: RemoteAccountResult, previous: RemoteAccountResult,
    requestedTags: [String], knownIDs: Set<UUID>?) throws -> RemoteAccountResult {
    var normalized = response, expected = previous
    if let knownIDs {
      normalized.accountTagIDs = normalized.accountTagIDs?.filter { knownIDs.contains($0) }
      expected.accountTagIDs = expected.accountTagIDs?.filter { knownIDs.contains($0) }
    }
    expected.tags = try self.requestedTags(requestedTags)
    guard normalized == expected else { throw RemoteAccountError.unexpectedResponse }
    return normalized
  }
}
