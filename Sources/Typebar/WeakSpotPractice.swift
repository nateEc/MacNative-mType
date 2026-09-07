import Foundation

struct WeakSpotCharacterScore: Equatable, Identifiable {
  let character: Character
  let mistakeCount: Int

  var id: Character { character }
}

struct WeakSpotReport: Equatable {
  let language: TypingLanguage
  let analyzedResultCount: Int
  let totalMistakeCount: Int
  let characters: [WeakSpotCharacterScore]
  let suggestedWords: [String]
}

/// Builds a local, adaptive word drill from Typebar's own completed replay
/// data. It neither uploads results nor imports a third-party corpus.
enum WeakSpotPractice {
  static func report(
    results: [CompletedTestResult],
    language: TypingLanguage,
    englishVariant: EnglishVariant,
    suggestionLimit: Int = 8
  ) -> WeakSpotReport? {
    guard language.usesSpaceDelimitedWords else { return nil }
    let eligibleResults = results.filter {
      $0.outcome == .completed && $0.configuration.language == language && !$0.prompt.isEmpty
        && !$0.replayEvents.isEmpty
    }
    let scores = characterScores(results: eligibleResults, language: language)
    guard !scores.isEmpty else { return nil }

    let characters = scores.map {
      WeakSpotCharacterScore(character: $0.key, mistakeCount: $0.value)
    }.sorted {
      if $0.mistakeCount != $1.mistakeCount { return $0.mistakeCount > $1.mistakeCount }
      return String($0.character) < String($1.character)
    }
    let rankedWords = language.ownedPracticeWords(englishVariant: englishVariant).enumerated()
      .map { (index: $0.offset, word: $0.element, score: score(word: $0.element, scores: scores)) }
      .sorted {
        if $0.score != $1.score { return $0.score > $1.score }
        return $0.index < $1.index
      }
    guard rankedWords.first?.score ?? 0 > 0 else { return nil }

    return .init(
      language: language,
      analyzedResultCount: eligibleResults.count,
      totalMistakeCount: scores.values.reduce(0, +),
      characters: characters,
      suggestedWords: rankedWords.prefix(max(1, suggestionLimit)).map(\.word)
    )
  }

  static func prompt(
    results: [CompletedTestResult],
    language: TypingLanguage,
    englishVariant: EnglishVariant,
    wordCount: Int = 25
  ) -> String? {
    guard let report = report(
      results: results, language: language, englishVariant: englishVariant)
    else { return nil }
    let pool = report.suggestedWords
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

}
