import Foundation

struct WebsiteConfigMember: Equatable, Sendable {
  var key: [UInt16]
  var value: WebsiteConfigValue
}

extension WebsiteConfigValue {
  var stringUnits: [UInt16]? {
    switch self {
    case .string(let value): Array(value.utf16)
    case .stringCodeUnits(let units): units
    default: nil
    }
  }

  var objectMembers: [WebsiteConfigMember]? {
    switch self {
    case .object(let values): values.map { .init(key: Array($0.key.utf16), value: $0.value) }
    case .objectCodeUnits(let members): members
    default: nil
    }
  }

  static func string(units: [UInt16]) -> Self {
    let scalar = String(decoding: units, as: UTF16.self)
    return scalar.utf16.elementsEqual(units) ? .string(scalar) : .stringCodeUnits(units)
  }

  static func object(members: [WebsiteConfigMember]) -> Self {
    var merged: [WebsiteConfigMember] = [], positions: [[UInt16]: Int] = [:]
    for member in members {
      if let index = positions[member.key] { merged[index].value = member.value }
      else { positions[member.key] = merged.count; merged.append(member) }
    }
    var scalar: [String: Self] = [:], spellings: [String: [UInt16]] = [:]
    for member in merged {
      let key = String(decoding: member.key, as: UTF16.self)
      guard key.utf16.elementsEqual(member.key), spellings[key].map({ $0 == member.key }) ?? true else {
        return .objectCodeUnits(merged)
      }
      scalar[key] = member.value; spellings[key] = member.key
    }
    return .object(scalar)
  }

  /// Config field names (including legacy aliases) are ASCII. Both source
  /// partial-strip and fallback migration ignore every other root name.
  /// Keep the complete raw object above; project only at the import boundary.
  var importFields: [String: Self]? {
    guard let members = objectMembers else { return nil }
    var result: [String: Self] = [:]
    for member in members where member.key.allSatisfy({ $0 < 128 }) {
      result[String(decoding: member.key, as: UTF16.self)] = member.value
    }
    return result
  }

  var trimmingWebsiteString: Self {
    guard let units = stringUnits else { return self }
    let whitespace: Set<UInt16> = [9, 10, 11, 12, 13, 32, 160, 5760, 8192, 8193, 8194, 8195,
      8196, 8197, 8198, 8199, 8200, 8201, 8202, 8232, 8233, 8239, 8287, 12288, 65279]
    let start = units.firstIndex { !whitespace.contains($0) } ?? units.count
    let end = units.lastIndex { !whitespace.contains($0) }.map { $0 + 1 } ?? start
    return .string(units: Array(units[start..<end]))
  }
}

/// Semantic website JSON transport. Escaping preserves non-scalar code units;
/// nonfinite numbers and negative zero follow JSON.stringify's value behavior.
/// Key order/number spelling are deterministic, not byte-identical JS output.
enum WebsiteConfigJSONWriter {
  static func write(_ value: WebsiteConfigValue, asciiOnly: Bool = true) -> String {
    if let units = value.stringUnits { return quoted(units, asciiOnly: asciiOnly) }
    if let members = value.objectMembers {
      let unique = Dictionary(members.map { ($0.key, $0.value) }, uniquingKeysWith: { _, new in new })
      return "{" + unique.keys.sorted { $0.lexicographicallyPrecedes($1) }
        .map { quoted($0, asciiOnly: asciiOnly) + ":" + write(unique[$0]!, asciiOnly: asciiOnly) }.joined(separator: ",") + "}"
    }
    switch value {
    case .null: return "null"
    case .bool(let flag): return flag ? "true" : "false"
    case .number(let number): return !number.isFinite ? "null" : number == 0 ? "0"
      : asciiOnly ? String(number) : WebsiteNumberText.decimal(number)
    case .array(let values): return "[" + values.map { write($0, asciiOnly: asciiOnly) }.joined(separator: ",") + "]"
    default: preconditionFailure("String and object cases are handled above")
    }
  }

  private static func quoted(_ units: [UInt16], asciiOnly: Bool) -> String {
    var result = "\"", index = 0
    while index < units.count {
      let unit = units[index]
      if !asciiOnly, (0xd800...0xdbff).contains(unit), index + 1 < units.count,
        (0xdc00...0xdfff).contains(units[index + 1]) {
        let scalar = 0x10000 + (UInt32(unit) - 0xd800) * 0x400 + UInt32(units[index + 1]) - 0xdc00
        result.unicodeScalars.append(UnicodeScalar(scalar)!); index += 2; continue
      }
      switch unit {
      case 34: result += "\\\""
      case 92: result += "\\\\"
      case 8 where !asciiOnly: result += "\\b"
      case 9 where !asciiOnly: result += "\\t"
      case 10 where !asciiOnly: result += "\\n"
      case 12 where !asciiOnly: result += "\\f"
      case 13 where !asciiOnly: result += "\\r"
      case 32...126: result.unicodeScalars.append(UnicodeScalar(unit)!)
      case 127...0xffff where !asciiOnly && !(0xd800...0xdfff).contains(unit):
        result.unicodeScalars.append(UnicodeScalar(unit)!)
      default:
        let hex = String(unit, radix: 16)
        result += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
      }
      index += 1
    }
    return result + "\""
  }
}
