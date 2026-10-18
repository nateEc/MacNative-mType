import Foundation

/// Stages the same canonical-cell ownership rules as the synchronous
/// projection. Nothing escapes until all directories and the caret are ready.
final class PromptCompositionProjectionBuilder {
  private typealias Cell = PromptCompositionProjection.Cell
  private typealias GlyphSlice = PromptCompositionProjection.GlyphSlice
  private typealias Field = PromptCompositionProjection.Field
  private typealias Anchor = PromptCompositionProjection.Anchor

  private let glyphs: [TypingPromptGlyph]
  private let indices: [Int]
  private let targetGlyphCount: Int
  private let field: PromptCompositionField
  private let plan: PromptCompositionPlan
  private let ranges: [Range<Int>]
  private let localStarts: [Int]
  private let lower: Int
  private let upper: Int
  private let showsMarked: Bool
  private let visibleIDs: Set<Int>
  private let canonicalCaret: Int?
  private let zenPlaceholder: Int?
  private let extraOwners: [Int: Int]
  private let firstRetainedFieldIndex: Int
  private let removedFieldIndices: Set<Int>
  private let glyphOverrides: [Int: TypingPromptGlyph]
  private let events: [Int: [Int]]
  private let eventPoints: [Int]
  private let boundaries: [Int]
  private var eventIndex = 0, nextVirtualID = -1, globalUnit = 0, boundaryIndex = 0, ownerCursor = 0
  private var output: [Cell] = []
  private var aliases: [Int: [Int]] = [:], fieldIDs: [Int: [Int]] = [:]
  private var fields: [Field] = []
  private var firstMarked: Cell?, firstTarget: Cell?, firstSpecialMatch: Cell?
  private var firstFieldMatch: Cell?, lastField: Cell?

  init(glyphs: [TypingPromptGlyph], indices: [Int], targetGlyphCount: Int,
    field: PromptCompositionField, composition: String, style: CompositionDisplayStyle,
    canonicalCaret: Int?, zenPlaceholder: Int?, extraOwners: [Int: Int],
    firstRetainedFieldIndex: Int, removedFieldIndices: Set<Int>,
    glyphOverrides: [Int: TypingPromptGlyph]) {
    self.glyphs = glyphs; self.indices = indices; self.targetGlyphCount = targetGlyphCount
    self.field = field; self.canonicalCaret = canonicalCaret; self.zenPlaceholder = zenPlaceholder
    self.extraOwners = extraOwners; self.firstRetainedFieldIndex = firstRetainedFieldIndex
    self.removedFieldIndices = removedFieldIndices; self.glyphOverrides = glyphOverrides
    plan = PromptCompositionPlan(field: field, composition: composition, style: style)
    ranges = field.sourceFieldUTF16Ranges
    var starts = [0]
    for character in String(decoding: field.targetUTF16, as: UTF16.self) {
      starts.append(starts.last! + String(character).utf16.count)
    }
    localStarts = starts
    lower = field.targetUTF16Range.lowerBound + starts[plan.replacedTargetRange.lowerBound]
    upper = field.targetUTF16Range.lowerBound + starts[plan.replacedTargetRange.upperBound]
    showsMarked = !composition.isEmpty && field.index >= firstRetainedFieldIndex
      && !removedFieldIndices.contains(field.index)
    visibleIDs = Set(indices)
    var extraEvents: [Int: [Int]] = [:]
    for id in indices where id >= targetGlyphCount && id != zenPlaceholder {
      guard let owner = extraOwners[id], ranges.indices.contains(owner),
        owner >= firstRetainedFieldIndex && !removedFieldIndices.contains(owner) else { continue }
      let range = ranges[owner]
      let gap = !range.isEmpty && field.sourceTargetUTF16[range.upperBound - 1] == 32 ? 1 : 0
      let point = showsMarked && owner == field.index ? lower : range.upperBound - gap
      extraEvents[point, default: []].append(id)
    }
    if showsMarked, extraEvents[lower] == nil { extraEvents[lower] = [] }
    events = extraEvents
    eventPoints = extraEvents.keys.sorted()
    var cuts = Set(ranges.flatMap { [$0.lowerBound, $0.upperBound] })
    cuts.formUnion(eventPoints)
    if showsMarked { cuts.formUnion([lower, upper]) }
    boundaries = cuts.sorted()
  }

  private func isVisible(_ owner: Int?) -> Bool {
    owner.map { $0 >= firstRetainedFieldIndex && !removedFieldIndices.contains($0) } ?? true
  }

  private func owner(at unit: Int) -> Int? {
    // The source loop walks UTF-16 positions in ascending order. Empty ranges
    // are skipped exactly as by the synchronous upper-bound search.
    while ownerCursor < ranges.count, ranges[ownerCursor].upperBound <= unit { ownerCursor += 1 }
    return ranges.indices.contains(ownerCursor) && ranges[ownerCursor].contains(unit) ? ownerCursor : nil
  }

  private func virtualID() -> Int { defer { nextVirtualID -= 1 }; return nextVirtualID }

  private func sourceSlices(in localRange: Range<Int>) -> [GlyphSlice] {
    let slices = field.targetGlyphSlices
    var low = 0, high = slices.count
    while low < high {
      let middle = (low + high) / 2
      if slices[middle].fieldUTF16Range.upperBound <= localRange.lowerBound { low = middle + 1 }
      else { high = middle }
    }
    var result: [GlyphSlice] = []
    while low < slices.count, slices[low].fieldUTF16Range.lowerBound < localRange.upperBound {
      let slice = slices[low]
      let start = max(localRange.lowerBound, slice.fieldUTF16Range.lowerBound)
      let end = min(localRange.upperBound, slice.fieldUTF16Range.upperBound)
      let glyphStart = slice.glyphUTF16Range.lowerBound + start - slice.fieldUTF16Range.lowerBound
      result.append(.init(glyphID: slice.glyphID,
        glyphUTF16Range: glyphStart..<(glyphStart + end - start), glyphUTF16Count: slice.glyphUTF16Count))
      low += 1
    }
    return result
  }

  private func emitEvents(through unit: Int) {
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

  private func appendGlyph(_ id: Int) {
    let units = Array(String(glyphs[id].character).utf16)
    let start = globalUnit, end = start + units.count
    globalUnit = end
    guard visibleIDs.contains(id) else { return }
    while boundaryIndex < boundaries.count, boundaries[boundaryIndex] <= start { boundaryIndex += 1 }
    var stops = [start]
    while boundaryIndex < boundaries.count, boundaries[boundaryIndex] < end {
      stops.append(boundaries[boundaryIndex]); boundaryIndex += 1
    }
    stops.append(end)
    for pair in zip(stops, stops.dropFirst()) {
      emitEvents(through: pair.0)
      let span = pair.0..<pair.1, sourceOwner = owner(at: pair.0)
      guard isVisible(sourceOwner),
        !(showsMarked && lower <= pair.0 && pair.1 <= upper && lower < upper) else { continue }
      let local = (pair.0 - start)..<(pair.1 - start)
      let whole = local == units.indices
      output.append(.init(id: whole ? id : virtualID(), displayUTF16: Array(units[local]),
        sourceSlices: [.init(glyphID: id, glyphUTF16Range: local, glyphUTF16Count: units.count)],
        sourceFieldIndex: sourceOwner, targetUTF16Range: span,
        role: whole ? .original : .fragment, sourceGlyphOverride: whole ? glyphOverrides[id] : nil))
    }
  }

  private func finishCells() {
    emitEvents(through: Int.max)
    for id in indices where id >= targetGlyphCount && id != zenPlaceholder && extraOwners[id] == nil {
      output.append(.init(id: id, displayUTF16: Array(String(glyphs[id].character).utf16),
        sourceSlices: [], sourceFieldIndex: nil, targetUTF16Range: nil, role: .original))
    }
    if !showsMarked, let id = zenPlaceholder, visibleIDs.contains(id), isVisible(field.index) {
      output.append(.init(id: id, displayUTF16: Array(String(glyphs[id].character).utf16),
        sourceSlices: [], sourceFieldIndex: field.index, targetUTF16Range: nil, role: .original))
    }
  }

  private func appendOwnership(_ cell: Cell) {
    for slice in cell.sourceSlices { aliases[slice.glyphID, default: []].append(cell.id) }
    if let owner = cell.sourceFieldIndex { fieldIDs[owner, default: []].append(cell.id) }
  }

  private func appendField(_ index: Int) {
    let range = ranges[index]
    fields.append(.init(index: index, targetUTF16Range: range, cellIDs: fieldIDs[index] ?? [],
      structuralReturnCount: field.sourceTargetUTF16[range].filter { $0 == 10 }.count,
      isRetired: index < firstRetainedFieldIndex, isRemoved: removedFieldIndices.contains(index)))
  }

  private var caretTargetUnit: Int? {
    if case .target(let index) = plan.caret {
      field.targetUTF16Range.lowerBound + localStarts[index]
    } else { nil }
  }

  private func considerCaret(_ cell: Cell, targetUnit: Int?) {
    guard isVisible(field.index) else { return }
    if cell.sourceFieldIndex == field.index {
      lastField = cell
      if let targetUnit, firstTarget == nil, cell.compositionIndex == nil,
        cell.targetUTF16Range?.contains(targetUnit) == true { firstTarget = cell }
    }
    if showsMarked, case .afterComposition(let markedIndex) = plan.caret,
      cell.compositionIndex == markedIndex, firstMarked == nil { firstMarked = cell }
    if let canonicalCaret, cell.id == canonicalCaret
      || cell.sourceSlices.contains(where: { $0.glyphID == canonicalCaret }) {
      if cell.sourceFieldIndex == field.index {
        if firstFieldMatch == nil { firstFieldMatch = cell }
        if cell.targetUTF16Range == nil, firstSpecialMatch == nil { firstSpecialMatch = cell }
      }
    }
  }

  private func resolvedCaret() -> Anchor? {
    guard isVisible(field.index) else { return nil }
    if showsMarked {
      switch plan.caret {
      case .target: return firstTarget.map { .init(cellID: $0.id, after: false) }
      case .afterComposition: return firstMarked.map { .init(cellID: $0.id, after: true) }
      case .afterInput: return nil
      }
    }
    if let firstSpecialMatch { return .init(cellID: firstSpecialMatch.id, after: false) }
    if case .target = plan.caret { return firstTarget.map { .init(cellID: $0.id, after: false) } }
    return firstFieldMatch.map { .init(cellID: $0.id, after: false) }
      ?? lastField.map { .init(cellID: $0.id, after: true) }
  }

  private func resolveCaretSynchronously() -> Anchor? {
    let targetUnit = caretTargetUnit
    for cell in output { considerCaret(cell, targetUnit: targetUnit) }
    return resolvedCaret()
  }

  @MainActor private func resolveCaret(batchSize: Int) async throws -> Anchor? {
    let targetUnit = caretTargetUnit
    for (index, cell) in output.enumerated() {
      considerCaret(cell, targetUnit: targetUnit)
      if (index + 1).isMultiple(of: batchSize) {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    return resolvedCaret()
  }

  func buildSynchronously() -> PromptCompositionProjection {
    for id in 0..<targetGlyphCount { appendGlyph(id) }
    finishCells()
    for cell in output { appendOwnership(cell) }
    for index in ranges.indices { appendField(index) }
    return .init(cells: output, fields: fields, canonicalAliases: aliases,
      caret: resolveCaretSynchronously(), replacedTargetUTF16Range: lower..<upper,
      referenceLetterUnitIndex: plan.referenceLetterUnitIndex)
  }

  @MainActor func build(batchSize: Int, didProject: @MainActor (Int) -> Void) async throws
    -> PromptCompositionProjection {
    try Task.checkCancellation()
    let interval = max(1, batchSize)
    for id in 0..<targetGlyphCount {
      appendGlyph(id)
      if (id + 1).isMultiple(of: interval) {
        didProject(id + 1)
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    if !targetGlyphCount.isMultiple(of: interval) { didProject(targetGlyphCount) }
    try Task.checkCancellation()
    finishCells()
    try Task.checkCancellation()
    for (index, cell) in output.enumerated() {
      appendOwnership(cell)
      if (index + 1).isMultiple(of: interval) {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    try Task.checkCancellation()
    for index in ranges.indices {
      appendField(index)
      if (index + 1).isMultiple(of: interval) {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    try Task.checkCancellation()
    let caret = try await resolveCaret(batchSize: interval)
    try Task.checkCancellation()
    return .init(cells: output, fields: fields, canonicalAliases: aliases, caret: caret,
      replacedTargetUTF16Range: lower..<upper,
      referenceLetterUnitIndex: plan.referenceLetterUnitIndex)
  }
}
