import Foundation

/// Independent source-local memories, not fields of the 94-key configuration
/// and not aliases of the legacy Typebar preferences.
struct WebsiteConfigLazyModeMemory: Equatable, Sendable, Decodable {
  var remember = false
  var prefersArabic = true

  var recordValue: WebsiteConfigValue { .array([.bool(remember), .bool(prefersArabic)]) }
  init(remember: Bool = false, prefersArabic: Bool = true) {
    self.remember = remember; self.prefersArabic = prefersArabic
  }
  init?(recordValue: WebsiteConfigValue) {
    guard case .array(let values) = recordValue, values.count == 2,
      case .bool(let remember) = values[0], case .bool(let arabic) = values[1] else { return nil }
    self.init(remember: remember, prefersArabic: arabic)
  }
}
