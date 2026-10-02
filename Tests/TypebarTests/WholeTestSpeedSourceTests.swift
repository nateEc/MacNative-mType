import XCTest
@testable import Typebar

final class WholeTestSpeedSourceTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 100)

  func testCompletedUnicodeSpeedUsesUTF16WithoutChangingVisibleCounts() throws {
    for (word, speed) in [("🦊a", 18), ("👩‍💻a", 36), ("🇫🇷a", 30), ("e\u{301}a", 18)] {
      var session = TypingSession(configuration: .words(1), prompt: word)
      session.insert(String(word.first!), at: start)
      session.insert("a", at: start.addingTimeInterval(2))
      let result = try XCTUnwrap(session.result())
      XCTAssertEqual(result.outcome, .completed)
      XCTAssertEqual(result.wpm, speed, word)
      XCTAssertEqual(result.rawWpm, speed, word)
      XCTAssertEqual(result.preciseWpm, Double(speed), word)
      XCTAssertEqual(result.preciseRawWpm, Double(speed), word)
      XCTAssertEqual(result.typedCharacterCount, 2)
      XCTAssertEqual(result.correctCharacterCount, 2)
      XCTAssertEqual(result.characterStats.matched, 2)
      XCTAssertEqual(result.accuracy, 100)
    }
  }

  func testCommittedUnicodeWordAndActivePrefixHaveIndependentWordCredit() throws {
    var session = TypingSession(configuration: .timed(seconds: 2), prompt: "🦊a bay")
    session.insert("🦊a b", at: start)
    XCTAssertEqual(session.wpm(at: start.addingTimeInterval(1)), 60)
    session.tick(at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.wpm, 30)
    XCTAssertEqual(result.rawWpm, 30)
    XCTAssertEqual(result.correctCharacterCount, 4)
  }

  func testIncorrectCommittedUnicodeWordEarnsNoPartialCreditButKeepsRawUnits() throws {
    var session = TypingSession(configuration: .words(2), prompt: "🦊a bay")
    session.insert("🦊x ", at: start)
    session.insert("bay", at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.wpm, 18)
    XCTAssertEqual(result.rawWpm, 42)
    XCTAssertEqual(result.correctCharacterCount, 3)
    XCTAssertEqual(result.typedCharacterCount, 6)
  }

  func testNoSpaceSpeedRetainsHiddenWordCreditWithoutVirtualSeparators() throws {
    var session = TypingSession(configuration: TestConfiguration.words(2).with(modifiers: [.noSpaces]),
      prompt: "🦊abay", noSpaceWordEndIndices: [2, 5], noSpaceTargetWords: ["🦊a", "bay"])
    session.insert("🦊a", at: start)
    session.insert("bay", at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.wpm, 36)
    XCTAssertEqual(result.rawWpm, 36)
    XCTAssertEqual(result.typedCharacterCount, 5)
    XCTAssertEqual(result.correctCharacterCount, 5)
  }

  func testZenRawAndSpeedUseEnteredUTF16Units() throws {
    var session = TypingSession(configuration: .init(mode: .zen, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init()), prompt: "")
    session.insert("🦊a", at: start)
    session.finishZen(at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.wpm, 18)
    XCTAssertEqual(result.rawWpm, 18)
    XCTAssertEqual(result.typedCharacterCount, 2)
  }

  func testCodeWrongCommittedLineDoesNotReceiveMatchingCharacterCredit() throws {
    var session = TypingSession(configuration: .words(2, language: .codeSwift), prompt: "ab\nby")
    session.insert("ax\n", at: start)
    session.insert("by", at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.wpm, 12)
    XCTAssertEqual(result.rawWpm, 30)
    XCTAssertEqual(result.characterStats.incorrect, 1)
  }

  func testReplayWrongActiveWordLosesAllPrefixCreditAndCorrectionRestoresIt() {
    let points = ResultPerformanceTrace.points(prompt: "amber", events: [
      .init(offset: 0, kind: .insert, text: "am"),
      .init(offset: 2, kind: .insert, text: "x"),
      .init(offset: 3, kind: .delete, text: ""),
      .init(offset: 4, kind: .insert, text: "b"),
    ], duration: 4)
    XCTAssertEqual(points.map(\.wpm), [24, 0, 8, 9])
    XCTAssertEqual(points.map(\.rawWpm), [24, 18, 8, 9])
  }

  func testReplayWrongCommittedWordDoesNotShiftCreditForTheNextWord() {
    let points = ResultPerformanceTrace.points(prompt: "amber bay", events: [
      .init(offset: 0, kind: .insert, text: "axber "),
      .init(offset: 2, kind: .insert, text: "ba"),
    ], duration: 2)
    XCTAssertEqual(points.map(\.wpm), [0, 12])
    XCTAssertEqual(points.map(\.rawWpm), [72, 48])
  }

  func testReplayUnicodeDeleteRemovesOneNativeClusterButItsFullSpeedWeight() {
    let points = ResultPerformanceTrace.points(prompt: "🦊a bay", events: [
      .init(offset: 0, kind: .insert, text: "🦊a"),
      .init(offset: 2, kind: .delete, text: ""),
      .init(offset: 3, kind: .delete, text: ""),
      .init(offset: 4, kind: .insert, text: "🦊a "),
    ], duration: 4)
    XCTAssertEqual(points.map(\.wpm), [36, 12, 0, 12])
    XCTAssertEqual(points.map(\.rawWpm), [36, 12, 0, 12])
  }

  func testReplaySubsecondUsesActualDurationAndMatchesLiveAndTerminalSpeed() throws {
    var session = TypingSession(configuration: .words(1), prompt: "🦊a")
    session.insert("🦊", at: start)
    session.insert("a", at: start.addingTimeInterval(0.5))
    let result = try XCTUnwrap(session.result())
    let point = ResultPerformanceTrace.point(prompt: result.prompt, events: result.replayEvents,
      elapsed: result.elapsedDuration, configuration: result.configuration)
    XCTAssertEqual(result.wpm, 72)
    XCTAssertEqual(result.rawWpm, 72)
    XCTAssertEqual(point.wpm, result.wpm)
    XCTAssertEqual(point.rawWpm, result.rawWpm)
    XCTAssertEqual(ResultPerformanceTrace.points(prompt: result.prompt, events: result.replayEvents,
      duration: result.elapsedDuration, configuration: result.configuration).last, point)
  }

  func testReplayCodeUsesWordCreditAndZenNeedsNoTarget() {
    let code = ResultPerformanceTrace.point(prompt: "ab\nby", events: [
      .init(offset: 0, kind: .insert, text: "ax\nby"),
    ], elapsed: 2, configuration: .words(2, language: .codeSwift))
    XCTAssertEqual(code.wpm, 12)
    XCTAssertEqual(code.rawWpm, 30)
    let zen = ResultPerformanceTrace.point(prompt: "", events: [
      .init(offset: 0, kind: .insert, text: "🦊a"),
    ], elapsed: 2, configuration: .init(mode: .zen, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init()))
    XCTAssertEqual(zen.wpm, 18)
    XCTAssertEqual(zen.rawWpm, 18)
  }

  func testStoredOldScoresAreNotRecomputedFromUnicodeReplay() throws {
    let legacy = CompletedTestResult(id: UUID(), configuration: .words(1), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(2), typedCharacterCount: 2,
      correctCharacterCount: 2, errorCount: 0, wpm: 12, rawWpm: 12, accuracy: 100,
      prompt: "🦊a", replayEvents: [.init(offset: 0, kind: .insert, text: "🦊a")])
    let decoded = try JSONDecoder().decode(CompletedTestResult.self,
      from: JSONEncoder().encode(legacy))
    XCTAssertEqual(decoded, legacy)
    XCTAssertEqual(ResultMetric(record: TestResultRecord(result: decoded)).wpm, 12)
    XCTAssertEqual(RemoteResultSubmission(result: decoded).wpm, 12)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: decoded).portableResult), legacy)
  }

  func testNormalizedCompletedReplayKeepsTheSameWordCreditAsItsSession() throws {
    var session = TypingSession(configuration: .words(1), prompt: "’a")
    session.insert("'", at: start)
    session.insert("a", at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    // New logs retain source-normalized data; old raw-key tapes stay readable.
    XCTAssertEqual(result.replayEvents.first?.text, "’")
    XCTAssertEqual(result.replayEvents.first?.inputCorrectness, [true])
    XCTAssertEqual(result.replayEvents.first?.inputField?.value, "’")
    XCTAssertEqual(result.wpm, 12)
    let point = ResultPerformanceTrace.point(prompt: result.prompt, events: result.replayEvents,
      elapsed: result.elapsedDuration, configuration: result.configuration)
    XCTAssertEqual(point.wpm, result.wpm)
    XCTAssertEqual(point.errorCount, 0)
    XCTAssertEqual(ResultPerformanceTrace.points(prompt: result.prompt, events: result.replayEvents,
      duration: result.elapsedDuration, configuration: result.configuration).last, point)
    let old: [TypingReplayEvent] = [.init(offset: 0, kind: .insert, text: "'"),
      .init(offset: 2, kind: .insert, text: "a")]
    XCTAssertEqual(TypingReplay.typedText(events: old, through: 2), "'a")
    let oldPoint = ResultPerformanceTrace.point(prompt: result.prompt, events: old,
      elapsed: result.elapsedDuration, configuration: result.configuration)
    XCTAssertEqual(oldPoint.wpm, result.wpm)
    XCTAssertEqual(oldPoint.errorCount, 0)
  }

  func testReplayWordCreditUsesLanguageEquivalenceAndNormalizedCommitSpaces() {
    let point = ResultPerformanceTrace.point(prompt: "ё bay", events: [
      .init(offset: 0, kind: .insert, text: "e\u{3000}b"),
    ], elapsed: 1, configuration: .words(2, language: .russian))
    XCTAssertEqual(point.wpm, 36)
    XCTAssertEqual(point.rawWpm, 36)
    XCTAssertEqual(point.errorCount, 0)
  }

  func testZenReplayIsAvailableWithoutAnArtificialTarget() {
    let configuration = TestConfiguration(mode: .zen, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init())
    let events: [TypingReplayEvent] = [.init(offset: 0, kind: .insert, text: "🦊a")]
    let points = ResultPerformanceTrace.points(prompt: "", events: events, duration: 2,
      configuration: configuration)
    XCTAssertEqual(points.map(\.wpm), [36, 18])
    XCTAssertEqual(points.map(\.rawWpm), [36, 18])
    XCTAssertTrue(ResultPerformanceChartAvailability.isAvailable(prompt: "", events: events,
      duration: 2, configuration: configuration))
    XCTAssertFalse(ResultPerformanceChartAvailability.isAvailable(prompt: "", events: events,
      duration: 2, configuration: .words(1)))
  }

  func testReplaySpeedRejectsInvalidOrUnrepresentableDurationInsteadOfCrashing() {
    let events: [TypingReplayEvent] = [.init(offset: 0, kind: .insert, text: "a")]
    for elapsed in [0, -1, .nan, .infinity, Double.leastNormalMagnitude] {
      let point = ResultPerformanceTrace.point(prompt: "a", events: events, elapsed: elapsed)
      XCTAssertEqual(point.wpm, 0)
      XCTAssertEqual(point.rawWpm, 0)
    }
  }

  func testEarlyCommitAndForcedInputEvidenceDoNotReplaceTheRetainedTextScore() {
    let early = ResultPerformanceTrace.point(prompt: "amber bay", events: [
      .init(offset: 0, kind: .insert, text: "am b"),
    ], elapsed: 2)
    XCTAssertEqual(early.wpm, 6)
    XCTAssertEqual(early.rawWpm, 24)
    let forced = ResultPerformanceTrace.point(prompt: "ab", events: [
      .init(offset: 0, kind: .insert, text: "ab", forceError: true),
    ], elapsed: 1)
    XCTAssertEqual(forced.wpm, 24, "Retained DOM text and input-time mistakes are separate metrics")
    XCTAssertEqual(forced.errorCount, 2)
  }

  func testNewUnicodeScoreSurvivesArchiveCSVPersonalBestAndChallengeConsumption() throws {
    var session = TypingSession(configuration: .words(1), prompt: "🦊a")
    session.insert("🦊", at: start)
    session.insert("a", at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    let decoded = try JSONDecoder().decode(CompletedTestResult.self,
      from: JSONEncoder().encode(result))
    let record = TestResultRecord(result: decoded)
    XCTAssertEqual(try XCTUnwrap(record.portableResult), result)
    XCTAssertEqual(ResultMetric(record: record).wpm, 18)
    XCTAssertEqual(ResultMetric(record: record).rawWpm, 18)
    XCTAssertEqual(RemoteResultSubmission(result: decoded).wpm, 18)
    XCTAssertEqual(RemoteResultSubmission(result: decoded).rawWpm, 18)
    XCTAssertEqual(LocalPersonalBestTablePolicy.rows(results: [decoded]).first?.wpm, 18)
    let row = ResultCSVExport.csvString(for: [decoded]).components(separatedBy: "\r\n")[1]
    let fields = Dictionary(uniqueKeysWithValues: zip(ResultCSVExport.columns, row.components(separatedBy: ",")))
    XCTAssertEqual(fields["wpm"], "18")
    XCTAssertEqual(fields["raw_wpm"], "18")
    XCTAssertEqual(fields["typed_characters"], "2")
    let challenge = TypebarChallenge(id: "native-speed-test", title: "速度测试", description: "自有规则夹具",
      preset: .init(configuration: result.configuration, quoteID: nil, customText: nil),
      requirements: .init(wpm: .minimum(15)))
    XCTAssertTrue(ChallengeEvaluator.evaluate(decoded, challenge: challenge).passed)
  }

  func testMinimumSpeedUsesTheCorrectUnicodeUnitsAfterFourCommittedWords() {
    var session = TypingSession(configuration: .words(5, rules: .init(minimumWpm: 80)),
      prompt: "🦊a 🦊a 🦊a 🦊a bay")
    session.insert("🦊a 🦊a 🦊a ", at: start)
    session.insert("🦊a ", at: start.addingTimeInterval(2))
    XCTAssertEqual(session.completedWordCount, 4)
    XCTAssertEqual(session.wpm(at: start.addingTimeInterval(2)), 96)
    XCTAssertEqual(session.outcome, .active)
    XCTAssertNil(session.failureReason)
  }
}
