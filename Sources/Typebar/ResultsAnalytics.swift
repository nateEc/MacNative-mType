import Foundation

struct ResultMetric: Equatable, Identifiable {
    let id: UUID
    let finishedAt: Date
    let wpm: Int
    let accuracy: Int
    let typingSeconds: TimeInterval
    let consistency: Double

    init(
        id: UUID = UUID(), finishedAt: Date, wpm: Int, accuracy: Int, typingSeconds: TimeInterval,
        consistency: Double = 0
    ) {
        self.id = id
        self.finishedAt = finishedAt
        self.wpm = wpm
        self.accuracy = accuracy
        self.typingSeconds = typingSeconds
        self.consistency = consistency.isFinite ? min(100, max(0, consistency)) : 0
    }

    init(record: TestResultRecord) {
        self.init(
            id: record.id,
            finishedAt: record.finishedAt,
            wpm: record.wpm,
            accuracy: record.accuracy,
            typingSeconds: record.engagedDuration,
            consistency: ResultConsistencyPolicy.metrics(
                events: record.replayEvents,
                duration: record.finishedAt.timeIntervalSince(record.startedAt)
            ).typing
        )
    }
}

/// Controls the four independently visible traces in the local history view.
/// The defaults mirror the reference account history's initially enabled set,
/// while the native chart keeps its data entirely on this Mac.
struct HistoryChartVisibility: Codable, Equatable {
  var speed = true
  var accuracy = true
  var average10 = true
  var average100 = true
}

/// Small, deterministic transforms for the local history chart. Inputs are
/// newest-first, matching the result query order used by the history screen.
enum HistoryChartPolicy {
  static func movingAverage(values: [Double], windowSize: Int) -> [Double] {
    guard windowSize > 0 else { return values }
    return values.indices.map { index in
      let upperBound = min(values.count, index + windowSize)
      let window = values[index..<upperBound]
      guard !window.isEmpty else { return 0 }
      return window.reduce(0, +) / Double(window.count)
    }
  }

  /// Produces a historical best-speed envelope aligned with newest-first input.
  static func personalBestEnvelope(values: [Double]) -> [Double] {
    guard !values.isEmpty else { return [] }
    var envelope = Array(repeating: 0.0, count: values.count)
    var currentBest = -Double.infinity
    for index in values.indices.reversed() {
      currentBest = max(currentBest, values[index])
      envelope[index] = currentBest
    }
    return envelope
  }

  /// Estimates speed change per hour of actual typing from the same local
  /// sequence used for the chart. It intentionally avoids calendar-wall time.
  static func speedChangePerTypingHour(metrics: [ResultMetric]) -> Double? {
    guard metrics.count >= 2 else { return nil }
    let totalTypingSeconds = metrics.map(\.typingSeconds).reduce(0, +)
    guard totalTypingSeconds > 0 else { return nil }

    let chronological = metrics.reversed()
    let count = Double(chronological.count)
    let meanX = (count - 1) / 2
    let meanY = chronological.map { Double($0.wpm) }.reduce(0, +) / count
    var numerator = 0.0
    var denominator = 0.0
    for (index, metric) in chronological.enumerated() {
      let centeredX = Double(index) - meanX
      numerator += centeredX * (Double(metric.wpm) - meanY)
      denominator += centeredX * centeredX
    }
    guard denominator > 0 else { return nil }
    let fittedChange = numerator / denominator * (count - 1)
    return fittedChange * 3_600 / totalTypingSeconds
  }
}

/// Completed practice that belongs to the current running app process. It
/// keeps the daily result summary truthful even when the user opted out of
/// persisting a completed test to SwiftData.
struct CurrentProcessPractice: Equatable, Identifiable {
  let id: UUID
  let finishedAt: Date
  let typingSeconds: TimeInterval

  init(id: UUID = UUID(), finishedAt: Date, typingSeconds: TimeInterval) {
    self.id = id
    self.finishedAt = finishedAt
    self.typingSeconds = max(0, typingSeconds)
  }

  init(result: CompletedTestResult) {
    self.init(
      id: result.id, finishedAt: result.finishedAt,
      typingSeconds: result.engagedDuration)
  }
}

struct TodayPracticeSummary: Equatable {
  let typingSeconds: TimeInterval
  let completedTests: Int

  var formattedDuration: String {
    let totalSeconds = max(0, Int(typingSeconds.rounded()))
    let hours = totalSeconds / 3_600
    let minutes = totalSeconds % 3_600 / 60
    let seconds = totalSeconds % 60
    if hours > 0 { return "\(hours) 小时 \(minutes) 分" }
    if minutes > 0 { return "\(minutes) 分 \(seconds) 秒" }
    return "\(seconds) 秒"
  }
}

enum TodayPracticeAggregation {
  static func summary(
    persisted: [ResultMetric], currentProcess: [CurrentProcessPractice], now: Date = .now,
    calendar: Calendar = .current
  ) -> TodayPracticeSummary {
    let local = currentProcess.filter { calendar.isDate($0.finishedAt, inSameDayAs: now) }
    let localIDs = Set(local.map(\.id))
    let saved = persisted.filter {
      calendar.isDate($0.finishedAt, inSameDayAs: now) && !localIDs.contains($0.id)
    }
    return .init(
      typingSeconds: saved.map(\.typingSeconds).reduce(0, +)
        + local.map(\.typingSeconds).reduce(0, +),
      completedTests: saved.count + local.count)
  }
}

struct ResultHistoryEntry: Equatable, Identifiable {
    let id: UUID
    let mode: TestMode?
    let language: TypingLanguage?
    let tags: [String]
    let finishedAt: Date
    let difficulty: Difficulty?
    let includesPunctuation: Bool?
    let includesNumbers: Bool?
    let quoteLength: QuoteLength?
    let duration: TimeInterval?
    let wordLimit: Int?
    let modifiers: [TestModifier]?

    init(
        id: UUID, mode: TestMode?, language: TypingLanguage?, tags: [String],
        finishedAt: Date = .distantPast, difficulty: Difficulty? = nil,
        includesPunctuation: Bool? = nil, includesNumbers: Bool? = nil,
        quoteLength: QuoteLength? = nil, duration: TimeInterval? = nil, wordLimit: Int? = nil,
        modifiers: [TestModifier]? = nil
    ) {
        self.id = id
        self.mode = mode
        self.language = language
        self.tags = tags
        self.finishedAt = finishedAt
        self.difficulty = difficulty
        self.includesPunctuation = includesPunctuation
        self.includesNumbers = includesNumbers
        self.quoteLength = quoteLength
        self.duration = duration
        self.wordLimit = wordLimit
        self.modifiers = modifiers
    }
}

/// The minimum immutable data needed to calculate the practice-screen average
/// without making the display depend on a network account or a SwiftData query.
struct RecentAverageSample: Equatable {
  let configuration: TestConfiguration
  let prompt: String
  let finishedAt: Date
  let wpm: Int
  let accuracy: Int
}

struct RecentTestAverage: Equatable {
  let count: Int
  let wpm: Int
  let accuracy: Int
}

struct CurrentPersonalBest: Equatable {
  let wpm: Int
  let accuracy: Int
}

enum WordBurstHeatmapTone: Int, CaseIterable, Equatable, Identifiable {
  case slow
  case measured
  case steady
  case fast
  case swift
  case unmeasured

  var id: Self { self }

  static var scoredTones: [Self] { [.slow, .measured, .steady, .fast, .swift] }
}

struct WordBurstHeatmap: Equatable {
  let tones: [WordBurstHeatmapTone]
  let lowerBounds: [Int]

  func tone(at wordIndex: Int) -> WordBurstHeatmapTone? {
    guard tones.indices.contains(wordIndex) else { return nil }
    return tones[wordIndex]
  }

  func lowerBound(for tone: WordBurstHeatmapTone) -> Int? {
    guard let index = WordBurstHeatmapTone.scoredTones.firstIndex(of: tone),
      lowerBounds.indices.contains(index)
    else { return nil }
    return lowerBounds[index]
  }
}

/// Classifies result-page word bursts with independently authored quintiles.
/// Each band is relative to the current completed test, making the display
/// useful at both beginner and advanced typing speeds without any network data.
enum WordBurstHeatmapPolicy {
  static func make(bursts: [Int?]) -> WordBurstHeatmap? {
    let measured = bursts.compactMap { $0 }.filter { $0 > 0 }.sorted()
    guard !measured.isEmpty else { return nil }
    let lowerBounds = [0.0, 0.25, 0.5, 0.75, 1.0].map { percentile in
      measured[Int((Double(measured.count - 1) * percentile).rounded(.down))]
    }
    return .init(
      tones: bursts.map { burst in tone(for: burst, lowerBounds: lowerBounds) },
      lowerBounds: lowerBounds)
  }

  private static func tone(for burst: Int?, lowerBounds: [Int]) -> WordBurstHeatmapTone {
    guard let burst, burst > 0 else { return .unmeasured }
    let index = lowerBounds.lastIndex(where: { burst >= $0 }) ?? 0
    return WordBurstHeatmapTone.scoredTones[index]
  }
}

/// A local-only slow-word follow-up matching the reference selection rule:
/// rank attempted targets by word burst, retain the slowest rounded 20%, and
/// weight the slowest selected target most heavily.
struct SlowWordPracticePlan: Equatable {
  let selectedWords: [String]
  let exerciseWords: [String]

  static let maximumSelectedWords = 20

  static func make(reviews: [TypedWordReview], bursts: [Int?]) -> Self? {
    struct Candidate {
      let index: Int
      let target: String
      let burst: Int
    }

    // The reference event history ends with the active trailing entry, which
    // is not eligible for slow-word classification.
    let candidates = reviews.dropLast().enumerated().compactMap { index, review -> Candidate? in
      guard !review.target.isEmpty else { return nil }
      return .init(index: index, target: review.target, burst: bursts.indices.contains(index) ? bursts[index] ?? 0 : 0)
    }
    let selectedCount = min(
      maximumSelectedWords,
      Int((Double(candidates.count) * 0.2).rounded(.toNearestOrAwayFromZero)))
    guard selectedCount > 0 else { return nil }
    let ranked = candidates.sorted {
      $0.burst == $1.burst ? $0.index < $1.index : $0.burst < $1.burst
    }
    let selected = Array(ranked.prefix(selectedCount))
    guard !selected.isEmpty else { return nil }

    let exerciseWords = selected.enumerated().flatMap { index, candidate in
      Array(repeating: candidate.target, count: selected.count - index)
    }
    return .init(selectedWords: selected.map(\.target), exerciseWords: exerciseWords)
  }
}

/// Builds a finite, local follow-up that keeps the previous target word next
/// to each missed word. The context is derived only from the attempt being
/// reviewed, never from a remote corpus or an unattempted tail of the prompt.
struct ContextualMissedWordPracticePlan: Equatable {
  let phrases: [String]
  let missedWordCount: Int
  let selectedTargetCount: Int

  static let maximumSelectedWords = 10

  static func make(reviews: [TypedWordReview], errorCounts: [Int]) -> Self? {
    let countsByTarget = reviews.indices.reduce(into: [String: Int]()) { totals, index in
      let count = errorCounts.indices.contains(index) ? errorCounts[index] : 0
      let target = reviews[index].target
      guard count > 0, !target.isEmpty else { return }
      totals[target, default: 0] += count
    }
    struct Candidate {
      let index: Int
      let phrase: String
      let count: Int
    }
    let selected = reviews.indices.compactMap { index -> Candidate? in
      let target = reviews[index].target
      guard let count = countsByTarget[target], count > 0 else { return nil }
      let phrase = index > 0 && !reviews[index - 1].target.isEmpty
        ? "\(reviews[index - 1].target) \(target)" : target
      return .init(index: index, phrase: phrase, count: count)
    }
    .sorted { lhs, rhs in lhs.count == rhs.count ? lhs.index < rhs.index : lhs.count > rhs.count }
    .prefix(maximumSelectedWords)
    let phrases = selected.flatMap { Array(repeating: $0.phrase, count: $0.count) }
    guard !phrases.isEmpty else { return nil }
    return .init(
      phrases: phrases, missedWordCount: phrases.count, selectedTargetCount: selected.count)
  }
}

/// Selects a bounded set of locally observed error targets, then repeats each
/// target by its actual error-event count. It intentionally accepts counts
/// supplied by the input engine rather than deriving guesses from final text.
struct MissedWordPracticePlan: Equatable {
  let selectedWords: [String]
  let exerciseWords: [String]

  static let maximumSelectedWords = 20

  static func make(
    errorCounts: [MissedWordErrorCount], maximumSelectedWords: Int = maximumSelectedWords
  ) -> Self? {
    let selected = errorCounts.enumerated()
      .filter { $0.element.count > 0 && !$0.element.word.isEmpty }
      .sorted { lhs, rhs in
        lhs.element.count == rhs.element.count ? lhs.offset < rhs.offset : lhs.element.count > rhs.element.count
      }
      .prefix(max(1, maximumSelectedWords))
      .map(\.element)
    guard !selected.isEmpty else { return nil }
    return .init(
      selectedWords: selected.map(\.word),
      exerciseWords: selected.flatMap { Array(repeating: $0.word, count: $0.count) })
  }
}

/// Combines independently observed missed and slow words into one bounded
/// local exercise. The smaller missed-word limit mirrors the reference
/// practice mode when slow words are included, while slow-word repetition is
/// ranked from slowest to fastest.
struct MissedAndSlowWordPracticePlan: Equatable {
  let exerciseWords: [String]
  let selectedTargetCount: Int

  static let maximumMissedWords = 10
  static let maximumSlowWords = 10

  static func make(
    missed: MissedWordPracticePlan?, slow: SlowWordPracticePlan?
  ) -> Self? {
    guard let missed, let slow else { return nil }
    let selectedMissed = Array(missed.selectedWords.prefix(maximumMissedWords))
    let selectedSlow = Array(slow.selectedWords.prefix(maximumSlowWords))
    guard !selectedMissed.isEmpty, !selectedSlow.isEmpty else { return nil }
    let missedSet = Set(selectedMissed)
    let missedWords = missed.exerciseWords.filter { missedSet.contains($0) }
    let slowWords = selectedSlow.enumerated().flatMap { index, word in
      Array(repeating: word, count: selectedSlow.count - index)
    }
    return .init(
      exerciseWords: missedWords + slowWords,
      selectedTargetCount: selectedMissed.count + selectedSlow.count)
  }
}

/// The contextual counterpart keeps the immediately preceding attempted word
/// attached to every missed target before it is combined with slow words.
struct ContextualMissedAndSlowWordPracticePlan: Equatable {
  let exerciseSegments: [String]
  let selectedTargetCount: Int

  static let maximumSlowWords = 10

  static func make(
    contextual: ContextualMissedWordPracticePlan?, slow: SlowWordPracticePlan?
  ) -> Self? {
    guard let contextual, let slow else { return nil }
    let selectedSlow = Array(slow.selectedWords.prefix(maximumSlowWords))
    guard contextual.selectedTargetCount > 0, !selectedSlow.isEmpty else { return nil }
    let slowSegments = selectedSlow.enumerated().flatMap { index, word in
      Array(repeating: word, count: selectedSlow.count - index)
    }
    return .init(
      exerciseSegments: contextual.phrases + slowSegments,
      selectedTargetCount: contextual.selectedTargetCount + selectedSlow.count)
  }
}

enum WordPracticeText {
  static func make(words: [String], language: TypingLanguage) -> String {
    words.joined(separator: language.usesSpaceDelimitedWords ? " " : "")
  }

  /// A practice run is a shuffled sequence of complete candidate sections.
  /// Rebuilding the small shuffled bag keeps error-frequency duplicates as
  /// weights while ensuring every candidate is revisited locally.
  static func sectionedPractice(
    segments: [String], selectedTargetCount: Int,
    random: () -> Int = { Int.random(in: Int.min...Int.max) }
  ) -> SectionedPractice? {
    let candidates = segments.filter { !$0.isEmpty }
    let sectionCount = selectedTargetCount * 5
    guard !candidates.isEmpty, sectionCount > 0 else { return nil }

    var practiceSections: [String] = []
    while practiceSections.count < sectionCount {
      var shuffled = candidates
      guard shuffled.count > 1 else {
        practiceSections.append(contentsOf: repeatElement(shuffled[0], count: sectionCount - practiceSections.count))
        break
      }
      for index in stride(from: shuffled.count - 1, through: 1, by: -1) {
        let swapIndex = Int(random().magnitude % UInt(index + 1))
        shuffled.swapAt(index, swapIndex)
      }
      practiceSections.append(contentsOf: shuffled.prefix(sectionCount - practiceSections.count))
    }
    return .init(text: practiceSections.joined(separator: " | "), sectionCount: sectionCount)
  }

  struct SectionedPractice: Equatable {
    let text: String
    let sectionCount: Int
  }
}

enum MissedWordCopyText {
  /// A copied list remains space separated even for unspaced languages, so
  /// individual locally identified targets can be read and reused elsewhere.
  static func make(words: [String]) -> String {
    words.joined(separator: " ")
  }
}

struct ResultPerformancePoint: Equatable, Identifiable {
  let elapsed: TimeInterval
  let wpm: Int
  let rawWpm: Int
  let burstWpm: Int
  let errorCount: Int

  var id: Int { Int((elapsed * 1_000).rounded()) }
}

struct ResultPerformanceVisibility: Codable, Equatable {
  var raw = true
  var burst = true
  var errors = true
}

enum ResultImageExport {
  static func filename(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return "typebar-result-\(formatter.string(from: date)).png"
  }
}

enum ResultInputText {
  static func make(for result: CompletedTestResult) -> String? {
    guard !result.replayEvents.isEmpty else { return nil }
    let elapsed = max(0, result.finishedAt.timeIntervalSince(result.startedAt))
    let typed = TypingReplay.typedText(events: result.replayEvents, through: elapsed)
    return typed.isEmpty ? nil : typed
  }
}

/// Builds the local equivalent of the completed-result "copy words" action.
/// Normal space-delimited tests copy the reached target words, whereas Zen
/// mode intentionally copies the user's open-ended input. Chinese prompts use
/// Typebar's own generated-word boundaries so a partial current word still
/// copies its complete target token.
enum ResultPromptText {
  static func make(for result: CompletedTestResult, reviews: [TypedWordReview]) -> String? {
    if result.configuration.mode == .zen {
      return ResultInputText.make(for: result)
    }

    if result.configuration.language.usesSpaceDelimitedWords,
      !result.configuration.modifiers.contains(.noSpaces)
    {
      let targets = reviews.map(\.target)
      return targets.isEmpty ? nil : targets.joined(separator: " ")
    }

    guard let typed = ResultInputText.make(for: result) else { return nil }
    let reachedCount = min(typed.count, result.prompt.count)
    guard reachedCount > 0 else { return nil }
    if result.configuration.language == .simplifiedChinese {
      return chineseTargetText(prompt: result.prompt, reachedCharacterCount: reachedCount)
    }
    return String(result.prompt.prefix(reachedCount))
  }

  private static func chineseTargetText(prompt: String, reachedCharacterCount: Int) -> String {
    let characters = Array(prompt)
    let tokens = StarterLexicon.simplifiedChineseWords
      .map { Array($0) }
      .sorted { $0.count > $1.count }
    let trailingPunctuation: Set<Character> = ["，", "。", "！", "？", "：", "；"]
    var index = 0

    while index < characters.count {
      let coreStart = characters[index] == "（" ? index + 1 : index
      guard let token = tokens.first(where: { token in
        let end = coreStart + token.count
        return end <= characters.count && characters[coreStart..<end].elementsEqual(token)
      })
      else {
        if index >= reachedCharacterCount { break }
        index += 1
        continue
      }

      var end = coreStart + token.count
      if end < characters.count, characters[end] == "）" { end += 1 }
      if end < characters.count, trailingPunctuation.contains(characters[end]) { end += 1 }
      if reachedCharacterCount > index && reachedCharacterCount <= end {
        return String(characters.prefix(end))
      }
      index = end
    }
    return String(characters.prefix(reachedCharacterCount))
  }
}

/// Local result consistency values reconstructed from Typebar's own replay.
/// They intentionally remain derived data: existing archives with no replay
/// safely show zero instead of inventing a cadence statistic.
struct ResultConsistency: Equatable {
  let typing: Double
  let key: Double
}

enum ResultConsistencyPolicy {
  static func metrics(events: [TypingReplayEvent], duration: TimeInterval) -> ResultConsistency {
    let ordered = events.enumerated().sorted { lhs, rhs in
      lhs.element.offset == rhs.element.offset ? lhs.offset < rhs.offset : lhs.element.offset < rhs.element.offset
    }.map(\.element)
    let typingSamples = typingSpeeds(events: ordered, duration: duration)
    let keySpacing = keySpacings(events: ordered)
    return .init(
      typing: consistency(for: typingSamples),
      key: consistency(for: Array(keySpacing.dropLast())))
  }

  private static func typingSpeeds(
    events: [TypingReplayEvent], duration: TimeInterval
  ) -> [Double] {
    guard duration > 0 else { return [] }
    let wholeSeconds = Int(duration.rounded(.down))
    var boundaries = wholeSeconds > 0 ? (1...wholeSeconds).map(TimeInterval.init) : []
    let fractionalTail = duration - Double(wholeSeconds)
    if fractionalTail >= 0.5 { boundaries.append(duration) }

    var previousBoundary: TimeInterval = 0
    return boundaries.map { boundary in
      let characters = events.reduce(into: 0) { count, event in
        guard event.kind == .insert, event.offset > previousBoundary, event.offset <= boundary else { return }
        count += event.text.count
      }
      defer { previousBoundary = boundary }
      let interval = boundary - previousBoundary
      guard interval > 0 else { return 0 }
      return Double(Int((Double(characters) / 5 / interval * 60).rounded()))
    }
  }

  private static func keySpacings(events: [TypingReplayEvent]) -> [TimeInterval] {
    let keyEvents = events.filter { $0.kind == .insert || $0.kind == .delete }
    return zip(keyEvents, keyEvents.dropFirst()).map { earlier, later in
      max(0, later.offset - earlier.offset)
    }
  }

  private static func consistency(for samples: [Double]) -> Double {
    guard !samples.isEmpty else { return 0 }
    let average = samples.reduce(0, +) / Double(samples.count)
    guard average > 0 else { return 0 }
    let variance = samples.reduce(0) { partial, sample in
      partial + pow(sample - average, 2)
    } / Double(samples.count)
    let coefficientOfVariation = sqrt(variance) / average
    let mapped = 100 * (
      1 - tanh(
        coefficientOfVariation
          + pow(coefficientOfVariation, 3) / 3
          + pow(coefficientOfVariation, 5) / 5
      )
    )
    guard mapped.isFinite else { return 0 }
    return (mapped * 100).rounded() / 100
  }
}

/// Rebuilds a compact, local-only result trace from the input replay that is
/// already saved with a completed test. It uses Typebar's own incremental
/// character accounting and deliberately has a conservative duration cap so
/// a long practice session cannot create an impractically dense result chart.
enum ResultPerformanceTrace {
  static let maximumChartDuration: TimeInterval = 120

  static func points(
    prompt: String,
    events: [TypingReplayEvent],
    duration: TimeInterval
  ) -> [ResultPerformancePoint] {
    guard !prompt.isEmpty, !events.isEmpty,
      duration > 0, duration <= maximumChartDuration
    else { return [] }

    let sampleTimes = samplingTimes(for: duration)
    let orderedEvents = events.enumerated().sorted { lhs, rhs in
      lhs.element.offset == rhs.element.offset ? lhs.offset < rhs.offset : lhs.element.offset < rhs.element.offset
    }.map(\.element)
    var eventIndex = 0
    var typed: [Character] = []
    var forcedErrors: [Bool] = []
    var characterTimes: [TimeInterval] = []

    return sampleTimes.map { elapsed in
      while eventIndex < orderedEvents.count, orderedEvents[eventIndex].offset <= elapsed {
        apply(
          orderedEvents[eventIndex],
          typed: &typed,
          forcedErrors: &forcedErrors,
          characterTimes: &characterTimes)
        eventIndex += 1
      }
      let errors = errorCount(typed: typed, prompt: Array(prompt), forcedErrors: forcedErrors)
      let correct = max(0, typed.count - errors)
      return .init(
        elapsed: elapsed,
        wpm: wpm(characters: correct, elapsed: elapsed),
        rawWpm: wpm(characters: typed.count, elapsed: elapsed),
        burstWpm: burst(typed: typed, dates: characterTimes),
        errorCount: errors)
    }
  }

  private static func samplingTimes(for duration: TimeInterval) -> [TimeInterval] {
    guard duration >= 1 else { return [duration] }
    let completedSeconds = Int(duration.rounded(.down))
    var samples = (1...completedSeconds).map(TimeInterval.init)
    if abs((samples.last ?? 0) - duration) > 0.001 {
      samples.append(duration)
    }
    return samples
  }

  private static func apply(
    _ event: TypingReplayEvent,
    typed: inout [Character],
    forcedErrors: inout [Bool],
    characterTimes: inout [TimeInterval]
  ) {
    switch event.kind {
    case .insert:
      for character in event.text {
        typed.append(character)
        forcedErrors.append(event.forceError)
        characterTimes.append(event.offset)
      }
    case .delete:
      guard !typed.isEmpty else { return }
      typed.removeLast()
      forcedErrors.removeLast()
      characterTimes.removeLast()
    }
  }

  private static func errorCount(
    typed: [Character], prompt: [Character], forcedErrors: [Bool]
  ) -> Int {
    typed.indices.reduce(into: 0) { count, index in
      if index >= prompt.count || typed[index] != prompt[index] || forcedErrors[index] {
        count += 1
      }
    }
  }

  private static func wpm(characters: Int, elapsed: TimeInterval) -> Int {
    Int((Double(characters) / 5 / max(elapsed, 1) * 60).rounded())
  }

  private static func burst(typed: [Character], dates: [TimeInterval]) -> Int {
    guard typed.count == dates.count, !typed.isEmpty else { return 0 }
    let lastCharacter = typed.count - 1
    let wordEnd: Int
    let wordStart: Int
    if typed[lastCharacter] == " " {
      wordEnd = lastCharacter
      wordStart = typed[..<wordEnd].lastIndex(of: " ").map { $0 + 1 } ?? 0
    } else {
      wordEnd = lastCharacter
      wordStart = typed[..<typed.count].lastIndex(of: " ").map { $0 + 1 } ?? 0
    }
    let elapsed = dates[wordEnd] - dates[wordStart]
    guard elapsed > 0 else { return 0 }
    let characters = wordEnd - wordStart + 1 + (typed[wordEnd] == " " ? 0 : 1)
    return wpm(characters: characters, elapsed: elapsed)
  }
}

/// Mirrors the official current-settings average with Typebar's locally stored
/// result model. Tags are deliberately absent because the native practice screen
/// has no active tag-filter state.
enum RecentTestAveragePolicy {
  static func average(
    currentConfiguration: TestConfiguration,
    currentPrompt: String,
    samples: [RecentAverageSample],
    limit: Int = 10
  ) -> RecentTestAverage? {
    guard limit > 0 else { return nil }
    let matching = matchingSamples(
      currentConfiguration: currentConfiguration, currentPrompt: currentPrompt, samples: samples)
      .prefix(limit)

    guard !matching.isEmpty else { return nil }
    let count = matching.count
    let averageWpm = Int(
      (Double(matching.map(\.wpm).reduce(0, +)) / Double(count)).rounded())
    let averageAccuracy = Int(
      (Double(matching.map(\.accuracy).reduce(0, +)) / Double(count)).rounded())
    return .init(count: count, wpm: averageWpm, accuracy: averageAccuracy)
  }

  /// Uses the setting fields the reference project uses for local average and
  /// PB lookup. Modifiers other than simplified input intentionally do not
  /// split this collection; PB eligibility is applied by its own policy.
  static func matchingSamples(
    currentConfiguration: TestConfiguration,
    currentPrompt: String,
    samples: [RecentAverageSample]
  ) -> [RecentAverageSample] {
    samples
      .filter {
        matches(
          sample: $0, currentConfiguration: currentConfiguration, currentPrompt: currentPrompt)
      }
      .sorted { $0.finishedAt > $1.finishedAt }
  }

  private static func matches(
    sample: RecentAverageSample,
    currentConfiguration: TestConfiguration,
    currentPrompt: String
  ) -> Bool {
    let sampleConfiguration = sample.configuration
    return sampleConfiguration.mode == currentConfiguration.mode
      && sameModeParameter(sampleConfiguration, currentConfiguration)
      && (currentConfiguration.mode != .quote || sample.prompt == currentPrompt)
      && sampleConfiguration.contentOptions == currentConfiguration.contentOptions
      && sampleConfiguration.language == currentConfiguration.language
      && sampleConfiguration.difficulty == currentConfiguration.difficulty
      && sampleConfiguration.modifiers.contains(.lazyLatin)
        == currentConfiguration.modifiers.contains(.lazyLatin)
  }

  private static func sameModeParameter(
    _ sample: TestConfiguration, _ current: TestConfiguration
  ) -> Bool {
    switch current.mode {
    case .time:
      sample.duration == current.duration
    case .words:
      sample.wordLimit == current.wordLimit
    case .quote:
      true
    case .zen, .custom:
      true
    }
  }
}

/// Determines whether a locally completed Typebar result may contribute to a
/// current-setting personal best. It mirrors the reference funbox eligibility
/// while also excluding Typebar-only corrective modifiers that alter scoring.
enum CurrentPersonalBestPolicy {
  static func personalBest(
    currentConfiguration: TestConfiguration,
    currentPrompt: String,
    samples: [RecentAverageSample]
  ) -> CurrentPersonalBest? {
    guard isConfigurationEligible(currentConfiguration) else { return nil }
    let matching = RecentTestAveragePolicy.matchingSamples(
      currentConfiguration: currentConfiguration, currentPrompt: currentPrompt, samples: samples)
      .filter { isResultEligible(configuration: $0.configuration, accuracy: $0.accuracy) }
    guard let highestWpm = matching.map(\.wpm).max(),
      let best = matching.filter({ $0.wpm == highestWpm }).min(by: { $0.finishedAt < $1.finishedAt })
    else {
      return nil
    }
    return .init(wpm: best.wpm, accuracy: best.accuracy)
  }

  static func isConfigurationEligible(_ configuration: TestConfiguration) -> Bool {
    configuration.mode != .quote
      && configuration.language != .mixedEnglishChinese
      && configuration.language != .mixedLanguages
      && configuration.modifiers.allSatisfy(modifierAllowsPersonalBest)
  }

  static func isResultEligible(configuration: TestConfiguration, accuracy: Int) -> Bool {
    isConfigurationEligible(configuration)
      && (!configuration.rules.stopOnError || accuracy == 100)
  }

  private static func modifierAllowsPersonalBest(_ modifier: TestModifier) -> Bool {
    switch modifier {
    case .noSpaces, .underscoreSeparators, .uppercase, .titleCase, .alternatingCase, .randomCase,
      .messagingStyle, .binaryStream, .accountingStream, .hexadecimalStream, .symbolStream,
      .asciiStream, .specialCharacterStream, .gibberishStream, .poetryStream, .referenceStream,
      .arrowStream, .ipv4Stream, .ipv6Stream, .pseudolangStream, .morseStream, .zipf,
      .correctBeforeAdvance, .clearCurrentWordOnError:
      false
    case .mirrorVisual, .upsideDownVisual, .crtVisual, .earthquakeVisual, .spaceVisual,
      .nauseaVisual, .roundVisual, .chooVisual, .layoutFluid, .aslVisual, .rot13, .backwards,
      .doubleCharacters, .listening, .simonSays, .memory, .readAheadEasy, .readAhead,
      .readAheadHard, .noQuit, .mirrorKeyboard, .focusCurrentWord, .focusNextWord,
      .focusTwoWords, .focusThreeWords, .lazyLatin:
      true
    }
  }
}

enum ResultHistoryDateRange: String, CaseIterable, Codable, Equatable {
    case all
    case lastDay
    case lastWeek
    case lastMonth
    case lastThreeMonths

    var displayName: String {
        switch self {
        case .all: "全部时间"
        case .lastDay: "最近 24 小时"
        case .lastWeek: "最近 7 天"
        case .lastMonth: "最近 30 天"
        case .lastThreeMonths: "最近 90 天"
        }
    }

    func cutoff(relativeTo now: Date) -> Date? {
        let seconds: TimeInterval?
        switch self {
        case .all: seconds = nil
        case .lastDay: seconds = 24 * 60 * 60
        case .lastWeek: seconds = 7 * 24 * 60 * 60
        case .lastMonth: seconds = 30 * 24 * 60 * 60
        case .lastThreeMonths: seconds = 90 * 24 * 60 * 60
        }
        return seconds.map { now.addingTimeInterval(-$0) }
    }
}

enum ResultHistoryBinaryFilter: String, CaseIterable, Codable, Equatable {
    case all
    case included
    case excluded
    case noMatches

    var displayName: String {
        switch self {
        case .all: "全部"
        case .included: "包含"
        case .excluded: "不包含"
        case .noMatches: "无匹配项"
        }
    }

    func matches(_ value: Bool?) -> Bool {
        switch self {
        case .all: true
        case .included: value == true
        case .excluded: value == false
        case .noMatches: false
        }
    }
}

enum ResultHistoryPersonalBestFilter: String, CaseIterable, Codable, Equatable {
    case all
    case only
    case excluded
    case noMatches

    var displayName: String {
        switch self {
        case .all: "全部"
        case .only: "仅个人最佳"
        case .excluded: "排除个人最佳"
        case .noMatches: "无匹配项"
        }
    }

    func matches(id: UUID, personalBestIDs: Set<UUID>) -> Bool {
        switch self {
        case .all: true
        case .only: personalBestIDs.contains(id)
        case .excluded: !personalBestIDs.contains(id)
        case .noMatches: false
        }
    }
}

enum ResultHistoryTimeLimit: String, CaseIterable, Codable, Hashable {
    case seconds15 = "15"
    case seconds30 = "30"
    case seconds60 = "60"
    case seconds120 = "120"
    case custom

    var displayName: String {
        switch self {
        case .seconds15: "15 秒"
        case .seconds30: "30 秒"
        case .seconds60: "60 秒"
        case .seconds120: "120 秒"
        case .custom: "自定义"
        }
    }

    func matches(_ duration: TimeInterval?) -> Bool {
        guard let duration else { return self == .custom }
        let rounded = Int(duration.rounded())
        let isWholeSecond = abs(duration - TimeInterval(rounded)) < 0.0001
        switch self {
        case .seconds15: return isWholeSecond && rounded == 15
        case .seconds30: return isWholeSecond && rounded == 30
        case .seconds60: return isWholeSecond && rounded == 60
        case .seconds120: return isWholeSecond && rounded == 120
        case .custom: return !isWholeSecond || ![15, 30, 60, 120].contains(rounded)
        }
    }

    static func selectionSummary(_ selection: Set<Self>) -> String {
        guard !selection.isEmpty else { return "无匹配档位" }
        guard selection != Set(allCases) else { return "全部" }
        return allCases.filter(selection.contains).map(\.displayName).joined(separator: "、")
    }
}

enum ResultHistoryWordLimit: String, CaseIterable, Codable, Hashable {
    case words10 = "10"
    case words25 = "25"
    case words50 = "50"
    case words100 = "100"
    case custom

    var displayName: String {
        switch self {
        case .words10: "10 词"
        case .words25: "25 词"
        case .words50: "50 词"
        case .words100: "100 词"
        case .custom: "自定义"
        }
    }

    func matches(_ wordLimit: Int?) -> Bool {
        switch self {
        case .words10: wordLimit == 10
        case .words25: wordLimit == 25
        case .words50: wordLimit == 50
        case .words100: wordLimit == 100
        case .custom: ![10, 25, 50, 100].contains(wordLimit ?? -1)
        }
    }

    static func selectionSummary(_ selection: Set<Self>) -> String {
        guard !selection.isEmpty else { return "无匹配档位" }
        guard selection != Set(allCases) else { return "全部" }
        return allCases.filter(selection.contains).map(\.displayName).joined(separator: "、")
    }
}

struct ResultHistoryModifierFilter: Codable, Equatable {
    var includesNoModifiers: Bool
    var modifiers: Set<TestModifier>

    init(
        includesNoModifiers: Bool = true,
        modifiers: Set<TestModifier> = Set(TestModifier.allCases)
    ) {
        self.includesNoModifiers = includesNoModifiers
        self.modifiers = modifiers
    }

    var isUnfiltered: Bool {
        includesNoModifiers && modifiers == Set(TestModifier.allCases)
    }

    func matches(_ entryModifiers: [TestModifier]?) -> Bool {
        guard !isUnfiltered else { return true }
        guard let entryModifiers else { return false }
        return (includesNoModifiers && entryModifiers.isEmpty)
            || !modifiers.isDisjoint(with: entryModifiers)
    }

    var selectionSummary: String {
        guard !includesNoModifiers || !modifiers.isEmpty else { return "无匹配修饰器" }
        guard !isUnfiltered else { return "全部" }
        let selected = TestModifier.allCases.filter(modifiers.contains).map(\.displayName)
        let labels = (includesNoModifiers ? ["无修饰器"] : []) + selected
        return labels.count <= 3 ? labels.joined(separator: "、") : "已选 \(labels.count) 项"
    }
}

struct ResultHistoryTagFilter: Codable, Equatable {
    var isUnrestricted: Bool
    var includesNoTags: Bool
    var tags: Set<String>

    init(
        isUnrestricted: Bool = true,
        includesNoTags: Bool = true,
        tags: Set<String> = []
    ) {
        self.isUnrestricted = isUnrestricted
        self.includesNoTags = includesNoTags
        self.tags = tags
    }

    func matches(_ entryTags: [String]) -> Bool {
        guard !isUnrestricted else { return true }
        return (includesNoTags && entryTags.isEmpty)
            || entryTags.contains(where: tags.contains)
    }

    func isTagSelected(_ tag: String) -> Bool {
        isUnrestricted || tags.contains(tag)
    }

    var isNoTagsSelected: Bool {
        isUnrestricted || includesNoTags
    }

    var selectionSummary: String {
        guard !isUnrestricted else { return "全部" }
        guard includesNoTags || !tags.isEmpty else { return "无匹配标签" }
        let labels = (includesNoTags ? ["无标签"] : []) + tags.sorted()
        return labels.count <= 3 ? labels.joined(separator: "、") : "已选 \(labels.count) 项"
    }

    mutating func setNoTagsSelected(_ selected: Bool, availableTags: Set<String>) {
        prepareForExplicitSelection(availableTags: availableTags)
        includesNoTags = selected
    }

    mutating func setTag(_ tag: String, selected: Bool, availableTags: Set<String>) {
        prepareForExplicitSelection(availableTags: availableTags)
        if selected { tags.insert(tag) } else { tags.remove(tag) }
    }

    private mutating func prepareForExplicitSelection(availableTags: Set<String>) {
        guard isUnrestricted else { return }
        isUnrestricted = false
        includesNoTags = true
        tags = availableTags
    }
}

struct ResultHistoryFilter: Codable, Equatable {
    var mode: TestMode?
    var modes: Set<TestMode>?
    var language: TypingLanguage?
    var languages: Set<TypingLanguage>?
    var tag: String?
    var tagFilter: ResultHistoryTagFilter?
    var difficulty: Difficulty?
    var difficulties: Set<Difficulty>?
    var personalBestOnly: Bool
    var personalBestFilter: ResultHistoryPersonalBestFilter?
    var dateRange: ResultHistoryDateRange
    var punctuation: ResultHistoryBinaryFilter
    var numbers: ResultHistoryBinaryFilter
    var quoteLength: QuoteLength?
    var quoteLengths: Set<QuoteLength>?
    var timeLimits: Set<ResultHistoryTimeLimit>
    var wordLimits: Set<ResultHistoryWordLimit>
    var modifierFilter: ResultHistoryModifierFilter

    init(
        mode: TestMode? = nil, language: TypingLanguage? = nil,
        modes: Set<TestMode>? = nil,
        languages: Set<TypingLanguage>? = nil, tag: String? = nil,
        tagFilter: ResultHistoryTagFilter? = nil,
        personalBestOnly: Bool = false,
        personalBestFilter: ResultHistoryPersonalBestFilter? = nil,
        difficulty: Difficulty? = nil,
        difficulties: Set<Difficulty>? = nil,
        dateRange: ResultHistoryDateRange = .all,
        punctuation: ResultHistoryBinaryFilter = .all, numbers: ResultHistoryBinaryFilter = .all,
        quoteLength: QuoteLength? = nil,
        quoteLengths: Set<QuoteLength>? = nil,
        timeLimits: Set<ResultHistoryTimeLimit> = Set(ResultHistoryTimeLimit.allCases),
        wordLimits: Set<ResultHistoryWordLimit> = Set(ResultHistoryWordLimit.allCases),
        modifierFilter: ResultHistoryModifierFilter = .init()
    ) {
        self.mode = mode
        self.modes = modes
        self.language = language
        self.languages = languages
        self.tag = tag
        self.tagFilter = tagFilter
        self.difficulty = difficulty
        self.difficulties = difficulties
        self.personalBestOnly = personalBestOnly
        self.personalBestFilter = personalBestFilter
        self.dateRange = dateRange
        self.punctuation = punctuation
        self.numbers = numbers
        self.quoteLength = quoteLength
        self.quoteLengths = quoteLengths
        self.timeLimits = timeLimits
        self.wordLimits = wordLimits
        self.modifierFilter = modifierFilter
    }

    /// Mirrors the reference product's "current settings" history shortcut
    /// using only Typebar's current local test configuration. Typebar tags are
    /// assigned to completed results and have no separate active-tag state, so
    /// the shortcut deliberately leaves them unrestricted.
    static func currentSettings(_ configuration: TestConfiguration) -> Self {
        let selectedModifiers = Set(configuration.modifiers)
        let timeLimits: Set<ResultHistoryTimeLimit> = configuration.mode == .time
            ? Set(ResultHistoryTimeLimit.allCases.filter { $0.matches(configuration.duration) })
            : Set(ResultHistoryTimeLimit.allCases)
        let wordLimits: Set<ResultHistoryWordLimit> = configuration.mode == .words
            ? Set(ResultHistoryWordLimit.allCases.filter { $0.matches(configuration.wordLimit) })
            : Set(ResultHistoryWordLimit.allCases)

        return .init(
            modes: [configuration.mode],
            languages: [configuration.language],
            difficulties: [configuration.difficulty],
            punctuation: configuration.contentOptions.includePunctuation ? .included : .excluded,
            numbers: configuration.contentOptions.includeNumbers ? .included : .excluded,
            quoteLengths: configuration.mode == .quote && configuration.quoteLength != .all
                ? [configuration.quoteLength] : Self.filterableQuoteLengths,
            timeLimits: timeLimits,
            wordLimits: wordLimits,
            modifierFilter: .init(
                includesNoModifiers: selectedModifiers.isEmpty,
                modifiers: selectedModifiers
            )
        )
    }

    var languageSelections: Set<TypingLanguage> {
        languages ?? language.map { [$0] } ?? Set(TypingLanguage.allCases)
    }

    /// New presets can mirror the reference product's independently toggled
    /// mode records. Older Typebar presets stored one optional mode, so retain
    /// that representation as the decoding fallback.
    var modeSelections: Set<TestMode> {
        modes ?? mode.map { [$0] } ?? Set(TestMode.allCases)
    }

    /// New presets can preserve several difficulty toggles. The original
    /// optional field remains the fallback for already-saved local presets.
    var difficultySelections: Set<Difficulty> {
        difficulties ?? difficulty.map { [$0] } ?? Set(Difficulty.allCases)
    }

    static let filterableQuoteLengths = Set(QuoteLength.allCases.filter { $0 != .all })

    /// Result records outside quote mode use the reference product's fallback
    /// bucket. A newly-created partial selection therefore filters quote rows
    /// only and retains other modes. Legacy one-length presets retain their
    /// prior Typebar-only exact-match behavior.
    var quoteLengthSelections: Set<QuoteLength> {
        quoteLengths ?? quoteLength.map { [$0] } ?? Self.filterableQuoteLengths
    }

    var effectiveTagFilter: ResultHistoryTagFilter {
        if let tagFilter { return tagFilter }
        guard let tag else { return .init() }
        return .init(isUnrestricted: false, includesNoTags: false, tags: [tag])
    }

    var effectivePersonalBestFilter: ResultHistoryPersonalBestFilter {
        personalBestFilter ?? (personalBestOnly ? .only : .all)
    }

    static func languageSelectionSummary(_ selection: Set<TypingLanguage>) -> String {
        guard !selection.isEmpty else { return "无匹配语言" }
        guard selection != Set(TypingLanguage.allCases) else { return "全部" }
        let names = TypingLanguage.allCases.filter(selection.contains).map(\.displayName)
        return names.count <= 3 ? names.joined(separator: "、") : "已选 \(names.count) 种"
    }

    static func modeSelectionSummary(_ selection: Set<TestMode>) -> String {
        guard !selection.isEmpty else { return "无匹配模式" }
        guard selection != Set(TestMode.allCases) else { return "全部" }
        let names = TestMode.allCases.filter(selection.contains).map(\.displayName)
        return names.count <= 3 ? names.joined(separator: "、") : "已选 \(names.count) 种"
    }

    static func difficultySelectionSummary(_ selection: Set<Difficulty>) -> String {
        guard !selection.isEmpty else { return "无匹配难度" }
        guard selection != Set(Difficulty.allCases) else { return "全部" }
        let names = Difficulty.allCases.filter(selection.contains).map(\.displayName)
        return names.joined(separator: "、")
    }

    static func quoteLengthSelectionSummary(_ selection: Set<QuoteLength>) -> String {
        guard !selection.isEmpty else { return "仅非引语" }
        guard selection != filterableQuoteLengths else { return "全部" }
        let names = QuoteLength.allCases.filter(selection.contains).map(\.displayName)
        return names.count <= 3 ? names.joined(separator: "、") : "已选 \(names.count) 项"
    }

    private enum CodingKeys: String, CodingKey {
        case mode, modes, language, languages, tag, tagFilter, difficulty, difficulties, personalBestOnly, personalBestFilter, dateRange, punctuation, numbers, quoteLength,
          quoteLengths, timeLimits, wordLimits, modifierFilter
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        mode = try values.decodeIfPresent(TestMode.self, forKey: .mode)
        modes = try values.decodeIfPresent(Set<TestMode>.self, forKey: .modes)
        language = try values.decodeIfPresent(TypingLanguage.self, forKey: .language)
        languages = try values.decodeIfPresent(Set<TypingLanguage>.self, forKey: .languages)
        tag = try values.decodeIfPresent(String.self, forKey: .tag)
        tagFilter = try values.decodeIfPresent(ResultHistoryTagFilter.self, forKey: .tagFilter)
        difficulty = try values.decodeIfPresent(Difficulty.self, forKey: .difficulty)
        difficulties = try values.decodeIfPresent(Set<Difficulty>.self, forKey: .difficulties)
        personalBestOnly = try values.decodeIfPresent(Bool.self, forKey: .personalBestOnly) ?? false
        personalBestFilter = try values.decodeIfPresent(
            ResultHistoryPersonalBestFilter.self, forKey: .personalBestFilter)
        dateRange = try values.decodeIfPresent(ResultHistoryDateRange.self, forKey: .dateRange) ?? .all
        punctuation = try values.decodeIfPresent(ResultHistoryBinaryFilter.self, forKey: .punctuation) ?? .all
        numbers = try values.decodeIfPresent(ResultHistoryBinaryFilter.self, forKey: .numbers) ?? .all
        quoteLength = try values.decodeIfPresent(QuoteLength.self, forKey: .quoteLength)
        quoteLengths = try values.decodeIfPresent(Set<QuoteLength>.self, forKey: .quoteLengths)
        timeLimits = try values.decodeIfPresent(Set<ResultHistoryTimeLimit>.self, forKey: .timeLimits)
          ?? Set(ResultHistoryTimeLimit.allCases)
        wordLimits = try values.decodeIfPresent(Set<ResultHistoryWordLimit>.self, forKey: .wordLimits)
          ?? Set(ResultHistoryWordLimit.allCases)
        modifierFilter = try values.decodeIfPresent(ResultHistoryModifierFilter.self, forKey: .modifierFilter)
          ?? .init()
    }

    func matchingIDs(
        entries: [ResultHistoryEntry], personalBestIDs: Set<UUID>, now: Date = .now
    ) -> Set<UUID> {
        let cutoff = dateRange.cutoff(relativeTo: now)
        return Set(entries.filter { entry in
            matchesMode(entry.mode)
                && matchesLanguage(entry.language)
                && effectiveTagFilter.matches(entry.tags)
                && matchesDifficulty(entry.difficulty)
                && effectivePersonalBestFilter.matches(id: entry.id, personalBestIDs: personalBestIDs)
                && (cutoff.map { entry.finishedAt >= $0 } ?? true)
                && punctuation.matches(entry.includesPunctuation)
                && numbers.matches(entry.includesNumbers)
                && matchesQuoteLength(entry.quoteLength)
                && matchesTimeLimit(entry)
                && matchesWordLimit(entry)
                && modifierFilter.matches(entry.modifiers)
        }.map(\.id))
    }

    private func matchesTimeLimit(_ entry: ResultHistoryEntry) -> Bool {
        entry.mode != .time || timeLimits.contains { $0.matches(entry.duration) }
    }

    private func matchesMode(_ entryMode: TestMode?) -> Bool {
        let selection = modeSelections
        guard selection != Set(TestMode.allCases) else { return true }
        return entryMode.map(selection.contains) ?? false
    }

    private func matchesDifficulty(_ entryDifficulty: Difficulty?) -> Bool {
        let selection = difficultySelections
        guard selection != Set(Difficulty.allCases) else { return true }
        return entryDifficulty.map(selection.contains) ?? false
    }

    private func matchesQuoteLength(_ entryQuoteLength: QuoteLength?) -> Bool {
        if let quoteLengths {
            guard quoteLengths != Self.filterableQuoteLengths else { return true }
            return entryQuoteLength.map(quoteLengths.contains) ?? true
        }
        return quoteLength == nil || entryQuoteLength == quoteLength
    }

    private func matchesLanguage(_ entryLanguage: TypingLanguage?) -> Bool {
        let selection = languageSelections
        guard selection != Set(TypingLanguage.allCases) else { return true }
        return entryLanguage.map(selection.contains) ?? false
    }

    private func matchesWordLimit(_ entry: ResultHistoryEntry) -> Bool {
        entry.mode != .words || wordLimits.contains { $0.matches(entry.wordLimit) }
    }
}

struct ResultStatistics: Equatable {
    let completedTests: Int
    let averageWPM: Int
    let bestWPM: Int
    let averageAccuracy: Int
    let totalTypingSeconds: TimeInterval
    let highestConsistency: Double
    let averageConsistency: Double
    let averageConsistencyLast10: Double

    init(metrics: [ResultMetric]) {
        completedTests = metrics.count
        averageWPM = metrics.isEmpty ? 0 : Int((Double(metrics.map(\.wpm).reduce(0, +)) / Double(metrics.count)).rounded())
        bestWPM = metrics.map(\.wpm).max() ?? 0
        averageAccuracy = metrics.isEmpty ? 0 : Int((Double(metrics.map(\.accuracy).reduce(0, +)) / Double(metrics.count)).rounded())
        totalTypingSeconds = metrics.map(\.typingSeconds).reduce(0, +)
        highestConsistency = metrics.map(\.consistency).max() ?? 0
        averageConsistency = Self.averageConsistency(metrics)
        averageConsistencyLast10 = Self.averageConsistency(Array(metrics.prefix(10)))
    }

    private static func averageConsistency(_ metrics: [ResultMetric]) -> Double {
        guard !metrics.isEmpty else { return 0 }
        return metrics.map(\.consistency).reduce(0, +) / Double(metrics.count)
    }

    static func personalBestIDs(metrics: [ResultMetric]) -> Set<UUID> {
        guard let bestWPM = metrics.map(\.wpm).max() else { return [] }
        return Set(metrics.filter { $0.wpm == bestWPM }.map(\.id))
    }
}

struct WPMHistogramBucket: Equatable, Identifiable {
    let lowerBound: Int
    let upperBound: Int
    let count: Int

    var id: Int { lowerBound }
    var label: String { "\(lowerBound)–\(upperBound)" }
}

/// Groups the selected local results into stable speed intervals. Keeping empty intervals
/// makes a genuine gap in the distribution visible instead of implying a continuous run.
enum WPMHistogram {
    static func buckets(metrics: [ResultMetric], interval: Int = 10) -> [WPMHistogramBucket] {
        guard let lowestWPM = metrics.map(\.wpm).min(), let highestWPM = metrics.map(\.wpm).max() else {
            return []
        }

        let interval = max(interval, 1)
        let firstLowerBound = max(0, (lowestWPM / interval) * interval)
        let finalExclusiveBound = max(
            firstLowerBound + interval,
            ((highestWPM / interval) + 1) * interval
        )

        return stride(from: firstLowerBound, to: finalExclusiveBound, by: interval).map { lowerBound in
            let upperBound = lowerBound + interval - 1
            return WPMHistogramBucket(
                lowerBound: lowerBound,
                upperBound: upperBound,
                count: metrics.filter { lowerBound...upperBound ~= $0.wpm }.count
            )
        }
    }
}

struct DailyActivity: Equatable, Identifiable {
    let day: Date
    let completedTests: Int
    let typingSeconds: TimeInterval
    let averageConsistency: Double

    init(
        day: Date, completedTests: Int, typingSeconds: TimeInterval, averageConsistency: Double = 0
    ) {
        self.day = day
        self.completedTests = completedTests
        self.typingSeconds = typingSeconds
        self.averageConsistency = averageConsistency.isFinite ? min(100, max(0, averageConsistency)) : 0
    }

    var id: Date { day }
}

/// A fixed recent-day series is deliberately separate from `DailyActivity`: charts need
/// zero-value days too, otherwise time gaps visually collapse into adjacent bars.
struct ActivityBarPoint: Equatable, Identifiable {
    let day: Date
    let completedTests: Int
    let typingSeconds: TimeInterval
    let averageConsistency: Double

    init(
        day: Date, completedTests: Int, typingSeconds: TimeInterval, averageConsistency: Double = 0
    ) {
        self.day = day
        self.completedTests = completedTests
        self.typingSeconds = typingSeconds
        self.averageConsistency = averageConsistency.isFinite ? min(100, max(0, averageConsistency)) : 0
    }

    var id: Date { day }
}

struct ActivityHeatmapCell: Equatable, Identifiable {
    let day: Date
    let completedTests: Int
    var id: Date { day }

    var intensity: Int {
        switch completedTests {
        case 0: 0
        case 1: 1
        case 2...3: 2
        case 4...6: 3
        default: 4
        }
    }
}

enum ActivityAggregation {
    static func daily(metrics: [ResultMetric], calendar: Calendar = .current) -> [DailyActivity] {
        let grouped = Dictionary(grouping: metrics) { calendar.startOfDay(for: $0.finishedAt) }
        return grouped.map { day, values in
            DailyActivity(
                day: day,
                completedTests: values.count,
                typingSeconds: values.map(\.typingSeconds).reduce(0, +),
                averageConsistency: values.map(\.consistency).reduce(0, +) / Double(values.count)
            )
        }
        .sorted { $0.day < $1.day }
    }

    static func currentStreak(activity: [DailyActivity], today: Date = .now, calendar: Calendar = .current) -> Int {
        let days = Set(activity.filter { $0.completedTests > 0 }.map { calendar.startOfDay(for: $0.day) })
        var cursor = calendar.startOfDay(for: today)
        var streak = 0
        while days.contains(cursor) {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return streak
    }

    static func recentDays(
        activity: [DailyActivity],
        days: Int = 28,
        endingAt endDate: Date = .now,
        calendar: Calendar = .current
    ) -> [ActivityBarPoint] {
        guard days > 0 else { return [] }
        let byDay = Dictionary(uniqueKeysWithValues: activity.map {
            (calendar.startOfDay(for: $0.day), $0)
        })
        let end = calendar.startOfDay(for: endDate)
        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset - days + 1, to: end) else { return nil }
            let value = byDay[day]
            return ActivityBarPoint(
                day: day,
                completedTests: value?.completedTests ?? 0,
                typingSeconds: value?.typingSeconds ?? 0,
                averageConsistency: value?.averageConsistency ?? 0
            )
        }
    }
}

enum ActivityHeatmap {
    static func cells(
        activity: [DailyActivity],
        days: Int = 84,
        endingAt endDate: Date = .now,
        calendar: Calendar = .current
    ) -> [ActivityHeatmapCell] {
        let countByDay = Dictionary(uniqueKeysWithValues: activity.map { (calendar.startOfDay(for: $0.day), $0.completedTests) })
        let end = calendar.startOfDay(for: endDate)
        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset - days + 1, to: end) else { return nil }
            return ActivityHeatmapCell(day: day, completedTests: countByDay[day] ?? 0)
        }
    }
}
