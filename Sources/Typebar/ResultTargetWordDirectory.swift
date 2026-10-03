import Foundation

/// Actual ordered targets, including their literal commit units and empty
/// slots. These are generated values, never reconstructed from accepted input
/// or resampled from a transform recipe. Glyph boundaries are not word bounds.
struct ResultTargetWordDirectory: Codable, Equatable, Sendable {
  let words: [String]
  let noSpace: Bool

  func matches(prompt: String, noSpace: Bool) -> Bool {
    self.noSpace == noSpace && !words.isEmpty
      && words.joined().utf16.elementsEqual(prompt.utf16)
  }

  /// UTF-16 offsets may split one visible grapheme across several words.
  /// Empty targets deliberately retain duplicate boundaries.
  var unitRanges: [Range<Int>] {
    var start = 0
    return words.map { word in
      let end = start + word.utf16.count
      defer { start = end }
      return start..<end
    }
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.noSpace == rhs.noSpace && lhs.words.count == rhs.words.count
      && zip(lhs.words, rhs.words).allSatisfy { $0.utf16.elementsEqual($1.utf16) }
  }
}
