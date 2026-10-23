import Foundation

enum WebsiteConfigNativeBehaviorError: Error, Equatable {
  case missingField(String), invalidField(String), unrepresentableField(String)
}

/// Sound, pace and general-behavior draft. No playback, network, persistence
/// or permission to apply a whole website configuration is implied.
struct WebsiteConfigNativeBehavior {
  static let mappedKeys: Set<String> = ["playSoundOnClick", "playSoundOnError", "playTimeWarning", "soundVolume",
    "paceCaret", "paceCaretCustomSpeed", "repeatedPace", "quickRestart", "singleListCommandLine",
    "britishEnglish", "resultSaving", "repeatQuotes"]

  let clickSoundStyle: TypingClickSoundStyle?
  let errorSoundStyle: TypingErrorSoundStyle?
  let timeWarningOffset: TimeWarningOffset
  let soundVolume: Double
  let paceGuideMode: PaceGuideMode
  let paceGuideCustomWpm: Double
  let repeatedPace: Bool
  let quickRestartKey: QuickRestartKey
  let commandPaletteListMode: CommandPaletteListMode
  let englishVariant: EnglishVariant
  let saveCompletedResults: Bool
  let repeatQuotes: Bool

  init(runtime: [String: WebsiteConfigValue]) throws {
    func value(_ key: String) throws -> WebsiteConfigValue {
      guard let value = runtime[key] else { throw WebsiteConfigNativeBehaviorError.missingField(key) }
      return value
    }
    func boolean(_ key: String) throws -> Bool {
      guard case .bool(let result) = try value(key) else { throw WebsiteConfigNativeBehaviorError.invalidField(key) }
      return result
    }
    func text(_ key: String) throws -> String {
      guard case .string(let result) = try value(key), result.utf8.allSatisfy({ $0 < 128 })
      else { throw WebsiteConfigNativeBehaviorError.invalidField(key) }
      return result
    }
    func number(_ key: String, maximum: Double? = nil) throws -> Double {
      guard case .number(let result) = try value(key), result >= 0,
        maximum.map({ result <= $0 }) ?? true else { throw WebsiteConfigNativeBehaviorError.invalidField(key) }
      guard result.isFinite else { throw WebsiteConfigNativeBehaviorError.unrepresentableField(key) }
      return result
    }
    guard let click = try SoundCommandCatalog.target(for: "sound.playSoundOnClick.\(text("playSoundOnClick"))"),
      case .click(let clickStyle) = click else { throw WebsiteConfigNativeBehaviorError.invalidField("playSoundOnClick") }
    clickSoundStyle = clickStyle
    guard let error = try SoundCommandCatalog.target(for: "sound.playSoundOnError.\(text("playSoundOnError"))"),
      case .error(let errorStyle) = error else { throw WebsiteConfigNativeBehaviorError.invalidField("playSoundOnError") }
    errorSoundStyle = errorStyle
    guard let warning = try SoundCommandCatalog.target(for: "sound.playTimeWarning.\(text("playTimeWarning"))"),
      case .timeWarning(let offset) = warning else { throw WebsiteConfigNativeBehaviorError.invalidField("playTimeWarning") }
    timeWarningOffset = offset
    soundVolume = try number("soundVolume", maximum: 1)
    switch try text("paceCaret") {
    case "off": paceGuideMode = .off
    case "custom": paceGuideMode = .custom
    case "pb": paceGuideMode = .personalBest
    // Website tags are stable account identities, not native text labels.
    case "tagPb": paceGuideMode = .accountTagPersonalBest
    case "last": paceGuideMode = .lastTest
    case "average": paceGuideMode = .recentAverage
    case "daily": paceGuideMode = .dailyBest
    default: throw WebsiteConfigNativeBehaviorError.invalidField("paceCaret")
    }
    // Config stores canonical WPM even when the displayed unit is CPS/WPH.
    // The disabled mode also retains its custom memory, including zero.
    paceGuideCustomWpm = try number("paceCaretCustomSpeed")
    repeatedPace = try boolean("repeatedPace")
    switch try text("quickRestart") {
    case "off": quickRestartKey = .off
    case "esc": quickRestartKey = .escape
    case "tab": quickRestartKey = .tab
    case "enter": quickRestartKey = .enter
    default: throw WebsiteConfigNativeBehaviorError.invalidField("quickRestart")
    }
    switch try text("singleListCommandLine") {
    case "manual": commandPaletteListMode = .grouped
    case "on": commandPaletteListMode = .singleList
    default: throw WebsiteConfigNativeBehaviorError.invalidField("singleListCommandLine")
    }
    englishVariant = try boolean("britishEnglish") ? .british : .american
    saveCompletedResults = try boolean("resultSaving")
    switch try text("repeatQuotes") {
    case "off": repeatQuotes = false
    case "typing": repeatQuotes = true
    default: throw WebsiteConfigNativeBehaviorError.invalidField("repeatQuotes")
    }
  }

  func applying(to snapshot: AppSettingsSnapshot) -> AppSettingsSnapshot {
    var result = snapshot
    result.playKeyclickSound = clickSoundStyle != nil
    if let clickSoundStyle { result.clickSoundStyle = clickSoundStyle }
    result.playErrorBeep = errorSoundStyle != nil
    if let errorSoundStyle { result.errorSoundStyle = errorSoundStyle }
    result.timeWarningOffset = timeWarningOffset
    result.soundVolume = soundVolume
    result.paceGuideMode = paceGuideMode
    result.paceGuideCustomWpm = paceGuideCustomWpm
    result.repeatedPace = repeatedPace
    result.quickRestartKey = quickRestartKey
    result.commandPaletteListMode = commandPaletteListMode
    result.englishVariant = englishVariant
    result.saveCompletedResults = saveCompletedResults
    result.repeatQuotes = repeatQuotes
    return result
  }

  func applying(to configuration: TestConfiguration) -> TestConfiguration {
    var result = configuration
    result.englishVariant = englishVariant
    return result
  }
}
