import Foundation
import Observation
import SwiftUI

enum PracticeLineWidth: String, CaseIterable, Codable, Equatable, Identifiable {
  case compact
  case standard
  case wide
  case custom
  case fluid

  static let customColumnRange = 30...140

  var id: Self { self }

  func maximumWidth(fontSize: Double, customColumns: Int = 60) -> CGFloat? {
    let columns: Double
    switch self {
    case .compact: columns = 42
    case .standard: columns = 60
    case .wide: columns = 80
    case .custom: columns = Double(customColumns.clamped(to: Self.customColumnRange))
    case .fluid: return nil
    }
    return columns * fontSize * 0.62
  }

  var displayName: String {
    switch self {
    case .compact: "紧凑"
    case .standard: "标准"
    case .wide: "宽"
    case .custom: "自定义"
    case .fluid: "自适应"
    }
  }
}

enum PracticeTapeMode: String, CaseIterable, Codable, Equatable, Identifiable {
  case off
  case word
  case letter

  var id: Self { self }

  var displayName: String {
    switch self {
    case .off: "关闭"
    case .word: "按词"
    case .letter: "按字符"
    }
  }
}

/// A small set of native caret treatments for the active prompt character.
/// They use SwiftUI text attributes only and do not depend on copied CSS.
enum TypingCaretStyle: String, CaseIterable, Codable, Equatable, Identifiable {
  case bar
  case underline
  case block

  var id: Self { self }

  var displayName: String {
    switch self {
    case .bar: "条形"
    case .underline: "下划线"
    case .block: "块状"
    }
  }
}

/// Controls how an already-entered wrong character is shown without changing
/// the session's target text, accepted input, or metrics.
enum TypoIndicatorStyle: String, CaseIterable, Codable, Equatable, Identifiable {
  case off
  case replace
  case below
  case both

  var id: Self { self }

  var displayName: String {
    switch self {
    case .off: "关闭"
    case .replace: "替换为实际输入"
    case .below: "下方显示实际输入"
    case .both: "替换并在下方显示目标"
    }
  }

  var replacesTarget: Bool { self == .replace || self == .both }
  var showsHint: Bool { self == .below || self == .both }
}

/// Controls the presentation of marked text while a macOS input method is
/// composing. Marked text is never sent to the typing engine until AppKit
/// commits it through `insertText`.
enum CompositionDisplayStyle: String, CaseIterable, Codable, Equatable, Identifiable {
  case off
  case below
  case replace

  var id: Self { self }

  var displayName: String {
    switch self {
    case .off: "关闭"
    case .below: "下方显示"
    case .replace: "替换当前字符"
    }
  }
}

/// A presentation-only unit for live speed metrics. Results stay stored in
/// WPM so historical comparisons and server submissions remain canonical.
enum TypingSpeedUnit: String, CaseIterable, Codable, Equatable, Identifiable {
  case wpm
  case cpm
  case wps
  case cps
  case wph

  var id: Self { self }
  var displayName: String { rawValue.uppercased() }

  func converted(wpm: Int) -> Double {
    switch self {
    case .wpm: Double(wpm)
    case .cpm: Double(wpm * 5)
    case .wps: Double(wpm) / 60
    case .cps: Double(wpm * 5) / 60
    case .wph: Double(wpm * 60)
    }
  }

  func formatted(wpm: Int, alwaysShowDecimalPlaces: Bool = false) -> String {
    switch self {
    case .wpm:
      return alwaysShowDecimalPlaces ? String(format: "%.2f", Double(wpm)) : "\(wpm)"
    case .cpm:
      let cpm = wpm * 5
      return alwaysShowDecimalPlaces ? String(format: "%.2f", Double(cpm)) : "\(cpm)"
    case .wps:
      let wps = Double(wpm) / 60
      return alwaysShowDecimalPlaces ? String(format: "%.2f", wps) : String(format: "%.1f", wps)
    case .cps:
      let cps = Double(wpm * 5) / 60
      return alwaysShowDecimalPlaces ? String(format: "%.2f", cps) : String(format: "%.1f", cps)
    case .wph:
      let wph = wpm * 60
      return alwaysShowDecimalPlaces ? String(format: "%.2f", Double(wph)) : "\(wph)"
    }
  }
}

/// Chooses which local, current-setting average appears above the practice area.
/// It intentionally starts off so the main practice screen remains quiet by default.
enum AverageNoticeDisplay: String, CaseIterable, Codable, Equatable, Identifiable {
  case off
  case speed
  case accuracy
  case both

  var id: Self { self }

  var displayName: String {
    switch self {
    case .off: "关闭"
    case .speed: "速度"
    case .accuracy: "准确率"
    case .both: "速度和准确率"
    }
  }

  var showsSpeed: Bool { self == .speed || self == .both }
  var showsAccuracy: Bool { self == .accuracy || self == .both }
}

enum TypedCharacterEffect: String, CaseIterable, Codable, Equatable, Identifiable {
  case keep
  case hide
  case fade
  case dots

  var id: Self { self }

  var displayName: String {
    switch self {
    case .keep: "保留"
    case .hide: "隐藏已完成词"
    case .fade: "淡化已完成词"
    case .dots: "圆点代替已完成词"
    }
  }
}

enum LiveMetricStyle: String, CaseIterable, Codable, Equatable, Identifiable {
  case off
  case text
  case mini

  var id: Self { self }

  var displayName: String {
    switch self {
    case .off: "关闭"
    case .text: "文字"
    case .mini: "迷你"
    }
  }
}

enum LiveProgressStyle: String, CaseIterable, Codable, Equatable, Identifiable {
  case off
  case text
  case mini
  case bar

  var id: Self { self }

  var displayName: String {
    switch self {
    case .off: "关闭"
    case .text: "文字"
    case .mini: "迷你"
    case .bar: "进度条"
    }
  }

  var metricStyle: LiveMetricStyle {
    switch self {
    case .off: .off
    case .text: .text
    case .mini: .mini
    case .bar: .off
    }
  }
}

/// Native type treatments available in the practice surface. They map only to
/// macOS system designs, so no third-party font file is bundled or copied.
enum PracticeFont: String, CaseIterable, Codable, Equatable, Identifiable {
  case monospaced
  case rounded
  case serif
  case defaultSystem

  var id: Self { self }

  var displayName: String {
    switch self {
    case .monospaced: "等宽"
    case .rounded: "圆角"
    case .serif: "衬线"
    case .defaultSystem: "系统"
    }
  }

  func font(size: Double) -> Font {
    let design: Font.Design
    switch self {
    case .monospaced: design = .monospaced
    case .rounded: design = .rounded
    case .serif: design = .serif
    case .defaultSystem: design = .default
    }
    return .system(size: size, weight: .medium, design: design)
  }
}

enum ThemeFavoritePolicy {
  private static let builtInPrefix = "builtin:"
  private static let customPrefix = "custom:"

  static func builtInID(for theme: AppTheme) -> String {
    builtInPrefix + theme.rawValue
  }

  static func customID(for id: UUID) -> String {
    customPrefix + id.uuidString.lowercased()
  }

  static func normalized(_ identifiers: [String], customThemes: [CustomThemeDefinition]) -> [String]
  {
    let knownBuiltIns = Set(AppTheme.allCases.map(builtInID))
    let knownCustomThemes = Set(customThemes.map { customID(for: $0.id) })
    var seen = Set<String>()
    return identifiers.filter { identifier in
      guard knownBuiltIns.contains(identifier) || knownCustomThemes.contains(identifier),
        seen.insert(identifier).inserted
      else {
        return false
      }
      return true
    }
  }
}

struct AppSettingsSnapshot: Codable, Equatable {
  var difficulty: Difficulty = .normal
  var strictSpace = false
  var stopOnError = false
  var stopOnErrorMode: StopOnErrorMode = .off
  var deleteOnError = false
  var deleteOnErrorMode: DeleteOnErrorMode = .off
  var hideExtraLetters = false
  var blindMode = false
  var fontSize: Double = 28
  var practiceFont: PracticeFont = .monospaced
  var theme: AppTheme = .paper
  var publishCompletedResults = false
  var saveCompletedResults = true
  var customThemes: [CustomThemeDefinition] = []
  var activeCustomThemeID: UUID?
  var favoriteThemeIDs: [String] = []
  var showKeyboardGuide = true
  var keyboardLayout: KeyboardLayout = .ansiQwerty
  var quickEnd = false
  var quickRestartKey: QuickRestartKey = .escape
  var followSystemTheme = false
  var randomThemeOnRestart = false
  var practiceBackdrop: PracticeBackdropStyle = .solid
  var reducePracticeMotion = false
  var englishVariant: EnglishVariant = .american
  var favoriteQuoteIDs: [String] = []
  var repeatQuotes = false
  var freedomMode = false
  var confidenceMode: ConfidenceMode = .off
  var oppositeShiftMode: OppositeShiftMode = .off
  var codeUnindentOnBackspace = false
  var minimumAccuracy = 0
  var minimumWpm = 0
  var minimumWordBurstWpm = 0
  var minimumWordBurstMode: MinimumWordBurstMode = .off
  var practiceLineWidth: PracticeLineWidth = .standard
  var customPracticeLineColumns = 60
  var practiceTapeMode: PracticeTapeMode = .off
  var practiceTapeMargin: Double = 0.5
  var smoothPracticeLineScroll = true
  var showAllPracticeLines = false
  var caretStyle: TypingCaretStyle = .block
  var typoIndicatorStyle: TypoIndicatorStyle = .off
  var compositionDisplayStyle: CompositionDisplayStyle = .replace
  var typingSpeedUnit: TypingSpeedUnit = .wpm
  var alwaysShowDecimalPlaces = false
  var alwaysShowWordsHistory = false
  var showWordBurstHeatmap = false
  var resultPerformanceVisibility = ResultPerformanceVisibility()
  var startGraphsAtZero = true
  var showAverage: AverageNoticeDisplay = .off
  var showPersonalBest = false
  var typedCharacterEffect: TypedCharacterEffect = .keep
  var liveSpeedStyle: LiveMetricStyle = .text
  var liveAccuracyStyle: LiveMetricStyle = .text
  var liveBurstStyle: LiveMetricStyle = .text
  var liveProgressStyle: LiveProgressStyle = .text
  var testModifiers: [TestModifier] = []
  var showFocusWarning = true
  var showCapsLockWarning = true
  var playErrorBeep = false
  var playKeyclickSound = false
  var clickSoundStyle: TypingClickSoundStyle = .tink
  var errorSoundStyle: TypingErrorSoundStyle = .basso
  var timeWarningOffset: TimeWarningOffset = .off
  var timeWarningSoundStyle: TimeWarningSoundStyle = .glass
  var soundVolume: Double = 0.7
  var globalHotkeyEnabled = false
  var paceGuideMode: PaceGuideMode = .off
  var paceGuideCustomWpm = 60
  var paceCaretStyle: TypingCaretStyle = .bar
  var repeatedPace = false

  init(
    difficulty: Difficulty = .normal,
    strictSpace: Bool = false,
    stopOnError: Bool = false,
    stopOnErrorMode: StopOnErrorMode = .off,
    deleteOnError: Bool = false,
    deleteOnErrorMode: DeleteOnErrorMode = .off,
    hideExtraLetters: Bool = false,
    blindMode: Bool = false,
    fontSize: Double = 28,
    practiceFont: PracticeFont = .monospaced,
    theme: AppTheme = .paper,
    publishCompletedResults: Bool = false,
    saveCompletedResults: Bool = true,
    customThemes: [CustomThemeDefinition] = [],
    activeCustomThemeID: UUID? = nil,
    favoriteThemeIDs: [String] = [],
    showKeyboardGuide: Bool = true,
    keyboardLayout: KeyboardLayout = .ansiQwerty,
    quickEnd: Bool = false,
    quickRestartKey: QuickRestartKey = .escape,
    followSystemTheme: Bool = false,
    randomThemeOnRestart: Bool = false,
    practiceBackdrop: PracticeBackdropStyle = .solid,
    reducePracticeMotion: Bool = false,
    englishVariant: EnglishVariant = .american,
    favoriteQuoteIDs: [String] = [],
    repeatQuotes: Bool = false,
    freedomMode: Bool = false,
    confidenceMode: ConfidenceMode = .off,
    oppositeShiftMode: OppositeShiftMode = .off,
    codeUnindentOnBackspace: Bool = false,
    minimumAccuracy: Int = 0,
    minimumWpm: Int = 0,
    minimumWordBurstWpm: Int = 0,
    minimumWordBurstMode: MinimumWordBurstMode = .off,
    practiceLineWidth: PracticeLineWidth = .standard,
    customPracticeLineColumns: Int = 60,
    practiceTapeMode: PracticeTapeMode = .off,
    practiceTapeMargin: Double = 0.5,
    smoothPracticeLineScroll: Bool = true,
    showAllPracticeLines: Bool = false,
    caretStyle: TypingCaretStyle = .block,
    typoIndicatorStyle: TypoIndicatorStyle = .off,
    compositionDisplayStyle: CompositionDisplayStyle = .replace,
    typingSpeedUnit: TypingSpeedUnit = .wpm,
    alwaysShowDecimalPlaces: Bool = false,
    alwaysShowWordsHistory: Bool = false,
    showWordBurstHeatmap: Bool = false,
    resultPerformanceVisibility: ResultPerformanceVisibility = .init(),
    startGraphsAtZero: Bool = true,
    showAverage: AverageNoticeDisplay = .off,
    showPersonalBest: Bool = false,
    typedCharacterEffect: TypedCharacterEffect = .keep,
    liveSpeedStyle: LiveMetricStyle = .text,
    liveAccuracyStyle: LiveMetricStyle = .text,
    liveBurstStyle: LiveMetricStyle = .text,
    liveProgressStyle: LiveProgressStyle = .text,
    testModifiers: [TestModifier] = [],
    showFocusWarning: Bool = true,
    showCapsLockWarning: Bool = true,
    playErrorBeep: Bool = false,
    playKeyclickSound: Bool = false,
    clickSoundStyle: TypingClickSoundStyle = .tink,
    errorSoundStyle: TypingErrorSoundStyle = .basso,
    timeWarningOffset: TimeWarningOffset = .off,
    timeWarningSoundStyle: TimeWarningSoundStyle = .glass,
    soundVolume: Double = 0.7,
    globalHotkeyEnabled: Bool = false,
    paceGuideMode: PaceGuideMode = .off,
    paceGuideCustomWpm: Int = 60,
    paceCaretStyle: TypingCaretStyle = .bar,
    repeatedPace: Bool = false
  ) {
    self.difficulty = difficulty
    self.strictSpace = strictSpace
    self.stopOnErrorMode = stopOnErrorMode.isEnabled
      ? stopOnErrorMode : (stopOnError ? .letter : .off)
    self.deleteOnErrorMode = deleteOnErrorMode.isEnabled
      ? deleteOnErrorMode : (deleteOnError ? .letter : .off)
    if self.stopOnErrorMode.isEnabled { self.deleteOnErrorMode = .off }
    self.stopOnError = self.stopOnErrorMode.isEnabled
    self.deleteOnError = self.deleteOnErrorMode.isEnabled
    self.hideExtraLetters = hideExtraLetters
    self.blindMode = blindMode
    self.fontSize = fontSize
    self.practiceFont = practiceFont
    self.theme = theme
    self.publishCompletedResults = publishCompletedResults
    self.saveCompletedResults = saveCompletedResults
    self.customThemes = customThemes
    self.activeCustomThemeID = activeCustomThemeID
    self.favoriteThemeIDs = ThemeFavoritePolicy.normalized(
      favoriteThemeIDs, customThemes: customThemes)
    self.showKeyboardGuide = showKeyboardGuide
    self.keyboardLayout = keyboardLayout
    self.quickEnd = quickEnd
    self.quickRestartKey = quickRestartKey
    self.followSystemTheme = followSystemTheme
    self.randomThemeOnRestart = randomThemeOnRestart
    self.practiceBackdrop = practiceBackdrop
    self.reducePracticeMotion = reducePracticeMotion
    self.englishVariant = englishVariant
    self.favoriteQuoteIDs = favoriteQuoteIDs
    self.repeatQuotes = repeatQuotes
    self.freedomMode = freedomMode
    self.confidenceMode = confidenceMode
    self.oppositeShiftMode = oppositeShiftMode
    self.codeUnindentOnBackspace = codeUnindentOnBackspace
    self.minimumAccuracy = minimumAccuracy.clamped(to: 0...100)
    self.minimumWpm = minimumWpm.clamped(to: 0...300)
    self.minimumWordBurstWpm = minimumWordBurstWpm.clamped(to: 0...300)
    self.minimumWordBurstMode = minimumWordBurstMode == .off && self.minimumWordBurstWpm > 0
      ? .fixed : minimumWordBurstMode
    self.practiceLineWidth = practiceLineWidth
    self.customPracticeLineColumns = customPracticeLineColumns.clamped(
      to: PracticeLineWidth.customColumnRange)
    self.practiceTapeMode = practiceTapeMode
    self.practiceTapeMargin = practiceTapeMargin.clamped(to: 0...1)
    self.smoothPracticeLineScroll = smoothPracticeLineScroll
    self.showAllPracticeLines = showAllPracticeLines
    self.caretStyle = caretStyle
    self.typoIndicatorStyle = typoIndicatorStyle
    self.compositionDisplayStyle = compositionDisplayStyle
    self.typingSpeedUnit = typingSpeedUnit
    self.alwaysShowDecimalPlaces = alwaysShowDecimalPlaces
    self.alwaysShowWordsHistory = alwaysShowWordsHistory
    self.showWordBurstHeatmap = showWordBurstHeatmap
    self.resultPerformanceVisibility = resultPerformanceVisibility
    self.startGraphsAtZero = startGraphsAtZero
    self.showAverage = showAverage
    self.showPersonalBest = showPersonalBest
    self.typedCharacterEffect = typedCharacterEffect
    self.liveSpeedStyle = liveSpeedStyle
    self.liveAccuracyStyle = liveAccuracyStyle
    self.liveBurstStyle = liveBurstStyle
    self.liveProgressStyle = liveProgressStyle
    self.testModifiers = TestModifierPolicy.normalized(testModifiers)
    self.showFocusWarning = showFocusWarning
    self.showCapsLockWarning = showCapsLockWarning
    self.playErrorBeep = playErrorBeep
    self.playKeyclickSound = playKeyclickSound
    self.clickSoundStyle = clickSoundStyle
    self.errorSoundStyle = errorSoundStyle
    self.timeWarningOffset = timeWarningOffset
    self.timeWarningSoundStyle = timeWarningSoundStyle
    self.soundVolume = soundVolume.clamped(to: 0...1)
    self.globalHotkeyEnabled = globalHotkeyEnabled
    self.paceGuideMode = paceGuideMode
    self.paceGuideCustomWpm = paceGuideCustomWpm.clamped(
      to: PaceGuidePolicy.minimumWpm...PaceGuidePolicy.maximumWpm)
    self.paceCaretStyle = paceCaretStyle
    self.repeatedPace = repeatedPace
  }

  private enum CodingKeys: String, CodingKey {
    case difficulty, strictSpace, stopOnError, stopOnErrorMode, deleteOnError, deleteOnErrorMode,
      hideExtraLetters, blindMode, fontSize,
      practiceFont, theme, publishCompletedResults, saveCompletedResults, customThemes,
      activeCustomThemeID,
      favoriteThemeIDs, showKeyboardGuide, keyboardLayout, quickEnd, quickRestartKey, followSystemTheme,
      randomThemeOnRestart, practiceBackdrop, reducePracticeMotion, englishVariant,
      favoriteQuoteIDs, repeatQuotes, freedomMode, confidenceMode, oppositeShiftMode, codeUnindentOnBackspace,
      minimumAccuracy, minimumWpm, minimumWordBurstWpm, minimumWordBurstMode,
      practiceLineWidth, customPracticeLineColumns, practiceTapeMode, practiceTapeMargin,
      smoothPracticeLineScroll, showAllPracticeLines, caretStyle, typoIndicatorStyle, compositionDisplayStyle, typingSpeedUnit,
      alwaysShowDecimalPlaces, alwaysShowWordsHistory, showWordBurstHeatmap, resultPerformanceVisibility,
      startGraphsAtZero, showAverage, showPersonalBest,
      typedCharacterEffect, liveSpeedStyle, liveAccuracyStyle, liveBurstStyle, liveProgressStyle,
      testModifiers, showFocusWarning,
      showCapsLockWarning, playErrorBeep, playKeyclickSound, clickSoundStyle, errorSoundStyle,
      timeWarningOffset, timeWarningSoundStyle, soundVolume,
      globalHotkeyEnabled,
      paceGuideMode, paceGuideCustomWpm, paceCaretStyle, repeatedPace
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    difficulty = try values.decodeIfPresent(Difficulty.self, forKey: .difficulty) ?? .normal
    strictSpace = try values.decodeIfPresent(Bool.self, forKey: .strictSpace) ?? false
    let legacyStopOnError = try values.decodeIfPresent(Bool.self, forKey: .stopOnError) ?? false
    stopOnErrorMode = try values.decodeIfPresent(StopOnErrorMode.self, forKey: .stopOnErrorMode)
      ?? (legacyStopOnError ? .letter : .off)
    let legacyDeleteOnError = try values.decodeIfPresent(Bool.self, forKey: .deleteOnError) ?? false
    deleteOnErrorMode =
      try values.decodeIfPresent(DeleteOnErrorMode.self, forKey: .deleteOnErrorMode)
      ?? (legacyDeleteOnError ? .letter : .off)
    if stopOnErrorMode.isEnabled { deleteOnErrorMode = .off }
    stopOnError = stopOnErrorMode.isEnabled
    deleteOnError = deleteOnErrorMode.isEnabled
    hideExtraLetters = try values.decodeIfPresent(Bool.self, forKey: .hideExtraLetters) ?? false
    blindMode = try values.decodeIfPresent(Bool.self, forKey: .blindMode) ?? false
    fontSize = try values.decodeIfPresent(Double.self, forKey: .fontSize) ?? 28
    practiceFont =
      try values.decodeIfPresent(PracticeFont.self, forKey: .practiceFont) ?? .monospaced
    theme = try values.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .paper
    publishCompletedResults =
      try values.decodeIfPresent(Bool.self, forKey: .publishCompletedResults) ?? false
    saveCompletedResults =
      try values.decodeIfPresent(Bool.self, forKey: .saveCompletedResults) ?? true
    customThemes =
      try values.decodeIfPresent([CustomThemeDefinition].self, forKey: .customThemes) ?? []
    activeCustomThemeID = try values.decodeIfPresent(UUID.self, forKey: .activeCustomThemeID)
    favoriteThemeIDs = ThemeFavoritePolicy.normalized(
      try values.decodeIfPresent([String].self, forKey: .favoriteThemeIDs) ?? [],
      customThemes: customThemes)
    showKeyboardGuide = try values.decodeIfPresent(Bool.self, forKey: .showKeyboardGuide) ?? true
    keyboardLayout =
      try values.decodeIfPresent(KeyboardLayout.self, forKey: .keyboardLayout) ?? .ansiQwerty
    quickEnd = try values.decodeIfPresent(Bool.self, forKey: .quickEnd) ?? false
    quickRestartKey = try values.decodeIfPresent(QuickRestartKey.self, forKey: .quickRestartKey) ?? .escape
    followSystemTheme = try values.decodeIfPresent(Bool.self, forKey: .followSystemTheme) ?? false
    randomThemeOnRestart =
      try values.decodeIfPresent(Bool.self, forKey: .randomThemeOnRestart) ?? false
    practiceBackdrop =
      try values.decodeIfPresent(PracticeBackdropStyle.self, forKey: .practiceBackdrop) ?? .solid
    reducePracticeMotion =
      try values.decodeIfPresent(Bool.self, forKey: .reducePracticeMotion) ?? false
    englishVariant =
      try values.decodeIfPresent(EnglishVariant.self, forKey: .englishVariant) ?? .american
    favoriteQuoteIDs = try values.decodeIfPresent([String].self, forKey: .favoriteQuoteIDs) ?? []
    repeatQuotes = try values.decodeIfPresent(Bool.self, forKey: .repeatQuotes) ?? false
    freedomMode = try values.decodeIfPresent(Bool.self, forKey: .freedomMode) ?? false
    confidenceMode = try values.decodeIfPresent(ConfidenceMode.self, forKey: .confidenceMode) ?? .off
    oppositeShiftMode =
      try values.decodeIfPresent(OppositeShiftMode.self, forKey: .oppositeShiftMode) ?? .off
    codeUnindentOnBackspace =
      try values.decodeIfPresent(Bool.self, forKey: .codeUnindentOnBackspace) ?? false
    minimumAccuracy = (try values.decodeIfPresent(Int.self, forKey: .minimumAccuracy) ?? 0).clamped(
      to: 0...100)
    minimumWpm = (try values.decodeIfPresent(Int.self, forKey: .minimumWpm) ?? 0).clamped(
      to: 0...300)
    minimumWordBurstWpm = (try values.decodeIfPresent(Int.self, forKey: .minimumWordBurstWpm) ?? 0)
      .clamped(to: 0...300)
    minimumWordBurstMode =
      try values.decodeIfPresent(MinimumWordBurstMode.self, forKey: .minimumWordBurstMode)
      ?? (minimumWordBurstWpm > 0 ? .fixed : .off)
    practiceLineWidth =
      try values.decodeIfPresent(PracticeLineWidth.self, forKey: .practiceLineWidth) ?? .standard
    customPracticeLineColumns =
      (try values.decodeIfPresent(Int.self, forKey: .customPracticeLineColumns) ?? 60).clamped(
        to: PracticeLineWidth.customColumnRange)
    practiceTapeMode =
      try values.decodeIfPresent(PracticeTapeMode.self, forKey: .practiceTapeMode) ?? .off
    practiceTapeMargin =
      (try values.decodeIfPresent(Double.self, forKey: .practiceTapeMargin) ?? 0.5).clamped(to: 0...1)
    smoothPracticeLineScroll =
      try values.decodeIfPresent(Bool.self, forKey: .smoothPracticeLineScroll) ?? true
    showAllPracticeLines =
      try values.decodeIfPresent(Bool.self, forKey: .showAllPracticeLines) ?? false
    caretStyle = try values.decodeIfPresent(TypingCaretStyle.self, forKey: .caretStyle) ?? .block
    typoIndicatorStyle = try values.decodeIfPresent(TypoIndicatorStyle.self, forKey: .typoIndicatorStyle) ?? .off
    compositionDisplayStyle =
      try values.decodeIfPresent(CompositionDisplayStyle.self, forKey: .compositionDisplayStyle) ?? .replace
    typingSpeedUnit = try values.decodeIfPresent(TypingSpeedUnit.self, forKey: .typingSpeedUnit) ?? .wpm
    alwaysShowDecimalPlaces =
      try values.decodeIfPresent(Bool.self, forKey: .alwaysShowDecimalPlaces) ?? false
    alwaysShowWordsHistory =
      try values.decodeIfPresent(Bool.self, forKey: .alwaysShowWordsHistory) ?? false
    showWordBurstHeatmap =
      try values.decodeIfPresent(Bool.self, forKey: .showWordBurstHeatmap) ?? false
    resultPerformanceVisibility =
      try values.decodeIfPresent(ResultPerformanceVisibility.self, forKey: .resultPerformanceVisibility) ?? .init()
    startGraphsAtZero =
      try values.decodeIfPresent(Bool.self, forKey: .startGraphsAtZero) ?? true
    showAverage =
      try values.decodeIfPresent(AverageNoticeDisplay.self, forKey: .showAverage) ?? .off
    showPersonalBest = try values.decodeIfPresent(Bool.self, forKey: .showPersonalBest) ?? false
    typedCharacterEffect = try values.decodeIfPresent(TypedCharacterEffect.self, forKey: .typedCharacterEffect) ?? .keep
    liveSpeedStyle = try values.decodeIfPresent(LiveMetricStyle.self, forKey: .liveSpeedStyle) ?? .text
    liveAccuracyStyle = try values.decodeIfPresent(LiveMetricStyle.self, forKey: .liveAccuracyStyle) ?? .text
    liveBurstStyle = try values.decodeIfPresent(LiveMetricStyle.self, forKey: .liveBurstStyle) ?? .text
    liveProgressStyle = try values.decodeIfPresent(LiveProgressStyle.self, forKey: .liveProgressStyle) ?? .text
    testModifiers = TestModifierPolicy.normalized(
      try values.decodeIfPresent([TestModifier].self, forKey: .testModifiers) ?? [])
    showFocusWarning = try values.decodeIfPresent(Bool.self, forKey: .showFocusWarning) ?? true
    showCapsLockWarning =
      try values.decodeIfPresent(Bool.self, forKey: .showCapsLockWarning) ?? true
    playErrorBeep = try values.decodeIfPresent(Bool.self, forKey: .playErrorBeep) ?? false
    playKeyclickSound = try values.decodeIfPresent(Bool.self, forKey: .playKeyclickSound) ?? false
    clickSoundStyle =
      try values.decodeIfPresent(TypingClickSoundStyle.self, forKey: .clickSoundStyle) ?? .tink
    errorSoundStyle =
      try values.decodeIfPresent(TypingErrorSoundStyle.self, forKey: .errorSoundStyle) ?? .basso
    timeWarningOffset =
      try values.decodeIfPresent(TimeWarningOffset.self, forKey: .timeWarningOffset) ?? .off
    timeWarningSoundStyle =
      try values.decodeIfPresent(TimeWarningSoundStyle.self, forKey: .timeWarningSoundStyle) ?? .glass
    soundVolume = (try values.decodeIfPresent(Double.self, forKey: .soundVolume) ?? 0.7).clamped(
      to: 0...1)
    globalHotkeyEnabled =
      try values.decodeIfPresent(Bool.self, forKey: .globalHotkeyEnabled) ?? false
    paceGuideMode = try values.decodeIfPresent(PaceGuideMode.self, forKey: .paceGuideMode) ?? .off
    paceGuideCustomWpm = (try values.decodeIfPresent(Int.self, forKey: .paceGuideCustomWpm) ?? 60)
      .clamped(to: PaceGuidePolicy.minimumWpm...PaceGuidePolicy.maximumWpm)
    paceCaretStyle = try values.decodeIfPresent(TypingCaretStyle.self, forKey: .paceCaretStyle) ?? .bar
    repeatedPace = try values.decodeIfPresent(Bool.self, forKey: .repeatedPace) ?? false
  }
}

@MainActor
@Observable
final class AppSettings {
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let storageKey = "appSettings.v1"
  @ObservationIgnored private let layoutFluidStorageKey = "layoutFluidLayouts.v1"

  var difficulty: Difficulty = .normal { didSet { persist() } }
  var strictSpace = false { didSet { persist() } }
  /// Backward-compatible Boolean bridge for archives and callers written
  /// before selectable error-handling variants existed.
  var stopOnError = false {
    didSet {
      if stopOnError && stopOnErrorMode == .off { stopOnErrorMode = .letter; return }
      if !stopOnError && stopOnErrorMode != .off { stopOnErrorMode = .off; return }
      if stopOnError {
        confidenceMode = .off
        deleteOnErrorMode = .off
      }
      persist()
    }
  }
  var stopOnErrorMode: StopOnErrorMode = .off {
    didSet {
      if stopOnErrorMode.isEnabled {
        confidenceMode = .off
        deleteOnErrorMode = .off
      }
      if stopOnError != stopOnErrorMode.isEnabled {
        stopOnError = stopOnErrorMode.isEnabled
        return
      }
      persist()
    }
  }
  /// Backward-compatible Boolean bridge for archives and callers written
  /// before selectable error-handling variants existed.
  var deleteOnError = false {
    didSet {
      if deleteOnError && deleteOnErrorMode == .off { deleteOnErrorMode = .letter; return }
      if !deleteOnError && deleteOnErrorMode != .off { deleteOnErrorMode = .off; return }
      if deleteOnError {
        confidenceMode = .off
        stopOnErrorMode = .off
      }
      persist()
    }
  }
  var deleteOnErrorMode: DeleteOnErrorMode = .off {
    didSet {
      if deleteOnErrorMode.isEnabled {
        confidenceMode = .off
        stopOnErrorMode = .off
      }
      if deleteOnError != deleteOnErrorMode.isEnabled {
        deleteOnError = deleteOnErrorMode.isEnabled
        return
      }
      persist()
    }
  }
  var hideExtraLetters = false { didSet { persist() } }
  var blindMode = false { didSet { persist() } }
  var fontSize: Double = 28 { didSet { persist() } }
  var practiceFont: PracticeFont = .monospaced { didSet { persist() } }
  var theme: AppTheme = .paper {
    didSet {
      activeCustomThemeID = nil
      persist()
    }
  }
  var publishCompletedResults = false { didSet { persist() } }
  var saveCompletedResults = true { didSet { persist() } }
  var customThemes: [CustomThemeDefinition] = [] { didSet { persist() } }
  var activeCustomThemeID: UUID? { didSet { persist() } }
  var favoriteThemeIDs: [String] = [] { didSet { persist() } }
  var showKeyboardGuide = true { didSet { persist() } }
  var keyboardLayout: KeyboardLayout = .ansiQwerty { didSet { persist() } }
  var layoutFluidLayouts: [KeyboardLayout] = LayoutFluidPolicy.defaultLayouts {
    didSet { defaults.set(layoutFluidLayouts.map(\.rawValue), forKey: layoutFluidStorageKey) }
  }
  var quickEnd = false { didSet { persist() } }
  var quickRestartKey: QuickRestartKey = .escape { didSet { persist() } }
  var followSystemTheme = false { didSet { persist() } }
  var randomThemeOnRestart = false { didSet { persist() } }
  var practiceBackdrop: PracticeBackdropStyle = .solid { didSet { persist() } }
  var reducePracticeMotion = false { didSet { persist() } }
  var englishVariant: EnglishVariant = .american { didSet { persist() } }
  var favoriteQuoteIDs: [String] = [] { didSet { persist() } }
  var repeatQuotes = false { didSet { persist() } }
  var freedomMode = false { didSet { if freedomMode { confidenceMode = .off }; persist() } }
  var confidenceMode: ConfidenceMode = .off {
    didSet {
      if confidenceMode != .off {
        freedomMode = false
        stopOnError = false
        deleteOnError = false
      }
      persist()
    }
  }
  var oppositeShiftMode: OppositeShiftMode = .off { didSet { persist() } }
  var codeUnindentOnBackspace = false { didSet { persist() } }
  var minimumAccuracy = 0 { didSet { persist() } }
  var minimumWpm = 0 { didSet { persist() } }
  var minimumWordBurstWpm = 0 {
    didSet {
      if minimumWordBurstWpm > 0 && minimumWordBurstMode == .off {
        minimumWordBurstMode = .fixed
        return
      }
      if minimumWordBurstWpm <= 0 && minimumWordBurstMode != .off {
        minimumWordBurstMode = .off
        return
      }
      persist()
    }
  }
  var minimumWordBurstMode: MinimumWordBurstMode = .off {
    didSet {
      if minimumWordBurstMode == .off && minimumWordBurstWpm != 0 {
        minimumWordBurstWpm = 0
        return
      }
      if minimumWordBurstMode != .off && minimumWordBurstWpm == 0 {
        minimumWordBurstWpm = 60
        return
      }
      persist()
    }
  }
  var practiceLineWidth: PracticeLineWidth = .standard { didSet { persist() } }
  var customPracticeLineColumns = 60 { didSet { persist() } }
  var practiceTapeMode: PracticeTapeMode = .off { didSet { persist() } }
  var practiceTapeMargin: Double = 0.5 { didSet { persist() } }
  var smoothPracticeLineScroll = true { didSet { persist() } }
  var showAllPracticeLines = false { didSet { persist() } }
  var caretStyle: TypingCaretStyle = .block { didSet { persist() } }
  var typoIndicatorStyle: TypoIndicatorStyle = .off { didSet { persist() } }
  var compositionDisplayStyle: CompositionDisplayStyle = .replace { didSet { persist() } }
  var typingSpeedUnit: TypingSpeedUnit = .wpm { didSet { persist() } }
  var alwaysShowDecimalPlaces = false { didSet { persist() } }
  var alwaysShowWordsHistory = false { didSet { persist() } }
  var showWordBurstHeatmap = false { didSet { persist() } }
  var resultPerformanceVisibility = ResultPerformanceVisibility() { didSet { persist() } }
  var startGraphsAtZero = true { didSet { persist() } }
  var showAverage: AverageNoticeDisplay = .off { didSet { persist() } }
  var showPersonalBest = false { didSet { persist() } }
  var typedCharacterEffect: TypedCharacterEffect = .keep { didSet { persist() } }
  var liveSpeedStyle: LiveMetricStyle = .text { didSet { persist() } }
  var liveAccuracyStyle: LiveMetricStyle = .text { didSet { persist() } }
  var liveBurstStyle: LiveMetricStyle = .text { didSet { persist() } }
  var liveProgressStyle: LiveProgressStyle = .text { didSet { persist() } }
  var testModifiers: [TestModifier] = [] { didSet { persist() } }
  var showFocusWarning = true { didSet { persist() } }
  var showCapsLockWarning = true { didSet { persist() } }
  var playErrorBeep = false { didSet { persist() } }
  var playKeyclickSound = false { didSet { persist() } }
  var clickSoundStyle: TypingClickSoundStyle = .tink { didSet { persist() } }
  var errorSoundStyle: TypingErrorSoundStyle = .basso { didSet { persist() } }
  var timeWarningOffset: TimeWarningOffset = .off { didSet { persist() } }
  var timeWarningSoundStyle: TimeWarningSoundStyle = .glass { didSet { persist() } }
  var soundVolume: Double = 0.7 { didSet { persist() } }
  var globalHotkeyEnabled = false { didSet { persist() } }
  var paceGuideMode: PaceGuideMode = .off { didSet { persist() } }
  var paceGuideCustomWpm = 60 { didSet { persist() } }
  var paceCaretStyle: TypingCaretStyle = .bar { didSet { persist() } }
  var repeatedPace = false { didSet { persist() } }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let rawLayouts = defaults.stringArray(forKey: layoutFluidStorageKey) {
      layoutFluidLayouts = LayoutFluidPolicy.normalizedLayouts(
        rawLayouts.compactMap(KeyboardLayout.init(rawValue:)))
    }
    guard
      let data = defaults.data(forKey: storageKey),
      let snapshot = try? JSONDecoder().decode(AppSettingsSnapshot.self, from: data)
    else { return }
    difficulty = snapshot.difficulty
    strictSpace = snapshot.strictSpace
    stopOnError = snapshot.stopOnError
    stopOnErrorMode = snapshot.stopOnErrorMode
    deleteOnError = snapshot.deleteOnError
    deleteOnErrorMode = snapshot.deleteOnErrorMode
    hideExtraLetters = snapshot.hideExtraLetters
    blindMode = snapshot.blindMode
    fontSize = snapshot.fontSize
    practiceFont = snapshot.practiceFont
    theme = snapshot.theme
    publishCompletedResults = snapshot.publishCompletedResults
    saveCompletedResults = snapshot.saveCompletedResults
    customThemes = snapshot.customThemes
    activeCustomThemeID = snapshot.activeCustomThemeID
    favoriteThemeIDs = ThemeFavoritePolicy.normalized(
      snapshot.favoriteThemeIDs, customThemes: snapshot.customThemes)
    showKeyboardGuide = snapshot.showKeyboardGuide
    keyboardLayout = snapshot.keyboardLayout
    quickEnd = snapshot.quickEnd
    quickRestartKey = snapshot.quickRestartKey
    followSystemTheme = snapshot.followSystemTheme
    randomThemeOnRestart = snapshot.randomThemeOnRestart
    practiceBackdrop = snapshot.practiceBackdrop
    reducePracticeMotion = snapshot.reducePracticeMotion
    englishVariant = snapshot.englishVariant
    favoriteQuoteIDs = snapshot.favoriteQuoteIDs
    repeatQuotes = snapshot.repeatQuotes
    freedomMode = snapshot.freedomMode
    confidenceMode = snapshot.confidenceMode
    oppositeShiftMode = snapshot.oppositeShiftMode
    codeUnindentOnBackspace = snapshot.codeUnindentOnBackspace
    minimumAccuracy = snapshot.minimumAccuracy
    minimumWpm = snapshot.minimumWpm
    minimumWordBurstWpm = snapshot.minimumWordBurstWpm
    minimumWordBurstMode = snapshot.minimumWordBurstMode
    practiceLineWidth = snapshot.practiceLineWidth
    customPracticeLineColumns = snapshot.customPracticeLineColumns
    practiceTapeMode = snapshot.practiceTapeMode
    practiceTapeMargin = snapshot.practiceTapeMargin
    smoothPracticeLineScroll = snapshot.smoothPracticeLineScroll
    showAllPracticeLines = snapshot.showAllPracticeLines
    caretStyle = snapshot.caretStyle
    typoIndicatorStyle = snapshot.typoIndicatorStyle
    compositionDisplayStyle = snapshot.compositionDisplayStyle
    typingSpeedUnit = snapshot.typingSpeedUnit
    alwaysShowDecimalPlaces = snapshot.alwaysShowDecimalPlaces
    alwaysShowWordsHistory = snapshot.alwaysShowWordsHistory
    showWordBurstHeatmap = snapshot.showWordBurstHeatmap
    resultPerformanceVisibility = snapshot.resultPerformanceVisibility
    startGraphsAtZero = snapshot.startGraphsAtZero
    showAverage = snapshot.showAverage
    showPersonalBest = snapshot.showPersonalBest
    typedCharacterEffect = snapshot.typedCharacterEffect
    liveSpeedStyle = snapshot.liveSpeedStyle
    liveAccuracyStyle = snapshot.liveAccuracyStyle
    liveBurstStyle = snapshot.liveBurstStyle
    liveProgressStyle = snapshot.liveProgressStyle
    testModifiers = snapshot.testModifiers
    showFocusWarning = snapshot.showFocusWarning
    showCapsLockWarning = snapshot.showCapsLockWarning
    playErrorBeep = snapshot.playErrorBeep
    playKeyclickSound = snapshot.playKeyclickSound
    clickSoundStyle = snapshot.clickSoundStyle
    errorSoundStyle = snapshot.errorSoundStyle
    timeWarningOffset = snapshot.timeWarningOffset
    timeWarningSoundStyle = snapshot.timeWarningSoundStyle
    soundVolume = snapshot.soundVolume
    globalHotkeyEnabled = snapshot.globalHotkeyEnabled
    paceGuideMode = snapshot.paceGuideMode
    paceGuideCustomWpm = snapshot.paceGuideCustomWpm
    paceCaretStyle = snapshot.paceCaretStyle
    repeatedPace = snapshot.repeatedPace
  }

  var inputRules: InputRules {
    .init(
      strictSpace: strictSpace,
      stopOnError: stopOnError,
      stopOnErrorMode: stopOnErrorMode,
      deleteOnError: deleteOnError,
      deleteOnErrorMode: deleteOnErrorMode,
      hideExtraLetters: hideExtraLetters,
      blindMode: blindMode,
      quickEnd: quickEnd,
      freedomMode: freedomMode,
      confidenceMode: confidenceMode,
      oppositeShiftMode: oppositeShiftMode,
      codeUnindentOnBackspace: codeUnindentOnBackspace,
      minimumAccuracy: minimumAccuracy,
      minimumWpm: minimumWpm,
      minimumWordBurstWpm: minimumWordBurstWpm,
      minimumWordBurstMode: minimumWordBurstMode
    )
  }

  var snapshot: AppSettingsSnapshot {
    .init(
      difficulty: difficulty, strictSpace: strictSpace, stopOnError: stopOnError,
      stopOnErrorMode: stopOnErrorMode, deleteOnError: deleteOnError,
      deleteOnErrorMode: deleteOnErrorMode, hideExtraLetters: hideExtraLetters, blindMode: blindMode,
      fontSize: fontSize, practiceFont: practiceFont, theme: theme,
      publishCompletedResults: publishCompletedResults, saveCompletedResults: saveCompletedResults,
      customThemes: customThemes,
      activeCustomThemeID: activeCustomThemeID, favoriteThemeIDs: favoriteThemeIDs,
      showKeyboardGuide: showKeyboardGuide, keyboardLayout: keyboardLayout, quickEnd: quickEnd,
      quickRestartKey: quickRestartKey,
      followSystemTheme: followSystemTheme, randomThemeOnRestart: randomThemeOnRestart,
      practiceBackdrop: practiceBackdrop, reducePracticeMotion: reducePracticeMotion,
      englishVariant: englishVariant, favoriteQuoteIDs: favoriteQuoteIDs,
      repeatQuotes: repeatQuotes, freedomMode: freedomMode, confidenceMode: confidenceMode,
      oppositeShiftMode: oppositeShiftMode,
      minimumAccuracy: minimumAccuracy,
      minimumWpm: minimumWpm, minimumWordBurstWpm: minimumWordBurstWpm,
      minimumWordBurstMode: minimumWordBurstMode,
      practiceLineWidth: practiceLineWidth, customPracticeLineColumns: customPracticeLineColumns,
      practiceTapeMode: practiceTapeMode, practiceTapeMargin: practiceTapeMargin,
      smoothPracticeLineScroll: smoothPracticeLineScroll,
      showAllPracticeLines: showAllPracticeLines,
      caretStyle: caretStyle, typoIndicatorStyle: typoIndicatorStyle,
      compositionDisplayStyle: compositionDisplayStyle, typingSpeedUnit: typingSpeedUnit,
      alwaysShowDecimalPlaces: alwaysShowDecimalPlaces,
      alwaysShowWordsHistory: alwaysShowWordsHistory,
      showWordBurstHeatmap: showWordBurstHeatmap,
      resultPerformanceVisibility: resultPerformanceVisibility,
      startGraphsAtZero: startGraphsAtZero,
      showAverage: showAverage,
      showPersonalBest: showPersonalBest,
      typedCharacterEffect: typedCharacterEffect, liveSpeedStyle: liveSpeedStyle,
      liveAccuracyStyle: liveAccuracyStyle, liveBurstStyle: liveBurstStyle,
      liveProgressStyle: liveProgressStyle, testModifiers: testModifiers, showFocusWarning: showFocusWarning,
      showCapsLockWarning: showCapsLockWarning, playErrorBeep: playErrorBeep,
      playKeyclickSound: playKeyclickSound, timeWarningOffset: timeWarningOffset,
      soundVolume: soundVolume,
      globalHotkeyEnabled: globalHotkeyEnabled, paceGuideMode: paceGuideMode,
      paceGuideCustomWpm: paceGuideCustomWpm, paceCaretStyle: paceCaretStyle,
      repeatedPace: repeatedPace)
  }

  func restoreDefaults() {
    difficulty = .normal
    strictSpace = false
    stopOnError = false
    stopOnErrorMode = .off
    deleteOnError = false
    deleteOnErrorMode = .off
    hideExtraLetters = false
    blindMode = false
    fontSize = 28
    practiceFont = .monospaced
    theme = .paper
    publishCompletedResults = false
    saveCompletedResults = true
    customThemes = []
    activeCustomThemeID = nil
    favoriteThemeIDs = []
    showKeyboardGuide = true
    keyboardLayout = .ansiQwerty
    layoutFluidLayouts = LayoutFluidPolicy.defaultLayouts
    quickEnd = false
    quickRestartKey = .escape
    followSystemTheme = false
    randomThemeOnRestart = false
    practiceBackdrop = .solid
    reducePracticeMotion = false
    englishVariant = .american
    favoriteQuoteIDs = []
    repeatQuotes = false
    freedomMode = false
    confidenceMode = .off
    oppositeShiftMode = .off
    codeUnindentOnBackspace = false
    minimumAccuracy = 0
    minimumWpm = 0
    minimumWordBurstWpm = 0
    minimumWordBurstMode = .off
    practiceLineWidth = .standard
    customPracticeLineColumns = 60
    practiceTapeMode = .off
    practiceTapeMargin = 0.5
    smoothPracticeLineScroll = true
    showAllPracticeLines = false
    caretStyle = .block
    typoIndicatorStyle = .off
    compositionDisplayStyle = .replace
    typingSpeedUnit = .wpm
    alwaysShowDecimalPlaces = false
    alwaysShowWordsHistory = false
    showWordBurstHeatmap = false
    resultPerformanceVisibility = .init()
    startGraphsAtZero = true
    showAverage = .off
    showPersonalBest = false
    typedCharacterEffect = .keep
    liveSpeedStyle = .text
    liveAccuracyStyle = .text
    liveBurstStyle = .text
    liveProgressStyle = .text
    testModifiers = []
    showFocusWarning = true
    showCapsLockWarning = true
    playErrorBeep = false
    playKeyclickSound = false
    clickSoundStyle = .tink
    errorSoundStyle = .basso
    timeWarningOffset = .off
    timeWarningSoundStyle = .glass
    soundVolume = 0.7
    globalHotkeyEnabled = false
    paceGuideMode = .off
    paceGuideCustomWpm = 60
    paceCaretStyle = .bar
    repeatedPace = false
  }

  func apply(_ configuration: TestConfiguration) {
    difficulty = configuration.difficulty
    strictSpace = configuration.rules.strictSpace
    stopOnError = configuration.rules.stopOnError
    stopOnErrorMode = configuration.rules.stopOnErrorMode
    deleteOnError = configuration.rules.deleteOnError
    deleteOnErrorMode = configuration.rules.deleteOnErrorMode
    hideExtraLetters = configuration.rules.hideExtraLetters
    blindMode = configuration.rules.blindMode
    quickEnd = configuration.rules.quickEnd
    englishVariant = configuration.englishVariant
    freedomMode = configuration.rules.freedomMode
    confidenceMode = configuration.rules.confidenceMode
    oppositeShiftMode = configuration.rules.oppositeShiftMode
    codeUnindentOnBackspace = configuration.rules.codeUnindentOnBackspace
    minimumAccuracy = configuration.rules.minimumAccuracy
    minimumWpm = configuration.rules.minimumWpm
    minimumWordBurstWpm = configuration.rules.minimumWordBurstWpm
    minimumWordBurstMode = configuration.rules.minimumWordBurstMode
    testModifiers = configuration.modifiers
  }

  func setLayoutFluidLayout(_ layout: KeyboardLayout, at index: Int) {
    guard layoutFluidLayouts.indices.contains(index) else { return }
    var layouts = layoutFluidLayouts
    layouts[index] = layout
    layoutFluidLayouts = LayoutFluidPolicy.normalizedLayouts(layouts)
  }

  func addLayoutFluidLayout() {
    guard layoutFluidLayouts.count < 5 else { return }
    let candidate = KeyboardLayout.allCases.first { !layoutFluidLayouts.contains($0) } ?? .ansiQwerty
    layoutFluidLayouts = LayoutFluidPolicy.normalizedLayouts(layoutFluidLayouts + [candidate])
  }

  func removeLayoutFluidLayout(at index: Int) {
    guard layoutFluidLayouts.count > 1, layoutFluidLayouts.indices.contains(index) else { return }
    var layouts = layoutFluidLayouts
    layouts.remove(at: index)
    layoutFluidLayouts = LayoutFluidPolicy.normalizedLayouts(layouts)
  }

  func apply(_ snapshot: AppSettingsSnapshot) {
    difficulty = snapshot.difficulty
    strictSpace = snapshot.strictSpace
    stopOnError = snapshot.stopOnError
    deleteOnError = snapshot.deleteOnError
    hideExtraLetters = snapshot.hideExtraLetters
    blindMode = snapshot.blindMode
    fontSize = snapshot.fontSize
    practiceFont = snapshot.practiceFont
    theme = snapshot.theme
    publishCompletedResults = snapshot.publishCompletedResults
    saveCompletedResults = snapshot.saveCompletedResults
    customThemes = snapshot.customThemes
    activeCustomThemeID = snapshot.activeCustomThemeID
    favoriteThemeIDs = ThemeFavoritePolicy.normalized(
      snapshot.favoriteThemeIDs, customThemes: snapshot.customThemes)
    showKeyboardGuide = snapshot.showKeyboardGuide
    keyboardLayout = snapshot.keyboardLayout
    quickEnd = snapshot.quickEnd
    quickRestartKey = snapshot.quickRestartKey
    followSystemTheme = snapshot.followSystemTheme
    randomThemeOnRestart = snapshot.randomThemeOnRestart
    practiceBackdrop = snapshot.practiceBackdrop
    reducePracticeMotion = snapshot.reducePracticeMotion
    englishVariant = snapshot.englishVariant
    favoriteQuoteIDs = snapshot.favoriteQuoteIDs
    repeatQuotes = snapshot.repeatQuotes
    freedomMode = snapshot.freedomMode
    confidenceMode = snapshot.confidenceMode
    oppositeShiftMode = snapshot.oppositeShiftMode
    minimumAccuracy = snapshot.minimumAccuracy
    minimumWpm = snapshot.minimumWpm
    minimumWordBurstWpm = snapshot.minimumWordBurstWpm
    minimumWordBurstMode = snapshot.minimumWordBurstMode
    practiceLineWidth = snapshot.practiceLineWidth
    customPracticeLineColumns = snapshot.customPracticeLineColumns
    caretStyle = snapshot.caretStyle
    typoIndicatorStyle = snapshot.typoIndicatorStyle
    compositionDisplayStyle = snapshot.compositionDisplayStyle
    typingSpeedUnit = snapshot.typingSpeedUnit
    alwaysShowDecimalPlaces = snapshot.alwaysShowDecimalPlaces
    alwaysShowWordsHistory = snapshot.alwaysShowWordsHistory
    showWordBurstHeatmap = snapshot.showWordBurstHeatmap
    resultPerformanceVisibility = snapshot.resultPerformanceVisibility
    startGraphsAtZero = snapshot.startGraphsAtZero
    showAverage = snapshot.showAverage
    showPersonalBest = snapshot.showPersonalBest
    typedCharacterEffect = snapshot.typedCharacterEffect
    liveSpeedStyle = snapshot.liveSpeedStyle
    liveAccuracyStyle = snapshot.liveAccuracyStyle
    liveBurstStyle = snapshot.liveBurstStyle
    liveProgressStyle = snapshot.liveProgressStyle
    testModifiers = snapshot.testModifiers
    showFocusWarning = snapshot.showFocusWarning
    showCapsLockWarning = snapshot.showCapsLockWarning
    playErrorBeep = snapshot.playErrorBeep
    playKeyclickSound = snapshot.playKeyclickSound
    clickSoundStyle = snapshot.clickSoundStyle
    errorSoundStyle = snapshot.errorSoundStyle
    timeWarningOffset = snapshot.timeWarningOffset
    timeWarningSoundStyle = snapshot.timeWarningSoundStyle
    soundVolume = snapshot.soundVolume
    globalHotkeyEnabled = snapshot.globalHotkeyEnabled
    paceGuideMode = snapshot.paceGuideMode
    paceGuideCustomWpm = snapshot.paceGuideCustomWpm
    paceCaretStyle = snapshot.paceCaretStyle
    repeatedPace = snapshot.repeatedPace
  }

  var activeTheme: ResolvedTheme {
    guard let activeCustomThemeID,
      let custom = customThemes.first(where: { $0.id == activeCustomThemeID })
    else {
      return theme.resolvedTheme
    }
    return custom.resolvedTheme
  }

  func resolvedTheme(for systemColorScheme: ColorScheme) -> ResolvedTheme {
    guard followSystemTheme else { return activeTheme }
    return (systemColorScheme == .dark ? AppTheme.midnight : AppTheme.paper).resolvedTheme
  }

  func randomizeBuiltInTheme(using index: Int? = nil) {
    guard !followSystemTheme else { return }
    let selection =
      index.map { AppTheme.allCases[abs($0) % AppTheme.allCases.count] } ?? AppTheme.allCases
      .randomElement()!
    theme = selection
  }

  func addCustomTheme(
    name: String, background: Color, panel: Color, accent: Color, prefersDark: Bool
  ) {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty, trimmedName.count <= 40 else { return }
    let custom = CustomThemeDefinition(
      name: trimmedName, background: .init(color: background), panel: .init(color: panel),
      accent: .init(color: accent), prefersDark: prefersDark)
    customThemes.append(custom)
    activeCustomThemeID = custom.id
  }

  func selectCustomTheme(_ id: UUID) {
    guard customThemes.contains(where: { $0.id == id }) else { return }
    activeCustomThemeID = id
  }

  func selectBuiltInTheme(_ theme: AppTheme) {
    self.theme = theme
    activeCustomThemeID = nil
  }

  func isFavoriteTheme(_ theme: AppTheme) -> Bool {
    favoriteThemeIDs.contains(ThemeFavoritePolicy.builtInID(for: theme))
  }

  func isFavoriteCustomTheme(_ id: UUID) -> Bool {
    favoriteThemeIDs.contains(ThemeFavoritePolicy.customID(for: id))
  }

  func toggleFavoriteTheme(_ theme: AppTheme) {
    toggleFavoriteThemeID(ThemeFavoritePolicy.builtInID(for: theme))
  }

  func toggleFavoriteCustomTheme(_ id: UUID) {
    guard customThemes.contains(where: { $0.id == id }) else { return }
    toggleFavoriteThemeID(ThemeFavoritePolicy.customID(for: id))
  }

  func deleteCustomTheme(_ id: UUID) {
    customThemes.removeAll { $0.id == id }
    favoriteThemeIDs.removeAll { $0 == ThemeFavoritePolicy.customID(for: id) }
    if activeCustomThemeID == id { activeCustomThemeID = nil }
  }

  private func toggleFavoriteThemeID(_ id: String) {
    if favoriteThemeIDs.contains(id) {
      favoriteThemeIDs.removeAll { $0 == id }
    } else {
      favoriteThemeIDs.append(id)
    }
  }

  private func persist() {
    let snapshot = AppSettingsSnapshot(
      difficulty: difficulty,
      strictSpace: strictSpace,
      stopOnError: stopOnError,
      stopOnErrorMode: stopOnErrorMode,
      deleteOnError: deleteOnError,
      deleteOnErrorMode: deleteOnErrorMode,
      hideExtraLetters: hideExtraLetters,
      blindMode: blindMode,
      fontSize: fontSize,
      practiceFont: practiceFont,
      theme: theme,
      publishCompletedResults: publishCompletedResults,
      saveCompletedResults: saveCompletedResults,
      customThemes: customThemes,
      activeCustomThemeID: activeCustomThemeID,
      favoriteThemeIDs: favoriteThemeIDs,
      showKeyboardGuide: showKeyboardGuide,
      keyboardLayout: keyboardLayout,
      quickEnd: quickEnd,
      quickRestartKey: quickRestartKey,
      followSystemTheme: followSystemTheme,
      randomThemeOnRestart: randomThemeOnRestart,
      practiceBackdrop: practiceBackdrop,
      reducePracticeMotion: reducePracticeMotion,
      englishVariant: englishVariant,
      favoriteQuoteIDs: favoriteQuoteIDs,
      repeatQuotes: repeatQuotes,
      freedomMode: freedomMode,
      confidenceMode: confidenceMode,
      oppositeShiftMode: oppositeShiftMode,
      codeUnindentOnBackspace: codeUnindentOnBackspace,
      minimumAccuracy: minimumAccuracy,
      minimumWpm: minimumWpm,
      minimumWordBurstWpm: minimumWordBurstWpm,
      minimumWordBurstMode: minimumWordBurstMode,
      practiceLineWidth: practiceLineWidth,
      customPracticeLineColumns: customPracticeLineColumns,
      practiceTapeMode: practiceTapeMode,
      practiceTapeMargin: practiceTapeMargin,
      smoothPracticeLineScroll: smoothPracticeLineScroll,
      showAllPracticeLines: showAllPracticeLines,
      caretStyle: caretStyle,
      typoIndicatorStyle: typoIndicatorStyle,
      compositionDisplayStyle: compositionDisplayStyle,
      typingSpeedUnit: typingSpeedUnit,
      alwaysShowDecimalPlaces: alwaysShowDecimalPlaces,
      alwaysShowWordsHistory: alwaysShowWordsHistory,
      showWordBurstHeatmap: showWordBurstHeatmap,
      resultPerformanceVisibility: resultPerformanceVisibility,
      startGraphsAtZero: startGraphsAtZero,
      showAverage: showAverage,
      showPersonalBest: showPersonalBest,
      typedCharacterEffect: typedCharacterEffect,
      liveSpeedStyle: liveSpeedStyle,
      liveAccuracyStyle: liveAccuracyStyle,
      liveBurstStyle: liveBurstStyle,
      liveProgressStyle: liveProgressStyle,
      testModifiers: testModifiers,
      showFocusWarning: showFocusWarning,
      showCapsLockWarning: showCapsLockWarning,
      playErrorBeep: playErrorBeep,
      playKeyclickSound: playKeyclickSound,
      clickSoundStyle: clickSoundStyle,
      errorSoundStyle: errorSoundStyle,
      timeWarningOffset: timeWarningOffset,
      timeWarningSoundStyle: timeWarningSoundStyle,
      soundVolume: soundVolume,
      globalHotkeyEnabled: globalHotkeyEnabled,
      paceGuideMode: paceGuideMode,
      paceGuideCustomWpm: paceGuideCustomWpm,
      paceCaretStyle: paceCaretStyle,
      repeatedPace: repeatedPace
    )
    defaults.set(try? JSONEncoder().encode(snapshot), forKey: storageKey)
  }

  func isFavoriteQuote(_ id: String) -> Bool {
    favoriteQuoteIDs.contains(id)
  }

  func toggleFavoriteQuote(_ id: String) {
    if isFavoriteQuote(id) {
      favoriteQuoteIDs.removeAll { $0 == id }
    } else {
      favoriteQuoteIDs.append(id)
    }
  }

  func toggleTestModifier(_ modifier: TestModifier) {
    testModifiers = TestModifierPolicy.toggling(modifier, in: testModifiers)
  }
}
