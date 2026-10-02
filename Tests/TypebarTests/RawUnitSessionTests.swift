import AppKit
import XCTest
@testable import Typebar

final class RawUnitSessionTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 908_500_000)

  func testLetterStopAcceptsHighSurrogateBeforeStoppingWrongLowSurrogate() throws {
    var session = TypingSession(configuration: .words(1, rules: .init(stopOnErrorMode: .letter)), prompt: "🙂x")
    XCTAssertEqual(session.insertBatch("🙃", at: start), [false])
    XCTAssertEqual(session.typed, "�")
    XCTAssertEqual(session.preciseAccuracy, 50)
    session.bailOut(at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.replayEvents.map(\.textUTF16), [[55357], [56899]])
    XCTAssertEqual(result.replayEvents.map(\.inputCorrectness), [[true], [false]])
    XCTAssertEqual(result.replayEvents.map(\.inputStopped), [nil, true])
    XCTAssertEqual(result.replayEvents.map { $0.inputField?.valueUTF16 }, [[55357], [55357]])
    XCTAssertEqual(TypingReplay.typedUTF16(events: result.replayEvents, through: 1), [55357])
  }

  func testEmojiBackspaceRetainsHighSurrogateAndReinsertionRepairsThePair() throws {
    var session = TypingSession(configuration: .words(1, rules: .init(stopOnErrorMode: .letter)), prompt: "🙂x")
    session.insertBatch("🙂", at: start)
    session.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "�")
    XCTAssertEqual(session.insertBatch("🙂", at: start.addingTimeInterval(2)), [true])
    XCTAssertEqual(session.typed, "🙂")
    XCTAssertEqual(session.preciseAccuracy, 75)
    session.bailOut(at: start.addingTimeInterval(3))
    let events = try XCTUnwrap(session.result()).replayEvents
    XCTAssertEqual(events.map { $0.inputField?.valueUTF16 }, [[55357], [55357, 56898], [55357], [55357], [55357, 56898]])
    XCTAssertEqual(TypingReplay.typedUTF16(events: events, through: 3), [55357, 56898])
  }

  func testCombiningInputAcrossACommittedSeparatorKeepsItsOwnFieldWhenDeleted() throws {
    var session = TypingSession(configuration: .words(2), prompt: "ab cd")
    session.insertBatch("ab \u{301}c", at: start)
    session.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "ab \u{301}")
    session.deleteBackward(at: start.addingTimeInterval(2))
    XCTAssertEqual(session.typed, "ab ")
    XCTAssertEqual(session.completedWordCount, 1)
    session.deleteBackward(at: start.addingTimeInterval(3))
    XCTAssertEqual(session.typed, "ab ", "A correct prior field remains protected")
    session.bailOut(at: start.addingTimeInterval(4))
    let events = try XCTUnwrap(session.result()).replayEvents
    XCTAssertEqual(events.map { $0.inputField?.index }, [0, 0, 0, 1, 1, 1, 1])
    XCTAssertEqual(events.map { $0.inputField?.valueUTF16 }, [[97], [97, 98], [97, 98, 32], [769], [769, 99], [769], []])
    XCTAssertEqual(TypingReplay.typedUTF16(events: events, through: 4), [97, 98, 32])
  }

  func testTargetSeparatorJoinedToAMarkStillCreatesTwoLogicalFieldsAndFinishes() throws {
    var session = TypingSession(configuration: .words(2), prompt: "a \u{301}b")
    session.insertBatch("a \u{301}b", at: start)
    XCTAssertEqual(session.typed, "a \u{301}b")
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 2)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.replayEvents.map { $0.inputField?.index }, [0,0,1,1])
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 4)
    XCTAssertEqual(result.inputMetrics?.correctAttempts, 4)
  }

  func testSafeReplacementProjectionCannotFinishOrScoreAsALiteralReplacementTarget() throws {
    var session = TypingSession(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init()), prompt: "�x")
    session.insertBatch("🙂", at: start)
    session.deleteBackward(at: start.addingTimeInterval(1))
    session.insertBatch("x", at: start.addingTimeInterval(2))
    XCTAssertEqual(session.typed, "�x")
    XCTAssertEqual(session.outcome, .active)
    session.bailOut(at: start.addingTimeInterval(3))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.inputMetrics?.retainedUnits, 2)
    XCTAssertEqual(result.inputMetrics?.creditedUnits, 0)
    XCTAssertEqual(TypingReplay.typedUTF16(events: result.replayEvents, through: 3), [55357,120])
  }

  func testZenCapacityCanRetainAHalfPairWithoutInventingASecondAttempt() throws {
    var session = TypingSession(configuration: .init(mode: .zen, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init()), prompt: "")
    session.insertBatch(String(repeating: "a", count: 29), at: start)
    XCTAssertEqual(session.insertBatch("🙂", at: start.addingTimeInterval(1)), [])
    XCTAssertEqual(session.typed, String(repeating: "a", count: 29) + "�")
    session.deleteBackward(at: start.addingTimeInterval(2))
    XCTAssertEqual(session.typed, String(repeating: "a", count: 29))
    session.finishZen(at: start.addingTimeInterval(3))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 30)
    XCTAssertEqual(result.replayEvents[29].textUTF16, [55357])
    XCTAssertEqual(result.replayEvents[30].textUTF16, [])
  }

  func testJoinedEmojiTailProjectionMatchesRawDecodingAfterEveryDeletion() throws {
    for text in ["👩‍💻", "🇫🇷", "\u{600}🙂", "a \u{301}👩‍👩‍👧‍👧", "각🙂", "\r\n🙂"] {
      var session = TypingSession(configuration: .init(mode: .zen, duration: nil, wordLimit: nil,
        difficulty: .normal, rules: .init(freedomMode: true)), prompt: "")
      session.insertBatch(text, at: start)
      var units = Array(text.utf16)
      XCTAssertEqual(Array(session.typed.utf16), units, text)
      while !units.isEmpty {
        units.removeLast()
        session.deleteBackward(at: start.addingTimeInterval(1))
        XCTAssertEqual(Array(session.typed.utf16), Array(String(decoding: units, as: UTF16.self).utf16), text)
      }
      session.finishZen(at: start.addingTimeInterval(2))
      XCTAssertEqual(TypingReplay.typedUTF16(events: try XCTUnwrap(session.result()).replayEvents, through: 2), [])
    }
  }

  func testNativeRawFieldsSurvivePortableAndArchiveWithoutRejudgingStoredMetrics() throws {
    var session = TypingSession(configuration: .words(1, rules: .init(stopOnErrorMode: .letter)), prompt: "🙂x")
    session.insertBatch("🙃", at: start)
    session.bailOut(at: start.addingTimeInterval(1))
    let original = try XCTUnwrap(session.result())
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [original], presets: [], at: start))
    XCTAssertEqual(archive.version, 14)
    for result in [try XCTUnwrap(TestResultRecord(result: original).portableResult), archive.results[0]] {
      XCTAssertEqual(result, original)
      XCTAssertEqual(result.replayEvents.first?.inputField?.valueUTF16, [55357])
      XCTAssertEqual(result.preciseAccuracy, 50)
    }
  }

  @MainActor
  func testUnopenedAppKitConfirmationKeepsHalfPairAndDeletionInTheSession() throws {
    var session = TypingSession(configuration: .words(1, rules: .init(stopOnErrorMode: .letter)), prompt: "🙂x")
    let input = TypingInputView(frame: .zero)
    input.onInsert = { text, force in session.insertBatch(text, forceError: force, at: self.start) }
    input.onDelete = { session.deleteBackward(at: self.start.addingTimeInterval(1)) }
    input.setMarkedText("🙃", selectedRange: .init(), replacementRange: .init())
    XCTAssertEqual(session.typed, "")
    input.insertText("🙃", replacementRange: .init())
    XCTAssertEqual(session.typed, "�")
    XCTAssertFalse(input.hasMarkedText())
    input.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
    XCTAssertEqual(session.typed, "")
    session.bailOut(at: start.addingTimeInterval(2))
    XCTAssertEqual(try XCTUnwrap(session.result()).replayEvents.map(\.textUTF16), [[55357],[56899],[]])
  }

  func testDeterministicMixedUnicodeEditsMatchIndependentUnitAndFieldModel() throws {
    var session = TypingSession(configuration: .init(mode: .zen, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(freedomMode: true)), prompt: "")
    session.insertBatch("\u{600}", at: start)
    var units: [UInt16] = [1536]
    var fieldStarts = [0]
    var attempts = 1
    var seed: UInt64 = 0x7CAB_1234
    let tokens = ["a", "🙂", "👩‍💻", "🇫", "\u{301}", "\u{600}", "가", "\r\n", " ", "\n", "\u{200D}"]
    for step in 1...1_000 {
      seed = seed &* 6_364_136_223_846_793_005 &+ 1
      let date = start.addingTimeInterval(Double(step) / 10)
      if seed % 4 == 0 {
        if let last = units.last {
          if last == 32 || last == 10 { fieldStarts.removeLast() }
          units.removeLast()
        }
        session.deleteBackward(at: date)
      } else {
        let token = tokens[Int((seed >> 32) % UInt64(tokens.count))]
        for unit in token.utf16 {
          let activeCount = units.count - fieldStarts.last!
          if activeCount >= 30 && unit != 32 && unit != 10 { continue }
          if activeCount == 0 && unit == 32 { continue }
          units.append(unit)
          attempts += 1
          if unit == 32 || unit == 10 { fieldStarts.append(units.count) }
        }
        session.insertBatch(token, at: date)
      }
      XCTAssertEqual(Array(session.typed.utf16), Array(String(decoding: units, as: UTF16.self).utf16), "step \(step)")
    }
    session.finishZen(at: start.addingTimeInterval(101))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.inputMetrics?.totalAttempts, attempts)
    XCTAssertEqual(TypingReplay.typedUTF16(events: result.replayEvents, through: 101), units)
    XCTAssertEqual(result.replayEvents.last?.inputField?.index, fieldStarts.count - 1)
  }

  func testExhaustedRawFieldStillStopsEachWrongUnitInATimedSession() throws {
    var session = TypingSession(configuration: .timed(seconds: 5, rules: .init(stopOnErrorMode: .letter)), prompt: "🙂")
    session.insertBatch("🙂", at: start)
    XCTAssertEqual(session.insertBatch("🙃", at: start.addingTimeInterval(1)), [false])
    XCTAssertEqual(session.typed, "🙂")
    XCTAssertEqual(session.preciseAccuracy, 50)
    session.tick(at: start.addingTimeInterval(5))
    let events = try XCTUnwrap(session.result()).replayEvents
    XCTAssertEqual(events.map(\.inputStopped), [nil,nil,true,true])
    XCTAssertEqual(events.suffix(2).map { $0.inputField?.valueUTF16 }, [[55357,56898],[55357,56898]])
  }

  func testWrongCommitSeparatorDoesNotProtectAnOtherwiseCorrectPriorField() {
    var session = TypingSession(configuration: .words(3), prompt: "é beta\nlast")
    session.insertBatch("é\n", at: start)
    XCTAssertEqual(session.completedWordCount, 1)
    session.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "é", "The source compares the whole submitted field, including its separator")
    XCTAssertEqual(session.completedWordCount, 0)
  }
}
