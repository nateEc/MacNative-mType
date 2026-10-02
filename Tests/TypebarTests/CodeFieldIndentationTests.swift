import AppKit
import XCTest
@testable import Typebar

final class CodeFieldIndentationTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 905_100_000)
  private func configuration(unindent: Bool = true, words: Int = 10) -> TestConfiguration {
    .words(words, rules: .init(codeUnindentOnBackspace: unindent), language: .codeSwift)
  }

  private func ended(_ session: TypingSession) throws -> CompletedTestResult {
    var copy = session
    copy.bailOut(at: start.addingTimeInterval(4))
    return try XCTUnwrap(copy.result(at: start.addingTimeInterval(4)))
  }

  func testCorrectSpaceAutoInsertsCurrentFieldTabsWithoutWaitingForANewline() throws {
    var input = TypingSession(configuration: configuration(words: 3), prompt: "ab \t\tgo() tail")
    input.insertBatch("ab ", at: start)
    XCTAssertEqual(input.typed, "ab \t\t")
    XCTAssertEqual(input.errors, 0)
    let result = try ended(input)
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 5)
    let automatic = result.replayEvents.filter(\.automatic)
    XCTAssertEqual(automatic.map(\.text), ["\t", "\t"])
    XCTAssertTrue(automatic.allSatisfy { $0.offset == 0 && $0.kind == .insert })
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 0), input.typed)
    input.insertBatch("go() tail", at: start.addingTimeInterval(1))
    XCTAssertEqual(input.typed, "ab \t\tgo() tail")
    XCTAssertEqual(input.outcome, .completed)
  }

  func testLineInternalTabOnlyFieldCharacterDeleteReturnsToPreviousField() throws {
    var input = TypingSession(configuration: configuration(), prompt: "ab next tail")
    input.insertBatch("ab \t", at: start)
    let before = try ended(input).inputMetrics
    input.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(input.typed, "ab")
    XCTAssertEqual(input.errors, 0)
    let result = try ended(input)
    XCTAssertEqual(result.inputMetrics?.totalAttempts, before?.totalAttempts)
    XCTAssertEqual(result.inputMetrics?.correctAttempts, before?.correctAttempts)
    let deletes = result.replayEvents.filter { $0.kind == .delete }
    XCTAssertEqual(deletes.count, 2)
    XCTAssertEqual(deletes.first?.wordDeletionCount, 1)
    XCTAssertEqual(deletes.last?.characterDeletionCount, 1)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 1), "ab")
  }

  func testLineInternalTabOnlyFieldWordDeleteClearsPreviousFieldNotJustCurrentTabs() throws {
    var input = TypingSession(configuration: configuration(), prompt: "first ab next tail")
    input.insertBatch("first ab \t\t\t", at: start)
    input.deleteWordBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(input.typed, "first ")
    let result = try ended(input)
    let deletes = result.replayEvents.filter { $0.kind == .delete }
    XCTAssertEqual(deletes.count, 6)
    XCTAssertEqual(deletes.map(\.wordDeletionCount), [3, nil, nil, nil, nil, nil])
    XCTAssertEqual(deletes.map(\.characterDeletionCount), [nil, nil, nil, 3, nil, nil])
    let actions = TypingReplay.actions(events: result.replayEvents).filter { $0.kind != .insert }
    XCTAssertEqual(actions.map(\.kind), [.deleteWord, .deleteCharacter])
    XCTAssertEqual(actions.map { $0.primitives.count }, [3, 3])
    XCTAssertEqual(TypingReplay.soundCues(prompt: result.prompt, events: result.replayEvents,
      after: 0.5, through: 1.5, configuration: result.configuration), [.click, .click])
  }

  func testRegularNewlineWholeFieldNavigationAlreadyClearsPreviousWordAsPositiveControl() throws {
    var input = TypingSession(configuration: configuration(), prompt: "if ready {\n\tgo()\n}")
    input.insertBatch("if ready {\n", at: start)
    input.deleteWordBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(input.typed, "if ready ")
    XCTAssertEqual(TypingReplay.typedText(events: try ended(input).replayEvents, through: 1), input.typed)
  }

  func testManualLeadingTabSchedulesRemainingTabsAndKeepsHistoricalAttempts() throws {
    var input = TypingSession(configuration: configuration(), prompt: "\t\tgo() tail")
    input.insert("\t", at: start)
    XCTAssertEqual(input.typed, "\t\t")
    let result = try ended(input)
    XCTAssertEqual(result.replayEvents.map(\.automatic), [false, true])
    XCTAssertEqual(result.inputMetrics?.correctAttempts, 2)
    XCTAssertEqual(result.inputMetrics?.totalAttempts, 2)
    input.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(input.typed, "")
    XCTAssertEqual(try ended(input).inputMetrics?.totalAttempts, 2)
  }

  func testIncorrectEarlyCommitDoesNotAutoIndentDespiteMappedSeparatorCursor() throws {
    var input = TypingSession(configuration: configuration(), prompt: "abcd \t\tgo() tail")
    input.insertBatch("ab ", at: start)
    XCTAssertEqual(input.typed, "ab ")
    XCTAssertFalse(try ended(input).replayEvents.contains(where: \.automatic))
    input.insert("\t", at: start.addingTimeInterval(1))
    XCTAssertEqual(input.typed, "ab \t\t")
    input.deleteBackward(at: start.addingTimeInterval(2))
    XCTAssertEqual(input.typed, "ab")
  }

  func testAutoIndentRequiresTabLeadingTargetAndCorrectTriggerNotCorrectWholeField() throws {
    var inner = TypingSession(configuration: configuration(), prompt: "g\t\tgo() tail")
    inner.insert("g", at: start)
    XCTAssertEqual(inner.typed, "g")
    var wrong = TypingSession(configuration: configuration(), prompt: "\tX\t\tgo() tail")
    wrong.insert("\t", at: start)
    wrong.insert("x", at: start)
    wrong.insert("\t", at: start.addingTimeInterval(1))
    XCTAssertEqual(wrong.typed, "\tx\t\t")
    XCTAssertEqual(try ended(wrong).replayEvents.filter(\.automatic).map(\.text), ["\t"])
    var forced = TypingSession(configuration: configuration(), prompt: "\t\tgo() tail")
    forced.insert("\t", forceError: true, at: start)
    XCTAssertEqual(forced.typed, "\t")
  }

  func testUnindentUsesTextPrefixAfterDeletionNotPriorWordLengthOrForcedFlags() throws {
    var input = TypingSession(configuration: configuration(), prompt: "longer \tgo() tail")
    input.insertBatch("x ", at: start)
    input.insert("\t", forceError: true, at: start)
    input.insert("\t", at: start)
    input.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(input.typed, "x")
    XCTAssertEqual(try ended(input).inputMetrics?.totalAttempts, 4)
  }

  func testIncorrectRemainingTabsStayInFieldUntilPrefixMatches() throws {
    var input = TypingSession(configuration: configuration(), prompt: "ab next tail")
    input.insertBatch("ab \t\t", at: start)
    input.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(input.typed, "ab \t")
    input.deleteBackward(at: start.addingTimeInterval(2))
    XCTAssertEqual(input.typed, "ab")
  }

  func testRetainedLeadingAndStoppedSeparatorsAreNotFieldBoundaries() throws {
    var leading = TypingSession(configuration: .words(10,
      rules: .init(strictSpace: true, codeUnindentOnBackspace: true), language: .codeSwift),
      prompt: "\t\tgo() tail")
    leading.insertBatch(" \t", at: start)
    XCTAssertEqual(leading.typed, " \t")
    leading.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(leading.typed, " ")
    var stopped = TypingSession(configuration: .words(10,
      rules: .init(stopOnErrorMode: .word, codeUnindentOnBackspace: true), language: .codeSwift),
      prompt: "ab \t\tgo() tail")
    stopped.insertBatch("a \t", at: start)
    stopped.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(stopped.typed, "a ")
  }

  func testDisabledUnindentAndNonCodeLanguageKeepOrdinaryDeletion() {
    var disabled = TypingSession(configuration: configuration(unindent: false), prompt: "ab next tail")
    disabled.insertBatch("ab \t", at: start)
    disabled.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(disabled.typed, "ab ")
    var ordinary = TypingSession(configuration: .words(10,
      rules: .init(codeUnindentOnBackspace: true)), prompt: "ab \t\tgo() tail")
    ordinary.insertBatch("ab ", at: start)
    XCTAssertEqual(ordinary.typed, "ab ")
  }

  func testKnownNoSpaceFieldsAutoIndentAndNavigateWithoutVisibleSeparator() throws {
    var input = TypingSession(configuration: configuration().with(modifiers: [.noSpaces]),
      prompt: "ab\t\tgo()tail", noSpaceWordEndIndices: [2, 8, 12],
      noSpaceTargetWords: ["ab", "\t\tgo()", "tail"])
    input.insertBatch("ab", at: start)
    XCTAssertEqual(input.typed, "ab\t\t")
    input.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(input.typed, "a")
    let result = try ended(input)
    XCTAssertEqual(result.replayEvents.filter { $0.kind == .delete }.count, 3)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 1), "a")
  }

  func testNoSpaceTabClearingNeverConsumesPreviousFieldsTrailingTab() throws {
    for whole in [false, true] {
      var input = TypingSession(configuration: configuration().with(modifiers: [.noSpaces]),
        prompt: "ab\txxtail", noSpaceWordEndIndices: [3, 5, 9],
        noSpaceTargetWords: ["ab\t", "xx", "tail"])
      input.insertBatch("ab\t\t", at: start)
      if whole { input.deleteWordBackward(at: start.addingTimeInterval(1)) }
      else { input.deleteBackward(at: start.addingTimeInterval(1)) }
      XCTAssertEqual(input.typed, whole ? "" : "ab")
      let deletes = try ended(input).replayEvents.filter { $0.kind == .delete }
      XCTAssertEqual(deletes.first?.wordDeletionCount, 1)
      XCTAssertEqual(deletes.dropFirst().first?.characterDeletionCount, whole ? 3 : 1)
    }
  }

  func testFieldActionsSurviveResultEncodingAndSeekWithoutRewritingStoredMetrics() throws {
    var input = TypingSession(configuration: configuration(), prompt: "first ab next tail")
    input.insertBatch("first ab \t\t", at: start)
    input.deleteWordBackward(at: start.addingTimeInterval(1))
    let original = try ended(input)
    let restored = try JSONDecoder().decode(CompletedTestResult.self,
      from: JSONEncoder().encode(original))
    XCTAssertEqual(restored.inputMetrics, original.inputMetrics)
    XCTAssertEqual(restored.replayEvents, original.replayEvents)
    XCTAssertEqual(TypingReplay.typedText(events: restored.replayEvents, through: 0), "first ab \t\t")
    XCTAssertEqual(TypingReplay.typedText(events: restored.replayEvents, through: 1), "first ")
    XCTAssertEqual(TypingReplay.actions(events: restored.replayEvents).filter { $0.kind != .insert }
      .map(\.kind), [.deleteWord, .deleteCharacter])
  }

  func testAllCodeLanguagesApplyFieldNavigationInsideALine() {
    for language in TypingLanguage.allCases.filter(\.isCodeLanguage) {
      var input = TypingSession(configuration: .words(10,
        rules: .init(codeUnindentOnBackspace: true), language: language),
        prompt: "first ab \tgo() tail")
      input.insertBatch("first ab ", at: start)
      XCTAssertEqual(input.typed, "first ab \t", language.rawValue)
      input.deleteWordBackward(at: start.addingTimeInterval(1))
      XCTAssertEqual(input.typed, "first ", language.rawValue)
    }
  }

  func testEmptyPreviousFieldIsReopenedWithoutDeletingEarlierWords() throws {
    for whole in [false, true] {
      var input = TypingSession(configuration: configuration(), prompt: "first  \tgo() tail")
      input.insertBatch("first  ", at: start)
      XCTAssertEqual(input.typed, "first  \t")
      if whole { input.deleteWordBackward(at: start.addingTimeInterval(1)) }
      else { input.deleteBackward(at: start.addingTimeInterval(1)) }
      XCTAssertEqual(input.typed, "first ")
      XCTAssertEqual(TypingReplay.typedText(events: try ended(input).replayEvents, through: 1), "first ")
    }
  }

  func testConfidenceMaximumBlocksFieldDeletionButOnAllowsTabNavigation() {
    for confidence in [ConfidenceMode.off, .on, .maximum] {
      var input = TypingSession(configuration: .words(10,
        rules: .init(confidenceMode: confidence, codeUnindentOnBackspace: true), language: .codeSwift),
        prompt: "first ab \tgo() tail")
      input.insertBatch("first ab ", at: start)
      input.deleteWordBackward(at: start.addingTimeInterval(1))
      XCTAssertEqual(input.typed, confidence == .maximum ? "first ab \t" : "first ")
    }
  }

  @MainActor
  func testUnopenedNativeResponderDeliversFieldInsertAndBothDeleteCommands() {
    for whole in [false, true] {
      var input = TypingSession(configuration: configuration(), prompt: "first ab \tgo() tail")
      let view = TypingInputView(frame: .zero)
      view.onInsert = { text, forced in input.insertBatch(text, forceError: forced, at: self.start) }
      view.onDelete = { input.deleteBackward(at: self.start.addingTimeInterval(1)) }
      view.onDeleteWord = { input.deleteWordBackward(at: self.start.addingTimeInterval(1)) }
      view.insertText("first ab ", replacementRange: .init())
      XCTAssertEqual(input.typed, "first ab \t")
      view.doCommand(by: whole ? #selector(NSResponder.deleteWordBackward(_:))
        : #selector(NSResponder.deleteBackward(_:)))
      XCTAssertEqual(input.typed, whole ? "first " : "first ab")
    }
  }
}
