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

  init(cells: [Cell], fields: [Field], canonicalAliases: [Int: [Int]], caret: Anchor?,
    replacedTargetUTF16Range: Range<Int>, referenceLetterUnitIndex: Int) {
    self.cells = cells; self.fields = fields; self.canonicalAliases = canonicalAliases
    self.caret = caret; self.replacedTargetUTF16Range = replacedTargetUTF16Range
    self.referenceLetterUnitIndex = referenceLetterUnitIndex
  }

  @MainActor static func makeCooperatively(glyphs: [TypingPromptGlyph], indices: [Int],
    targetGlyphCount: Int, field: PromptCompositionField, composition: String,
    style: CompositionDisplayStyle, canonicalCaret: Int?, zenPlaceholder: Int? = nil,
    extraOwners: [Int: Int] = [:], firstRetainedFieldIndex: Int = 0,
    removedFieldIndices: Set<Int> = [], glyphOverrides: [Int: TypingPromptGlyph] = [:],
    batchSize: Int = 512, didProject: @MainActor (Int) -> Void = { _ in }
  ) async throws -> PromptCompositionProjection {
    try Task.checkCancellation()
    let builder = PromptCompositionProjectionBuilder(glyphs: glyphs, indices: indices,
      targetGlyphCount: targetGlyphCount, field: field, composition: composition, style: style,
      canonicalCaret: canonicalCaret, zenPlaceholder: zenPlaceholder, extraOwners: extraOwners,
      firstRetainedFieldIndex: firstRetainedFieldIndex, removedFieldIndices: removedFieldIndices,
      glyphOverrides: glyphOverrides)
    return try await builder.build(batchSize: batchSize, didProject: didProject)
  }

  init(glyphs: [TypingPromptGlyph], indices: [Int], targetGlyphCount: Int,
    field: PromptCompositionField, composition: String, style: CompositionDisplayStyle,
    canonicalCaret: Int?, zenPlaceholder: Int? = nil, extraOwners: [Int: Int] = [:],
    firstRetainedFieldIndex: Int = 0, removedFieldIndices: Set<Int> = [],
    glyphOverrides: [Int: TypingPromptGlyph] = [:]) {
    self = PromptCompositionProjectionBuilder(glyphs: glyphs, indices: indices,
      targetGlyphCount: targetGlyphCount, field: field, composition: composition, style: style,
      canonicalCaret: canonicalCaret, zenPlaceholder: zenPlaceholder, extraOwners: extraOwners,
      firstRetainedFieldIndex: firstRetainedFieldIndex, removedFieldIndices: removedFieldIndices,
      glyphOverrides: glyphOverrides).buildSynchronously()
  }
}
