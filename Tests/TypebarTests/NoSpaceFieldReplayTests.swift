import XCTest
import SwiftData
@testable import Typebar

final class NoSpaceFieldReplayTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 909_500_000)
  private let configuration = TestConfiguration.words(2).with(modifiers: [.noSpaces])
  private func inserted(_ unit: UInt16, field: Int, snapshot: [UInt16], at offset: Double) -> TypingReplayEvent {
    .init(offset: offset, kind: .insert, units: [unit], inputField: .init(index: field, units: snapshot), inputCorrectness: [true])
  }

  func testKnownHiddenBoundariesProduceTargetFrameAndIndexBasedSeek() throws {
    let directory = ResultTargetWordDirectory(words: ["ab", "cd"], noSpace: true)
    let events = [inserted(97, field: 0, snapshot: [97], at: 0),
      inserted(98, field: 0, snapshot: [97,98], at: 0),
      inserted(99, field: 1, snapshot: [99], at: 1),
      inserted(100, field: 1, snapshot: [99,100], at: 2)]
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: "abcd", events: events,
      configuration: configuration, targetWordDirectory: directory))
    XCTAssertEqual(plan.initialFrame.fields.count, 2)
    XCTAssertEqual(plan.initialFrame.presentation.text, "abcd")
    let seek = try XCTUnwrap(plan.seek(.init(word: 1, position: 0)))
    XCTAssertEqual(seek.frame.nextActionIndex, 3)
    XCTAssertEqual(seek.nextOffset, 1)
    XCTAssertEqual(seek.frame.presentation.glyphs.map(\.state), [.correct,.correct,.pending,.pending])
    var frame = seek.frame
    XCTAssertEqual(plan.advance(&frame, through: 1), [.click])
    XCTAssertEqual(plan.advance(&frame, through: 1), [])
    XCTAssertEqual(plan.advance(&frame, through: 2), [.click])
    XCTAssertEqual(frame.coordinate, .init(word: 1, position: 2))
    XCTAssertEqual(frame, plan.frame(through: 2))
  }

  func testTerminalRegressionPreservesSourceNetPrefixRatherThanAcceptedText() throws {
    var input = TypingSession(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(freedomMode: true), modifiers: [.noSpaces]),
      prompt: "abcd", noSpaceTargetWords: ["ab", "cd"])
    input.insertBatch("abcd ", at: start)
    input.deleteBackward(at: start.addingTimeInterval(1))
    input.bailOut(at: start.addingTimeInterval(2))
    let saved = try XCTUnwrap(input.result())
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: saved.prompt, events: saved.replayEvents,
      configuration: saved.configuration, targetWordDirectory: saved.targetWordDirectory))
    XCTAssertEqual(plan.initialFrame.fields.count, 1)
    let frame = plan.frame(through: 1)
    XCTAssertEqual(frame.presentation.text, "ab")
    XCTAssertEqual(frame.presentation.glyphs.map(\.state), [.correct,.correct])
    XCTAssertEqual(frame.presentation.errorIndices, [0,1])
    XCTAssertEqual(frame.coordinate, .init(word: 1, position: 0))
    XCTAssertEqual(TypingReplay.typedText(events: saved.replayEvents, through: 1), "a")
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: saved.replayEvents), ["a", ""])
    XCTAssertEqual(saved.inputMetrics?.retainedUnits, 3)
  }

  func testRawSurrogateActionsKeepScalarTargetsAndHiddenWordSeek() throws {
    let directory = ResultTargetWordDirectory(words: ["🙂", "a"], noSpace: true)
    let events = [inserted(0xd83d, field: 0, snapshot: [0xd83d], at: 0),
      inserted(0xde42, field: 0, snapshot: [0xd83d,0xde42], at: 0),
      inserted(97, field: 1, snapshot: [97], at: 1)]
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: "🙂a", events: events,
      configuration: configuration, targetWordDirectory: directory))
    XCTAssertEqual(plan.initialFrame.fields.map { $0.letters.count }, [1,1])
    let seek = try XCTUnwrap(plan.seek(.init(word: 1, position: 0)))
    XCTAssertEqual(seek.frame.nextActionIndex, 3)
    XCTAssertEqual(seek.frame.presentation.glyphs.map(\.state), [.correct,.pending])
    XCTAssertEqual(plan.frame(through: 1).presentation.glyphs.map(\.state), [.correct,.correct])
  }

  func testLiteralNewlineAndCombiningTargetUseSavedWordsNotFlattenedSplit() throws {
    let words = ["a\u{301}\n", "b"]
    let directory = ResultTargetWordDirectory(words: words, noSpace: true)
    let events = [inserted(97, field: 0, snapshot: [97], at: 0),
      inserted(769, field: 0, snapshot: [97,769], at: 0),
      inserted(10, field: 0, snapshot: [97,769,10], at: 1),
      inserted(98, field: 1, snapshot: [98], at: 2)]
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: words.joined(), events: events,
      configuration: configuration, targetWordDirectory: directory))
    XCTAssertEqual(plan.initialFrame.fields.map { $0.letters.map(\.text) }, [["a", "\u{301}", "\n"], ["b"]])
    XCTAssertTrue(plan.frame(through: 2).presentation.glyphs.allSatisfy { $0.state == .correct })
  }

  func testStoppedInsertionStillSubmitsHiddenWordWithoutAddingLetterOrCue() throws {
    let events = [inserted(97, field: 0, snapshot: [97], at: 0), inserted(98, field: 0, snapshot: [97,98], at: 0),
      TypingReplayEvent(offset: 1, kind: .insert, units: [120], inputStopped: true,
        inputField: .init(index: 1, units: []), inputCorrectness: [false])]
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: "abcd", events: events,
      configuration: configuration, targetWordDirectory: .init(words: ["ab", "cd"], noSpace: true)))
    var frame = plan.initialFrame
    XCTAssertEqual(plan.advance(&frame, through: 1), [.click,.click,.click])
    XCTAssertEqual(frame.coordinate, .init(word: 1, position: 0))
    XCTAssertEqual(frame.presentation.glyphs.map(\.state), [.correct,.correct,.pending,.pending])
  }

  func testEmptyCatalogSlotKeepsSingleSourceAdvanceRatherThanIndexJump() throws {
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: "ab", events: [
      inserted(97, field: 0, snapshot: [97], at: 0), inserted(98, field: 2, snapshot: [98], at: 1)],
      configuration: configuration, targetWordDirectory: .init(words: ["a", "", "b"], noSpace: true)))
    XCTAssertEqual(plan.initialFrame.fields.map { $0.letters.count }, [1,0])
    let frame = plan.frame(through: 1)
    XCTAssertEqual(frame.coordinate, .init(word: 1, position: 1))
    XCTAssertEqual(frame.presentation.text, "a")
    XCTAssertEqual(plan.actions.count, 3)
  }

  func testCapturedNonzeroFirstFieldStillUsesSourceZeroDisplayCursor() throws {
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: "b", events: [
      inserted(98, field: 1, snapshot: [98], at: 0)], configuration: configuration,
      targetWordDirectory: .init(words: ["", "b"], noSpace: true)))
    XCTAssertEqual(plan.initialFrame.fields.count, 1)
    XCTAssertEqual(plan.frame(through: 0).presentation.text, "")
    XCTAssertEqual(plan.frame(through: 0).coordinate, .init(word: 0, position: 1))
  }

  func testWrongHiddenWordKeepsTargetStatesAndFinalSnapshotErrorCue() throws {
    let events = [TypingReplayEvent(offset: 0, kind: .insert, units: [120],
      inputField: .init(index: 0, units: [120]), inputCorrectness: [false]),
      inserted(98, field: 0, snapshot: [120,98], at: 0), inserted(99, field: 1, snapshot: [99], at: 1)]
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: "abcd", events: events,
      configuration: configuration, targetWordDirectory: .init(words: ["ab", "cd"], noSpace: true)))
    var frame = plan.initialFrame
    XCTAssertEqual(plan.advance(&frame, through: 1), [.error,.click,.error,.click])
    XCTAssertEqual(frame.presentation.glyphs.map(\.state), [.incorrect,.correct,.correct,.pending])
    XCTAssertEqual(frame.presentation.errorIndices, [0,1])
  }

  func testWholeWordRegressionUsesFinalPrimitiveAndDoesNotInventSecondResize() throws {
    let events = [inserted(97, field: 0, snapshot: [97], at: 0), inserted(98, field: 0, snapshot: [97,98], at: 0),
      inserted(99, field: 1, snapshot: [99], at: 0),
      TypingReplayEvent(offset: 1, kind: .delete, units: [], wordDeletionCount: 2,
        inputField: .init(index: 1, units: [])),
      TypingReplayEvent(offset: 1, kind: .delete, units: [], inputField: .init(index: 0, units: [97])),
      inserted(98, field: 0, snapshot: [97,98], at: 2), inserted(99, field: 1, snapshot: [99], at: 3)]
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: "abcd", events: events,
      configuration: configuration, targetWordDirectory: .init(words: ["ab", "cd"], noSpace: true)))
    XCTAssertEqual(plan.actions.filter { $0.offset == 1 }.map(\.kind), [.retreat])
    XCTAssertEqual(plan.frame(through: 1).coordinate, .init(word: 0, position: 2))
    XCTAssertEqual(plan.frame(through: 3).coordinate, .init(word: 1, position: 1))
  }

  func testMissingMismatchedDirectoryMixedLegacyAndUnsafeIndicesKeepFallback() {
    let event = inserted(97, field: 0, snapshot: [97], at: 0)
    let valid = ResultTargetWordDirectory(words: ["ab", "cd"], noSpace: true)
    let invalidDirectories: [ResultTargetWordDirectory?] = [nil,
      .init(words: ["ab", "cx"], noSpace: true),
      .init(words: ["ab", "cd"], noSpace: false), .init(words: [], noSpace: true)]
    for directory in invalidDirectories {
      XCTAssertNil(FieldReplayPlan.make(prompt: "abcd", events: [event], configuration: configuration, targetWordDirectory: directory))
    }
    for events in [[event,.init(offset: 1, kind: .insert, text: "b")],
      [.init(offset: 0, kind: .insert, text: "a")],
      [inserted(97, field: Int.max, snapshot: [97], at: 0)],
      [inserted(97, field: -1, snapshot: [97], at: 0)],
      [inserted(97, field: 0, snapshot: [97], at: -.infinity)]] {
      XCTAssertNil(FieldReplayPlan.make(prompt: "abcd", events: events, configuration: configuration, targetWordDirectory: valid))
    }
    XCTAssertEqual(FieldReplayPresentation.glyphs(prompt: "abcd", events: [event], through: 1, configuration: configuration),
      TypingReplay.inputGlyphs(prompt: "abcd", events: [event], through: 1))
  }

  func testCapturedPresentationFacadeUsesSamePlanInsteadOfAcceptedGlyphFallback() throws {
    let events = [inserted(97, field: 0, snapshot: [97], at: 0)]
    let directory = ResultTargetWordDirectory(words: ["ab", "cd"], noSpace: true)
    let glyphs = FieldReplayPresentation.glyphs(prompt: "abcd", events: events, through: 0,
      configuration: configuration, targetWordDirectory: directory)
    XCTAssertEqual(String(glyphs.map(\.character)), "ab")
    XCTAssertEqual(glyphs.map(\.state), [.correct,.pending])
  }

  func testOwnedFifteenDirectoryCanRenderWithoutRescoringOrAddingNewArchiveMetadata() throws {
    let old = CompletedTestResult(id: UUID(), configuration: configuration, outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(2), typedCharacterCount: 4,
      correctCharacterCount: 3, errorCount: 1, wpm: 17, rawWpm: 29, accuracy: 75, prompt: "abcd",
      replayEvents: [inserted(97, field: 0, snapshot: [97], at: 0), inserted(98, field: 0, snapshot: [97,98], at: 0),
        inserted(99, field: 1, snapshot: [99], at: 1), inserted(100, field: 1, snapshot: [99,100], at: 2)],
      targetWordDirectory: .init(words: ["ab", "cd"], noSpace: true))
    let archive = TypebarArchive(version: 15, exportedAt: start, settings: .init(), results: [old], presets: [])
    XCTAssertEqual(archive.version, 15)
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    let restored = try TypebarDataTransfer.importArchive(from: encoder.encode(archive)).results[0]
    XCTAssertEqual(restored, old)
    XCTAssertNil(restored.characterStats.sourceUnits)
    for result in [restored, try XCTUnwrap(TestResultRecord(result: restored).portableResult)] {
      let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: result.prompt, events: result.replayEvents,
        configuration: result.configuration, targetWordDirectory: result.targetWordDirectory))
      XCTAssertEqual(plan.frame(through: 2).coordinate, .init(word: 1, position: 2))
      XCTAssertEqual(result.wpm, 17)
    }
  }

  func testIncrementalThousandHiddenWordsResumeWithoutDuplicateCues() throws {
    let words = Array(repeating: "a", count: 1_000)
    let events = (0..<1_000).map { inserted(97, field: $0, snapshot: [97], at: Double($0)) }
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: words.joined(), events: events,
      configuration: configuration, targetWordDirectory: .init(words: words, noSpace: true)))
    var frame = plan.initialFrame; var cues = 0
    for offset in [0.0,200,500,999] {
      cues += plan.advance(&frame, through: offset).count
      XCTAssertEqual(frame, plan.frame(through: offset))
      XCTAssertEqual(plan.advance(&frame, through: offset), [])
    }
    XCTAssertEqual(cues, 1_999)
    XCTAssertEqual(frame.presentation.glyphs.count, 1_000)
    XCTAssertTrue(frame.presentation.glyphs.allSatisfy { $0.state == .correct })
  }
}
