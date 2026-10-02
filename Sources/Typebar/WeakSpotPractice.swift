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
      if result.replayEvents.contains(where: \.hasRawUTF16Metadata),
        result.replayEvents.allSatisfy({ $0.inputField != nil })
      {
        addUnitFieldSamples(from: result, to: &samples)
        return
      }
      var typed: [Character] = []
      let target = Array(result.prompt)
      var previousInputOffset: TimeInterval?
      for event in TypingReplay.chronologicalEvents(result.replayEvents) {
        // Automatic indentation and error recovery still move the input
        // cursor, but neither is a new human attempt or timing sample.
        let interval = event.automatic ? nil
          : previousInputOffset.flatMap { event.offset > $0 ? event.offset - $0 : nil }
        if !event.automatic { previousInputOffset = event.offset }
        switch event.kind {
        case .delete:
          if !typed.isEmpty { typed.removeLast() }
        case .insert:
          for (index, entered) in event.text.enumerated() {
            guard typed.count < target.count else { continue }
            let expected = target[typed.count]
            if !event.automatic, expected != " " {
              samples[expected, default: .init()].attemptCount += 1
              if !InputTextIdentity.matches(entered, expected) || event.forceError {
                samples[expected, default: .init()].mistakeCount += 1
              }
              if index == 0, let interval {
                samples[expected, default: .init()].intervals.append(interval)
              }
            }
            if !event.isStoppedInsertion { typed.append(entered) }
          }
        }
      }
    }
  }

  /// New unit tapes have authoritative field positions and input judgments.
  /// Keep local drill keys as visible target characters, but never regrade a
  /// correct base or mark against that entire glyph. Legacy tapes stay above.
  private static func addUnitFieldSamples(from result: CompletedTestResult,
    to samples: inout [Character: CharacterSample]) {
    let targets = TypingReplay.promptFields(result.prompt).map { String($0) }
    let fields = targets.map { Array($0.utf16) }
    let owners = targets.map { text in
      text.flatMap { character in
        Array(repeating: character, count: String(character).utf16.count)
      }
    }
    var previousInputOffset: TimeInterval?
    for event in TypingReplay.chronologicalEvents(result.replayEvents) {
      let interval = event.automatic ? nil
        : previousInputOffset.flatMap { event.offset > $0 ? event.offset - $0 : nil }
      if !event.automatic { previousInputOffset = event.offset }
      guard event.kind == .insert, !event.automatic, let field = event.inputField,
        fields.indices.contains(field.index) else { continue }
      let units = event.inputUnits
      let position = field.units.count - (event.isStoppedInsertion ? 0 : units.count)
      let judgments = event.validatedInputCorrectness
      for (index, unit) in units.enumerated() {
        let targetPosition = position + index
        guard owners[field.index].indices.contains(targetPosition) else { continue }
        let expected = owners[field.index][targetPosition]
        guard !isPromptWordSeparator(expected) else { continue }
        samples[expected, default: .init()].attemptCount += 1
        let correct = judgments?[index]
          ?? (!event.forceError && fields[field.index][targetPosition] == unit)
        if !correct { samples[expected, default: .init()].mistakeCount += 1 }
        if index == 0, let interval { samples[expected, default: .init()].intervals.append(interval) }
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
