import SwiftUI

enum PromptGlyphColor: Equatable {
  case completed, future, error, extra, hidden
}

enum TypingPromptWordPhase: Equatable {
  case committed, active, future
}

struct TypingPromptWordPresentation: Equatable {
  let range: Range<Int>
  let phase: TypingPromptWordPhase
  let hasInputError: Bool
  let hasCommitError: Bool
  var extraGlyphIndices: [Int] = []

  static func ranges(in characters: [Character]) -> [Range<Int>] {
    var ranges: [Range<Int>] = []
    var start = 0
    for index in characters.indices where isPromptWordSeparator(characters[index]) {
      ranges.append(start..<index)
      start = index + 1
    }
    if start <= characters.count { ranges.append(start..<characters.count) }
    return ranges
  }
}

/// Presentation-only roles: no theme values, input decisions, or saved scores.
struct PromptGlyphAppearance: Equatable {
  var color: PromptGlyphColor
  var hasErrorUnderline = false

  func applyErrorUnderline(to text: inout AttributedString, errorColor: Color) {
    if hasErrorUnderline { text.underlineStyle = Text.LineStyle(color: errorColor) }
  }

  func applyVisibility(to text: inout AttributedString) {
    if color == .hidden { text.foregroundColor = .clear }
  }

  static func plan(
    glyphs: [TypingPromptGlyph], words: [TypingPromptWordPresentation],
    mode: PromptHighlightMode, blindMode: Bool, typedEffect: TypedCharacterEffect = .keep,
    hidesUntypedGlyphs: Bool = false
  ) -> [Self] {
    var output = glyphs.map { glyph in
      let color: PromptGlyphColor
      switch glyph.state {
      case .correct: color = .completed
      case .incorrect: color = .error
      case .extra: color = .extra
      case .current, .pending: color = .future
      case .hidden: color = .hidden
      }
      return Self(color: mode == .off && color == .completed ? .future : color)
    }
    let activeWord = words.firstIndex { $0.phase == .active }
    for (wordIndex, word) in words.enumerated() {
      let wordColor: PromptGlyphColor?
      if let futureCount = mode.futureWordCount {
        if word.phase == .committed {
          wordColor = !blindMode && word.hasCommitError ? .error : .future
        } else if word.phase == .active && !blindMode && word.hasInputError {
          wordColor = .error
        } else {
          wordColor = activeWord.map { wordIndex <= $0 + futureCount } == true ? .completed : .future
        }
      } else { wordColor = nil }
      for index in Array(word.range) + word.extraGlyphIndices where output.indices.contains(index) {
        guard output[index].color != .hidden else { continue }
        if typedEffect == .hide && word.phase == .committed {
          output[index].color = .hidden
          continue
        }
        if let wordColor { output[index].color = wordColor }
        output[index].hasErrorUnderline = word.phase == .committed && word.hasCommitError && !blindMode
      }
    }
    if hidesUntypedGlyphs {
      for index in output.indices where output[index].color == .future { output[index].color = .hidden }
    }
    return output
  }
}
