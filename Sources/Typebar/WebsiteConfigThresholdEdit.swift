import Foundation

/// One actual source setter. In particular, the burst value setter does not
/// select fixed/flex, while the speed/accuracy value setters select custom.
enum WebsiteConfigThresholdEdit: Equatable {
  case speedMode(PracticeThresholdConfiguration.Mode), speedValue(Double)
  case accuracyMode(PracticeThresholdConfiguration.Mode), accuracyValue(Double)
  case burstMode(MinimumWordBurstMode), burstValue(Double)

  static let keys: Set<String> = ["minWpm", "minWpmCustomSpeed", "minAcc", "minAccCustom", "minBurst", "minBurstCustomSpeed"]
  var key: String {
    switch self {
    case .speedMode: "minWpm"; case .speedValue: "minWpmCustomSpeed"
    case .accuracyMode: "minAcc"; case .accuracyValue: "minAccCustom"
    case .burstMode: "minBurst"; case .burstValue: "minBurstCustomSpeed"
    }
  }
  var value: WebsiteConfigValue {
    switch self {
    case .speedMode(let mode), .accuracyMode(let mode): .string(mode.rawValue)
    case .burstMode(let mode): .string(mode.rawValue)
    case .speedValue(let value), .accuracyValue(let value), .burstValue(let value): .number(value)
    }
  }
}
