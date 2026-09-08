import Foundation

struct WeakSpotCharacterScore: Equatable, Identifiable {
  let character: Character
  let attemptCount: Int
  let mistakeCount: Int
  let averageIntervalMilliseconds: Int?
  fileprivate let priority: Double

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
  /// One repeated mistake outweighs two typical inter-key intervals while
  /// still allowing a consistently slow, correct character to surface.
  private static let mistakePriorityWeight = 2.0

  private struct CharacterSample {
    var attemptCount = 0
    var mistakeCount = 0
    var intervals: [TimeInterval] = []

    var averageInterval: TimeInterval? {
      guard !intervals.isEmpty else { return nil }
      return intervals.reduce(0, +) / Double(intervals.count)
    }
  }

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
    let samples = characterSamples(results: eligibleResults, language: language)
    let baseline = median(samples.values.flatMap(\.intervals))
    guard !samples.isEmpty, baseline > 0 || samples.values.contains(where: { $0.mistakeCount > 0 })
    else { return nil }

    let characters = samples.compactMap { character, sample -> WeakSpotCharacterScore? in
      let averageInterval = sample.averageInterval
      guard sample.mistakeCount > 0 || averageInterval ?? 0 > baseline else { return nil }
      let normalizedDelay = baseline > 0 ? (averageInterval ?? 0) / baseline : 0
      let priority = normalizedDelay + Double(sample.mistakeCount) * mistakePriorityWeight
      guard priority > 0 else { return nil }
      return .init(
        character: character,
        attemptCount: sample.attemptCount,
        mistakeCount: sample.mistakeCount,
        averageIntervalMilliseconds: averageInterval.map { Int(($0 * 1_000).rounded()) },
        priority: priority)
    }.sorted {
      if $0.priority != $1.priority { return $0.priority > $1.priority }
      if $0.mistakeCount != $1.mistakeCount { return $0.mistakeCount > $1.mistakeCount }
      return String($0.character) < String($1.character)
    }
    let priorities = Dictionary(uniqueKeysWithValues: characters.map { ($0.character, $0.priority) })
    let rankedWords = topRankedWords(
      in: language.ownedPracticeLexicon(englishVariant: englishVariant),
      priorities: priorities, limit: max(1, suggestionLimit))
    guard rankedWords.first?.score ?? 0 > 0 else { return nil }

    return .init(
      language: language,
      analyzedResultCount: eligibleResults.count,
      totalMistakeCount: samples.values.map(\.mistakeCount).reduce(0, +),
      characters: characters,
      suggestedWords: rankedWords.map(\.word)
    )
  }

  private static func topRankedWords(
    in lexicon: IndexedLexicon, priorities: [Character: Double], limit: Int
  ) -> [(word: String, score: Double)] {
    var ranked: [(word: String, score: Double)] = []
    ranked.reserveCapacity(limit)
    for word in lexicon {
      let candidate = (word: word, score: score(word: word, priorities: priorities))
      let insertionIndex = ranked.firstIndex { candidate.score > $0.score } ?? ranked.endIndex
      guard insertionIndex < limit || ranked.count < limit else { continue }
      ranked.insert(candidate, at: insertionIndex)
      if ranked.count > limit { ranked.removeLast() }
    }
    return ranked
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
    characterSamples(results: results, language: language).reduce(into: [:]) { scores, item in
      if item.value.mistakeCount > 0 { scores[item.key] = item.value.mistakeCount }
    }
  }

  private static func characterSamples(
    results: [CompletedTestResult], language: TypingLanguage
  ) -> [Character: CharacterSample] {
    results.reduce(into: [:]) { samples, result in
      guard result.outcome == .completed, result.configuration.language == language,
        !result.prompt.isEmpty
      else { return }
      var typed: [Character] = []
      let target = Array(result.prompt)
      var previousInputOffset: TimeInterval?
      for event in result.replayEvents.sorted(by: { $0.offset < $1.offset }) where !event.automatic {
        let interval = previousInputOffset.flatMap { event.offset > $0 ? event.offset - $0 : nil }
        previousInputOffset = event.offset
        switch event.kind {
        case .delete:
          if !typed.isEmpty { typed.removeLast() }
        case .insert:
          for (index, entered) in event.text.enumerated() {
            guard typed.count < target.count else { continue }
            let expected = target[typed.count]
            if expected != " " {
              samples[expected, default: .init()].attemptCount += 1
              if entered != expected || event.forceError {
                samples[expected, default: .init()].mistakeCount += 1
              }
              if index == 0, let interval {
                samples[expected, default: .init()].intervals.append(interval)
              }
            }
            typed.append(entered)
          }
        }
      }
    }
  }

  private static func score(word: String, priorities: [Character: Double]) -> Double {
    let values = word.compactMap { priorities[$0] }
    guard !values.isEmpty else { return 0 }
    return values.reduce(0, +) / Double(values.count)
  }

  private static func median(_ values: [TimeInterval]) -> TimeInterval {
    let sorted = values.filter { $0 > 0 && $0.isFinite }.sorted()
    guard !sorted.isEmpty else { return 0 }
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
      return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
  }

}
