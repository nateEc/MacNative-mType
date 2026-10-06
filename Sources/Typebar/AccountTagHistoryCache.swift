import Foundation

/// A client cache is not an accepted service ledger or a completion snapshot.
struct AccountTagHistoryGroup: Hashable {
  let mode: String
  let mode2: String
  let language: String
  let difficulty: String
  let punctuation: Bool
  let numbers: Bool
  let lazy: Bool

  init?(_ result: RemoteAccountResult) {
    guard let options = result.personalBestConfiguration, let mode2 = result.mode2,
      ["time", "words", "custom", "zen"].contains(result.mode) else { return nil }
    mode = result.mode; self.mode2 = mode2; language = result.language
    difficulty = options.difficulty; punctuation = options.punctuation
    numbers = options.numbers; lazy = options.lazyMode
  }
  init?(_ configuration: TestConfiguration) {
    guard let group = LocalPersonalBestGroup(configuration) else { return nil }
    mode = group.mode.rawValue
    mode2 = [.time, .words].contains(group.mode) ? String(group.parameter) : mode
    language = group.language.rawValue; difficulty = group.difficulty.rawValue
    punctuation = group.punctuation; numbers = group.numbers; lazy = group.lazy
  }
  init?(_ best: RemotePublicProfileBest) {
    guard let options = best.personalBestConfiguration, let parameter = best.mode2 else { return nil }
    mode = best.mode; mode2 = parameter; language = best.language; difficulty = options.difficulty
    punctuation = options.punctuation; numbers = options.numbers; lazy = options.lazyMode
  }
}

struct AccountTagHistoryPersonalBest: Equatable {
  let tagID: UUID
  let group: AccountTagHistoryGroup
  let wpm: Double
  let rawWpm: Double
  let accuracy: Double
  let consistency: Double
  let rebuiltAtMilliseconds: Int64

  static func retained(_ snapshots: [Self], before: [RemoteAccountTag], after: [RemoteAccountTag]) -> [Self] {
    snapshots.filter { snapshot in
      guard let tag = after.first(where: { $0.id == snapshot.tagID }) else { return false }
      let old = before.first { $0.id == snapshot.tagID }?.personalBests.first { AccountTagHistoryGroup($0) == snapshot.group }
      let new = tag.personalBests.first { AccountTagHistoryGroup($0) == snapshot.group }
      switch (old, new) {
      case (nil, nil): return true
      case let (old?, new?):
        return old.id == new.id && old.acceptedAtMilliseconds == new.acceptedAtMilliseconds
          && old.effectiveWpm == new.effectiveWpm && old.preciseRawWpm == new.preciseRawWpm
          && old.rawWpm == new.rawWpm && old.accuracy == new.accuracy
          && old.preciseAccuracy == new.preciseAccuracy && old.consistency == new.consistency
          && old.finishedAt == new.finishedAt
      default: return false
      }
    }
  }
}

struct AccountTagHistoryCache {
  let scope: ResultPublicationScope
  private(set) var results: [RemoteAccountResult]
  private(set) var personalBests: [AccountTagHistoryPersonalBest] = []
  private(set) var isComplete = true
  private var pendingAcceptedIDs: Set<UUID> = []
  private var acceptedDirectory: [RemoteAccountTag]

  init(scope: ResultPublicationScope, results: [RemoteAccountResult], knownIDs: Set<UUID>,
    directory: [RemoteAccountTag] = []) throws {
    guard Set(results.map(\.id)).count == results.count else { throw RemoteAccountError.unexpectedResponse }
    self.scope = scope
    acceptedDirectory = directory
    self.results = results.map { result in
      var normalized = result
      if let ids = result.accountTagIDs { normalized.accountTagIDs = ids.filter { knownIDs.contains($0) } }
      return normalized
    }
    for result in results {
      guard result.effectiveWpm.isFinite, (0...420).contains(result.effectiveWpm),
        result.effectiveRawWpm.isFinite, (result.effectiveWpm...500).contains(result.effectiveRawWpm),
        (result.preciseAccuracy ?? Double(result.accuracy)).isFinite,
        (0...100).contains(result.preciseAccuracy ?? Double(result.accuracy)),
        result.consistency.isFinite, (0...100).contains(result.consistency)
      else { throw RemoteAccountError.unexpectedResponse }
    }
  }

  mutating func edit(id: UUID, tagIDs: [UUID], knownIDs: Set<UUID>, at milliseconds: Int64) throws {
    try RemoteAccountTagPolicy.validateIDs(tagIDs)
    guard isComplete, Set(tagIDs).isSubset(of: knownIDs), let index = results.firstIndex(where: { $0.id == id }),
      (0...8_640_000_000_000_000).contains(milliseconds) else { throw RemoteAccountError.unexpectedResponse }
    let old = Set(results[index].accountTagIDs ?? [])
    results[index].accountTagIDs = tagIDs
    guard let group = AccountTagHistoryGroup(results[index]) else { return }
    for tagID in old.symmetricDifference(Set(tagIDs)).intersection(knownIDs) {
      // Strictly greater preserves the first complete snapshot at equal speed.
      let winner = results.reduce(nil as RemoteAccountResult?) { best, result in
        guard result.accountTagIDs?.contains(tagID) == true,
          AccountTagHistoryGroup(result) == group, result.effectiveWpm > (best?.effectiveWpm ?? 0)
        else { return best }
        return result
      }
      let snapshot = AccountTagHistoryPersonalBest(tagID: tagID, group: group,
        wpm: winner?.effectiveWpm ?? 0, rawWpm: winner?.effectiveRawWpm ?? 0,
        accuracy: winner.map { $0.preciseAccuracy ?? Double($0.accuracy) } ?? 0,
        consistency: winner?.consistency ?? 0, rebuiltAtMilliseconds: milliseconds)
      personalBests.removeAll { $0.tagID == tagID && $0.group == group }
      personalBests.append(snapshot)
    }
  }

  mutating func removeTag(_ id: UUID, clearOnly: Bool) {
    personalBests.removeAll { $0.tagID == id }
    if !clearOnly {
      for index in results.indices { results[index].accountTagIDs?.removeAll { $0 == id } }
    }
  }

  mutating func replaceResults(_ rows: [RemoteAccountResult], knownIDs: Set<UUID>) throws {
    results = try Self(scope: scope, results: rows, knownIDs: knownIDs, directory: acceptedDirectory).results
    isComplete = true
    pendingAcceptedIDs = []
  }

  mutating func clearResults() { results = []; pendingAcceptedIDs = []; isComplete = true }

  mutating func noteAccepted(_ id: UUID) {
    guard !results.contains(where: { $0.id == id }) else { return }
    pendingAcceptedIDs.insert(id)
    isComplete = false
  }

  mutating func insertAcceptedResult(_ result: RemoteAccountResult, knownIDs: Set<UUID>) throws {
    let normalized = try Self(scope: scope, results: [result], knownIDs: knownIDs).results[0]
    pendingAcceptedIDs.remove(result.id)
    isComplete = pendingAcceptedIDs.isEmpty
    guard !results.contains(where: { $0.id == result.id }) else { return }
    // Collection insertion order is distinct from the recent-history display.
    results.append(normalized)
  }

  mutating func markIncomplete() { isComplete = false }

  mutating func discardPersonalBestOverrides(tagIDs: [UUID], group: AccountTagHistoryGroup) {
    personalBests.removeAll { tagIDs.contains($0.tagID) && $0.group == group }
  }

  func recentResults(limit: Int) -> [RemoteAccountResult] {
    Array(results.enumerated().sorted {
      $0.element.finishedAt == $1.element.finishedAt ? $0.offset < $1.offset
        : $0.element.finishedAt > $1.element.finishedAt
    }.prefix(limit).map(\.element))
  }

  mutating func adoptDirectory(_ tags: [RemoteAccountTag]) {
    let owned = Set(tags.map(\.id))
    personalBests = AccountTagHistoryPersonalBest.retained(personalBests, before: acceptedDirectory, after: tags)
    for index in results.indices {
      results[index].accountTagIDs = results[index].accountTagIDs?.filter { owned.contains($0) }
    }
    acceptedDirectory = tags
  }
}

struct AccountTagHistoryRead: Equatable {
  let scope: ResultPublicationScope
  let generation: UInt64
}

enum AccountTagHistoryLoadingPolicy {
  static let initialResultLimit = 1_000
  static func initialResults(_ page: RemoteAccountResultPage) throws -> [RemoteAccountResult] {
    guard page.total >= 0, page.results.count == min(page.total, initialResultLimit),
      Set(page.results.map(\.id)).count == page.results.count else { throw RemoteAccountError.unexpectedResponse }
    return page.results
  }
}
