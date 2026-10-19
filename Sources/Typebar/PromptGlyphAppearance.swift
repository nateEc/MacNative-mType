import SwiftUI
import AppKit

enum PromptGlyphColor: Hashable {
  case completed, future, error, extra, hidden
}

/// Reuse ink only within one render. Non-ASCII and any position-dependent
/// presentation keep their exact original UTF-16 and per-cell attributes.
struct PlainPendingGlyphInkKey: Hashable {
  let ascii: UInt8
  let color: PromptGlyphColor
  let hasErrorUnderline: Bool

  static func make(glyph: TypingPromptGlyph, appearance: PromptGlyphAppearance,
    isCompleted: Bool, hasSpecialPresentation: Bool) -> Self? {
    guard glyph.state == .pending, glyph.typedCharacter == nil, !isCompleted,
      !hasSpecialPresentation, let ascii = glyph.character.asciiValue,
      (33...126).contains(ascii), glyph.character.unicodeScalars.count == 1 else { return nil }
    return .init(ascii: ascii, color: appearance.color,
      hasErrorUnderline: appearance.hasErrorUnderline)
  }
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
    if hasErrorUnderline {
      text.underlineStyle = Text.LineStyle(color: errorColor)
      text.appKit.underlineColor = NSColor(errorColor)
    }
  }

  func applyVisibility(to text: inout AttributedString) {
    if color == .hidden { text.foregroundColor = .clear }
  }

  private static func initial(_ glyph: TypingPromptGlyph, mode: PromptHighlightMode) -> Self {
    let color: PromptGlyphColor
    switch glyph.state {
    case .correct: color = .completed
    case .incorrect: color = .error
    case .extra: color = .extra
    case .current, .pending: color = .future
    case .hidden: color = .hidden
    }
    return .init(color: mode == .off && color == .completed ? .future : color)
  }

  private static func wordColor(index: Int, word: TypingPromptWordPresentation,
    activeWord: Int?, mode: PromptHighlightMode, blindMode: Bool) -> PromptGlyphColor? {
    guard let futureCount = mode.futureWordCount else { return nil }
    if word.phase == .committed { return !blindMode && word.hasCommitError ? .error : .future }
    if word.phase == .active && !blindMode && word.hasInputError { return .error }
    return activeWord.map { index <= $0 + futureCount } == true ? .completed : .future
  }

  private static func applyWord(_ word: TypingPromptWordPresentation,
    wordColor: PromptGlyphColor?, blindMode: Bool, typedEffect: TypedCharacterEffect,
    to appearance: inout Self) {
    guard appearance.color != .hidden else { return }
    if typedEffect == .hide && word.phase == .committed {
      appearance.color = .hidden
      return
    }
    if let wordColor { appearance.color = wordColor }
    appearance.hasErrorUnderline = word.phase == .committed && word.hasCommitError && !blindMode
  }

  static func plan(
    glyphs: [TypingPromptGlyph], words: [TypingPromptWordPresentation],
    mode: PromptHighlightMode, blindMode: Bool, typedEffect: TypedCharacterEffect = .keep,
    hidesUntypedGlyphs: Bool = false
  ) -> [Self] {
    var output = glyphs.map { initial($0, mode: mode) }
    let activeWord = words.firstIndex { $0.phase == .active }
    for (wordIndex, word) in words.enumerated() {
      let ink = wordColor(index: wordIndex, word: word, activeWord: activeWord,
        mode: mode, blindMode: blindMode)
      for index in word.range where output.indices.contains(index) {
        applyWord(word, wordColor: ink, blindMode: blindMode,
          typedEffect: typedEffect, to: &output[index])
      }
      for index in word.extraGlyphIndices where output.indices.contains(index) {
        applyWord(word, wordColor: ink, blindMode: blindMode,
          typedEffect: typedEffect, to: &output[index])
      }
    }
    if hidesUntypedGlyphs {
      for index in output.indices where output[index].color == .future { output[index].color = .hidden }
    }
    return output
  }

  /// The caller supplies only words touching its selected global glyph IDs.
  /// Word indices and activeWordIndex remain global, not window-local.
  static func planWindow(glyphs: [TypingPromptGlyph], globalIndices: [Int],
    words: [(index: Int, value: TypingPromptWordPresentation)], activeWordIndex: Int?,
    mode: PromptHighlightMode, blindMode: Bool, typedEffect: TypedCharacterEffect = .keep,
    hidesUntypedGlyphs: Bool = false) -> [Self]? {
    guard glyphs.count == globalIndices.count,
      globalIndices.allSatisfy({ $0 >= 0 }), Set(globalIndices).count == globalIndices.count
    else { return nil }
    var output = glyphs.map { initial($0, mode: mode) }
    for (index, word) in words {
      let ink = wordColor(index: index, word: word, activeWord: activeWordIndex,
        mode: mode, blindMode: blindMode)
      for (local, global) in globalIndices.enumerated()
        where word.range.contains(global) || word.extraGlyphIndices.contains(global) {
        applyWord(word, wordColor: ink, blindMode: blindMode,
          typedEffect: typedEffect, to: &output[local])
      }
    }
    if hidesUntypedGlyphs {
      for index in output.indices where output[index].color == .future { output[index].color = .hidden }
    }
    return output
  }
}
