import Foundation

/// An in-memory score book matching Monkeytype's weakspot Funbox: each
/// character keeps an exponential moving average of recent inter-key delays,
/// with a five-second penalty for an incorrect entry. It intentionally has no
/// persistence surface; ending the app clears these transient preferences.
struct WeakSpotScores: Equatable {
  private struct Score: Equatable {
    var average: TimeInterval = 0
    var count = 0

    mutating func record(_ value: TimeInterval) {
      if count < WeakSpotScores.maximumSamplesPerCharacter { count += 1 }
      let adjustment = 1 / Double(count)
      average = value * adjustment + average * (1 - adjustment)
    }
  }

  static let maximumSamplesPerCharacter = 50
  static let incorrectPenalty: TimeInterval = 5

  private var values: [Character: Score] = [:]

  mutating func record(character: Character, interval: TimeInterval, isCorrect: Bool) {
    guard interval.isFinite, interval >= 0 else { return }
    let value = interval + (isCorrect ? 0 : Self.incorrectPenalty)
    values[character, default: .init()].record(value)
  }

  mutating func absorb(_ samples: [WeakSpotInputSample]) {
    for sample in samples {
      record(character: sample.character, interval: sample.interval, isCorrect: sample.isCorrect)
    }
  }

  func averageScore(for character: Character) -> TimeInterval {
    values[character]?.average ?? 0
  }
}

/// One user-entered character that is eligible for weakspot scoring. The
/// first input event of a test deliberately produces no sample because the
/// reference has no preceding input event from which to measure a gap.
struct WeakSpotInputSample: Equatable {
  let character: Character
  let interval: TimeInterval
  let isCorrect: Bool
}

enum WeakSpotWordSelection {
  static let candidateCount = 20

  /// Chooses exactly twenty random candidates and retains the first one with
  /// the highest mean character score, preserving the reference tie rule.
  static func word(
    from lexicon: IndexedLexicon, scores: WeakSpotScores,
    random: () -> Int = { Int.random(in: Int.min...Int.max) }
  ) -> String? {
    guard !lexicon.isEmpty else { return nil }
    var selected: String?
    var highestScore: TimeInterval?
    for _ in 0..<candidateCount {
      let index = Int(random().magnitude % UInt(lexicon.count))
      let candidate = lexicon[index]
      let score = self.score(of: candidate, scores: scores)
      if highestScore == nil || score > highestScore! {
        selected = candidate
        highestScore = score
      }
    }
    return selected
  }

  static func word(
    from words: [String], scores: WeakSpotScores,
    random: () -> Int = { Int.random(in: Int.min...Int.max) }
  ) -> String? {
    word(from: IndexedLexicon(words), scores: scores, random: random)
  }

  static func prompt(
    wordCount: Int, language: TypingLanguage, englishVariant: EnglishVariant,
    mixedLanguageComponents: [TypingLanguage] = TypingLanguage.defaultMixedComponents,
    contentOptions: ContentOptions, scores: WeakSpotScores
  ) -> String? {
    guard !language.isCodeLanguage else { return nil }
    guard let source = sourceLexicon(
      for: language, englishVariant: englishVariant,
      mixedLanguageComponents: mixedLanguageComponents)
    else { return nil }
    let count = max(1, wordCount)
    let selected = (0..<count).compactMap { _ in word(from: source, scores: scores) }
    guard selected.count == count else { return nil }
    return selected.enumerated().map { index, word in
      decorated(
        word, at: index, punctuation: StarterLexicon.punctuation(
          for: language, englishVariant: englishVariant),
        contentOptions: contentOptions)
    }.joined(separator: language.usesSpaceDelimitedWords ? " " : "")
  }

  private static func sourceLexicon(
    for language: TypingLanguage, englishVariant: EnglishVariant,
    mixedLanguageComponents: [TypingLanguage]
  ) -> IndexedLexicon? {
    switch language {
    case .mixedEnglishChinese:
      return combinedLexicon([
        TypingLanguage.english.ownedPracticeLexicon(englishVariant: englishVariant),
        TypingLanguage.simplifiedChinese.ownedPracticeLexicon(),
      ])
    case .mixedLanguages:
      return combinedLexicon(TypingLanguage.normalizedMixedComponents(mixedLanguageComponents)
        .filter { !$0.isCodeLanguage }
        .map { $0.ownedPracticeLexicon(englishVariant: englishVariant) })
    default:
      let lexicon = language.ownedPracticeLexicon(englishVariant: englishVariant)
      return lexicon.isEmpty ? nil : lexicon
    }
  }

  private static func combinedLexicon(_ lexicons: [IndexedLexicon]) -> IndexedLexicon? {
    let nonEmptyLexicons = lexicons.filter { !$0.isEmpty }
    let totalCount = nonEmptyLexicons.reduce(0) { $0 + $1.count }
    guard totalCount > 0 else { return nil }
    return IndexedLexicon(count: totalCount) { index in
      var remaining = index
      for lexicon in nonEmptyLexicons {
        if remaining < lexicon.count { return lexicon[remaining] }
        remaining -= lexicon.count
      }
      preconditionFailure("Weakspot index must belong to its combined lexicon")
    }
  }

  private static func score(of word: String, scores: WeakSpotScores) -> TimeInterval {
    let characters = Array(word)
    guard !characters.isEmpty else { return 0 }
    return characters.map(scores.averageScore).reduce(0, +) / Double(characters.count)
  }

  private static func decorated(
    _ word: String, at index: Int, punctuation: [String], contentOptions: ContentOptions
  ) -> String {
    if contentOptions.includeNumbers, index.isMultiple(of: 9) {
      return String(index / 9 + 1)
    }
    guard contentOptions.includePunctuation, index.isMultiple(of: 7),
      !punctuation.isEmpty
    else { return word }
    return word + punctuation[index / 7 % punctuation.count]
  }
}
