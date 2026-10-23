import Foundation

/// Staged website input, never an AppSettings snapshot or a diagnostics payload.
indirect enum WebsiteConfigValue: Codable, Equatable {
  case null, bool(Bool), number(Double), string(String)
  case array([Self]), object([String: Self])
  case stringCodeUnits([UInt16]), objectCodeUnits([WebsiteConfigMember])

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() { self = .null }
    else if let value = try? container.decode(Bool.self) { self = .bool(value) }
    else if let value = try? container.decode(Double.self) { self = .number(value) }
    else if let value = try? container.decode(String.self) { self = .string(value) }
    else if let value = try? container.decode([Self].self) { self = .array(value) }
    else { self = .object(try container.decode([String: Self].self)) }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .array(let values): try container.encode(values)
    case .object(let values): try container.encode(values)
    case .stringCodeUnits, .objectCodeUnits:
      throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath,
        debugDescription: "Use the website JSON writer to preserve UTF-16 units"))
    }
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    if let a = lhs.stringUnits, let b = rhs.stringUnits { return a == b }
    if let a = lhs.objectMembers, let b = rhs.objectMembers {
      return Dictionary(a.map { ($0.key, $0.value) }, uniquingKeysWith: { _, new in new })
        == Dictionary(b.map { ($0.key, $0.value) }, uniquingKeysWith: { _, new in new })
    }
    return switch (lhs, rhs) {
    case (.null, .null): true
    case (.bool(let a), .bool(let b)): a == b
    case (.number(let a), .number(let b)): a == b || (a.isNaN && b.isNaN)
    case (.array(let a), .array(let b)): a == b
    default: false
    }
  }
}

enum WebsiteConfigInputError: Error { case expectedObject }

enum MonkeytypeLegacyConfigMigration {
  static func decodeObject(_ json: String) throws -> [String: WebsiteConfigValue] {
    let value = try WebsiteConfigJSONReader.read(json)
    guard case .object(let object) = value else { throw WebsiteConfigInputError.expectedObject }
    return object
  }

  /// Legacy replacement only. Schema sanitization, default merging and runtime
  /// admission are later stages; no preferences or files are written here.
  static func replacingLegacyValues(_ input: [String: WebsiteConfigValue]) -> [String: WebsiteConfigValue] {
    var output = input
    if output["quickRestart"] == nil {
      if output["quickTab"] == .bool(true) { output["quickRestart"] = .string("tab") }
      else if output["swapEscAndTab"] == .bool(true) { output["quickRestart"] = .string("esc") }
    }
    for (key, enabled, disabled) in [
      ("smoothCaret", "medium", "off"), ("playSoundOnError", "1", "off"),
      ("indicateTypos", "replace", "off")
    ] {
      if case .bool(let value) = output[key] { output[key] = .string(value ? enabled : disabled) }
    }
    if output["alwaysShowCPM"] == .bool(true), output["typingSpeedUnit"] == nil {
      output["typingSpeedUnit"] = .string("cpm")
    }
    if output["showAverage"] == .string("wpm") { output["showAverage"] = .string("speed") }
    if output["showTimerProgress"] == .bool(false), output["timerStyle"] == nil {
      output["timerStyle"] = .string("off")
    }
    for (legacy, current) in [("showLiveWpm", "liveSpeedStyle"),
      ("showLiveAcc", "liveAccStyle"), ("showLiveBurst", "liveBurstStyle")] {
      if output[legacy] == .bool(true), output[current] == nil {
        output[current] = [WebsiteConfigValue.string("bar"), .string("off")].contains(output["timerStyle"] ?? .null)
          ? .string("mini") : output["timerStyle"]
      }
    }
    if let units = output["soundVolume"]?.stringUnits {
      output["soundVolume"] = .number(WebsiteConfigNumbers.floatPrefix(String(decoding: units, as: UTF16.self)))
    }
    for key in ["funbox", "customLayoutfluid"] {
      if let units = output[key]?.stringUnits {
        output[key] = .array(key == "funbox" && units == Array("none".utf16) ? []
          : units.split(separator: 35, omittingEmptySubsequences: false).map { .string(units: Array($0)) })
      }
    }
    if let units = output["fontSize"]?.stringUnits {
      let value = String(decoding: units, as: UTF16.self)
      let number = value == "125" ? 1.25 : value == "15" ? 1.5 : WebsiteConfigNumbers.integerPrefix(value)
      output["fontSize"] = .number(number)
    } else if let value = output["fontSize"], WebsiteConfigNumbers.coerce(value) < 0 {
      output["fontSize"] = .number(1)
    }
    if case .array(let values) = output["accountChart"], values.count != 4 {
      output["accountChart"] = .array(Array(repeating: .string("on"), count: 4))
    }
    if case .number(let value) = output["minAccCustom"], value > 100 {
      output["minAccCustom"] = .number(100)
    }
    if case .array(var values) = output["customThemeColors"], values.count == 9 {
      values.insert(.string("#000000"), at: 4)
      output["customThemeColors"] = .array(values)
    }
    if case .array(let values) = output["customBackgroundFilter"], values.count == 5 {
      output["customBackgroundFilter"] = .array(Array(values.prefix(4)))
    }
    if case .number(let value) = output["quoteLength"] {
      output["quoteLength"] = .array(value == -1 ? [0, 1, 2, 3].map { .number(Double($0)) } : [.number(value)])
    }
    if let value = output["tapeMargin"] {
      let number = WebsiteConfigNumbers.coerce(value)
      if number < 10 { output["tapeMargin"] = .number(10) }
      else if number > 90 { output["tapeMargin"] = .number(90) }
    }
    if let value = output["maxLineWidth"] {
      let number = WebsiteConfigNumbers.coerce(value)
      if number < 20, value != .number(0) { output["maxLineWidth"] = .number(20) }
      else if number > 1000 { output["maxLineWidth"] = .number(1000) }
    }
    if let legacy = output["keymapShowTopRow"], output["keymapKeys"] == nil {
      switch legacy {
      case .string("never"), .string("layout"): output["keymapKeys"] = .string("minimal")
      case .string("always"): output["keymapKeys"] = .string("minimal_numrow")
      default: break
      }
      output.removeValue(forKey: "keymapShowTopRow")
    }
    return output
  }
}

/// Numeric rules used by the website's legacy replacement stage, not Swift's
/// locale-dependent UI entry or a JavaScript runtime embedded in the product.
private enum WebsiteConfigNumbers {
  // ECMAScript whitespace deliberately excludes U+0085.
  static let whitespace = CharacterSet(charactersIn:
    "\u{0009}\u{000A}\u{000B}\u{000C}\u{000D}\u{0020}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}")

  static func prefix(_ value: String, pattern: String) -> String? {
    let trimmed = value.trimmingCharacters(in: whitespace)
    guard let range = trimmed.range(of: pattern, options: .regularExpression) else { return nil }
    return String(trimmed[range])
  }

  static func floatPrefix(_ value: String) -> Double {
    guard let token = prefix(value,
      pattern: #"^[+-]?(?:Infinity|(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][+-]?[0-9]+)?)"#)
    else { return .nan }
    return floating(token)
  }

  static func integerPrefix(_ value: String) -> Double {
    var text = value.trimmingCharacters(in: whitespace)
    let negative = text.first == "-"
    if text.first == "+" || negative { text.removeFirst() }
    let magnitude: Double
    if text.hasPrefix("0x") || text.hasPrefix("0X") {
      let remainder = String(text.dropFirst(2))
      guard remainder.first?.isASCII == true, remainder.first?.isHexDigit == true,
        let digits = prefix(remainder, pattern: #"^[0-9a-fA-F]+"#)
      else { return .nan }
      magnitude = Double("0x" + digits + "p0") ?? .nan
    } else {
      guard let digits = prefix(text, pattern: #"^[0-9]+"#), text.first?.isASCII == true,
        text.first?.isNumber == true else { return .nan }
      magnitude = Double(digits) ?? .nan
    }
    return negative ? -magnitude : magnitude
  }

  static func coerce(_ value: WebsiteConfigValue) -> Double {
    switch value {
    case .null: return 0
    case .bool(let value): return value ? 1 : 0
    case .number(let value): return value
    case .object, .objectCodeUnits: return .nan
    case .stringCodeUnits(let units): return coerce(.string(String(decoding: units, as: UTF16.self)))
    case .array(let values): return coerce(.string(values.map(arrayText).joined(separator: ",")))
    case .string(let value):
      let text = value.trimmingCharacters(in: whitespace)
      if text.isEmpty { return 0 }
      if text.hasPrefix("0x") || text.hasPrefix("0X") {
        guard text.range(of: #"^0[xX][0-9a-fA-F]+$"#, options: .regularExpression) != nil else { return .nan }
        return Double(text + "p0") ?? .nan
      }
      if text.hasPrefix("0b") || text.hasPrefix("0B") || text.hasPrefix("0o") || text.hasPrefix("0O") {
        let binary = text.lowercased().hasPrefix("0b")
        let digits = String(text.dropFirst(2))
        guard !digits.isEmpty, digits.allSatisfy({ (binary ? "01" : "01234567").contains($0) }) else { return .nan }
        let bits = binary ? digits : digits.map { String(Int(String($0))!, radix: 2).leftPaddedToThreeBits }.joined()
        let padded = String(repeating: "0", count: (4 - bits.count % 4) % 4) + bits
        let characters = Array(padded)
        let hex = stride(from: 0, to: characters.count, by: 4).map {
          String(Int(String(characters[$0..<($0 + 4)]), radix: 2)!, radix: 16)
        }.joined()
        return Double("0x" + hex + "p0") ?? .nan
      }
      guard text.range(of: #"^[+-]?(?:Infinity|(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][+-]?[0-9]+)?)$"#,
        options: .regularExpression) != nil else { return .nan }
      return floating(text)
    }
  }

  static func floating(_ token: String) -> Double {
    if token == "Infinity" || token == "+Infinity" { return .infinity }
    if token == "-Infinity" { return -.infinity }
    return Double(token) ?? .nan
  }

  static func arrayText(_ value: WebsiteConfigValue) -> String {
    switch value {
    case .null: ""
    case .bool(let value): value ? "true" : "false"
    case .number(let value): value.isNaN ? "NaN" : value == .infinity ? "Infinity"
      : value == -.infinity ? "-Infinity" : String(value)
    case .string(let value): value
    case .stringCodeUnits(let units): String(decoding: units, as: UTF16.self)
    case .array(let values): values.map(arrayText).joined(separator: ",")
    case .object, .objectCodeUnits: "[object Object]"
    }
  }
}

private extension String {
  var leftPaddedToThreeBits: String { String(repeating: "0", count: 3 - count) + self }
}
