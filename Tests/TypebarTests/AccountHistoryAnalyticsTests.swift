import Foundation
import XCTest
@testable import Typebar

final class AccountHistoryAnalyticsTests: XCTestCase {
  private let scope = ResultPublicationScope(endpoint: "https://owned.invalid", userID: UUID())
  private func row(speed: Double = 80.49, raw: Double = 90.31, time: Double = 115,
    tags: [UUID]? = [], restartCount: Int? = 0, prior: Int? = 0,
    preciseDuration: Double? = 15, options: Bool = true, mode: String = "time") throws -> RemoteAccountResult {
    var object: [String: Any] = ["id": UUID().uuidString, "mode": mode,
      "language": "english", "wpm": Int(speed.rounded()), "rawWpm": Int(raw.rounded()),
      "accuracy": 98, "preciseAccuracy": 98.31, "consistency": 80.11,
      "errorCount": 1, "eventCount": 75, "tags": ["desk"],
      "startedAt": time - 15, "finishedAt": time,
      "startedAtReferenceTime": time - 15, "finishedAtReferenceTime": time,
      "speedPrecision": ["version": 1, "wpm": speed, "rawWpm": raw]]
    if mode == "time" { object["mode2"] = "15"; object["durationSeconds"] = 15 }
    if let tags { object["accountTagIDs"] = tags.map(\.uuidString) }
    if let restartCount { object["restartCount"] = restartCount }
    if let prior { object["practiceTiming"] = ["version": 1,
      "terminalEngagedMilliseconds": 14000, "priorAttemptEngagedMilliseconds": prior] }
    if let preciseDuration { object["elapsedTime"] = ["version": 1, "seconds": preciseDuration] }
    if options {
      object["personalBestConfiguration"] = ["version": 1, "difficulty": "expert",
        "punctuation": true, "numbers": false, "lazyMode": false]
      object["rankingEvidence"] = ["version": 1, "stopOnLetter": false, "modifiers": []]
    }
    return try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: object))
  }

  func testPrecisionIsNotRoundedBeforeAggregation() throws {
    let stats = AccountHistoryStatistics(try [row(), row(speed: 60.41, raw: 70.21)])
    XCTAssertEqual(try XCTUnwrap(stats.averageWpm), 70.45, accuracy: 1e-9)
    XCTAssertEqual(stats.maximumWpm, 80.49)
    XCTAssertEqual(try XCTUnwrap(stats.averageRaw), 80.26, accuracy: 1e-9)
    XCTAssertEqual(stats.averageAccuracy, 98.31)
    XCTAssertEqual(stats.averageConsistency, 80.11)
  }

  func testWholeLoadedCollectionIsFilteredBeforeStatisticsAndPageLimit() throws {
    let selected = UUID(), other = UUID()
    let rows = try (0..<25).map { try row(speed: $0 == 24 ? 100.25 : 60, raw: 120,
      tags: [$0 == 24 ? selected : other]) }
    let filter = ResultHistoryFilter(accountTagFilter: .init(scope: scope, knownIDs: [selected, other],
      selectedIDs: [selected], includesNoTags: false))
    let matched = AccountHistoryQuery.matching(rows, scope: scope, filter: filter)
    XCTAssertEqual(matched.map(\.id), [rows[24].id])
    XCTAssertEqual(AccountHistoryStatistics(matched).averageWpm, 100.25)
  }

  func testElapsedTerminalPlusExplicitPriorNotEngagedTerminalOrRestartEstimate() throws {
    let stats = AccountHistoryStatistics(try [row(restartCount: 2, prior: 2345)])
    XCTAssertEqual(stats.timeTyping, 17.345)
    XCTAssertEqual(stats.restarted, 2)
    XCTAssertEqual(stats.estimatedWords, 20)
  }

  func testMissingOrInvalidPracticeEvidenceDoesNotBecomeZeroOrSubtotal() throws {
    for unknown in try [row(restartCount: nil), row(restartCount: -1), row(restartCount: 1001)] {
      let stats = AccountHistoryStatistics(try [row(restartCount: 2, prior: 2000), unknown])
      XCTAssertNil(stats.restarted); XCTAssertNil(stats.started); XCTAssertNil(stats.completionPercentage)
      XCTAssertNil(stats.restartsPerCompleted); XCTAssertNil(stats.timeTyping)
      XCTAssertEqual(stats.completed, 2); XCTAssertEqual(stats.averageWpm, 80.49)
    }
    for unknown in try [row(prior: nil), row(prior: -1), row(prior: 1), row(restartCount: 1, prior: 3600001)] {
      XCTAssertNil(AccountHistoryStatistics([unknown]).timeTyping)
    }
    let absentDuration = try row(preciseDuration: nil)
    XCTAssertNil(AccountHistoryStatistics([absentDuration]).timeTyping)
    XCTAssertNil(AccountHistoryStatistics([absentDuration]).estimatedWords)
    XCTAssertEqual(AccountHistoryStatistics(try [row(restartCount: 2, prior: 0)]).timeTyping, 15,
      "Explicit zero prior time wins over the old restart estimate")
  }

  func testPerRowWordRoundingEmptyAndRestartDerivedCounts() throws {
    let stats = AccountHistoryStatistics(try [row(speed: 2.01, restartCount: 1), row(speed: 2.01, restartCount: 2)])
    XCTAssertEqual(stats.estimatedWords, 2)
    XCTAssertEqual(stats.started, 5); XCTAssertEqual(stats.completionPercentage, 40)
    XCTAssertEqual(stats.restartsPerCompleted, 1.5)
    let empty = AccountHistoryStatistics([])
    XCTAssertEqual(empty.completed, 0); XCTAssertEqual(empty.restarted, 0)
    XCTAssertEqual(empty.started, 0); XCTAssertEqual(empty.timeTyping, 0)
    XCTAssertEqual(empty.estimatedWords, 0); XCTAssertEqual(empty.completionPercentage, 0)
    XCTAssertEqual(empty.restartsPerCompleted, 0); XCTAssertNil(empty.averageWpm); XCTAssertNil(empty.maximumWpm)
  }

  func testLatestTenUsesChronologyAfterFilteringNotSpeedSortOrFirstPage() throws {
    let rows = try (0..<25).reversed().map { try row(speed: Double(100 - $0) + 0.25, raw: 120, time: Double($0) + 115) }
    let ascending = AccountHistoryQuery.sorted(rows, by: .wpm, direction: .ascending)
    XCTAssertEqual(ascending.first?.id, rows.first?.id)
    let recent = AccountHistoryQuery.latestTen(AccountHistoryQuery.sorted(rows, by: .wpm, direction: .descending))
    XCTAssertEqual(recent.map(\.id), Array(rows.prefix(10)).map(\.id))
    XCTAssertEqual(AccountHistoryStatistics(recent).averageWpm, 80.75)
    XCTAssertNotEqual(AccountHistoryStatistics(Array(rows.suffix(10))).averageWpm, 80.75)
  }

  func testTieSortUsesDateThenStableIDAndNeverRoundedSpeed() throws {
    let low = try row(speed: 80.41, time: 130), high = try row(speed: 80.49)
    XCTAssertEqual(AccountHistoryQuery.sorted([low,high], by: .wpm).map(\.id), [high.id,low.id])
    let equal = try row(speed: 80.49, time: 130)
    XCTAssertEqual(AccountHistoryQuery.sorted([high,equal], by: .wpm).map(\.id), [equal.id,high.id])
    let another = try row(speed: 80.49, time: 130)
    XCTAssertEqual(AccountHistoryQuery.sorted([another,equal], by: .wpm).map(\.id),
      [another.id,equal.id].sorted { $0.uuidString < $1.uuidString })
  }

  func testUnknownOptionsAndHistoricalPBCannotMasqueradeAsDefaultsOrNegativePB() throws {
    let known = try row(), unknown = try row(options: false)
    XCTAssertEqual(AccountHistoryQuery.matching([known,unknown], scope: scope, filter: .init()).count, 2)
    for filter in [ResultHistoryFilter(difficulties: [.expert]), .init(punctuation: .included),
      .init(numbers: .excluded), .init(modifierFilter: .init(includesNoModifiers: true, modifiers: []))] {
      XCTAssertEqual(AccountHistoryQuery.matching([known,unknown], scope: scope, filter: filter).map(\.id), [known.id])
    }
    for selection in ResultHistoryPersonalBestFilter.allCases where selection != .all {
      XCTAssertTrue(AccountHistoryQuery.matching([known,unknown], scope: scope,
        filter: .init(personalBestFilter: selection)).isEmpty)
    }
    let quote = try row(mode: "quote")
    XCTAssertEqual(AccountHistoryQuery.matching([known,quote], scope: scope, filter: .init()).count, 2)
    XCTAssertEqual(AccountHistoryQuery.matching([known,quote], scope: scope,
      filter: .init(quoteLengths: [.short])).map(\.id), [known.id])
    XCTAssertTrue(AccountHistoryQuery.matching([known], scope: scope, filter: .init(modes: [])).isEmpty)
  }

  func testAccountNoneTextNoneForeignScopeAndUnknownAssociationsStaySeparate() throws {
    let tag = UUID(), known = try row(tags: []), unknown = try row(tags: nil), tagged = try row(tags: [tag])
    let accountNone = ResultHistoryFilter(accountTagFilter: .init(scope: scope, knownIDs: [tag], selectedIDs: [], includesNoTags: true))
    XCTAssertEqual(AccountHistoryQuery.matching([known,unknown,tagged], scope: scope, filter: accountNone).map(\.id), [known.id])
    var both = accountNone
    both.tagFilter = .init(isUnrestricted: false, includesNoTags: true, tags: [])
    XCTAssertTrue(AccountHistoryQuery.matching([known,unknown,tagged], scope: scope, filter: both).isEmpty)
    let foreign = ResultPublicationScope(endpoint: "https://owned.invalid", userID: UUID())
    XCTAssertTrue(AccountHistoryQuery.matching([known,unknown,tagged], scope: foreign, filter: accountNone).isEmpty)
  }

  func testDayGroupingUsesInjectedLocalCalendarAcrossDSTAndNoSyntheticEmptyDays() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
    let parser = ISO8601DateFormatter()
    let dates = try ["2026-03-08T07:59:00Z", "2026-03-08T08:01:00Z", "2026-03-09T06:59:00Z", "2026-03-09T07:01:00Z"]
      .map { try XCTUnwrap(parser.date(from: $0)) }
    let rows = try dates.map { try row(time: $0.timeIntervalSinceReferenceDate) }
    let days = AccountHistoryQuery.days(rows, calendar: calendar)
    XCTAssertEqual(days.map { $0.statistics.completed }, [1,2,1])
    XCTAssertEqual(days[2].day.timeIntervalSince(days[1].day), 23 * 3600)
    XCTAssertEqual(days.map(\.day), [dates[0],dates[1],dates[3]].map { calendar.startOfDay(for: $0) })
    XCTAssertTrue(AccountHistoryQuery.days([], calendar: calendar).isEmpty)
  }

  func testCSVExportsWholeSortedFilterSnapshotAndRejectsAccountEndpointLogoutChanges() throws {
    let rows = try (0..<25).map { try row(time: Double($0) + 115) }
    let sorted = AccountHistoryQuery.sorted(rows)
    let snapshot = AccountHistoryExportSnapshot(scope: scope, rows: sorted)
    let csv = String(decoding: try XCTUnwrap(snapshot.data(currentScope: scope)), as: UTF8.self)
    XCTAssertEqual(csv.components(separatedBy: "\r\n").count, 27)
    XCTAssertTrue(csv.components(separatedBy: "\r\n")[1].hasPrefix(sorted[0].id.uuidString.lowercased()))
    XCTAssertTrue(csv.contains("80.49")); XCTAssertFalse(csv.contains("prompt")); XCTAssertFalse(csv.contains("replay"))
    XCTAssertNil(snapshot.data(currentScope: nil))
    XCTAssertNil(snapshot.data(currentScope: .init(endpoint: "https://owned.invalid", userID: UUID())))
    XCTAssertNil(snapshot.data(currentScope: .init(endpoint: "https://other.invalid", userID: scope.userID)))
  }

  @MainActor func testRealSessionExposesLoadedRowsBeyondTwentyAndInvalidatesAtScopeChange() throws {
    let suite = "TypebarTests.account-history.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let account = AccountSession(defaults: defaults)
    account.currentUser = .init(id: scope.userID, email: "owned@example.invalid", displayName: "Owned", totalExperience: 0)
    let directory = try JSONDecoder().decode(RemoteAccountTagList.self, from: Data(#"{"version":1,"tags":[]}"#.utf8))
    try account.applyAccountTagDirectory(directory, read: account.beginAccountTagDirectoryRead())
    let rows = try (0..<25).map { try row(time: Double($0) + 115) }
    try account.applyAccountTagHistory(rows, read: account.beginAccountTagHistoryRead())
    XCTAssertEqual(account.remoteResults.count, 20); XCTAssertEqual(account.accountHistoryLoadedResults.count, 25)
    XCTAssertEqual(AccountHistoryStatistics(account.accountHistoryLoadedResults).completed, 25)
    account.currentUser = .init(id: UUID(), email: "other@example.invalid", displayName: "Other", totalExperience: 0)
    XCTAssertTrue(account.accountHistoryLoadedResults.isEmpty)
    account.remoteResults = rows
    XCTAssertEqual(account.accountHistoryLoadedResults.count, 25, "Legacy recent-only projection is separately labelled in the UI")
    XCTAssertTrue(account.updateEndpoint("https://other.invalid"))
    XCTAssertTrue(account.accountHistoryLoadedResults.isEmpty)
  }

  func testMissingOrUnrepresentableModeParameterIsNotCustomAndDateFiltersApply() throws {
    let known = try row()
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(known)) as? [String: Any])
    object.removeValue(forKey: "mode2"); object["durationSeconds"] = Int.max
    let unknown = try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: object))
    XCTAssertEqual(AccountHistoryQuery.matching([unknown], scope: scope, filter: .init()).count, 1)
    XCTAssertTrue(AccountHistoryQuery.matching([unknown], scope: scope, filter: .init(timeLimits: [.custom])).isEmpty)
    XCTAssertEqual(AccountHistoryQuery.matching([known], scope: scope, filter: .init(timeLimits: [.seconds15])).map(\.id), [known.id])
    XCTAssertTrue(AccountHistoryQuery.matching([known], scope: scope, filter: .init(timeLimits: [.seconds30])).isEmpty)
    XCTAssertTrue(AccountHistoryQuery.matching([known], scope: scope,
      filter: .init(dateRange: .lastDay), now: known.finishedAt.addingTimeInterval(86401)).isEmpty)
  }

  func testLegacyOutOfRangeMetricsAndImpossibleEngagedTimingCannotLookLikeValidAggregates() throws {
    let row = try row()
    let original = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String: Any])
    func changed(_ mutate: (inout [String: Any]) -> Void) throws -> RemoteAccountResult {
      var value = original; mutate(&value)
      return try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: value))
    }
    let speed = try changed { $0.removeValue(forKey: "speedPrecision"); $0["wpm"] = 500; $0["rawWpm"] = 600 }
    let speedStats = AccountHistoryStatistics([row,speed])
    XCTAssertNil(speedStats.averageWpm); XCTAssertNil(speedStats.maximumWpm)
    XCTAssertNil(speedStats.averageRaw); XCTAssertNil(speedStats.maximumRaw); XCTAssertNil(speedStats.estimatedWords)
    let accuracy = try changed { $0["preciseAccuracy"] = 101 }
    XCTAssertNil(AccountHistoryStatistics([accuracy]).averageAccuracy)
    let consistency = try changed { $0["consistency"] = 101 }
    XCTAssertNil(AccountHistoryStatistics([consistency]).averageConsistency)
    let timing = try changed { $0["practiceTiming"] = ["version": 1,
      "terminalEngagedMilliseconds": 15001, "priorAttemptEngagedMilliseconds": 0] }
    XCTAssertNil(AccountHistoryStatistics([timing]).timeTyping)
  }

  func testPolyglotIsNotNoModifiersAndKnownCompanionStillMatches() throws {
    let original = try row()
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
    object["language"] = TypingLanguage.mixedLanguages.rawValue
    for modifiers in [["polyglot"], ["polyglot",TestModifier.memory.rawValue]] {
      object["rankingEvidence"] = ["version": 1, "stopOnLetter": false, "modifiers": modifiers]
      let row = try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: object))
      XCTAssertEqual(AccountHistoryQuery.matching([row], scope: scope, filter: .init()).map(\.id), [row.id])
      XCTAssertTrue(AccountHistoryQuery.matching([row], scope: scope,
        filter: .init(modifierFilter: .init(includesNoModifiers: true, modifiers: []))).isEmpty,
        "A service-only modifier must never disappear into the no-modifiers bucket")
      let memory = AccountHistoryQuery.matching([row], scope: scope,
        filter: .init(modifierFilter: .init(includesNoModifiers: false, modifiers: [.memory])))
      XCTAssertEqual(memory.map(\.id), modifiers.count == 2 ? [row.id] : [])
    }
  }

  func testExplicitPolyglotChoiceMatchesAndSurvivesEncoding() throws {
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ResultHistoryFilter())) as? [String: Any])
    object["modifierFilter"] = ["includesNoModifiers": false, "modifiers": [], "includesPolyglot": true]
    let filter = try JSONDecoder().decode(ResultHistoryFilter.self, from: JSONSerialization.data(withJSONObject: object))
    var remote = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(row())) as? [String: Any])
    remote["language"] = TypingLanguage.mixedLanguages.rawValue
    remote["rankingEvidence"] = ["version": 1, "stopOnLetter": false, "modifiers": ["polyglot"]]
    let result = try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: remote))
    XCTAssertEqual(AccountHistoryQuery.matching([result], scope: scope, filter: filter).map(\.id), [result.id])
    let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(filter)) as? [String: Any])
    XCTAssertEqual((encoded["modifierFilter"] as? [String: Any])?["includesPolyglot"] as? Bool, true)
  }

  func testAcceptedLegacyRawAbovePrecisionDomainStillAggregates() throws {
    let original = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(row())) as? [String: Any])
    for raw in [421, 500] {
      var object = original; object.removeValue(forKey: "speedPrecision"); object["rawWpm"] = raw
      let result = try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: object))
      XCTAssertEqual(AccountHistoryStatistics([result]).maximumRaw, Double(raw))
      XCTAssertEqual(AccountHistoryStatistics([result]).averageRaw, Double(raw))
    }
    var invalid = original; invalid.removeValue(forKey: "speedPrecision"); invalid["rawWpm"] = 501
    let result = try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: invalid))
    XCTAssertNil(AccountHistoryStatistics([result]).maximumRaw)
  }

  func testStatisticsAgainstCompletePinnedQueryNormalizationAndAggregationFunctions() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Readiness supplies the pinned reference")
    }
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Scripts/check-source-account-history-stats.mjs")
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node",script.path,reference,"--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors
    try process.run()
    let bytes = output.fileHandleForReading.readDataToEndOfFile()
    let error = errors.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus,0,String(decoding: error,as: UTF8.self))
    struct Stats: Decodable {
      let dayTimestamp: Double?
      let completed: Int; let restarted: Int; let words: Double; let timeTyping: Double
      let maxWpm: Double?; let avgWpm: Double?; let maxRaw: Double?; let avgRaw: Double?
      let maxAcc: Double?; let avgAcc: Double?; let maxConsistency: Double?; let avgConsistency: Double?
    }
    struct Fixture: Decodable {
      let wireRows: [RemoteAccountResult]; let selectedIDs: Set<UUID>; let includesNoTags: Bool
      let mode: String; let matchedIDs: [UUID]; let all: Stats; let recent: Stats; let days: [Stats]
    }
    struct Day: Decodable { let timeZone: String; let timestamps: [Double]; let expected: [Double] }
    struct Modifier: Decodable { let controls: [String]; let selection: String; let matches: Bool }
    struct Polyglot: Decodable {
      let controls: [String]; let includesNoModifiers, includesPolyglot, includesMemory, matches: Bool
    }
    struct Metadata: Decodable { let pb: ResultHistoryPersonalBestFilter; let lengths: Set<QuoteLength>; let mode: String; let matchedIDs: [UUID] }
    struct Quote: Decodable { let length: Int; let group: Int; let classification: QuoteLength }
    struct Document: Decodable {
      let referenceCommit: String; let ids: Set<UUID>; let fixtures: [Fixture]
      let dayFixtures: [Day]; let modifierFixtures: [Modifier]
      let polyglotFixtures: [Polyglot]
      let metadataRows: [RemoteAccountResult]; let metadataFixtures: [Metadata]; let quoteFixtures: [Quote]
    }
    let document = try JSONDecoder().decode(Document.self, from: bytes)
    XCTAssertEqual(document.referenceCommit,"91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(document.fixtures.count,96); XCTAssertEqual(document.dayFixtures.count,4)
    XCTAssertEqual(document.modifierFixtures.count,9)
    XCTAssertEqual(document.polyglotFixtures.count,32)
    XCTAssertEqual(document.metadataFixtures.count,192); XCTAssertEqual(document.quoteFixtures.count,6)
    for fixture in document.metadataFixtures {
      let filter = ResultHistoryFilter(modes: fixture.mode == "all" ? nil : [try XCTUnwrap(TestMode(rawValue: fixture.mode))],
        personalBestFilter: fixture.pb, quoteLengths: fixture.lengths)
      XCTAssertEqual(AccountHistoryQuery.matching(document.metadataRows, scope: scope, filter: filter).map(\.id), fixture.matchedIDs,
        "\(fixture.pb)/\(fixture.lengths)/\(fixture.mode)")
    }
    for quote in document.quoteFixtures {
      XCTAssertEqual(quote.classification.compatibilityValue, String(quote.group))
      let selected = try XCTUnwrap(ResultQuoteSource.make(mode: .quote, sourceIsCommunity: true,
        title: "Owned partial text", actualLength: quote.classification))
      XCTAssertEqual(selected.actualLength, quote.classification)
    }
    func compare(_ native: AccountHistoryStatistics, _ source: Stats) throws {
      XCTAssertEqual(native.completed, source.completed); XCTAssertEqual(native.restarted, source.restarted)
      XCTAssertEqual(try XCTUnwrap(native.timeTyping), source.timeTyping, accuracy: 1e-8)
      XCTAssertEqual(native.estimatedWords, source.words)
      for (actual, expected) in [(native.averageWpm,source.avgWpm),(native.maximumWpm,source.maxWpm),
        (native.averageRaw,source.avgRaw),(native.maximumRaw,source.maxRaw),
        (native.averageAccuracy,source.avgAcc),(native.maximumAccuracy,source.maxAcc),
        (native.averageConsistency,source.avgConsistency),(native.maximumConsistency,source.maxConsistency)] {
        if let expected { XCTAssertEqual(try XCTUnwrap(actual), expected, accuracy: 1e-8) }
        else { XCTAssertNil(actual) }
      }
    }
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    for fixture in document.fixtures {
      let filter = ResultHistoryFilter(modes: fixture.mode == "all" ? nil : [try XCTUnwrap(TestMode(rawValue: fixture.mode))],
        accountTagFilter: .init(scope: scope, knownIDs: document.ids,
          selectedIDs: fixture.selectedIDs, includesNoTags: fixture.includesNoTags))
      let rows = AccountHistoryQuery.matching(fixture.wireRows, scope: scope, filter: filter)
      XCTAssertEqual(rows.map(\.id), fixture.matchedIDs)
      try compare(AccountHistoryStatistics(rows), fixture.all)
      try compare(AccountHistoryStatistics(AccountHistoryQuery.latestTen(rows)), fixture.recent)
      let days = AccountHistoryQuery.days(rows, calendar: calendar)
      XCTAssertEqual(days.count, fixture.days.count)
      for (native, source) in zip(days, fixture.days) {
        XCTAssertEqual(native.day.timeIntervalSince1970 * 1000, source.dayTimestamp)
        try compare(native.statistics, source)
      }
    }
    for fixture in document.dayFixtures {
      calendar.timeZone = try XCTUnwrap(TimeZone(identifier: fixture.timeZone))
      for (timestamp, expected) in zip(fixture.timestamps, fixture.expected) {
        let row = try row(time: timestamp / 1000 - 978307200)
        XCTAssertEqual(AccountHistoryQuery.days([row], calendar: calendar).first?.day.timeIntervalSince1970,
          expected / 1000)
      }
    }
    for fixture in document.modifierFixtures {
      let original = try row()
      var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
      object["language"] = fixture.controls.contains("polyglot") ? TypingLanguage.mixedLanguages.rawValue : "english"
      object["rankingEvidence"] = ["version": 1, "stopOnLetter": false, "modifiers": fixture.controls]
      let remote = try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: object))
      let modifiers: ResultHistoryModifierFilter
      switch fixture.selection {
      case "none": modifiers = .init(includesNoModifiers: true, modifiers: [])
      case "memory": modifiers = .init(includesNoModifiers: false, modifiers: [.memory])
      default: modifiers = .init()
      }
      XCTAssertEqual(!AccountHistoryQuery.matching([remote], scope: scope,
        filter: .init(modifierFilter: modifiers)).isEmpty, fixture.matches)
    }
    for fixture in document.polyglotFixtures {
      var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(row())) as? [String: Any])
      object["language"] = fixture.controls.contains("polyglot") ? TypingLanguage.mixedLanguages.rawValue : "english"
      object["rankingEvidence"] = ["version": 1, "stopOnLetter": false, "modifiers": fixture.controls]
      let remote = try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: object))
      let filter = ResultHistoryFilter(modifierFilter: .init(includesNoModifiers: fixture.includesNoModifiers,
        modifiers: fixture.includesMemory ? [.memory] : [], includesPolyglot: fixture.includesPolyglot))
      XCTAssertEqual(!AccountHistoryQuery.matching([remote], scope: scope, filter: filter).isEmpty, fixture.matches)
    }
  }
}
