import AppKit
import XCTest
@testable import Typebar

final class CodeUnindentDeletionTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 874_100_000)

  private func session(_ rules: InputRules = .init(codeUnindentOnBackspace: true),
    prompt: String = "seed ab\n\tgo()\ntail", language: TypingLanguage = .codeSwift) -> TypingSession {
    TypingSession(configuration: .words(4, rules: rules, language: language), prompt: prompt)
  }

  private func saved(_ input: TypingSession) throws -> CompletedTestResult {
    var ended = input
    ended.bailOut(at: start.addingTimeInterval(3))
    return try XCTUnwrap(ended.result())
  }

  private func deletionActions(_ result: CompletedTestResult) -> [TypingReplay.Action] {
    TypingReplay.actions(events: result.replayEvents).filter { $0.kind != .insert }
  }

  private func deletionCues(_ result: CompletedTestResult) -> [TypingReplaySoundCue] {
    TypingReplay.soundCues(prompt: result.prompt, events: result.replayEvents, after: 0.5, through: 1.5)
  }

  func testWordUnindentClearsThePreviousWordNotEveryWordOnThePreviousLine() throws {
    var input = session()
    input.insertBatch("seed ab\n\t\t", at: start)
    input.deleteWordBackward(at: start.addingTimeInterval(1))
    let result = try saved(input)
    XCTAssertEqual(input.typed, "seed ")
    XCTAssertEqual(input.completedWordCount, 1)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 1), "seed ")
    let actions = deletionActions(result)
    XCTAssertEqual(actions.map(\.kind), [.deleteWord, .deleteCharacter])
    XCTAssertEqual(actions.map { $0.primitiveRange.count }, [3, 3])
    XCTAssertTrue(actions.flatMap(\.primitives).allSatisfy { !$0.automatic })
    XCTAssertEqual(deletionCues(result), [.click, .click])
  }

  func testOrdinaryUnindentKeepsThePreviousWordAndRecordsTwoManualActions() throws {
    var input = session()
    input.insertBatch("seed ab\n\t", at: start)
    input.deleteBackward(at: start.addingTimeInterval(1))
    let result = try saved(input)
    XCTAssertEqual(input.typed, "seed ab")
    XCTAssertEqual(deletionActions(result).map(\.kind), [.deleteWord, .deleteCharacter])
    XCTAssertEqual(deletionActions(result).map { $0.primitiveRange.count }, [2, 1])
    XCTAssertTrue(deletionActions(result).flatMap(\.primitives).allSatisfy { !$0.automatic })
    XCTAssertEqual(deletionCues(result), [.click, .click])
  }

  func testWordUnindentCanReopenACorrectPriorWordInConfidenceOnButMaximumBlocksIt() throws {
    for confidence in [ConfidenceMode.off, .on, .maximum] {
      var input = session(.init(confidenceMode: confidence, codeUnindentOnBackspace: true))
      input.insertBatch("seed ab\n", at: start)
      input.deleteWordBackward(at: start.addingTimeInterval(1))
      let result = try saved(input)
      XCTAssertEqual(input.typed, confidence == .maximum ? "seed ab\n\t" : "seed ")
      XCTAssertEqual(deletionActions(result).count, confidence == .maximum ? 0 : 2)
      XCTAssertEqual(deletionCues(result), confidence == .maximum ? [] : [.click, .click])
    }
  }

  func testOrdinaryUnindentDoesNotClearTwoIncorrectRemainingTabs() throws {
    var input = session()
    input.insertBatch("seed ab\n\t\t", at: start)
    input.deleteBackward(at: start.addingTimeInterval(1))
    let result = try saved(input)
    XCTAssertEqual(input.typed, "seed ab\n\t\t")
    XCTAssertEqual(deletionActions(result).map(\.kind), [.deleteCharacter])
    XCTAssertEqual(deletionCues(result), [.click])
  }

  func testFirstWordUnindentRecordsTheDestinationNoOpWithoutDeletingEarlierInput() throws {
    for wholeWord in [false, true] {
      var input = session(prompt: "\tgo()\ntail")
      input.insertBatch("\t\t", at: start)
      if wholeWord { input.deleteWordBackward(at: start.addingTimeInterval(1)) }
      else { input.deleteBackward(at: start.addingTimeInterval(1)) }
      let result = try saved(input)
      XCTAssertEqual(input.typed, "")
      XCTAssertEqual(deletionActions(result).map(\.kind), [.deleteWord, .deleteCharacter])
      XCTAssertEqual(deletionActions(result).map { $0.primitiveRange.count }, [2, 1])
      XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 1), "")
      XCTAssertEqual(deletionCues(result), [.click, .click])
    }
  }

  func testDisabledUnindentKeepsPreviousCommittedWord() throws {
    var input = session(.init(codeUnindentOnBackspace: false))
    input.insertBatch("seed ab\n", at: start)
    input.deleteWordBackward(at: start.addingTimeInterval(1))
    let result = try saved(input)
    XCTAssertEqual(input.typed, "seed ab\n")
    XCTAssertEqual(deletionActions(result).map(\.kind), [.deleteWord])
    XCTAssertEqual(deletionCues(result), [.click])
  }

  func testUnicodePreviousWordIsClearedAsOneCharacterActionAndCanBeRetypedToFinish() throws {
    let prompt = "seed 🙂e\u{301}\n\tgo()\ntail"
    var input = session(prompt: prompt)
    input.insertBatch("seed 🙂e\u{301}\n", at: start)
    input.deleteWordBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(input.typed, "seed ")
    let actions = deletionActions(try saved(input))
    XCTAssertEqual(actions.map(\.kind), [.deleteWord, .deleteCharacter])
    // Converted combining text deletes its mark and base separately, while
    // this still-unconverted emoji retains its legacy whole-glyph primitive.
    XCTAssertEqual(actions.map { $0.primitiveRange.count }, [1, 4])
    input.insertBatch("🙂e\u{301}\n\tgo()\ntail", at: start.addingTimeInterval(2))
    XCTAssertEqual(input.outcome, .completed)
    XCTAssertEqual(input.typed, prompt)
    let result = try XCTUnwrap(input.result())
    let portable = try XCTUnwrap(TestResultRecord(result: result).portableResult)
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [], at: start))
    for restored in [result, portable, archive.results[0]] {
      XCTAssertEqual(deletionActions(restored).map(\.kind), [.deleteWord, .deleteCharacter])
      XCTAssertEqual(deletionCues(restored), [.click, .click])
      XCTAssertEqual(TypingReplay.typedText(events: restored.replayEvents, through: 2), prompt)
    }
  }

  func testWeakSpotCursorIncludesAutomaticIndentationButDoesNotScoreItAsAHumanAttempt() throws {
    var input = session()
    input.insertBatch("seed ab\n", at: start)
    input.insertBatch("\t", at: start)
    input.deleteWordBackward(at: start.addingTimeInterval(1))
    input.insertBatch("ab\n", at: start.addingTimeInterval(2))
    input.insertBatch("go()\ntail", at: start.addingTimeInterval(2))
    XCTAssertEqual(input.outcome, .completed)
    let result = try XCTUnwrap(input.result())
    // The extra manually entered tab is the only wrong attempt, at target g.
    XCTAssertEqual(WeakSpotPractice.characterScores(results: [result], language: .codeSwift), ["g": 1])
  }

  func testWeakSpotCursorAppliesAutomaticErrorDeletesWithoutScoringNewAttempts() throws {
    for mode in [DeleteOnErrorMode.word, .wordHard] {
      var input = TypingSession(configuration: .words(2, rules: .init(deleteOnErrorMode: mode)),
        prompt: "ab cd")
      input.insertBatch(mode == .word ? "a" : "ab ", at: start)
      input.insertBatch("x", at: start.addingTimeInterval(1))
      input.insertBatch("ab cd", at: start.addingTimeInterval(2))
      let result = try XCTUnwrap(input.result())
      let expected: [Character: Int] = mode == .word ? ["b": 1] : ["c": 1]
      XCTAssertEqual(WeakSpotPractice.characterScores(results: [result], language: .english), expected)
    }
  }

  func testWeakSpotUsesTheSameExactSpellingAsTheLiveInputAfterRecovery() throws {
    var input = TypingSession(configuration: .words(2), prompt: "ab e\u{301}")
    input.insertBatch("ab é", at: start)
    input.deleteBackward(at: start.addingTimeInterval(1))
    input.insertBatch("e\u{301}", at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(input.result())
    XCTAssertEqual(WeakSpotPractice.characterScores(results: [result], language: .english),
      [Character("e\u{301}"): 1])
  }

  @MainActor
  func testUnopenedNativeResponderDeliversTheOriginalWordDeleteCommand() throws {
    var input = session()
    let view = TypingInputView(frame: .zero)
    view.onInsert = { text, forced in input.insertBatch(text, forceError: forced, at: self.start) }
    view.onDelete = { input.deleteBackward(at: self.start.addingTimeInterval(1)) }
    view.onDeleteWord = { input.deleteWordBackward(at: self.start.addingTimeInterval(1)) }
    view.insertText("seed ab\n", replacementRange: .init())
    view.doCommand(by: #selector(NSResponder.deleteWordBackward(_:)))
    XCTAssertEqual(input.typed, "seed ")
    XCTAssertEqual(deletionCues(try saved(input)), [.click, .click])
  }

  func testEveryCodeLanguageUsesCommandAwareDestinationDeletion() {
    for language in TypingLanguage.allCases.filter(\.isCodeLanguage) {
      var input = session(language: language)
      input.insertBatch("seed ab\n", at: start)
      input.deleteWordBackward(at: start.addingTimeInterval(1))
      XCTAssertEqual(input.typed, "seed ", language.rawValue)
      XCTAssertEqual(input.completedWordCount, 1, language.rawValue)
    }
  }

  func testEmptyPreviousFieldDoesNotConsumeAnEarlierLine() throws {
    for wholeWord in [false, true] {
      var input = session(prompt: "seed\n\n\tgo()\ntail")
      input.insertBatch("seed\n\n", at: start)
      if wholeWord { input.deleteWordBackward(at: start.addingTimeInterval(1)) }
      else { input.deleteBackward(at: start.addingTimeInterval(1)) }
      let result = try saved(input)
      XCTAssertEqual(input.typed, "seed\n")
      XCTAssertEqual(deletionActions(result).map(\.kind), [.deleteWord, .deleteCharacter])
      XCTAssertEqual(deletionCues(result), [.click, .click])
    }
  }

  func testCharacterSpanSurvivesNewAndPreviousReaderShapesWithoutTextLoss() throws {
    // The previous binary knew wordDeletionCount, but not characterDeletionCount.
    struct PreviousEvent: Decodable {
      let offset: TimeInterval
      let kind: TypingReplayEventKind
      let text: String
      let forceError: Bool
      let automatic: Bool
      let commitsWord: Bool?
      let wordDeletionCount: Int?
    }
    var input = session()
    input.insertBatch("seed ab\n", at: start)
    input.deleteWordBackward(at: start.addingTimeInterval(1))
    let result = try saved(input)
    let data = try JSONEncoder().encode(result.replayEvents)
    let current = try JSONDecoder().decode([TypingReplayEvent].self, from: data)
    XCTAssertEqual(current, result.replayEvents)
    XCTAssertEqual(deletionActions(result).last?.primitives.map(\.characterDeletionCount), [3, nil, nil])
    let old = try JSONDecoder().decode([PreviousEvent].self, from: data).map {
      TypingReplayEvent(offset: $0.offset, kind: $0.kind, text: $0.text, forceError: $0.forceError,
        automatic: $0.automatic, commitsWord: $0.commitsWord, wordDeletionCount: $0.wordDeletionCount)
    }
    XCTAssertEqual(TypingReplay.typedText(events: old, through: 1), "seed ")
    XCTAssertEqual(TypingReplay.soundCues(prompt: result.prompt, events: old, after: 0.5, through: 1),
      [.click, .click, .click, .click])
    XCTAssertEqual(TypingReplay.actions(events: old).filter { $0.kind != .insert }.map(\.kind),
      [.deleteWord, .deleteCharacter, .deleteCharacter, .deleteCharacter])
    // Missing fields stay nil; do not manufacture a type change in old tapes.
    let oldData = try JSONEncoder().encode(old)
    XCTAssertFalse(try XCTUnwrap(String(data: oldData, encoding: .utf8)).contains("characterDeletionCount"))
    XCTAssertTrue(try JSONDecoder().decode([TypingReplayEvent].self, from: oldData)
      .allSatisfy { $0.characterDeletionCount == nil })
  }

  func testMixedAndInvalidCharacterMarkersCannotSwallowOrRetypePrimitiveDeletes() {
    let insert = TypingReplayEvent(offset: 0, kind: .insert, text: "ab")
    let plain = TypingReplayEvent(offset: 1, kind: .delete, text: "")
    let pairs: [[TypingReplayEvent]] = [-1, 0, 3, Int.max].map {
      [.init(offset: 1, kind: .delete, text: "", characterDeletionCount: $0), plain]
    } + [
      [.init(offset: 1, kind: .delete, text: "", wordDeletionCount: 2, characterDeletionCount: 2), plain],
      [.init(offset: 1, kind: .delete, text: "", characterDeletionCount: 2),
       .init(offset: 1, kind: .delete, text: "", wordDeletionCount: 1)],
      [.init(offset: 1, kind: .delete, text: "", wordDeletionCount: 2),
       .init(offset: 1, kind: .delete, text: "", characterDeletionCount: 1)],
      [.init(offset: 1, kind: .delete, text: "", characterDeletionCount: 2),
       .init(offset: 1, kind: .delete, text: "", automatic: true)],
      [.init(offset: 1, kind: .delete, text: "", characterDeletionCount: 2),
       .init(offset: 1.1, kind: .delete, text: "")],
      [.init(offset: 1, kind: .delete, text: "", characterDeletionCount: 2),
       .init(offset: 1, kind: .insert, text: "a")]
    ]
    for pair in pairs {
      let events = [insert] + pair
      let plainEvents = events.map { TypingReplayEvent(offset: $0.offset, kind: $0.kind, text: $0.text,
        forceError: $0.forceError, automatic: $0.automatic, commitsWord: $0.commitsWord) }
      let actions = TypingReplay.actions(events: events)
      XCTAssertEqual(actions[1].primitiveRange.count, 1)
      XCTAssertEqual(actions[1].kind, .deleteCharacter)
      XCTAssertEqual(Array(actions.flatMap(\.primitives)), TypingReplay.chronologicalEvents(events))
      XCTAssertEqual(TypingReplay.typedText(events: events, through: 2),
        TypingReplay.typedText(events: plainEvents, through: 2))
      XCTAssertEqual(TypingReplay.soundCues(prompt: "ab", events: events, after: 0.5, through: 2),
        TypingReplay.soundCues(prompt: "ab", events: plainEvents, after: 0.5, through: 2))
    }
  }

  func testDestinationNoOpDoesNotAffectSeekGraphsOrSavedProgress() throws {
    var input = session(prompt: "\tgo()\ntail")
    input.insertBatch("\t\t", at: start)
    input.deleteWordBackward(at: start.addingTimeInterval(1))
    let result = try saved(input)
    let events = result.replayEvents
    let withoutNoOp = Array(events.dropLast())
    XCTAssertEqual(TypingReplay.typedText(events: events, through: 1), "")
    XCTAssertEqual(TypingReplay.inputGlyphs(prompt: result.prompt, events: events, through: 1), [])
    XCTAssertEqual(TypingReplay.characterSeekOffsets(prompt: result.prompt, events: events),
      TypingReplay.characterSeekOffsets(prompt: result.prompt, events: withoutNoOp))
    XCTAssertEqual(ResultPerformanceTrace.points(prompt: result.prompt, events: events, duration: 3),
      ResultPerformanceTrace.points(prompt: result.prompt, events: withoutNoOp, duration: 3))
    let displays = SavedTextInputHistoryPolicy.displayWords(in: result.prompt)
    XCTAssertEqual(SavedTextInputHistoryPolicy.progressWordCount(displays: displays, events: events),
      SavedTextInputHistoryPolicy.progressWordCount(displays: displays, events: withoutNoOp))
  }
}
