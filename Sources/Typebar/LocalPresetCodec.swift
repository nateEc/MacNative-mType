import Foundation

/// Local record format only; this does not grant support to archive/share codecs.
enum LocalPresetCodec {
  enum Failure: Error { case invalidDefinition }
  private static let kind = "typebar.local-preset"
  private struct Header: Decodable { let kind: String?; let version: Int? }
  private struct Document: Codable {
    let kind: String
    let version: Int
    let definition: SavedTestPreset
  }

  static func encode(_ definition: SavedTestPreset) throws -> Data {
    guard PracticeThresholdSource.isPresent(in: definition) else {
      return try JSONEncoder().encode(definition)
    }
    try validateSource(definition)
    let encoder = JSONEncoder()
    encoder.userInfo[PracticeThresholdSource.codingCapability] = true
    let data = try encoder.encode(Document(kind: kind, version: 1, definition: definition))
    guard try decode(data) == definition else { throw Failure.invalidDefinition }
    return data
  }

  static func decode(_ data: Data) throws -> SavedTestPreset {
    let header = try JSONDecoder().decode(Header.self, from: data)
    if header.kind == nil && header.version == nil {
      // No capability: bare legacy data must not smuggle in a source capsule.
      return try JSONDecoder().decode(SavedTestPreset.self, from: data)
    }
    guard header.kind == kind, header.version == 1 else { throw Failure.invalidDefinition }
    let decoder = JSONDecoder()
    decoder.userInfo[PracticeThresholdSource.codingCapability] = true
    let definition = try decoder.decode(Document.self, from: data).definition
    try validateSource(definition)
    return definition
  }

  private static func validateSource(_ definition: SavedTestPreset) throws {
    let rules = definition.configuration.rules
    guard let source = rules.thresholdSource, source.matches(rules) else { throw Failure.invalidDefinition }
    if let snapshot = definition.settingsSnapshot {
      guard snapshot.thresholdSource == source, source.matches(snapshot) else { throw Failure.invalidDefinition }
    }
  }
}
