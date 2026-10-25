import Foundation

enum WebsiteThresholdCommandInput {
  static func edits(for target: PracticeThresholdCommandTarget, raw: String,
    unit: TypingSpeedUnit) -> [WebsiteConfigThresholdEdit]? {
    switch target {
    case .minimumWpmOff: return [.speedMode(.off)]
    case .minimumAccuracyOff: return [.accuracyMode(.off)]
    case .minimumWordBurstOff: return [.burstMode(.off)]
    case .minimumWpmCustom:
      let value = toWpm(number(raw), unit: unit)
      guard !value.isNaN, value >= 0 else { return nil }
      return [.speedValue(value)]
    case .minimumAccuracyCustom:
      let value = number(raw)
      guard !value.isNaN, (0...100).contains(value) else { return nil }
      return [.accuracyValue(value)]
    case .minimumWordBurst(let mode):
      if raw.isEmpty { return [] }
      return [.burstMode(mode), .burstValue(toWpm(integerPrefix(raw), unit: unit))]
    }
  }

  static func toWpm(_ value: Double, unit: TypingSpeedUnit) -> Double {
    let factor: Double
    switch unit {
    case .wpm: factor = 1
    case .cpm: factor = 5
    case .wps: factor = 1.0 / 60.0
    case .cps: factor = 5.0 / 60.0
    case .wph: factor = 60
    }
    return value / factor
  }
  private static func trimmed(_ text: String) -> String {
    guard let units = WebsiteConfigValue.string(text).trimmingWebsiteString.stringUnits else { return text }
    return String(decoding: units, as: UTF16.self)
  }
  /// ECMAScript Number(string), including its empty, radix and nonfinite
  /// results. Admission/representability belongs to the actual setter.
  static func number(_ text: String) -> Double {
    let value = trimmed(text)
    if value.isEmpty { return 0 }
    if value == "Infinity" || value == "+Infinity" { return .infinity }
    if value == "-Infinity" { return -.infinity }
    let units = Array(value.utf16)
    if units.count > 2, units[0] == 48 {
      let radix: Int?
      switch units[1] { case 120, 88: radix = 16; case 98, 66: radix = 2; case 111, 79: radix = 8; default: radix = nil }
      if let radix {
        let digits = Array(units.dropFirst(2))
        guard digits.allSatisfy({ digit($0).map { $0 < radix } ?? false }) else { return .nan }
        return radixNumber(digits, radix: radix)
      }
    }
    let grammar = #"\A[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?\z"#
    guard value.range(of: grammar, options: .regularExpression) != nil else { return .nan }
    return Double(value) ?? .nan
  }
  static func integerPrefix(_ text: String) -> Double {
    var units = Array(trimmed(text).utf16), negative = false
    if units.first == 43 || units.first == 45 {
      negative = units.first == 45; units.removeFirst()
    }
    let radix = units.count >= 2 && units[0] == 48 && [88,120].contains(units[1]) ? 16 : 10
    if radix == 16 { units.removeFirst(2) }
    let digits = Array(units.prefix { digit($0).map { $0 < radix } ?? false })
    guard !digits.isEmpty else { return .nan }
    let result = radix == 16 ? radixNumber(digits, radix: 16) : Double(String(decoding: digits, as: UTF16.self)) ?? .nan
    return negative ? -result : result
  }
  private static func digit(_ unit: UInt16) -> Int? {
    switch unit {
    case 48...57: Int(unit - 48)
    case 65...70: Int(unit - 65) + 10
    case 97...102: Int(unit - 97) + 10
    default: nil
    }
  }
  private static func radixNumber(_ units: [UInt16], radix: Int) -> Double {
    if radix == 16 { return Double("0x" + String(decoding: units, as: UTF16.self) + "p0") ?? .nan }
    // Convert power-of-two radices exactly before binary64 rounding. Repeated
    // floating point accumulation can lose the final rounding bit.
    let width = radix == 2 ? 1 : 3, hex = Array("0123456789abcdef")
    var output = "", bits = (4 - (units.count * width) % 4) % 4, nibble = 0
    for unit in units {
      let value = Int(unit - 48)
      for shift in stride(from: width - 1, through: 0, by: -1) {
        nibble = (nibble << 1) | ((value >> shift) & 1); bits += 1
        if bits == 4 { output.append(hex[nibble]); bits = 0; nibble = 0 }
      }
    }
    return Double("0x" + output + "p0") ?? .nan
  }
}
