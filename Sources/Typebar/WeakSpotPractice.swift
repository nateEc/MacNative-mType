import Foundation

/// Builds a local, adaptive word drill from Typebar's own completed replay
/// data. It neither uploads results nor imports a third-party corpus.
enum WeakSpotPractice {
  static func prompt(
    results: [CompletedTestResult],
    language: TypingLanguage,
    englishVariant: EnglishVariant,
    wordCount: Int = 25
  ) -> String? {
    guard language.usesSpaceDelimitedWords else { return nil }
    let scores = characterScores(results: results, language: language)
    guard !scores.isEmpty else { return nil }
    let candidates = lexicon(for: language, englishVariant: englishVariant)
    let ranked = candidates.sorted {
      score(word: $0, scores: scores) > score(word: $1, scores: scores)
    }
    guard let best = ranked.first, score(word: best, scores: scores) > 0 else { return nil }
    let pool = Array(ranked.prefix(min(8, ranked.count)))
    return (0..<max(1, wordCount)).map { pool[$0 % pool.count] }.joined(separator: " ")
  }

  static func characterScores(results: [CompletedTestResult], language: TypingLanguage)
    -> [Character: Int]
  {
    results.reduce(into: [:]) { scores, result in
      guard result.outcome == .completed, result.configuration.language == language,
        !result.prompt.isEmpty
      else { return }
      var typed: [Character] = []
      let target = Array(result.prompt)
      for event in result.replayEvents.sorted(by: { $0.offset < $1.offset }) {
        switch event.kind {
        case .delete:
          if !typed.isEmpty { typed.removeLast() }
        case .insert:
          for entered in event.text {
            guard typed.count < target.count else { continue }
            let expected = target[typed.count]
            if entered != expected && expected != " " {
              scores[expected, default: 0] += 1
            }
            typed.append(entered)
          }
        }
      }
    }
  }

  private static func score(word: String, scores: [Character: Int]) -> Int {
    word.reduce(0) { $0 + (scores[$1] ?? 0) }
  }

  private static func lexicon(for language: TypingLanguage, englishVariant: EnglishVariant)
    -> [String]
  {
    guard !language.isCodeLanguage else { return [] }
    return switch language {
    case .english: englishVariant == .british ? StarterLexicon.britishWords : StarterLexicon.words
    case .spanish: StarterLexicon.spanishWords
    case .german: StarterLexicon.germanWords
    case .french: StarterLexicon.frenchWords
    case .italian: StarterLexicon.italianWords
    case .portuguese: StarterLexicon.portugueseWords
    case .russian: StarterLexicon.russianWords
    case .ukrainian: StarterLexicon.ukrainianWords
    case .ukrainianLatin: StarterLexicon.ukrainianLatinWords
    case .korean: StarterLexicon.koreanWords
    case .turkish: StarterLexicon.turkishWords
    case .polish: StarterLexicon.polishWords
    case .mixedEnglishChinese: StarterLexicon.words
    case .mixedLanguages: []
    case .simplifiedChinese, .traditionalChinese, .japaneseHiragana: []
    default: []
    }
  }
}
