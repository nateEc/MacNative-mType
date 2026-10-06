import Foundation

enum ResultAccountTagSnapshotError: LocalizedError {
  case invalid, conflictingResult
  var errorDescription: String? {
    switch self {
    case .invalid: "完成时的账户标签快照损坏或无法捕获；本次成绩未发布，请检查标签选择，不会用当前标签替换。"
    case .conflictingResult: "同一成绩 ID 的账户标签快照或完成内容冲突，未覆盖已有成绩。"
    }
  }
}

/// Captured at completion, not test start or network retry. It contains no
/// token, tag name, PB payload or text. Nil means an unknown older result.
struct ResultAccountTagSnapshot: Codable, Equatable, Sendable {
  let version: Int
  let scope: ResultPublicationScope?
  let tagIDs: [UUID]
  init(scope: ResultPublicationScope?, tagIDs: [UUID]) {
    version = 1; self.scope = scope; self.tagIDs = tagIDs
  }
  private init(unavailable: Bool) { version = 0; scope = nil; tagIDs = [] }
  /// Keep a failed capture explicit in the in-memory result; saving/encoding
  /// must reject it rather than convert it to unknown or known empty.
  static let unavailable = Self(unavailable: true)
  func validate() throws {
    guard version == 1, tagIDs.count <= 15, Set(tagIDs).count == tagIDs.count,
      scope != nil || tagIDs.isEmpty else { throw ResultAccountTagSnapshotError.invalid }
    if let scope {
      let key = scope.serverID
      guard !key.isEmpty, key.count <= 8_192,
        key.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0)
          || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else { throw ResultAccountTagSnapshotError.invalid }
      let base64 = key.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        + String(repeating: "=", count: (4 - key.count % 4) % 4)
      guard let bytes = Data(base64Encoded: base64), let endpoint = String(data: bytes, encoding: .utf8),
        let url = URLComponents(string: endpoint), url.scheme.map({ ["http", "https"].contains($0) }) == true,
        url.host?.isEmpty == false, url.user == nil, url.password == nil,
        RemoteServerScope(endpoint: endpoint).storageSuffix == key else { throw ResultAccountTagSnapshotError.invalid }
    }
  }
  private enum CodingKeys: String, CodingKey { case version, scope, tagIDs }
  init(from decoder: Decoder) throws {
    let fields = try decoder.container(keyedBy: CodingKeys.self)
    version = try fields.decode(Int.self, forKey: .version)
    scope = fields.contains(.scope) ? try fields.decode(ResultPublicationScope.self, forKey: .scope) : nil
    tagIDs = try fields.decode([UUID].self, forKey: .tagIDs)
    try validate()
  }
  func encode(to encoder: Encoder) throws {
    try validate()
    var fields = encoder.container(keyedBy: CodingKeys.self)
    try fields.encode(version, forKey: .version)
    try fields.encodeIfPresent(scope, forKey: .scope)
    try fields.encode(tagIDs, forKey: .tagIDs)
  }
}

enum ResultAccountTagSnapshotPolicy {
  /// Keep legacy duplicate handling unchanged, but do not let first-wins or
  /// SwiftData upsert hide any repeated UUID carrying completion evidence.
  static func validateUniqueResultIdentities(_ results: [CompletedTestResult]) throws {
    var seen = Set<UUID>(), repeated = Set<UUID>()
    for result in results where !seen.insert(result.id).inserted { repeated.insert(result.id) }
    guard !results.contains(where: { $0.accountTagSnapshot != nil && repeated.contains($0.id) })
    else { throw ResultAccountTagSnapshotError.conflictingResult }
  }
  static func merged(local: CompletedTestResult, remote: CompletedTestResult) throws -> CompletedTestResult {
    try local.accountTagSnapshot?.validate(); try remote.accountTagSnapshot?.validate()
    guard local.accountTagSnapshot != nil || remote.accountTagSnapshot != nil else { return local }
    var left = local, right = remote
    left.accountTagSnapshot = nil; right.accountTagSnapshot = nil
    // Local text labels are mutable metadata, independent of completion IDs.
    left.tags = []; right.tags = []
    guard left == right else { throw ResultAccountTagSnapshotError.conflictingResult }
    if let first = local.accountTagSnapshot, let second = remote.accountTagSnapshot, first != second {
      throw ResultAccountTagSnapshotError.conflictingResult
    }
    var value = local
    value.accountTagSnapshot = local.accountTagSnapshot ?? remote.accountTagSnapshot
    return value
  }
  static func capture(scope: ResultPublicationScope?, selectedIDs: [UUID]) -> ResultAccountTagSnapshot {
    let snapshot = ResultAccountTagSnapshot(scope: scope, tagIDs: selectedIDs)
    do { try snapshot.validate(); return snapshot } catch { return .unavailable }
  }
  static func ids(_ snapshot: ResultAccountTagSnapshot?, for scope: ResultPublicationScope) throws -> [UUID]? {
    guard let snapshot else { return nil }
    try snapshot.validate()
    guard snapshot.scope == nil || snapshot.scope == scope else { throw RemoteAccountError.accountScopeChanged }
    return snapshot.tagIDs
  }
  static func prepare(_ snapshot: ResultAccountTagSnapshot?, for scope: ResultPublicationScope,
    capabilities: RemoteServiceCapabilities?) throws -> [UUID]? {
    guard let ids = try ids(snapshot, for: scope) else { return nil }
    if ids.isEmpty { return capabilities?.supportsAccountTags == true ? [] : nil }
    return try RemoteAccountTagPolicy.prepare(ids: ids, capabilities: capabilities)
  }
}
