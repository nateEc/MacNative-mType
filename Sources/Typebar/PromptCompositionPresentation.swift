import AppKit
import SwiftUI

/// Dense appearance indices are not presentation or canonical identities.
/// The existing appearance policy consumes this ephemeral word/glyph list.
struct PromptCompositionPresentation {
  let projection: PromptCompositionProjection
  let glyphs: [TypingPromptGlyph]
  let words: [TypingPromptWordPresentation]
  let completedIndices: Set<Int>
  let emptyPlaceholderIndex: Int?
  let isZen: Bool

  init?(session: TypingSession, composition: String, style: CompositionDisplayStyle) {
    guard let field = session.promptCompositionField,
      let projection = session.promptCompositionProjection(composition: composition, style: style) else { return nil }
    self.projection = projection
    isZen = session.configuration.mode == .zen
    let original = session.promptGlyphs, completed = session.completedPromptCharacterIndices
    var glyphs: [TypingPromptGlyph] = [], completedIndices: Set<Int> = []
    var indicesByField: [Int: [Int]] = [:]
    for (index, cell) in projection.cells.enumerated() {
      if let owner = cell.sourceFieldIndex { indicesByField[owner, default: []].append(index) }
      let glyph: TypingPromptGlyph
      if cell.compositionIndex != nil {
        let target = cell.sourceSlices.first.map { original[$0.glyphID].character }
        let hidden = cell.sourceSlices.contains { original[$0.glyphID].state == .hidden }
          || (session.configuration.modifiers.contains(.memory) && session.hasStarted && !session.isFinished)
        glyph = .init(character: target == "\n" ? "\n" : cell.text.first!,
          state: hidden ? .hidden : cell.matchesTarget && !isZen ? .correct : .pending)
      } else if cell.role == .fragment {
        let source = original[cell.sourceSlices[0].glyphID]
        let pending = cell.sourceFieldIndex.map { $0 > field.index } == true
          || (cell.sourceFieldIndex == field.index
            && (cell.targetUTF16Range?.lowerBound ?? 0) >= projection.replacedTargetUTF16Range.lowerBound)
        glyph = pending ? .init(character: cell.text.first!, state: source.state == .hidden ? .hidden : .pending)
          : session.promptCompositionFragmentGlyph(cell, source: source, field: field)
        if !pending, completed.contains(cell.sourceSlices[0].glyphID) { completedIndices.insert(index) }
      } else {
        glyph = original[cell.id]
        if completed.contains(cell.id) { completedIndices.insert(index) }
      }
      glyphs.append(glyph)
    }
    self.glyphs = glyphs
    self.completedIndices = completedIndices
    emptyPlaceholderIndex = session.zenEmptyWordPlaceholderGlyphIndex.flatMap { id in
      projection.cells.firstIndex { $0.id == id && $0.compositionIndex == nil }
    }
    let originalWords = session.promptWordPresentations
    let errors = session.promptCompositionFieldErrors(field)
    words = projection.fields.map { source in
      var indices = indicesByField[source.index] ?? []
      if let last = indices.last, !source.targetUTF16Range.isEmpty,
        field.sourceTargetUTF16[source.targetUTF16Range.upperBound - 1] == 32,
        projection.cells[last].compositionIndex == nil,
        projection.cells[last].targetUTF16Range?.upperBound == source.targetUTF16Range.upperBound {
        indices.removeLast() // A commit SPACE is not part of the word ink.
      }
      let previous = originalWords.indices.contains(source.index) ? originalWords[source.index] : nil
      return .init(range: indices.first.map { $0..<((indices.last ?? $0) + 1) } ?? 0..<0,
        phase: source.index < field.index ? .committed : source.index == field.index ? .active : .future,
        hasInputError: errors?[source.index].input ?? previous?.hasInputError ?? false,
        hasCommitError: errors?[source.index].commit ?? previous?.hasCommitError ?? false)
    }
  }

  func markedText(for cell: PromptCompositionProjection.Cell, glyph: TypingPromptGlyph) -> String {
    PromptControlCharacterPresentation.plan(for: glyph, style: .off, isZen: isZen,
      compositionReplacement: cell.text).text
  }

  func render(_ renderGlyph: (Int, TypingPromptGlyph, PromptCompositionProjection.Cell?) -> AttributedString) -> PromptRendering {
    var text = AttributedString(), ranges: [Int: NSRange] = [:], inks: [Int: NSRange] = [:], texts: [Int: AttributedString] = [:]
    var fieldUnits: [Int: Int] = [:], structuralUnits: [Int: Int] = [:], nextField = 0, unit = 0
    func emitRemovedFields(before owner: Int) {
      while nextField < owner {
        let field = projection.fields[nextField]
        if field.isRemoved && !field.isRetired && field.hasStructuralReturn {
          structuralUnits[field.index] = unit
          text += AttributedString(String(repeating: "\n", count: field.structuralReturnCount))
          unit += field.structuralReturnCount
        }
        nextField += 1
      }
    }
    for (index, cell) in projection.cells.enumerated() {
      if let owner = cell.sourceFieldIndex { emitRemovedFields(before: owner) }
      let value = renderGlyph(index, glyphs[index], cell.compositionIndex == nil ? nil : cell)
      ranges[cell.id] = NSRange(location: unit, length: String(value.characters).utf16.count)
      let hint = value.runs.first { ($0.baselineOffset ?? 0) < 0 }
      let body = hint.map { AttributedString(value[..<$0.range.lowerBound]) } ?? value
      let bodyUnits = Array(String(body.characters).utf16)
      let length = bodyUnits.count > 1 && bodyUnits.last == 10 ? bodyUnits.count - 1 : bodyUnits.count
      inks[cell.id] = NSRange(location: unit, length: length)
      texts[cell.id] = value
      if let owner = cell.sourceFieldIndex, fieldUnits[owner] == nil { fieldUnits[owner] = unit }
      text += value; unit += ranges[cell.id]!.length
    }
    emitRemovedFields(before: projection.fields.count)
    let map = PromptCompositionTextMap(text: text, cellRanges: ranges, inkRanges: inks, cellTexts: texts,
      canonicalAliases: projection.canonicalAliases, fieldUnits: fieldUnits, caret: projection.caret)
    // Legacy character offsets remain a convenience for older callers, not
    // the identity directory. Partial/virtual slots live only in cellRanges.
    let offsets = Dictionary(projection.cells.filter { $0.id >= 0 }.compactMap { cell in
      ranges[cell.id].map { (cell.id, map.characterOffset(atUTF16: $0.location)) }
    }, uniquingKeysWith: { first, _ in first })
    return .init(text: text, glyphCharacterOffsets: offsets,
      emptyWordPlaceholderGlyphID: emptyPlaceholderIndex.map { projection.cells[$0].id },
      structuralNewlineOffsets: structuralUnits.mapValues { map.characterOffset(atUTF16: $0) },
      compositionTextMap: map)
  }
}

/// Final per-cell attributes survive grapheme fusion on concatenation. TextKit
/// uses UTF-16 ranges; field/legacy scroll coordinates are explicitly derived.
struct PromptCompositionTextMap {
  let cellRanges: [Int: NSRange]
  let inkRanges: [Int: NSRange]
  let cellTexts: [Int: AttributedString]
  let canonicalAliases: [Int: [Int]]
  let fieldCharacterOffsets: [Int: Int]
  let caret: PromptCompositionProjection.Anchor?
  private let characterStarts: [Int]

  init(text: AttributedString, cellRanges: [Int: NSRange], inkRanges: [Int: NSRange], cellTexts: [Int: AttributedString],
    canonicalAliases: [Int: [Int]], fieldUnits: [Int: Int], caret: PromptCompositionProjection.Anchor?) {
    self.cellRanges = cellRanges; self.inkRanges = inkRanges
    self.cellTexts = cellTexts; self.canonicalAliases = canonicalAliases; self.caret = caret
    var starts = [0]
    for character in text.characters { starts.append(starts.last! + String(character).utf16.count) }
    characterStarts = starts
    fieldCharacterOffsets = fieldUnits.mapValues { Self.offset($0, starts: starts) }
  }
  private static func offset(_ unit: Int, starts: [Int]) -> Int {
    var low = 0, high = starts.count
    while low < high {
      let middle = (low + high) / 2
      if starts[middle] <= unit { low = middle + 1 } else { high = middle }
    }
    return max(0, low - 1)
  }
  func characterOffset(atUTF16 unit: Int) -> Int { Self.offset(unit, starts: characterStarts) }
  func range(forCanonicalGlyph id: Int, after: Bool = false) -> NSRange? {
    let ids = canonicalAliases[id] ?? (cellRanges[id] == nil ? [] : [id])
    return (after ? ids.last : ids.first).flatMap { inkRanges[$0] }
  }
}
