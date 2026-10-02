import Foundation

struct CustomSectionPromptChunk {
  var text = ""
  var sectionEndOffsets: [Int] = []
  var sectionWordEnds: [Int] = []
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
  private var recentWords: [String] = []
  private var pendingWords: [String] = []
  private var pendingIndex = 0
  private var emittedWords = 0
  private var randomState = UInt64.random(in: .min ... .max)

  init?(source: String, configuration: TestConfiguration) {
    var sections = Self.sourceSections(from: source, usesPipe: configuration.usesCustomTextPipeDelimiter)
    if configuration.modifiers.contains(.backwards) { sections.reverse() }
    let limit: Int
    switch configuration.customTextCompletion {
    case .sections: limit = configuration.customTextSectionLimit ?? sections.count
    case .finish: limit = sections.count
    case .time, .words: limit = 0
    }
    guard !sections.isEmpty, (0...OfficialTestLimitInput.maximumValue).contains(limit) else { return nil }
    self.configuration = configuration
    self.sections = sections
    self.words = sections.map { section in
      section.unicodeScalars.split(separator: " ")
        .map { String(String.UnicodeScalarView($0)) }
    }
    self.sectionLimit = limit
  }

  var hasRemaining: Bool {
    if configuration.customTextCompletion == .words, let limit = configuration.wordLimit,
      limit > 0, emittedWords >= limit { return false }
    return hasSectionWordsRemaining
  }

  private var hasSectionWordsRemaining: Bool {
    pendingIndex < pendingWords.count || sectionLimit == 0 || selectedSections < sectionLimit
  }

  mutating func nextChunk(random: (() -> Int)? = nil,
    nextRandomCaseBit: () -> Bool = { Bool.random() }) -> CustomSectionPromptChunk {
    var chunk = CustomSectionPromptChunk()
    var length = 0
    guard hasRemaining else { return chunk }
    let initial = emittedWords == 0
    let finiteWords = configuration.customTextCompletion == .words && (configuration.wordLimit ?? 0) > 0
    let maximumWords = finiteWords && !initial ? min(100, (configuration.wordLimit ?? 0) - emittedWords) : 100
    let initialSectionQuota = finiteWords ? min(100, configuration.wordLimit ?? 100) : 100
    let alterationBound: Int
    if initial {
      let requested = finiteWords ? configuration.wordLimit ?? 100 : sectionLimit
      alterationBound = requested > 0 ? min(100, requested) : 100
    } else {
      alterationBound = 100
    }
    let previousSectionCount = selectedSections
    var lastSeparator = ""
    var lastWordIsBlank = false
    let britishEnglish = BritishEnglishPolicy.Context(configuration: configuration)
    for _ in 0..<maximumWords where hasSectionWordsRemaining {
      if pendingIndex >= pendingWords.count {
        let index = nextSectionIndex(random: random)
        pendingWords = words[index]
        pendingIndex = 0
        selectedSections += 1
        recentSections = Array((recentSections + [sections[index]]).suffix(2))
      }
      let altered = TestModifierPolicy.transformedWord(pendingWords[pendingIndex],
        modifiers: configuration.modifiers, language: configuration.language,
        wordIndex: emittedWords, wordBound: alterationBound, britishEnglish: britishEnglish,
        nextRandomCaseBit: nextRandomCaseBit)
      pendingIndex += 1
      emittedWords += 1
      // Commit follows text alteration; reversing a word must not move its
      // separator to the beginning or suppress a newly produced newline.
      let commits = hasSectionWordsRemaining && !altered.hasSuffix("\n")
        && !TestModifierPolicy.usesNoSpaceInput(configuration.modifiers)
      let separator = commits ? " " : ""
      let transformed = altered + separator
      lastSeparator = altered.hasSuffix("\n") ? "\n" : separator
      lastWordIsBlank = altered == "\n"
      recentWords = Array((recentWords + [altered]).suffix(2))
      chunk.text += transformed
      length += transformed.count
      if TestModifierPolicy.usesNoSpaceInput(configuration.modifiers) {
        chunk.noSpaceWordLengths.append(transformed.count)
        chunk.noSpaceTargetWords.append(transformed)
      }
      if pendingIndex == pendingWords.count {
        chunk.sectionEndOffsets.append(length)
        chunk.sectionWordEnds.append(emittedWords)
      }
      // The source's initial pipe/word prompt prefetches complete sections;
      // completion consumes that entire generated queue. Later chunks are
      // bounded by the configured budget's remaining words.
      if initial && finiteWords && pendingIndex == pendingWords.count,
        selectedSections - previousSectionCount >= initialSectionQuota { break }
    }
    // A newline-only candidate is an empty word with a real commit. Removing
    // that commit would erase its only target and silently skip the slot.
    if !hasRemaining && !lastSeparator.isEmpty && !lastWordIsBlank {
      chunk.text.removeLast(lastSeparator.count)
      if chunk.sectionEndOffsets.last == length {
        chunk.sectionEndOffsets[chunk.sectionEndOffsets.count - 1] -= lastSeparator.count
      }
      if !chunk.noSpaceWordLengths.isEmpty {
        chunk.noSpaceWordLengths[chunk.noSpaceWordLengths.count - 1] -= lastSeparator.count
        chunk.noSpaceTargetWords[chunk.noSpaceTargetWords.count - 1].removeLast(lastSeparator.count)
      }
    }
    let captured = TransformedPromptBatch(text: chunk.text, noSpaceTargetWords: chunk.noSpaceTargetWords)
    chunk.noSpaceWordLengths = captured.noSpaceWordLengths
    chunk.noSpaceTargetWords = captured.noSpaceTargetWords
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
        while shouldAvoid(sections[index]), retries < 100 {
          index = drawIndex(bound: sections.count, random: random)
          retries += 1
        }
      }
      return index
    }
  }

  private func shouldAvoid(_ section: String) -> Bool {
    if configuration.customTextCompletion == .sections { return recentSections.contains(section) }
    return CustomTextOrderPolicy.avoidsRecentFirstWord(in: section, previous: recentWords,
      lazyLanguage: configuration.modifiers.contains(.lazyLatin) ? configuration.language : nil)
  }

  private mutating func drawIndex(bound: Int, random: (() -> Int)?) -> Int {
    if let random { return Int(random().magnitude % UInt(bound)) }
    // Local reproducible draws, not a copy of the reference random sequence.
    randomState = randomState &* 2_862_933_555_777_941_757 &+ 3_037_000_493
    return Int((randomState >> 32) % UInt64(bound))
  }

  static func sourceSections(from source: String, usesPipe: Bool) -> [String] {
    // A literal delimiter may share a grapheme with the following mark. It
    // still separates candidates; the mark belongs to the next candidate.
    normalized(source).unicodeScalars.split(separator: usesPipe ? "|" : " ")
      .map { scalars in
        let trimmed = scalars.drop(while: { $0 == " " }).reversed()
          .drop(while: { $0 == " " }).reversed()
        return String(String.UnicodeScalarView(trimmed))
      }
      .filter { !$0.isEmpty }
  }

  private static func normalized(_ source: String) -> String {
    var text = ""
    var previousWasCR = false
    for scalar in source.precomposedStringWithCanonicalMapping.unicodeScalars {
      if scalar.value == 0x0A && previousWasCR {
        previousWasCR = false
        continue
      }
      previousWasCR = scalar.value == 0x0D
      if previousWasCR {
        text.unicodeScalars.append("\n")
      } else if (0x2000...0x200A).contains(scalar.value)
        || [0x202F, 0x205F, 0x00A0].contains(scalar.value) {
        text.unicodeScalars.append(" ")
      } else {
        text.unicodeScalars.append(scalar)
      }
    }
    let lines = text.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false).map { line in
      line.split(separator: " ").map { String(String.UnicodeScalarView($0)) }.joined(separator: " ")
    }
    return lines.joined(separator: "\n ")
  }
}
