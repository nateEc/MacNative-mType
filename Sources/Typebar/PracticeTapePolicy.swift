import AppKit

/// Native, single-line practice presentation policy. It is intentionally kept
/// separate from the typing engine: tape presentation never changes prompt
/// text, accepted input, scoring, or replay.
enum PracticeTapePolicy {
  static func isOverflowing(wordLeft: CGFloat, wordWidth: CGFloat,
    viewportWidth: CGFloat, rightToLeft: Bool) -> Bool {
    rightToLeft ? floor(wordLeft) > viewportWidth : floor(wordLeft) < -floor(wordWidth)
  }

  static func isRightToLeft(_ text: String, fallback: Bool) -> Bool {
    // Foundation's whitespace set also includes U+200B; the reference's
    // punctuation/symbol/ECMAScript-space trim deliberately does not.
    func decoration(_ scalar: Unicode.Scalar) -> Bool {
      switch scalar.properties.generalCategory {
      case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
           .initialPunctuation, .finalPunctuation, .otherPunctuation,
           .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol,
           .spaceSeparator, .lineSeparator, .paragraphSeparator: true
      default: (0x09...0x0D).contains(scalar.value) || scalar.value == 0xFEFF
      }
    }
    let core = text.unicodeScalars.drop(while: decoration).reversed().drop(while: decoration)
    guard !core.isEmpty else { return fallback }
    return core.contains { scalar in
      switch scalar.value {
      case 0x0590...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF,
           0xFB50...0xFDFF, 0xFE70...0xFEFF: true
      default: false
      }
    }
  }

  static func wordStartCharacterOffsets(session: TypingSession, rendering: PromptRendering) -> [Int: Int] {
    var starts: [Int: Int] = [:]
    for word in session.promptWordPresentations {
      guard let start = rendering.characterOffset(forGlyphAt: word.range.lowerBound) else { continue }
      for id in Array(word.range) + word.extraGlyphIndices {
        if let offset = rendering.characterOffset(forGlyphAt: id) { starts[offset] = start }
      }
    }
    return starts
  }

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
    return rect.minX - containerWidth * margin.clamped(to: 0...1)
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
    return anchor - containerWidth * margin.clamped(to: 0...1)
  }
}
