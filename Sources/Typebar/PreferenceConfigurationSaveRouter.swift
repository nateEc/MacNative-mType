import Foundation
import Observation

/// Synchronous delivery to one live practice window, never a broadcast or a saved setting.
@MainActor
@Observable
final class PreferenceConfigurationSaveRouter {
  private var handlers: [UUID: () -> Void] = [:]
  private var modifierProviders: [UUID: () -> [TestModifier]] = [:]
  private var languageProviders: [UUID: () -> TypingLanguage] = [:]
  private var keyboardGuideProviders: [UUID: () -> KeyboardGuideMode] = [:]
  private var priority: [UUID] = []
  private var isDelivering = false

  func register(owner: UUID, requestedModifiers: (() -> [TestModifier])? = nil,
    selectedLanguage: (() -> TypingLanguage)? = nil,
    keyboardGuideMode: (() -> KeyboardGuideMode)? = nil,
    save: @escaping () -> Void) {
    if handlers[owner] == nil { priority.insert(owner, at: 0) }
    handlers[owner] = save
    modifierProviders[owner] = requestedModifiers
    languageProviders[owner] = selectedLanguage
    keyboardGuideProviders[owner] = keyboardGuideMode
  }

  /// Read live state from the same owner that would receive an explicit save.
  var requestedModifiers: [TestModifier]? {
    guard let owner = priority.last else { return nil }
    return modifierProviders[owner]?()
  }

  var selectedLanguage: TypingLanguage? {
    guard let owner = priority.last else { return nil }
    return languageProviders[owner]?()
  }

  var keyboardGuideMode: KeyboardGuideMode? {
    guard let owner = priority.last else { return nil }
    return keyboardGuideProviders[owner]?()
  }

  func activate(owner: UUID) {
    guard handlers[owner] != nil else { return }
    priority.removeAll { $0 == owner }
    priority.append(owner)
  }

  func remove(owner: UUID) {
    handlers.removeValue(forKey: owner)
    modifierProviders.removeValue(forKey: owner)
    languageProviders.removeValue(forKey: owner)
    keyboardGuideProviders.removeValue(forKey: owner)
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
