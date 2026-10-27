import Foundation

/// Read-only input for the ordinary page's whole-profile receiver.
/// This does not establish a profile owner, persist a document or restart.
@MainActor enum WebsiteConfigNativeBaseline {
  enum Failure: Error, Equatable, LocalizedError {
    case unrepresentable(String), incomplete
    var errorDescription: String? {
      switch self {
      case .unrepresentable(let field): "当前“\(field)”设置还不能无损迁移到完整配置。"
      case .incomplete: "当前配置尚不能完整迁移，请保留原设置。"
      }
    }
  }
  @MainActor struct Capture {
    let runtime: [String: WebsiteConfigValue]
    let configuration: TestConfiguration
    let nativePreferences: AppSettingsSnapshot
    let scope: WebsiteConfigSessionBuilder.Scope
    let lazyMemory: WebsiteConfigLazyModeMemory
    func draft(pointsPerRem: Double) throws -> WebsiteConfigNativeDraft {
      guard let custom = scope.websiteCustomText else { throw Failure.incomplete }
      return try .init(received: .init(state: .init(runtime: runtime, settingsStore: runtime,
        custom: custom, active: false, lazyMemory: lazyMemory)), pointsPerRem: pointsPerRem)
    }
  }
  static func capture(preferences: AppSettingsSnapshot, configuration: TestConfiguration,
    scope: WebsiteConfigSessionBuilder.Scope, layoutFluidLayouts: [KeyboardLayout],
    fontFamily: String, pointsPerRem: Double) throws -> Capture {
    guard pointsPerRem.isFinite, pointsPerRem > 0 else { throw Failure.unrepresentable("fontSize") }
    guard configuration.challengeID == nil else { throw Failure.unrepresentable("challenge") }
    // The source's -3 selection addresses an authenticated collection. Native
    // local favorites have no such identity; keep their native receiver until
    // that collection has an explicit persistent owner in the whole profile.
    guard configuration.quoteSelectionMode != .favorites else { throw Failure.unrepresentable("localQuoteFavorites") }
    var nativeScope = try currentNativeScope(configuration: configuration, preserving: scope)
    let selection = WebsiteTestSettingsShare.nativeSnapshot(configuration: configuration, scope: nativeScope)
    guard !selection.unavailableFields.contains(.language), let language = selection.runtime["language"] else {
      throw Failure.unrepresentable("language")
    }
    guard !selection.unavailableFields.contains(.funbox), let boxes = selection.runtime["funbox"] else {
      throw Failure.unrepresentable("funbox")
    }
    let rules = configuration.rules
    let threshold: PracticeThresholdSource
    if let source = rules.thresholdSource {
      guard source.configuration.isValidWebsite, source.matches(rules) else { throw Failure.unrepresentable("thresholds") }
      threshold = source
    } else {
      threshold = try LegacyThresholdProjection.source(for: rules,
        preserving: preferences.thresholdSource ?? .init(configuration: .init()))
    }
    let raw = threshold.configuration
    let guideMode: KeyboardGuideMode = preferences.showKeyboardGuide ? preferences.keyboardGuideMode : .off
    let guideLayout: String
    switch preferences.keyboardGuideLayoutSource {
    case .builtIn: guideLayout = try layout(preferences.keyboardLayout, field: "keymapLayout")
    case .websiteEmulation: guideLayout = "overrideSync"
    case .inputEmulation:
      // Visible native system-source rows are not the website's physical US
      // overrideSync diagram. Keep that distinction instead of changing it.
      guard guideMode == .off || preferences.keyboardInputLayout != .system else {
        throw Failure.unrepresentable("keymapLayout")
      }
      guideLayout = "overrideSync"
    case .systemInput, .custom: throw Failure.unrepresentable("keymapLayout")
    }
    let inputLayout: String
    if preferences.keyboardInputLayout == .system { inputLayout = "default" }
    else if let value = preferences.keyboardInputLayout.emulatedLayout { inputLayout = try layout(value, field: "layout") }
    else { throw Failure.unrepresentable("layout") }
    let columns: Double
    switch preferences.practiceLineWidth {
    case .fluid: columns = 0
    case .compact: columns = 42
    case .standard: columns = 60
    case .wide: columns = 80
    case .custom:
      guard PracticeLineWidth.customColumnRange.contains(preferences.customPracticeLineColumns) else {
        throw Failure.unrepresentable("maxLineWidth")
      }
      columns = Double(preferences.customPracticeLineColumns)
    }
    let customID = preferences.activeCustomThemeID ?? preferences.lastCustomThemeID
    let custom = customID.flatMap { id in preferences.customThemes.first { $0.id == id } }
    guard customID == nil || custom != nil else { throw Failure.unrepresentable("customTheme") }
    if preferences.activeCustomThemeID != nil, custom?.fadedText != custom?.panel {
      throw Failure.unrepresentable("customThemeColors")
    }
    let colors: WebsiteConfigValue
    if let custom {
      colors = .array(try [custom.background, custom.accent, custom.caret, custom.secondaryText, custom.panel,
        custom.text, custom.error, custom.extraInput, custom.colorfulError, custom.colorfulExtraInput].map { .string(try hex($0)) })
    } else {
      // Native storage has no inactive ten-color memory when no custom theme
      // exists. Use the independently authored initial colors only there.
      colors = try WebsiteConfigNativeProfile.defaultDocument().values["customThemeColors"]!
    }
    let quoteGroups: [Int]
    switch configuration.quoteSelectionMode {
    case .favorites: quoteGroups = [-3]
    case .search: quoteGroups = [-2]
    case .lengths:
      let lengths = configuration.effectiveQuoteLengths
      quoteGroups = lengths.contains(.all) ? [0, 1, 2, 3]
        : QuoteLength.allCases.compactMap { lengths.contains($0) ? $0.compatibilityValue.flatMap(Int.init) : nil }
    }
    let customText: WebsiteCustomTextSettings
    if let value = WebsiteTestSettingsShare.customText(in: nativeScope) { customText = try .init(value: value) }
    else {
      // Preserve an empty native buffer, rather than inventing sample words.
      var empty = nativeScope; empty.preparedCustomSections = [""]
      guard var value = WebsiteTestSettingsShare.customText(in: empty)?.importFields else { throw Failure.unrepresentable("customText") }
      if empty.customCompletion == .finish {
        value["limit"] = .object(["mode": .string(empty.customPipeDelimiter == true ? "section" : "word"), "value": .number(0)])
      }
      customText = try .init(value: .object(value))
    }
    nativeScope.websiteCustomText = customText
    guard WebsiteCustomTextStateStore.encodeDocument(customText) != nil else { throw Failure.unrepresentable("customText") }
    var values: [String: WebsiteConfigValue] = [
      "mode": .string(configuration.mode.rawValue), "language": language,
      "words": .number(configuration.mode == .words ? try exact(configuration.wordLimit ?? 0, field: "words") : Double(scope.parameterMemory.wordLimit)),
      "time": .number(configuration.mode == .time ? configuration.duration ?? 0 : Double(scope.parameterMemory.duration)),
      "punctuation": .bool(configuration.contentOptions.includePunctuation), "numbers": .bool(configuration.contentOptions.includeNumbers),
      "quoteLength": .array(quoteGroups.map { .number(Double($0)) }),
      "difficulty": .string(configuration.difficulty.rawValue), "strictSpace": .bool(rules.strictSpace),
      "stopOnError": .string(rules.stopOnErrorMode.rawValue),
      "deleteOnError": .string(deletion(rules.deleteOnErrorMode)),
      "hideExtraLetters": .bool(rules.hideExtraLetters), "blindMode": .bool(rules.blindMode),
      "quickEnd": .bool(rules.quickEnd), "freedomMode": .bool(rules.freedomMode),
      "confidenceMode": .string(rules.confidenceMode == .maximum ? "max" : rules.confidenceMode.rawValue),
      "oppositeShiftMode": .string(rules.oppositeShiftMode.rawValue), "codeUnindentOnBackspace": .bool(rules.codeUnindentOnBackspace),
      "minWpm": .string(raw.minimumWpmMode.rawValue), "minWpmCustomSpeed": .number(raw.minimumWpmCustomValue),
      "minAcc": .string(raw.minimumAccuracyMode.rawValue), "minAccCustom": .number(raw.minimumAccuracyCustomValue),
      "minBurst": .string(raw.minimumWordBurstMode.rawValue), "minBurstCustomSpeed": .number(raw.minimumWordBurstCustomValue),
      "funbox": boxes, "lazyMode": .bool(configuration.modifiers.contains(.lazyLatin)),
      "customLayoutfluid": .array(try layoutFluidLayouts.map { .string(try layout($0, field: "customLayoutfluid")) }),
      "customPolyglot": .array(try configuration.mixedLanguageComponents.map {
        guard let name = WebsiteLanguageIdentity.name(for: $0) else { throw Failure.unrepresentable("customPolyglot") }
        return .string(name)
      }),
      "layout": .string(inputLayout), "keymapMode": .string(guideMode.rawValue), "keymapLayout": .string(guideLayout),
      "keymapStyle": .string(preferences.keyboardGuideStyle.rawValue), "keymapLegendStyle": .string(preferences.keyboardGuideLegendStyle.rawValue),
      "keymapKeys": .string(preferences.keyboardGuideKeysMode.rawValue), "keymapSize": .number(preferences.keyboardGuideScale),
      "fontFamily": .string(fontFamily), "fontSize": .number(preferences.fontSize / pointsPerRem), "maxLineWidth": .number(columns),
      "theme": .string(preferences.theme.rawValue), "themeLight": .string(preferences.systemLightTheme.rawValue),
      "themeDark": .string(preferences.systemDarkTheme.rawValue), "autoSwitchTheme": .bool(preferences.followSystemTheme),
      "customTheme": .bool(preferences.activeCustomThemeID != nil), "customThemeColors": colors,
      "favThemes": .array(try preferences.favoriteThemeIDs.map { id in
        guard id.hasPrefix("builtin:"), let theme = AppTheme(rawValue: String(id.dropFirst(8))) else { throw Failure.unrepresentable("favThemes") }
        return .string(theme.rawValue)
      }),
      "randomTheme": .string((preferences.randomThemeMode == .off && preferences.randomThemeOnRestart ? RandomThemeMode.on : preferences.randomThemeMode).rawValue),
      "quickRestart": .string(preferences.quickRestartKey == .escape ? "esc" : preferences.quickRestartKey.rawValue),
      "singleListCommandLine": .string(preferences.commandPaletteListMode == .grouped ? "manual" : "on"),
      "britishEnglish": .bool(configuration.englishVariant == .british), "resultSaving": .bool(preferences.saveCompletedResults),
      "repeatQuotes": .string(preferences.repeatQuotes ? "typing" : "off"),
      "playSoundOnClick": .string(try sound(preferences.playKeyclickSound ? .click(preferences.clickSoundStyle) : .click(nil), field: "playSoundOnClick")),
      "playSoundOnError": .string(try sound(preferences.playErrorBeep ? .error(preferences.errorSoundStyle) : .error(nil), field: "playSoundOnError")),
      "playTimeWarning": .string(preferences.timeWarningOffset == .off ? "off" : String(preferences.timeWarningOffset.rawValue)),
      "soundVolume": .number(preferences.soundVolume), "paceCaret": .string(try pace(preferences.paceGuideMode)),
      "paceCaretCustomSpeed": .number(preferences.paceGuideCustomWpm), "repeatedPace": .bool(preferences.repeatedPace),
      "accountChart": .array([preferences.historyChartVisibility.speed, preferences.historyChartVisibility.accuracy,
        preferences.historyChartVisibility.average10, preferences.historyChartVisibility.average100].map { .string($0 ? "on" : "off") }),
      "ads": .string("off"), "customBackground": .string(preferences.customBackgroundURL),
      "customBackgroundSize": .string(preferences.customBackgroundFit.rawValue),
      "customBackgroundFilter": .array([preferences.customBackgroundFilter.blur, preferences.customBackgroundFilter.brightness,
        preferences.customBackgroundFilter.saturation, preferences.customBackgroundFilter.opacity].map(WebsiteConfigValue.number)),
    ]
    let presentation: [String: WebsiteConfigValue] = [
      "smoothCaret": .string(preferences.smoothCaretMotion.rawValue), "caretStyle": .string(preferences.caretStyle.compatibilityValue),
      "paceCaretStyle": .string(preferences.paceCaretStyle.compatibilityValue), "timerStyle": .string(preferences.liveProgressStyle.rawValue),
      "liveSpeedStyle": .string(preferences.liveSpeedStyle.rawValue), "liveAccStyle": .string(preferences.liveAccuracyStyle.rawValue),
      "liveBurstStyle": .string(preferences.liveBurstStyle.rawValue), "timerColor": .string(preferences.liveStatsColor.compatibilityValue),
      "timerOpacity": .string(WebsiteNumberText.decimal(preferences.liveStatsOpacity.rawValue)),
      "showAverage": .string(preferences.showAverage == .accuracy ? "acc" : preferences.showAverage.rawValue),
      "highlightMode": .string(highlight(preferences.promptHighlightMode)), "typedEffect": .string(preferences.typedCharacterEffect.rawValue),
      "typingSpeedUnit": .string(preferences.typingSpeedUnit.rawValue), "monkeyPowerLevel": .string(preferences.typingPowerMode.compatibilityValue),
      "indicateTypos": .string(preferences.typoIndicatorStyle.rawValue), "compositionDisplay": .string(preferences.compositionDisplayStyle.rawValue),
      "showKeyTips": .bool(preferences.showKeyTips), "alwaysShowDecimalPlaces": .bool(preferences.alwaysShowDecimalPlaces),
      "alwaysShowWordsHistory": .bool(preferences.alwaysShowWordsHistory), "burstHeatmap": .bool(preferences.showWordBurstHeatmap),
      "startGraphsAtZero": .bool(preferences.startGraphsAtZero), "showOutOfFocusWarning": .bool(preferences.showFocusWarning),
      "capsLockWarning": .bool(preferences.showCapsLockWarning), "showPb": .bool(preferences.showPersonalBest),
      "flipTestColors": .bool(preferences.flipTestColors), "colorfulMode": .bool(preferences.colorfulMode), "monkey": .bool(preferences.showTypingCompanion),
      "smoothLineScroll": .bool(preferences.smoothPracticeLineScroll), "showAllLines": .bool(preferences.showAllPracticeLines),
      "tapeMode": .string(preferences.practiceTapeMode.rawValue), "tapeMargin": .number(preferences.practiceTapeMargin * 100),
    ]
    guard Set(values.keys).isDisjoint(with: presentation.keys) else { throw Failure.incomplete }
    values.merge(presentation) { _, new in new }
    let schema = WebsiteConfigSchema(catalogs: WebsiteConfigNativeProfile.catalogs)
    guard Set(values.keys) == schema.keys else { throw Failure.incomplete }
    for key in values.keys.sorted() where !schema.accepts(values[key]!, for: key) { throw Failure.unrepresentable(key) }
    let result = Capture(runtime: values, configuration: configuration, nativePreferences: preferences, scope: nativeScope,
      lazyMemory: .init(remember: false, prefersArabic: preferences.prefersArabicLazyInput))
    let draft: WebsiteConfigNativeDraft
    do { draft = try result.draft(pointsPerRem: pointsPerRem) }
    catch { throw Failure.unrepresentable("configuration") }
    // Ordinary native time can contain fractions, but the whole-profile
    // builder currently consumes integral time. Never silently truncate it.
    if configuration.mode == .time, Double(draft.testParameters.duration) != (configuration.duration ?? 0) {
      throw Failure.unrepresentable("time")
    }
    return result
  }

  static func currentNativeScope(configuration: TestConfiguration,
    preserving scope: WebsiteConfigSessionBuilder.Scope) throws -> WebsiteConfigSessionBuilder.Scope {
    var result = scope
    // A global website text cache is not the ordinary page's editor buffer.
    result.websiteCustomText = nil
    guard !result.customTextRecoveryBlocked else { throw Failure.unrepresentable("customText") }
    for value in [scope.parameterMemory.duration, scope.parameterMemory.wordLimit, scope.parameterMemory.customTextDuration,
      scope.parameterMemory.customTextWordLimit, scope.parameterMemory.customTextSectionLimit] { _ = try exact(value, field: "parameterMemory") }
    if configuration.mode == .custom {
      result.customCompletion = configuration.customTextCompletion; result.customOrdering = configuration.customTextOrdering
      result.customPipeDelimiter = configuration.customTextPipeDelimiter
      let words = configuration.customTextCompletion == .words ? configuration.wordLimit ?? 0 : scope.parameterMemory.customTextWordLimit
      let sections = configuration.customTextCompletion == .sections ? configuration.customTextSectionLimit ?? 0 : scope.parameterMemory.customTextSectionLimit
      _ = try exact(words, field: "customText"); _ = try exact(sections, field: "customText")
      let m = scope.parameterMemory
      result.parameterMemory = .init(duration: m.duration, wordLimit: m.wordLimit, customTextDuration: m.customTextDuration,
        customTextWordLimit: words, customTextSectionLimit: sections)
      if configuration.customTextCompletion == .time { result.customDurationOverride = configuration.duration ?? 0 }
    }
    return result
  }

  static func sameNativeInput(_ capture: Capture, as scope: WebsiteConfigSessionBuilder.Scope) throws -> Bool {
    guard capture.scope.parameterMemory.duration == scope.parameterMemory.duration,
      capture.scope.parameterMemory.wordLimit == scope.parameterMemory.wordLimit,
      capture.scope.selectedQuoteID == scope.selectedQuoteID else { return false }
    let a = WebsiteTestSettingsShare.nativeSnapshot(configuration: capture.configuration, scope: capture.scope).customText
    let b = WebsiteTestSettingsShare.nativeSnapshot(configuration: capture.configuration, scope: scope).customText
    guard let a, let b else { return a == nil && b == nil }
    let lhs = try WebsiteCustomTextSettings(value: a), rhs = try WebsiteCustomTextSettings(value: b)
    return lhs.mode == rhs.mode && lhs.limitMode == rhs.limitMode && lhs.limitValue.bitPattern == rhs.limitValue.bitPattern
      && lhs.pipeDelimiter == rhs.pipeDelimiter && lhs.text.count == rhs.text.count
      && zip(lhs.text, rhs.text).allSatisfy { $0.stringUnits == $1.stringUnits }
  }

  private static func exact(_ value: Int, field: String) throws -> Double {
    guard let restored = Int(exactly: Double(value)), restored == value else { throw Failure.unrepresentable(field) }
    return Double(value)
  }
  private static func layout(_ value: KeyboardLayout, field: String) throws -> String {
    guard let name = OfficialLayoutCommandCatalog.name(for: value) else { throw Failure.unrepresentable(field) }
    return name
  }
  private static func deletion(_ value: DeleteOnErrorMode) -> String {
    switch value { case .letterHard: "letter_hard"; case .wordHard: "word_hard"; default: value.rawValue }
  }
  private static func highlight(_ value: PromptHighlightMode) -> String {
    switch value { case .nextWord: "next_word"; case .nextTwoWords: "next_two_words"; case .nextThreeWords: "next_three_words"; default: value.rawValue }
  }
  private static func pace(_ value: PaceGuideMode) throws -> String {
    switch value {
    case .off: "off"
    case .custom: "custom"
    case .personalBest: "pb"
    case .accountTagPersonalBest: "tagPb"
    case .lastTest: "last"
    case .recentAverage: "average"
    case .dailyBest: "daily"
    default: throw Failure.unrepresentable("paceCaret")
    }
  }
  private static func sound(_ target: SoundCommandTarget, field: String) throws -> String {
    for name in ["off"] + (1...26).map(String.init) {
      if SoundCommandCatalog.target(for: "sound.\(field).\(name)") == target { return name }
    }
    throw Failure.unrepresentable(field)
  }
  private static func hex(_ color: ThemeColor) throws -> String {
    guard color.opacity == 1 else { throw Failure.unrepresentable("customThemeColors") }
    let parts = try [color.red, color.green, color.blue].map { part -> String in
      guard part.isFinite, (0...1).contains(part) else { throw Failure.unrepresentable("customThemeColors") }
      let byte = Int((part * 255).rounded())
      guard Double(byte) / 255 == part else { throw Failure.unrepresentable("customThemeColors") }
      return String(format: "%02x", byte)
    }
    return "#" + parts.joined()
  }
}
