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

struct ActiveTestSelectionStore {
  static let storageKey = "activeTestSelection.v1"

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func load() -> ActiveTestSelectionDocument? {
    guard let data = defaults.data(forKey: Self.storageKey),
      let decoded = try? JSONDecoder().decode(ActiveTestSelectionDocument.self, from: data),
      isValid(decoded)
    else { return nil }
    return ActiveTestSelectionDocument(
      version: decoded.version,
      preset: decoded.preset,
      quoteSource: decoded.quoteSource,
      testParameterMemory: decoded.testParameterMemory)
  }

  @discardableResult
  func save(_ document: ActiveTestSelectionDocument) -> Bool {
    guard isValid(document), let data = try? JSONEncoder().encode(document) else { return false }
    defaults.set(data, forKey: Self.storageKey)
    return true
  }

  func remove() {
    defaults.removeObject(forKey: Self.storageKey)
  }

  private func isValid(_ document: ActiveTestSelectionDocument) -> Bool {
    guard document.version == ActiveTestSelectionDocument.currentVersion,
      SettingsJSONConfigurationPolicy.isValid(document.preset.configuration),
      SettingsJSONConfigurationPolicy.isValid(document.testParameterMemory)
    else { return false }
    if let quoteID = document.preset.quoteID,
      quoteID.isEmpty || quoteID.count > 256
    {
      return false
    }
    if document.preset.configuration.mode == .custom {
      guard let customText = document.preset.customText,
        CustomTextPolicy.isValid(customText)
      else { return false }
    } else if document.preset.customText != nil {
      return false
    }
    return true
  }
}
