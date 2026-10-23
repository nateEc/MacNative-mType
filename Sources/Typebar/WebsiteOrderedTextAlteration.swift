import Foundation

/// The imported sequence is observable: do not sort or deduplicate. UTF-16
/// intermediate values may be non-scalar and later become valid again.
enum WebsiteOrderedTextAlteration {
  static func apply(_ modifier: TestModifier, to units: [UInt16], wordIndex: Int, wordBound: Int,
    nextRandomCaseBit: () -> Bool) -> [UInt16] {
    switch modifier {
    case .backwards: return Array(units.reversed())
    case .uppercase: return WebsiteUnicode17Case.converted(units, upper: true)
    case .titleCase:
      var parts: [[UInt16]] = [[]]
      var wasSpace = false
      for unit in units {
        if unit == 32 {
          if !wasSpace { parts.append([]) }
          wasSpace = true
        } else { parts[parts.count - 1].append(unit); wasSpace = false }
      }
      return parts.enumerated().reduce(into: []) { output, item in
        if item.offset > 0 { output.append(32) }
        if let first = item.element.first {
          output += WebsiteUnicode17Case.converted([first], upper: true)
          output += item.element.dropFirst()
        }
      }
    case .alternatingCase:
      return units.enumerated().flatMap { offset, unit in
        WebsiteUnicode17Case.converted([unit], upper: !offset.isMultiple(of: 2))
      }
    case .randomCase:
      return scalars(units).flatMap { scalar in
        let upper = nextRandomCaseBit()
        return WebsiteUnicode17Case.converted(scalar, upper: upper)
      }
    case .rot13:
      return scalars(units).flatMap { scalar in
        let lower = WebsiteUnicode17Case.converted(scalar, upper: false)
        guard lower.count == 1, (97...122).contains(lower[0]) else { return scalar }
        let upper = WebsiteUnicode17Case.converted(scalar, upper: true) == scalar
        return [UInt16((lower[0] - 97 + 13) % 26 + (upper ? 65 : 97))]
      }
    case .doubleCharacters:
      return scalars(units).flatMap { scalar in
        scalar.count == 1 && [10, 13, 0x2028, 0x2029].contains(scalar[0]) ? scalar : scalar + scalar
      }
    case .messagingStyle:
      var lower = WebsiteUnicode17Case.converted(units, upper: false)
      if let last = lower.last, [33, 46, 63].contains(last) { lower[lower.count - 1] = 10 }
      return lower.reduce(into: []) { output, unit in
        if [40, 41, 46, 39, 34].contains(unit) { return }
        if unit == 10, output.last == 10 { return }
        output.append(unit)
      }
    case .morseStream:
      // Unsupported lone code units have no Morse symbol. They delimit valid
      // normalization runs but must not become replacement characters.
      return validRuns(units, map: MorseTextPolicy.transformed)
    case .underscoreSeparators: return wordIndex == wordBound - 1 ? units : units + [95]
    default: return units
    }
  }

  private static func scalars(_ units: [UInt16]) -> [[UInt16]] {
    var result: [[UInt16]] = [], index = 0
    while index < units.count {
      let paired = (0xD800...0xDBFF).contains(units[index]) && index + 1 < units.count
        && (0xDC00...0xDFFF).contains(units[index + 1])
      let end = index + (paired ? 2 : 1)
      result.append(Array(units[index..<end])); index = end
    }
    return result
  }

  private static func validRuns(_ units: [UInt16], map: (String) -> String) -> [UInt16] {
    var output: [UInt16] = [], run: [UInt16] = []
    func flush() {
      if !run.isEmpty { output += map(String(decoding: run, as: UTF16.self)).utf16; run.removeAll(keepingCapacity: true) }
    }
    for scalar in scalars(units) {
      if scalar.count == 1, (0xD800...0xDFFF).contains(scalar[0]) {
        flush()
      } else { run += scalar }
    }
    flush()
    return output
  }
}
