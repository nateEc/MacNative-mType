import Foundation

enum ThresholdSettingsRead: Equatable {
  case missing
  case available(AppSettingsSnapshot)
  case unavailable
}

/// A separate preference generation. The application has not cut over to it yet.
struct ThresholdSettingsStore {
  static let storageKey = "appSettings.v4"
  static let currentVersion = 4
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  private struct Header: Decodable { let version: Int }
  private struct Document: Codable {
    let version: Int
    let settings: AppSettingsSnapshot
  }

  func read() -> ThresholdSettingsRead {
    guard let value = defaults.object(forKey: Self.storageKey) else { return .missing }
    guard let data = value as? Data, let snapshot = decode(data) else { return .unavailable }
    return .available(snapshot)
  }

  @discardableResult
  func save(_ snapshot: AppSettingsSnapshot) -> Bool {
    guard let source = snapshot.thresholdSource, source.matches(snapshot) else { return false }
    if case .unavailable = read() { return false }
    let encoder = JSONEncoder()
    encoder.userInfo[PracticeThresholdSource.codingCapability] = true
    guard let data = try? encoder.encode(Document(version: Self.currentVersion, settings: snapshot)),
      decode(data) == snapshot else { return false }
    defaults.set(data, forKey: Self.storageKey)
    return true
  }

  private func decode(_ data: Data) -> AppSettingsSnapshot? {
    // Inspect only the generation before allowing any source-aware decoding.
    guard let header = try? JSONDecoder().decode(Header.self, from: data),
      header.version == Self.currentVersion else { return nil }
    let decoder = JSONDecoder()
    decoder.userInfo[PracticeThresholdSource.codingCapability] = true
    guard let document = try? decoder.decode(Document.self, from: data),
      document.version == Self.currentVersion,
      let source = document.settings.thresholdSource,
      source.matches(document.settings) else { return nil }
    return document.settings
  }
}
