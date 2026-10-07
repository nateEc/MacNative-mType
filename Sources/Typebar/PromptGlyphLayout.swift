/// Logical target indices remain stable for validation and caret ownership.
/// Only the presentation traversal may change their order or omit extras.
enum PromptGlyphLayout {
  static func indices(
    glyphs: [TypingPromptGlyph], words: [TypingPromptWordPresentation], hideExtraLetters: Bool,
    firstRetainedWordIndex: Int = 0
  ) -> [Int] {
    let firstRetained = max(0, firstRetainedWordIndex)
    let lowerBound = firstRetained == 0 ? 0
      : words.indices.contains(firstRetained) ? words[firstRetained].range.lowerBound : glyphs.count
    let retiredExtras = Set(words.prefix(firstRetained).flatMap(\.extraGlyphIndices))
    func retained(_ index: Int) -> Bool { index >= lowerBound && !retiredExtras.contains(index) }
    guard words.contains(where: { !$0.extraGlyphIndices.isEmpty }) else {
      return firstRetained == 0 ? Array(glyphs.indices) : glyphs.indices.filter(retained)
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
    return firstRetained == 0 ? output : output.filter(retained)
  }
}
