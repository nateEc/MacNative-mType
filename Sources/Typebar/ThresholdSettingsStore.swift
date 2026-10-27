import Foundation

enum ThresholdSettingsRead: Equatable {
  case missing
  case available(AppSettingsSnapshot)
  case unavailable
}

/// Source-owned preference family. Finite documents remain v4; v5 adds only
/// explicitly tagged positive-infinite speed memories using a finite carrier.
struct ThresholdSettingsStore {
  static let storageKey = "appSettings.v4"
  static let currentVersion = 4
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  private struct Header: Decodable {
    let version: Int
    let hasInfiniteSpeedMemory: Bool
    private enum CodingKeys: String, CodingKey { case version, infiniteSpeedMemory }
    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      version = try values.decode(Int.self, forKey: .version)
      hasInfiniteSpeedMemory = values.contains(.infiniteSpeedMemory)
    }
  }
  private struct Document: Codable {
    let version: Int
    let settings: AppSettingsSnapshot
  }
  private struct InfiniteSpeedMemory: Codable {
    let minimumWpm: Bool, minimumWordBurst: Bool
    var isPresent: Bool { minimumWpm || minimumWordBurst }
  }
  private struct WebsiteDocument: Codable {
    let version: Int
    let settings: AppSettingsSnapshot
    let infiniteSpeedMemory: InfiniteSpeedMemory
  }

  private func replacing(_ snapshot: AppSettingsSnapshot, speed: Double, burst: Double) throws -> AppSettingsSnapshot {
    guard let source = snapshot.thresholdSource, source.configuration.isValidWebsite, source.matches(snapshot)
    else { throw CocoaError(.coderInvalidValue) }
    let raw = source.configuration
    let replacement = try PracticeThresholdConfiguration(websiteMinimumWpmMode: raw.minimumWpmMode, speed: speed,
      accuracyMode: raw.minimumAccuracyMode, accuracy: raw.minimumAccuracyCustomValue,
      burstMode: raw.minimumWordBurstMode, burst: burst)
    return PracticeThresholdSource(configuration: replacement).applying(to: snapshot)
  }

  func read() -> ThresholdSettingsRead {
    guard let value = defaults.object(forKey: Self.storageKey) else { return .missing }
    guard let data = value as? Data, let snapshot = decode(data) else { return .unavailable }
    return .available(snapshot)
  }

  @discardableResult
  func save(_ snapshot: AppSettingsSnapshot) -> Bool {
    guard let source = snapshot.thresholdSource, source.configuration.isValidWebsite, source.matches(snapshot) else { return false }
    if case .unavailable = read() { return false }
    let encoder = JSONEncoder()
    encoder.userInfo[PracticeThresholdSource.codingCapability] = true
    let memory = InfiniteSpeedMemory(minimumWpm: source.configuration.minimumWpmCustomValue == .infinity,
      minimumWordBurst: source.configuration.minimumWordBurstCustomValue == .infinity)
    let data: Data
    do {
      if memory.isPresent {
        let finite = try replacing(snapshot,
          speed: memory.minimumWpm ? 100 : source.configuration.minimumWpmCustomValue,
          burst: memory.minimumWordBurst ? 100 : source.configuration.minimumWordBurstCustomValue)
        data = try encoder.encode(WebsiteDocument(version: 5, settings: finite, infiniteSpeedMemory: memory))
      } else { data = try encoder.encode(Document(version: Self.currentVersion, settings: snapshot)) }
    } catch { return false }
    guard decode(data) == snapshot else { return false }
    defaults.set(data, forKey: Self.storageKey)
    return defaults.data(forKey: Self.storageKey) == data
  }

  private func decode(_ data: Data) -> AppSettingsSnapshot? {
    // Inspect only the generation before allowing any source-aware decoding.
    guard let header = try? JSONDecoder().decode(Header.self, from: data) else { return nil }
    let decoder = JSONDecoder()
    decoder.userInfo[PracticeThresholdSource.codingCapability] = true
    switch header.version {
    case Self.currentVersion:
      guard !header.hasInfiniteSpeedMemory,
        let document = try? decoder.decode(Document.self, from: data),
        let source = document.settings.thresholdSource, source.matches(document.settings) else { return nil }
      return document.settings
    case 5:
      guard header.hasInfiniteSpeedMemory, let document = try? decoder.decode(WebsiteDocument.self, from: data),
        document.infiniteSpeedMemory.isPresent, let source = document.settings.thresholdSource,
        source.configuration.isValid, source.matches(document.settings) else { return nil }
      let raw = source.configuration, memory = document.infiniteSpeedMemory
      guard (!memory.minimumWpm || raw.minimumWpmCustomValue == 100),
        (!memory.minimumWordBurst || raw.minimumWordBurstCustomValue == 100),
        let restored = try? replacing(document.settings,
          speed: memory.minimumWpm ? .infinity : raw.minimumWpmCustomValue,
          burst: memory.minimumWordBurst ? .infinity : raw.minimumWordBurstCustomValue),
        let carrier = try? replacing(restored, speed: raw.minimumWpmCustomValue, burst: raw.minimumWordBurstCustomValue),
        carrier == document.settings else { return nil }
      return restored
    default: return nil
    }
  }
}
