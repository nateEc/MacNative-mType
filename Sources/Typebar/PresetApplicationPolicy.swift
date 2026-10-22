import Foundation

/// Builds a resolved preset before the UI mutates observable state. Keeping
/// this pure makes partial presets auditable and prevents an unchecked group
/// from changing an unrelated setting.
enum PresetApplicationPolicy {
  static func applying(current: SavedTestPreset, preset: SavedTestPreset) -> SavedTestPreset {
    guard let groups = preset.settingGroups else { return preset }
    guard !groups.isEmpty else { return current }

    let sourceConfiguration = preset.configuration
    let currentConfiguration = current.configuration
    let usesTest = groups.contains(.test)
    let usesBehavior = groups.contains(.behavior)
    let usesInput = groups.contains(.input)

    var rules = currentConfiguration.rules
    if usesBehavior {
      rules.blindMode = sourceConfiguration.rules.blindMode
      rules.minimumAccuracy = sourceConfiguration.rules.minimumAccuracy
      rules.minimumWpm = sourceConfiguration.rules.minimumWpm
      rules.minimumWordBurstWpm = sourceConfiguration.rules.minimumWordBurstWpm
      rules.minimumWordBurstMode = sourceConfiguration.rules.minimumWordBurstMode
      // Source memory and its effective projection have the same group owner.
      // Nil deliberately clears metadata when applying a legacy behavior group.
      rules.thresholdSource = sourceConfiguration.rules.thresholdSource
    }
    if usesInput {
      rules.strictSpace = sourceConfiguration.rules.strictSpace
      rules.stopOnError = sourceConfiguration.rules.stopOnError
      rules.stopOnErrorMode = sourceConfiguration.rules.stopOnErrorMode
      rules.deleteOnError = sourceConfiguration.rules.deleteOnError
      rules.deleteOnErrorMode = sourceConfiguration.rules.deleteOnErrorMode
      rules.hideExtraLetters = sourceConfiguration.rules.hideExtraLetters
      rules.quickEnd = sourceConfiguration.rules.quickEnd
      rules.freedomMode = sourceConfiguration.rules.freedomMode
      rules.confidenceMode = sourceConfiguration.rules.confidenceMode
      rules.oppositeShiftMode = sourceConfiguration.rules.oppositeShiftMode
      rules.codeUnindentOnBackspace = sourceConfiguration.rules.codeUnindentOnBackspace
    }

    var resolvedSnapshot: AppSettingsSnapshot?
    if var currentSnapshot = current.settingsSnapshot ?? preset.settingsSnapshot {
      if current.settingsSnapshot == nil {
        currentSnapshot.copyThresholds(from: currentConfiguration.rules)
      }
      var sourceSnapshot = preset.settingsSnapshot ?? currentSnapshot
      if preset.settingsSnapshot == nil {
        sourceSnapshot.copyPresetConfiguration(from: sourceConfiguration)
      }
      resolvedSnapshot = currentSnapshot.applyingPresetSettings(from: sourceSnapshot, groups: groups)
    }
    let testMetadata = usesTest ? sourceConfiguration : currentConfiguration
    var modifiers = usesBehavior ? sourceConfiguration.modifiers : currentConfiguration.modifiers
    if let snapshot = resolvedSnapshot, snapshot.thresholdSource != nil, testMetadata.challengeID == nil {
      modifiers = EffectiveTestModifierPolicy.modifiers(
        requested: snapshot.testModifiers, language: testMetadata.language, mode: testMetadata.mode,
        mixedLanguageComponents: testMetadata.mixedLanguageComponents,
        automaticallyEnabledArabic: snapshot.prefersArabicLazyInput)
    }
    // Feed the projection through the complete constructor: it also owns
    // infinite-limit filtering, Memory mode and forced content options.
    var configuration = TestConfiguration(
      mode: usesTest ? sourceConfiguration.mode : currentConfiguration.mode,
      duration: usesTest ? sourceConfiguration.duration : currentConfiguration.duration,
      wordLimit: usesTest ? sourceConfiguration.wordLimit : currentConfiguration.wordLimit,
      difficulty: usesBehavior ? sourceConfiguration.difficulty : currentConfiguration.difficulty,
      rules: rules,
      language: usesTest ? sourceConfiguration.language : currentConfiguration.language,
      englishVariant: usesBehavior
        ? sourceConfiguration.englishVariant : currentConfiguration.englishVariant,
      quoteLength: usesTest ? sourceConfiguration.quoteLength : currentConfiguration.quoteLength,
      quoteLengths: usesTest ? sourceConfiguration.quoteLengths : currentConfiguration.quoteLengths,
      quoteSelectionMode: usesTest
        ? sourceConfiguration.quoteSelectionMode : currentConfiguration.quoteSelectionMode,
      customTextCompletion: usesTest
        ? sourceConfiguration.customTextCompletion : currentConfiguration.customTextCompletion,
      customTextSectionLimit: usesTest
        ? sourceConfiguration.customTextSectionLimit : currentConfiguration.customTextSectionLimit,
      customTextOrdering: usesTest
        ? sourceConfiguration.customTextOrdering : currentConfiguration.customTextOrdering,
      customTextPipeDelimiter: testMetadata.customTextPipeDelimiter,
      mixedLanguageComponents: usesTest
        ? sourceConfiguration.mixedLanguageComponents : currentConfiguration.mixedLanguageComponents,
      polyglotBaseLanguage: testMetadata.polyglotBaseLanguage,
      modifiers: modifiers,
      contentOptions: usesTest ? sourceConfiguration.contentOptions : currentConfiguration.contentOptions,
      challengeID: usesTest ? sourceConfiguration.challengeID : currentConfiguration.challengeID)
    configuration.polyglotUsesPrimaryDirection = testMetadata.polyglotUsesPrimaryDirection
    configuration.polyglotUsesPrimaryCodeInput = testMetadata.polyglotUsesPrimaryCodeInput
    configuration.polyglotUsesPrimaryInputNormalization = testMetadata.polyglotUsesPrimaryInputNormalization
    configuration.dockerfileUsesLiteralIndentation = testMetadata.dockerfileUsesLiteralIndentation
    configuration.zenUsesSourceInputAdmission = testMetadata.zenUsesSourceInputAdmission

    var applied = current
    applied.configuration = configuration
    if usesTest {
      applied.quoteID = preset.quoteID
      applied.customText = preset.customText
    }
    if usesBehavior {
      applied.activeResultTags = preset.activeResultTags
        ?? preset.settingsSnapshot?.activeResultTags ?? []
    }
    applied.settingsSnapshot = resolvedSnapshot
    applied.settingGroups = preset.settingGroups
    return applied
  }
}

extension AppSettingsSnapshot {
  /// An old preset may have only input rules. Preserve that explicit projection
  /// and optional source rather than borrowing another preset's threshold state.
  fileprivate mutating func copyThresholds(from rules: InputRules) {
    minimumAccuracy = rules.minimumAccuracy
    minimumWpm = rules.minimumWpm
    minimumWordBurstWpm = rules.minimumWordBurstWpm
    minimumWordBurstMode = rules.minimumWordBurstMode
    thresholdSource = rules.thresholdSource
  }

  fileprivate mutating func copyPresetConfiguration(from configuration: TestConfiguration) {
    let rules = configuration.rules
    copyThresholds(from: rules)
    difficulty = configuration.difficulty
    englishVariant = configuration.englishVariant
    testModifiers = configuration.modifiers
    blindMode = rules.blindMode
    strictSpace = rules.strictSpace
    stopOnError = rules.stopOnError
    stopOnErrorMode = rules.stopOnErrorMode
    deleteOnError = rules.deleteOnError
    deleteOnErrorMode = rules.deleteOnErrorMode
    hideExtraLetters = rules.hideExtraLetters
    quickEnd = rules.quickEnd
    freedomMode = rules.freedomMode
    confidenceMode = rules.confidenceMode
    oppositeShiftMode = rules.oppositeShiftMode
    codeUnindentOnBackspace = rules.codeUnindentOnBackspace
  }

  func applyingPresetSettings(from source: Self, groups: Set<PresetSettingGroup>) -> Self {
    var result = self
    if groups.contains(.test) {
      result.favoriteQuoteIDs = source.favoriteQuoteIDs
      result.showWordBurstHeatmap = source.showWordBurstHeatmap
    }
    if groups.contains(.behavior) {
      result.difficulty = source.difficulty
      result.blindMode = source.blindMode
      result.publishCompletedResults = source.publishCompletedResults
      result.saveCompletedResults = source.saveCompletedResults
      result.quickRestartKey = source.quickRestartKey
      result.commandPaletteListMode = source.commandPaletteListMode
      result.englishVariant = source.englishVariant
      result.activeResultTags = source.activeResultTags
      result.repeatQuotes = source.repeatQuotes
      result.minimumAccuracy = source.minimumAccuracy
      result.minimumWpm = source.minimumWpm
      result.minimumWordBurstWpm = source.minimumWordBurstWpm
      result.minimumWordBurstMode = source.minimumWordBurstMode
      result.thresholdSource = source.thresholdSource
      result.alwaysShowWordsHistory = source.alwaysShowWordsHistory
      result.testModifiers = source.testModifiers
    }
    if groups.contains(.input) {
      result.strictSpace = source.strictSpace
      result.stopOnError = source.stopOnError
      result.stopOnErrorMode = source.stopOnErrorMode
      result.deleteOnError = source.deleteOnError
      result.deleteOnErrorMode = source.deleteOnErrorMode
      result.hideExtraLetters = source.hideExtraLetters
      result.quickEnd = source.quickEnd
      result.freedomMode = source.freedomMode
      result.confidenceMode = source.confidenceMode
      result.oppositeShiftMode = source.oppositeShiftMode
      result.codeUnindentOnBackspace = source.codeUnindentOnBackspace
      result.typoIndicatorStyle = source.typoIndicatorStyle
      result.compositionDisplayStyle = source.compositionDisplayStyle
      result.prefersArabicLazyInput = source.prefersArabicLazyInput
      result.keyboardLayout = source.keyboardLayout
      result.keyboardInputLayout = source.keyboardInputLayout
      result.keyboardGuideLayoutSource = source.keyboardGuideLayoutSource
      result.customKeyboardLayouts = source.customKeyboardLayouts
      result.customKeyboardLayoutID = source.customKeyboardLayoutID
    }
    if groups.contains(.sound) {
      result.playErrorBeep = source.playErrorBeep
      result.playKeyclickSound = source.playKeyclickSound
      result.clickSoundStyle = source.clickSoundStyle
      result.errorSoundStyle = source.errorSoundStyle
      result.timeWarningOffset = source.timeWarningOffset
      result.timeWarningSoundStyle = source.timeWarningSoundStyle
      result.soundVolume = source.soundVolume
    }
    if groups.contains(.caret) {
      result.smoothCaretMotion = source.smoothCaretMotion
      result.caretStyle = source.caretStyle
      result.paceGuideMode = source.paceGuideMode
      result.paceGuideCustomWpm = source.paceGuideCustomWpm
      result.paceCaretStyle = source.paceCaretStyle
      result.repeatedPace = source.repeatedPace
    }
    if groups.contains(.appearance) {
      result.fontSize = source.fontSize
      result.practiceFont = source.practiceFont
      result.installedPracticeFontName = source.installedPracticeFontName
      result.showKeyboardGuide = source.showKeyboardGuide
      result.keyboardGuideMode = source.keyboardGuideMode
      result.keyboardGuideScale = source.keyboardGuideScale
      result.keyboardGuideLegendStyle = source.keyboardGuideLegendStyle
      result.keyboardGuideKeysMode = source.keyboardGuideKeysMode
      result.keyboardGuideStyle = source.keyboardGuideStyle
      result.practiceBackdrop = source.practiceBackdrop
      result.reducePracticeMotion = source.reducePracticeMotion
      result.animationFrameRate = source.animationFrameRate
      result.practiceLineWidth = source.practiceLineWidth
      result.customPracticeLineColumns = source.customPracticeLineColumns
      result.practiceTapeMode = source.practiceTapeMode
      result.practiceTapeMargin = source.practiceTapeMargin
      result.smoothPracticeLineScroll = source.smoothPracticeLineScroll
      result.showAllPracticeLines = source.showAllPracticeLines
      result.typingSpeedUnit = source.typingSpeedUnit
      result.alwaysShowDecimalPlaces = source.alwaysShowDecimalPlaces
      result.startGraphsAtZero = source.startGraphsAtZero
      result.typedCharacterEffect = source.typedCharacterEffect
      result.liveSpeedStyle = source.liveSpeedStyle
      result.liveAccuracyStyle = source.liveAccuracyStyle
      result.liveBurstStyle = source.liveBurstStyle
      result.liveProgressStyle = source.liveProgressStyle
      result.liveStatsColor = source.liveStatsColor
      result.liveStatsOpacity = source.liveStatsOpacity
      result.promptHighlightMode = source.promptHighlightMode
    }
    if groups.contains(.theme) {
      result.theme = source.theme
      result.customThemes = source.customThemes
      result.activeCustomThemeID = source.activeCustomThemeID
      result.lastCustomThemeID = source.lastCustomThemeID
      result.favoriteThemeIDs = source.favoriteThemeIDs
      result.followSystemTheme = source.followSystemTheme
      result.systemLightTheme = source.systemLightTheme
      result.systemDarkTheme = source.systemDarkTheme
      result.randomThemeOnRestart = source.randomThemeOnRestart
      result.randomThemeMode = source.randomThemeMode
      result.flipTestColors = source.flipTestColors
      result.colorfulMode = source.colorfulMode
      result.customBackgroundURL = source.customBackgroundURL
      result.customBackgroundFit = source.customBackgroundFit
      result.customBackgroundFilter = source.customBackgroundFilter
    }
    if groups.contains(.hideElements) {
      result.showKeyTips = source.showKeyTips
      result.showFocusWarning = source.showFocusWarning
      result.showCapsLockWarning = source.showCapsLockWarning
      result.showAverage = source.showAverage
      result.showPersonalBest = source.showPersonalBest
    }
    if groups.contains(.hidden) {
      result.showTypingCompanion = source.showTypingCompanion
      result.typingPowerMode = source.typingPowerMode
      result.resultPerformanceVisibility = source.resultPerformanceVisibility
      result.historyChartVisibility = source.historyChartVisibility
      result.globalHotkeyEnabled = source.globalHotkeyEnabled
      result.streakDayBoundaryOffsetHours = source.streakDayBoundaryOffsetHours
      result.hasSetStreakDayBoundary = source.hasSetStreakDayBoundary
    }
    return result
  }
}
