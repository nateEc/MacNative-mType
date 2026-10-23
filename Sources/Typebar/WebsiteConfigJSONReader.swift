import Foundation

enum WebsiteConfigJSONReadError: Error, Equatable {
  case tooLarge, tooDeep, unsupportedUTF16, ambiguousObjectKey
  case invalidJSON(offset: Int)
}

/// Website JSON only. Native Typebar backup decoding is deliberately separate.
/// Resource bounds and non-scalar UTF-16 are explicit, not silent repair.
enum WebsiteConfigJSONReader {
  static let maximumBytes = 1_048_576
  static let maximumDepth = 128

  static func read(_ json: String) throws -> WebsiteConfigValue {
    guard json.utf8.count <= maximumBytes else { throw WebsiteConfigJSONReadError.tooLarge }
    var parser = Parser(bytes: Array(json.utf8))
    let value = try parser.value(depth: 0)
    parser.space()
    guard parser.offset == parser.bytes.count else { throw parser.invalid() }
    return value
  }

  private struct Parser {
    let bytes: [UInt8]
    var offset = 0
    var next: UInt8? { offset < bytes.count ? bytes[offset] : nil }
    func invalid() -> WebsiteConfigJSONReadError { .invalidJSON(offset: offset) }
    mutating func space() {
      while let byte = next, [9, 10, 13, 32].contains(byte) { offset += 1 }
    }
    mutating func consume(_ byte: UInt8) -> Bool {
      guard next == byte else { return false }
      offset += 1; return true
    }
    mutating func value(depth: Int) throws -> WebsiteConfigValue {
      space()
      guard depth <= WebsiteConfigJSONReader.maximumDepth else { throw WebsiteConfigJSONReadError.tooDeep }
      switch next {
      case 34: return .string(try string())
      case 123:
        offset += 1; space()
        var object: [String: WebsiteConfigValue] = [:]
        var spellings: [String: [UInt16]] = [:]
        if consume(125) { return .object(object) }
        while true {
          let key = try string()
          // Swift canonical equivalence must not merge different JS keys.
          let units = Array(key.utf16)
          if let old = spellings[key], old != units {
            throw WebsiteConfigJSONReadError.ambiguousObjectKey
          }
          spellings[key] = units
          space(); guard consume(58) else { throw invalid() }
          object[key] = try value(depth: depth + 1)
          space()
          if consume(125) { return .object(object) }
          guard consume(44) else { throw invalid() }
          space()
        }
      case 91:
        offset += 1; space()
        var array: [WebsiteConfigValue] = []
        if consume(93) { return .array(array) }
        while true {
          array.append(try value(depth: depth + 1)); space()
          if consume(93) { return .array(array) }
          guard consume(44) else { throw invalid() }
        }
      case 116: try literal("true"); return .bool(true)
      case 102: try literal("false"); return .bool(false)
      case 110: try literal("null"); return .null
      case .some(45), .some(48...57): return .number(try number())
      default: throw invalid()
      }
    }
    mutating func literal(_ text: String) throws {
      for byte in text.utf8 { guard consume(byte) else { throw invalid() } }
    }
    mutating func string() throws -> String {
      let start = offset
      guard consume(34) else { throw invalid() }
      while let byte = next {
        offset += 1
        if byte == 34 {
          do { return try JSONDecoder().decode(String.self, from: Data(bytes[start..<offset])) }
          catch { throw WebsiteConfigJSONReadError.unsupportedUTF16 }
        }
        guard byte >= 32 else { throw invalid() }
        if byte == 92 {
          guard let escape = next else { throw invalid() }
          offset += 1
          if escape == 117 {
            for _ in 0..<4 {
              guard let hex = next, (48...57).contains(hex) || (65...70).contains(hex) || (97...102).contains(hex) else { throw invalid() }
              offset += 1
            }
          } else if ![34, 47, 92, 98, 102, 110, 114, 116].contains(escape) { throw invalid() }
        }
      }
      throw invalid()
    }
    mutating func number() throws -> Double {
      let start = offset
      _ = consume(45)
      if !consume(48) {
        guard let byte = next, (49...57).contains(byte) else { throw invalid() }
        digits()
      }
      if consume(46) {
        guard let byte = next, (48...57).contains(byte) else { throw invalid() }
        digits()
      }
      if next == 101 || next == 69 {
        offset += 1
        if next == 43 || next == 45 { offset += 1 }
        guard let byte = next, (48...57).contains(byte) else { throw invalid() }
        digits()
      }
      guard let number = Double(String(decoding: bytes[start..<offset], as: UTF8.self)) else { throw invalid() }
      return number
    }
    mutating func digits() {
      while let byte = next, (48...57).contains(byte) { offset += 1 }
    }
  }
}
