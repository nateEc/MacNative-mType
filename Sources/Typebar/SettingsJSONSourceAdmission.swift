import Foundation

@MainActor
enum SettingsJSONSourceAdmission {
  static func preparing(_ document: TypebarSettingsDocument, for settings: AppSettings) throws -> TypebarSettingsDocument {
    let incomingSource = document.settings.thresholdSource != nil || document.configuration.rules.thresholdSource != nil
    guard settings.hasThresholdProfile else {
      guard !incomingSource else { throw SettingsJSONCommandError.thresholdSourceNotReady }
      return document
    }
    guard let current = settings.snapshot.thresholdSource,
      case .available(let stored) = settings.thresholdProfileRead,
      stored.thresholdSource == current,
      settings.activeTestSelectionRead != .unavailable
    else { throw SettingsJSONCommandError.settingsNotApplied }
    let prepared: TypebarSettingsDocument
    if incomingSource { prepared = document }
    else {
      let source: PracticeThresholdSource
      do { source = try LegacyThresholdProjection.source(for: document.configuration.rules, preserving: current) }
      catch { throw SettingsJSONCommandError.invalidConfiguration }
      guard source.matches(document.settings) else { throw SettingsJSONCommandError.invalidConfiguration }
      var configuration = document.configuration
      configuration.rules = source.applying(to: configuration.rules)
      prepared = .init(settings: source.applying(to: document.settings), configuration: configuration,
        layoutFluidLayouts: document.layoutFluidLayouts, testParameterMemory: document.testParameterMemory)
    }
    let preset = SavedTestPreset(configuration: prepared.configuration, settingsSnapshot: prepared.settings)
    guard (try? LocalPresetCodec.encode(preset)) != nil,
      PresetSettingsApplication.agreesWithSnapshot(preset)
    else { throw SettingsJSONCommandError.invalidConfiguration }
    return prepared
  }
}
