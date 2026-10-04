import SwiftData
import XCTest
@testable import Typebar

final class OrdinarySourceUnitStatsTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 910_300_000)
  private func result(_ session: TypingSession) throws -> CompletedTestResult {
    var copy = session
    copy.bailOut(at: start.addingTimeInterval(4))
    return try XCTUnwrap(copy.result())
  }
  private func counts(_ saved: CompletedTestResult) throws -> [Int] {
    let stats = try XCTUnwrap(saved.characterStats.sourceUnits)
    return [stats.allCorrect, stats.correctWord, stats.incorrect, stats.extra, stats.missed]
  }

  func testTypoWordMatchingSpaceIsExtraNotCreditedButLaterWordStillScores() throws {
    var input = TypingSession(configuration: .words(2), prompt: "ab cd")
    input.insertBatch("ax cd", at: start)
    let saved = try result(input)
    XCTAssertEqual(try counts(saved), [3,2,1,1,0])
    XCTAssertEqual(saved.characterStats.matched, 4)
    XCTAssertEqual(saved.inputMetrics?.creditedUnits, 2)
  }

  func testSupplementaryAndCombiningFieldsKeepSeparateNativeGlyphCounts() throws {
    var input = TypingSession(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init()), prompt: "🙂 e\u{301}")
    input.insertBatch("🙂 e\u{301}", at: start)
    let saved = try result(input)
    XCTAssertEqual(try counts(saved), [5,5,0,0,0])
    XCTAssertEqual(saved.characterStats.matched, 3)
    XCTAssertEqual(saved.typedCharacterCount, 3)
    XCTAssertEqual(saved.inputMetrics?.creditedUnits, 5)
  }

  func testFinalSpaceCommitTrimsSourceProjectionAndFinalSpeedButNotReplay() throws {
    var input = TypingSession(configuration: .words(1), prompt: "ab")
    input.insertBatch("ab ", at: start)
    let saved = try result(input)
    XCTAssertEqual(saved.outcome, .completed)
    XCTAssertEqual(saved.inputMetrics?.creditedUnits, 2)
    XCTAssertEqual(saved.inputMetrics?.retainedUnits, 2)
    XCTAssertEqual(saved.correctCharacterCount, 2)
    XCTAssertEqual(try counts(saved), [2,2,0,0,0])
    XCTAssertEqual(saved.typedCharacterCount, 3)
    XCTAssertEqual(saved.replayEvents.last?.inputField?.units, [97,98,32])
    XCTAssertEqual(saved.replayEvents.last?.inputPosition, .init(charIndex: 2, lastWord: true))
    XCTAssertEqual(TypingReplay.typedText(events: saved.replayEvents, through: 4), "ab ")
  }

  func testFinalWpmAndRawUseTheSameTrimmedSourceNumerators() throws {
    var input = TypingSession(configuration: .words(1), prompt: "ab")
    input.insertBatch("a", at: start)
    input.insertBatch("b ", at: start.addingTimeInterval(1))
    let saved = try result(input)
    XCTAssertEqual(saved.preciseWpm, 24)
    XCTAssertEqual(saved.preciseRawWpm, 24)
    XCTAssertEqual(saved.preciseAccuracy, 66.67)
    XCTAssertEqual(saved.characterStats.extra, 1)
    XCTAssertEqual(try counts(saved), [2,2,0,0,0])
  }

  func testStoppedAndRetainedFinalSpacesAreNotTrimmedAsCommits() throws {
    var stopped = TypingSession(configuration: .words(1, rules: .init(stopOnErrorMode: .letter)), prompt: "ab")
    stopped.insertBatch("a ", at: start)
    let stoppedSaved = try result(stopped)
    XCTAssertEqual(try counts(stoppedSaved), [1,0,0,0,1])
    XCTAssertEqual(stoppedSaved.replayEvents.last?.isStoppedInsertion, true)
    var retained = TypingSession(configuration: .words(1, rules: .init(stopOnErrorMode: .word)), prompt: "ab")
    retained.insertBatch("ax ", at: start)
    let retainedSaved = try result(retained)
    XCTAssertEqual(try counts(retainedSaved), [1,0,1,1,0])
    XCTAssertEqual(retainedSaved.replayEvents.last?.commitsWord, false)
  }

  func testTerminalSpaceBatchReentryKeepsTheActualFieldAndPreClearPosition() throws {
    for target in ["ab", "🙂"] {
      var input = TypingSession(configuration: .words(1), prompt: target)
      input.insertBatch(target + " x", at: start)
      XCTAssertFalse(input.isFinished, target)
      XCTAssertEqual(input.typed, "x", target)
      let saved = try result(input)
      XCTAssertEqual(try counts(saved), [0,0,1,0,0], target)
      XCTAssertEqual(saved.replayEvents.last?.inputField?.index, 0, target)
      XCTAssertEqual(saved.replayEvents.last?.inputPosition, .init(charIndex: 3, lastWord: true), target)
      XCTAssertEqual(saved.replayEvents.last?.discardedInputUnits, 3, target)
      XCTAssertEqual(TypingReplay.typedText(events: saved.replayEvents, through: 4), "x", target)
      input.insertBatch("b", at: start.addingTimeInterval(1))
      XCTAssertEqual(try result(input).replayEvents.last?.inputPosition?.charIndex, 1, target)
    }
  }

  func testPartialModePolicyDistinguishesFailedFiniteFromInfiniteWords() throws {
    for (limit, missed) in [(0,0), (1,2)] {
      var input = TypingSession(configuration: .words(limit, difficulty: .master), prompt: "abcd")
      input.insertBatch("ax", at: start)
      let saved = try result(input)
      XCTAssertEqual(saved.outcome, .failed)
      XCTAssertEqual(try counts(saved), [1,0,1,0,missed])
    }
    var prefix = TypingSession(configuration: .words(1), prompt: "abcd")
    prefix.insertBatch("ab", at: start)
    XCTAssertEqual(try counts(result(prefix)), [2,2,0,0,0])
  }

  func testEarlySpaceAndBlankReturnFieldsKeepMissingAndEmptySlots() throws {
    var early = TypingSession(configuration: .words(2), prompt: "abcd ef")
    early.insertBatch("a ef", at: start)
    XCTAssertEqual(try counts(result(early)), [3,2,1,0,3])
    var quote = TypingSession(configuration: .init(mode: .quote, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init()), prompt: "ab\n\ncd")
    quote.insertBatch("ab\n\ncd", at: start)
    let saved = try result(quote)
    XCTAssertEqual(try counts(saved), [6,6,0,0,0])
    XCTAssertEqual(saved.replayEvents.map { $0.inputField?.index }, [0,0,0,1,2,2])
  }

  func testInsertionPositionsUseUnitsAndCatalogIdentityBeforeTimedRefill() throws {
    var unicode = TypingSession(configuration: .words(2), prompt: "🙂 e\u{301}")
    unicode.insertBatch("🙂 e\u{301}", at: start)
    XCTAssertEqual(try result(unicode).replayEvents.map { $0.inputPosition?.charIndex }, [0,1,2,0,1])
    var timed = TypingSession(configuration: .timed(seconds: 5), prompt: "ab ", repeatingPrompt: "cd")
    timed.insertBatch("ab ", at: start)
    timed.insertBatch("c", at: start.addingTimeInterval(1))
    timed.tick(at: start.addingTimeInterval(5))
    let saved = try XCTUnwrap(timed.result())
    XCTAssertEqual(saved.replayEvents.prefix(3).map { $0.inputPosition?.lastWord }, [true,true,true])
    XCTAssertTrue(saved.prompt.contains("cd"))
    XCTAssertEqual(try counts(saved), [4,4,0,0,0])
  }

  func testTargetTraitsKeepASCIICatalogLazyAndDetectActualHangulNotLanguageName() {
    for source in ["", "ab", "ab ", "ab\n", "ab\n\ncd", " a", "🙂 e\u{301}"] {
      let lazy = UnitInputTargets(source)
      XCTAssertEqual(lazy.sourceFieldCount, UnitInputTargets(source, buildsASCIICatalog: true).fields.count)
      if source.utf8.allSatisfy({ $0 < 128 }) { XCTAssertTrue(lazy.fields.isEmpty) }
    }
    for source in ["가", "\u{1100}", "\u{3130}", "\u{a960}", "\u{d7b0}"] {
      XCTAssertTrue(UnitInputTargets(source).requiresKoreanDisassembly, source)
    }
    XCTAssertFalse(UnitInputTargets("🙂 e\u{301}").requiresKoreanDisassembly)
    var hangul = TypingSession(configuration: .words(1), prompt: "가x")
    hangul.insertBatch("가", at: start)
    hangul.bailOut(at: start.addingTimeInterval(1))
    XCTAssertEqual(hangul.result()?.characterStats.sourceUnits?.correctWord, 2)
    XCTAssertEqual(hangul.result()?.characterStats.sourceUnitBasis, .koreanJamo)
  }

  func testCacheTrimPreservesRawHistorySurrogateAndNonECMAScriptNEL() {
    // Raw policy fixtures, not physical insertion normalization or IME proof.
    for (raw, target, expected): ([UInt16], String, [Int]) in [
      ([97,0xfeff,32], "a", [1,1,0,0,0]),
      ([97,0x85,32], "a", [1,0,0,1,0]),
      ([0xd83d,32], "🙂", [1,0,0,0,1]),
    ] {
      var cache = RecordedInputFieldStats()
      cache.record(.init(offset: 0, kind: .insert, units: [32],
        inputField: .init(index: 0, units: raw), inputCorrectness: [false],
        inputPosition: .init(charIndex: raw.count - 1, lastWord: true)))
      let value = cache.counts(targets: .init(target, buildsASCIICatalog: true), creditsActivePrefix: true).unitStats
      XCTAssertEqual([value.allCorrect,value.correctWord,value.incorrect,value.extra,value.missed], expected)
      XCTAssertEqual(cache.history(0), raw)
    }
  }

  func testGrowingASCIIFieldCountKeepsSourceTimeIdentityAndRestart() throws {
    for chunks in [["a", " ", "b\n", "\n", "c"], ["🙂", " ", "e\u{301}\n"]] {
      var text = ""; var separators = 0
      for chunk in chunks {
        text += chunk
        separators += chunk.utf8.filter { $0 == 32 || $0 == 10 }.count
        XCTAssertEqual(UnitInputTargets(text, asciiSeparatorCount: separators).sourceFieldCount,
          UnitInputTargets(text, buildsASCIICatalog: true).fields.count)
      }
    }
    var input = TypingSession(configuration: .words(0), prompt: "a ", repeatingPrompt: "b ")
    for word in 0..<120 {
      input.insertBatch(word == 0 ? "a " : "b ", at: start.addingTimeInterval(Double(word)))
    }
    var finished = input
    finished.bailOut(at: start.addingTimeInterval(120))
    let saved = try XCTUnwrap(finished.result())
    let commits = saved.replayEvents.filter { $0.text == " " }
    XCTAssertEqual(commits.count, 120)
    for (word, event) in commits.enumerated() {
      XCTAssertEqual(event.inputPosition?.lastWord, true)
      XCTAssertEqual(event.inputField?.index, word)
    }
    var restarted = input.repeatedAttempt()
    restarted.insertBatch("a ", at: start)
    let restartResult = try result(restarted)
    XCTAssertEqual(restartResult.replayEvents.last?.inputPosition?.lastWord, true)
    XCTAssertEqual(restartResult.replayEvents.last?.inputField?.index, 0)
  }

  func testMissingFalseOrStoppedCommitEvidenceCannotTrimRawField() {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, units: [32], commitsWord: false,
        inputField: .init(index: 0, units: [97,98,32]), inputCorrectness: [false],
        inputPosition: .init(charIndex: 2, lastWord: true)),
      .init(offset: 0, kind: .insert, units: [32], inputStopped: true,
        inputField: .init(index: 0, units: [97,98,32]), inputCorrectness: [false],
        inputPosition: .init(charIndex: 2, lastWord: true)),
      .init(offset: 0, kind: .insert, units: [32],
        inputField: .init(index: 0, units: [97,98,32]), inputCorrectness: [false]),
      .init(offset: 0, kind: .insert, units: [32],
        inputField: .init(index: 0, units: [97,98,32]),
        inputPosition: .init(charIndex: 2, lastWord: true)),
      .init(offset: 0, kind: .insert, units: [10],
        inputField: .init(index: 0, units: [97,98,10]), inputCorrectness: [false],
        inputPosition: .init(charIndex: 2, lastWord: true)),
    ]
    for event in events {
      var cache = RecordedInputFieldStats(); cache.record(event)
      XCTAssertEqual(cache.counts(targets: .init("ab", buildsASCIICatalog: true),
        creditsActivePrefix: true).rawUnits, 3)
    }
  }

  func testFormalPortableAndCSVRetainUnitStatsAndDoNotMislabelNineteen() throws {
    var input = TypingSession(configuration: .words(2), prompt: "ab cd")
    input.insertBatch("ax cd", at: start)
    let saved = try result(input)
    let data = try TypebarDataTransfer.exportArchive(settings: .init(), results: [saved], presets: [], at: start)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from: data).results, [saved])
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: saved).portableResult), saved)
    XCTAssertEqual(TypebarArchive(version: 1, exportedAt: start, settings: .init(), results: [saved], presets: []).version, 19)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    for version in 1...18 {
      object["version"] = version
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: object))) {
        XCTAssertEqual($0 as? DataTransferError, .unsupportedVersion(version))
      }
    }
    let row = ResultCSVExport.csvString(for: [saved]).components(separatedBy: "\r\n")[1].components(separatedBy: ",")
    let scoringColumns = ["source_matched_scoring_units", "source_credited_scoring_units",
      "source_incorrect_scoring_units", "source_extra_scoring_units", "source_missed_scoring_units"]
    XCTAssertEqual(row.count, ResultCSVExport.columns.count)
    let firstScoringColumn = try XCTUnwrap(ResultCSVExport.columns.firstIndex(of: scoringColumns[0]))
    XCTAssertEqual(Array(ResultCSVExport.columns.dropFirst(firstScoringColumn).prefix(5)), scoringColumns)
    let scoringValues = Dictionary(uniqueKeysWithValues: zip(ResultCSVExport.columns, row))
    XCTAssertEqual(scoringColumns.map { scoringValues[$0] ?? "missing" }, ["3","2","1","1","0"])
    XCTAssertEqual(ResultCharacterStatsPresentation.value(saved.characterStats), "2/1/1/0")
  }

  @MainActor func testInMemoryEntityKeepsTrimmedStatsAndRawTerminalReplayTogether() throws {
    var input = TypingSession(configuration: .words(1), prompt: "ab")
    input.insertBatch("ab ", at: start)
    let saved = try result(input)
    let container = try ModelContainer(for: TestResultRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    container.mainContext.insert(TestResultRecord(result: saved)); try container.mainContext.save()
    let fetched = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).first?.portableResult)
    XCTAssertEqual(fetched, saved)
    XCTAssertEqual(try counts(fetched), [2,2,0,0,0])
    XCTAssertEqual(fetched.replayEvents.last?.inputField?.units, [97,98,32])
  }
}
