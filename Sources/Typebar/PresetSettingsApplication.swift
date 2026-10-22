import Foundation

@MainActor
enum PresetSettingsApplication {
  /// Complete settings admission before the scene mutates selection state.
  /// Selection-only success neither writes preferences nor persists selection.
  static func commit(
    original: SavedTestPreset, resolved: SavedTestPreset,
    configuration: TestConfiguration, to settings: AppSettings,
    appliesGlobalSettings: Bool
  ) -> Bool {
    guard settings.allowsRestartingConfigurationChange else { return false }
    let sourceContext =
      settings.hasThresholdProfile || PracticeThresholdSource.isPresent(in: original)
      || PracticeThresholdSource.isPresent(in: resolved)
    if sourceContext {
      // This opens selection-only restoration, not source adoption, partial
      // preset effects or challenge rule overrides that are not migrated yet.
      guard !appliesGlobalSettings, settings.thresholdConfiguration != nil,
        case .available = settings.thresholdProfileRead,
        settings.activeTestSelectionRead != .unavailable,
        !original.isPartial, !resolved.isPartial,
        original.configuration.challengeID == nil, resolved.configuration.challengeID == nil,
        configuration.challengeID == nil,
        SettingsJSONConfigurationPolicy.isValid(configuration)
      else { return false }
      for definition in [original, resolved] where PracticeThresholdSource.isPresent(in: definition)
      {
        guard (try? LocalPresetCodec.encode(definition)) != nil else { return false }
      }
    }
    guard appliesGlobalSettings else { return true }
    let committed: Bool
    if let snapshot = resolved.settingsSnapshot {
      committed = settings.apply(snapshot)
    } else {
      committed = settings.apply(configuration)
    }
    guard committed else { return false }
    let appliesTags = !original.isPartial || (original.settingGroups?.contains(.behavior) == true)
    if appliesTags, let tags = resolved.activeResultTags { settings.activeResultTags = tags }
    return true
  }
}

enum PresetResourceAdmission {
  enum Refusal: Equatable { case missingWingdings, missingVerifiedScript }

  static func refusal(
    for configuration: TestConfiguration,
    wingdingsAvailable: () -> Bool,
    scriptIsVerified: (ReferenceScriptChallengePolicy.Specification) -> Bool
  ) -> Refusal? {
    guard let challenge = TypebarChallengeLibrary.challenge(id: configuration.challengeID) else {
      return nil
    }
    if challenge.id == "ten-words-of-pain", !wingdingsAvailable() { return .missingWingdings }
    if let specification = challenge.requirements.referenceScriptSpecification,
      !scriptIsVerified(specification)
    {
      return .missingVerifiedScript
    }
    return nil
  }
}
