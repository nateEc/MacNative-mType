import Foundation

/// Only result configuration bytes (and their value-only workers) use this format.
enum LocalResultConfigurationCodec {
  enum Failure: Error { case invalidConfiguration }
  private static let kind = "typebar.result-configuration"
  private struct Header: Decodable {
    let kind: String?, version: Int?
    let hasInfiniteSpeedMemory: Bool
    private enum CodingKeys: String, CodingKey { case kind, version, infiniteSpeedMemory }
    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      kind = try values.decodeIfPresent(String.self, forKey: .kind)
      version = try values.decodeIfPresent(Int.self, forKey: .version)
      hasInfiniteSpeedMemory = values.contains(.infiniteSpeedMemory)
    }
  }
  private struct Document: Codable {
    let kind: String
    let version: Int
    let configuration: TestConfiguration
  }
  private struct InfiniteSpeedMemory: Codable {
    let minimumWpm: Bool, minimumWordBurst: Bool
    var isPresent: Bool { minimumWpm || minimumWordBurst }
  }
  private struct WebsiteDocument: Codable {
    let kind: String, version: Int
    let configuration: TestConfiguration
    let infiniteSpeedMemory: InfiniteSpeedMemory
  }

  private static func replacingSpeedMemories(in configuration: TestConfiguration,
    speed: Double, burst: Double) throws -> TestConfiguration {
    guard let source = configuration.rules.thresholdSource, source.configuration.isValidWebsite,
      source.matches(configuration.rules) else { throw Failure.invalidConfiguration }
    let raw = source.configuration
    let replacement = try PracticeThresholdConfiguration(websiteMinimumWpmMode: raw.minimumWpmMode,
      speed: speed, accuracyMode: raw.minimumAccuracyMode, accuracy: raw.minimumAccuracyCustomValue,
      burstMode: raw.minimumWordBurstMode, burst: burst)
    var copy = configuration
    copy.rules = PracticeThresholdSource(configuration: replacement).applying(to: copy.rules)
    return copy
  }

  static func encode(_ configuration: TestConfiguration) throws -> Data {
    guard let source = configuration.rules.thresholdSource else {
      return try JSONEncoder().encode(configuration)
    }
    guard source.configuration.isValidWebsite, source.matches(configuration.rules) else { throw Failure.invalidConfiguration }
    let encoder = JSONEncoder()
    encoder.userInfo[PracticeThresholdSource.codingCapability] = true
    let raw = source.configuration
    let memory = InfiniteSpeedMemory(minimumWpm: raw.minimumWpmCustomValue == .infinity,
      minimumWordBurst: raw.minimumWordBurstCustomValue == .infinity)
    let data: Data
    if memory.isPresent {
      // Keep ordinary JSON strict. Only these two remembered speeds use a v2
      // tag; unrelated nonfinite fields still make the default encoder fail.
      let finite = try replacingSpeedMemories(in: configuration,
        speed: memory.minimumWpm ? 100 : raw.minimumWpmCustomValue,
        burst: memory.minimumWordBurst ? 100 : raw.minimumWordBurstCustomValue)
      data = try encoder.encode(WebsiteDocument(kind: kind, version: 2, configuration: finite,
        infiniteSpeedMemory: memory))
    } else { data = try encoder.encode(Document(kind: kind, version: 1, configuration: configuration)) }
    guard try decode(data) == configuration else { throw Failure.invalidConfiguration }
    return data
  }

  static func decode(_ data: Data) throws -> TestConfiguration {
    let header = try JSONDecoder().decode(Header.self, from: data)
    if header.kind == nil && header.version == nil {
      return try JSONDecoder().decode(TestConfiguration.self, from: data)
    }
    guard header.kind == kind else { throw Failure.invalidConfiguration }
    let decoder = JSONDecoder()
    decoder.userInfo[PracticeThresholdSource.codingCapability] = true
    switch header.version {
    case 1:
      guard !header.hasInfiniteSpeedMemory else { throw Failure.invalidConfiguration }
      let configuration = try decoder.decode(Document.self, from: data).configuration
      guard let source = configuration.rules.thresholdSource, source.matches(configuration.rules)
      else { throw Failure.invalidConfiguration }
      return configuration
    case 2:
      let document = try decoder.decode(WebsiteDocument.self, from: data)
      guard document.infiniteSpeedMemory.isPresent,
        let source = document.configuration.rules.thresholdSource,
        source.configuration.isValid, source.matches(document.configuration.rules) else { throw Failure.invalidConfiguration }
      let raw = source.configuration, memory = document.infiniteSpeedMemory
      guard (!memory.minimumWpm || raw.minimumWpmCustomValue == 100),
        (!memory.minimumWordBurst || raw.minimumWordBurstCustomValue == 100) else { throw Failure.invalidConfiguration }
      return try replacingSpeedMemories(in: document.configuration,
        speed: memory.minimumWpm ? .infinity : raw.minimumWpmCustomValue,
        burst: memory.minimumWordBurst ? .infinity : raw.minimumWordBurstCustomValue)
    default: throw Failure.invalidConfiguration
    }
  }

  /// Inspect explicit transport fields, never a re-encoding that fills legacy
  /// defaults. In v2 the two tagged speed memories are finite placeholders;
  /// semantic values must be read through decode, not this presence audit.
  static func explicitFields(in data: Data) throws -> [String: Any] {
    let configuration = try decode(data)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { throw Failure.invalidConfiguration }
    if configuration.rules.thresholdSource == nil { return object }
    guard let fields = object["configuration"] as? [String: Any] else { throw Failure.invalidConfiguration }
    return fields
  }
}
