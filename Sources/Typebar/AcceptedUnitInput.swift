import Foundation

/// Accepted input, not a rendering string. Unpaired UTF-16 units are legal
/// intermediate states; decoding is exclusively a presentation operation.
struct AcceptedUnitInput {
  struct Entry {
    let unit: UInt16
    let target: Int?
    let date: Date
    let forced: Bool
    let extra: Bool
    let commits: Bool
  }

  private(set) var entries: [Entry] = []
  private(set) var starts = [0]
  var fieldIndex: Int { starts.count - 1 }
  var activeCount: Int { entries.count - starts.last! }
  var lastCommits: Bool { entries.last?.commits == true }
  var units: [UInt16] { entries.map(\.unit) }

  mutating func append(_ entry: Entry) {
    entries.append(entry)
    if entry.commits { starts.append(entries.count) }
  }

  @discardableResult
  mutating func removeLast() -> Entry? {
    guard let last = entries.last else { return nil }
    if last.commits { starts.removeLast() }
    return entries.removeLast()
  }

  func range(_ index: Int, withoutCommit: Bool = false) -> Range<Int> {
    guard starts.indices.contains(index) else { return 0..<0 }
    let start = starts[index]
    var end = starts.indices.contains(index + 1) ? starts[index + 1] : entries.count
    if withoutCommit, end > start, entries[end - 1].commits { end -= 1 }
    return start..<end
  }

  func field(_ index: Int, withoutCommit: Bool = false) -> [UInt16] {
    entries[range(index, withoutCommit: withoutCommit)].map(\.unit)
  }

  func burst(_ index: Int) -> Int? {
    let range = range(index)
    guard !range.isEmpty else { return nil }
    let elapsed = entries[range.upperBound - 1].date.timeIntervalSince(entries[range.lowerBound].date)
    guard elapsed > 0 else { return nil }
    let count = range.count + (entries[range.upperBound - 1].commits ? 0 : 1)
    let value = (Double(count) / 5 / elapsed * 60).rounded()
    guard value.isFinite, value >= 0, value < Double(Int.max) else { return nil }
    return Int(value)
  }
}

/// Source fields split literal separator units, independently of how macOS
/// groups their surrounding Unicode scalars into visible glyphs.
struct UnitInputTargets {
  let units: [UInt16]
  let glyphs: [Int]
  let fields: [Range<Int>]
  let requiresUnitInput: Bool
  let hasNewline: Bool

  init(_ text: String, buildsASCIICatalog: Bool = false) {
    requiresUnitInput = text.utf8.contains { $0 > 127 || $0 == 13 }
    hasNewline = text.utf8.contains(10)
    // A growing ASCII prompt has no unit/glyph ambiguity. Do not rebuild an
    // unused full catalog on each chunk; a later Unicode input builds it once.
    guard requiresUnitInput || buildsASCIICatalog else {
      units = []; glyphs = []; fields = []
      return
    }
    units = Array(text.utf16)
    glyphs = requiresUnitInput ? text.enumerated().flatMap { index, character in
      Array(repeating: index, count: String(character).utf16.count)
    } : Array(units.indices)
    var ranges: [Range<Int>] = []
    var start = 0
    for index in units.indices where units[index] == 32 || units[index] == 10 {
      ranges.append(start..<(index + 1))
      start = index + 1
    }
    if start < units.count || ranges.isEmpty { ranges.append(start..<units.count) }
    fields = ranges
  }

  func field(_ index: Int, withoutCommit: Bool = false) -> [UInt16] {
    guard fields.indices.contains(index) else { return [] }
    let range = fields[index]
    var end = range.upperBound
    if withoutCommit, end > range.lowerBound, units[end - 1] == 32 || units[end - 1] == 10 { end -= 1 }
    return Array(units[range.lowerBound..<end])
  }

  func cursor(field: Int, position: Int, endGlyph: Int) -> Int {
    guard fields.indices.contains(field) else { return endGlyph }
    let range = fields[field]
    let end = range.upperBound
    let hasCommit = end > range.lowerBound && (units[end - 1] == 32 || units[end - 1] == 10)
    let unitIndex = min(range.lowerBound + position, hasCommit ? end - 1 : end)
    return glyphs.indices.contains(unitIndex) ? glyphs[unitIndex] : endGlyph
  }
}
