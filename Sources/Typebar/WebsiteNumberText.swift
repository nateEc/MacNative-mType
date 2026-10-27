/// Decimal input text for website-compatible commands. Keep Swift's shortest
/// round-tripping digits, but apply decimal/scientific notation independently.
/// This is display text, not a JSON encoder or a persistence migration.
enum WebsiteNumberText {
  static func decimal(_ value: Double) -> String {
    if value.isNaN { return "NaN" }
    if value.isInfinite { return value.sign == .minus ? "-Infinity" : "Infinity" }
    if value == 0 { return "0" }
    let pieces = String(value.magnitude).split(separator: "e")
    let mantissa = Array(pieces[0])
    let exponent = pieces.count == 2 ? Int(pieces[1])! : 0
    var point = (mantissa.firstIndex(of: ".") ?? mantissa.count) + exponent
    var digits = mantissa.filter { $0 != "." }
    while digits.first == "0" { digits.removeFirst(); point -= 1 }
    while digits.count > 1 && digits.last == "0" { digits.removeLast() }
    let body: String
    if point >= digits.count && point <= 21 {
      body = String(digits) + String(repeating: "0", count: point - digits.count)
    } else if point > 0 && point <= 21 {
      body = String(digits.prefix(point)) + "." + String(digits.dropFirst(point))
    } else if point > -6 && point <= 0 {
      body = "0." + String(repeating: "0", count: -point) + String(digits)
    } else {
      let power = point - 1
      body = String(digits.prefix(1)) + (digits.count > 1 ? "." + String(digits.dropFirst()) : "")
        + "e" + (power >= 0 ? "+" : "") + String(power)
    }
    return (value.sign == .minus ? "-" : "") + body
  }
}
