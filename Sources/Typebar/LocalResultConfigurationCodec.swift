import Foundation

/// Only result configuration bytes (and their value-only workers) use this format.
enum LocalResultConfigurationCodec {
  enum Failure: Error { case invalidConfiguration }
  private static let kind = "typebar.result-configuration"
  private struct Header: Decodable { let kind: String?; let version: Int? }
  private struct Document: Codable {
    let kind: String
    let version: Int
    let configuration: TestConfiguration
  }

  static func encode(_ configuration: TestConfiguration) throws -> Data {
    guard let source = configuration.rules.thresholdSource else {
      return try JSONEncoder().encode(configuration)
    }
    guard source.matches(configuration.rules) else { throw Failure.invalidConfiguration }
    let encoder = JSONEncoder()
    encoder.userInfo[PracticeThresholdSource.codingCapability] = true
    let data = try encoder.encode(Document(kind: kind, version: 1, configuration: configuration))
    guard try decode(data) == configuration else { throw Failure.invalidConfiguration }
    return data
  }

  static func decode(_ data: Data) throws -> TestConfiguration {
    let header = try JSONDecoder().decode(Header.self, from: data)
    if header.kind == nil && header.version == nil {
      return try JSONDecoder().decode(TestConfiguration.self, from: data)
    }
    guard header.kind == kind, header.version == 1 else { throw Failure.invalidConfiguration }
    let decoder = JSONDecoder()
    decoder.userInfo[PracticeThresholdSource.codingCapability] = true
    let configuration = try decoder.decode(Document.self, from: data).configuration
    guard let source = configuration.rules.thresholdSource, source.matches(configuration.rules)
    else { throw Failure.invalidConfiguration }
    return configuration
  }

  /// Inspect original fields, never a re-encoding that fills legacy defaults.
  static func explicitFields(in data: Data) throws -> [String: Any] {
    let configuration = try decode(data)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { throw Failure.invalidConfiguration }
    if configuration.rules.thresholdSource == nil { return object }
    guard let fields = object["configuration"] as? [String: Any] else { throw Failure.invalidConfiguration }
    return fields
  }
}
