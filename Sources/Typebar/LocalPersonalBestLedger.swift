import Foundation
import SwiftData

/// Numeric PB snapshots intentionally do not retain prompts, input or replays.
struct LocalPersonalBestSnapshot: Codable, Equatable {
  enum Origin: String, Codable { case accepted, legacyHistory, importedHistory }
  let row: LocalPersonalBestRow
  let recordedAt: Date?
  let origin: Origin
}

struct LocalTagPersonalBestSnapshot: Codable, Equatable {
  let tag: String
  let snapshot: LocalPersonalBestSnapshot
}

struct LocalPersonalBestGroup: Hashable {
  let mode: TestMode
  let parameter: Int
  let language: TypingLanguage
  let difficulty: Difficulty
  let punctuation: Bool
  let numbers: Bool
  let lazy: Bool

  init?(_ configuration: TestConfiguration) {
    mode = configuration.mode
    switch mode {
    case .time:
      guard let seconds = configuration.duration, seconds.isFinite, seconds >= 0,
        seconds < Double(Int.max), seconds.rounded(.towardZero) == seconds else { return nil }
      parameter = Int(seconds)
    case .words:
      guard let count = configuration.wordLimit, count >= 0 else { return nil }
      parameter = count
    case .custom, .zen: parameter = 0
    case .quote: return nil
    }
    language = configuration.language; difficulty = configuration.difficulty
    punctuation = configuration.contentOptions.includePunctuation
    numbers = configuration.contentOptions.includeNumbers
    lazy = configuration.modifiers.contains(.lazyLatin)
  }

  init(_ row: LocalPersonalBestRow) {
    mode = row.mode; parameter = row.parameter; language = row.language; difficulty = row.difficulty
    punctuation = row.includesPunctuation; numbers = row.includesNumbers; lazy = row.usesLazyLatin
  }
}

struct LocalPersonalBestLedger: Codable, Equatable {
  var version = 1
  var historyComplete = true
  var entries: [LocalPersonalBestSnapshot] = []
  var tagEntries: [LocalTagPersonalBestSnapshot] = []

  static func tagKey(_ tag: String) -> String {
    tag.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
  }

  func best(configuration: TestConfiguration, activeTags: [String] = [],
    requiresCurrentEligibility: Bool = true) -> LocalPersonalBestSnapshot? {
    guard (!requiresCurrentEligibility || CurrentPersonalBestPolicy.isConfigurationEligible(configuration)),
      let group = LocalPersonalBestGroup(configuration) else { return nil }
    if activeTags.isEmpty { return entries.first { LocalPersonalBestGroup($0.row) == group } }
    let keys = Set(activeTags.map(Self.tagKey))
    return tagEntries.filter { keys.contains(Self.tagKey($0.tag))
      && LocalPersonalBestGroup($0.snapshot.row) == group }
      .map(\.snapshot).reduce(nil) { current, next in
        guard let current else { return next }
        return next.row.wpm > current.row.wpm ? next : current
      }
  }

  func feedback(for result: CompletedTestResult) -> ResultPersonalBestFeedback? {
    guard Self.qualifies(result) else { return nil }
    return .init(previousBestWpm: best(configuration: result.configuration)?.row.wpm,
      currentWpm: result.preciseWpm)
  }

  func tagFeedback(for result: CompletedTestResult) -> [TagPersonalBestFeedback] {
    guard Self.qualifies(result) else { return [] }
    return ResultTagPolicy.normalized(result.tags).map { tag in
      .init(tag: tag, previousBestWpm: best(configuration: result.configuration, activeTags: [tag])?.row.wpm,
        currentWpm: result.preciseWpm)
    }
  }

  mutating func accept(_ result: CompletedTestResult, at date: Date?,
    origin: LocalPersonalBestSnapshot.Origin = .accepted) throws {
    guard Self.qualifies(result), let group = LocalPersonalBestGroup(result.configuration) else { return }
    let configuration = result.configuration
    let row = LocalPersonalBestRow(id: result.id, mode: group.mode, parameter: group.parameter,
      wpm: result.preciseWpm, rawWpm: result.preciseRawWpm, accuracy: result.preciseAccuracy,
      consistency: ResultConsistencyPolicy.metrics(events: result.replayEvents, duration: result.chartDuration,
        configuration: configuration, keySpacingSamples: result.keySpacingSamples).typing,
      difficulty: group.difficulty, language: group.language, includesPunctuation: group.punctuation,
      includesNumbers: group.numbers, usesLazyLatin: group.lazy, finishedAt: result.finishedAt)
    let recordedAt = date.map { Date(timeIntervalSince1970: floor($0.timeIntervalSince1970 * 1000) / 1000) }
    let candidate = LocalPersonalBestSnapshot(row: row, recordedAt: recordedAt, origin: origin)
    try Self.validate(candidate)
    if let index = entries.firstIndex(where: { LocalPersonalBestGroup($0.row) == group }) {
      if row.wpm > entries[index].row.wpm { entries[index] = candidate }
    } else { entries.append(candidate) }
    for tag in ResultTagPolicy.normalized(result.tags) {
      if let index = tagEntries.firstIndex(where: { Self.tagKey($0.tag) == Self.tagKey(tag)
        && LocalPersonalBestGroup($0.snapshot.row) == group }) {
        if row.wpm > tagEntries[index].snapshot.row.wpm {
          tagEntries[index] = .init(tag: tag, snapshot: candidate)
        }
      } else { tagEntries.append(.init(tag: tag, snapshot: candidate)) }
    }
    if origin != .accepted { historyComplete = false }
  }

  private static func qualifies(_ result: CompletedTestResult) -> Bool {
    result.outcome == .completed && CurrentPersonalBestPolicy.isResultEligible(
      configuration: result.configuration, accuracy: result.preciseAccuracy)
  }

  func validate() throws {
    guard version == 1 else { throw LocalPersonalBestStoreError.invalidLedger }
    var identities: [UUID: LocalPersonalBestRow] = [:]
    for snapshot in entries + tagEntries.map(\.snapshot) {
      if let old = identities[snapshot.row.id], old != snapshot.row {
        throw LocalPersonalBestStoreError.conflictingResult
      }
      identities[snapshot.row.id] = snapshot.row
    }
    var groups = Set<LocalPersonalBestGroup>()
    for entry in entries {
      try Self.validate(entry)
      guard groups.insert(LocalPersonalBestGroup(entry.row)).inserted else {
        throw LocalPersonalBestStoreError.invalidLedger
      }
    }
    var tagGroups = Set<String>()
    for entry in tagEntries {
      try Self.validate(entry.snapshot)
      guard ResultTagPolicy.normalized([entry.tag]) == [entry.tag] else {
        throw LocalPersonalBestStoreError.invalidLedger
      }
      // Encode the group to avoid locale-dependent descriptions and delimiter collisions.
      let row = entry.snapshot.row
      let key = try JSONEncoder().encode([Self.tagKey(entry.tag), row.mode.rawValue,
        String(row.parameter), row.language.rawValue, row.difficulty.rawValue,
        String(row.includesPunctuation), String(row.includesNumbers), String(row.usesLazyLatin)])
      guard tagGroups.insert(key.base64EncodedString()).inserted else {
        throw LocalPersonalBestStoreError.invalidLedger
      }
    }
  }

  private static func validate(_ snapshot: LocalPersonalBestSnapshot) throws {
    let row = snapshot.row
    guard row.mode != .quote, row.parameter >= 0,
      (row.mode == .time || row.mode == .words || row.parameter == 0),
      row.finishedAt.timeIntervalSinceReferenceDate.isFinite,
      [row.wpm, row.rawWpm, row.accuracy, row.consistency].allSatisfy({ $0.isFinite && $0 >= 0 }),
      row.accuracy <= 100, row.consistency <= 100,
      (snapshot.origin == .accepted
        ? snapshot.recordedAt?.timeIntervalSinceReferenceDate.isFinite == true : snapshot.recordedAt == nil)
    else { throw LocalPersonalBestStoreError.invalidLedger }
  }

  /// Offline union has no global acceptance order. Prefer faster whole snapshots,
  /// then the earlier known acceptance clock, then UUID; never combine metrics.
  func merged(with other: Self) throws -> Self {
    try validate(); try other.validate()
    var identities: [UUID: LocalPersonalBestRow] = [:]
    for snapshot in entries + other.entries + (tagEntries + other.tagEntries).map(\.snapshot) {
      if let old = identities[snapshot.row.id], old != snapshot.row {
        throw LocalPersonalBestStoreError.conflictingResult
      }
      identities[snapshot.row.id] = snapshot.row
    }
    func winner(_ left: LocalPersonalBestSnapshot, _ right: LocalPersonalBestSnapshot) -> LocalPersonalBestSnapshot {
      if left.row.wpm != right.row.wpm { return left.row.wpm > right.row.wpm ? left : right }
      if left.recordedAt != right.recordedAt {
        guard let l = left.recordedAt else { return right }
        guard let r = right.recordedAt else { return left }
        return l < r ? left : right
      }
      if left.row.id != right.row.id {
        return left.row.id.uuidString < right.row.id.uuidString ? left : right
      }
      return left.origin.rawValue <= right.origin.rawValue ? left : right
    }
    var groups: [LocalPersonalBestGroup: LocalPersonalBestSnapshot] = [:]
    for candidate in entries + other.entries {
      let group = LocalPersonalBestGroup(candidate.row)
      groups[group] = groups[group].map { winner($0, candidate) } ?? candidate
    }
    struct TagGroup: Hashable { let tag: String; let group: LocalPersonalBestGroup }
    var tags: [TagGroup: LocalTagPersonalBestSnapshot] = [:]
    for candidate in tagEntries + other.tagEntries {
      let key = TagGroup(tag: Self.tagKey(candidate.tag), group: .init(candidate.snapshot.row))
      if let old = tags[key] {
        let selected = winner(old.snapshot, candidate.snapshot)
        if old.snapshot == candidate.snapshot {
          tags[key] = old.tag <= candidate.tag ? old : candidate
        } else { tags[key] = selected == old.snapshot ? old : candidate }
      } else { tags[key] = candidate }
    }
    var result = Self()
    result.historyComplete = historyComplete && other.historyComplete
    result.entries = groups.values.sorted { $0.row.id.uuidString < $1.row.id.uuidString }
    result.tagEntries = tags.values.sorted {
      let l = Self.tagKey($0.tag), r = Self.tagKey($1.tag)
      return l == r ? $0.snapshot.row.id.uuidString < $1.snapshot.row.id.uuidString : l < r
    }
    try result.validate()
    return result
  }
}

enum LocalPersonalBestStoreError: LocalizedError {
  case invalidLedger, conflictingResult
  var errorDescription: String? {
    switch self {
    case .invalidLedger: "本机个人最佳账本损坏或版本不受支持；数据未清空，请备份数据库后修复。"
    case .conflictingResult: "同一成绩 ID 的内容不一致，未替换已有成绩。"
    }
  }
}

@Model
final class LocalPersonalBestLedgerRecord {
  @Attribute(.unique) var id: UUID
  var ledgerData: Data

  init(ledger: LocalPersonalBestLedger) throws {
    id = UUID(uuidString: "A6E40891-BCF0-4C7A-A218-29135E040101")!
    try ledger.validate()
    ledgerData = try JSONEncoder().encode(ledger)
  }

  var ledger: LocalPersonalBestLedger? { try? decodedLedger() }

  func decodedLedger() throws -> LocalPersonalBestLedger {
    do {
      let value = try JSONDecoder().decode(LocalPersonalBestLedger.self, from: ledgerData)
      try value.validate(); return value
    } catch { throw LocalPersonalBestStoreError.invalidLedger }
  }
}

@MainActor
enum LocalPersonalBestStore {
  struct Checkpoint {
    let record: LocalPersonalBestLedgerRecord?
    let bytes: Data?
  }

  static func checkpoint(in context: ModelContext) throws -> Checkpoint {
    let record = try existing(in: context)
    return .init(record: record, bytes: record?.ledgerData)
  }

  static func restore(_ checkpoint: Checkpoint, in context: ModelContext) {
    context.rollback()
    // A failed real save may advance the registered blob's in-memory baseline
    // even though SQLite did not commit it. Do not display an uncommitted PB.
    if let record = checkpoint.record, let bytes = checkpoint.bytes, record.ledgerData != bytes {
      record.ledgerData = bytes
    }
  }

  /// Startup freezes recoverable history once, before any history deletion.
  /// The same database save is the cutover boundary; no sidecar or defaults write.
  static func initialize(in context: ModelContext, legacyStorePresent: Bool = false) throws {
    if let record = try existing(in: context) { _ = try record.decodedLedger(); return }
    let record = try baseline(in: context, legacyStorePresent: legacyStorePresent)
    context.insert(record)
    do { try context.save() } catch { context.rollback(); throw error }
  }

  @discardableResult
  static func save(_ result: CompletedTestResult, in context: ModelContext,
    acceptedAt: Date = .now, save: (() throws -> Void)? = nil) throws -> TestResultRecord {
    try result.accountTagSnapshot?.validate()
    let checkpoint = try checkpoint(in: context)
    let id = result.id
    if let old = try context.fetch(FetchDescriptor<TestResultRecord>(predicate: #Predicate { $0.id == id })).first {
      guard old.portableResult == result else { throw LocalPersonalBestStoreError.conflictingResult }
      return old
    }
    do {
      try stage([result], in: context, at: acceptedAt, origin: .accepted)
      let record = TestResultRecord(result: result)
      context.insert(record)
      try (save ?? { try context.save() })()
      return record
    } catch { restore(checkpoint, in: context); throw error }
  }

  /// Imports may extend a local baseline, but cannot invent an acceptance clock.
  /// The caller commits this staged update together with its history merge.
  @discardableResult
  static func stage(_ results: [CompletedTestResult], in context: ModelContext,
    at date: Date? = nil, origin: LocalPersonalBestSnapshot.Origin = .importedHistory
  ) throws -> LocalPersonalBestLedgerRecord {
    for result in results { try result.accountTagSnapshot?.validate() }
    let record: LocalPersonalBestLedgerRecord
    if let old = try existing(in: context) { record = old }
    else { record = try baseline(in: context); context.insert(record) }
    var ledger = try record.decodedLedger()
    for result in results { try ledger.accept(result, at: date, origin: origin) }
    try ledger.validate()
    record.ledgerData = try JSONEncoder().encode(ledger)
    return record
  }

  private static func existing(in context: ModelContext) throws -> LocalPersonalBestLedgerRecord? {
    let records = try context.fetch(FetchDescriptor<LocalPersonalBestLedgerRecord>())
    guard records.count <= 1,
      records.first.map({ $0.id == UUID(uuidString: "A6E40891-BCF0-4C7A-A218-29135E040101")! }) ?? true
    else { throw LocalPersonalBestStoreError.invalidLedger }
    return records.first
  }

  static func exportLedger(in context: ModelContext) throws -> LocalPersonalBestLedger {
    guard let record = try existing(in: context) else { throw LocalPersonalBestStoreError.invalidLedger }
    return try record.decodedLedger()
  }

  /// A captured empty book is authoritative: history must not rebuild it.
  static func stageImportedLedger(_ incoming: LocalPersonalBestLedger, in context: ModelContext) throws {
    try incoming.validate()
    let record: LocalPersonalBestLedgerRecord
    if let old = try existing(in: context) { record = old }
    else { record = try baseline(in: context); context.insert(record) }
    let merged = try record.decodedLedger().merged(with: incoming)
    record.ledgerData = try JSONEncoder().encode(merged)
  }

  private static func baseline(in context: ModelContext, legacyStorePresent: Bool = false) throws -> LocalPersonalBestLedgerRecord {
    var ledger = LocalPersonalBestLedger()
    let records = try context.fetch(FetchDescriptor<TestResultRecord>(sortBy: [SortDescriptor(\.finishedAt)]))
    ledger.historyComplete = records.isEmpty && !legacyStorePresent
    for record in records {
      // TestConfiguration has legacy defaults. Do not infer an absent PB group.
      guard let object = try? JSONSerialization.jsonObject(with: record.configurationData) as? [String: Any],
        ["mode", "difficulty", "language", "modifiers", "contentOptions"].allSatisfy({ object[$0] != nil }),
        let options = object["contentOptions"] as? [String: Any],
        options["includePunctuation"] is Bool, options["includeNumbers"] is Bool,
        let result = record.portableResult else { continue }
      try ledger.accept(result, at: nil, origin: .legacyHistory)
    }
    return try .init(ledger: ledger)
  }
}
