/// Replay text storage and offsets refer to retained source spelling, rather
/// than Swift's canonical equivalence. Keep this local to replay rendering.
enum ReplayGlyphIdentity {
  static func matches(_ first: TypingPromptGlyph, _ second: TypingPromptGlyph) -> Bool {
    // Preserve existing metadata equality; only visible text needs a stricter
    // encoding check. Unrendered canonical aliases must not cause scrolling.
    first == second && InputTextIdentity.matches(first.character, second.character)
  }

  static func matches(_ first: [TypingPromptGlyph], _ second: [TypingPromptGlyph]) -> Bool {
    first.count == second.count && zip(first, second).allSatisfy { matches($0.0, $0.1) }
  }

  static func matches(_ first: [TypingPromptGlyph]?, _ second: [TypingPromptGlyph]?) -> Bool {
    switch (first, second) {
    case (nil, nil): return true
    case let (first?, second?): return matches(first, second)
    default: return false
    }
  }
}
