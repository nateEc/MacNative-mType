import XCTest
@testable import Typebar

final class ReplayScoringCombinationTests: XCTestCase {
  private struct Event: Decodable {
    let time: Double; let field: Int; let value, payload: [UInt16]
    let correct: Bool; let stopped, commit, last, deletion: Bool?
  }
  private struct Fixture: Decodable {
    let targets: [[UInt16]]; let noSpace, korean, zen: Bool
    let duration: Double; let history, rawHistory: [Double]; let consistency: Double; let tape: [Event]
    var words: [String] { targets.map { String(decoding: $0, as: UTF16.self) } }
    var configuration: TestConfiguration {
      if zen { return .init(mode: .zen, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()) }
      return .words(targets.count).with(modifiers: noSpace ? [.noSpaces] : [])
    }
    var events: [TypingReplayEvent] {
      tape.map { event in
        .init(offset: event.time, kind: event.deletion == true ? .delete : .insert, units: event.payload,
          commitsWord: event.commit, inputStopped: event.stopped,
          inputField: .init(index: event.field, units: event.value),
          inputCorrectness: event.deletion == true ? nil : event.payload.map { _ in event.correct },
          inputPosition: event.deletion == true ? nil : .init(charIndex: max(0, event.value.count - event.payload.count), lastWord: event.last == true))
      }
    }
  }
  private struct Output: Decodable { let fixtures, chartFixtures: [Fixture] }

  private func sourceOutput() throws -> Output {
    let env = ProcessInfo.processInfo.environment
    guard let reference = env["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"], env["TYPEBAR_REPLAY_HANGUL_ARCHIVE"] != nil else {
      throw XCTSkip("Requires pinned reference and verified QA-only Hangul archive")
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-replay-click.mjs").path, reference, "--combinations"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    return try JSONDecoder().decode(Output.self, from: data)
  }

  private func fixtures() throws -> [Fixture] { try sourceOutput().fixtures }

  func testExplicitInputFlagsKoreanAndNoSpaceAgainstCompletePinnedStatistics() throws {
    let all = try fixtures(); XCTAssertEqual(all.count, 583)
    for (index, fixture) in all.enumerated() {
      let configuration = fixture.configuration, events = fixture.events
      let directory = fixture.zen ? nil : ResultTargetWordDirectory(words: fixture.words, noSpace: fixture.noSpace)
      let prompt = fixture.zen ? "" : fixture.words.joined()
      let basis: ResultScoringUnitBasis? = fixture.korean ? .koreanJamo : nil
      let history = try XCTUnwrap(ResultPerformanceTrace.replayWPMHistory(prompt: prompt, events: events,
        duration: fixture.duration, configuration: configuration, targetWordDirectory: directory, sourceScoringBasis: basis))
      let actual = fixture.history.indices.map { history.wpm(at: Double($0 + 1)) }
      XCTAssertEqual(actual, fixture.history, "combination \(index)")
      let consistency = try XCTUnwrap(ResultPerformanceTrace.wpmConsistency(prompt: prompt, events: events,
        duration: fixture.duration, configuration: configuration, targetWordDirectory: directory, sourceScoringBasis: basis))
      XCTAssertEqual(consistency, fixture.consistency, accuracy: 0.0000001, "combination \(index)")
    }
  }

  func testCurrentNoSpaceKoreanCaptureAndRestoreKeepTheSavedScoringBasis() throws {
    let source = try XCTUnwrap(fixtures().first { $0.words == ["괅","x"] })
    let config = TestConfiguration.words(2, language: .korean).with(modifiers: [.noSpaces])
    var session = TypingSession(configuration: config, prompt: "괅x", noSpaceTargetWords: ["괅","x"])
    let start = Date(timeIntervalSinceReferenceDate: 918_700_000)
    session.insert("괅", at: start); session.insert("x", at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.outcome, .completed)
    XCTAssertEqual(result.characterStats.sourceUnitBasis, .koreanJamo)
    let restored = try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(result))
    XCTAssertEqual(restored, result)
    let portable = try XCTUnwrap(TestResultRecord(result: result).portableResult)
    XCTAssertEqual(portable, result)
    for value in [result, restored, portable] {
      let history = try XCTUnwrap(ResultPerformanceTrace.replayWPMHistory(prompt: value.prompt, events: value.replayEvents,
        duration: value.chartDuration, configuration: value.configuration, targetWordDirectory: value.targetWordDirectory,
        sourceScoringBasis: value.characterStats.sourceUnitBasis))
      XCTAssertEqual([history.wpm(at: 1), history.wpm(at: 2)], Array(source.history.prefix(2)))
      let points = ResultPerformanceTrace.points(prompt: value.prompt, events: value.replayEvents,
        duration: value.chartDuration, configuration: value.configuration, targetWordDirectory: value.targetWordDirectory,
        sourceScoringBasis: value.characterStats.sourceUnitBasis)
      XCTAssertEqual(points.map { Double($0.wpm) }, Array(source.history.prefix(2)))
      XCTAssertEqual(points.map { Double($0.rawWpm) }, Array(source.rawHistory.prefix(2)))
      let account = try XCTUnwrap(AccountResultChartInput(value).calculate())
      XCTAssertEqual(account.samples.map(\.wpm), Array(source.history.prefix(2)))
    }
  }

  func testCapturedTargetChartsMatchCompletePinnedWPMAndRawHistories() throws {
    let output = try sourceOutput()
    XCTAssertEqual(output.fixtures.count, 583); XCTAssertEqual(output.chartFixtures.count, 16)
    let all = output.fixtures + output.chartFixtures
    for (index, fixture) in all.enumerated() {
      let directory = fixture.zen ? nil : ResultTargetWordDirectory(words: fixture.words, noSpace: fixture.noSpace)
      let points = ResultPerformanceTrace.points(prompt: fixture.zen ? "" : fixture.words.joined(),
        events: fixture.events, duration: fixture.duration, configuration: fixture.configuration,
        targetWordDirectory: directory, sourceScoringBasis: fixture.korean ? .koreanJamo : nil)
      XCTAssertEqual(points.map { Double($0.wpm) }, fixture.history, "chart WPM combination \(index)")
      XCTAssertEqual(points.map { Double($0.rawWpm) }, fixture.rawHistory, "chart raw combination \(index)")
      let history = try XCTUnwrap(ResultPerformanceTrace.replayWPMHistory(prompt: fixture.zen ? "" : fixture.words.joined(),
        events: fixture.events, duration: fixture.duration, configuration: fixture.configuration,
        targetWordDirectory: directory, sourceScoringBasis: fixture.korean ? .koreanJamo : nil))
      XCTAssertEqual(fixture.history.indices.map { history.wpm(at: Double($0 + 1)) }, fixture.history,
        "replay WPM combination \(index)")
      let consistency = try XCTUnwrap(ResultPerformanceTrace.wpmConsistency(prompt: fixture.zen ? "" : fixture.words.joined(),
        events: fixture.events, duration: fixture.duration, configuration: fixture.configuration,
        targetWordDirectory: directory, sourceScoringBasis: fixture.korean ? .koreanJamo : nil))
      XCTAssertEqual(consistency, fixture.consistency, accuracy: 0.0000001, "WPM consistency combination \(index)")
    }
  }

  func testMissingChartContextRetainsCompatibilityAndDoesNotRewriteSavedScores() throws {
    let event = TypingReplayEvent(offset: 0, kind: .insert, text: " ", commitsWord: true,
      inputField: .init(index: 0, value: "ab "), inputCorrectness: [false],
      inputPosition: .init(charIndex: 2, lastWord: true))
    let directory = ResultTargetWordDirectory(words: ["ab"], noSpace: false)
    for (config, targets) in [(Optional(TestConfiguration.words(1)), nil), (nil, Optional(directory))] {
      let points = ResultPerformanceTrace.points(prompt: "ab", events: [event], duration: 2.5,
        configuration: config, targetWordDirectory: targets)
      XCTAssertEqual(points.map(\.wpm), [0, 0, 0])
      XCTAssertEqual(points.map(\.rawWpm), [36, 18, 14])
    }
    let start = Date(timeIntervalSinceReferenceDate: 918_900_000)
    let saved = CompletedTestResult(id: UUID(), configuration: .words(1), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(2.5), typedCharacterCount: 3,
      correctCharacterCount: 2, errorCount: 1, wpm: 91, rawWpm: 92, accuracy: 93,
      prompt: "ab", replayEvents: [event], targetWordDirectory: directory)
    let before = try JSONEncoder().encode(saved)
    let data = try XCTUnwrap(AccountResultChartInput(saved).calculate())
    XCTAssertEqual(data.samples.map(\.wpm), [24, 12, 10])
    XCTAssertEqual(saved.wpm, 91); XCTAssertEqual(saved.rawWpm, 92); XCTAssertEqual(saved.accuracy, 93)
    XCTAssertEqual(saved.replayEvents, [event])
    XCTAssertEqual(try JSONDecoder().decode(CompletedTestResult.self, from: before), saved)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: saved).portableResult), saved)
  }

  func testExplicitStoppedCommitUpdatesClassificationWithoutChangingAcceptedHistory() throws {
    let source = try XCTUnwrap(fixtures().first {
      !$0.noSpace && $0.words == ["ab"] && $0.tape[0].value == Array("ab ".utf16)
        && $0.tape[0].commit == true && $0.tape[0].stopped == true && $0.tape[0].last == true && !$0.tape[0].correct
    })
    let event = try XCTUnwrap(source.events.first)
    XCTAssertEqual(RecordedInputFieldStats.classificationInput(for: event), Array("ab".utf16))
    var stats = RecordedInputFieldStats(); stats.record(event)
    let counts = stats.counts(targets: .init("ab", buildsASCIICatalog: true), creditsActivePrefix: false)
    XCTAssertEqual(counts.unitStats.correctWord, Int(source.history[0] / 12))
    XCTAssertEqual(counts.retainedInputUnits, 2)
    XCTAssertEqual(stats.history(0), Array("ab ".utf16))
    XCTAssertEqual(event.inputField?.units, Array("ab ".utf16))
    let legacy = TypingReplayEvent(offset: 0, kind: .insert, units: [32],
      inputField: .init(index: 0, units: Array("ab ".utf16)), inputCorrectness: [false],
      inputPosition: .init(charIndex: 2, lastWord: true))
    XCTAssertNil(legacy.commitsWord)
    XCTAssertEqual(RecordedInputFieldStats.classificationInput(for: legacy), Array("ab".utf16))
    XCTAssertEqual(RecordedInputFieldStats.classificationInput(for: legacy, sourceEventFlags: true), Array("ab ".utf16))
  }
}
