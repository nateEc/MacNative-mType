import Foundation

/// Prepares a newly selected ordinary quote, not a persisted attempt or an
/// already prepared external stream. Interior Unicode whitespace and scalar
/// composition are deliberately retained; quote input is not custom input.
enum QuoteSourcePolicy {
  static func preparedText(_ source: String) -> String {
    let scalars = Array(source.unicodeScalars)
    var output: [Unicode.Scalar] = []
    output.reserveCapacity(scalars.count)
    var position = 0
    var pendingSpace = false
    while position < scalars.count {
      let scalar = scalars[position]
      position += 1
      switch scalar.value {
      case 0x20:
        pendingSpace = true
      case 0x0D, 0x0A:
        pendingSpace = false
        if scalar.value == 0x0D, position < scalars.count, scalars[position].value == 0x0A {
          position += 1
        }
        while position < scalars.count, scalars[position].value == 0x20 { position += 1 }
        // This generated separator is not part of the input being scanned.
        // A following newline must keep it, rather than merge blank lines.
        output.append("\n")
        output.append(" ")
      default:
        if pendingSpace { output.append(" "); pendingSpace = false }
        if scalar.value == 0x2026 { output.append(contentsOf: [".", ".", "."]) }
        else { output.append(scalar) }
      }
    }
    if pendingSpace { output.append(" ") }
    var lower = 0
    var upper = output.count
    while lower < upper, isBoundaryWhitespace(output[lower]) { lower += 1 }
    while upper > lower, isBoundaryWhitespace(output[upper - 1]) { upper -= 1 }
    return String(String.UnicodeScalarView(output[lower..<upper]))
  }

  // ECMAScript TrimString's WhiteSpace + LineTerminator, not Foundation's
  // broader whitespace set (which would also trim NEL). No interior trimming.
  private static func isBoundaryWhitespace(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A,
      0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: true
    default: false
    }
  }
}
