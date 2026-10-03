import SwiftData
import XCTest
@testable import Typebar

final class ZenSourceUnitStatsTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 910_100_000)

  private func session(rules: InputRules = .init()) -> TypingSession {
    .init(configuration: .init(mode: .zen, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: rules), prompt: "")
  }

  private func finish(_ session: TypingSession) throws -> CompletedTestResult {
    var copy = session
    copy.finishZen(at: start.addingTimeInterval(2))
    return try XCTUnwrap(copy.result())
  }

  private func units(_ result: CompletedTestResult) throws -> ResultUnitCharacterStats {
    try XCTUnwrap(result.characterStats.sourceUnits)
  }

  func testSupplementaryAndCombiningTextUsesFiveUnitsWithoutReplacingThreeGlyphs() throws {
    var input = session()
    input.insertBatch("🙂 e\u{301}", at: start)
    let saved = try finish(input)
    let stats = try units(saved)
    XCTAssertEqual(stats.allCorrect, 5)
    XCTAssertEqual(stats.correctWord, 5)
    XCTAssertEqual([stats.incorrect, stats.extra, stats.missed], [0,0,0])
    XCTAssertEqual(saved.characterStats.matched, 3)
    XCTAssertEqual(saved.typedCharacterCount, 3)
    XCTAssertEqual(saved.correctCharacterCount, 3)
    XCTAssertEqual(saved.inputMetrics?.creditedUnits, 5)
    XCTAssertEqual(saved.inputMetrics?.retainedUnits, 5)
    XCTAssertEqual(saved.preciseAccuracy, 100)
    XCTAssertEqual(ResultCharacterStatsPresentation.value(saved.characterStats), "5/0/0/0")
  }

  func testRejectedShiftAttemptDoesNotBecomeAcceptedSourceText() throws {
    var input = session(rules: .init(oppositeShiftMode: .on))
    input.insertBatch("x", forceError: true, at: start)
    input.insertBatch("a", at: start.addingTimeInterval(1))
    let saved = try finish(input)
    XCTAssertEqual(try units(saved).correctWord, 1)
    XCTAssertEqual(saved.inputMetrics?.totalAttempts, 2)
    XCTAssertEqual(saved.inputMetrics?.correctAttempts, 2)
    XCTAssertEqual(saved.characterStats.matched, 1)
    XCTAssertEqual(saved.replayEvents.first?.isStoppedInsertion, true)
    XCTAssertEqual(TypingReplay.typedText(events: saved.replayEvents, through: 2), "a")
  }

  func testEmptyAcceptedFieldHasZeroUnitsAfterRejectedAttempt() throws {
    var input = session(rules: .init(oppositeShiftMode: .on))
    input.insertBatch("x", forceError: true, at: start)
    let saved = try finish(input)
    XCTAssertEqual(try units(saved), ResultUnitCharacterStats())
    XCTAssertEqual(saved.typedCharacterCount, 0)
    XCTAssertEqual(saved.inputMetrics?.totalAttempts, 1)
  }

  func testSourceFallbackHandlesReturnsAndTrailingCommitWithoutATarget() throws {
    for text in ["a\n\nb", "ab ", "가 🙂", "a\u{3000}"] {
      var input = session()
      input.insertBatch(text, at: start)
      let saved = try finish(input)
      let stats = try units(saved)
      XCTAssertEqual(stats.correctWord, input.typed.utf16.count, text)
      XCTAssertEqual(stats.allCorrect, input.typed.utf16.count, text)
      XCTAssertEqual([stats.incorrect, stats.extra, stats.missed], [0,0,0], text)
      XCTAssertEqual(saved.characterStats.matched, input.typed.count, text)
    }
  }

  func testLateUnicodeConversionKeepsEarlierASCIIFieldsAndLiteralTabs() throws {
    var input = session()
    input.insertBatch("ab ", at: start)
    input.insertBatch("\t🙂", at: start.addingTimeInterval(1))
    let saved = try finish(input)
    XCTAssertEqual(try units(saved).correctWord, 6)
    XCTAssertEqual(saved.characterStats.matched, 5)
    XCTAssertEqual(saved.replayEvents.last?.inputField?.units, [9,0xd83d,0xde42])
  }

  func testDeletionReentryAndRepeatUseFreshFieldSnapshots() throws {
    var input = session()
    input.insertBatch("ab c", at: start)
    input.deleteBackward(at: start.addingTimeInterval(0.5))
    XCTAssertEqual(try units(finish(input)).correctWord, 3)
    input.insertBatch("d", at: start.addingTimeInterval(1))
    XCTAssertEqual(try units(finish(input)).correctWord, 4)
    var repeated = input.repeatedAttempt()
    repeated.insertBatch("z", at: start)
    XCTAssertEqual(try units(finish(repeated)).correctWord, 1)
  }

  func testPreInsertionCapDoesNotAddUnloggedUnits() throws {
    var input = session()
    input.insertBatch(String(repeating: "a", count: 35), at: start)
    let saved = try finish(input)
    XCTAssertEqual(saved.replayEvents.count, 30)
    XCTAssertEqual(try units(saved).correctWord, 30)
    XCTAssertEqual(saved.inputMetrics?.totalAttempts, 30)
  }

  func testFailedMinimumBurstAndBailoutStillClassifyTheLoggedInput() throws {
    var failed = session(rules: .init(minimumWordBurstWpm: 100, minimumWordBurstMode: .fixed))
    failed.insertBatch("f", at: start)
    failed.insertBatch("ree ", at: start.addingTimeInterval(4))
    let saved = try XCTUnwrap(failed.result())
    XCTAssertEqual(saved.outcome, .failed)
    XCTAssertEqual(try units(saved).correctWord, 5)
    XCTAssertEqual(saved.characterStats.matched, 5)
    var bailed = session()
    bailed.insertBatch("🙂", at: start)
    bailed.bailOut(at: start.addingTimeInterval(1))
    XCTAssertEqual(try units(try XCTUnwrap(bailed.result())).correctWord, 2)
  }

  func testFormalPortableRoundTripsRetainStatsAndRequireNineteen() throws {
    var input = session()
    input.insertBatch("🙂 e\u{301}", at: start)
    let saved = try finish(input)
    let data = try TypebarDataTransfer.exportArchive(settings: .init(), results: [saved], presets: [], at: start)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from: data).results, [saved])
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: saved).portableResult), saved)
    XCTAssertEqual(TypebarArchive(version: 1, exportedAt: start, settings: .init(),
      results: [saved], presets: []).version, 19)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    for version in 1...18 {
      object["version"] = version
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: object))) {
        XCTAssertEqual($0 as? DataTransferError, .unsupportedVersion(version))
      }
    }
  }

  func testGenuineEighteenZenFixtureDoesNotBackfillOrRescore() throws {
    // An owned older record, not a current session with its new fields removed.
    let old = CompletedTestResult(id: UUID(), configuration: .init(mode: .zen, duration: nil,
      wordLimit: nil, difficulty: .normal, rules: .init()), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(2), typedCharacterCount: 1,
      correctCharacterCount: 1, errorCount: 0, wpm: 17, rawWpm: 29, accuracy: 77,
      characterStats: .init(matched: 1, incorrect: 0, extra: 0, missed: 0), prompt: "",
      replayEvents: [.init(offset: 0, kind: .insert, text: "🙂", inputField: .init(index: 0, value: "🙂"))])
    let archive = TypebarArchive(version: 18, exportedAt: start, settings: .init(), results: [old], presets: [])
    XCTAssertEqual(archive.version, 18)
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    let restored = try TypebarDataTransfer.importArchive(from: encoder.encode(archive)).results[0]
    XCTAssertEqual(restored, old)
    XCTAssertNil(restored.characterStats.sourceUnits)
    XCTAssertEqual(ResultCharacterStatsPresentation.value(restored.characterStats), "1/0/0/0")
    XCTAssertTrue(ResultCSVExport.csvString(for: [restored]).hasSuffix(",,,,,\r\n"))
  }

  @MainActor func testInMemoryEntityRetainsUnitsAndNativeGlyphStats() throws {
    var input = session()
    input.insertBatch("🙂 e\u{301}", at: start)
    let saved = try finish(input)
    let container = try ModelContainer(for: TestResultRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    container.mainContext.insert(TestResultRecord(result: saved))
    try container.mainContext.save()
    let fetched = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).first?.portableResult)
    XCTAssertEqual(fetched, saved)
    XCTAssertEqual(try units(fetched).correctWord, 5)
    XCTAssertEqual(fetched.characterStats.matched, 3)
  }

  func testHistoryAccessibilityAndCSVExposeUnitsWithoutChangingGlyphColumns() throws {
    var input = session()
    input.insertBatch("🙂 e\u{301}", at: start)
    let saved = try finish(input)
    let summary = ResultHistoryRowSummaryPolicy.summary(configuration: saved.configuration,
      characterStats: saved.characterStats, tags: [])
    XCTAssertEqual(summary.characterStats, "UTF-16 单位 5/0/0/0")
    XCTAssertEqual(summary.accessibilityMetadata, "UTF-16 单位：计分正确 5，错误 0，多打 0，漏打 0；位置匹配 5")
    let row = ResultCSVExport.csvString(for: [saved]).components(separatedBy: "\r\n")[1].components(separatedBy: ",")
    XCTAssertEqual(row.count, ResultCSVExport.columns.count)
    XCTAssertEqual(Array(row.suffix(5)), ["5", "5", "0", "0", "0"])
    XCTAssertFalse(row.joined().contains("🙂"))
  }

  func testUnknownNoSpaceSessionsRemainUnclassifiedAfterOrdinaryCapture() throws {
    var input = TypingSession(configuration: .words(2).with(modifiers: [.noSpaces]), prompt: "ab cd")
    input.insertBatch("a", at: start)
    input.bailOut(at: start.addingTimeInterval(2))
    XCTAssertNil(try XCTUnwrap(input.result()).characterStats.sourceUnits)
  }
}
