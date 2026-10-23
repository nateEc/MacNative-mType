import Foundation

@MainActor
enum SourceChallengeAdmission {
  /// A library challenge is a transient selection, not an arbitrary preset
  /// allowed to replace global preferences under the same public identity.
  nonisolated static func accepts(_ preset: SavedTestPreset) -> Bool {
    guard !preset.isPartial, preset.settingsSnapshot == nil, preset.activeResultTags == nil,
      preset.quoteID == nil,
      let challenge = TypebarChallengeLibrary.challenge(id: preset.configuration.challengeID),
      SettingsJSONConfigurationPolicy.isValid(preset.configuration),
      (try? LocalPresetCodec.encode(preset)) != nil else { return false }
    var template = challenge.preset.configuration
    if challenge.id == "one-handed-bandit" {
      guard let text = preset.customText,
        let selection = OneHandedChallengePolicy.identify(source: text),
        let selected = OneHandedChallengePolicy.preset(for: selection) else { return false }
      template = selected.configuration
    } else if preset.customText != challenge.preset.customText { return false }
    var canonical = ChallengeSetupSelectionPolicy.applying(.init(configuration: preset.configuration),
      for: challenge, template: template)
    canonical.rules = preset.configuration.rules
    // These optional generation markers belong to the selected language's
    // existing format, not to challenge limits or completion requirements.
    canonical.polyglotUsesPrimaryDirection = preset.configuration.polyglotUsesPrimaryDirection
    canonical.polyglotUsesPrimaryCodeInput = preset.configuration.polyglotUsesPrimaryCodeInput
    canonical.polyglotUsesPrimaryInputNormalization = preset.configuration.polyglotUsesPrimaryInputNormalization
    canonical.dockerfileUsesLiteralIndentation = preset.configuration.dockerfileUsesLiteralIndentation
    canonical.zenUsesSourceInputAdmission = preset.configuration.zenUsesSourceInputAdmission
    if canonical == preset.configuration { return true }
    // A captured session can contain automatic Arabic or Polyglot filtering.
    // Permit only the existing projections of this challenge's own modifiers.
    return [false, true].contains { automaticArabic in
      canonical.with(modifiers: EffectiveTestModifierPolicy.modifiers(
        requested: template.modifiers, language: canonical.language, mode: canonical.mode,
        mixedLanguageComponents: canonical.mixedLanguageComponents,
        automaticallyEnabledArabic: automaticArabic)) == preset.configuration
    }
  }

  static func commit(original: SavedTestPreset, resolved: SavedTestPreset,
    configuration: TestConfiguration, to settings: AppSettings, appliesGlobalSettings: Bool,
    baseline: PresetSourcePreparation.Baseline?) -> Bool {
    guard let baseline, baseline.matches(settings), settings.allowsRestartingConfigurationChange,
      case .available = settings.thresholdProfileRead,
      settings.activeTestSelectionRead != .unavailable,
      settings.inputRules.thresholdSource != nil,
      accepts(original), original == resolved,
      original.configuration.rules == settings.inputRules,
      configuration.rules == settings.inputRules,
      configuration.challengeID == original.configuration.challengeID,
      accepts(.init(configuration: configuration, customText: original.customText)) else { return false }
    guard appliesGlobalSettings, !settings.testModifiers.isEmpty else { return true }
    // Pinned setup persists clearing the previous Funbox, but its challenge
    // mode/difficulty/limits are nosave. Only this owned global delta is saved.
    var cleared = settings.snapshot
    cleared.testModifiers = []
    guard settings.clearChallengeModifiers(), settings.snapshot == cleared,
      case .available(let stored) = settings.thresholdProfileRead, stored == cleared else { return false }
    return true
  }
}
