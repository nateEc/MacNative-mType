import XCTest
import SwiftData
@testable import Typebar

final class KoreanPerformanceTraceTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 911_300_000)
  private func insert(_ unit: UInt16, field: Int = 0, snapshot: [UInt16], at: Double = 0,
    correct: Bool = true, stopped: Bool = false, lastWord: Bool = false, commits: Bool? = nil
  ) -> TypingReplayEvent {
    .init(offset: at, kind: .insert, units: [unit], commitsWord: commits, inputStopped: stopped,
      inputField: .init(index: field, units: snapshot), inputCorrectness: [correct],
      inputPosition: .init(charIndex: max(0, snapshot.count - 1), lastWord: lastWord))
  }

  func testSixActualSourceHistoryFixturesKeepScoringSeparateFromAttempts() {
    let cases: [(String, [TypingReplayEvent], Double, [Int], [Int], [Double], [Int])] = [
      ("괅", [insert(0xad05, snapshot: [0xad05])], 2, [60,30], [60,30], [12,0], [0,0]),
      ("각", [insert(0xac00, snapshot: [0xac00], correct: false),
        insert(0xac01, snapshot: [0xac01], at: 1.5)], 3.5, [24,18,12,10], [24,18,12,10], [12,12,0,0], [1,0,0,0]),
      ("괅", [insert(32, snapshot: [0xad05,32], correct: false, lastWord: true, commits: true)],
        2, [60,30], [60,30], [12,0], [1,0]),
      ("각", [insert(32, snapshot: [0xac00], correct: false, stopped: true, lastWord: true)],
        2, [0,0], [24,12], [12,0], [1,0]),
      ("괅x가", [insert(120, snapshot: [0xad05,120]),
        insert(0xac00, field: 1, snapshot: [0xac00], at: 0.5),
        .init(offset: 1.5, kind: .delete, units: [], inputField: .init(index: 0, units: [0xad05]),
          discardedInputUnits: 1, clearedNextWord: true)], 2, [96,12], [96,42], [24,0], [0,0]),
      ("가🙂", [insert(0xd83d, snapshot: [0xac00,0xd83d], correct: false)],
        2, [36,18], [36,18], [12,0], [1,0]),
    ]
    for (prompt, events, duration, wpm, raw, burst, errors) in cases {
      let directory = prompt == "괅x가" ? ResultTargetWordDirectory(words: ["괅x","가"], noSpace: true) : nil
      let config = directory == nil ? TestConfiguration.words(1) : .words(1).with(modifiers: [.noSpaces])
      let points = ResultPerformanceTrace.points(prompt: prompt, events: events,
        duration: duration, configuration: config, targetWordDirectory: directory,
        sourceScoringBasis: .koreanJamo)
      XCTAssertEqual(points.map(\.wpm), wpm, prompt)
      XCTAssertEqual(points.map(\.rawWpm), raw, prompt)
      XCTAssertEqual(points.map(\.burstWpm), burst, prompt)
      XCTAssertEqual(points.map(\.errorCount), errors, prompt)
      XCTAssertEqual(points.last, ResultPerformanceTrace.point(prompt: prompt, events: events,
        elapsed: duration, configuration: config, targetWordDirectory: directory, sourceScoringBasis: .koreanJamo))
    }
  }

  func testActualSavedSessionCurveUsesItsCapturedBasisNotLanguageOrFinalPrompt() throws {
    var session = TypingSession(configuration: .words(0), prompt: "괅 ")
    session.insertBatch("괅", at: start); session.bailOut(at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.characterStats.sourceUnitBasis, .koreanJamo)
    let points = ResultPerformanceTrace.points(prompt: result.prompt, events: result.replayEvents,
      duration: result.elapsedDuration, configuration: result.configuration,
      targetWordDirectory: result.targetWordDirectory, sourceScoringBasis: result.characterStats.sourceUnitBasis)
    XCTAssertEqual(points.map(\.wpm), [60,30])
    XCTAssertEqual(points.map(\.rawWpm), [60,30])
    XCTAssertEqual(points.last?.wpm, result.wpm)
    XCTAssertEqual(points.last?.rawWpm, result.rawWpm)
    XCTAssertEqual(points.map(\.burstWpm), [12,0])
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 1)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 2), "괅")
  }

  func testGenuineMissingBasisDoesNotGuessKoreanFromPrompt() {
    let events = [insert(0xad05, snapshot: [0xad05])]
    let old = ResultPerformanceTrace.points(prompt: "괅", events: events, duration: 2)
    XCTAssertEqual(old.map(\.wpm), [12,6])
    XCTAssertEqual(old, ResultPerformanceTrace.points(prompt: "괅", events: events,
      duration: 2, sourceScoringBasis: .utf16))
  }

  func testGrowthFromASCIIDoesNotSelectBasisFromTheFinalPrompt() throws {
    var session = TypingSession(configuration: .timed(seconds: 2), prompt: "a ", repeatingPrompt: "괅 ")
    session.insertBatch("a ", at: start)
    session.insertBatch("괅", at: start.addingTimeInterval(1)); session.tick(at: start.addingTimeInterval(2))
    let saved = try XCTUnwrap(session.result())
    XCTAssertTrue(saved.prompt.contains("괅"))
    XCTAssertNil(saved.characterStats.sourceUnitBasis)
    let points = ResultPerformanceTrace.points(prompt: saved.prompt, events: saved.replayEvents,
      duration: 2, configuration: saved.configuration, sourceScoringBasis: saved.characterStats.sourceUnitBasis)
    XCTAssertEqual(points.map(\.wpm), [36,18])
    XCTAssertEqual(points.last?.wpm, saved.wpm)
    XCTAssertEqual(points.map(\.rawWpm), [36,18])
  }

  func testUnknownMalformedAndMixedFieldTapesRetainTheirPriorFallback() {
    let noSpace = TestConfiguration.words(0).with(modifiers: [.noSpaces])
    let events = [insert(0xad05, snapshot: [0xad05])]
    let unknown = ResultPerformanceTrace.points(prompt: "괅x", events: events, duration: 2,
      configuration: noSpace)
    XCTAssertEqual(unknown, ResultPerformanceTrace.points(prompt: "괅x", events: events, duration: 2,
      configuration: noSpace, sourceScoringBasis: .koreanJamo))
    for tape in [
      [insert(0xad05, field: Int.max, snapshot: [0xad05])],
      [TypingReplayEvent(offset: 0, kind: .insert, units: [0xad05],
        inputField: .init(index: 0, value: "가", valueUTF16: [0xad05]))],
      events + [.init(offset: 1, kind: .delete, units: [])],
    ] {
      XCTAssertEqual(ResultPerformanceTrace.point(prompt: "괅x", events: tape, elapsed: 2),
        ResultPerformanceTrace.point(prompt: "괅x", events: tape, elapsed: 2, sourceScoringBasis: .koreanJamo))
    }
    let invalid = ResultTargetWordDirectory(words: ["각"], noSpace: true)
    XCTAssertEqual(unknown, ResultPerformanceTrace.points(prompt: "괅x", events: events, duration: 2,
      configuration: noSpace, targetWordDirectory: invalid, sourceScoringBasis: .koreanJamo))
  }

  func testZenCannotTurnAnExplicitBadKoreanHintIntoScoringExpansion() {
    let config = TestConfiguration(mode: .zen, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init())
    let events = [insert(0xad05, snapshot: [0xad05], correct: false)]
    let points = ResultPerformanceTrace.points(prompt: "", events: events, duration: 2,
      configuration: config, sourceScoringBasis: .koreanJamo)
    XCTAssertEqual(points.map(\.wpm), [12,6])
    XCTAssertEqual(points.map(\.rawWpm), [12,6])
    XCTAssertEqual(points.map(\.errorCount), [0,0])
  }

  func testFirstAppearanceOrderAndStableEqualOffsetsKeepSourceRoles() {
    let events = [insert(0xac00, field: 1, snapshot: [0xac00]),
      insert(32, snapshot: [0xad05,32], at: 0.5)]
    let points = ResultPerformanceTrace.points(prompt: "괅 가", events: events, duration: 2,
      sourceScoringBasis: .koreanJamo)
    XCTAssertEqual(points.map(\.wpm), [24,12])
    XCTAssertEqual(points.map(\.rawWpm), [24,12])
    XCTAssertEqual(points.map(\.burstWpm), [24,0])
    XCTAssertEqual(points.map(\.errorCount), [0,0])
    let tied = [insert(0xad05, snapshot: [0xad05]),
      TypingReplayEvent(offset: 0, kind: .delete, units: [], inputField: .init(index: 0, units: [])),
      insert(0xac00, snapshot: [0xac00])]
    XCTAssertEqual(ResultPerformanceTrace.point(prompt: "가", events: tied, elapsed: 1,
      sourceScoringBasis: .koreanJamo).wpm, 24)
  }

  func testLiteralNewlineInsideSavedNoSpaceWordDoesNotBecomeAWordBreak() {
    let events = [insert(10, snapshot: [0xad05,10]), insert(0xac00, field: 1, snapshot: [0xac00])]
    let points = ResultPerformanceTrace.points(prompt: "괅\n가", events: events, duration: 2,
      configuration: .words(0).with(modifiers: [.noSpaces]),
      targetWordDirectory: .init(words: ["괅\n","가"], noSpace: true), sourceScoringBasis: .koreanJamo)
    XCTAssertEqual(points.map(\.wpm), [96,48])
    XCTAssertEqual(points.map(\.rawWpm), [96,48])
    XCTAssertEqual(points.map(\.burstWpm), [24,0])
    XCTAssertEqual(events[0].inputField?.units, [0xad05,10])
  }

  func testTrimRequiresAllSourceEvidenceAndPreservesTheRawBuffer() {
    for (correct, stopped, last, commits) in [(true,false,true,true), (false,true,true,true),
      (false,false,false,true), (false,false,true,false)] {
      let events = [insert(32, snapshot: [0xad05,32], correct: correct, stopped: stopped,
        lastWord: last, commits: commits)]
      XCTAssertEqual(ResultPerformanceTrace.point(prompt: "괅", events: events, elapsed: 1,
        sourceScoringBasis: .koreanJamo).rawWpm, 72)
      XCTAssertEqual(events[0].inputField?.units, [0xad05,32])
    }
  }

  func testAvailabilityCeilingAndSingleFractionalPointUseTheSameBasis() {
    let events = [insert(0xad05, snapshot: [0xad05])]
    XCTAssertEqual(ResultPerformanceTrace.point(prompt: "괅", events: events, elapsed: 0.5,
      sourceScoringBasis: .koreanJamo).wpm, 120)
    XCTAssertTrue(ResultPerformanceChartAvailability.isAvailable(prompt: "괅", events: events,
      duration: 122, sourceScoringBasis: .koreanJamo))
    XCTAssertFalse(ResultPerformanceChartAvailability.isAvailable(prompt: "괅", events: events,
      duration: 122.1, sourceScoringBasis: .koreanJamo))
    XCTAssertTrue(ResultPerformanceTrace.points(prompt: "괅", events: events, duration: Double.greatestFiniteMagnitude,
      sourceScoringBasis: .koreanJamo).isEmpty)
  }

  @MainActor func testFormalPortableAndInMemoryRecordKeepCurveBasisWithoutChangingTheScore() throws {
    var session = TypingSession(configuration: .words(0), prompt: "괅 ")
    session.insertBatch("괅", at: start); session.bailOut(at: start.addingTimeInterval(2))
    let saved = try XCTUnwrap(session.result())
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [saved], presets: [], at: start))
    XCTAssertEqual(archive.version, 22)
    let container = try ModelContainer(for: TestResultRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    container.mainContext.insert(TestResultRecord(result: saved)); try container.mainContext.save()
    let stored = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).first)
    XCTAssertEqual(stored.characterStats.sourceUnitBasis, .koreanJamo)
    for result in [archive.results[0], try XCTUnwrap(TestResultRecord(result: saved).portableResult),
      try XCTUnwrap(stored.portableResult)] {
      XCTAssertEqual(result, saved)
      let points = ResultPerformanceTrace.points(prompt: result.prompt, events: result.replayEvents,
        duration: 2, configuration: result.configuration, targetWordDirectory: result.targetWordDirectory,
        sourceScoringBasis: result.characterStats.sourceUnitBasis)
      XCTAssertEqual(points.map(\.wpm), [60,30])
      XCTAssertEqual(points.last?.wpm, result.wpm)
      XCTAssertEqual(points.last?.rawWpm, result.rawWpm)
    }
  }

  func testOwnedArchive21KeepsItsOldBasisAndStoredMetrics() throws {
    let old = CompletedTestResult(id: UUID(), configuration: .words(1), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(2), typedCharacterCount: 1,
      correctCharacterCount: 1, errorCount: 0, wpm: 17, rawWpm: 29, accuracy: 77,
      characterStats: .init(matched: 1, incorrect: 0, extra: 0, missed: 0,
        sourceUnits: .classify(input: [0xad05], target: [0xad05], creditsPartial: false)),
      prompt: "괅", replayEvents: [insert(0xad05, snapshot: [0xad05])])
    let archive = TypebarArchive(version: 21, exportedAt: start, settings: .init(), results: [old], presets: [])
    XCTAssertEqual(archive.version, 21)
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    let restored = try TypebarDataTransfer.importArchive(from: encoder.encode(archive)).results[0]
    XCTAssertEqual(restored, old)
    let points = ResultPerformanceTrace.points(prompt: restored.prompt, events: restored.replayEvents,
      duration: 2, configuration: restored.configuration, sourceScoringBasis: restored.characterStats.sourceUnitBasis)
    XCTAssertEqual(points.map(\.wpm), [12,6])
    XCTAssertEqual(restored.wpm, 17)
    XCTAssertEqual(restored.rawWpm, 29)
    XCTAssertNil(restored.characterStats.sourceUnitBasis)
  }
}
