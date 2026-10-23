import Foundation

enum WebsiteConfigNativeStateRead: Equatable {
  case missing, available([String: WebsiteConfigValue]), unavailable
}

/// Isolated, explicitly injected preference generation. Not a live application
/// store, cross-process transaction, or configuration/resource commit protocol.
@MainActor
struct WebsiteConfigNativeStateStore {
  static let storageKey = "websiteConfig.native.v1"
  private let defaults: UserDefaults
  init(defaults: UserDefaults) { self.defaults = defaults }

  func read() -> WebsiteConfigNativeStateRead {
    guard let object = defaults.object(forKey: Self.storageKey) else { return .missing }
    guard let data = object as? Data, let state = try? WebsiteConfigNativeStateCodec.decode(data) else { return .unavailable }
    return .available(state)
  }

  /// True means accepted by this process's UserDefaults, not fsync durability.
  /// Never overwrite opaque current/future bytes or fill from a legacy key.
  @discardableResult
  func save(_ runtime: [String: WebsiteConfigValue]) -> Bool {
    if case .unavailable = read() { return false }
    guard let data = try? WebsiteConfigNativeStateCodec.encode(runtime) else { return false }
    defaults.set(data, forKey: Self.storageKey)
    return true
  }
}
