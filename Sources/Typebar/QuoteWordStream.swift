import Foundation

/// A finite, value-owned pool of a selected quote's raw candidates. Initial
/// generation and later forward navigation have distinct bounds and context;
/// targets are sampled only when requested, never regenerated from display.
struct QuoteWordStream {
  enum GenerationError: Error { case emptyCandidate }

  private let configuration: TestConfiguration
  private let words: [String]
  private let britishEnglish: BritishEnglishPolicy.Context
  let initialLimit: Int
  let lookaheadBound: Int
  let sourceHasNewline: Bool
  let sourceHasTab: Bool
  private(set) var emittedWords = 0
  private var previousRaw: String?
  private var previousText: String?

  init(quote: OfflineQuote, configuration: TestConfiguration, showAllLines: Bool) {
    self.configuration = configuration
    let source = QuoteSourcePolicy.selectedText(for: quote, variant: configuration.englishVariant)
    // Only the selected pool contributes source controls, including candidates
    // outside the initial window. An unselected alternate/base cannot leak in.
    sourceHasNewline = source.contains("\n")
    sourceHasTab = source.contains("\t")
    var words = source.unicodeScalars.split(separator: " ", omittingEmptySubsequences: false)
      .map { String(String.UnicodeScalarView($0)) }
    if configuration.modifiers.contains(.backwards) { words.reverse() }
    self.words = words
    britishEnglish = .init(configuration: configuration, authoredQuoteAlternate: quote.britishText?.isEmpty == false)
    lookaheadBound = configuration.visibleFutureWordCount ?? 100
    initialLimit = min(words.count, configuration.visibleFutureWordCount.map { $0 + 1 }
      ?? (showAllLines ? words.count : 100))
  }

  var totalWords: Int { words.count }
  var hasRemaining: Bool { emittedWords < words.count }

  func reset() -> Self {
    var fresh = self
    fresh.emittedWords = 0
    fresh.previousRaw = nil
    fresh.previousText = nil
    return fresh
  }

  mutating func initialChunk(nextRandomCaseBit: () -> Bool = { Bool.random() }) throws -> TransformedPromptBatch {
    var text = ""
    var targets: [String] = []
    for _ in 0..<initialLimit {
      let word = try nextWord(initial: true, nextRandomCaseBit: nextRandomCaseBit)
      text += word.text
      targets += word.noSpaceTargetWords
    }
    return .init(text: text, noSpaceTargetWords: targets)
  }

  mutating func nextWord(initial: Bool = false,
    nextRandomCaseBit: () -> Bool = { Bool.random() }) throws -> TransformedPromptBatch {
    guard hasRemaining else { return .init(text: "") }
    let source = words[emittedWords]
    guard !source.isEmpty else { throw GenerationError.emptyCandidate }
    let previous = initial ? previousRaw : previousText
    let altered = TestModifierPolicy.transformedWord(source, modifiers: configuration.modifiers,
      language: configuration.language, wordIndex: emittedWords,
      wordBound: initial ? initialLimit : lookaheadBound,
      britishEnglish: britishEnglish, previousBritishWord: previous.map(BritishEnglishPolicy.previousWordKey),
      nextRandomCaseBit: nextRandomCaseBit)
    var committed = altered
    if altered.unicodeScalars.last != "\n", !TestModifierPolicy.usesNoSpaceInput(configuration.modifiers) {
      committed.append(" ")
    }
    previousRaw = altered
    var text = committed
    let hasCommit = text.unicodeScalars.last == " " || text.unicodeScalars.last == "\n"
    if hasCommit { text.unicodeScalars.removeLast() }
    previousText = text
    emittedWords += 1
    // Remove one literal commit, not a whole native CRLF grapheme. A blank
    // LF-only word must retain its only target, even at the end of the pool.
    if !hasRemaining, hasCommit, !text.isEmpty { committed = text }
    return .init(text: committed, noSpaceTargetWords:
      TestModifierPolicy.usesNoSpaceInput(configuration.modifiers) ? [committed] : [])
  }
}
