import AppKit
import XCTest
@testable import Typebar

final class AccuracyInputUnitSourceTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 100)

  func testCorrectEmojiAndWrongASCIIHaveDifferentEventWeights() throws {
    var session = TypingSession(configuration: .timed(seconds: 1), prompt: "🦊a")
    session.insert("🦊", at: start)
    session.insert("x", at: start.addingTimeInterval(0.5))
    session.tick(at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.accuracy, 67)
    XCTAssertEqual(result.preciseAccuracy, 66.67)
    XCTAssertEqual(result.typedCharacterCount, 2)
    XCTAssertEqual(result.errorCount, 1)
    XCTAssertEqual(result.rawWpm, 36)
  }

  func testDifferentEmojiCanShareOneCorrectSurrogateUnit() {
    var session = TypingSession(configuration: .words(2), prompt: "🦊a bay")
    session.insert("🦁", at: start)
    XCTAssertEqual(session.typed, "🦁")
    XCTAssertEqual(session.errors, 1)
    XCTAssertEqual(session.accuracy, 50)
    XCTAssertEqual(session.preciseAccuracy, 50)
  }

  func testDeletingAndCorrectingAnEmojiDoesNotEraseItsInputMistake() {
    var session = TypingSession(configuration: .words(2), prompt: "🦊a bay")
    session.insert("🦁", at: start)
    session.deleteBackward(at: start.addingTimeInterval(0.1))
    XCTAssertEqual(session.typed, "�", "One source backspace retains the high surrogate")
    session.deleteBackward(at: start.addingTimeInterval(0.15))
    session.insert("🦊", at: start.addingTimeInterval(0.2))
    XCTAssertEqual(session.preciseAccuracy, 75)
    session.insert("a", at: start.addingTimeInterval(0.3))
    XCTAssertEqual(session.accuracy, 80)
    XCTAssertEqual(session.typed, "🦊a")
    XCTAssertEqual(session.errors, 0)
  }

  func testWordLocalUTF16PositionDoesNotFollowTheVisibleGraphemeCursor() {
    var session = TypingSession(configuration: .words(2), prompt: "🦊a bay")
    session.insert("x", at: start)
    session.insert("a", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "xa")
    XCTAssertEqual(session.preciseAccuracy, 0,
      "Both units miss their source positions, despite the second visible glyph matching")
    XCTAssertEqual(session.errors, 2, "Both accepted glyphs occupy the surrogate slots, not the later a")
  }

  func testNFDAndZWJAndFlagWeightsAreNotVisibleCharacterCounts() {
    for (word, expected) in [("e\u{301}", 200.0 / 3), ("👩‍💻", 500.0 / 6), ("🇫🇷", 80.0)] {
      var session = TypingSession(configuration: .words(2), prompt: "\(word)ab bay")
      session.insert(word, at: start)
      session.insert("x", at: start.addingTimeInterval(1))
      XCTAssertEqual(session.preciseAccuracy, expected, accuracy: 0.000_001, word)
      XCTAssertEqual(session.typedCharacterCount, 2)
    }
  }

  func testNoSpaceHiddenBoundaryResetsTheUnitPosition() throws {
    var session = TypingSession(configuration: TestConfiguration.words(2).with(modifiers: [.noSpaces]),
      prompt: "🦊a🦊b", noSpaceWordEndIndices: [2, 4], noSpaceTargetWords: ["🦊a", "🦊b"])
    session.insert("🦊a", at: start)
    session.insert("🦁", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.preciseAccuracy, 80)
    session.insert("b", at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.preciseAccuracy, 83.33)
    XCTAssertEqual(result.typedCharacterCount, 4)
  }

  func testForcedErrorCountsEveryUnitButLeavesFinalTextDiagnosticsSeparate() throws {
    var session = TypingSession(configuration: .timed(seconds: 1), prompt: "🦊a")
    session.insert("🦊", forceError: true, at: start)
    session.insert("a", at: start.addingTimeInterval(0.5))
    session.tick(at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.accuracy, 33)
    XCTAssertEqual(result.preciseAccuracy, 33.33)
    XCTAssertEqual(result.typedCharacterCount, 2)
    XCTAssertEqual(result.errorCount, 1)
  }

  func testOppositeShiftRejectedUnicodeCountsButDoesNotAdvanceText() throws {
    var session = TypingSession(configuration: .words(2, rules: .init(oppositeShiftMode: .on)),
      prompt: "a🦊b bay")
    session.insert("a", at: start)
    session.insert("🦊", forceError: true, at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "a")
    XCTAssertEqual(session.preciseAccuracy, 100.0 / 3, accuracy: 0.000_001)
    session.insert("🦊", at: start.addingTimeInterval(2))
    XCTAssertEqual(session.preciseAccuracy, 60)
    session.bailOut(at: start.addingTimeInterval(3))
    let tape = try XCTUnwrap(session.result()).replayEvents
    XCTAssertEqual(tape.filter { !$0.isStoppedInsertion }.flatMap(\.inputUnits), Array("a🦊".utf16))
    XCTAssertEqual(tape.filter(\.isStoppedInsertion).map(\.textUTF16), [[55358], [56714]])
  }

  func testAutomaticCodeIndentationContributesItsOwnCorrectInputUnits() throws {
    var session = TypingSession(configuration: .words(2, language: .codeSwift), prompt: "🦊a\n\t\tb")
    session.insert("🦊x\n", at: start)
    XCTAssertEqual(session.typed, "🦊x\n\t\t")
    XCTAssertEqual(session.preciseAccuracy, 500.0 / 6, accuracy: 0.000_001)
    session.insert("b", at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.replayEvents.filter(\.automatic).map(\.text), ["\t", "\t"])
    XCTAssertEqual(result.preciseAccuracy, 85.71)
    XCTAssertEqual(result.accuracy, 86)
    XCTAssertEqual(result.errorCount, 1)
  }

  func testTerminalEmptyCompositionHasZeroAccuracyWithoutChangingIdleDisplay() throws {
    var session = TypingSession(configuration: .words(2), prompt: "amber bay")
    XCTAssertEqual(session.accuracy, 100)
    XCTAssertEqual(session.preciseAccuracy, 100)
    session.beginComposition(at: start)
    session.bailOut(at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.accuracy, 0)
    XCTAssertEqual(result.preciseAccuracy, 0)
    XCTAssertEqual(result.replayEvents, [])
  }

  func testOnlyTerminalPrecisionRoundsToHundredths() throws {
    var session = TypingSession(configuration: .timed(seconds: 2), prompt: "abc")
    session.insert("ax", at: start)
    XCTAssertEqual(session.preciseAccuracy, 50)
    session.insert("c", at: start.addingTimeInterval(1))
    session.tick(at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.accuracy, 67)
    XCTAssertEqual(result.preciseAccuracy, 66.67)
  }

  func testRejectedPreInputGuardsDoNotCreateAccuracyEvents() {
    var session = TypingSession(configuration: .words(1), prompt: "🦊a")
    session.insert(" \n", at: start)
    XCTAssertFalse(session.hasStarted)
    XCTAssertEqual(session.preciseAccuracy, 100)
    session.insert("🦊", at: start)
    XCTAssertEqual(session.preciseAccuracy, 100)
    var noSpace = TypingSession(configuration: TestConfiguration.words(2).with(modifiers: [.noSpaces]),
      prompt: "🦊abay", noSpaceWordEndIndices: [2, 5])
    noSpace.insert("🦊", at: start)
    noSpace.insert("\u{3000}", at: start.addingTimeInterval(1))
    XCTAssertEqual(noSpace.typed, "🦊")
    XCTAssertEqual(noSpace.preciseAccuracy, 100)
  }

  func testMinimumAccuracyUsesUnroundedUnitsRatherThanTerminalPrecision() throws {
    for (threshold, shouldFail) in [(66.66, false), (66.667, true)] {
      var session = TypingSession(configuration: .timed(seconds: 5,
        rules: .init(minimumAccuracy: threshold)), prompt: "🦊ab")
      session.insert("🦊x", at: start)
      XCTAssertEqual(session.preciseAccuracy, 200.0 / 3, accuracy: 0.000_001)
      session.enforceLivePracticeThresholds(at: start.addingTimeInterval(1))
      XCTAssertEqual(session.isFinished, shouldFail)
      if shouldFail {
        XCTAssertEqual(session.outcome, .failed)
        XCTAssertEqual(session.failureReason, .minimumAccuracy)
        XCTAssertEqual(try XCTUnwrap(session.result()).preciseAccuracy, 66.67)
      }
    }
  }

  @MainActor
  func testNativeCompositionOnlyCountsConfirmedInputUnits() throws {
    var session = TypingSession(configuration: .timed(seconds: 2), prompt: "🦊ab")
    let input = TypingInputView(frame: .zero)
    var now = start
    input.onCompositionStarted = { session.beginComposition(at: now) }
    input.onInsert = { text, forced in session.insertBatch(text, forceError: forced, at: now) }
    input.setMarkedText("🦊", selectedRange: .init(), replacementRange: .init())
    XCTAssertTrue(input.hasMarkedText())
    XCTAssertEqual(session.typed, "")
    XCTAssertEqual(session.preciseAccuracy, 100)
    now = start.addingTimeInterval(1)
    input.insertText("🦊", replacementRange: .init())
    XCTAssertFalse(input.hasMarkedText())
    XCTAssertEqual(session.typed, "🦊")
    now = start.addingTimeInterval(1.5)
    input.insertText("x", replacementRange: .init())
    XCTAssertEqual(session.preciseAccuracy, 200.0 / 3, accuracy: 0.000_001)
    session.tick(at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.preciseAccuracy, 66.67)
    XCTAssertEqual(result.replayEvents.map(\.textUTF16), [[55358], [56714], [120]])
  }

  func testNewAndLegacyAccuracySurviveArchivesWithPreciseLocalAndLegacyWireConsumers() throws {
    var session = TypingSession(configuration: .timed(seconds: 1), prompt: "🦊a")
    session.insert("🦊", at: start)
    session.insert("x", at: start.addingTimeInterval(0.5))
    session.tick(at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    let legacy = CompletedTestResult(id: UUID(), configuration: result.configuration, outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(1), typedCharacterCount: 2,
      correctCharacterCount: 0, errorCount: 1, wpm: 0, rawWpm: 24, accuracy: 50,
      prompt: "🦊a", replayEvents: result.replayEvents)
    for (original, precise, integer) in [(result, 66.67, 67), (legacy, 50.0, 50)] {
      let decoded = try JSONDecoder().decode(CompletedTestResult.self,
        from: JSONEncoder().encode(original))
      XCTAssertEqual(decoded, original)
      XCTAssertEqual(decoded.preciseAccuracy, precise)
      let record = TestResultRecord(result: decoded)
      XCTAssertEqual(try XCTUnwrap(record.portableResult), original)
      XCTAssertEqual(ResultMetric(record: record).accuracy, precise)
      XCTAssertEqual(RemoteResultSubmission(result: decoded).accuracy, integer)
      let challenge = TypebarChallenge(id: "native-accuracy-boundary", title: "准确率边界",
        description: "自有精度夹具",
        preset: .init(configuration: decoded.configuration, quoteID: nil, customText: nil),
        requirements: .init(accuracy: .minimum(integer)))
      XCTAssertEqual(ChallengeEvaluator.evaluate(decoded, challenge: challenge).passed,
        precise >= Double(integer), "Challenges use precise accuracy, not rounded display data")
      let row = ResultCSVExport.csvString(for: [decoded]).components(separatedBy: "\r\n")[1]
      let fields = Dictionary(uniqueKeysWithValues: zip(ResultCSVExport.columns,
        row.components(separatedBy: ",")))
      XCTAssertEqual(fields["accuracy_percent"], precise == 66.67 ? "66.67" : "50",
        "CSV preserves precision while legacy protocol and aggregate integers remain unchanged")
    }
  }

  func testZenRejectedOppositeShiftInputStillHasNoTargetErrors() throws {
    var session = TypingSession(configuration: .init(mode: .zen, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(oppositeShiftMode: .on)), prompt: "")
    session.insert("🦁", forceError: true, at: start)
    XCTAssertEqual(session.typed, "")
    XCTAssertEqual(session.preciseAccuracy, 100)
    session.insert("🦊", at: start.addingTimeInterval(1))
    session.finishZen(at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.preciseAccuracy, 100)
    XCTAssertEqual(result.replayEvents.filter { !$0.isStoppedInsertion }.flatMap(\.inputUnits), Array("🦊".utf16))
    XCTAssertEqual(result.replayEvents.filter(\.isStoppedInsertion).flatMap(\.inputUnits), Array("🦁".utf16))
  }

  func testStoppedEntirelyWrongUnicodeUnitsCountWithoutAdvancingPosition() {
    var session = TypingSession(configuration: .words(2, rules: .init(stopOnErrorMode: .letter)),
      prompt: "a🦊b bay")
    session.insert("a", at: start)
    session.insert("e\u{301}", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "a")
    XCTAssertEqual(session.preciseAccuracy, 100.0 / 3, accuracy: 0.000_001)
    session.insert("🦊", at: start.addingTimeInterval(2))
    XCTAssertEqual(session.typed, "a🦊")
    XCTAssertEqual(session.preciseAccuracy, 60)
  }

  func testLongerWrongGraphemeMovesSubsequentAccuracyByItsInputUnitLength() {
    var session = TypingSession(configuration: .words(2), prompt: "a🦊b bay")
    session.insert("ae\u{301}b", at: start)
    XCTAssertEqual(session.typedCharacterCount, 3)
    XCTAssertEqual(session.errors, 1)
    XCTAssertEqual(session.preciseAccuracy, 50)
  }
}
