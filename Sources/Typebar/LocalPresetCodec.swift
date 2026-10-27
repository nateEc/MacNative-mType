import Foundation

/// Versioned preset bytes. Enclosing archives and links must explicitly adopt
/// this codec; ordinary SavedTestPreset JSON stays strict.
enum LocalPresetCodec {
  enum Failure: Error { case invalidDefinition }
  private static let kind = "typebar.local-preset"
  private struct Header: Decodable {
    let kind: String?, version: Int?
    let hasConfigurationData: Bool
    private enum CodingKeys: String, CodingKey { case kind, version, configurationData }
    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      kind = try values.decodeIfPresent(String.self, forKey: .kind)
      version = try values.decodeIfPresent(Int.self, forKey: .version)
      hasConfigurationData = values.contains(.configurationData)
    }
  }
  private struct Document: Codable {
    let kind: String
    let version: Int
    let definition: SavedTestPreset
  }
  private struct WebsiteDocument: Codable {
    let kind: String
    let version: Int
    let definition: SavedTestPreset
    let configurationData: Data
  }

  static func encode(_ definition: SavedTestPreset) throws -> Data {
    guard PracticeThresholdSource.isPresent(in: definition) else {
      return try JSONEncoder().encode(definition)
    }
    try validateSource(definition)
    let encoder = JSONEncoder()
    encoder.userInfo[PracticeThresholdSource.codingCapability] = true
    let data: Data
    if LocalResultConfigurationCodec.containsWebsiteInfiniteSpeedMemory(definition.configuration) {
      let configuration = try LocalResultConfigurationCodec.finiteWebsiteSpeedMemoryCarrier(definition.configuration)
      let finite = try replacingConfiguration(in: definition, with: configuration)
      data = try encoder.encode(WebsiteDocument(kind: kind, version: 2, definition: finite,
        configurationData: LocalResultConfigurationCodec.encode(definition.configuration)))
    } else { data = try encoder.encode(Document(kind: kind, version: 1, definition: definition)) }
    guard try decode(data) == definition else { throw Failure.invalidDefinition }
    return data
  }

  static func decode(_ data: Data) throws -> SavedTestPreset {
    let header = try JSONDecoder().decode(Header.self, from: data)
    if header.kind == nil && header.version == nil {
      guard !header.hasConfigurationData else { throw Failure.invalidDefinition }
      // No capability: bare legacy data must not smuggle in a source capsule.
      return try JSONDecoder().decode(SavedTestPreset.self, from: data)
    }
    guard header.kind == kind else { throw Failure.invalidDefinition }
    let decoder = JSONDecoder()
    decoder.userInfo[PracticeThresholdSource.codingCapability] = true
    switch header.version {
    case 1:
      guard !header.hasConfigurationData else { throw Failure.invalidDefinition }
      let definition = try decoder.decode(Document.self, from: data).definition
      try validateSource(definition)
      return definition
    case 2:
      let document = try decoder.decode(WebsiteDocument.self, from: data)
      try validateSource(document.definition)
      let configuration = try LocalResultConfigurationCodec.decode(document.configurationData)
      guard LocalResultConfigurationCodec.containsWebsiteInfiniteSpeedMemory(configuration),
        try LocalResultConfigurationCodec.finiteWebsiteSpeedMemoryCarrier(configuration) == document.definition.configuration
      else { throw Failure.invalidDefinition }
      return try replacingConfiguration(in: document.definition, with: configuration)
    default: throw Failure.invalidDefinition
    }
  }

  private static func replacingConfiguration(in definition: SavedTestPreset,
    with configuration: TestConfiguration) throws -> SavedTestPreset {
    guard let source = configuration.rules.thresholdSource else { throw Failure.invalidDefinition }
    var copy = definition
    copy.configuration = configuration
    if let snapshot = copy.settingsSnapshot { copy.settingsSnapshot = source.applying(to: snapshot) }
    try validateSource(copy)
    return copy
  }

  private static func validateSource(_ definition: SavedTestPreset) throws {
    let rules = definition.configuration.rules
    guard let source = rules.thresholdSource, source.matches(rules) else { throw Failure.invalidDefinition }
    if let snapshot = definition.settingsSnapshot {
      guard snapshot.thresholdSource == source, source.matches(snapshot) else { throw Failure.invalidDefinition }
    }
  }
}
