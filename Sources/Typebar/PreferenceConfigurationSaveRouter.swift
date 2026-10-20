import Foundation

/// Synchronous delivery to one live practice window, never a broadcast or a saved setting.
@MainActor
final class PreferenceConfigurationSaveRouter {
  private var handlers: [UUID: () -> Void] = [:]
  private var priority: [UUID] = []
  private var isDelivering = false

  func register(owner: UUID, save: @escaping () -> Void) {
    if handlers[owner] == nil { priority.insert(owner, at: 0) }
    handlers[owner] = save
  }

  func activate(owner: UUID) {
    guard handlers[owner] != nil else { return }
    priority.removeAll { $0 == owner }
    priority.append(owner)
  }

  func remove(owner: UUID) {
    handlers.removeValue(forKey: owner)
    priority.removeAll { $0 == owner }
  }

  /// A true result means delivery, not successful persistence or disk durability.
  @discardableResult
  func deliver() -> Bool {
    guard !isDelivering, let owner = priority.last, let save = handlers[owner] else { return false }
    isDelivering = true
    defer { isDelivering = false }
    save()
    return true
  }
}
