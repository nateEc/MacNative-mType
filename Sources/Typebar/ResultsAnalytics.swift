import Foundation

struct ResultMetric: Equatable, Identifiable {
    let id: UUID
    let finishedAt: Date
    let wpm: Int
    let accuracy: Int
    let typingSeconds: TimeInterval

    init(id: UUID = UUID(), finishedAt: Date, wpm: Int, accuracy: Int, typingSeconds: TimeInterval) {
        self.id = id
        self.finishedAt = finishedAt
        self.wpm = wpm
        self.accuracy = accuracy
        self.typingSeconds = typingSeconds
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
      typingSeconds: result.finishedAt.timeIntervalSince(result.startedAt))
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

struct ResultHistoryFilter: Codable, Equatable {
    var mode: TestMode?
    var language: TypingLanguage?
    var tag: String?
    var personalBestOnly: Bool

    init(mode: TestMode? = nil, language: TypingLanguage? = nil, tag: String? = nil, personalBestOnly: Bool = false) {
        self.mode = mode
        self.language = language
        self.tag = tag
        self.personalBestOnly = personalBestOnly
    }

    func matchingIDs(entries: [ResultHistoryEntry], personalBestIDs: Set<UUID>) -> Set<UUID> {
        Set(entries.filter { entry in
            (mode == nil || entry.mode == mode)
                && (language == nil || entry.language == language)
                && (tag == nil || entry.tags.contains(tag!))
                && (!personalBestOnly || personalBestIDs.contains(entry.id))
        }.map(\.id))
    }
}

struct ResultStatistics: Equatable {
    let completedTests: Int
    let averageWPM: Int
    let bestWPM: Int
    let averageAccuracy: Int
    let totalTypingSeconds: TimeInterval

    init(metrics: [ResultMetric]) {
        completedTests = metrics.count
        averageWPM = metrics.isEmpty ? 0 : Int((Double(metrics.map(\.wpm).reduce(0, +)) / Double(metrics.count)).rounded())
        bestWPM = metrics.map(\.wpm).max() ?? 0
        averageAccuracy = metrics.isEmpty ? 0 : Int((Double(metrics.map(\.accuracy).reduce(0, +)) / Double(metrics.count)).rounded())
        totalTypingSeconds = metrics.map(\.typingSeconds).reduce(0, +)
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
    var id: Date { day }
}

/// A fixed recent-day series is deliberately separate from `DailyActivity`: charts need
/// zero-value days too, otherwise time gaps visually collapse into adjacent bars.
struct ActivityBarPoint: Equatable, Identifiable {
    let day: Date
    let completedTests: Int
    let typingSeconds: TimeInterval
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
            DailyActivity(day: day, completedTests: values.count, typingSeconds: values.map(\.typingSeconds).reduce(0, +))
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
                typingSeconds: value?.typingSeconds ?? 0
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
