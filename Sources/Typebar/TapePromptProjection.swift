import Foundation

/// One main-actor read binds input identity, raw field units and final slots.
/// Optional topology and retirement bind a complete representable transaction.
/// Without them, the compatibility path remains a same-field refresh only.
struct TapePromptProjectionSnapshot {
  let input: PromptCaretInputIdentity
  let field: PromptCompositionField
  let rendering: PromptRendering
  let newlineWords: [TapePromptWord]?
  let retirement: PromptLineScrollContext?

  init(input: PromptCaretInputIdentity, field: PromptCompositionField, rendering: PromptRendering,
    newlineWords: [TapePromptWord]? = nil, retirement: PromptLineScrollContext? = nil) {
    self.input = input; self.field = field; self.rendering = rendering
    self.newlineWords = newlineWords; self.retirement = retirement
  }
}

/// Word identity and structural ownership come from the session, never from
/// splitting the displayed string (which can contain replacement/hint text).
enum TapePromptProjection {
  /// Sum the measured letter allocations in source order. This is not the
  /// union of their ink bounds: joining, zero-width and virtual slots retain
  /// their own allocation semantics. A missing next slot is not zero-width.
  static func inlineAdvance(cells: [PromptFieldTextRun.Cell], nextCellID: Int?,
    frames: [Int: CGRect], hidesExtras: Bool) -> CGFloat {
    var width: CGFloat = 0, lastPositive: CGFloat = 0
    for cell in cells {
      if hidesExtras && cell.glyph.state == .extra { continue }
      let advance = frames[cell.id]?.width ?? 0
      width += advance
      if advance > 0 { lastPositive = advance }
    }
    if let nextCellID, frames[nextCellID]?.width == 0 { width -= lastPositive }
    return width
  }

  /// The source scrolls over input.length displayed letter nodes, not the
  /// candidate caret or canonical glyph IDs. Keep the raw UTF-16 count even
  /// when it selects a marked node after a multi-unit accepted character.
  /// Geometry applies hidden-extra and zero-width handling separately.
  static func advanceCells(session: TypingSession, rendering: PromptRendering,
    mode: PracticeTapeMode) -> [PromptFieldTextRun.Cell] {
    guard mode == .letter, let field = session.promptCompositionField,
      let map = rendering.compositionTextMap else { return [] }
    return Array(map.fieldRuns.lazy.filter { $0.fieldID == field.index }
      .flatMap(\.cells).filter { !$0.isGap }.prefix(field.inputUTF16.count))
  }

  static func words(session: TypingSession, rendering: PromptRendering) -> [TapePromptWord] {
    let glyphs = session.promptGlyphs
    let presentations = session.promptWordPresentations
    let targetCount = session.configuration.mode == .zen ? session.typed.count : session.prompt.count
    let targetOwners = Set(presentations.flatMap { Array($0.range) })
    let starts = Set(rendering.glyphCharacterOffsets.values).sorted()
    let ends = Dictionary(uniqueKeysWithValues: starts.enumerated().map {
      ($0.element, $0.offset + 1 < starts.count ? starts[$0.offset + 1] : rendering.text.characters.count)
    })
    var cursor = 0
    return presentations.enumerated().compactMap { index, word in
      guard index >= session.firstRetainedPromptWordIndex else { return nil }
      let separator = word.range.upperBound
      let separatorIsNewline = separator < targetCount && !targetOwners.contains(separator)
        && glyphs.indices.contains(separator) && glyphs[separator].character == "\n"
        && glyphs[separator].state != .extra
      let targetIDs = Array(word.range) + (separatorIsNewline ? [separator] : [])
      var ids = targetIDs + word.extraGlyphIndices
      if session.configuration.mode == .zen, word.phase == .active,
        let caret = session.promptCaretGlyphIndex, !ids.contains(caret) { ids.append(caret) }
      // Source word building appends one structural row per word containing
      // a Return, even when a no-space field contains several internal LFs.
      let newlineID = targetIDs.first { glyphs.indices.contains($0)
        && glyphs[$0].character == "\n" && glyphs[$0].state != .extra }
      let offsets = ids.compactMap { rendering.characterOffset(forGlyphAt: $0) }
      // Separator-based navigation exposes a future tail at target.count;
      // unlike a real empty field, no source word or glyph has been generated.
      if session.configuration.mode != .zen, !session.usesHiddenPromptWordBoundaries,
        word.phase == .future, word.range.isEmpty, word.range.lowerBound == targetCount,
        offsets.isEmpty, newlineID == nil, !session.removedTapePromptWordIndices.contains(index) { return nil }
      if session.configuration.mode == .zen, word.phase == .future, offsets.isEmpty,
        newlineID == nil, !session.removedTapePromptWordIndices.contains(index) { return nil }
      let lower = offsets.min() ?? rendering.structuralNewlineOffsets[index] ?? cursor
      let upper = offsets.compactMap { ends[$0] }.max() ?? lower
      cursor = max(upper, rendering.structuralNewlineOffsets[index].map { $0 + 1 } ?? upper)
      return .init(index: index, glyphID: word.range.lowerBound, characters: lower..<upper,
        newlineCharacterOffset: newlineID.flatMap { rendering.characterOffset(forGlyphAt: $0) },
        incorrectNewline: newlineID.map { glyphs[$0].state == .incorrect } ?? false,
        hasStructuralNewline: newlineID != nil, isRemoved: session.removedTapePromptWordIndices.contains(index),
        controlCharacterOffsets: Dictionary(uniqueKeysWithValues: targetIDs.compactMap { id in
          guard glyphs.indices.contains(id), glyphs[id].state != .extra,
            glyphs[id].character == "\n" || glyphs[id].character == "\t",
            let offset = rendering.characterOffset(forGlyphAt: id) else { return nil }
          return (offset, glyphs[id].character)
        }))
    }
  }
}
