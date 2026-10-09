import Foundation

/// Word identity and structural ownership come from the session, never from
/// splitting the displayed string (which can contain replacement/hint text).
enum TapePromptProjection {
  static func words(session: TypingSession, rendering: PromptRendering) -> [TapePromptWord] {
    let glyphs = session.promptGlyphs
    let starts = Set(rendering.glyphCharacterOffsets.values).sorted()
    let ends = Dictionary(uniqueKeysWithValues: starts.enumerated().map {
      ($0.element, $0.offset + 1 < starts.count ? starts[$0.offset + 1] : rendering.text.characters.count)
    })
    var cursor = 0
    return session.promptWordPresentations.enumerated().compactMap { index, word in
      guard index >= session.firstRetainedPromptWordIndex else { return nil }
      let separator = word.range.upperBound
      let newline = glyphs.indices.contains(separator) && glyphs[separator].character == "\n"
        && glyphs[separator].state != .extra
      let ids = Array(word.range) + word.extraGlyphIndices + (newline ? [separator] : [])
      let offsets = ids.compactMap { rendering.characterOffset(forGlyphAt: $0) }
      let lower = offsets.min() ?? rendering.structuralNewlineOffsets[index] ?? cursor
      let upper = offsets.compactMap { ends[$0] }.max() ?? lower
      cursor = max(upper, rendering.structuralNewlineOffsets[index].map { $0 + 1 } ?? upper)
      return .init(index: index, glyphID: word.range.lowerBound, characters: lower..<upper,
        newlineCharacterOffset: newline ? rendering.characterOffset(forGlyphAt: separator) : nil,
        incorrectNewline: newline && glyphs[separator].state == .incorrect,
        hasStructuralNewline: newline, isRemoved: session.removedTapePromptWordIndices.contains(index))
    }
  }
}
