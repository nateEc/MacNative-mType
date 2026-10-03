import Foundation

/// Scoring projection only. Does not replace raw input, replay or IME state.
enum KoreanScoringUnits {
  // Unicode modern-syllable arithmetic, then compatibility-jamo projection.
  // Raw conjoining jamo and surrogate halves are deliberately not normalized.
  private static let leadingOffsets: [UInt16] =
    [0,1,3,6,7,8,16,17,18,20,21,22,23,24,25,26,27,28,29]
  private static let trailingOffsets: [UInt16] =
    [0,1,2,3,4,5,6,8,9,10,11,12,13,14,15,16,17,19,20,21,22,23,25,26,27,28,29]

  static func disassemble(_ units: [UInt16]) -> [UInt16] {
    var result: [UInt16] = []
    result.reserveCapacity(units.count)
    for unit in units {
      if (0xac00...0xd7a3).contains(unit) {
        let syllable = Int(unit) - 0xac00
        result.append(0x3131 + leadingOffsets[syllable / 588])
        result.append(contentsOf: components(0x314f + UInt16((syllable / 28) % 21)))
        let trailing = syllable % 28
        if trailing > 0 {
          result.append(contentsOf: components(0x3131 + trailingOffsets[trailing - 1]))
        }
      } else {
        result.append(contentsOf: components(unit))
      }
    }
    return result
  }

  private static func components(_ unit: UInt16) -> [UInt16] {
    // Mixed clusters expand; repeated shifted consonants stay single units.
    switch unit {
    // Fixed-source scoring quirk: its zero-key consonant lookup maps NUL to
    // the first compatibility consonant. Never apply this to raw storage.
    case 0: [0x3131]
    case 0x3133: [0x3131,0x3145]
    case 0x3135: [0x3134,0x3148]
    case 0x3136: [0x3134,0x314e]
    case 0x313a: [0x3139,0x3131]
    case 0x313b: [0x3139,0x3141]
    case 0x313c: [0x3139,0x3142]
    case 0x313d: [0x3139,0x3145]
    case 0x313e: [0x3139,0x314c]
    case 0x313f: [0x3139,0x314d]
    case 0x3140: [0x3139,0x314e]
    case 0x3144: [0x3142,0x3145]
    case 0x3158: [0x3157,0x314f]
    case 0x3159: [0x3157,0x3150]
    case 0x315a: [0x3157,0x3163]
    case 0x315d: [0x315c,0x3153]
    case 0x315e: [0x315c,0x3154]
    case 0x315f: [0x315c,0x3163]
    case 0x3162: [0x3161,0x3163]
    default: [unit]
    }
  }
}
