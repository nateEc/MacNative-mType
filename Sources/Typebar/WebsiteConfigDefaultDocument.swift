import Foundation

/// Identifiers and colors are supplied by the native appearance adapter, not
/// extracted from a reference theme/font asset or the user's current settings.
struct WebsiteConfigDefaultAppearance {
  var theme: String
  var lightTheme: String
  var darkTheme: String
  var fontFamily: String
  var customThemeColors: [String]
}

struct WebsiteConfigDefaultDocument {
  let values: [String: WebsiteConfigValue]
  let orderedKeys: [String]

  init(appearance: WebsiteConfigDefaultAppearance, catalogs: WebsiteConfigCatalogs) throws {
    // This order is observable in full-config setter events. Do not derive it
    // from a Swift Dictionary, schema order or the current practice snapshot.
    let fields: [(String, WebsiteConfigValue)] = [
      ("theme", .string(appearance.theme)),
      ("themeLight", .string(appearance.lightTheme)),
      ("themeDark", .string(appearance.darkTheme)),
      ("autoSwitchTheme", .bool(false)),
      ("customTheme", .bool(false)),
      ("customThemeColors", .array(appearance.customThemeColors.map(WebsiteConfigValue.string))),
      ("favThemes", .array([])),
      ("showKeyTips", .bool(true)),
      ("smoothCaret", .string("medium")),
      ("codeUnindentOnBackspace", .bool(false)),
      ("quickRestart", .string("off")),
      ("punctuation", .bool(false)),
      ("numbers", .bool(false)),
      ("words", .number(50)),
      ("time", .number(30)),
      ("mode", .string("time")),
      ("quoteLength", .array([.number(1)])),
      ("language", .string("english")),
      ("fontSize", .number(2)),
      ("freedomMode", .bool(false)),
      ("difficulty", .string("normal")),
      ("blindMode", .bool(false)),
      ("quickEnd", .bool(false)),
      ("caretStyle", .string("default")),
      ("paceCaretStyle", .string("default")),
      ("flipTestColors", .bool(false)),
      ("layout", .string("default")),
      ("funbox", .array([])),
      ("confidenceMode", .string("off")),
      ("indicateTypos", .string("off")),
      ("compositionDisplay", .string("replace")),
      ("timerStyle", .string("mini")),
      ("liveSpeedStyle", .string("off")),
      ("liveAccStyle", .string("off")),
      ("liveBurstStyle", .string("off")),
      ("colorfulMode", .bool(false)),
      ("randomTheme", .string("off")),
      ("timerColor", .string("main")),
      ("timerOpacity", .string("1")),
      ("stopOnError", .string("off")),
      ("deleteOnError", .string("off")),
      ("showAllLines", .bool(false)),
      ("keymapMode", .string("off")),
      ("keymapStyle", .string("staggered")),
      ("keymapLegendStyle", .string("lowercase")),
      ("keymapLayout", .string("overrideSync")),
      ("keymapKeys", .string("minimal")),
      ("keymapSize", .number(1)),
      ("fontFamily", .string(appearance.fontFamily)),
      ("smoothLineScroll", .bool(false)),
      ("alwaysShowDecimalPlaces", .bool(false)),
      ("alwaysShowWordsHistory", .bool(false)),
      ("singleListCommandLine", .string("on")),
      ("capsLockWarning", .bool(true)),
      ("playSoundOnError", .string("off")),
      ("playSoundOnClick", .string("off")),
      ("soundVolume", .number(0.5)),
      ("startGraphsAtZero", .bool(true)),
      ("showOutOfFocusWarning", .bool(true)),
      ("paceCaret", .string("off")),
      ("paceCaretCustomSpeed", .number(100)),
      ("repeatedPace", .bool(true)),
      ("accountChart", .array(Array(repeating: .string("on"), count: 4))),
      ("minWpm", .string("off")),
      ("minWpmCustomSpeed", .number(100)),
      ("highlightMode", .string("letter")),
      ("typedEffect", .string("keep")),
      ("typingSpeedUnit", .string("wpm")),
      ("ads", .string("result")),
      ("hideExtraLetters", .bool(false)),
      ("strictSpace", .bool(false)),
      ("minAcc", .string("off")),
      ("minAccCustom", .number(90)),
      ("monkey", .bool(false)),
      ("repeatQuotes", .string("off")),
      ("resultSaving", .bool(true)),
      ("oppositeShiftMode", .string("off")),
      ("customBackground", .string("")),
      ("customBackgroundSize", .string("cover")),
      ("customBackgroundFilter", .array([0, 1, 1, 1].map { .number(Double($0)) })),
      ("customLayoutfluid", .array(["qwerty", "dvorak", "colemak"].map(WebsiteConfigValue.string))),
      ("customPolyglot", .array(["english", "spanish", "french", "german"].map(WebsiteConfigValue.string))),
      ("monkeyPowerLevel", .string("off")),
      ("minBurst", .string("off")),
      ("minBurstCustomSpeed", .number(100)),
      ("burstHeatmap", .bool(false)),
      ("britishEnglish", .bool(false)),
      ("lazyMode", .bool(false)),
      ("showAverage", .string("off")),
      ("showPb", .bool(false)),
      ("tapeMode", .string("off")),
      ("tapeMargin", .number(50)),
      ("maxLineWidth", .number(0)),
      ("playTimeWarning", .string("off")),
    ]
    let schema = WebsiteConfigSchema(catalogs: catalogs)
    let document = Dictionary(uniqueKeysWithValues: fields)
    guard Set(document.keys) == schema.keys,
      document.allSatisfy({ schema.accepts($0.value, for: $0.key) })
    else { throw WebsiteConfigSchemaError.invalidDefaults }
    values = document
    orderedKeys = fields.map(\.0)
  }
}
