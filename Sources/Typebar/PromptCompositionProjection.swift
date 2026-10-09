import Foundation

/// Global identity and ownership, not attributed text or a scoring buffer.
/// A presentation ID may replace one whole canonical glyph, but a partial
/// glyph or overflow always receives its own opaque negative ID. Aliases are
/// explicit relations for pace geometry, never duplicate text offsets.
struct PromptCompositionProjection {
  struct GlyphSlice: Equatable {
    let glyphID: Int
    let glyphUTF16Range: Range<Int>
    let glyphUTF16Count: Int
    var isWholeGlyph: Bool { glyphUTF16Range == 0..<glyphUTF16Count }
  }

  struct Cell {
    enum Role: Equatable { case original, fragment, composition(Int, matchesTarget: Bool) }
    let id: Int
    let displayUTF16: [UInt16]
    let sourceSlices: [GlyphSlice]
    let sourceFieldIndex: Int?
    let targetUTF16Range: Range<Int>?
    let role: Role
    var sourceGlyphOverride: TypingPromptGlyph? = nil
    var text: String { String(decoding: displayUTF16, as: UTF16.self) }
    var compositionIndex: Int? {
      if case .composition(let index, _) = role { return index }
      return nil
    }
    var matchesTarget: Bool {
      if case .composition(_, let correct) = role { return correct }
      return false
    }
  }

  struct Anchor: Equatable { let cellID: Int; let after: Bool }
  struct Field {
    let index: Int
    let targetUTF16Range: Range<Int>
    let cellIDs: [Int]
    let structuralReturnCount: Int
    var hasStructuralReturn: Bool { structuralReturnCount > 0 }
    let isRetired: Bool
    let isRemoved: Bool
  }

  let cells: [Cell]
  let fields: [Field]
  let canonicalAliases: [Int: [Int]]
  let caret: Anchor?
  let replacedTargetUTF16Range: Range<Int>
  let referenceLetterUnitIndex: Int
  var markedCells: [Cell] { cells.filter { $0.compositionIndex != nil } }

  init(glyphs: [TypingPromptGlyph], indices: [Int], targetGlyphCount: Int,
    field: PromptCompositionField, composition: String, style: CompositionDisplayStyle,
    canonicalCaret: Int?, zenPlaceholder: Int? = nil, extraOwners: [Int: Int] = [:],
    firstRetainedFieldIndex: Int = 0, removedFieldIndices: Set<Int> = [],
    glyphOverrides: [Int: TypingPromptGlyph] = [:]) {
    let plan = PromptCompositionPlan(field: field, composition: composition, style: style)
    referenceLetterUnitIndex = plan.referenceLetterUnitIndex
    let ranges = field.sourceFieldUTF16Ranges
    func isVisible(_ owner: Int?) -> Bool {
      owner.map { $0 >= firstRetainedFieldIndex && !removedFieldIndices.contains($0) } ?? true
    }
    func owner(at unit: Int) -> Int? {
      var low = 0, high = ranges.count
      while low < high {
        let middle = (low + high) / 2
        if ranges[middle].upperBound <= unit { low = middle + 1 } else { high = middle }
      }
      return ranges.indices.contains(low) && ranges[low].contains(unit) ? low : nil
    }
    var localStarts = [0]
    for character in String(decoding: field.targetUTF16, as: UTF16.self) {
      localStarts.append(localStarts.last! + String(character).utf16.count)
    }
    let lower = field.targetUTF16Range.lowerBound + localStarts[plan.replacedTargetRange.lowerBound]
    let upper = field.targetUTF16Range.lowerBound + localStarts[plan.replacedTargetRange.upperBound]
    replacedTargetUTF16Range = lower..<upper
    let showsMarked = !composition.isEmpty && isVisible(field.index)
    let visibleIDs = Set(indices)
    var nextVirtualID = -1
    func virtualID() -> Int { defer { nextVirtualID -= 1 }; return nextVirtualID }
    func sourceSlices(in localRange: Range<Int>) -> [GlyphSlice] {
      let slices = field.targetGlyphSlices
      var low = 0, high = slices.count
      while low < high {
        let middle = (low + high) / 2
        if slices[middle].fieldUTF16Range.upperBound <= localRange.lowerBound { low = middle + 1 }
        else { high = middle }
      }
      var output = [GlyphSlice]()
      while low < slices.count, slices[low].fieldUTF16Range.lowerBound < localRange.upperBound {
        let slice = slices[low]
        let start = max(localRange.lowerBound, slice.fieldUTF16Range.lowerBound)
        let end = min(localRange.upperBound, slice.fieldUTF16Range.upperBound)
        let glyphStart = slice.glyphUTF16Range.lowerBound + start - slice.fieldUTF16Range.lowerBound
        output.append(.init(glyphID: slice.glyphID, glyphUTF16Range: glyphStart..<(glyphStart + end - start),
          glyphUTF16Count: slice.glyphUTF16Count))
        low += 1
      }
      return output
    }
    var events: [Int: [Int]] = [:]
    for id in indices where id >= targetGlyphCount && id != zenPlaceholder {
      guard let owner = extraOwners[id], ranges.indices.contains(owner), isVisible(owner) else { continue }
      let range = ranges[owner]
      let gap = !range.isEmpty && field.sourceTargetUTF16[range.upperBound - 1] == 32 ? 1 : 0
      let point = showsMarked && owner == field.index ? lower : range.upperBound - gap
      events[point, default: []].append(id)
    }
    if showsMarked, events[lower] == nil { events[lower] = [] }
    let eventPoints = events.keys.sorted()
    var eventIndex = 0, output = [Cell]()
    func emitEvents(through unit: Int) {
      while eventIndex < eventPoints.count, eventPoints[eventIndex] <= unit {
        let point = eventPoints[eventIndex]
        for id in events[point] ?? [] {
          output.append(.init(id: id, displayUTF16: Array(String(glyphs[id].character).utf16),
            sourceSlices: [], sourceFieldIndex: extraOwners[id], targetUTF16Range: nil, role: .original))
        }
        if showsMarked, point == lower {
          for cell in plan.cells where cell.compositionIndex != nil {
            let sourceRange = cell.targetIndex.map { localStarts[$0]..<localStarts[$0 + 1] }
            let slices = sourceRange.map(sourceSlices) ?? []
            let id = slices.count == 1 && slices[0].isWholeGlyph && visibleIDs.contains(slices[0].glyphID)
              ? slices[0].glyphID : virtualID()
            output.append(.init(id: id, displayUTF16: Array(cell.text.utf16), sourceSlices: slices,
              sourceFieldIndex: field.index,
              targetUTF16Range: sourceRange.map {
                (field.targetUTF16Range.lowerBound + $0.lowerBound)..<(field.targetUTF16Range.lowerBound + $0.upperBound)
              }, role: .composition(cell.compositionIndex!, matchesTarget: cell.matchesTarget)))
          }
        }
        eventIndex += 1
      }
    }
    var cuts = Set(ranges.flatMap { [$0.lowerBound, $0.upperBound] })
    cuts.formUnion(eventPoints)
    if showsMarked { cuts.formUnion([lower, upper]) }
    let boundaries = cuts.sorted()
    var globalUnit = 0, boundaryIndex = 0
    for id in 0..<targetGlyphCount {
      let units = Array(String(glyphs[id].character).utf16)
      let start = globalUnit, end = start + units.count
      globalUnit = end
      guard visibleIDs.contains(id) else { continue }
      while boundaryIndex < boundaries.count, boundaries[boundaryIndex] <= start { boundaryIndex += 1 }
      var stops = [start]
      while boundaryIndex < boundaries.count, boundaries[boundaryIndex] < end {
        stops.append(boundaries[boundaryIndex]); boundaryIndex += 1
      }
      stops.append(end)
      for pair in zip(stops, stops.dropFirst()) {
        emitEvents(through: pair.0)
        let span = pair.0..<pair.1, sourceOwner = owner(at: pair.0)
        guard isVisible(sourceOwner), !(showsMarked && lower <= pair.0 && pair.1 <= upper && lower < upper) else { continue }
        let local = (pair.0 - start)..<(pair.1 - start)
        let whole = local == units.indices
        output.append(.init(id: whole ? id : virtualID(), displayUTF16: Array(units[local]),
          sourceSlices: [.init(glyphID: id, glyphUTF16Range: local, glyphUTF16Count: units.count)],
          sourceFieldIndex: sourceOwner, targetUTF16Range: span, role: whole ? .original : .fragment,
          sourceGlyphOverride: whole ? glyphOverrides[id] : nil))
      }
    }
    emitEvents(through: Int.max)
    // Unknown ownership remains explicit, not guessed from a decoded word.
    for id in indices where id >= targetGlyphCount && id != zenPlaceholder && extraOwners[id] == nil {
      output.append(.init(id: id, displayUTF16: Array(String(glyphs[id].character).utf16),
        sourceSlices: [], sourceFieldIndex: nil, targetUTF16Range: nil, role: .original))
    }
    if !showsMarked, let id = zenPlaceholder, visibleIDs.contains(id), isVisible(field.index) {
      output.append(.init(id: id, displayUTF16: Array(String(glyphs[id].character).utf16),
        sourceSlices: [], sourceFieldIndex: field.index, targetUTF16Range: nil, role: .original))
    }
    cells = output
    var aliases: [Int: [Int]] = [:], fieldIDs: [Int: [Int]] = [:]
    for cell in output {
      for slice in cell.sourceSlices { aliases[slice.glyphID, default: []].append(cell.id) }
      if let owner = cell.sourceFieldIndex { fieldIDs[owner, default: []].append(cell.id) }
    }
    canonicalAliases = aliases
    fields = ranges.enumerated().map { index, range in
      .init(index: index, targetUTF16Range: range, cellIDs: fieldIDs[index] ?? [],
        structuralReturnCount: field.sourceTargetUTF16[range].filter { $0 == 10 }.count,
        isRetired: index < firstRetainedFieldIndex, isRemoved: removedFieldIndices.contains(index))
    }
    if !isVisible(field.index) { caret = nil }
    else if showsMarked {
      switch plan.caret {
      case .target(let index):
        let unit = field.targetUTF16Range.lowerBound + localStarts[index]
        caret = output.first { $0.sourceFieldIndex == field.index && $0.compositionIndex == nil
          && $0.targetUTF16Range?.contains(unit) == true }.map { .init(cellID: $0.id, after: false) }
      case .afterComposition(let index):
        caret = output.first { $0.compositionIndex == index }.map { .init(cellID: $0.id, after: true) }
      case .afterInput: caret = nil
      }
    } else {
      let matches = canonicalCaret.map { id in output.filter { $0.id == id || $0.sourceSlices.contains { $0.glyphID == id } } } ?? []
      if let cell = matches.first(where: { $0.sourceFieldIndex == field.index && $0.targetUTF16Range == nil }) {
        caret = .init(cellID: cell.id, after: false)
      } else if case .target(let index) = plan.caret {
        let unit = field.targetUTF16Range.lowerBound + localStarts[index]
        caret = output.first { $0.sourceFieldIndex == field.index
          && $0.targetUTF16Range?.contains(unit) == true }.map { .init(cellID: $0.id, after: false) }
      } else {
        caret = matches.first(where: { $0.sourceFieldIndex == field.index }).map { .init(cellID: $0.id, after: false) }
          ?? output.last(where: { $0.sourceFieldIndex == field.index }).map { .init(cellID: $0.id, after: true) }
      }
    }
  }
}
