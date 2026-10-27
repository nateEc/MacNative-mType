import Foundation

/// Old transports carry active values only. Disabled values keep the current
/// source owner's memory; no missing historical value is invented.
enum LegacyThresholdProjection {
  enum Failure: Error { case invalidRules }

  static func source(for rules: InputRules, preserving current: PracticeThresholdSource) throws -> PracticeThresholdSource {
    guard rules.minimumWpm.isFinite, rules.minimumWpm >= 0,
      rules.minimumAccuracy.isFinite, (0...100).contains(rules.minimumAccuracy),
      rules.minimumWordBurstWpm.isFinite, rules.minimumWordBurstWpm >= 0,
      (rules.minimumWordBurstWpm == 0 && rules.minimumWordBurstMode == .off)
        || (rules.minimumWordBurstWpm > 0 && rules.minimumWordBurstMode != .off)
    else { throw Failure.invalidRules }
    var raw = current.configuration
    try raw.apply(.minimumWpm(mode: rules.minimumWpm > 0 ? .custom : .off,
      customValue: rules.minimumWpm > 0 ? rules.minimumWpm : nil), allowingWebsiteValues: true)
    try raw.apply(.minimumAccuracy(mode: rules.minimumAccuracy > 0 ? .custom : .off,
      customValue: rules.minimumAccuracy > 0 ? rules.minimumAccuracy : nil), allowingWebsiteValues: true)
    try raw.apply(.minimumWordBurst(mode: rules.minimumWordBurstMode,
      customValue: rules.minimumWordBurstWpm > 0 ? rules.minimumWordBurstWpm : nil), allowingWebsiteValues: true)
    return .init(configuration: raw)
  }
}
