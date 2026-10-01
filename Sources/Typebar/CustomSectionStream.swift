import Foundation

struct CustomSectionPromptChunk {
  var text = ""
  var sectionEndOffsets: [Int] = []
  var noSpaceWordLengths: [Int] = []
  var noSpaceTargetWords: [String] = []
}

/// Independently consumes complete user-authored sections in bounded word
/// batches. The cursor, including its random state, is value-owned by one
/// attempt so a repeat does not share mutable generation state.
struct CustomSectionWordStream {
  let sectionLimit: Int
  private let configuration: TestConfiguration
  private let sections: [String]
  private let words: [[String]]
  private var selectedSections = 0
  private var orderedIndex = 0
  private var shuffledIndices: [Int] = []
  private var recentSections: [String] = []
  private var pendingWords: [String] = []
  private var pendingIndex = 0
  private var randomState = UInt64.random(in: .min ... .max)

  init?(source: String, configuration: TestConfiguration) {
    let normalized = Self.normalized(source)
    let sections = normalized.split(separator: "|", omittingEmptySubsequences: true)
      .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " ")) }
      .filter { !$0.isEmpty }
    let limit = configuration.customTextSectionLimit ?? sections.count
    guard !sections.isEmpty, (0...OfficialTestLimitInput.maximumValue).contains(limit) else { return nil }
    self.configuration = configuration
    self.sections = sections
    self.words = sections.map { $0.split(separator: " ").map(String.init) }
    self.sectionLimit = limit
  }

  var hasRemaining: Bool {
    pendingIndex < pendingWords.count || sectionLimit == 0 || selectedSections < sectionLimit
  }

  mutating func nextChunk(random: (() -> Int)? = nil) -> CustomSectionPromptChunk {
    var chunk = CustomSectionPromptChunk()
    var length = 0
    for _ in 0..<100 where hasRemaining {
      if pendingIndex >= pendingWords.count {
        let index = nextSectionIndex(random: random)
        pendingWords = words[index]
        pendingIndex = 0
        selectedSections += 1
        recentSections = Array((recentSections + [sections[index]]).suffix(2))
      }
      let word = pendingWords[pendingIndex]
      pendingIndex += 1
      // Commit follows text alteration; reversing a word must not move its
      // separator to the beginning or suppress a newly produced newline.
      let part = GeneratedWordChunk(source: word, configuration: configuration)
      let commits = hasRemaining && !part.transformed.hasSuffix("\n")
      let separator = !commits || configuration.modifiers.contains(.noSpaces)
        ? "" : configuration.modifiers.contains(.underscoreSeparators) ? "_" : " "
      let transformed = part.transformed + separator
      chunk.text += transformed
      length += transformed.count
      if TestModifierPolicy.usesNoSpaceInput(configuration.modifiers) {
        chunk.noSpaceWordLengths.append(transformed.count)
        chunk.noSpaceTargetWords.append(transformed)
      }
      if pendingIndex == pendingWords.count { chunk.sectionEndOffsets.append(length) }
    }
    return chunk
  }

  private mutating func nextSectionIndex(random: (() -> Int)?) -> Int {
    switch configuration.customTextOrdering {
    case .inOrder:
      let index = orderedIndex
      orderedIndex = (orderedIndex + 1) % sections.count
      return index
    case .shuffled:
      if shuffledIndices.isEmpty {
        shuffledIndices = Array(sections.indices)
        for position in stride(from: sections.count - 1, through: 1, by: -1) {
          shuffledIndices.swapAt(position, drawIndex(bound: position + 1, random: random))
        }
      }
      return shuffledIndices.removeLast()
    case .random:
      var index = drawIndex(bound: sections.count, random: random)
      if sections.count >= 4 {
        var retries = 0
        while recentSections.contains(sections[index]), retries < 100 {
          index = drawIndex(bound: sections.count, random: random)
          retries += 1
        }
      }
      return index
    }
  }

  private mutating func drawIndex(bound: Int, random: (() -> Int)?) -> Int {
    if let random { return Int(random().magnitude % UInt(bound)) }
    // Local reproducible draws, not a copy of the reference random sequence.
    randomState = randomState &* 2_862_933_555_777_941_757 &+ 3_037_000_493
    return Int((randomState >> 32) % UInt64(bound))
  }

  private static func normalized(_ source: String) -> String {
    var text = source.precomposedStringWithCanonicalMapping
    text = String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
      (0x2000...0x200A).contains(scalar.value) || [0x202F, 0x205F, 0x00A0].contains(scalar.value)
        ? UnicodeScalar(0x20)! : scalar
    }))
    text = text.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map {
      $0.split(separator: " ").joined(separator: " ")
    }
    return lines.joined(separator: "\n ")
  }
}
