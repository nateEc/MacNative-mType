import Foundation

enum WebsiteConfigNativeStateError: Error, Equatable {
  case invalidEnvelope, unsupportedVersion, invalidFields, invalidValue, tooLarge
}

/// Dedicated local preference format, not website JSON or a Typebar backup.
/// A successful decode proves schema-level retention, not resource admission
/// or that the decoded state can already be applied to the native interface.
@MainActor
enum WebsiteConfigNativeStateCodec {
  static let kind = "typebar.website-config-state"
  static let version = 1
  static let maximumBytes = 8_388_608
  static func encode(_ runtime: [String: WebsiteConfigValue]) throws -> Data {
    try validate(runtime)
    var budget = maximumBytes - 256
    func charge(_ count: Int) throws {
      guard count <= budget else { throw WebsiteConfigNativeStateError.tooLarge }
      budget -= count
    }
    func node(_ value: WebsiteConfigValue, depth: Int = 0) throws -> WebsiteConfigValue {
      if let units = value.stringUnits {
        guard units.count <= budget / 4 else { throw WebsiteConfigNativeStateError.tooLarge }
        try charge(units.count * 4 + 8)
        let digits = Array("0123456789abcdef".utf8)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(units.count * 4)
        for unit in units {
          for shift in [12, 8, 4, 0] { bytes.append(digits[Int((unit >> shift) & 15)]) }
        }
        return .array([.string("s"), .string(String(decoding: bytes, as: UTF8.self))])
      }
      switch value {
      case .bool(let flag):
        try charge(11)
        return .array([.string("b"), .bool(flag)])
      case .number(let number):
        try charge(24)
        let hex = String(number.bitPattern, radix: 16)
        return .array([.string("n"), .string(String(repeating: "0", count: 16 - hex.count) + hex)])
      case .array(let values):
        guard depth == 0 else { throw WebsiteConfigNativeStateError.invalidValue }
        try charge(8 + values.count)
        return .array([.string("a"), .array(try values.map { try node($0, depth: depth + 1) })])
      default: throw WebsiteConfigNativeStateError.invalidValue
      }
    }
    let fields = try runtime.keys.sorted().map { key -> WebsiteConfigValue in
      try charge(key.utf8.count + 6)
      return .array([.string(key), try node(runtime[key]!)])
    }
    // Arrays throughout: no object keys can be silently merged by JSON parsing.
    let envelope = WebsiteConfigValue.array([.string(kind), .number(Double(version)), .array(fields)])
    let data = Data(WebsiteConfigJSONWriter.write(envelope).utf8)
    guard data.count <= maximumBytes else { throw WebsiteConfigNativeStateError.tooLarge }
    return data
  }

  static func decode(_ data: Data) throws -> [String: WebsiteConfigValue] {
    guard data.count <= maximumBytes else { throw WebsiteConfigNativeStateError.tooLarge }
    guard let text = String(data: data, encoding: .utf8),
      let root = try? WebsiteConfigJSONReader.read(text, maximumBytes: maximumBytes),
      case .array(let envelope) = root, envelope.count == 3, envelope[0] == .string(kind) else {
      throw WebsiteConfigNativeStateError.invalidEnvelope
    }
    guard envelope[1] == .number(Double(version)) else { throw WebsiteConfigNativeStateError.unsupportedVersion }
    guard case .array(let fields) = envelope[2] else { throw WebsiteConfigNativeStateError.invalidEnvelope }
    func hex(_ bytes: ArraySlice<UInt8>) throws -> UInt64 {
      var result: UInt64 = 0
      for byte in bytes {
        let digit: UInt8
        switch byte {
        case 48...57: digit = byte - 48
        case 97...102: digit = byte - 87
        default: throw WebsiteConfigNativeStateError.invalidValue
        }
        result = (result << 4) | UInt64(digit)
      }
      return result
    }
    func node(_ value: WebsiteConfigValue, depth: Int = 0) throws -> WebsiteConfigValue {
      guard case .array(let pair) = value, pair.count == 2, case .string(let tag) = pair[0] else {
        throw WebsiteConfigNativeStateError.invalidValue
      }
      switch tag {
      case "s":
        guard case .string(let text) = pair[1] else { throw WebsiteConfigNativeStateError.invalidValue }
        let bytes = Array(text.utf8)
        guard bytes.count.isMultiple(of: 4) else { throw WebsiteConfigNativeStateError.invalidValue }
        let units = try stride(from: 0, to: bytes.count, by: 4).map { UInt16(try hex(bytes[$0..<($0 + 4)])) }
        return .string(units: units)
      case "n":
        guard case .string(let text) = pair[1], text.utf8.count == 16 else { throw WebsiteConfigNativeStateError.invalidValue }
        return .number(Double(bitPattern: try hex(Array(text.utf8)[...])))
      case "b":
        guard case .bool = pair[1] else { throw WebsiteConfigNativeStateError.invalidValue }
        return pair[1]
      case "a":
        guard depth == 0, case .array(let values) = pair[1] else { throw WebsiteConfigNativeStateError.invalidValue }
        return .array(try values.map { try node($0, depth: depth + 1) })
      default: throw WebsiteConfigNativeStateError.invalidValue
      }
    }
    let schema = WebsiteConfigSchema(catalogs: WebsiteConfigNativeProfile.catalogs)
    guard fields.count == schema.keys.count else { throw WebsiteConfigNativeStateError.invalidFields }
    var runtime: [String: WebsiteConfigValue] = [:]
    for field in fields {
      guard case .array(let pair) = field, pair.count == 2, case .string(let key) = pair[0],
        key.utf8.allSatisfy({ $0 < 128 }), schema.keys.contains(key), runtime[key] == nil else {
        throw WebsiteConfigNativeStateError.invalidFields
      }
      runtime[key] = try node(pair[1])
    }
    try validate(runtime)
    return runtime
  }

  private static func validate(_ runtime: [String: WebsiteConfigValue]) throws {
    let schema = WebsiteConfigSchema(catalogs: WebsiteConfigNativeProfile.catalogs)
    guard schema.keys.count == 94, Set(runtime.keys) == schema.keys,
      runtime.allSatisfy({ schema.accepts($0.value, for: $0.key) }) else {
      throw WebsiteConfigNativeStateError.invalidFields
    }
  }
}
