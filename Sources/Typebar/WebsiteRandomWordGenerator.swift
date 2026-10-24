import Foundation

/// Primitive getWord behavior for admitted website profiles. Entropy is
/// explicit; this does not replace the source wordset's preceding base draw.
enum WebsiteRandomWordGenerator {
  enum Kind: String, CaseIterable {
    case binary, hexadecimal, gibberish, ascii, specials
    case ipv4 = "IPv4", ipv6 = "IPv6"
    case accounting = "58008"
    var modifier: TestModifier {
      switch self {
      case .binary: .binaryStream; case .hexadecimal: .hexadecimalStream
      case .gibberish: .gibberishStream; case .ascii: .asciiStream
      case .specials: .specialCharacterStream
      case .ipv4: .ipv4Stream; case .ipv6: .ipv6Stream
      case .accounting: .accountingStream
      }
    }
  }
  static func selected(for configuration: TestConfiguration) -> Kind? {
    // The ordered website-stage marker already distinguishes this path from
    // historical native indexed streams, including configurations in records.
    guard configuration.websiteTextAlterationOrder != nil else { return nil }
    let matches = Kind.allCases.filter { configuration.modifiers.contains($0.modifier) }
    return matches.count == 1 ? matches.first : nil
  }

  static func usesCandidateStream(for configuration: TestConfiguration) -> Bool {
    selected(for: configuration) != nil || WebsiteArrowChart.isSelected(configuration)
      || WebsitePseudolangModel.isSelected(configuration)
  }

  static func word(_ kind: Kind, language: TypingLanguage = .english, randomUnit: () -> Double) -> String? {
    func draw(_ count: Int, lower: Int = 0) -> Int? {
      let unit = randomUnit()
      guard unit.isFinite, unit >= 0, unit < 1 else { return nil }
      // Keep multiply, add and floor in this order. At the upper binary64
      // edge the positive lower bound can round into the next integer.
      return Int((unit * Double(count) + Double(lower)).rounded(.down))
    }
    switch kind {
    case .accounting:
      guard let length = draw(7, lower: 1) else { return nil }
      let name = WebsiteLanguageIdentity.name(for: language) ?? ""
      let digitZero: UInt32 = name.hasPrefix("kurdish") ? 0x0660 : name.hasPrefix("nepali") ? 0x0966 : 0x0030
      var result = ""
      for index in 0..<length {
        guard let digit = draw(index == 0 ? 9 : 10, lower: index == 0 ? 1 : 0) else { return nil }
        result.unicodeScalars.append(UnicodeScalar(digitZero + UInt32(digit))!)
      }
      return result
    case .ipv4, .ipv6:
      let version6 = kind == .ipv6
      var parts: [String] = []
      for _ in 0..<(version6 ? 8 : 4) {
        guard let value = draw(version6 ? 65_536 : 256) else { return nil }
        let digits = String(value, radix: version6 ? 16 : 10)
        parts.append(version6 ? String(repeating: "0", count: 4 - digits.count) + digits : digits)
      }
      return parts.joined(separator: version6 ? ":" : ".")
    case .binary:
      guard let byte = draw(256) else { return nil }
      let digits = String(byte, radix: 2)
      return String(repeating: "0", count: 8 - digits.count) + digits
    case .hexadecimal:
      guard let size = draw(4, lower: 1) else { return nil }
      var result = ""
      for _ in 0..<size {
        guard let byte = draw(256) else { return nil }
        let digits = String(byte, radix: 16)
        result += String(repeating: "0", count: 2 - digits.count) + digits
      }
      return result
    case .gibberish, .ascii, .specials:
      guard let size = draw(kind == .ascii ? 10 : 7, lower: 1) else { return nil }
      // Printable punctuation, in the keyboard order of the getWord contract;
      // no word lists or other reference assets are used.
      let punctuation = Array("`~!@#$%^&*()-_=+{}[]'\"/\\|?;:><,.")
      var result = ""
      for _ in 0..<size {
        switch kind {
        case .gibberish:
          guard let code = draw(26) else { return nil }
          result.unicodeScalars.append(UnicodeScalar(97 + code)!)
        case .ascii:
          guard let code = draw(94) else { return nil }
          result.unicodeScalars.append(UnicodeScalar(33 + code)!)
        case .specials:
          guard let index = draw(punctuation.count) else { return nil }
          result.append(punctuation[index])
        default: return nil
        }
      }
      return result
    }
  }

  /// Punctuation of generated numeric words, using UTF-16 positions like the
  /// source handler. Its zero-neighbor check is specifically ASCII zero.
  static func punctuatedAccountingWord(_ word: String, randomUnit: () -> Double) -> String? {
    var units = Array(word.utf16)
    guard units.count > 3 else { return word }
    func unit() -> Double? {
      let value = randomUnit()
      return value.isFinite && value >= 0 && value < 1 ? value : nil
    }
    func position() -> Int? {
      guard let value = unit() else { return nil }
      return Int((value * Double(units.count - 2) + 1).rounded(.down))
    }
    guard let decimalChance = unit() else { return nil }
    if decimalChance < 0.5 {
      guard let index = position() else { return nil }
      units[index] = 46
    }
    guard let operatorChance = unit() else { return nil }
    if operatorChance < 0.75 {
      guard let index = position() else { return nil }
      let next = index + 1 < units.count ? units[index + 1] : nil
      if units[index - 1] != 46 && next != 46 && next != 48 {
        guard let value = unit() else { return nil }
        units[index] = Array("/*-+".utf16)[Int((value * 4).rounded(.down))]
      }
    }
    return String(decoding: units, as: UTF16.self)
  }

  /// Called only at the website punctuation stage. Plain IPv6 stays padded;
  /// punctuation compresses it even when the CIDR branch is not selected.
  static func punctuatedNetworkWord(_ word: String, kind: Kind, randomUnit: () -> Double) -> String? {
    guard kind == .ipv4 || kind == .ipv6 else { return nil }
    let version6 = kind == .ipv6
    let parts = word.components(separatedBy: version6 ? ":" : ".")
    let values = parts.compactMap { Int($0, radix: version6 ? 16 : 10) }
    guard parts.count == (version6 ? 8 : 4), values.count == parts.count,
      values.allSatisfy({ $0 >= 0 && $0 < (version6 ? 65_536 : 256) }) else { return nil }
    let chance = randomUnit()
    guard chance.isFinite, chance >= 0, chance < 1 else { return nil }
    var prefix: Int?
    if chance < 0.25 {
      let unit = randomUnit()
      guard unit.isFinite, unit >= 0, unit < 1 else { return nil }
      // Positive lower bound stays inside floor, including binary64 edges.
      prefix = Int((unit * (version6 ? 17 : 25) + (version6 ? 16 : 8)).rounded(.down)) * (version6 ? 4 : 1)
    }
    let address: String
    if version6 {
      var groups = values.map { UInt16($0) }
      if let prefix { groups = TypebarNetworkAddressStream.maskedIPv6(groups, prefix: prefix) }
      address = TypebarNetworkAddressStream.compressedIPv6(groups)
    } else {
      let octets = prefix.map { TypebarNetworkAddressStream.maskedIPv4(values, prefix: $0) } ?? values
      address = octets.map(String.init).joined(separator: ".")
    }
    return address + (prefix.map { "/\($0)" } ?? "")
  }
}
