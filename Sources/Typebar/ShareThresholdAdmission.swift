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

    var prepared = incoming
    do {
      prepared.configuration.rules = try LegacyThresholdProjection.source(
        for: incoming.configuration.rules, preserving: source).applying(to: incoming.configuration.rules)
    } catch { throw TestConfigurationShareError.invalidConfiguration }
    return prepared
  }
}
