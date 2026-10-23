/// Locale-independent Unicode 17 default case conversion. This is versioned
/// independently of Foundation, and retains unsupported UTF-16 code units.
enum WebsiteUnicode17Case {
  static func converted(_ units: [UInt16], upper: Bool) -> [UInt16] {
    var points: [UInt32] = [], index = 0
    while index < units.count {
      let first = units[index]
      if (0xD800...0xDBFF).contains(first), index + 1 < units.count,
        (0xDC00...0xDFFF).contains(units[index + 1]) {
        points.append(0x10000 + (UInt32(first) - 0xD800) * 1024 + UInt32(units[index + 1]) - 0xDC00)
        index += 2
      } else { points.append(UInt32(first)); index += 1 }
    }
    let mapping = upper ? WebsiteUnicode17CaseData.upper : WebsiteUnicode17CaseData.lower
    var output: [UInt16] = []
    for (position, point) in points.enumerated() {
      let replacement: [UInt32]
      if !upper, point == 0x03A3, finalSigma(in: points, at: position) { replacement = [0x03C2] }
      else { replacement = mapping[point] ?? [point] }
      for value in replacement {
        if value <= 0xFFFF { output.append(UInt16(value)) }
        else {
          let adjusted = value - 0x10000
          output += [UInt16(0xD800 + adjusted / 1024), UInt16(0xDC00 + adjusted % 1024)]
        }
      }
    }
    return output
  }

  private static func finalSigma(in points: [UInt32], at index: Int) -> Bool {
    var before = index - 1
    while before >= 0, contains(points[before], in: WebsiteUnicode17CaseData.ignorable) { before -= 1 }
    guard before >= 0, contains(points[before], in: WebsiteUnicode17CaseData.cased) else { return false }
    var after = index + 1
    while after < points.count, contains(points[after], in: WebsiteUnicode17CaseData.ignorable) { after += 1 }
    return after == points.count || !contains(points[after], in: WebsiteUnicode17CaseData.cased)
  }

  private static func contains(_ point: UInt32, in ranges: [ClosedRange<UInt32>]) -> Bool {
    var low = 0, high = ranges.count
    while low < high {
      let middle = low + (high - low) / 2
      if point < ranges[middle].lowerBound { high = middle }
      else if point > ranges[middle].upperBound { low = middle + 1 }
      else { return true }
    }
    return false
  }
}
