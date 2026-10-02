import AppKit

/// Native, single-line practice presentation policy. It is intentionally kept
/// separate from the typing engine: tape presentation never changes prompt
/// text, accepted input, scoring, or replay.
enum PracticeTapePolicy {
  static func anchorCharacterIndex(
    session: TypingSession, rendering: PromptRendering, mode: PracticeTapeMode
  ) -> Int {
    let logicalIndex: Int?
    switch mode {
    case .off: return 0
    case .letter: logicalIndex = session.promptCaretGlyphIndex
    case .word:
      let words = session.promptWordPresentations
      logicalIndex = (words.first { $0.phase == .active } ?? words.last)?.range.lowerBound
    }
    return rendering.characterOffset(forGlyphAt: logicalIndex) ?? rendering.text.characters.count
  }

  static func horizontalOffset(
    prompt: AttributedString, anchorCharacterIndex: Int, mode: PracticeTapeMode,
    margin: Double, font: NSFont, containerWidth: Double
  ) -> Double {
    guard mode != .off, containerWidth > 0,
      let rect = PromptCaretLayout.rect(
        in: prompt, characterOffset: anchorCharacterIndex,
        containerSize: CGSize(width: .greatestFiniteMagnitude, height: font.pointSize * 2),
        font: font, lineSpacing: 0)
    else { return 0 }
    return max(0, rect.minX - containerWidth * margin.clamped(to: 0...1))
  }

  static func anchorCharacterIndex(typed: String, mode: PracticeTapeMode) -> Int {
    switch mode {
    case .off: return 0
    case .letter: return typed.count
    case .word:
      guard let separator = typed.lastIndex(where: \.isWhitespace) else { return 0 }
      return typed.distance(from: typed.startIndex, to: typed.index(after: separator))
    }
  }

  static func horizontalOffset(
    typed: String, mode: PracticeTapeMode, margin: Double, glyphWidth: Double,
    containerWidth: Double
  ) -> Double {
    horizontalOffset(
      anchorCharacterIndex: anchorCharacterIndex(typed: typed, mode: mode), mode: mode,
      margin: margin, glyphWidth: glyphWidth, containerWidth: containerWidth)
  }

  static func horizontalOffset(
    anchorCharacterIndex: Int, mode: PracticeTapeMode, margin: Double, glyphWidth: Double,
    containerWidth: Double
  ) -> Double {
    guard mode != .off, glyphWidth > 0, containerWidth > 0 else { return 0 }
    let anchor = Double(anchorCharacterIndex) * glyphWidth
    return max(0, anchor - containerWidth * margin.clamped(to: 0...1))
  }
}
