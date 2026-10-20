import Foundation

enum QuoteSource: String, CaseIterable, Codable, Equatable, Identifiable {
  case builtIn
  case community

  var id: Self { self }
  var title: String { self == .builtIn ? "Typebar 自有" : "社区审核" }
}

struct ActiveTestSelectionDocument: Codable, Equatable {
  static let currentVersion = 2
  static let legacyVersion = 1

  let version: Int
  let preset: SavedTestPreset
  let quoteSource: QuoteSource
  let testParameterMemory: TypebarTestParameterMemory
  /// The ordinary language selected before the native Polyglot command
  /// substituted the mixed-language prompt. This mirrors the reference
  /// configuration, which leaves its selected language intact under Polyglot.
  let polyglotReturnLanguage: TypingLanguage?
  /// The physical hand side/layout selected for a local one-handed challenge.
  let oneHandedChallengeSelection: OneHandedChallengeSelection?

  init(
    version: Int? = nil,
    preset: SavedTestPreset,
    quoteSource: QuoteSource = .builtIn,
    testParameterMemory: TypebarTestParameterMemory,
    polyglotReturnLanguage: TypingLanguage? = nil,
    oneHandedChallengeSelection: OneHandedChallengeSelection? = nil
  ) {
    self.version = version ?? (PracticeThresholdSource.isPresent(in: preset) ? Self.currentVersion : Self.legacyVersion)
    self.preset = .init(
      configuration: preset.configuration,
      quoteID: preset.quoteID,
      customText: preset.customText,
      activeResultTags: nil,
      settingsSnapshot: PracticeThresholdSource.isPresent(in: preset) ? preset.settingsSnapshot : nil)
    self.quoteSource = quoteSource
    self.testParameterMemory = testParameterMemory
    self.polyglotReturnLanguage = PolyglotReturnLanguagePolicy.validated(
      polyglotReturnLanguage)
    self.oneHandedChallengeSelection = oneHandedChallengeSelection
  }

  private enum CodingKeys: String, CodingKey {
    case version
    case preset
    case presetData
    case quoteSource
    case testParameterMemory
    case polyglotReturnLanguage
    case oneHandedChallengeSelection
  }

  func encode(to encoder: Encoder) throws {
    let document: Self
    if version == Self.currentVersion {
      guard let normalized = ActiveTestSelectionPolicy.validated(self) else {
        throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath, debugDescription: "Invalid source selection"))
      }
      document = normalized
    } else {
      guard !PracticeThresholdSource.isPresent(in: preset) else {
        throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath,
          debugDescription: "Active selection generation does not support threshold source"))
      }
      document = self
    }
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(version, forKey: .version)
    if version == Self.currentVersion {
      try values.encode(LocalPresetCodec.encode(document.preset), forKey: .presetData)
    } else { try values.encode(document.preset, forKey: .preset) }
    try values.encode(document.quoteSource, forKey: .quoteSource)
    try values.encode(document.testParameterMemory, forKey: .testParameterMemory)
    try values.encodeIfPresent(document.polyglotReturnLanguage, forKey: .polyglotReturnLanguage)
    try values.encodeIfPresent(document.oneHandedChallengeSelection, forKey: .oneHandedChallengeSelection)
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let version = try container.decode(Int.self, forKey: .version)
    guard (Self.legacyVersion...Self.currentVersion).contains(version) else {
      throw DecodingError.dataCorruptedError(forKey: .version, in: container, debugDescription: "Unsupported selection version")
    }
    let preset: SavedTestPreset
    if version == Self.currentVersion {
      guard !container.contains(.preset) else {
        throw DecodingError.dataCorruptedError(forKey: .preset, in: container, debugDescription: "Mixed selection payloads")
      }
      preset = try LocalPresetCodec.decode(container.decode(Data.self, forKey: .presetData))
      guard preset.configuration.rules.thresholdSource != nil, preset.settingsSnapshot == nil,
        preset.activeResultTags == nil, preset.settingGroups == nil else {
        throw DecodingError.dataCorruptedError(forKey: .presetData, in: container, debugDescription: "Invalid portable source selection")
      }
    } else {
      guard !container.contains(.presetData) else {
        throw DecodingError.dataCorruptedError(forKey: .presetData, in: container, debugDescription: "Source requires a new selection generation")
      }
      preset = try container.decode(SavedTestPreset.self, forKey: .preset)
      guard !PracticeThresholdSource.isPresent(in: preset) else {
        throw DecodingError.dataCorruptedError(forKey: .preset, in: container,
          debugDescription: "Active selection generation does not support threshold source")
      }
    }
    self.init(
      version: version,
      preset: preset,
      quoteSource: try container.decode(QuoteSource.self, forKey: .quoteSource),
      testParameterMemory: try container.decode(
        TypebarTestParameterMemory.self, forKey: .testParameterMemory),
      polyglotReturnLanguage: try container.decodeIfPresent(
        TypingLanguage.self, forKey: .polyglotReturnLanguage),
      oneHandedChallengeSelection: try container.decodeIfPresent(
        OneHandedChallengeSelection.self, forKey: .oneHandedChallengeSelection))
    if version == Self.currentVersion {
      guard let normalized = ActiveTestSelectionPolicy.validated(self) else {
        throw DecodingError.dataCorruptedError(forKey: .presetData, in: container, debugDescription: "Invalid source selection")
      }
      self = normalized
    }
  }
}

enum PolyglotReturnLanguagePolicy {
  static func validated(_ language: TypingLanguage?) -> TypingLanguage? {
    guard let language, language != .mixedLanguages else { return nil }
    return language
  }
}

enum ActiveTestSelectionPolicy {
  static func validated(
    _ document: ActiveTestSelectionDocument
  ) -> ActiveTestSelectionDocument? {
    guard (ActiveTestSelectionDocument.legacyVersion...ActiveTestSelectionDocument.currentVersion).contains(document.version),
      SettingsJSONConfigurationPolicy.isValid(document.preset.configuration),
      SettingsJSONConfigurationPolicy.isValid(document.testParameterMemory)
    else { return nil }
    let hasSource = PracticeThresholdSource.isPresent(in: document.preset)
    guard hasSource == (document.version == ActiveTestSelectionDocument.currentVersion) else { return nil }
    if hasSource, (try? LocalPresetCodec.encode(document.preset)) == nil { return nil }
    if let quoteID = document.preset.quoteID,
      quoteID.isEmpty || quoteID.count > 256
    {
      return nil
    }
    if document.preset.configuration.mode == .custom {
      guard let customText = document.preset.customText,
        CustomTextPolicy.isValid(customText, configuration: document.preset.configuration)
      else { return nil }
    } else if document.preset.customText != nil {
      return nil
    }
    var selection = document.preset
    selection.settingsSnapshot = nil
    return ActiveTestSelectionDocument(
      version: document.version,
      preset: selection,
      quoteSource: document.quoteSource,
      testParameterMemory: document.testParameterMemory,
      polyglotReturnLanguage: document.preset.configuration.language == .mixedLanguages
        ? document.polyglotReturnLanguage : nil,
      oneHandedChallengeSelection: document.oneHandedChallengeSelection.flatMap { selection in
        document.preset.configuration.challengeID == "one-handed-bandit"
          && OneHandedChallengePolicy.source(for: selection) == document.preset.customText
          ? selection : nil
      })
  }
}

enum ActiveTestSelectionRead: Equatable {
  case missing, unavailable
  case available(ActiveTestSelectionDocument)
}

struct ActiveTestSelectionStore {
  static let storageKey = "activeTestSelection.v1"
  static let sourceStorageKey = "activeTestSelection.v2"

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func load() -> ActiveTestSelectionDocument? {
    if case .available(let document) = read() { return document }
    return nil
  }

  func read() -> ActiveTestSelectionRead {
    let sourcePresent = defaults.object(forKey: Self.sourceStorageKey) != nil
    let key = sourcePresent ? Self.sourceStorageKey : Self.storageKey
    guard let value = defaults.object(forKey: key) else { return .missing }
    guard let data = value as? Data,
      let decoded = try? JSONDecoder().decode(ActiveTestSelectionDocument.self, from: data)
    else { return .unavailable }
    guard decoded.version == (sourcePresent ? ActiveTestSelectionDocument.currentVersion : ActiveTestSelectionDocument.legacyVersion),
      let validated = ActiveTestSelectionPolicy.validated(decoded) else { return .unavailable }
    return .available(validated)
  }

  @discardableResult
  func save(_ document: ActiveTestSelectionDocument) -> Bool {
    guard let document = ActiveTestSelectionPolicy.validated(document),
      let data = try? JSONEncoder().encode(document)
    else { return false }
    if defaults.object(forKey: Self.sourceStorageKey) != nil {
      guard case .available = read(), document.version == ActiveTestSelectionDocument.currentVersion else { return false }
    }
    defaults.set(data, forKey: document.version == ActiveTestSelectionDocument.currentVersion ? Self.sourceStorageKey : Self.storageKey)
    return true
  }

  func remove() {
    defaults.removeObject(forKey: Self.storageKey)
    defaults.removeObject(forKey: Self.sourceStorageKey)
  }
}
