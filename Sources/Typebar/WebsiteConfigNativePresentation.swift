import Foundation

enum WebsiteConfigNativePresentationError: Error, Equatable {
  case missingField(String), invalidField(String), incompatibleModes
}

/// Presentation-group draft only. Does not apply a window event, render a
/// resource, write preferences or certify a complete website import.
struct WebsiteConfigNativePresentation {
  static let mappedKeys: Set<String> = ["smoothCaret", "caretStyle", "paceCaretStyle", "timerStyle",
    "liveSpeedStyle", "liveAccStyle", "liveBurstStyle", "timerColor", "timerOpacity", "showAverage",
    "highlightMode", "typedEffect", "typingSpeedUnit", "monkeyPowerLevel", "indicateTypos", "compositionDisplay",
    "showKeyTips", "alwaysShowDecimalPlaces", "alwaysShowWordsHistory", "burstHeatmap", "startGraphsAtZero",
    "showOutOfFocusWarning", "capsLockWarning", "showPb", "flipTestColors", "colorfulMode", "monkey",
    "smoothLineScroll", "showAllLines", "tapeMode", "tapeMargin"]

  let smoothCaretMotion: SmoothCaretMotion
  let caretStyle: TypingCaretStyle
  let paceCaretStyle: TypingCaretStyle
  let liveProgressStyle: LiveProgressStyle
  let liveSpeedStyle: LiveMetricStyle
  let liveAccuracyStyle: LiveMetricStyle
  let liveBurstStyle: LiveMetricStyle
  let liveStatsColor: LiveStatsColor
  let liveStatsOpacity: LiveStatsOpacity
  let showAverage: AverageNoticeDisplay
  let promptHighlightMode: PromptHighlightMode
  let typedCharacterEffect: TypedCharacterEffect
  let typingSpeedUnit: TypingSpeedUnit
  let typingPowerMode: TypingPowerMode
  let typoIndicatorStyle: TypoIndicatorStyle
  let compositionDisplayStyle: CompositionDisplayStyle
  let showKeyTips: Bool
  let alwaysShowDecimalPlaces: Bool
  let alwaysShowWordsHistory: Bool
  let showWordBurstHeatmap: Bool
  let startGraphsAtZero: Bool
  let showFocusWarning: Bool
  let showCapsLockWarning: Bool
  let showPersonalBest: Bool
  let flipTestColors: Bool
  let colorfulMode: Bool
  let showTypingCompanion: Bool
  let smoothPracticeLineScroll: Bool
  let showAllPracticeLines: Bool
  let practiceTapeMode: PracticeTapeMode
  let practiceTapeMargin: Double

  init(runtime: [String: WebsiteConfigValue]) throws {
    func value(_ key: String) throws -> WebsiteConfigValue {
      guard let value = runtime[key] else { throw WebsiteConfigNativePresentationError.missingField(key) }
      return value
    }
    func boolean(_ key: String) throws -> Bool {
      guard case .bool(let result) = try value(key) else { throw WebsiteConfigNativePresentationError.invalidField(key) }
      return result
    }
    func text(_ key: String) throws -> String {
      guard case .string(let result) = try value(key), result.utf8.allSatisfy({ $0 < 128 })
      else { throw WebsiteConfigNativePresentationError.invalidField(key) }
      return result
    }
    func option<T: RawRepresentable>(_ key: String, _ type: T.Type) throws -> T where T.RawValue == String {
      guard let result = try T(rawValue: text(key)) else { throw WebsiteConfigNativePresentationError.invalidField(key) }
      return result
    }
    func choice<T>(_ key: String, _ choices: [T], _ spelling: (T) -> String) throws -> T {
      let name = try text(key)
      guard let result = choices.first(where: { spelling($0) == name }) else {
        throw WebsiteConfigNativePresentationError.invalidField(key)
      }
      return result
    }
    smoothCaretMotion = try option("smoothCaret", SmoothCaretMotion.self)
    caretStyle = try choice("caretStyle", TypingCaretStyle.allCases, \.compatibilityValue)
    paceCaretStyle = try choice("paceCaretStyle", TypingCaretStyle.allCases, \.compatibilityValue)
    liveProgressStyle = try option("timerStyle", LiveProgressStyle.self)
    liveSpeedStyle = try option("liveSpeedStyle", LiveMetricStyle.self)
    liveAccuracyStyle = try option("liveAccStyle", LiveMetricStyle.self)
    liveBurstStyle = try option("liveBurstStyle", LiveMetricStyle.self)
    liveStatsColor = try choice("timerColor", LiveStatsColor.allCases, \.compatibilityValue)
    switch try text("timerOpacity") {
    case "0.25": liveStatsOpacity = .quarter
    case "0.5": liveStatsOpacity = .half
    case "0.75": liveStatsOpacity = .threeQuarters
    case "1": liveStatsOpacity = .full
    default: throw WebsiteConfigNativePresentationError.invalidField("timerOpacity")
    }
    switch try text("showAverage") {
    case "off": showAverage = .off
    case "speed": showAverage = .speed
    case "acc": showAverage = .accuracy
    case "both": showAverage = .both
    default: throw WebsiteConfigNativePresentationError.invalidField("showAverage")
    }
    switch try text("highlightMode") {
    case "off": promptHighlightMode = .off
    case "letter": promptHighlightMode = .letter
    case "word": promptHighlightMode = .word
    case "next_word": promptHighlightMode = .nextWord
    case "next_two_words": promptHighlightMode = .nextTwoWords
    case "next_three_words": promptHighlightMode = .nextThreeWords
    default: throw WebsiteConfigNativePresentationError.invalidField("highlightMode")
    }
    typedCharacterEffect = try option("typedEffect", TypedCharacterEffect.self)
    typingSpeedUnit = try option("typingSpeedUnit", TypingSpeedUnit.self)
    typingPowerMode = try choice("monkeyPowerLevel", TypingPowerMode.allCases, \.compatibilityValue)
    typoIndicatorStyle = try option("indicateTypos", TypoIndicatorStyle.self)
    compositionDisplayStyle = try option("compositionDisplay", CompositionDisplayStyle.self)
    showKeyTips = try boolean("showKeyTips")
    alwaysShowDecimalPlaces = try boolean("alwaysShowDecimalPlaces")
    alwaysShowWordsHistory = try boolean("alwaysShowWordsHistory")
    showWordBurstHeatmap = try boolean("burstHeatmap")
    startGraphsAtZero = try boolean("startGraphsAtZero")
    showFocusWarning = try boolean("showOutOfFocusWarning")
    showCapsLockWarning = try boolean("capsLockWarning")
    showPersonalBest = try boolean("showPb")
    flipTestColors = try boolean("flipTestColors")
    colorfulMode = try boolean("colorfulMode")
    showTypingCompanion = try boolean("monkey")
    smoothPracticeLineScroll = try boolean("smoothLineScroll")
    showAllPracticeLines = try boolean("showAllLines")
    practiceTapeMode = try option("tapeMode", PracticeTapeMode.self)
    guard case .number(let margin) = try value("tapeMargin"), margin.isFinite, (10...90).contains(margin)
    else { throw WebsiteConfigNativePresentationError.invalidField("tapeMargin") }
    practiceTapeMargin = margin / 100
    guard !(showTypingCompanion && (liveSpeedStyle == .text || liveAccuracyStyle == .text)),
      !(showAllPracticeLines && practiceTapeMode != .off)
    else { throw WebsiteConfigNativePresentationError.incompatibleModes }
  }

  func applying(to snapshot: AppSettingsSnapshot) -> AppSettingsSnapshot {
    var result = snapshot
    result.smoothCaretMotion = smoothCaretMotion
    result.caretStyle = caretStyle
    result.paceCaretStyle = paceCaretStyle
    result.liveProgressStyle = liveProgressStyle
    result.liveSpeedStyle = liveSpeedStyle
    result.liveAccuracyStyle = liveAccuracyStyle
    result.liveBurstStyle = liveBurstStyle
    result.liveStatsColor = liveStatsColor
    result.liveStatsOpacity = liveStatsOpacity
    result.showAverage = showAverage
    result.promptHighlightMode = promptHighlightMode
    result.typedCharacterEffect = typedCharacterEffect
    result.typingSpeedUnit = typingSpeedUnit
    result.typingPowerMode = typingPowerMode
    result.typoIndicatorStyle = typoIndicatorStyle
    result.compositionDisplayStyle = compositionDisplayStyle
    result.showKeyTips = showKeyTips
    result.alwaysShowDecimalPlaces = alwaysShowDecimalPlaces
    result.alwaysShowWordsHistory = alwaysShowWordsHistory
    result.showWordBurstHeatmap = showWordBurstHeatmap
    result.startGraphsAtZero = startGraphsAtZero
    result.showFocusWarning = showFocusWarning
    result.showCapsLockWarning = showCapsLockWarning
    result.showPersonalBest = showPersonalBest
    result.flipTestColors = flipTestColors
    result.colorfulMode = colorfulMode
    result.showTypingCompanion = showTypingCompanion
    result.smoothPracticeLineScroll = smoothPracticeLineScroll
    result.showAllPracticeLines = showAllPracticeLines
    result.practiceTapeMode = practiceTapeMode
    result.practiceTapeMargin = practiceTapeMargin
    return result
  }
}
