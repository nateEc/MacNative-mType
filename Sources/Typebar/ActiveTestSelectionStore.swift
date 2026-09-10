import Foundation

enum QuoteSource: String, CaseIterable, Codable, Equatable, Identifiable {
  case builtIn
  case community

  var id: Self { self }
  var title: String { self == .builtIn ? "Typebar 自有" : "社区审核" }
}

struct ActiveTestSelectionDocument: Codable, Equatable {
  static let currentVersion = 1

  let version: Int
  let preset: SavedTestPreset
  let quoteSource: QuoteSource
  let testParameterMemory: TypebarTestParameterMemory

  init(
    version: Int = ActiveTestSelectionDocument.currentVersion,
    preset: SavedTestPreset,
    quoteSource: QuoteSource = .builtIn,
    testParameterMemory: TypebarTestParameterMemory
  ) {
    self.version = version
    self.preset = .init(
      configuration: preset.configuration,
      quoteID: preset.quoteID,
      customText: preset.customText,
      activeResultTags: nil)
    self.quoteSource = quoteSource
    self.testParameterMemory = testParameterMemory
  }
}

enum ActiveTestSelectionPolicy {
  static func validated(
    _ document: ActiveTestSelectionDocument
  ) -> ActiveTestSelectionDocument? {
    guard document.version == ActiveTestSelectionDocument.currentVersion,
      SettingsJSONConfigurationPolicy.isValid(document.preset.configuration),
      SettingsJSONConfigurationPolicy.isValid(document.testParameterMemory)
    else { return nil }
    if let quoteID = document.preset.quoteID,
      quoteID.isEmpty || quoteID.count > 256
    {
      return nil
    }
    if document.preset.configuration.mode == .custom {
      guard let customText = document.preset.customText,
        CustomTextPolicy.isValid(customText)
      else { return nil }
    } else if document.preset.customText != nil {
      return nil
    }
    return ActiveTestSelectionDocument(
      version: document.version,
      preset: document.preset,
      quoteSource: document.quoteSource,
      testParameterMemory: document.testParameterMemory)
  }
}

struct ActiveTestSelectionStore {
  static let storageKey = "activeTestSelection.v1"

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func load() -> ActiveTestSelectionDocument? {
    guard let data = defaults.data(forKey: Self.storageKey),
      let decoded = try? JSONDecoder().decode(ActiveTestSelectionDocument.self, from: data)
    else { return nil }
    return ActiveTestSelectionPolicy.validated(decoded)
  }

  @discardableResult
  func save(_ document: ActiveTestSelectionDocument) -> Bool {
    guard let document = ActiveTestSelectionPolicy.validated(document),
      let data = try? JSONEncoder().encode(document)
    else { return false }
    defaults.set(data, forKey: Self.storageKey)
    return true
  }

  func remove() {
    defaults.removeObject(forKey: Self.storageKey)
  }
}
