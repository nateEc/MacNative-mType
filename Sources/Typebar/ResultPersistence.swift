import Foundation
import SwiftData

enum ResultSavingPolicy {
  static func shouldPersist(outcome: TestOutcome, enabled: Bool) -> Bool {
    enabled && outcome == .completed
  }
}

enum ResultPublicationRetryPolicy {
  static func shouldQueue(_ error: Error) -> Bool {
    if error is URLError { return true }
    guard let accountError = error as? RemoteAccountError else { return false }
    if case .accountScopeChanged = accountError { return true }
    guard case .serverResponse(let statusCode, _) = accountError else { return false }
    return statusCode == 401 || statusCode == 408 || statusCode == 425 || statusCode == 429
      || (500...599).contains(statusCode)
  }
}

struct ResultPublicationScope: Codable, Equatable, Hashable, Sendable {
  let serverID: String
  let userID: UUID

  init(endpoint: String, userID: UUID) {
    serverID = RemoteServerScope(endpoint: endpoint).storageSuffix
    self.userID = userID
  }
}

private struct PendingResultPublication: Codable, Equatable, Hashable {
  let resultID: UUID
  let scope: ResultPublicationScope
}

/// Persists only result identifiers and their account/server ownership. The
/// result payload remains in SwiftData and credentials remain in Keychain.
final class PendingResultPublicationStore {
  static let storageKey = "resultPublication.pending.v1"

  private let defaults: UserDefaults
  private var entries: [PendingResultPublication]

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    entries = []
    reload()
  }

  private func reload() {
    if let data = defaults.data(forKey: Self.storageKey),
      let decoded = try? JSONDecoder().decode([PendingResultPublication].self, from: data)
    {
      var seen = Set<PendingResultPublication>()
      entries = decoded.filter { seen.insert($0).inserted }
    } else {
      entries = []
    }
  }

  func resultIDs(for scope: ResultPublicationScope) -> [UUID] {
    reload()
    return entries.lazy.filter { $0.scope == scope }.map(\.resultID)
  }

  func enqueue(_ resultID: UUID, for scope: ResultPublicationScope) {
    reload()
    let entry = PendingResultPublication(resultID: resultID, scope: scope)
    guard !entries.contains(entry) else { return }
    entries.append(entry)
    persist()
  }

  func remove(_ resultID: UUID, for scope: ResultPublicationScope) {
    reload()
    let oldCount = entries.count
    entries.removeAll { $0.resultID == resultID && $0.scope == scope }
    if entries.count != oldCount { persist() }
  }

  func removeAll() {
    entries.removeAll()
    defaults.removeObject(forKey: Self.storageKey)
  }

  private func persist() {
    guard !entries.isEmpty else {
      defaults.removeObject(forKey: Self.storageKey)
      return
    }
    guard let data = try? JSONEncoder().encode(entries) else { return }
    defaults.set(data, forKey: Self.storageKey)
  }
}

struct ResultPublicationReceipt: Equatable {
  let message: String
  let dailyLeaderboardRank: Int?
}

enum ResultPublicationState: Equatable {
  case idle
  case sending
  case sent(ResultPublicationReceipt)
  case failed(String)
  case notice(String)

  var message: String? {
    switch self {
    case .idle: nil
    case .sending: "正在发送至自建服务…"
    case .sent(let receipt): receipt.message
    case .failed(let message), .notice(let message): message
    }
  }

  var canRetry: Bool {
    if case .failed = self { return true }
    return false
  }

  var isSending: Bool {
    if case .sending = self { return true }
    return false
  }

  var dailyLeaderboardRank: Int? {
    guard case .sent(let receipt) = self else { return nil }
    return receipt.dailyLeaderboardRank
  }
}

@Model
final class TestResultRecord {
  @Attribute(.unique) var id: UUID
  var configurationData: Data
  var outcome: String
  var startedAt: Date
  var finishedAt: Date
  var afkDuration: TimeInterval = 0
  var typedCharacterCount: Int
  var correctCharacterCount: Int
  var errorCount: Int
  var wpm: Int
  var rawWpm: Int
  var accuracy: Int
  var storedRestartCount: Int?
  var characterStatsData: Data?
  var keyDurationSamplesData: Data?
  var keySpacingSamplesData: Data?
  var keyOverlapDuration: TimeInterval?
  var tagsData: Data
  var quoteSourceData: Data?
  var prompt: String
  var replayEventsData: Data?

  init(result: CompletedTestResult) {
    id = result.id
    configurationData = (try? JSONEncoder().encode(result.configuration)) ?? Data()
    outcome = result.outcome.rawValue
    startedAt = result.startedAt
    finishedAt = result.finishedAt
    afkDuration = result.afkDuration
    typedCharacterCount = result.typedCharacterCount
    correctCharacterCount = result.correctCharacterCount
    errorCount = result.errorCount
    wpm = result.wpm
    rawWpm = result.rawWpm
    accuracy = result.accuracy
    storedRestartCount = result.restartCount
    characterStatsData = try? JSONEncoder().encode(result.characterStats)
    keyDurationSamplesData = try? JSONEncoder().encode(result.keyDurationSamples)
    keySpacingSamplesData = try? JSONEncoder().encode(result.keySpacingSamples)
    keyOverlapDuration = result.keyOverlapDuration
    tagsData = (try? JSONEncoder().encode(ResultTagPolicy.normalized(result.tags))) ?? Data()
    quoteSourceData = result.quoteSource.flatMap { try? JSONEncoder().encode($0) }
    prompt = result.prompt
    replayEventsData = try? JSONEncoder().encode(result.replayEvents)
  }

  var configuration: TestConfiguration? {
    try? JSONDecoder().decode(TestConfiguration.self, from: configurationData)
  }

  var tags: [String] {
    get { (try? JSONDecoder().decode([String].self, from: tagsData)) ?? [] }
    set { tagsData = (try? JSONEncoder().encode(ResultTagPolicy.normalized(newValue))) ?? Data() }
  }

  var replayEvents: [TypingReplayEvent] {
    (replayEventsData.flatMap { try? JSONDecoder().decode([TypingReplayEvent].self, from: $0) })
      ?? []
  }

  var quoteSource: ResultQuoteSource? {
    quoteSourceData.flatMap { try? JSONDecoder().decode(ResultQuoteSource.self, from: $0) }
  }

  var restartCount: Int {
    max(0, storedRestartCount ?? 0)
  }

  var characterStats: ResultCharacterStats {
    characterStatsData.flatMap { try? JSONDecoder().decode(ResultCharacterStats.self, from: $0) }
      ?? .legacy(
        typedCharacterCount: typedCharacterCount,
        correctCharacterCount: correctCharacterCount)
  }

  var keyDurationSamples: [TimeInterval] {
    keyDurationSamplesData.flatMap { try? JSONDecoder().decode([TimeInterval].self, from: $0) }
      ?? []
  }

  var keySpacingSamples: [TimeInterval] {
    keySpacingSamplesData.flatMap { try? JSONDecoder().decode([TimeInterval].self, from: $0) }
      ?? []
  }

  var engagedDuration: TimeInterval {
    max(0, finishedAt.timeIntervalSince(startedAt) - afkDuration)
  }

  var afkPercentage: Double {
    let elapsedDuration = max(0, finishedAt.timeIntervalSince(startedAt))
    guard elapsedDuration > 0 else { return 0 }
    return afkDuration / elapsedDuration * 100
  }

  func addTag(_ rawTag: String) {
    tags = ResultTagPolicy.appending(rawTag, to: tags)
  }

  func removeTag(_ tag: String) {
    tags = tags.filter { $0 != tag }
  }

  var portableResult: CompletedTestResult? {
    guard let configuration, let parsedOutcome = TestOutcome(rawValue: outcome) else { return nil }
    return CompletedTestResult(
      id: id,
      configuration: configuration,
      outcome: parsedOutcome,
      startedAt: startedAt,
      finishedAt: finishedAt,
      afkDuration: afkDuration,
      typedCharacterCount: typedCharacterCount,
      correctCharacterCount: correctCharacterCount,
      errorCount: errorCount,
      wpm: wpm,
      rawWpm: rawWpm,
      accuracy: accuracy,
      restartCount: restartCount,
      characterStats: characterStats,
      keyDurationSamples: keyDurationSamples,
      keySpacingSamples: keySpacingSamples,
      keyOverlapDuration: keyOverlapDuration ?? 0,
      tags: tags,
      quoteSource: quoteSource,
      prompt: prompt,
      replayEvents: replayEvents
    )
  }
}

enum ResultTagPolicy {
  static let maximumCount = 5
  static let maximumLength = 24

  static func normalized(_ tags: [String]) -> [String] {
    var seen = Set<String>()
    return tags.compactMap(normalize).filter { tag in
      let key = tag.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      return seen.insert(key).inserted
    }.prefix(maximumCount).map { $0 }
  }

  static func appending(_ rawTag: String, to tags: [String]) -> [String] {
    normalized(tags + [rawTag])
  }

  private static func normalize(_ rawTag: String) -> String? {
    let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !tag.isEmpty, tag.count <= maximumLength else { return nil }
    return tag
  }
}

enum ResultFilterPresetPolicy {
  static let maximumNameLength = 40

  static func normalizedName(_ rawName: String) -> String? {
    let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, name.count <= maximumNameLength else { return nil }
    return name
  }
}

@Model
final class ResultFilterPresetRecord {
  @Attribute(.unique) var id: UUID
  var name: String
  var filterData: Data
  var createdAt: Date

  init?(name: String, filter: ResultHistoryFilter) {
    guard let name = ResultFilterPresetPolicy.normalizedName(name),
      let filterData = try? JSONEncoder().encode(filter)
    else { return nil }
    id = UUID()
    self.name = name
    self.filterData = filterData
    createdAt = .now
  }

  var filter: ResultHistoryFilter? {
    try? JSONDecoder().decode(ResultHistoryFilter.self, from: filterData)
  }
}
