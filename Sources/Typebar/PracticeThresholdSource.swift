import Foundation

/// A gated carrier for complete source state. Existing formats never opt in.
struct PracticeThresholdSource: Codable, Equatable {
  static let codingCapability = CodingUserInfoKey(rawValue: "typebar.practiceThresholdSource")!
  let version: Int
  let configuration: PracticeThresholdConfiguration

  init(configuration: PracticeThresholdConfiguration) {
    version = 1
    self.configuration = configuration
  }

  static func isPresent(in preset: SavedTestPreset) -> Bool {
    preset.configuration.rules.thresholdSource != nil || preset.settingsSnapshot?.thresholdSource != nil
  }

  private var accuracy: Double {
    configuration.minimumAccuracyMode == .off ? 0 : configuration.minimumAccuracyCustomValue
  }
  private var wpm: Double {
    configuration.minimumWpmMode == .off ? 0 : configuration.minimumWpmCustomValue
  }
  private var burst: Double {
    configuration.minimumWordBurstMode == .off ? 0 : configuration.minimumWordBurstCustomValue
  }
  private var burstMode: MinimumWordBurstMode {
    burst == 0 ? .off : configuration.minimumWordBurstMode
  }

  func applying(to rules: InputRules) -> InputRules {
    var result = rules
    result.minimumAccuracy = accuracy
    result.minimumWpm = wpm
    result.minimumWordBurstWpm = burst
    result.minimumWordBurstMode = burstMode
    result.thresholdSource = self
    return result
  }

  func applying(to snapshot: AppSettingsSnapshot) -> AppSettingsSnapshot {
    var result = snapshot
    result.minimumAccuracy = accuracy
    result.minimumWpm = wpm
    result.minimumWordBurstWpm = burst
    result.minimumWordBurstMode = burstMode
    result.thresholdSource = self
    return result
  }

  func matches(_ rules: InputRules) -> Bool {
    rules.minimumAccuracy == accuracy && rules.minimumWpm == wpm
      && rules.minimumWordBurstWpm == burst && rules.minimumWordBurstMode == burstMode
  }

  func matches(_ snapshot: AppSettingsSnapshot) -> Bool {
    snapshot.minimumAccuracy == accuracy && snapshot.minimumWpm == wpm
      && snapshot.minimumWordBurstWpm == burst && snapshot.minimumWordBurstMode == burstMode
  }

  private enum CodingKeys: String, CodingKey { case version, configuration }

  init(from decoder: Decoder) throws {
    guard decoder.userInfo[Self.codingCapability] as? Bool == true else {
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
        debugDescription: "Threshold source requires a supporting format generation"))
    }
    let values = try decoder.container(keyedBy: CodingKeys.self)
    version = try values.decode(Int.self, forKey: .version)
    guard version == 1 else {
      throw DecodingError.dataCorruptedError(forKey: .version, in: values,
        debugDescription: "Unsupported threshold source generation")
    }
    configuration = try values.decode(PracticeThresholdConfiguration.self, forKey: .configuration)
  }

  func encode(to encoder: Encoder) throws {
    guard encoder.userInfo[Self.codingCapability] as? Bool == true else {
      throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath,
        debugDescription: "Threshold source requires a supporting format generation"))
    }
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(version, forKey: .version)
    try values.encode(configuration, forKey: .configuration)
  }
}
