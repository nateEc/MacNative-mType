import XCTest
import SwiftData
@testable import Typebar

final class SourceUnitCharacterStatsTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 909_400_000)
  private func session(_ words: [String] = ["ab", "cd"]) -> TypingSession {
    .init(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(freedomMode: true), modifiers: [.noSpaces]),
      prompt: words.joined(), noSpaceTargetWords: words)
  }
  private func result(_ input: TypingSession) throws -> CompletedTestResult {
    var copy = input; copy.bailOut(at: start.addingTimeInterval(4))
    return try XCTUnwrap(copy.result())
  }
  private func counts(_ result: CompletedTestResult) throws -> [String: Int]? {
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(result.characterStats)) as? [String: Any])
    return object["sourceUnits"] as? [String: Int]
  }

  func testAbandonedHistoryKeepsRawFieldClassificationAndWordCredit() throws {
    var input = session(); input.insertBatch("abcd ", at: start)
    input.deleteBackward(at: start.addingTimeInterval(1))
    let saved = try result(input)
    XCTAssertEqual(try counts(saved), ["allCorrect": 3, "correctWord": 2, "incorrect": 0, "extra": 0, "missed": 1])
    XCTAssertEqual(saved.characterStats.matched, 1)
    XCTAssertEqual(saved.inputMetrics?.retainedUnits, 3)
    let summary = ResultHistoryRowSummaryPolicy.summary(configuration: saved.configuration,
      characterStats: saved.characterStats, tags: [])
    XCTAssertEqual(summary.characterStats, "UTF-16 单位 2/0/0/1")
    XCTAssertEqual(summary.accessibilityMetadata, "UTF-16 单位：计分正确 2，错误 0，多打 0，漏打 1；位置匹配 3")
  }

  func testSupplementaryUnitsDoNotReplaceNativeGlyphCounters() throws {
    var input = session(["ab", "🙂"]); input.insertBatch("ab🙂 ", at: start)
    input.deleteBackward(at: start.addingTimeInterval(1))
    let saved = try result(input)
    XCTAssertEqual(try counts(saved), ["allCorrect": 3, "correctWord": 2, "incorrect": 0, "extra": 0, "missed": 1])
    XCTAssertEqual(saved.typedCharacterCount, 2)
    XCTAssertEqual(saved.correctCharacterCount, 1)
    XCTAssertEqual(saved.characterStats.matched, 1)
  }

  func testBailedOutPrefixSuppressesMissedUnitsButTypoLosesWordCredit() throws {
    var prefix = session(["abcd"]); prefix.insertBatch("ab", at: start)
    XCTAssertEqual(try counts(result(prefix)), ["allCorrect": 2, "correctWord": 2, "incorrect": 0, "extra": 0, "missed": 0])
    var typo = session(["abcd"]); typo.insertBatch("ax", at: start)
    XCTAssertEqual(try counts(result(typo)), ["allCorrect": 1, "correctWord": 0, "incorrect": 1, "extra": 0, "missed": 0])
  }

  func testFailedInfiniteWordsStillUseTimedMissingUnitPolicy() throws {
    for (limit, missed) in [(0,0), (1,2)] {
      var input = TypingSession(configuration: .words(limit, difficulty: .master).with(modifiers: [.noSpaces]),
        prompt: "abcd", noSpaceTargetWords: ["abcd"])
      input.insertBatch("ax", at: start)
      let saved = try XCTUnwrap(input.result())
      XCTAssertEqual(saved.outcome, .failed)
      XCTAssertEqual(try counts(saved), ["allCorrect": 1, "correctWord": 0, "incorrect": 1, "extra": 0, "missed": missed])
    }
  }

  func testClassifiedResultsRequireNineteenAndBothPersistenceBoundariesKeepThem() throws {
    var input = session(); input.insertBatch("abcd ", at: start)
    input.deleteBackward(at: start.addingTimeInterval(1))
    let saved = try result(input)
    let data = try TypebarDataTransfer.exportArchive(settings: .init(), results: [saved], presets: [], at: start)
    let restored = try TypebarDataTransfer.importArchive(from: data)
    XCTAssertEqual(restored.version, 19)
    XCTAssertEqual(try counts(try XCTUnwrap(TestResultRecord(result: saved).portableResult)), try counts(saved))
    XCTAssertNotNil(try counts(restored.results[0]))
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    for version in 1...18 {
      object["version"] = version
      XCTAssertEqual(TypebarArchive(version: version, exportedAt: start, settings: .init(), results: [saved], presets: []).version, 19)
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: object))) {
        XCTAssertEqual($0 as? DataTransferError, .unsupportedVersion(version))
      }
    }
  }

  func testOwnedEighteenClearFixtureKeepsOriginalStatisticsAndMinimumVersion() throws {
    let old = CompletedTestResult(id: UUID(), configuration: .words(2).with(modifiers: [.noSpaces]),
      outcome: .bailedOut, startedAt: start, finishedAt: start.addingTimeInterval(2),
      typedCharacterCount: 3, correctCharacterCount: 2, errorCount: 0, wpm: 24, rawWpm: 36,
      accuracy: 77, characterStats: .init(matched: 1, incorrect: 0, extra: 0, missed: 0), prompt: "abcd",
      replayEvents: [.init(offset: 0, kind: .insert, units: [97,98], inputField: .init(index: 0, units: [97,98])),
        .init(offset: 0, kind: .insert, units: [99,100], inputField: .init(index: 1, units: [99,100])),
        .init(offset: 1, kind: .delete, units: [], inputField: .init(index: 0, units: [97]),
          discardedInputUnits: 2, clearedNextWord: true)],
      targetWordDirectory: .init(words: ["ab", "cd"], noSpace: true))
    XCTAssertNil(old.characterStats.sourceUnits)
    let archive = TypebarArchive(version: 1, exportedAt: start, settings: .init(), results: [old], presets: [])
    XCTAssertEqual(archive.version, 18)
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    let restored = try TypebarDataTransfer.importArchive(from: encoder.encode(archive)).results[0]
    XCTAssertEqual(restored, old)
    XCTAssertNil(try counts(restored))
    XCTAssertEqual(ResultCharacterStatsPresentation.value(restored.characterStats), "1/0/0/0")
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: restored.replayEvents), ["a", ""])
  }

  func testClassifierDistinguishesMatchingSpaceCreditExtrasAndMissing() throws {
    let cases: [(String, String, Bool, [Int])] = [
      ("ab", "ab", false, [2,2,0,0,0]),
      ("ax ", "ab ", false, [1,0,1,1,0]),
      ("ab", "ab ", false, [2,0,0,0,1]),
      ("abx", "ab ", false, [2,0,0,1,0]),
      ("ab ", "ab cd", true, [2,3,0,1,0]),
      ("ax", "abcd", true, [1,0,1,0,0]),
      ("ax", "abcd", false, [1,0,1,0,2]),
      ("abxx", "ab", true, [2,0,0,2,0]),
      ("", "abcd", false, [0,0,0,0,4]),
      ("", "abcd", true, [0,0,0,0,0]),
      ("🙂", "🙂", false, [2,2,0,0,0]),
      ("e\u{301}", "e\u{301}b", true, [2,2,0,0,0]),
      ("a\n", "ab\n", false, [1,0,1,0,1]),
      ("x y", "ab ", false, [0,0,3,0,0]),
    ]
    for (input, target, partial, expected) in cases {
      let units = ResultUnitCharacterStats.classify(input: Array(input.utf16), target: Array(target.utf16), creditsPartial: partial)
      XCTAssertEqual([units.allCorrect, units.correctWord, units.incorrect, units.extra, units.missed], expected, "\(input) / \(target) / \(partial)")
      XCTAssertEqual(units.allCorrect + units.incorrect + units.extra, input.utf16.count)
      XCTAssertEqual(try JSONDecoder().decode(ResultUnitCharacterStats.self, from: JSONEncoder().encode(units)), units)
    }
  }

  func testClassifierNormalizesReferenceSpacesAndKeepsRawSurrogateUnits() {
    let normalized = ResultUnitCharacterStats.classify(input: [97,0x3000], target: [97,32], creditsPartial: false)
    XCTAssertEqual(normalized.correctWord, 2)
    XCTAssertEqual(normalized.allCorrect, 2)
    let prefix = ResultUnitCharacterStats.classify(input: [0xd83d], target: [0xd83d,0xde42], creditsPartial: true)
    XCTAssertEqual(prefix.correctWord, 1)
    XCTAssertEqual(prefix.allCorrect, 1)
    XCTAssertEqual(prefix.missed, 0)
    let full = ResultUnitCharacterStats.classify(input: [0xd83d], target: [0xd83d,0xde42], creditsPartial: false)
    XCTAssertEqual(full.correctWord, 0)
    XCTAssertEqual(full.missed, 1)
  }

  func testMissingSourceTargetFallsBackWithoutConfusingKnownEmptyWord() {
    let fallback = ResultUnitCharacterStats.classify(input: [97,0x3000], target: nil, creditsPartial: false)
    XCTAssertEqual(fallback.correctWord, 2)
    XCTAssertEqual(fallback.extra, 0)
    let empty = ResultUnitCharacterStats.classify(input: [97,0x3000], target: [], creditsPartial: false)
    XCTAssertEqual(empty.correctWord, 0)
    XCTAssertEqual(empty.extra, 2)
    var cache = RecordedInputFieldStats()
    cache.record(.init(offset: 0, kind: .insert, units: [97], inputField: .init(index: 7, units: [97,0x3000])))
    let counts = cache.counts(targets: .init("ab", noSpaceWords: ["ab"]), creditsActivePrefix: false)
    XCTAssertEqual(counts.unitStats, fallback)
    XCTAssertEqual(counts.credit.inputUnits, 2)
  }

  func testCSVAppendsExplicitUnitsAndLeavesGenuineOlderRowsUnknown() throws {
    var input = session(); input.insertBatch("abcd ", at: start)
    input.deleteBackward(at: start.addingTimeInterval(1))
    let saved = try result(input)
    let row = ResultCSVExport.csvString(for: [saved]).components(separatedBy: "\r\n")[1]
      .components(separatedBy: ",")
    XCTAssertEqual(row.count, ResultCSVExport.columns.count)
    XCTAssertEqual(Array(row.suffix(5)), ["3", "2", "0", "0", "1"])
    XCTAssertEqual(Array(ResultCSVExport.columns.suffix(5)), ["source_matched_utf16_units", "source_credited_utf16_units", "source_incorrect_utf16_units", "source_extra_utf16_units", "source_missed_utf16_units"])
    XCTAssertFalse(row.joined().contains(saved.prompt))
    let old = CompletedTestResult(id: UUID(), configuration: .words(1), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(2), typedCharacterCount: 1,
      correctCharacterCount: 1, errorCount: 0, wpm: 6, rawWpm: 6, accuracy: 100)
    XCTAssertTrue(ResultCSVExport.csvString(for: [old]).hasSuffix(",,,,,\r\n"))
  }

  func testInvalidClassificationPayloadsCannotOverflowOrClaimUnenteredCredit() throws {
    for object: [String: Int] in [
      ["allCorrect": -1, "correctWord": 0, "incorrect": 0, "extra": 0, "missed": 0],
      ["allCorrect": 1, "correctWord": 2, "incorrect": 0, "extra": 0, "missed": 0],
      ["allCorrect": Int.max, "correctWord": 0, "incorrect": 1, "extra": 0, "missed": 0],
      ["allCorrect": 0, "correctWord": 0, "incorrect": 0, "extra": 0, "missed": -1],
    ] {
      XCTAssertThrowsError(try JSONDecoder().decode(ResultUnitCharacterStats.self, from: JSONSerialization.data(withJSONObject: object)))
    }
  }

  @MainActor func testInMemoryEntityPersistsBothClassificationUnitsWithoutColumnChanges() throws {
    var input = session(); input.insertBatch("abcd ", at: start)
    input.deleteBackward(at: start.addingTimeInterval(1))
    let saved = try result(input)
    let container = try ModelContainer(for: TestResultRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    container.mainContext.insert(TestResultRecord(result: saved)); try container.mainContext.save()
    let fetched = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).first?.portableResult)
    XCTAssertEqual(fetched, saved)
    XCTAssertEqual(try counts(fetched), ["allCorrect": 3, "correctWord": 2, "incorrect": 0, "extra": 0, "missed": 1])
  }

  func testUnknownNoSpaceDirectoryAndGenuineLegacyJSONNeverInventUnitClassification() throws {
    var input = TypingSession(configuration: .words(2).with(modifiers: [.noSpaces]), prompt: "abcd")
    input.insertBatch("ax", at: start)
    XCTAssertNil(try counts(result(input)))
    let stats = try JSONDecoder().decode(ResultCharacterStats.self,
      from: Data(#"{"matched":7,"incorrect":2,"extra":1,"missed":3}"#.utf8))
    XCTAssertNil(stats.sourceUnits)
    XCTAssertEqual(ResultCharacterStatsPresentation.value(stats), "7/2/1/3")
  }
}
