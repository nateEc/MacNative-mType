import Foundation

/// Actual ordered targets, including their literal commit units and empty
/// slots. These are generated values, never reconstructed from accepted input
/// or resampled from a transform recipe. Glyph boundaries are not word bounds.
struct ResultTargetWordDirectory: Codable, Equatable, Sendable {
  let words: [String]
  let noSpace: Bool
  /// Display-only spaces after these fields are not validation target units.
  let displayGaps: [Int]?

  init(words: [String], noSpace: Bool, displayGaps: [Int]? = nil) {
    self.words = words; self.noSpace = noSpace; self.displayGaps = displayGaps
  }

  var displayWords: [String] {
    guard let displayGaps else { return words }
    let gaps = Set(displayGaps)
    return words.enumerated().map { gaps.contains($0.offset) ? $0.element + " " : $0.element }
  }

  private var isStructurallyValid: Bool {
    guard !words.isEmpty else { return false }
    guard let displayGaps else { return true }
    guard !noSpace, !displayGaps.isEmpty, displayGaps == Set(displayGaps).sorted() else { return false }
    return displayGaps.allSatisfy { index in
      words.indices.contains(index) && !words[index].isEmpty
        && words[index].utf16.last != 32 && words[index].utf16.last != 10
    }
  }

  private enum CodingKeys: String, CodingKey { case words, noSpace, displayGaps }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(words: try values.decode([String].self, forKey: .words),
      noSpace: try values.decode(Bool.self, forKey: .noSpace),
      displayGaps: try values.decodeIfPresent([Int].self, forKey: .displayGaps))
    guard isStructurallyValid else {
      throw DecodingError.dataCorruptedError(forKey: .displayGaps, in: values, debugDescription: "Invalid target display gaps")
    }
  }
  func encode(to encoder: Encoder) throws {
    guard isStructurallyValid else {
      throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath, debugDescription: "Invalid target directory"))
    }
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(words, forKey: .words); try values.encode(noSpace, forKey: .noSpace)
    try values.encodeIfPresent(displayGaps, forKey: .displayGaps)
  }

  func matches(prompt: String, noSpace: Bool) -> Bool {
    self.noSpace == noSpace && isStructurallyValid
      && displayWords.joined().utf16.elementsEqual(prompt.utf16)
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
      && lhs.displayGaps == rhs.displayGaps
  }
}
