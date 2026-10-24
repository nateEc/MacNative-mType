import Foundation

/// Primitive getWord behavior for admitted website profiles. Entropy is
/// explicit; this does not replace the source wordset's preceding base draw.
enum WebsiteRandomWordGenerator {
  enum Kind: String, CaseIterable {
    case binary, hexadecimal, gibberish, ascii, specials
    var modifier: TestModifier {
      switch self {
      case .binary: .binaryStream; case .hexadecimal: .hexadecimalStream
      case .gibberish: .gibberishStream; case .ascii: .asciiStream
      case .specials: .specialCharacterStream
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

  static func word(_ kind: Kind, randomUnit: () -> Double) -> String? {
    func draw(_ count: Int, lower: Int = 0) -> Int? {
      let unit = randomUnit()
      guard unit.isFinite, unit >= 0, unit < 1 else { return nil }
      // Keep multiply, add and floor in this order. At the upper binary64
      // edge the positive lower bound can round into the next integer.
      return Int((unit * Double(count) + Double(lower)).rounded(.down))
    }
    switch kind {
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
}
