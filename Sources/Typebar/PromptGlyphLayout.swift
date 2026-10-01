/// Logical target indices remain stable for validation and caret ownership.
/// Only the presentation traversal may change their order or omit extras.
enum PromptGlyphLayout {
  static func indices(
    glyphs: [TypingPromptGlyph], words: [TypingPromptWordPresentation], hideExtraLetters: Bool
  ) -> [Int] {
    guard words.contains(where: { !$0.extraGlyphIndices.isEmpty }) else {
      return Array(glyphs.indices)
    }
    var extras = Set<Int>()
    var insertions: [Int: [Int]] = [:]
    for word in words {
      extras.formUnion(word.extraGlyphIndices)
      if !hideExtraLetters, !word.extraGlyphIndices.isEmpty {
        insertions[word.range.upperBound, default: []] += word.extraGlyphIndices
      }
    }
    var output: [Int] = []
    output.reserveCapacity(glyphs.count)
    for index in 0...glyphs.count {
      if let inserted = insertions[index] { output += inserted }
      if glyphs.indices.contains(index), !extras.contains(index) { output.append(index) }
    }
    return output
  }
}
