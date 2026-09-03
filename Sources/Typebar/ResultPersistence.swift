import Foundation
import SwiftData

enum ResultSavingPolicy {
  static func shouldPersist(outcome: TestOutcome, enabled: Bool) -> Bool {
    enabled && outcome == .completed
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
  var tagsData: Data
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
    tagsData = (try? JSONEncoder().encode(ResultTagPolicy.normalized(result.tags))) ?? Data()
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

  var engagedDuration: TimeInterval {
    max(0, finishedAt.timeIntervalSince(startedAt) - afkDuration)
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
      tags: tags,
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
