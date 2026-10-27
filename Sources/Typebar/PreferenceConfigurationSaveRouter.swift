import Foundation
import Observation

/// Synchronous delivery to one live practice window, never a broadcast or a saved setting.
@MainActor
@Observable
final class PreferenceConfigurationSaveRouter {
  struct Lease: Equatable, Sendable {
    let owner: UUID
    fileprivate let router: UUID
    fileprivate let generation: UUID
  }
  private let identity = UUID()
  private var generation = UUID()
  @ObservationIgnored private var leaseTransitions = 0
  private var handlers: [UUID: () -> Void] = [:]
  private var archiveAdmissions: [UUID: () -> Bool] = [:]
  func setWebsiteArchiveAdmission(owner: UUID, check: @escaping () -> Bool) { archiveAdmissions[owner] = check }
  var allowsWebsiteProfileArchiveRestore: Bool {
    guard let owner = priority.last else { return true }
    return archiveAdmissions[owner]?() ?? true
  }
  private var modifierProviders: [UUID: () -> [TestModifier]] = [:]
  private var languageProviders: [UUID: () -> TypingLanguage] = [:]
  private var keyboardGuideProviders: [UUID: () -> KeyboardGuideMode] = [:]
  private var fontFamilyProviders: [UUID: () -> String] = [:]
  private var fontSizeProviders: [UUID: () -> Double?] = [:]
  private var fontEditHandlers: [UUID: (PracticeFontEdit) -> Bool?] = [:]
  private var deliveringFontEdit = false
  private var priority: [UUID] = []
  private var isDelivering = false

  func register(owner: UUID, requestedModifiers: (() -> [TestModifier])? = nil,
    selectedLanguage: (() -> TypingLanguage)? = nil,
    keyboardGuideMode: (() -> KeyboardGuideMode)? = nil,
    fontFamilyName: (() -> String)? = nil,
    fontPointSize: (() -> Double?)? = nil,
    fontEdit: ((PracticeFontEdit) -> Bool?)? = nil,
    save: @escaping () -> Void) {
    leaseTransitions += 1
    defer { leaseTransitions -= 1 }
    let activeBefore = priority.last
    if handlers[owner] == nil { priority.insert(owner, at: 0) }
    handlers[owner] = save
    modifierProviders[owner] = requestedModifiers
    languageProviders[owner] = selectedLanguage
    keyboardGuideProviders[owner] = keyboardGuideMode
    fontFamilyProviders[owner] = fontFamilyName
    fontSizeProviders[owner] = fontPointSize
    fontEditHandlers[owner] = fontEdit
    if activeBefore != priority.last || priority.last == owner { generation = UUID() }
  }

  func captureLease() -> Lease? {
    guard leaseTransitions == 0, let owner = priority.last, handlers[owner] != nil else { return nil }
    return .init(owner: owner, router: identity, generation: generation)
  }

  func isCurrent(_ lease: Lease) -> Bool {
    leaseTransitions == 0 && lease.router == identity && lease.generation == generation
      && lease.owner == priority.last && handlers[lease.owner] != nil
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

  var fontFamilyName: String? {
    guard let owner = priority.last else { return nil }
    return fontFamilyProviders[owner]?()
  }

  var fontPointSize: Double? {
    guard let owner = priority.last else { return nil }
    return fontSizeProviders[owner]?()
  }
  /// nil selects the legacy native path; false is an owned rejection and must
  /// never fall through to mutating another configuration.
  func applyFontEdit(_ edit: PracticeFontEdit) -> Bool? {
    guard !deliveringFontEdit, !isDelivering, leaseTransitions == 0 else { return false }
    guard captureLease() != nil, let owner = priority.last, let action = fontEditHandlers[owner] else { return nil }
    deliveringFontEdit = true; defer { deliveringFontEdit = false }
    return action(edit)
  }

  func activate(owner: UUID) {
    guard handlers[owner] != nil else { return }
    leaseTransitions += 1
    defer { leaseTransitions -= 1 }
    if priority.last != owner { generation = UUID() }
    priority.removeAll { $0 == owner }
    priority.append(owner)
  }

  func remove(owner: UUID) {
    archiveAdmissions.removeValue(forKey: owner)
    leaseTransitions += 1
    defer { leaseTransitions -= 1 }
    let activeBefore = priority.last
    handlers.removeValue(forKey: owner)
    modifierProviders.removeValue(forKey: owner)
    languageProviders.removeValue(forKey: owner)
    keyboardGuideProviders.removeValue(forKey: owner)
    fontFamilyProviders.removeValue(forKey: owner)
    fontSizeProviders.removeValue(forKey: owner)
    fontEditHandlers.removeValue(forKey: owner)
    priority.removeAll { $0 == owner }
    if activeBefore != priority.last { generation = UUID() }
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
