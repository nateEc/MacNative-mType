import Foundation

/// A last-result read never creates or claims a loaded history collection.
struct AccountTagLastResultRead: Equatable {
  let scope: ResultPublicationScope
  let generation: UInt64
  let id: UUID
}

/// Client PBs exist independently of history readiness and immutable receipts.
struct AccountTagLastResultAwards {
  let scope: ResultPublicationScope
  private(set) var personalBests: [AccountTagHistoryPersonalBest] = []
  private var directory: [RemoteAccountTag]

  init(scope: ResultPublicationScope, directory: [RemoteAccountTag]) {
    self.scope = scope; self.directory = directory
  }
  mutating func save(_ ids: [UUID], from result: RemoteAccountResult, at milliseconds: Int64) throws {
    try RemoteAccountTagPolicy.validateIDs(ids)
    guard Set(ids).isSubset(of: Set(directory.map(\.id))),
      (0...8_640_000_000_000_000).contains(milliseconds) else { throw RemoteAccountError.unexpectedResponse }
    guard !ids.isEmpty, result.mode != "quote" else { return }
    guard let group = AccountTagHistoryGroup(result) else { throw RemoteAccountError.unexpectedResponse }
    _ = try AccountTagHistoryCache(scope: scope, results: [result], knownIDs: Set(directory.map(\.id)))
    for id in ids {
      personalBests.removeAll { $0.tagID == id && $0.group == group }
      personalBests.append(.init(tagID: id, group: group, wpm: result.effectiveWpm,
        rawWpm: result.effectiveRawWpm, accuracy: result.preciseAccuracy ?? Double(result.accuracy),
        consistency: result.consistency, rebuiltAtMilliseconds: milliseconds))
    }
  }
  mutating func adoptDirectory(_ tags: [RemoteAccountTag]) {
    personalBests = AccountTagHistoryPersonalBest.retained(personalBests, before: directory, after: tags)
    directory = tags
  }
  mutating func replaceOverrides(_ snapshots: [AccountTagHistoryPersonalBest]) {
    for snapshot in snapshots {
      personalBests.removeAll { $0.tagID == snapshot.tagID && $0.group == snapshot.group }
      personalBests.append(snapshot)
    }
  }
  mutating func removeTag(_ id: UUID) { personalBests.removeAll { $0.tagID == id } }
}
