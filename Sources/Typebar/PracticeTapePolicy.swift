import Foundation

/// Native, single-line practice presentation policy. It is intentionally kept
/// separate from the typing engine: tape presentation never changes prompt
/// text, accepted input, scoring, or replay.
enum PracticeTapePolicy {
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
    guard mode != .off, glyphWidth > 0, containerWidth > 0 else { return 0 }
    let anchor = Double(anchorCharacterIndex(typed: typed, mode: mode)) * glyphWidth
    return max(0, anchor - containerWidth * margin.clamped(to: 0...1))
  }
}
