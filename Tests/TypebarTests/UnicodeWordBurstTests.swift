import XCTest
@testable import Typebar

final class UnicodeWordBurstTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 100)

  func testCommittedUnicodeWordsUseUTF16UnitsWithoutChangingVisibleInput() {
    // Self-authored fixtures; literal expectations use a two-second interval.
    for (word, expected) in [("🦊", 18), ("👩‍💻", 36), ("🇫🇷", 30), ("e\u{301}", 18)] {
      var session = TypingSession(configuration: .words(2), prompt: "\(word) bay")
      session.insert(word, at: start)
      session.insert(" ", at: start.addingTimeInterval(2))
      XCTAssertEqual(session.typed, "\(word) ")
      XCTAssertEqual(session.burstWpm, expected, word)
      XCTAssertEqual(session.recentWordBursts, [expected], word)
      XCTAssertEqual(session.wordBurstHistory, [expected], word)
      XCTAssertEqual(session.completedWordCount, 1)
      XCTAssertEqual(session.outcome, .active)
    }
  }

  func testActiveUnicodeWordIncludesOneVirtualSubmitUnit() {
    var session = TypingSession(configuration: .words(2), prompt: "🦊a bay")
    session.insert("🦊", at: start)
    session.insert("a", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.burstWpm, 48)
    XCTAssertEqual(session.wordBurstHistory, [48])
    XCTAssertEqual(session.recentWordBursts, [])
    XCTAssertEqual(session.typed.count, 2)
  }

  func testNoSpaceCommitAndHistoryKeepGraphemeBoundariesButCountUTF16() {
    var session = TypingSession(
      configuration: TestConfiguration.words(2).with(modifiers: [.noSpaces]),
      prompt: "🦊abay", noSpaceWordEndIndices: [2, 5], noSpaceTargetWords: ["🦊a", "bay"])
    session.insert("🦊", at: start)
    session.insert("a", at: start.addingTimeInterval(2))
    XCTAssertEqual(session.completedWordCount, 1)
    XCTAssertEqual(session.burstWpm, 24)
    XCTAssertEqual(session.recentWordBursts, [24])
    XCTAssertEqual(session.wordBurstHistory, [24])
    session.insert("b", at: start.addingTimeInterval(3))
    session.insert("a", at: start.addingTimeInterval(4))
    XCTAssertEqual(session.burstWpm, 36)
    session.insert("y", at: start.addingTimeInterval(5))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.wordBurstHistory, [24, 24])
  }

  func testZenNewlineCommitUsesTheSameUnitsAsHistory() {
    var session = TypingSession(
      configuration: .init(mode: .zen, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()),
      prompt: "")
    session.insert("🦊", at: start)
    session.insert("a", at: start.addingTimeInterval(1))
    session.insert("\n", at: start.addingTimeInterval(2))
    XCTAssertEqual(session.burstWpm, 24)
    XCTAssertEqual(session.recentWordBursts, [24])
    XCTAssertEqual(session.wordBurstHistory, [24])
    XCTAssertEqual(session.outcome, .active)
  }

  func testFlexibleMinimumUsesUTF16TargetLengthForSpacedAndNoSpaceWords() {
    for noSpaces in [false, true] {
      for mode in [MinimumWordBurstMode.fixed, .flex] {
        let configuration = TestConfiguration.words(
          2, rules: .init(minimumWordBurstWpm: 60, minimumWordBurstMode: mode))
          .with(modifiers: noSpaces ? [.noSpaces] : [])
        var session = TypingSession(
          configuration: configuration, prompt: noSpaces ? "👩‍💻🦊bay" : "👩‍💻🦊 bay",
          noSpaceWordEndIndices: noSpaces ? [2, 5] : [])
        session.insert("👩‍💻", at: start)
        session.insert("🦊", at: start.addingTimeInterval(noSpaces ? 2 : 1))
        if !noSpaces { session.insert(" ", at: start.addingTimeInterval(2)) }
        // Seven target units: floor(60 × 1.03^-8) = 47; burst is 48.
        XCTAssertEqual(session.burstWpm, 48)
        XCTAssertEqual(session.outcome, mode == .flex ? .active : .failed)
      }
    }
  }

  func testZenFlexibleMinimumIncludesTheEnteredSubmitUnit() {
    var session = TypingSession(
      configuration: .init(
        mode: .zen, duration: nil, wordLimit: nil, difficulty: .normal,
        rules: .init(minimumWordBurstWpm: 60, minimumWordBurstMode: .flex)), prompt: "")
    session.insert("👩‍💻", at: start)
    session.insert("🦊", at: start.addingTimeInterval(1))
    session.insert(" ", at: start.addingTimeInterval(2))
    XCTAssertEqual(session.burstWpm, 48)
    XCTAssertEqual(session.outcome, .active)
  }

  func testReplayChartUsesUTF16AndActualSubsecondWindowDuration() {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "🦊"),
      .init(offset: 0.25, kind: .insert, text: "a"),
      .init(offset: 0.5, kind: .insert, text: " "),
    ]
    let points = ResultPerformanceTrace.points(prompt: "🦊a bay", events: events, duration: 0.5)
    XCTAssertEqual(points.map(\.burstWpm), [96])
    let point = ResultPerformanceTrace.point(prompt: "🦊a bay", events: events, elapsed: 0.5)
    XCTAssertEqual(point.burstWpm, 96)
    // Whole-test WPM/Raw still have their existing independent accounting.
    XCTAssertEqual(point.wpm, 36)
    XCTAssertEqual(point.rawWpm, 36)
  }

  func testReplayChartCountsNewlineInItsTimeWindowWithoutWordSubmitCredit() {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "🦊"),
      .init(offset: 1, kind: .insert, text: "a"),
      .init(offset: 2, kind: .insert, text: "\n"),
      .init(offset: 3, kind: .insert, text: "b"),
      .init(offset: 3.5, kind: .insert, text: "y"),
    ]
    XCTAssertEqual(ResultPerformanceTrace.point(prompt: "🦊a\nby", events: events, elapsed: 2).burstWpm, 12)
    XCTAssertEqual(ResultPerformanceTrace.point(prompt: "🦊a\nby", events: events, elapsed: 3.5).burstWpm, 24)
  }

  func testReplayChartKeepsUnrepresentableImportedBurstNeutral() {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "a"),
      .init(offset: Double.leastNormalMagnitude, kind: .insert, text: "b"),
    ]
    XCTAssertEqual(ResultPerformanceTrace.point(
      prompt: "ab", events: events, elapsed: Double.leastNormalMagnitude).burstWpm, 0)
  }

  func testDeleteAndRetypeKeepReplayIndicesAndWordTimingAligned() throws {
    var session = TypingSession(configuration: .words(2), prompt: "🦊a bay")
    session.insert("🦊", at: start)
    session.insert("x", at: start.addingTimeInterval(1))
    session.deleteBackward(at: start.addingTimeInterval(1.25))
    session.insert("a", at: start.addingTimeInterval(1.5))
    session.insert(" ", at: start.addingTimeInterval(2))
    XCTAssertEqual(session.typed, "🦊a ")
    XCTAssertEqual(session.burstWpm, 24)
    XCTAssertEqual(session.wordBurstHistory, [24])
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "🦊"),
      .init(offset: 1, kind: .insert, text: "x"),
      .init(offset: 1.25, kind: .delete, text: ""),
      .init(offset: 1.5, kind: .insert, text: "a"),
      .init(offset: 2, kind: .insert, text: " "),
    ]
    let decoded = try JSONDecoder().decode([TypingReplayEvent].self, from: JSONEncoder().encode(events))
    XCTAssertEqual(decoded, events)
    let point = ResultPerformanceTrace.point(prompt: "🦊a bay", events: decoded, elapsed: 2)
    XCTAssertEqual(point.burstWpm, 24)
    XCTAssertEqual(point.errorCount, 0)
  }

  func testASCIIAndUnmeasurableIntervalsAndTerminalCompletionStayUnchanged() {
    var ascii = TypingSession(configuration: .words(2), prompt: "amber bay")
    ascii.insert("a", at: start)
    ascii.insert("mber ", at: start.addingTimeInterval(2))
    XCTAssertEqual(ascii.burstWpm, 36)
    XCTAssertEqual(ascii.wordBurstHistory, [36])
    var instant = TypingSession(configuration: .words(2), prompt: "🦊a bay")
    instant.insert("🦊a ", at: start)
    XCTAssertEqual(instant.burstWpm, 0)
    XCTAssertEqual(instant.wordBurstHistory, [nil])
    var terminal = TypingSession(
      configuration: TestConfiguration.words(1, rules: .init(minimumWordBurstWpm: 100)),
      prompt: "🦊a")
    terminal.insert("🦊", at: start)
    terminal.insert("a", at: start.addingTimeInterval(10))
    XCTAssertEqual(terminal.outcome, .completed)
    XCTAssertEqual(terminal.wordBurstHistory, [5])
  }
}
