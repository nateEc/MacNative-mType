import Foundation

struct AccountFilterPresetTags: Codable, Equatable, Sendable {
  let knownIDs: [UUID]
  let selectedIDs: [UUID]
  let includesNoTags: Bool
  func validate() throws {
    try RemoteAccountTagPolicy.validateIDs(knownIDs)
    try RemoteAccountTagPolicy.validateIDs(selectedIDs)
    guard Set(selectedIDs).isSubset(of: Set(knownIDs)) else { throw RemoteAccountError.unexpectedResponse }
  }
}

/// Only filter choices travel. Endpoint, account scope, results and credentials do not.
struct AccountFilterPresetDocument: Codable, Equatable, Sendable {
  let version: Int
  let name: String
  let filterData: Data
  let accountTags: AccountFilterPresetTags?

  static func normalizedName(_ value: String) -> String { value.split(whereSeparator: \.isWhitespace).joined(separator: "_") }
  static func isValidName(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    return (1...16).contains(bytes.count) && bytes.first != 46 && bytes.allSatisfy {
      (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0)
    }
  }
  init(name: String, filter: ResultHistoryFilter, scope: ResultPublicationScope) throws {
    version = filter.modifierFilter.includesPolyglot == nil ? 1 : 2
    self.name = Self.normalizedName(name)
    var portable = filter
    if let tags = filter.accountTagFilter {
      guard tags.scope == scope else { throw RemoteAccountError.accountScopeChanged }
      accountTags = .init(knownIDs: tags.knownIDs.sorted { $0.uuidString < $1.uuidString },
        selectedIDs: tags.selectedIDs.sorted { $0.uuidString < $1.uuidString }, includesNoTags: tags.includesNoTags)
    } else { accountTags = nil }
    portable.accountTagFilter = nil
    filterData = try JSONEncoder().encode(portable)
    try validate()
  }
  private enum CodingKeys: String, CodingKey { case version, name, filterData, accountTags }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    version = try values.decode(Int.self, forKey: .version); name = try values.decode(String.self, forKey: .name)
    filterData = try values.decode(Data.self, forKey: .filterData)
    accountTags = values.contains(.accountTags) ? try values.decode(AccountFilterPresetTags.self, forKey: .accountTags) : nil
    try validate()
  }
  func validate() throws {
    guard (1...2).contains(version), Self.isValidName(name), filterData.count <= 65_536,
      let object = try JSONSerialization.jsonObject(with: filterData) as? [String: Any] else { throw RemoteAccountError.unexpectedResponse }
    let required: Set<String> = ["personalBestOnly", "dateRange", "punctuation", "numbers", "timeLimits", "wordLimits", "modifierFilter"]
    let allowed = required.union(["mode", "modes", "language", "languages", "tag", "tagFilter", "difficulty", "difficulties", "personalBestFilter", "quoteLength", "quoteLengths"])
    guard required.isSubset(of: Set(object.keys)), Set(object.keys).isSubset(of: allowed) else { throw RemoteAccountError.unexpectedResponse }
    for value in object.values {
      if value is NSNull { throw RemoteAccountError.unexpectedResponse }
      if let values = value as? [String], Set(values).count != values.count { throw RemoteAccountError.unexpectedResponse }
    }
    let modifierKeys: Set<String> = version == 1
      ? ["includesNoModifiers", "modifiers"] : ["includesNoModifiers", "modifiers", "includesPolyglot"]
    guard let modifiers = object["modifierFilter"] as? [String: Any], Set(modifiers.keys) == modifierKeys,
      let modifierIDs = modifiers["modifiers"] as? [String], Set(modifierIDs).count == modifierIDs.count else { throw RemoteAccountError.unexpectedResponse }
    if let tags = object["tagFilter"] as? [String: Any] {
      guard Set(tags.keys) == ["isUnrestricted", "includesNoTags", "tags"], let names = tags["tags"] as? [String],
        names.count <= 512, Set(names).count == names.count,
        names.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) })
      else { throw RemoteAccountError.unexpectedResponse }
    }
    let filter = try JSONDecoder().decode(ResultHistoryFilter.self, from: filterData)
    guard filter.accountTagFilter == nil, !filter.quoteLengthSelections.contains(.all) else { throw RemoteAccountError.unexpectedResponse }
    try accountTags?.validate()
  }
  func restored(scope: ResultPublicationScope, knownTagIDs: Set<UUID>?) throws -> ResultHistoryFilter {
    try validate()
    var filter = try JSONDecoder().decode(ResultHistoryFilter.self, from: filterData)
    if let tags = accountTags {
      guard let knownTagIDs else { throw RemoteAccountError.serverMessage("请先刷新账户标签，再应用这个预设。") }
      var selection = ResultHistoryAccountTagFilter(scope: scope, knownIDs: Set(tags.knownIDs),
        selectedIDs: Set(tags.selectedIDs), includesNoTags: tags.includesNoTags)
      selection.reconcile(scope: scope, knownIDs: knownTagIDs)
      filter.accountTagFilter = selection
    }
    return filter
  }
}

struct RemoteAccountFilterPreset: Codable, Identifiable, Equatable, Sendable {
  let id: UUID
  let document: AccountFilterPresetDocument
  var displayName: String { document.name.replacingOccurrences(of: "_", with: " ") }
  private enum CodingKeys: String, CodingKey { case id }
  init(id: UUID, document: AccountFilterPresetDocument) { self.id = id; self.document = document }
  init(from decoder: Decoder) throws {
    id = try decoder.container(keyedBy: CodingKeys.self).decode(UUID.self, forKey: .id)
    document = try AccountFilterPresetDocument(from: decoder)
  }
  func encode(to encoder: Encoder) throws {
    try document.encode(to: encoder)
    var values = encoder.container(keyedBy: CodingKeys.self); try values.encode(id, forKey: .id)
  }
}
struct RemoteAccountFilterPresetList: Codable, Sendable {
  let version: Int
  let maximumPresets: Int
  let mutationsEnabled: Bool
  let presets: [RemoteAccountFilterPreset]
  init(version: Int, maximumPresets: Int, mutationsEnabled: Bool = true, presets: [RemoteAccountFilterPreset]) {
    self.version = version; self.maximumPresets = maximumPresets
    self.mutationsEnabled = mutationsEnabled; self.presets = presets
  }
  private enum CodingKeys: String, CodingKey { case version, maximumPresets, mutationsEnabled, presets }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    version = try values.decode(Int.self, forKey: .version)
    maximumPresets = try values.decode(Int.self, forKey: .maximumPresets)
    mutationsEnabled = values.contains(.mutationsEnabled) ? try values.decode(Bool.self, forKey: .mutationsEnabled) : true
    presets = try values.decode([RemoteAccountFilterPreset].self, forKey: .presets)
  }
  func requireMutationsEnabled() throws {
    guard mutationsEnabled else { throw RemoteAccountError.serverMessage("账户筛选预设修改已暂停；已有预设仍可应用，请刷新后重试。") }
  }
  func validate() throws {
    guard version == 1, (0...100).contains(maximumPresets), presets.count <= 100,
      Set(presets.map(\.id)).count == presets.count else { throw RemoteAccountError.unexpectedResponse }
    for preset in presets { try preset.document.validate() }
  }
}
struct AccountFilterPresetRead: Equatable { let scope: ResultPublicationScope; let generation: UInt64 }
struct AccountFilterPresetCache {
  let scope: ResultPublicationScope
  var list: RemoteAccountFilterPresetList
}
