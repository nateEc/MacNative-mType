import Foundation

enum AccountHistoryQuery {
  static func matching(_ rows: [RemoteAccountResult], scope: ResultPublicationScope,
    filter: ResultHistoryFilter, now: Date = .now) -> [RemoteAccountResult] {
    // Only the admission receipt knows historical PB; a current crown does not.
    let personalBestIDs = Set(rows.filter { $0.historicalPersonalBest == true }.map(\.id))
    let entries = rows.compactMap { row -> ResultHistoryEntry? in
      if filter.effectivePersonalBestFilter != .all, row.historicalPersonalBest == nil { return nil }
      let mode = TestMode(rawValue: row.mode)
      if mode == .quote, row.quoteLength == nil,
        filter.quoteLength != nil || (filter.quoteLengths != nil
          && filter.quoteLengthSelections != ResultHistoryFilter.filterableQuoteLengths) {
        return nil
      }
      let duration = row.durationSeconds.flatMap { (1...3_600).contains($0) ? Double($0) : nil }
      let words = row.wordLimit.flatMap { (1...1_000_000).contains($0) ? $0 : nil }
      if mode == .time, duration == nil, filter.timeLimits != Set(ResultHistoryTimeLimit.allCases) { return nil }
      if mode == .words, words == nil, filter.wordLimits != Set(ResultHistoryWordLimit.allCases) { return nil }
      let options = row.personalBestConfiguration
      let controls = row.rankingEvidence?.modifiers ?? row.experienceEvidence?.modifiers
      // Lazy is a native filter choice but not part of the service Funbox array.
      let modifiers: [TestModifier]? = controls.flatMap { controls in
        guard let options else { return nil }
        let represented = controls.compactMap(TestModifier.init(rawValue:))
          + (options.lazyMode ? [.lazyLatin] : [])
        // Polyglot is a separate filter identity, never a typing modifier.
        if represented.isEmpty, controls.contains(where: { $0 != "polyglot" }) { return nil }
        return represented
      }
      return .init(id: row.id, mode: mode, language: TypingLanguage(rawValue: row.language), tags: row.tags,
        finishedAt: row.finishedAt, difficulty: options.flatMap { Difficulty(rawValue: $0.difficulty) },
        includesPunctuation: options?.punctuation ?? row.experienceEvidence?.punctuation,
        includesNumbers: options?.numbers ?? row.experienceEvidence?.numbers,
        quoteLength: row.quoteLength, duration: duration, wordLimit: words, modifiers: modifiers,
        isPolyglot: controls.map { $0.contains("polyglot") },
        accountTags: .init(scope: scope, tagIDs: row.accountTagIDs))
    }
    let ids = filter.matchingIDs(entries: entries, personalBestIDs: personalBestIDs, now: now)
    return rows.filter { ids.contains($0.id) }
  }

  static func sorted(_ rows: [RemoteAccountResult], by field: ResultHistorySortField = .finishedAt,
    direction: ResultHistorySortDirection = .descending) -> [RemoteAccountResult] {
    func value(_ row: RemoteAccountResult) -> Double {
      switch field {
      case .finishedAt: row.finishedAt.timeIntervalSinceReferenceDate
      case .wpm: row.effectiveWpm
      case .rawWpm: row.effectiveRawWpm
      case .accuracy: row.preciseAccuracy ?? Double(row.accuracy)
      case .consistency: row.consistency
      }
    }
    return rows.sorted {
      if value($0) != value($1) { return direction == .ascending ? value($0) < value($1) : value($0) > value($1) }
      if $0.finishedAt != $1.finishedAt { return $0.finishedAt > $1.finishedAt }
      return $0.id.uuidString < $1.id.uuidString
    }
  }

  static func latestTen(_ rows: [RemoteAccountResult]) -> [RemoteAccountResult] {
    Array(sorted(rows).prefix(10))
  }

  static func days(_ rows: [RemoteAccountResult], calendar: Calendar = .current) -> [AccountHistoryDay] {
    Dictionary(grouping: rows) { calendar.startOfDay(for: $0.finishedAt) }
      .map { AccountHistoryDay(day: $0.key, statistics: AccountHistoryStatistics($0.value)) }
      .sorted { $0.day < $1.day }
  }
}

struct AccountHistoryDay: Equatable, Identifiable {
  let day: Date
  let statistics: AccountHistoryStatistics
  var id: Date { day }
}

struct AccountHistoryExportSnapshot {
  let scope: ResultPublicationScope
  let rows: [RemoteAccountResult]
  func data(currentScope: ResultPublicationScope?) -> Data? {
    guard scope == currentScope else { return nil }
    return Data(RemoteResultCSVExport.csvString(for: rows).utf8)
  }
}

struct AccountHistoryStatistics: Equatable {
  let completed: Int
  let averageWpm: Double?
  let maximumWpm: Double?
  let averageRaw: Double?
  let maximumRaw: Double?
  let averageAccuracy: Double?
  let maximumAccuracy: Double?
  let averageConsistency: Double?
  let maximumConsistency: Double?
  let restarted: Int?
  let timeTyping: Double?
  let estimatedWords: Double?

  var started: Int? { restarted.map { completed + $0 } }
  var completionPercentage: Int? {
    started.map { $0 == 0 ? 0 : Int(floor(Double(completed) / Double($0) * 100)) }
  }
  var restartsPerCompleted: Double? {
    restarted.map { completed == 0 ? 0 : Double($0) / Double(completed) }
  }

  init(_ rows: [RemoteAccountResult]) {
    completed = rows.count
    func metrics(_ values: [Double], maximum: Double) -> (Double?, Double?) {
      guard !values.isEmpty, values.allSatisfy({ $0.isFinite && (0...maximum).contains($0) }) else { return (nil, nil) }
      return (values.reduce(0, +) / Double(values.count), values.max())
    }
    (averageWpm, maximumWpm) = metrics(rows.map(\.effectiveWpm), maximum: 420)
    // Legacy service results allow raw 500; precise speed remains decoder-bounded at 420.
    (averageRaw, maximumRaw) = metrics(rows.map(\.effectiveRawWpm), maximum: 500)
    (averageAccuracy, maximumAccuracy) = metrics(rows.map { $0.preciseAccuracy ?? Double($0.accuracy) }, maximum: 100)
    (averageConsistency, maximumConsistency) = metrics(rows.map(\.consistency), maximum: 100)
    let restarts = rows.compactMap(Self.knownRestartCount)
    restarted = restarts.count == rows.count ? restarts.reduce(0, +) : nil
    let times = rows.compactMap(Self.typingSeconds)
    timeTyping = times.count == rows.count ? times.reduce(0, +) : nil
    let words = rows.compactMap { row -> Double? in
      guard let duration = Self.duration(row), row.effectiveWpm.isFinite, (0...420).contains(row.effectiveWpm) else { return nil }
      // Round each result before summation, exactly as source normalizeResult.
      return (row.effectiveWpm / 60 * duration).rounded(.toNearestOrAwayFromZero)
    }
    estimatedWords = words.count == rows.count ? words.reduce(0, +) : nil
  }

  private static func knownRestartCount(_ row: RemoteAccountResult) -> Int? {
    row.restartCount.flatMap { (0...RemoteResultPracticeTiming.maximumRestartCount).contains($0) ? $0 : nil }
  }

  private static func duration(_ row: RemoteAccountResult) -> Double? {
    // Dates alone describe a wall-clock span, not a source testDuration.
    guard row.terminalTiming != nil || row.elapsedTime != nil else { return nil }
    let value = row.elapsedDuration
    return value.isFinite && (0...3_600).contains(value) ? value : nil
  }

  private static func typingSeconds(_ row: RemoteAccountResult) -> Double? {
    guard let duration = duration(row), let count = knownRestartCount(row), let timing = row.practiceTiming,
      timing.version == 1,
      (0...RemoteResultPracticeTiming.maximumTerminalEngagedMilliseconds).contains(timing.terminalEngagedMilliseconds),
      Double(timing.terminalEngagedMilliseconds) <= duration * 1_000 + 0.500001,
      (0...(count * RemoteResultPracticeTiming.maximumTerminalEngagedMilliseconds)).contains(timing.priorAttemptEngagedMilliseconds)
    else { return nil }
    // Source timeTyping is terminal testDuration + explicit incomplete seconds;
    // it does not subtract AFK here or estimate prior attempts when zero is known.
    return duration + Double(timing.priorAttemptEngagedMilliseconds) / 1_000
  }
}
