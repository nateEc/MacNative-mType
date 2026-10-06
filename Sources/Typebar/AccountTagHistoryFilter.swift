import Foundation

/// Mutable account-history metadata is distinct from immutable completion evidence.
/// Nil IDs remain unknown, not an explicit empty association.
struct ResultHistoryAccountTagMetadata: Equatable {
  let scope: ResultPublicationScope
  let tagIDs: [UUID]?
}

struct ResultHistoryAccountTagFilter: Codable, Equatable {
  let scope: ResultPublicationScope
  private(set) var knownIDs: Set<UUID>
  var selectedIDs: Set<UUID>
  var includesNoTags: Bool

  init(scope: ResultPublicationScope, knownIDs: Set<UUID>, selectedIDs: Set<UUID>, includesNoTags: Bool) {
    self.scope = scope; self.knownIDs = knownIDs
    self.selectedIDs = selectedIDs; self.includesNoTags = includesNoTags
  }

  func matches(_ metadata: ResultHistoryAccountTagMetadata?) -> Bool {
    guard let metadata, metadata.scope == scope, let ids = metadata.tagIDs,
      (try? RemoteAccountTagPolicy.validateIDs(ids)) != nil else { return false }
    let retained = Set(ids).intersection(knownIDs)
    return includesNoTags && retained.isEmpty || !selectedIDs.isDisjoint(with: retained)
  }

  /// Directory additions default on; removals prune IDs; existing off choices survive.
  /// A foreign account cannot reinterpret a saved filter, even with equal tag UUIDs.
  mutating func reconcile(scope: ResultPublicationScope, knownIDs newIDs: Set<UUID>) {
    guard self.scope == scope else { return }
    selectedIDs = selectedIDs.intersection(newIDs).union(newIDs.subtracting(knownIDs))
    knownIDs = newIDs
  }

  var selectionSummary: String {
    if includesNoTags && selectedIDs == knownIDs { return "全部账户标签" }
    if selectedIDs.isEmpty { return includesNoTags ? "无账户标签" : "无匹配账户标签" }
    return "已选 \(selectedIDs.count) 个账户标签\(includesNoTags ? "及无标签" : "")"
  }

  private func validate() throws {
    try ResultAccountTagSnapshot(scope: scope, tagIDs: Array(knownIDs)).validate()
    guard selectedIDs.isSubset(of: knownIDs) else { throw RemoteAccountError.unexpectedResponse }
  }
  private enum CodingKeys: String, CodingKey { case version, scope, knownIDs, selectedIDs, includesNoTags }
  init(from decoder: Decoder) throws {
    let fields = try decoder.container(keyedBy: CodingKeys.self)
    guard try fields.decode(Int.self, forKey: .version) == 1 else { throw RemoteAccountError.unexpectedResponse }
    scope = try fields.decode(ResultPublicationScope.self, forKey: .scope)
    let known = try fields.decode([UUID].self, forKey: .knownIDs)
    let selected = try fields.decode([UUID].self, forKey: .selectedIDs)
    try RemoteAccountTagPolicy.validateIDs(known); try RemoteAccountTagPolicy.validateIDs(selected)
    knownIDs = Set(known); selectedIDs = Set(selected)
    includesNoTags = try fields.decode(Bool.self, forKey: .includesNoTags)
    try validate()
  }
  func encode(to encoder: Encoder) throws {
    try validate()
    var fields = encoder.container(keyedBy: CodingKeys.self)
    try fields.encode(1, forKey: .version); try fields.encode(scope, forKey: .scope)
    try fields.encode(knownIDs.sorted { $0.uuidString < $1.uuidString }, forKey: .knownIDs)
    try fields.encode(selectedIDs.sorted { $0.uuidString < $1.uuidString }, forKey: .selectedIDs)
    try fields.encode(includesNoTags, forKey: .includesNoTags)
  }
}

enum AccountTagHistoryFilterPolicy {
  /// Legacy absence and explicitly broken disk evidence must not collapse.
  static func snapshot(from data: Data?) -> ResultAccountTagSnapshot? {
    guard let data else { return nil }
    return (try? JSONDecoder().decode(ResultAccountTagSnapshot.self, from: data)) ?? .unavailable
  }

  static func metadata(id: UUID, snapshot: ResultAccountTagSnapshot?, scope: ResultPublicationScope?,
    knownIDs: Set<UUID>, canonical: [UUID: ResultHistoryAccountTagMetadata]) -> ResultHistoryAccountTagMetadata? {
    guard let scope else { return nil }
    if let snapshot {
      guard (try? snapshot.validate()) != nil,
        snapshot.scope == nil || snapshot.scope == scope else { return nil }
    }
    if let row = canonical[id], row.scope == scope { return row }
    guard let snapshot, snapshot.scope == scope, (try? snapshot.validate()) != nil else { return nil }
    return .init(scope: scope, tagIDs: snapshot.tagIDs.filter { knownIDs.contains($0) })
  }
}
