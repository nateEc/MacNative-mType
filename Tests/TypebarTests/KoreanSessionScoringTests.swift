import XCTest
import SwiftData
@testable import Typebar

final class KoreanSessionScoringTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 911_000_000)
  private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
  }
  private func finish(_ input: TypingSession) throws -> CompletedTestResult {
    var copy = input; copy.bailOut(at: start.addingTimeInterval(60))
    return try XCTUnwrap(copy.result())
  }

  func testActualSessionExpandsFiveUnitsWithoutChangingReplayGlyphsOrAttempts() throws {
    var input = TypingSession(configuration: .words(0), prompt: "괅 ")
    input.insertBatch("괅", at: start)
    let saved = try finish(input)
    XCTAssertEqual(saved.wpm, 1)
    XCTAssertEqual(saved.rawWpm, 1)
    XCTAssertEqual(saved.inputMetrics?.creditedUnits, 5)
    XCTAssertEqual(saved.inputMetrics?.retainedUnits, 5)
    XCTAssertEqual(saved.inputMetrics?.totalAttempts, 1)
    XCTAssertEqual(saved.inputMetrics?.correctAttempts, 1)
    XCTAssertEqual(saved.typedCharacterCount, 1)
    XCTAssertEqual(saved.preciseAccuracy, 100)
    XCTAssertEqual(TypingReplay.typedText(events: saved.replayEvents, through: 60), "괅")
    let metrics = try object(try XCTUnwrap(saved.inputMetrics))
    XCTAssertEqual(metrics["version"] as? Int, 2)
    XCTAssertEqual(metrics["retainedInputUnits"] as? Int, 1)
    XCTAssertEqual(metrics["scoringUnitBasis"] as? String, "koreanJamo")
    let stats = try object(saved.characterStats)
    XCTAssertEqual(stats["sourceUnitBasis"] as? String, "koreanJamo")
    XCTAssertEqual((stats["sourceUnits"] as? [String: Int])?["correctWord"], 5)
  }

  func testPartialSyllableGetsLiveAndBailedOutCreditButNotNativeAttemptCredit() throws {
    var input = TypingSession(configuration: .words(0), prompt: "각 ")
    input.insertBatch("가", at: start)
    XCTAssertEqual(input.preciseWpm(at: start.addingTimeInterval(60)), 0.4, accuracy: 0.001)
    XCTAssertEqual(input.preciseRawWpm(at: start.addingTimeInterval(60)), 0.4, accuracy: 0.001)
    let saved = try finish(input)
    XCTAssertEqual(saved.inputMetrics?.creditedUnits, 2)
    XCTAssertEqual(saved.inputMetrics?.correctAttempts, 0)
    XCTAssertEqual(saved.preciseAccuracy, 0)
    XCTAssertEqual(saved.correctCharacterCount, 0)
    XCTAssertEqual((try object(saved.characterStats)["sourceUnits"] as? [String: Int])?["missed"], 0)
  }

  func testLabelsHistoryAndCSVNeverCallKoreanCountsUTF16() throws {
    var input = TypingSession(configuration: .words(0), prompt: "괅 ")
    input.insertBatch("괅", at: start)
    let saved = try finish(input)
    XCTAssertTrue(ResultCharacterStatsPresentation.label(saved.characterStats).contains("韩文拆分"))
    XCTAssertFalse(ResultCharacterStatsPresentation.spoken(saved.characterStats).contains("UTF-16"))
    let summary = ResultHistoryRowSummaryPolicy.summary(configuration: saved.configuration,
      characterStats: saved.characterStats, tags: [])
    XCTAssertEqual(summary.characterStats, "韩文拆分单位 5/0/0/0")
    let row = ResultCSVExport.csvString(for: [saved]).components(separatedBy: "\r\n")[1].components(separatedBy: ",")
    let columns = Dictionary(uniqueKeysWithValues: zip(ResultCSVExport.columns, row))
    XCTAssertEqual(columns["source_credited_utf16_units"], "")
    XCTAssertEqual(columns["source_scoring_unit_basis"], "koreanJamo")
    XCTAssertEqual(columns["source_credited_scoring_units"], "5")
  }

  func testUnrecognizedNoSpaceDirectoryDoesNotInventKoreanScoring() throws {
    var input = TypingSession(configuration: .words(0).with(modifiers: [.noSpaces]), prompt: "괅")
    input.insertBatch("괅", at: start)
    let saved = try finish(input)
    XCTAssertNil(saved.characterStats.sourceUnits)
    XCTAssertNotEqual(saved.inputMetrics?.scoringUnitBasis, .koreanJamo)
  }

  func testZenInputDoesNotEnableKoreanScoring() throws {
    var input = TypingSession(configuration: .init(mode: .zen, duration: nil,
      wordLimit: nil, difficulty: .normal, rules: .init()), prompt: "")
    input.insertBatch("괅", at: start); input.finishZen(at: start.addingTimeInterval(60))
    let saved = try XCTUnwrap(input.result())
    XCTAssertEqual(saved.inputMetrics?.retainedUnits, 1)
    XCTAssertNotEqual(saved.inputMetrics?.scoringUnitBasis, .koreanJamo)
  }

  func testBasisStaysFrozenAcrossPromptGrowthAndRestart() throws {
    var input = TypingSession(configuration: .timed(seconds: 60), prompt: "a ", repeatingPrompt: "괅 ")
    input.insertBatch("a ", at: start)
    input.insertBatch("괅", at: start.addingTimeInterval(1))
    XCTAssertTrue(input.prompt.contains("괅"))
    input.tick(at: start.addingTimeInterval(60))
    let saved = try XCTUnwrap(input.result())
    XCTAssertEqual(saved.inputMetrics?.retainedUnits, 3)
    XCTAssertNil(saved.characterStats.sourceUnitBasis)
    XCTAssertEqual(ResultCharacterStatsPresentation.unitName(saved.characterStats), "UTF-16 单位")
    var repeatInput = input.repeatedAttempt()
    XCTAssertEqual(repeatInput.prompt, "a ")
    repeatInput.insertBatch("a 괅", at: start)
    XCTAssertEqual(try finish(repeatInput).inputMetrics?.retainedUnits, 3)

    var korean = TypingSession(configuration: .timed(seconds: 60), prompt: "괅 ", repeatingPrompt: "a ")
    korean.insertBatch("괅 a", at: start)
    XCTAssertEqual(try finish(korean).inputMetrics?.retainedUnits, 7)
    var koreanRepeat = korean.repeatedAttempt()
    koreanRepeat.insertBatch("괅", at: start)
    XCTAssertEqual(try finish(koreanRepeat).inputMetrics?.retainedUnits, 5)
  }

  func testKnownNoSpaceFieldsAndPartialDeletionKeepRawUnits() throws {
    var input = TypingSession(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(freedomMode: true), modifiers: [.noSpaces]),
      prompt: "괅x가z", noSpaceTargetWords: ["괅x", "가z"])
    input.insertBatch("괅x가", at: start)
    XCTAssertEqual(try finish(input).inputMetrics?.retainedUnits, 8)
    input.deleteBackward(at: start.addingTimeInterval(1))
    let saved = try finish(input)
    XCTAssertEqual(saved.characterStats.sourceUnitBasis, .koreanJamo)
    XCTAssertEqual(saved.inputMetrics?.retainedUnits, 6)
    XCTAssertEqual(saved.inputMetrics?.retainedInputUnits, 2)
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: saved.replayEvents), ["괅x", ""])
    XCTAssertEqual(saved.replayEvents.first?.inputField?.units, Array("괅".utf16))
    XCTAssertEqual(saved.replayEvents.last?.inputField?.units, [])
    XCTAssertEqual(saved.inputMetrics?.totalAttempts, 3)
  }

  func testActualPublicationNegotiatesV2AndKeepsPrivateInputOutOfRequest() throws {
    var input = TypingSession(configuration: .words(0), prompt: "괅 ")
    input.insertBatch("괅", at: start)
    let saved = try finish(input)
    let old = RemoteServiceCapabilities(apiVersion: "v1", service: "typebar",
      capabilities: ["resultInputMetrics": "available"])
    XCTAssertThrowsError(try ResultInputMetricsPublicationPolicy.validate(saved, capabilities: old))
    let new = RemoteServiceCapabilities(apiVersion: "v1", service: "typebar",
      capabilities: ["resultInputMetricsV2": "available"])
    XCTAssertNoThrow(try ResultInputMetricsPublicationPolicy.validate(saved, capabilities: new))
    let submission = RemoteResultSubmission(result: saved, includesInputMetricsV2: true)
    XCTAssertEqual(submission.inputMetrics, saved.inputMetrics)
    let json = String(decoding: try JSONEncoder().encode(submission), as: UTF8.self)
    for text in ["괅", "prompt", "replayEvents", "inputField", "keyCode"] { XCTAssertFalse(json.contains(text)) }
  }

  @MainActor func testArchive22PortableAndInMemoryPersistencePreserveExplicitBasis() throws {
    var input = TypingSession(configuration: .words(0), prompt: "괅 ")
    input.insertBatch("괅", at: start)
    let saved = try finish(input)
    let data = try TypebarDataTransfer.exportArchive(settings: .init(), results: [saved], presets: [], at: start)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from: data).results, [saved])
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: saved).portableResult), saved)
    let container = try ModelContainer(for: TestResultRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    container.mainContext.insert(TestResultRecord(result: saved)); try container.mainContext.save()
    XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).first?.portableResult, saved)
    // Formal date precision is owned by the exporter; mutate that payload only.
    var value = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    for version in 1...21 {
      XCTAssertEqual(TypebarArchive(version: version, exportedAt: start,
        settings: .init(), results: [saved], presets: []).version, 22)
      value["version"] = version
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: value))) {
        XCTAssertEqual($0 as? DataTransferError, .unsupportedVersion(version))
      }
    }
  }

  func testOwnedArchive21NeverRecalculatesOldHangulScoresOrInventsNewBasis() throws {
    let old = CompletedTestResult(id: UUID(), configuration: .words(1), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(60), typedCharacterCount: 1,
      correctCharacterCount: 1, errorCount: 0, wpm: 17, rawWpm: 29, accuracy: 77,
      inputMetrics: .init(version: 1, correctAttempts: 1, totalAttempts: 1, creditedUnits: 1, retainedUnits: 1),
      characterStats: .init(matched: 1, incorrect: 0, extra: 0, missed: 0,
        sourceUnits: .classify(input: [0xad05], target: [0xad05], creditsPartial: false)), prompt: "괅")
    let archive = TypebarArchive(version: 21, exportedAt: start, settings: .init(), results: [old], presets: [])
    XCTAssertEqual(archive.version, 21)
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    let restored = try TypebarDataTransfer.importArchive(from: encoder.encode(archive)).results[0]
    XCTAssertEqual(restored, old)
    XCTAssertNil(restored.characterStats.sourceUnitBasis)
    XCTAssertEqual(ResultCharacterStatsPresentation.unitName(restored.characterStats), "UTF-16 单位")
    XCTAssertEqual(restored.wpm, 17)
    XCTAssertEqual(restored.rawWpm, 29)
  }

  func testDecoderRejectsUnknownOrOrphanBasisWithoutChangingGenuineOldShape() throws {
    let old = ResultCharacterStats(matched: 1, incorrect: 0, extra: 0, missed: 0)
    XCTAssertNil(try object(old)["sourceUnitBasis"])
    for basis in ["other", "koreanJamo", "utf16"] {
      var value = try object(old); value["sourceUnitBasis"] = basis
      XCTAssertThrowsError(try JSONDecoder().decode(ResultCharacterStats.self,
        from: JSONSerialization.data(withJSONObject: value)))
    }
  }

  func testCacheProjectsAfterSpaceNormalizationWithoutRewritingNULOrSurrogates() {
    var cache = RecordedInputFieldStats()
    let raw: [UInt16] = [0,0xac00,0xd83d,0x3000]
    cache.record(.init(offset: 0, kind: .insert, units: raw,
      inputField: .init(index: 7, units: raw)))
    let counts = cache.counts(targets: .init("각"), creditsActivePrefix: false, basis: .koreanJamo)
    XCTAssertEqual(counts.unitStats.correctWord, 5) // Missing source target uses projected normalized input.
    XCTAssertEqual(counts.rawUnits, 5)
    XCTAssertEqual(counts.retainedInputUnits, 4)
    XCTAssertEqual(cache.history(7), raw)
    XCTAssertEqual(ResultUnitCharacterStats.classify(input: raw, target: [],
      creditsPartial: false, basis: .koreanJamo).extra, 5)
  }

  func testExplicitAbandonedFieldProjectionDoesNotUseClearedSavedHistory() {
    // Source-time field fixture, not physical IME or navigation evidence.
    var cache = RecordedInputFieldStats()
    cache.record(.init(offset: 0, kind: .insert, units: [0xad05],
      inputField: .init(index: 0, units: [0xad05,120])))
    cache.record(.init(offset: 1, kind: .insert, units: [0xac00],
      inputField: .init(index: 1, units: [0xac00])))
    cache.record(.init(offset: 2, kind: .delete, units: [],
      inputField: .init(index: 0, units: [0xad05]), discardedInputUnits: 1, clearedNextWord: true))
    let counts = cache.counts(targets: .init("괅x가", noSpaceWords: ["괅x", "가"]),
      creditsActivePrefix: true, basis: .koreanJamo)
    XCTAssertEqual(cache.history(0), [0xad05])
    XCTAssertEqual(cache.history(1), [])
    XCTAssertEqual(counts.rawUnits, 7)
    XCTAssertEqual(counts.retainedInputUnits, 2)
    XCTAssertEqual(counts.credit.inputUnits, 2) // First incomplete committed word earns no credit.
  }
}
