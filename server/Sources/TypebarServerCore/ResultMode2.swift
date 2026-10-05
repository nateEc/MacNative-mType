import Foundation

/// Native wire identities, not the upstream numeric quote catalogue. Custom
/// limits intentionally share one bucket, as the pinned getMode2 does.
enum ResultMode2Policy {
  static func isValidOwnedQuoteID(_ id: String) -> Bool {
    (1...100).contains(id.utf8.count) && id.unicodeScalars.allSatisfy {
      CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
        || CharacterSet.nonBaseCharacters.contains($0) || [45, 46, 95].contains($0.value)
    }
  }
  static func isValid(_ value: String, mode: String) -> Bool {
    switch mode {
    case "time", "words":
      guard let number = Int(value), String(number) == value else { return false }
      return (mode == "time" ? 5...3_600 : 1...1_000).contains(number)
    case "custom", "zen": return value == mode
    case "quote":
      if value.hasPrefix("typebar:utf8:") {
        let hex = Array(value.dropFirst(13).utf8)
        guard !hex.isEmpty, hex.count <= 200, hex.count.isMultiple(of: 2),
          hex.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return false }
        let bytes = stride(from: 0, to: hex.count, by: 2).map { index in
          UInt8(String(bytes: hex[index...index+1], encoding: .utf8)!, radix: 16)!
        }
        guard let id = String(bytes: bytes, encoding: .utf8), bytes.contains(where: { $0 >= 128 }) else { return false }
        return isValidOwnedQuoteID(id)
      }
      if value.hasPrefix("typebar:") {
        let id = String(value.dropFirst(8))
        return (1...100).contains(id.utf8.count)
          && id.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0)
            || (97...122).contains($0) || [45, 46, 95].contains($0) }
      }
      guard value.hasPrefix("community:"), let id = UUID(uuidString: String(value.dropFirst(10))) else { return false }
      return value == "community:" + id.uuidString.lowercased()
    default: return false
    }
  }
  static func resolved(mode: String, explicit: String?, duration: Int?, words: Int?) -> String? {
    if let explicit { return isValid(explicit, mode: mode) ? explicit : nil }
    switch mode {
    case "time": return duration.map(String.init)
    case "words": return words.map(String.init)
    case "custom", "zen": return mode
    default: return nil // Historical quote titles cannot recover identities.
    }
  }
  static func agrees(_ value: String, mode: String, duration: Int?, words: Int?) -> Bool {
    isValid(value, mode: mode) && (mode != "time" || value == duration.map(String.init))
      && (mode != "words" || value == words.map(String.init))
  }
}
