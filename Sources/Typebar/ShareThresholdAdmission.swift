import Foundation

/// Test-selection transport only. This never adopts a source profile or
/// imports appearance, tags or preset scope from a link.
enum ShareThresholdAdmission {
  static func preparing(_ incoming: SavedTestPreset, current: SavedTestPreset) throws -> SavedTestPreset {
    guard incoming.settingsSnapshot == nil, incoming.activeResultTags == nil, incoming.settingGroups == nil
    else { throw TestConfigurationShareError.invalidConfiguration }
    let currentHasSource = PracticeThresholdSource.isPresent(in: current)
    let incomingHasSource = PracticeThresholdSource.isPresent(in: incoming)
    guard currentHasSource || incomingHasSource else { return incoming }
    guard currentHasSource else { throw TestConfigurationShareError.thresholdSourceNotReady }
    guard let source = current.configuration.rules.thresholdSource,
      (try? LocalPresetCodec.encode(current)) != nil
    else { throw TestConfigurationShareError.invalidConfiguration }
    guard incoming.configuration.challengeID == nil else {
      throw TestConfigurationShareError.thresholdSourceChallengeNotReady
    }
    if incomingHasSource {
      guard (try? LocalPresetCodec.encode(incoming)) != nil else {
        throw TestConfigurationShareError.invalidConfiguration
      }
      return incoming
    }

    // Old native links own effective thresholds, not the values remembered
    // while off. Preserve that missing information from the current owner.
    let rules = incoming.configuration.rules
    guard rules.minimumWpm.isFinite, rules.minimumWpm >= 0,
      rules.minimumAccuracy.isFinite, (0...100).contains(rules.minimumAccuracy),
      rules.minimumWordBurstWpm.isFinite, rules.minimumWordBurstWpm >= 0,
      (rules.minimumWordBurstWpm == 0 && rules.minimumWordBurstMode == .off)
        || (rules.minimumWordBurstWpm > 0 && rules.minimumWordBurstMode != .off)
    else { throw TestConfigurationShareError.invalidConfiguration }
    var raw = source.configuration
    try raw.apply(.minimumWpm(mode: rules.minimumWpm > 0 ? .custom : .off,
      customValue: rules.minimumWpm > 0 ? rules.minimumWpm : nil))
    try raw.apply(.minimumAccuracy(mode: rules.minimumAccuracy > 0 ? .custom : .off,
      customValue: rules.minimumAccuracy > 0 ? rules.minimumAccuracy : nil))
    try raw.apply(.minimumWordBurst(mode: rules.minimumWordBurstMode,
      customValue: rules.minimumWordBurstWpm > 0 ? rules.minimumWordBurstWpm : nil))
    var prepared = incoming
    prepared.configuration.rules = PracticeThresholdSource(configuration: raw).applying(to: rules)
    return prepared
  }
}
