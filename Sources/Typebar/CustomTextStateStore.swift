import Foundation

enum CustomTextSource: Codable, Equatable {
  case editor(String)
  case prepared([String])

  static func == (lhs: Self, rhs: Self) -> Bool {
    switch (lhs, rhs) {
    case (.editor(let lhs), .editor(let rhs)):
      return InputTextIdentity.matches(lhs, rhs)
    case (.prepared(let lhs), .prepared(let rhs)):
      return lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { InputTextIdentity.matches($0.0, $0.1) }
    default:
      return false
    }
  }

  var text: String {
    switch self {
    case .editor(let text): text
    case .prepared(let sections): sections.joined(separator: " | ")
    }
  }

  func preparedSections(matching text: String) -> [String]? {
    guard case .prepared(let sections) = self, InputTextIdentity.matches(self.text, text) else { return nil }
    return sections
  }
}

/// The most recent custom source is independent of the ordinary selected mode.
/// No language, input rules, result tags, or return-navigation state is stored.
struct CustomTextStateDocument: Codable, Equatable {
  static let currentVersion = 1
  let version: Int
  let source: CustomTextSource
  let completion: CustomTextCompletion
  let ordering: CustomTextOrdering
  let duration: TimeInterval?
  let wordLimit: Int?
  let sectionLimit: Int?
  let pipeDelimiter: Bool?

  init(version: Int = Self.currentVersion, source: CustomTextSource, configuration: TestConfiguration) {
    self.version = version
    self.source = source
    completion = configuration.customTextCompletion
    ordering = configuration.customTextOrdering
    duration = completion == .time ? configuration.duration : nil
    wordLimit = completion == .words ? configuration.wordLimit : nil
    sectionLimit = completion == .sections ? configuration.customTextSectionLimit : nil
    pipeDelimiter = configuration.customTextPipeDelimiter
  }

  /// Only the custom controls; callers retain their current language/rules.
  var configuration: TestConfiguration {
    .init(mode: .custom, duration: duration, wordLimit: wordLimit, difficulty: .normal,
      rules: .init(), customTextCompletion: completion, customTextSectionLimit: sectionLimit,
      customTextOrdering: ordering, customTextPipeDelimiter: pipeDelimiter)
  }

  var isValid: Bool {
    guard version == Self.currentVersion,
      completion == .time || duration == nil,
      completion == .words || wordLimit == nil,
      completion == .sections || sectionLimit == nil,
      SettingsJSONConfigurationPolicy.isValid(configuration) else { return false }
    switch source {
    case .editor(let text): return CustomTextPolicy.isValid(text, configuration: configuration)
    case .prepared(let sections): return !sections.isEmpty
    }
  }
}

enum CustomTextRestorePolicy {
  static func restoration(read: CustomTextStateRead, activePreset: SavedTestPreset?,
    explicitSelectionImport: Bool) -> (document: CustomTextStateDocument?, recovery: CustomTextRecoveryState) {
    var recovery = CustomTextRecoveryState(read: read)
    if explicitSelectionImport, acceptsReplacement(activePreset) {
      recovery.acceptExplicitSource()
      if let source = legacySource(activePreset) { recovery.stageKnownSource(source) }
      return (nil, recovery)
    }
    if case .missing = read, let source = legacySource(activePreset) {
      recovery.stageKnownSource(source)
    }
    return (recovery.requiresExplicitSource ? nil : read.document, recovery)
  }

  private static func legacySource(_ preset: SavedTestPreset?) -> CustomTextStateDocument? {
    guard acceptsReplacement(preset), let preset, let text = preset.customText else { return nil }
    let source = CustomTextStateDocument(source: .editor(text), configuration: preset.configuration)
    return source.isValid ? source : nil
  }

  static func acceptsReplacement(_ preset: SavedTestPreset?) -> Bool {
    guard let preset, preset.configuration.mode == .custom,
      let text = preset.customText else { return false }
    return CustomTextPolicy.isValid(text, configuration: preset.configuration)
  }

  static func returningSource(captured: CustomTextStateDocument?,
    latest: () -> CustomTextStateDocument) -> CustomTextStateDocument? {
    guard let captured else { return latest() }
    var configuration = captured.configuration
    // Reference return restores text/limit/delimiter but not the sort mode.
    configuration.customTextOrdering = latest().ordering
    return .init(version: captured.version, source: captured.source, configuration: configuration)
  }

  static func source(stored: CustomTextStateDocument?, activePreset: SavedTestPreset?,
    explicitSelectionImport: Bool) -> CustomTextStateDocument? {
    // An explicit custom selection/import owns its text. An ordinary mode
    // change does not erase the independently retained custom source.
    if explicitSelectionImport, acceptsReplacement(activePreset) { return nil }
    return stored
  }
}

enum CustomTextStateRead: Equatable {
  case missing
  case available(CustomTextStateDocument)
  case unavailable

  var document: CustomTextStateDocument? {
    guard case .available(let document) = self else { return nil }
    return document
  }
}

struct CustomTextRecoveryState: Equatable {
  private(set) var requiresExplicitSource: Bool
  private(set) var pendingSource: CustomTextStateDocument?

  init(read: CustomTextStateRead = .missing) {
    pendingSource = nil
    switch read {
    case .missing: requiresExplicitSource = false
    case .available(let document):
      let valid = document.isValid
      requiresExplicitSource = !valid
      pendingSource = valid ? document : nil
    case .unavailable: requiresExplicitSource = true
    }
  }

  var blocksCustomGeneration: Bool { requiresExplicitSource || pendingSource != nil }

  mutating func stageKnownSource(_ source: CustomTextStateDocument) {
    guard !requiresExplicitSource, source.isValid else { return }
    pendingSource = source
  }

  mutating func takePendingSource(whenAllowed: Bool) -> CustomTextStateDocument? {
    guard whenAllowed else { return nil }
    defer { pendingSource = nil }
    return pendingSource
  }

  mutating func acceptExplicitSource() {
    requiresExplicitSource = false
    pendingSource = nil
  }

  func permitsAutomaticPersistence(mode: TestMode) -> Bool {
    mode != .custom || !blocksCustomGeneration
  }
}

struct CustomTextStateStore {
  static let storageKey = "customTextState.v1"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  func load() -> CustomTextStateDocument? {
    read().document
  }

  func read() -> CustomTextStateRead {
    guard defaults.object(forKey: Self.storageKey) != nil else { return .missing }
    guard let data = defaults.data(forKey: Self.storageKey),
      let document = try? JSONDecoder().decode(CustomTextStateDocument.self, from: data),
      document.isValid else { return .unavailable }
    return .available(document)
  }

  @discardableResult
  func save(_ document: CustomTextStateDocument) -> Bool {
    struct Version: Decodable { let version: Int }
    if let existing = defaults.data(forKey: Self.storageKey),
      let version = try? JSONDecoder().decode(Version.self, from: existing),
      version.version != CustomTextStateDocument.currentVersion { return false }
    guard document.isValid, let data = try? JSONEncoder().encode(document) else { return false }
    defaults.set(data, forKey: Self.storageKey)
    return true
  }
}
