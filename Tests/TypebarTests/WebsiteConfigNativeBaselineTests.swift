import XCTest
@testable import Typebar

@MainActor final class WebsiteConfigNativeBaselineTests: XCTestCase {
  func testCompleteBaselineRetainsUnsharedPreferencesInsteadOfWebsiteDefaults() throws {
    var preferences = AppSettingsSnapshot()
    preferences.fontSize = 40
    preferences.caretStyle = .block
    preferences.soundVolume = 0.1
    preferences.showPersonalBest = true
    preferences.quickRestartKey = .enter
    var scope = WebsiteConfigSessionBuilder.Scope()
    scope.parameterMemory = .init(duration: 83, wordLimit: 147, customTextDuration: 31,
      customTextWordLimit: 27, customTextSectionLimit: 6)
    scope.customText = "cedar river"
    let capture = try WebsiteConfigNativeBaseline.capture(preferences: preferences, configuration: .words(17),
      scope: scope, layoutFluidLayouts: LayoutFluidPolicy.defaultLayouts, fontFamily: "Courier", pointsPerRem: 20)
    XCTAssertEqual(capture.runtime.count, 94)
    XCTAssertEqual(capture.runtime["fontSize"], .number(2))
    XCTAssertEqual(capture.runtime["time"], .number(83))
    XCTAssertEqual(capture.runtime["words"], .number(17))
    XCTAssertEqual(capture.runtime["soundVolume"], .number(0.1))
    XCTAssertEqual(capture.runtime["showPb"], .bool(true))
    XCTAssertEqual(capture.runtime["quickRestart"], .string("enter"))
    XCTAssertEqual(capture.nativePreferences, preferences)
    let draft = try capture.draft(pointsPerRem: 20)
    XCTAssertEqual(draft.presentation.applying(to: preferences), preferences)
    XCTAssertEqual(draft.behavior.applying(to: preferences), preferences)
    XCTAssertTrue(draft.projection.events.isEmpty)
    XCTAssertEqual(draft.settingsStoreValues, capture.runtime)
    XCTAssertEqual(try WebsiteConfigNativeStateCodec.decode(WebsiteConfigNativeStateCodec.encode(capture.runtime)), capture.runtime)
  }

  private func capture(_ preferences: AppSettingsSnapshot = .init(), configuration: TestConfiguration = .words(17),
    scope: WebsiteConfigSessionBuilder.Scope = .init(), font: String = "Courier") throws -> WebsiteConfigNativeBaseline.Capture {
    try WebsiteConfigNativeBaseline.capture(preferences: preferences, configuration: configuration, scope: scope,
      layoutFluidLayouts: LayoutFluidPolicy.defaultLayouts, fontFamily: font, pointsPerRem: 16)
  }

  func testCurrentConfigurationAndIndependentNativeTextOwnTheBaseline() throws {
    var preferences = AppSettingsSnapshot()
    preferences.difficulty = .normal
    preferences.englishVariant = .american
    var config = TestConfiguration.words(17)
    config.difficulty = .expert; config.englishVariant = .british
    config.rules = .init(strictSpace: true, minimumWpm: 42)
    var scope = WebsiteConfigSessionBuilder.Scope()
    scope.customText = "cedar river"
    scope.websiteCustomText = try .init(value: .object(["text": .array([.string("foreign cache")]),
      "mode": .string("random"), "limit": .object(["mode": .string("word"), "value": .number(99)]), "pipeDelimiter": .bool(true)]))
    let result = try capture(preferences, configuration: config, scope: scope)
    let draft = try result.draft(pointsPerRem: 16)
    XCTAssertEqual(draft.inputRules.difficulty, .expert)
    XCTAssertTrue(draft.inputRules.rules.strictSpace)
    XCTAssertEqual(draft.inputRules.rules.minimumWpm, 42)
    XCTAssertEqual(draft.behavior.englishVariant, .british)
    XCTAssertEqual(result.scope.websiteCustomText?.text, [.string("cedar"), .string("river")])
    XCTAssertEqual(result.nativePreferences, preferences)
    XCTAssertEqual(scope.websiteCustomText?.limitValue, 99)
  }

  func testAllPresentationChoicesAndSoundIdentitiesRoundTripThroughExistingAdapters() throws {
    for style in TypingCaretStyle.allCases {
      var preferences = AppSettingsSnapshot(); preferences.caretStyle = style; preferences.paceCaretStyle = style
      let draft = try capture(preferences).draft(pointsPerRem: 16)
      XCTAssertEqual(draft.presentation.applying(to: preferences), preferences)
    }
    for highlight in PromptHighlightMode.allCases {
      var preferences = AppSettingsSnapshot(); preferences.promptHighlightMode = highlight
      XCTAssertEqual(try capture(preferences).draft(pointsPerRem: 16).presentation.promptHighlightMode, highlight)
    }
    for style in TypingErrorSoundStyle.allCases {
      var preferences = AppSettingsSnapshot(); preferences.playErrorBeep = true; preferences.errorSoundStyle = style
      XCTAssertEqual(try capture(preferences).draft(pointsPerRem: 16).behavior.errorSoundStyle, style)
    }
    for name in 1...26 {
      guard case .click(let style?) = SoundCommandCatalog.target(for: "sound.playSoundOnClick.\(name)") else { return XCTFail("Missing tone") }
      var preferences = AppSettingsSnapshot(); preferences.playKeyclickSound = true; preferences.clickSoundStyle = style
      let result = try capture(preferences)
      XCTAssertEqual(result.runtime["playSoundOnClick"], .string(String(name)))
      XCTAssertEqual(try result.draft(pointsPerRem: 16).behavior.clickSoundStyle, style)
    }
  }

  func testThresholdMemoriesAndEmptyTextRemainIndependentOfTheirDisabledModes() throws {
    let raw = try PracticeThresholdConfiguration(websiteMinimumWpmMode: .off, speed: .infinity,
      accuracyMode: .off, accuracy: 73, burstMode: .off, burst: .infinity)
    var config = TestConfiguration.words(17)
    config.rules = PracticeThresholdSource(configuration: raw).applying(to: .init())
    let result = try capture(configuration: config)
    XCTAssertEqual(result.runtime["minWpm"], .string("off"))
    XCTAssertEqual(result.runtime["minWpmCustomSpeed"], .number(.infinity))
    XCTAssertEqual(result.runtime["minAccCustom"], .number(73))
    XCTAssertEqual(result.runtime["minBurstCustomSpeed"], .number(.infinity))
    XCTAssertEqual(result.scope.websiteCustomText?.text, [.string("")])
    XCTAssertEqual(result.scope.websiteCustomText?.limitValue, 0)
    XCTAssertEqual(try result.draft(pointsPerRem: 16).inputRules.rules.minimumWpm, 0)
  }

  func testUnrepresentableNativeValuesAreNotNormalizedIntoDefaults() throws {
    for field in ["theme", "fontFamily", "keymapLayout", "words", "time", "playSoundOnClick", "accountChart", "customText", "localQuoteFavorites"] {
      var preferences = AppSettingsSnapshot(), config = TestConfiguration.words(17)
      var scope = WebsiteConfigSessionBuilder.Scope(), font = "Courier"
      switch field {
      case "theme": preferences.theme = .grove
      case "fontFamily": font = "not a source font"
      case "keymapLayout": preferences.keyboardGuideLayoutSource = .systemInput
      case "words": config.wordLimit = Int.max
      case "time": config = .init(mode: .time, duration: 1.5, wordLimit: nil, difficulty: .normal, rules: .init())
      case "playSoundOnClick": preferences.playKeyclickSound = true; preferences.clickSoundStyle = .pulse
      case "accountChart": preferences.historyChartVisibility.speed = false; preferences.historyChartVisibility.accuracy = false
      case "localQuoteFavorites": config.quoteSelectionMode = .favorites
      default: scope.customTextRecoveryBlocked = true
      }
      XCTAssertThrowsError(try capture(preferences, configuration: config, scope: scope, font: font), field)
    }
  }

  func testExactCustomColorsAndFavoritesKeepTheirMeaningWhileLossyColorsRefuse() throws {
    var preferences = AppSettingsSnapshot()
    let defaults = try WebsiteConfigNativeProfile.defaultDocument().values
    let custom = try WebsiteConfigNativeThemes(runtime: defaults).makeCustomTheme(id: UUID(), name: "Owned")
    preferences.customThemes = [custom]; preferences.activeCustomThemeID = custom.id
    preferences.favoriteThemeIDs = [ThemeFavoritePolicy.builtInID(for: .paper)]
    let result = try capture(preferences)
    XCTAssertEqual(result.runtime["customTheme"], .bool(true))
    XCTAssertEqual(result.runtime["favThemes"], .array([.string("paper")]))
    XCTAssertEqual(try result.draft(pointsPerRem: 16).themes.customColors[0], custom.background)
    preferences.customThemes[0].background.red = 0.5
    XCTAssertThrowsError(try capture(preferences))
    preferences.customThemes = [custom]
    preferences.favoriteThemeIDs = [ThemeFavoritePolicy.customID(for: custom.id)]
    XCTAssertThrowsError(try capture(preferences))
  }

  func testKeyboardGuideCaptureUsesActualVisibilityAndDoesNotInventASystemDiagram() throws {
    var preferences = AppSettingsSnapshot()
    preferences.keyboardGuideMode = .react
    preferences.showKeyboardGuide = false
    let hidden = try capture(preferences)
    XCTAssertEqual(hidden.runtime["keymapMode"], .string("off"))
    XCTAssertEqual(hidden.nativePreferences.keyboardGuideMode, .react)
    preferences.showKeyboardGuide = true
    XCTAssertThrowsError(try capture(preferences))
    preferences.keyboardGuideLayoutSource = .builtIn
    XCTAssertEqual(try capture(preferences).runtime["keymapMode"], .string("react"))
  }

  func testCaptureDoesNotWritePreferencesSelectionsOrIndependentText() throws {
    let suite = "typebar.native-baseline.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults, feedbackSound: .init(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
    settings.fontSize = 40
    let snapshot = settings.snapshot
    let before = NSDictionary(dictionary: defaults.persistentDomain(forName: suite) ?? [:])
    let sourceGeneration = settings.websiteCustomTextStateGeneration
    let result = try WebsiteConfigNativeBaseline.capture(preferences: snapshot, configuration: .words(17), scope: .init(),
      layoutFluidLayouts: settings.layoutFluidLayouts, fontFamily: "Courier", pointsPerRem: 16)
    XCTAssertEqual(result.nativePreferences, snapshot)
    XCTAssertEqual(NSDictionary(dictionary: defaults.persistentDomain(forName: suite) ?? [:]), before)
    XCTAssertEqual(settings.websiteCustomTextStateGeneration, sourceGeneration)
    XCTAssertNil(settings.preferenceConfigurationSaves.captureLease())
  }

  func testActualSystemFacesAndFractionalCustomTimeSurvivePreparation() throws {
    for design in PracticeFont.allCases {
      var preferences = AppSettingsSnapshot(); preferences.practiceFont = design
      let native = design.nsFont(size: preferences.fontSize, resolver: .init(localFont: { _ in nil }))
      let family = NativeSystemPracticeFont.identifier(for: design)
      XCTAssertEqual(NativeSystemPracticeFont.identifier(matching: native), family)
      let result = try capture(preferences, font: family)
      let prepared = try WebsiteConfigFontResource.prepare(typography: result.draft(pointsPerRem: 16).keyboardTypography,
        language: .english, local: .absent)
      XCTAssertEqual(prepared.primary.font.fontName, native.fontName, design.rawValue)
      XCTAssertEqual(prepared.primary.font.pointSize, native.pointSize)
      XCTAssertEqual(prepared.primary.font.fontDescriptor.symbolicTraits, native.fontDescriptor.symbolicTraits)
      XCTAssertEqual(prepared.primary.font.fontDescriptor.object(forKey: .traits) as? NSDictionary,
        native.fontDescriptor.object(forKey: .traits) as? NSDictionary)
    }
    XCTAssertNil(NativeSystemPracticeFont.resolve("TypebarNativeSystem_missing", size: 28))
    XCTAssertNil(NativeSystemPracticeFont.resolve("Roboto_Mono", size: 28))
    var scope = WebsiteConfigSessionBuilder.Scope(); scope.customText = "cedar river"
    let config = TestConfiguration(mode: .custom, duration: 1.5, wordLimit: nil, difficulty: .normal,
      rules: .init(), customTextCompletion: .time)
    let result = try capture(configuration: config, scope: scope)
    XCTAssertEqual(result.scope.websiteCustomText?.limitMode, "time")
    XCTAssertEqual(result.scope.websiteCustomText?.limitValue, 1.5)
    XCTAssertEqual(try WebsiteConfigSessionBuilder.configuration(draft: result.draft(pointsPerRem: 16), scope: result.scope).duration, 1.5)
  }
}
