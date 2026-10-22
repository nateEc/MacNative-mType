import Foundation

@MainActor
enum PresetSettingsApplication {
  /// Complete settings admission before the scene mutates selection state.
  /// Selection-only success neither writes preferences nor persists selection.
  static func commit(
    original: SavedTestPreset, resolved: SavedTestPreset,
    configuration: TestConfiguration, to settings: AppSettings,
    appliesGlobalSettings: Bool,
    expectedSourceState: PresetSourcePreparation.Baseline? = nil
  ) -> Bool {
    guard settings.allowsRestartingConfigurationChange else { return false }
    if let expectedSourceState, !expectedSourceState.matches(settings) { return false }
    let sourceContext =
      settings.hasThresholdProfile || PracticeThresholdSource.isPresent(in: original)
      || PracticeThresholdSource.isPresent(in: resolved)
    if sourceContext,
      original.configuration.challengeID != nil || resolved.configuration.challengeID != nil
        || configuration.challengeID != nil {
      return SourceChallengeAdmission.commit(original: original, resolved: resolved,
        configuration: configuration, to: settings, appliesGlobalSettings: appliesGlobalSettings,
        baseline: expectedSourceState)
    }
    if sourceContext {
      // Existing-source restoration/application only. Source adoption and
      // challenge overrides have separate migration owners.
      guard settings.thresholdConfiguration != nil,
        case .available = settings.thresholdProfileRead,
        settings.activeTestSelectionRead != .unavailable,
        original.configuration.challengeID == nil, resolved.configuration.challengeID == nil,
        configuration.challengeID == nil,
        SettingsJSONConfigurationPolicy.isValid(configuration)
      else { return false }
      if original.isPartial || resolved.isPartial {
        guard appliesGlobalSettings, let groups = original.settingGroups, !groups.isEmpty,
          resolved.settingGroups == groups, resolved.settingsSnapshot != nil
        else { return false }
      }
      for definition in [original, resolved] where PracticeThresholdSource.isPresent(in: definition)
      {
        guard (try? LocalPresetCodec.encode(definition)) != nil else { return false }
      }
      if appliesGlobalSettings {
        let ownsThresholds = !original.isPartial || original.settingGroups?.contains(.behavior) == true
        guard (!ownsThresholds || original.configuration.rules.thresholdSource != nil),
          resolved.configuration.rules.thresholdSource != nil,
          configuration == resolved.configuration,
          agreesWithSnapshot(resolved)
        else { return false }
      }
    }
    guard appliesGlobalSettings else { return true }
    let appliesTags = !original.isPartial || (original.settingGroups?.contains(.behavior) == true)
    let tags = appliesTags ? resolved.activeResultTags : nil
    let committed: Bool
    if var snapshot = resolved.settingsSnapshot {
      // The alias owns tags when present (including an explicit empty list).
      // Include it in the staged source write, never a second settings write.
      if let tags { snapshot.activeResultTags = tags }
      committed = settings.apply(snapshot, groups: sourceContext ? original.settingGroups : nil)
    } else {
      let appliedConfiguration = !original.isPartial
        && TypebarChallengeLibrary.challenge(id: configuration.challengeID) != nil
        ? ChallengeInputRulePolicy.applying(settings.inputRules, to: configuration) : configuration
      committed = settings.apply(appliedConfiguration, activeResultTags: tags)
    }
    return committed
  }

  /// Reject two different owners for the same applied rule. Captured presets
  /// retain requested funboxes in settings and effective funboxes in the test.
  static func agreesWithSnapshot(_ preset: SavedTestPreset) -> Bool {
    guard let snapshot = preset.settingsSnapshot else { return true }
    let configuration = preset.configuration
    var rules = InputRules(
      strictSpace: snapshot.strictSpace,
      stopOnError: snapshot.stopOnError, stopOnErrorMode: snapshot.stopOnErrorMode,
      deleteOnError: snapshot.deleteOnError, deleteOnErrorMode: snapshot.deleteOnErrorMode,
      hideExtraLetters: snapshot.hideExtraLetters, blindMode: snapshot.blindMode,
      quickEnd: snapshot.quickEnd, freedomMode: snapshot.freedomMode,
      confidenceMode: snapshot.confidenceMode, oppositeShiftMode: snapshot.oppositeShiftMode,
      codeUnindentOnBackspace: snapshot.codeUnindentOnBackspace,
      minimumAccuracy: snapshot.minimumAccuracy, minimumWpm: snapshot.minimumWpm,
      minimumWordBurstWpm: snapshot.minimumWordBurstWpm,
      minimumWordBurstMode: snapshot.minimumWordBurstMode)
    rules.thresholdSource = snapshot.thresholdSource
    return configuration.rules == rules && configuration.difficulty == snapshot.difficulty
      && configuration.englishVariant == snapshot.englishVariant
      && configuration == configuration.with(modifiers: EffectiveTestModifierPolicy.modifiers(
        requested: snapshot.testModifiers, language: configuration.language, mode: configuration.mode,
        mixedLanguageComponents: configuration.mixedLanguageComponents,
        automaticallyEnabledArabic: snapshot.prefersArabicLazyInput))
  }
}

/// One value-only projection for scene construction and preset admission.
enum EffectiveTestModifierPolicy {
  static func modifiers(requested: [TestModifier], language: TypingLanguage, mode: TestMode,
    mixedLanguageComponents: [TypingLanguage], automaticallyEnabledArabic: Bool) -> [TestModifier] {
    let languageCompatible = language == .mixedLanguages
      ? TestModifierPolicy.modifiersCompatibleWithPolyglot(requested) : requested
    let lazy = ArabicLazyInputPolicy.effectiveModifiers(languageCompatible, language: language, mode: mode,
      mixedLanguageComponents: mixedLanguageComponents, automaticallyEnabled: automaticallyEnabledArabic)
    return JoiningScriptFunboxPolicy.effectiveModifiers(
      TestModifierPolicy.modifiersCompatibleWithMode(lazy, mode: mode),
      language: language, mixedLanguageComponents: mixedLanguageComponents)
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
