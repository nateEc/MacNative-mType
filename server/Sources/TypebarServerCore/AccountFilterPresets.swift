import Foundation
import CoreFoundation
import Vapor

public enum AccountFilterPresetConfiguration {
  public static func enabled(from raw: String?) throws -> Bool {
    switch raw {
    case nil, "true": return true
    case "false": return false
    default: throw Abort(.unprocessableEntity, reason: "TYPEBAR_ACCOUNT_FILTER_PRESETS_ENABLED must be true or false.")
    }
  }
  public static func maximum(from raw: String?) throws -> Int {
    guard let raw else { return 20 }
    guard !raw.isEmpty, raw.utf8.allSatisfy({ (48...57).contains($0) }),
      let value = Int(raw), (0...100).contains(value) else {
      throw Abort(.unprocessableEntity, reason: "TYPEBAR_MAX_ACCOUNT_FILTER_PRESETS must be an integer from 0 to 100.")
    }
    return value
  }
}

/// A private native filter document, not executable JSON or an official API payload.
public struct AccountFilterPresetRequest: Content, Equatable, Sendable {
  public let version: Int
  public let name: String
  public let filterData: Data
  public let accountTags: AccountFilterPresetTags?
  public init(version: Int = 1, name: String, filterData: Data, accountTags: AccountFilterPresetTags? = nil) {
    self.version = version; self.name = name; self.filterData = filterData; self.accountTags = accountTags
  }
  private enum CodingKeys: String, CodingKey { case version, name, filterData, accountTags }
  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    version = try values.decode(Int.self, forKey: .version); name = try values.decode(String.self, forKey: .name)
    filterData = try values.decode(Data.self, forKey: .filterData)
    accountTags = values.contains(.accountTags) ? try values.decode(AccountFilterPresetTags.self, forKey: .accountTags) : nil
    try validate()
  }
  func validate() throws {
    guard (1...2).contains(version), Self.validName(name), filterData.count <= 65_536,
      let object = (try? JSONSerialization.jsonObject(with: filterData)) as? [String: Any] else { throw Abort(.unprocessableEntity) }
    let required: Set<String> = ["personalBestOnly", "dateRange", "punctuation", "numbers", "timeLimits", "wordLimits", "modifierFilter"]
    let allowed = required.union(["mode", "modes", "language", "languages", "tag", "tagFilter", "difficulty", "difficulties", "personalBestFilter", "quoteLength", "quoteLengths"])
    guard required.isSubset(of: Set(object.keys)), Set(object.keys).isSubset(of: allowed) else { throw Abort(.unprocessableEntity) }
    // The service stores a bounded, closed-shape document. Native enum semantics
    // are checked by the consuming client; future unknown choices fail closed there.
    func inspect(_ value: Any, depth: Int) -> Bool {
      guard depth <= 3 else { return false }
      if let text = value as? String { return text.utf8.count <= 128 && !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }
      if let number = value as? NSNumber { return CFGetTypeID(number) == CFBooleanGetTypeID() }
      if let array = value as? [Any] {
        guard array.count <= 512, array.allSatisfy({ $0 is String }),
          Set(array.compactMap { $0 as? String }).count == array.count else { return false }
        return array.allSatisfy { inspect($0, depth: depth + 1) }
      }
      if let map = value as? [String: Any] { return map.count <= 4 && map.values.allSatisfy { inspect($0, depth: depth + 1) } }
      return false
    }
    let modifierKeys: Set<String> = version == 1
      ? ["includesNoModifiers", "modifiers"] : ["includesNoModifiers", "modifiers", "includesPolyglot"]
    guard object.values.allSatisfy({ inspect($0, depth: 0) }),
      let modifiers = object["modifierFilter"] as? [String: Any], Set(modifiers.keys) == modifierKeys,
      let flag = modifiers["includesNoModifiers"] as? NSNumber, CFGetTypeID(flag) == CFBooleanGetTypeID(),
      modifiers["modifiers"] is [String] else { throw Abort(.unprocessableEntity) }
    if version == 2 {
      guard let value = modifiers["includesPolyglot"] as? NSNumber,
        CFGetTypeID(value) == CFBooleanGetTypeID() else { throw Abort(.unprocessableEntity) }
    }
    if let tags = object["tagFilter"] as? [String: Any] {
      guard Set(tags.keys) == ["isUnrestricted", "includesNoTags", "tags"], tags["tags"] is [String],
        ["isUnrestricted", "includesNoTags"].allSatisfy({ key in
          guard let value = tags[key] as? NSNumber else { return false }; return CFGetTypeID(value) == CFBooleanGetTypeID()
        }) else { throw Abort(.unprocessableEntity) }
    } else if object["tagFilter"] != nil { throw Abort(.unprocessableEntity) }
    for key in ["modes", "languages", "difficulties", "quoteLengths", "timeLimits", "wordLimits"] where object[key] != nil {
      guard object[key] is [String] else { throw Abort(.unprocessableEntity) }
    }
    for key in ["mode", "language", "tag", "difficulty", "personalBestFilter", "dateRange", "punctuation", "numbers", "quoteLength"] where object[key] != nil {
      guard object[key] is String else { throw Abort(.unprocessableEntity) }
    }
    guard let legacyPB = object["personalBestOnly"] as? NSNumber, CFGetTypeID(legacyPB) == CFBooleanGetTypeID() else { throw Abort(.unprocessableEntity) }
    try accountTags?.validate()
  }
  static func validName(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    return (1...16).contains(bytes.count) && bytes.first != 46 && bytes.allSatisfy {
      (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0)
    }
  }
}
public struct AccountFilterPresetTags: Codable, Equatable, Sendable {
  public let knownIDs: [UUID]
  public let selectedIDs: [UUID]
  public let includesNoTags: Bool
  public init(knownIDs: [UUID], selectedIDs: [UUID], includesNoTags: Bool) {
    self.knownIDs = knownIDs; self.selectedIDs = selectedIDs; self.includesNoTags = includesNoTags
  }
  func validate() throws {
    guard knownIDs.count <= 15, Set(knownIDs).count == knownIDs.count,
      Set(selectedIDs).count == selectedIDs.count, Set(selectedIDs).isSubset(of: Set(knownIDs)) else { throw Abort(.unprocessableEntity) }
  }
}
public struct AccountFilterPresetResponse: Content, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let document: AccountFilterPresetRequest
  public init(id: UUID, document: AccountFilterPresetRequest) { self.id = id; self.document = document }
  private enum CodingKeys: String, CodingKey { case id }
  public init(from decoder: Decoder) throws {
    id = try decoder.container(keyedBy: CodingKeys.self).decode(UUID.self, forKey: .id)
    document = try AccountFilterPresetRequest(from: decoder)
    try document.validate()
  }
  public func encode(to encoder: Encoder) throws {
    try document.encode(to: encoder)
    var fields = encoder.container(keyedBy: CodingKeys.self); try fields.encode(id, forKey: .id)
  }
}
public struct AccountFilterPresetList: Content, Sendable {
  public let version: Int
  public let maximumPresets: Int
  public let mutationsEnabled: Bool
  public let presets: [AccountFilterPresetResponse]
}
struct StoredAccountFilterPreset: Codable {
  let userID: UUID
  let preset: AccountFilterPresetResponse
}
