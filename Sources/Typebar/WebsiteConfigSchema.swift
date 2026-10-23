import Foundation

/// Identifier catalogs and the default document belong to the import adapter.
/// No reference themes, fonts or default palette assets are bundled here.
struct WebsiteConfigCatalogs {
  var languages: Set<String>
  var themes: Set<String>
  var layouts: Set<String>
  var fonts: Set<String>
  var funboxes: Set<String>
}

enum WebsiteConfigSchemaError: Error { case invalidDefaults, cannotSanitize }

struct WebsiteConfigSchema {
  private let rules: [String: WebsiteConfigRule]
  var keys: Set<String> { Set(rules.keys) }

  func accepts(_ value: WebsiteConfigValue, for key: String) -> Bool {
    rules[key]?.accepts(value) == true
  }

  init(catalogs: WebsiteConfigCatalogs) {
    var fields: [String: WebsiteConfigRule] = [:]
    for key in ["punctuation", "numbers", "burstHeatmap", "resultSaving", "blindMode",
      "alwaysShowWordsHistory", "britishEnglish", "freedomMode", "strictSpace", "quickEnd",
      "hideExtraLetters", "lazyMode", "codeUnindentOnBackspace", "repeatedPace",
      "smoothLineScroll", "showAllLines", "alwaysShowDecimalPlaces", "startGraphsAtZero",
      "flipTestColors", "colorfulMode", "autoSwitchTheme", "customTheme", "showKeyTips",
      "showOutOfFocusWarning", "capsLockWarning", "showPb", "monkey"] { fields[key] = .boolean }
    let enums: [String: String] = [
      "mode": "time words quote zen custom", "difficulty": "normal expert master",
      "quickRestart": "off esc tab enter", "repeatQuotes": "off typing",
      "singleListCommandLine": "manual on", "minWpm": "off custom", "minAcc": "off custom",
      "minBurst": "off fixed flex", "oppositeShiftMode": "off on keymap",
      "stopOnError": "off word letter", "deleteOnError": "off letter letter_hard word word_hard",
      "confidenceMode": "off on max", "indicateTypos": "off below replace both",
      "compositionDisplay": "off below replace", "smoothCaret": "off slow medium fast",
      "caretStyle": "off default block outline underline carrot banana monkey",
      "paceCaretStyle": "off default block outline underline carrot banana monkey",
      "paceCaret": "off average pb tagPb last custom daily",
      "playSoundOnError": "off 1 2 3 4", "playTimeWarning": "off 1 3 5 10",
      "timerStyle": "off bar text mini flash_text flash_mini",
      "liveSpeedStyle": "off text mini", "liveAccStyle": "off text mini", "liveBurstStyle": "off text mini",
      "timerColor": "black sub text main", "timerOpacity": "0.25 0.5 0.75 1",
      "highlightMode": "off letter word next_word next_two_words next_three_words",
      "typedEffect": "keep hide fade dots", "tapeMode": "off letter word",
      "typingSpeedUnit": "wpm cpm wps cps wph", "keymapMode": "off static react next",
      "keymapStyle": "staggered alice matrix split split_matrix steno steno_matrix",
      "keymapLegendStyle": "lowercase uppercase blank dynamic", "keymapKeys": "minimal minimal_numrow full",
      "customBackgroundSize": "cover contain max", "randomTheme": "off on fav light dark custom auto",
      "showAverage": "off speed acc both", "monkeyPowerLevel": "off 1 2 3 4",
      "ads": "off result on sellout"]
    for (key, values) in enums { fields[key] = .choices(Set(values.split(separator: " ").map(String.init))) }
    fields["playSoundOnClick"] = .choices(Set(["off"] + (1...26).map(String.init)))
    for key in ["words", "time"] { fields[key] = .number(min: 0, integer: true) }
    for key in ["paceCaretCustomSpeed", "minWpmCustomSpeed", "minBurstCustomSpeed"] { fields[key] = .number(min: 0) }
    fields["minAccCustom"] = .number(min: 0, max: 100)
    fields["soundVolume"] = .number(min: 0, max: 1)
    fields["fontSize"] = .number(positive: true)
    fields["keymapSize"] = .number(min: 0.5, max: 3.5, tenth: true)
    fields["tapeMargin"] = .number(min: 10, max: 90)
    fields["maxLineWidth"] = .lineWidth
    fields["language"] = .choices(catalogs.languages)
    for key in ["theme", "themeLight", "themeDark"] { fields[key] = .choices(catalogs.themes) }
    fields["layout"] = .choices(catalogs.layouts.union(["default"]))
    fields["keymapLayout"] = .choices(catalogs.layouts.union(["overrideSync"]))
    fields["fontFamily"] = .font(catalogs.fonts)
    fields["customBackground"] = .imageURL
    fields["funbox"] = .list(.choices(catalogs.funboxes), max: 15)
    fields["customLayoutfluid"] = .list(.choices(catalogs.layouts), min: 2, max: 15)
    fields["customPolyglot"] = .list(.choices(catalogs.languages), min: 2)
    fields["favThemes"] = .list(.choices(catalogs.themes))
    fields["quoteLength"] = .list(.quoteLength)
    fields["accountChart"] = .tuple(Array(repeating: .choices(["on", "off"]), count: 4))
    fields["customBackgroundFilter"] = .tuple(Array(repeating: .number(), count: 4))
    fields["customThemeColors"] = .tuple(Array(repeating: .color, count: 10))
    rules = fields
  }

  func sanitize(_ input: [String: WebsiteConfigValue]) throws -> [String: WebsiteConfigValue] {
    var current = input
    for attempt in 0...2 {
      let invalid = current.keys.filter { key in
        guard let rule = rules[key], let value = current[key] else { return false }
        return !rule.accepts(value)
      }
      if invalid.isEmpty { return current.filter { rules[$0.key] != nil } }
      guard attempt < 2 else { throw WebsiteConfigSchemaError.cannotSanitize }
      for key in invalid {
        if let value = current[key] { current[key] = rules[key]?.repair(value) }
      }
    }
    throw WebsiteConfigSchemaError.cannotSanitize
  }

  /// The real JSON import entry first safe-parses the optional/strip schema.
  /// Unknown legacy keys disappear on success; migration is only a fallback.
  func validatingPartial(_ input: [String: WebsiteConfigValue]) -> [String: WebsiteConfigValue]? {
    let known = input.filter { rules[$0.key] != nil }
    guard known.allSatisfy({ rules[$0.key]?.accepts($0.value) == true }) else { return nil }
    return known
  }

  func migrating(_ input: [String: WebsiteConfigValue],
    defaults: [String: WebsiteConfigValue]) throws -> [String: WebsiteConfigValue] {
    guard Set(defaults.keys) == keys,
      defaults.allSatisfy({ rules[$0.key]?.accepts($0.value) == true })
    else { throw WebsiteConfigSchemaError.invalidDefaults }
    let sanitized = try sanitize(MonkeytypeLegacyConfigMigration.replacingLegacyValues(input))
    return defaults.merging(sanitized) { _, incoming in incoming }
  }
}

private indirect enum WebsiteConfigRule {
  case boolean, choices(Set<String>), font(Set<String>), color, imageURL, lineWidth, quoteLength
  case number(min: Double? = nil, max: Double? = nil, integer: Bool = false,
    positive: Bool = false, tenth: Bool = false)
  case list(Self, min: Int = 0, max: Int? = nil), tuple([Self])

  func accepts(_ value: WebsiteConfigValue) -> Bool {
    switch self {
    case .boolean: if case .bool = value { return true }; return false
    case .choices(let choices): if case .string(let text) = value { return choices.contains(text) }; return false
    case .number(let min, let max, let integer, let positive, let tenth):
      guard case .number(let number) = value, !number.isNaN,
        min.map({ number >= $0 }) ?? true, max.map({ number <= $0 }) ?? true,
        !positive || number > 0, !integer || (number.isFinite && number.rounded(.towardZero) == number)
      else { return false }
      return !tenth || acceptsTenthStep(number)
    case .font(let known):
      guard case .string(let text) = value else { return false }
      return known.contains(text) || (text.utf16.count <= 50 && matches(text, #"^[a-zA-Z0-9_\-+.]+$"#))
    case .color: if case .string(let text) = value { return matches(text, #"(?i)^#([0-9a-f]{3}){1,2}$"#) }; return false
    case .imageURL:
      guard case .string(let text) = value else { return false }
      if text.isEmpty { return true }
      guard text.utf16.count <= 2048, text.hasPrefix("http://") || text.hasPrefix("https://"),
        !text.contains(where: { "`'\"".contains($0) }),
        matches(text, #"(?i).+\.(png|gif|jpeg|jpg|webp)"#),
        let url = URL(string: normalizedSpecialURL(text)), let host = url.host, !host.isEmpty else { return false }
      return url.port.map { (0...65535).contains($0) } ?? true
    case .lineWidth:
      guard case .number(let number) = value else { return false }
      return number == 0 || (number >= 20 && number <= 1000)
    case .quoteLength:
      guard case .number(let number) = value else { return false }
      return [-3, -2, 0, 1, 2, 3].contains(number)
    case .list(let element, let min, let max):
      guard case .array(let values) = value, values.count >= min,
        max.map({ values.count <= $0 }) ?? true else { return false }
      return values.allSatisfy(element.accepts)
    case .tuple(let elements):
      guard case .array(let values) = value, values.count == elements.count else { return false }
      return zip(elements, values).allSatisfy { $0.accepts($1) }
    }
  }

  func repair(_ value: WebsiteConfigValue) -> WebsiteConfigValue? {
    guard case .array(let values) = value else { return nil }
    let retained: [WebsiteConfigValue]
    switch self {
    case .list(let element, let min, let max):
      guard values.count >= min, max.map({ values.count <= $0 }) ?? true else { return nil }
      retained = values.filter(element.accepts)
    case .tuple(let elements):
      guard values.count == elements.count else { return nil }
      retained = zip(elements, values).compactMap { $0.accepts($1) ? $1 : nil }
    default: return nil
    }
    // An all-invalid array removes its parent field, unlike a valid empty array.
    return retained.isEmpty ? nil : .array(retained)
  }

  private func normalizedSpecialURL(_ text: String) -> String {
    let cleaned = text.replacingOccurrences(of: "\t", with: "")
      .replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
      .replacingOccurrences(of: "\\", with: "/")
    let prefix = cleaned.hasPrefix("https:") ? "https://" : "http://"
    let rest = cleaned.dropFirst(cleaned.hasPrefix("https:") ? 6 : 5).drop(while: { $0 == "/" })
    return prefix + rest
  }

  private func matches(_ text: String, _ pattern: String) -> Bool {
    text.range(of: pattern, options: .regularExpression) != nil
  }

  private func acceptsTenthStep(_ number: Double) -> Bool {
    guard number.isFinite else { return false }
    // This rule is only used in [0.5, 3.5]. Zod 3.23.8 rounds decimal
    // integer operands to binary64 before taking the remainder, admitting
    // some adjacent doubles which a strict decimal-grid test would reject.
    let text = String(number)
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    let places = max(1, parts.count > 1 ? parts[1].count : 0)
    let digits = parts.joined() + (parts.count > 1 ? "" : "0")
    guard let integer = Double(digits), let quantum = Double("1" + String(repeating: "0", count: places - 1))
    else { return false }
    return integer.truncatingRemainder(dividingBy: quantum) == 0
  }
}
