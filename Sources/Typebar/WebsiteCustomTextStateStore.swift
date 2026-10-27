import Foundation

enum WebsiteCustomTextStateRead: Equatable {
  case missing, available(WebsiteCustomTextSettings), unavailable
  var settings: WebsiteCustomTextSettings? {
    guard case .available(let settings) = self else { return nil }; return settings
  }
}

struct WebsiteCustomTextStateStore {
  static let storageKey = "websiteCustomTextState.v1"
  static let maximumBytes = 8_388_608
  private struct Record: Codable {
    let kind: String, version: Int, text: [Data], mode: String, limitMode: String, limitBits: String, pipe: Bool
  }
  private let defaults: UserDefaults
  init(defaults: UserDefaults) { self.defaults = defaults }
  func read() -> WebsiteCustomTextStateRead {
    guard defaults.object(forKey: Self.storageKey) != nil else { return .missing }
    guard let data = defaults.data(forKey: Self.storageKey), data.count <= Self.maximumBytes,
      let record = try? PropertyListDecoder().decode(Record.self, from: data),
      record.kind == "typebar.website-custom-text", record.version == 1,
      record.limitBits.utf8.count == 16,
      record.limitBits.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
      let bits = UInt64(record.limitBits, radix: 16), record.text.allSatisfy({ $0.count.isMultiple(of: 2) }) else { return .unavailable }
    let pieces = record.text.map { data -> WebsiteConfigValue in
      let bytes = Array(data)
      return .string(units: stride(from: 0, to: bytes.count, by: 2).map { UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8 })
    }
    guard let settings = try? WebsiteCustomTextSettings(value: .object(["text": .array(pieces),
      "mode": .string(record.mode), "limit": .object(["mode": .string(record.limitMode),
        "value": .number(Double(bitPattern: bits))]), "pipeDelimiter": .bool(record.pipe)])) else { return .unavailable }
    return .available(settings)
  }
  @discardableResult func save(_ settings: WebsiteCustomTextSettings) -> Bool {
    guard (try? WebsiteCustomTextSettings(value: settings.value)) != nil else { return false }
    switch read() {
    case .unavailable: return false
    case .available(let existing) where existing == settings && existing.limitValue.bitPattern == settings.limitValue.bitPattern: return true
    default: break
    }
    var budget = Self.maximumBytes - 1024
    var text: [Data] = []
    for value in settings.text {
      guard let units = value.stringUnits, units.count <= (budget - 32) / 2 else { return false }
      budget -= units.count * 2 + 32
      text.append(Data(units.flatMap { [UInt8(truncatingIfNeeded: $0), UInt8(truncatingIfNeeded: $0 >> 8)] }))
    }
    let bits = String(settings.limitValue.bitPattern, radix: 16)
    let record = Record(kind: "typebar.website-custom-text", version: 1, text: text, mode: settings.mode,
      limitMode: settings.limitMode, limitBits: String(repeating: "0", count: 16 - bits.count) + bits, pipe: settings.pipeDelimiter)
    let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
    guard let data = try? encoder.encode(record), data.count <= Self.maximumBytes else { return false }
    defaults.set(data, forKey: Self.storageKey)
    return defaults.data(forKey: Self.storageKey) == data
  }
}
