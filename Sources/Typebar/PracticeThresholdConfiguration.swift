import Foundation

/// Source configuration, not the active numeric rules consumed by a test.
/// Modes and remembered custom values must remain independently transportable.
struct PracticeThresholdConfiguration: Codable, Equatable {
  enum Mode: String, Codable { case off, custom }
  enum Change {
    case minimumWpm(mode: Mode?, customValue: Double?)
    case minimumAccuracy(mode: Mode?, customValue: Double?)
    case minimumWordBurst(mode: MinimumWordBurstMode?, customValue: Double?)
  }

  private(set) var minimumWpmMode: Mode = .off
  private(set) var minimumWpmCustomValue: Double = 100
  private(set) var minimumAccuracyMode: Mode = .off
  private(set) var minimumAccuracyCustomValue: Double = 90
  private(set) var minimumWordBurstMode: MinimumWordBurstMode = .off
  private(set) var minimumWordBurstCustomValue: Double = 100

  init() {}

  /// The complete website profile has a lossless numeric archive. Existing
  /// settings/JSON formats and their editors retain finite-only admission.
  init(websiteMinimumWpmMode: Mode, speed: Double, accuracyMode: Mode, accuracy: Double,
    burstMode: MinimumWordBurstMode, burst: Double) throws {
    minimumWpmMode = websiteMinimumWpmMode; minimumWpmCustomValue = speed
    minimumAccuracyMode = accuracyMode; minimumAccuracyCustomValue = accuracy
    minimumWordBurstMode = burstMode; minimumWordBurstCustomValue = burst
    guard isValidWebsite else { throw ValidationError.invalidCustomValue }
  }

  enum ValidationError: Error { case invalidCustomValue }

  var isValid: Bool {
    isValidWebsite && minimumWpmCustomValue.isFinite && minimumWordBurstCustomValue.isFinite
  }

  var isValidWebsite: Bool {
    minimumWpmCustomValue >= 0 && minimumWordBurstCustomValue >= 0
      && minimumAccuracyCustomValue.isFinite && (0...100).contains(minimumAccuracyCustomValue)
  }

  mutating func apply(_ change: Change) throws {
    var updated = self
    switch change {
    case .minimumWpm(let mode, let value):
      if let mode { updated.minimumWpmMode = mode }
      if let value { updated.minimumWpmCustomValue = value }
    case .minimumAccuracy(let mode, let value):
      if let mode { updated.minimumAccuracyMode = mode }
      if let value { updated.minimumAccuracyCustomValue = value }
    case .minimumWordBurst(let mode, let value):
      if let mode { updated.minimumWordBurstMode = mode }
      if let value { updated.minimumWordBurstCustomValue = value }
    }
    guard updated.isValid else { throw ValidationError.invalidCustomValue }
    self = updated
  }

  private enum CodingKeys: String, CodingKey {
    case minimumWpmMode, minimumWpmCustomValue, minimumAccuracyMode,
      minimumAccuracyCustomValue, minimumWordBurstMode, minimumWordBurstCustomValue
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    minimumWpmMode = try values.decode(Mode.self, forKey: .minimumWpmMode)
    minimumWpmCustomValue = try values.decode(Double.self, forKey: .minimumWpmCustomValue)
    minimumAccuracyMode = try values.decode(Mode.self, forKey: .minimumAccuracyMode)
    minimumAccuracyCustomValue = try values.decode(Double.self, forKey: .minimumAccuracyCustomValue)
    minimumWordBurstMode = try values.decode(MinimumWordBurstMode.self, forKey: .minimumWordBurstMode)
    minimumWordBurstCustomValue = try values.decode(Double.self, forKey: .minimumWordBurstCustomValue)
    guard isValid else {
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
        debugDescription: "Invalid remembered threshold value"))
    }
  }
}
