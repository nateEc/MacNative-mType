import AppKit
import XCTest
@testable import Typebar

final class CombiningUnitInputTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 908_100_000)

  func testLetterStopAcceptsCorrectBaseBeforeStoppingIncorrectCombiningMark() throws {
    var session = TypingSession(configuration: .words(1, rules: .init(stopOnErrorMode: .letter)), prompt: "e\u{301}x")
    XCTAssertEqual(session.insertBatch("e\u{300}", at: start), [false])
    XCTAssertEqual(session.typed, "e")
    XCTAssertEqual(session.preciseAccuracy, 50)
    session.bailOut(at: start.addingTimeInterval(1))
    let events = try XCTUnwrap(session.result()).replayEvents
    XCTAssertEqual(events.map(\.text), ["e", "\u{300}"])
    XCTAssertEqual(events.map(\.inputStopped), [nil, true])
    XCTAssertEqual(events.map { $0.inputField?.value }, ["e", "e"])
  }

  func testLetterStopAllowsSeparateBaseAndCorrectCombiningMark() {
    var session = TypingSession(configuration: .words(1, rules: .init(stopOnErrorMode: .letter)), prompt: "e\u{301}x")
    XCTAssertEqual(session.insertBatch("e", at: start), [true])
    XCTAssertEqual(session.typed, "e")
    XCTAssertEqual(session.insertBatch("\u{301}", at: start.addingTimeInterval(1)), [true])
    XCTAssertEqual(session.typed, "e\u{301}")
    XCTAssertEqual(session.preciseAccuracy, 100)
    XCTAssertEqual(session.errors, 0)
    session.insertBatch("x", at: start.addingTimeInterval(2))
    XCTAssertEqual(session.outcome, .completed)
  }

  func testCombiningBackspaceRetainsBaseAndAllowsCorrectMarkRepair() throws {
    var session = TypingSession(configuration: .words(1, rules: .init(stopOnErrorMode: .letter)), prompt: "e\u{301}x")
    session.insertBatch("e\u{301}", at: start)
    session.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "e")
    XCTAssertEqual(session.insertBatch("\u{301}", at: start.addingTimeInterval(2)), [true])
    XCTAssertEqual(session.typed, "e\u{301}")
    session.bailOut(at: start.addingTimeInterval(3))
    let events = try XCTUnwrap(session.result()).replayEvents
    XCTAssertEqual(events.first { $0.kind == .delete }?.inputField?.value, "e")
    XCTAssertEqual(TypingReplay.typedText(events: events, through: 3), "e\u{301}")
  }

  func testWrongBaseStopsBothUnitsWithoutConsumingTheTargetMark() throws {
    var session = TypingSession(configuration: .words(1, rules: .init(stopOnErrorMode: .letter)), prompt: "e\u{301}x")
    XCTAssertEqual(session.insertBatch("a\u{301}", at: start), [false])
    XCTAssertEqual(session.typed, "")
    XCTAssertEqual(session.preciseAccuracy, 0)
    XCTAssertEqual(session.insertBatch("e\u{301}", at: start.addingTimeInterval(1)), [true])
    session.bailOut(at: start.addingTimeInterval(2))
    let events = try XCTUnwrap(session.result()).replayEvents
    XCTAssertEqual(events.map(\.inputCorrectness), [[false], [false], [true], [true]])
    XCTAssertEqual(events.map { $0.inputField?.value }, ["", "", "e", "e\u{301}"])
  }

  func testLetterRecoveryDeletesIncorrectMarkThenBaseAsTwoUnits() throws {
    var session = TypingSession(configuration: .words(1, rules: .init(deleteOnErrorMode: .letter)), prompt: "e\u{301}x")
    session.insertBatch("e\u{300}", at: start)
    XCTAssertEqual(session.typed, "")
    session.bailOut(at: start.addingTimeInterval(1))
    let events = try XCTUnwrap(session.result()).replayEvents
    XCTAssertEqual(events.map(\.kind), [.insert, .insert, .delete, .delete])
    XCTAssertEqual(events.map { $0.inputField?.value }, ["e", "e\u{300}", "e", ""])
    XCTAssertTrue(events.filter { $0.kind == .delete }.allSatisfy { $0.automatic })
    XCTAssertEqual(TypingReplay.typedUTF16(events: events, through: 1), [])
  }

  func testMultipleMarksDeleteAndRetypeWithOriginalWordStartTime() {
    var session = TypingSession(configuration: .words(2), prompt: "e\u{301}\u{323} bay")
    session.insertBatch("e\u{301}\u{323}", at: start)
    session.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(Array(session.typed.utf16), Array("e\u{301}".utf16))
    session.deleteBackward(at: start.addingTimeInterval(2))
    XCTAssertEqual(session.typed, "e")
    session.insertBatch("\u{301}\u{323}", at: start.addingTimeInterval(3))
    session.insertBatch(" ", at: start.addingTimeInterval(4))
    XCTAssertEqual(session.preciseAccuracy, 100)
    XCTAssertEqual(session.recentWordBursts, [12])
    XCTAssertEqual(session.completedWordCount, 1)
  }

  func testZenCapacityUsesUnitsAndAllowsCommitAfterPartialBatch() throws {
    var session = TypingSession(configuration: .init(mode: .zen, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init()), prompt: "")
    session.insertBatch(String(repeating: "e\u{301}", count: 15), at: start)
    session.insertBatch("e\u{301}", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed.utf16.count, 30)
    session.deleteBackward(at: start.addingTimeInterval(2))
    XCTAssertEqual(session.typed.utf16.count, 29)
    session.insertBatch("e\u{301}", at: start.addingTimeInterval(3))
    XCTAssertEqual(session.typed.utf16.count, 30)
    XCTAssertEqual(session.typed.last, "e")
    session.insertBatch(" ", at: start.addingTimeInterval(4))
    session.finishZen(at: start.addingTimeInterval(5))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 32)
    XCTAssertEqual(TypingReplay.typedUTF16(events: result.replayEvents, through: 5), Array(session.typed.utf16))
  }

  func testNativeBMPProducerKeepsExactUnitsAndDeletionRequiresTwenty() throws {
    var session = TypingSession(configuration: .words(1), prompt: "e\u{301}x")
    session.insertBatch("e\u{301}", at: start)
    session.deleteBackward(at: start.addingTimeInterval(1))
    session.bailOut(at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    let archive = TypebarArchive(version: 13, exportedAt: start, settings: .init(), results: [result], presets: [])
    XCTAssertEqual(archive.version, 20)
    XCTAssertEqual(result.replayEvents.map(\.deletionCharIndex), [nil,nil,2])
    XCTAssertEqual(result.replayEvents.map(\.textUTF16), [[101], [769], []])
    XCTAssertEqual(result.replayEvents.map { $0.inputField?.valueUTF16 }, [[101], [101, 769], [101]])
    let restored = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [], at: start))
    XCTAssertEqual(restored.results, [result])
  }

  func testOwnedFourteenBMPWithoutDeletionPositionsStaysFourteen() throws {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, units: [101], inputField: .init(index: 0, units: [101]), inputCorrectness: [true]),
      .init(offset: 0, kind: .insert, units: [769], inputField: .init(index: 0, units: [101,769]), inputCorrectness: [true]),
      .init(offset: 1, kind: .delete, units: [], inputField: .init(index: 0, units: [101]))]
    let old = CompletedTestResult(id: UUID(), configuration: .words(1), outcome: .bailedOut,
      startedAt: start, finishedAt: start.addingTimeInterval(2), typedCharacterCount: 1,
      correctCharacterCount: 1, errorCount: 0, wpm: 17, rawWpm: 29, accuracy: 77,
      prompt: "e\u{301}x", replayEvents: events)
    let archive = TypebarArchive(version: 13, exportedAt: start, settings: .init(), results: [old], presets: [])
    XCTAssertEqual(archive.version, 14)
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    let restored = try TypebarDataTransfer.importArchive(from: encoder.encode(archive)).results[0]
    XCTAssertEqual(restored, old)
    XCTAssertTrue(restored.replayEvents.allSatisfy { $0.deletionCharIndex == nil })
    XCTAssertEqual(TypingReplay.typedUTF16(events: restored.replayEvents, through: 2), [101])
  }

  func testUnitPositionOwnsQuoteNormalizationBeforeACombiningMark() throws {
    var session = TypingSession(configuration: .words(1), prompt: "’\u{301}x")
    XCTAssertEqual(session.insertBatch("'\u{301}", at: start), [true])
    XCTAssertEqual(Array(session.typed.utf16), [8217, 769])
    session.bailOut(at: start.addingTimeInterval(1))
    let events = try XCTUnwrap(session.result()).replayEvents
    XCTAssertEqual(events.map(\.textUTF16), [[8217], [769]])
    XCTAssertEqual(events.map(\.inputCorrectness), [[true], [true]])
  }

  func testASCIIFastPathKeepsRussianEUnitNormalization() throws {
    var session = TypingSession(configuration: .words(1, language: .russian), prompt: "е\u{301}x")
    session.insertBatch("e\u{301}", at: start)
    XCTAssertEqual(Array(session.typed.utf16), [1077, 769])
    session.insertBatch("x", at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.preciseAccuracy, 100)
    XCTAssertEqual(result.replayEvents.first?.textUTF16, [1077])
  }

  func testBMPPrependAndHangulPartsKeepAlignedMetadataDuringDeletion() throws {
    for text in ["\u{600}a", "\u{1100}\u{1161}\u{11A8}"] {
      var session = TypingSession(configuration: .words(1), prompt: text + "x")
      session.insertBatch(text, at: start)
      session.deleteBackward(at: start.addingTimeInterval(1))
      XCTAssertEqual(Array(session.typed.utf16), Array(text.utf16.dropLast()))
      session.insertBatch(String(text.unicodeScalars.last!), at: start.addingTimeInterval(2))
      session.insertBatch("x", at: start.addingTimeInterval(3))
      let result = try XCTUnwrap(session.result())
      XCTAssertEqual(session.errors, 0)
      XCTAssertEqual(session.wordBurstHistory, [Int((Double(text.utf16.count + 2) * 12 / 3).rounded(.down))])
      XCTAssertEqual(TypingReplay.typedUTF16(events: result.replayEvents, through: 3), Array((text + "x").utf16))
    }
  }

  func testCompletedUnitTapeDoesNotInventWeakSpotMistakesForCorrectParts() throws {
    var session = TypingSession(configuration: .words(2), prompt: "e\u{301} bay")
    session.insertBatch("e\u{300}", at: start)
    session.deleteBackward(at: start.addingTimeInterval(1))
    session.insertBatch("\u{301} bay", at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(WeakSpotPractice.characterScores(results: [result], language: .english), [Character("e\u{301}"): 1])
  }

  @MainActor
  func testUnopenedAppKitConfirmationAndBackspaceReachTheBMPUnitSession() throws {
    var session = TypingSession(configuration: .words(1), prompt: "e\u{301}x")
    let view = TypingInputView(frame: .zero)
    view.onInsert = { text, forced in session.insertBatch(text, forceError: forced, at: self.start) }
    view.onDelete = { session.deleteBackward(at: self.start.addingTimeInterval(1)) }
    view.setMarkedText("e\u{301}", selectedRange: .init(location: 2, length: 0), replacementRange: .init())
    XCTAssertEqual(session.typed, "")
    view.insertText(NSAttributedString(string: "e\u{301}"), replacementRange: .init())
    XCTAssertEqual(session.typed, "e\u{301}")
    XCTAssertFalse(view.hasMarkedText())
    view.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
    XCTAssertEqual(session.typed, "e")
    session.bailOut(at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 2)
    XCTAssertEqual(result.replayEvents.map(\.textUTF16), [[101], [769], []])
  }
}
