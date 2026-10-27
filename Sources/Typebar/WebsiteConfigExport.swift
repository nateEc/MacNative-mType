import Foundation

@MainActor enum WebsiteConfigExport {
  enum Surface { case command, settings }
  enum Failure: Error { case incompleteConfiguration, unsupportedValue }
  static func draft(in page: PracticePageSessionState) -> WebsiteConfigNativeDraft? {
    if let receipt = page.sharedReceipt, page.savedApplication == nil {
      return try? .init(received: receipt.outcome, pointsPerRem: receipt.basePointsPerRem)
    }
    return page.savedApplication?.draft ?? page.configurationDeparture?.draft ?? page.presentation?.publication.draft
  }
  static func json(in page: PracticePageSessionState, surface: Surface) throws -> String {
    if let receipt = page.sharedReceipt, page.savedApplication == nil {
      return try json(values: surface == .command ? receipt.outcome.state.runtime : receipt.outcome.state.settingsStore)
    }
    guard let draft = draft(in: page) else { throw Failure.incompleteConfiguration }
    return try json(draft, surface: surface)
  }
  static func copySettings(in page: PracticePageSessionStore, using exporter: WebsiteConfigClipboardExport) {
    exporter.copy {
      try json(in: page.state, surface: .settings)
    }
  }
  static func values(_ draft: WebsiteConfigNativeDraft, surface: Surface) -> [String: WebsiteConfigValue] {
    surface == .command ? draft.projection.runtime : draft.settingsStoreValues
  }
  static func json(_ draft: WebsiteConfigNativeDraft, surface: Surface) throws -> String {
    try json(values: values(draft, surface: surface))
  }
  static func json(values: [String: WebsiteConfigValue]) throws -> String {
    let order = try WebsiteConfigNativeProfile.defaultDocument().orderedKeys
    guard Set(values.keys) == Set(order) else { throw Failure.incompleteConfiguration }
    return "{" + (try order.map { key in quoted(Array(key.utf16)) + ":" + (try write(values[key]!)) }).joined(separator: ",") + "}"
  }
  private static func write(_ value: WebsiteConfigValue) throws -> String {
    if let units = value.stringUnits { return quoted(units) }
    switch value {
    case .null: return "null"
    case .bool(let flag): return flag ? "true" : "false"
    case .number(let number): return number.isFinite ? WebsiteNumberText.decimal(number) : "null"
    case .array(let values): return "[" + (try values.map(write)).joined(separator: ",") + "]"
    default: throw Failure.unsupportedValue
    }
  }
  private static func quoted(_ units: [UInt16]) -> String {
    var text = "\"", index = 0
    while index < units.count {
      let unit = units[index]
      if (0xd800...0xdbff).contains(unit), index + 1 < units.count,
        (0xdc00...0xdfff).contains(units[index + 1]) {
        let scalar = 0x10000 + (UInt32(unit) - 0xd800) * 0x400 + UInt32(units[index + 1]) - 0xdc00
        text.unicodeScalars.append(UnicodeScalar(scalar)!); index += 2; continue
      }
      switch unit {
      case 34: text += "\\\""
      case 92: text += "\\\\"
      case 8: text += "\\b"
      case 9: text += "\\t"
      case 10: text += "\\n"
      case 12: text += "\\f"
      case 13: text += "\\r"
      case 0...31, 0xd800...0xdfff:
        let hex = String(unit, radix: 16); text += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
      default: text.unicodeScalars.append(UnicodeScalar(unit)!)
      }
      index += 1
    }
    return text + "\""
  }
}
