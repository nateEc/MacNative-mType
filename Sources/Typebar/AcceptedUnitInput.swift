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
  /// Navigation cleared the element, but the last event still owns this
  /// finite field's validation snapshot until another input event replaces it.
  private(set) var terminalElementCleared = false
  private var retiredFields: [Int: [Entry]] = [:]
  var fieldIndex: Int { starts.count - 1 }
  var activeCount: Int { terminalElementCleared ? 0 : entries.count - starts.last! }
  var validationCount: Int { entries.count - starts.last! }
  var lastCommits: Bool { entries.last?.commits == true }
  var submittedFieldIndex: Int { fieldIndex - (terminalElementCleared ? 0 : 1) }
  var completedFieldCount: Int { fieldIndex + (terminalElementCleared ? 1 : 0) }
  var units: [UInt16] { entries.map(\.unit) }

  mutating func append(_ entry: Entry, advances: Bool = true) {
    retiredFields[fieldIndex] = nil
    entries.append(entry)
    if entry.commits {
      if advances { starts.append(entries.count) }
      else { terminalElementCleared = true }
    }
  }

  /// The next logged action replaces the cleared element, not its snapshot.
  /// Manual regression retains the abandoned field's navigation snapshot,
  /// not the separately projected saved history or source scoring counts.
  mutating func discardClearedTerminalField(retainsHistory: Bool = false) -> Int {
    guard terminalElementCleared else { return 0 }
    let range = range(fieldIndex)
    if retainsHistory { retiredFields[fieldIndex] = Array(entries[range]) }
    entries.removeLast(range.count)
    terminalElementCleared = false
    return range.count
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
    if withoutCommit, end > start, entries[end - 1].commits,
      entries[end - 1].unit == 32 || entries[end - 1].unit == 10 { end -= 1 }
    return start..<end
  }

  func field(_ index: Int, withoutCommit: Bool = false) -> [UInt16] {
    if index > fieldIndex, let retired = retiredFields[index] { return retired.map(\.unit) }
    return entries[range(index, withoutCommit: withoutCommit)].map(\.unit)
  }

  func burst(_ index: Int) -> Int? {
    let range = range(index)
    guard !range.isEmpty else { return nil }
    let elapsed = entries[range.upperBound - 1].date.timeIntervalSince(entries[range.lowerBound].date)
    guard elapsed > 0 else { return nil }
    let last = entries[range.upperBound - 1].unit
    let count = range.count + (last == 32 || last == 10 ? 0 : 1)
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
  let noSpace: Bool

  init(_ text: String, buildsASCIICatalog: Bool = false, noSpaceWords: [String]? = nil) {
    requiresUnitInput = text.utf8.contains { $0 > 127 || $0 == 13 }
    hasNewline = text.utf8.contains(10)
    noSpace = noSpaceWords.map { !$0.isEmpty && $0.joined().utf16.elementsEqual(text.utf16) } ?? false
    // A growing ASCII prompt has no unit/glyph ambiguity. Do not rebuild an
    // unused full catalog on each chunk; a later Unicode input builds it once.
    guard requiresUnitInput || buildsASCIICatalog || noSpace else {
      units = []; glyphs = []; fields = []
      return
    }
    units = Array(text.utf16)
    glyphs = requiresUnitInput ? text.enumerated().flatMap { index, character in
      Array(repeating: index, count: String(character).utf16.count)
    } : Array(units.indices)
    if noSpace, let noSpaceWords {
      var start = 0
      fields = noSpaceWords.map { word in
        let end = start + word.utf16.count
        defer { start = end }
        return start..<end
      }
      return
    }
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
    let unitIndex = min(range.lowerBound + position,
      hasCommit || noSpace && !range.isEmpty ? end - 1 : end)
    return glyphs.indices.contains(unitIndex) ? glyphs[unitIndex] : endGlyph
  }
}
