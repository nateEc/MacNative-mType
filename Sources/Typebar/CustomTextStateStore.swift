import Foundation

enum CustomTextSource: Codable, Equatable {
  case editor(String)
  case prepared([String])

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
  static func returningSource(captured: CustomTextStateDocument?,
    latest: () -> CustomTextStateDocument) -> CustomTextStateDocument? {
    captured ?? latest()
  }

  static func source(stored: CustomTextStateDocument?, activePreset: SavedTestPreset?,
    explicitSelectionImport: Bool) -> CustomTextStateDocument? {
    // An explicit custom selection/import owns its text. An ordinary mode
    // change does not erase the independently retained custom source.
    if explicitSelectionImport, activePreset?.configuration.mode == .custom { return nil }
    return stored
  }
}

struct CustomTextStateStore {
  static let storageKey = "customTextState.v1"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  func load() -> CustomTextStateDocument? {
    guard let data = defaults.data(forKey: Self.storageKey),
      let document = try? JSONDecoder().decode(CustomTextStateDocument.self, from: data),
      document.isValid else { return nil }
    return document
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
