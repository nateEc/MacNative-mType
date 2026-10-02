@preconcurrency import AppKit
import XCTest
@testable import Typebar

final class FieldReplayPresentationTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 907_600_000)

  private func delayedResult(finish: Bool = false) throws -> CompletedTestResult {
    var input = TypingSession(configuration: .words(2,
      rules: .init(deleteOnErrorMode: .letter), language: .codeSwift), prompt: "a \tb")
    input.insertBatch("a ", at: start, defersAutomaticInput: true)
    input.insertBatch("\t", at: start.addingTimeInterval(1), defersAutomaticInput: true)
    XCTAssertEqual(input.processNextAutomaticInput(for: input.automaticInputAttemptID,
      executedAt: start.addingTimeInterval(3)), [false])
    if finish { input.insertBatch("\tb", at: start.addingTimeInterval(4)) }
    else { input.bailOut(at: start.addingTimeInterval(4)) }
    return try XCTUnwrap(input.result())
  }

  func testDelayedRecoveryLeavesPriorTargetsMarkedAndCurrentFieldUnmarked() throws {
    let result = try delayedResult()
    let glyphs = FieldReplayPresentation.glyphs(prompt: result.prompt, events: result.replayEvents, through: 0)
    XCTAssertEqual(String(glyphs.map(\.character)), "a \tb")
    XCTAssertEqual(glyphs.map(\.state), [.correct, .correct, .pending, .pending])
  }

  func testLaterManualInputMarksTheTargetRatherThanDeletingThePriorCommit() throws {
    let result = try delayedResult()
    let glyphs = FieldReplayPresentation.glyphs(prompt: result.prompt, events: result.replayEvents, through: 1)
    XCTAssertEqual(String(glyphs.map(\.character)), "a \tb")
    XCTAssertEqual(glyphs.map(\.state), [.correct, .correct, .correct, .pending])
  }

  func testLaterCorrectActionsMarkTargetsEvenWhenSourceCursorPassesTheirEnd() throws {
    let result = try delayedResult(finish: true)
    let glyphs = FieldReplayPresentation.glyphs(prompt: result.prompt, events: result.replayEvents, through: 4)
    XCTAssertEqual(String(glyphs.map(\.character)), "a \tb")
    XCTAssertEqual(glyphs.map(\.state), [.correct, .correct, .correct, .correct])
  }

  private func inserted(_ text: String, value: String, field: Int = 0, at: Double,
    stopped: Bool = false, forced: Bool = false) -> TypingReplayEvent {
    .init(offset: at, kind: .insert, text: text, forceError: forced, inputStopped: stopped,
      inputField: .init(index: field, value: value))
  }

  private func deleted(value: String, field: Int = 0, at: Double, count: Int? = nil) -> TypingReplayEvent {
    .init(offset: at, kind: .delete, text: "", wordDeletionCount: count,
      inputField: .init(index: field, value: value))
  }

  func testDelayedFrameCursorIsNotTheFinalFieldSnapshotLength() throws {
    let result = try delayedResult(finish: true)
    XCTAssertEqual(result.replayEvents.map { $0.inputField?.value },
      ["a", "a ", "\t\t", "\t", "", "\t", "\t", "\tb"])
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: result.prompt, events: result.replayEvents))
    let frame = plan.frame(through: 4)
    XCTAssertEqual(frame.coordinate, .init(word: 1, position: 3))
    XCTAssertEqual(result.replayEvents.last?.inputField?.value.utf16.count, 2)
  }

  func testInitialFrameIsPendingAndDoesNotApplyZeroTimeActions() throws {
    let result = try delayedResult()
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: result.prompt, events: result.replayEvents))
    XCTAssertEqual(plan.initialFrame.presentation.text, result.prompt)
    XCTAssertEqual(plan.initialFrame.presentation.glyphs.map(\.state), Array(repeating: .pending, count: 4))
    XCTAssertEqual(plan.frame(through: -1), plan.initialFrame)
    XCTAssertEqual(plan.initialFrame.nextActionIndex, 0)
  }

  func testWrongLetterMarksTargetAndAnExtraIsRemovedByResize() throws {
    let events = [inserted("x", value: "x", at: 0), inserted("y", value: "xy", at: 1),
      inserted("z", value: "xyz", at: 2), deleted(value: "x", at: 3)]
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: "ab", events: events))
    let wrong = plan.frame(through: 2).presentation
    XCTAssertEqual(wrong.text, "abz")
    XCTAssertEqual(wrong.glyphs.map(\.state), [.incorrect, .incorrect, .extra])
    let resized = plan.frame(through: 3)
    XCTAssertEqual(resized.presentation.text, "ab")
    XCTAssertEqual(resized.presentation.glyphs.map(\.state), [.incorrect, .pending])
    XCTAssertEqual(resized.position, 1)
  }

  func testMultiCharacterExtraIsOneActionCoordinateWithSeveralDisplaySpans() throws {
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: "a", events: [
      inserted("a", value: "a", at: 0), inserted("xy", value: "axy", at: 1)]))
    let frame = plan.frame(through: 1)
    XCTAssertEqual(frame.position, 2)
    XCTAssertEqual(frame.fields[0].letters.count, 2)
    XCTAssertEqual(frame.presentation.text, "axy")
    XCTAssertEqual(frame.presentation.coordinates.map(\.position), [0, 1, 1])
  }

  func testResizeIsFieldLocalAndDoesNotRemoveEarlierTargetLetters() throws {
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: "a bc", events: [
      inserted("a", value: "a", at: 0), inserted(" ", value: "a ", at: 0),
      inserted("b", value: "b", field: 1, at: 1), deleted(value: "", field: 1, at: 2)]))
    XCTAssertEqual(plan.frame(through: 2).presentation.glyphs.map(\.state),
      [.correct, .correct, .pending, .pending])
  }

  func testSourceNetPrefixOmitsFinalRegressedWordAndIgnoresItsActions() throws {
    // Probed original DOM functions initialize only the net final prefix.
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: "a b", events: [
      inserted("a", value: "a", at: 0), inserted(" ", value: "a ", at: 0),
      inserted("b", value: "b", field: 1, at: 1), deleted(value: "a", at: 2)]))
    XCTAssertEqual(plan.initialFrame.fields.count, 1)
    var frame = plan.initialFrame
    XCTAssertEqual(plan.advance(&frame, through: 2), [.click, .click, .error])
    XCTAssertEqual(frame.coordinate, .init(word: 1, position: 0))
    XCTAssertEqual(frame.presentation.text, "a ")
    XCTAssertEqual(frame.presentation.errorIndices, [0, 1])
    XCTAssertEqual(frame.nextActionIndex, plan.actions.count)
  }

  func testBackWordClearsErrorAndUsesLastMarkedTargetWithoutResize() throws {
    let events = [inserted("x", value: "x", at: 0), inserted(" ", value: "x ", at: 1),
      inserted("b", value: "b", field: 1, at: 2), deleted(value: "", at: 3),
      inserted("b", value: "b", field: 1, at: 4)]
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: "a bc", events: events))
    XCTAssertEqual(plan.frame(through: 2).presentation.errorIndices, [0, 1])
    let back = plan.frame(through: 3)
    XCTAssertEqual(back.coordinate, .init(word: 0, position: 2))
    XCTAssertEqual(back.presentation.glyphs.prefix(2).map(\.state), [.incorrect, .correct])
    XCTAssertTrue(back.presentation.errorIndices.isEmpty)
    XCTAssertEqual(plan.actions.filter { if case .resize = $0.kind { return true }; return false }.count, 0)
  }

  func testGroupedRegressionUsesFinalSnapshotOnlyOnce() throws {
    let events = [inserted("a", value: "a", at: 0), inserted(" ", value: "a ", at: 0),
      inserted("b", value: "b", field: 1, at: 1), deleted(value: "", field: 1, at: 2, count: 2),
      deleted(value: "a", at: 2), inserted("b", value: "b", field: 1, at: 3)]
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: "a bc", events: events))
    XCTAssertEqual(plan.actions.filter { $0.offset == 2 }.map(\.kind), [.retreat])
    XCTAssertEqual(plan.frame(through: 2).coordinate, .init(word: 0, position: 2))
  }

  func testStoppedInsertNavigatesWithoutAddingLetter() throws {
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: "a bc", events: [
      inserted("a", value: "a", at: 0), inserted(" ", value: "a ", at: 0),
      inserted("x", value: "", field: 1, at: 1, stopped: true)]))
    let frame = plan.frame(through: 1)
    XCTAssertEqual(frame.coordinate, .init(word: 1, position: 0))
    XCTAssertEqual(frame.presentation.glyphs.map(\.state), [.correct, .correct, .pending, .pending])
  }

  func testSeekStopsBeforeTheClickedLetterInsideSameTimestampActions() throws {
    let result = try delayedResult()
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: result.prompt, events: result.replayEvents))
    let seek = try XCTUnwrap(plan.seek(.init(word: 1, position: 0)))
    XCTAssertEqual(seek.frame.nextActionIndex, 3)
    XCTAssertEqual(seek.nextOffset, 0)
    XCTAssertEqual(seek.frame.presentation.glyphs.map(\.state), [.correct, .correct, .pending, .pending])
    var frame = seek.frame
    XCTAssertEqual(plan.advance(&frame, through: 0), [.error, .click, .click])
    XCTAssertEqual(plan.advance(&frame, through: 0), [])
    XCTAssertEqual(frame, plan.frame(through: 0))
  }

  func testSeekUsesFirstCursorCrossingBeforeAResizeRewindsIt() throws {
    let result = try delayedResult()
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: result.prompt, events: result.replayEvents))
    let seek = try XCTUnwrap(plan.seek(.init(word: 1, position: 1)))
    XCTAssertEqual(seek.frame.nextActionIndex, 4)
    XCTAssertEqual(seek.nextOffset, 0)
    XCTAssertEqual(seek.frame.presentation.glyphs[2].state, .incorrect)
    XCTAssertNil(plan.seek(.init(word: 1, position: 2)))
    XCTAssertNil(plan.seek(.init(word: -1, position: 0)))
    XCTAssertNil(plan.seek(.init(word: 0, position: -1)))
  }

  func testSeekAtLastTimestampStillHasAnUnplayedAction() throws {
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: "ab", events: [
      inserted("a", value: "a", at: 0), inserted("b", value: "ab", at: 4)]))
    let seek = try XCTUnwrap(plan.seek(.init(word: 0, position: 1)))
    XCTAssertEqual(seek.nextOffset, 4)
    XCTAssertEqual(seek.frame.nextActionIndex, 1)
    var frame = seek.frame
    XCTAssertEqual(plan.advance(&frame, through: 4), [.click])
    XCTAssertEqual(frame.presentation.glyphs.map(\.state), [.correct, .correct])
    XCTAssertNil(plan.seek(.init(word: 0, position: 2)))
  }

  func testZeroDurationTapeCanSeekAndResumeByIndex() throws {
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: "ab", events: [
      inserted("a", value: "a", at: 0), inserted("b", value: "ab", at: 0)]))
    var frame = try XCTUnwrap(plan.seek(.init(word: 0, position: 1))).frame
    XCTAssertEqual(frame.nextActionIndex, 1)
    XCTAssertEqual(plan.advance(&frame, through: 0), [.click])
    XCTAssertEqual(frame.nextActionIndex, 2)
  }

  func testCombiningTargetUsesCodePointsWhileResizeRetainsNumericUTF16Length() throws {
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: "e\u{301}x", events: [
      inserted("e", value: "e", at: 0), inserted("\u{301}", value: "e\u{301}", at: 1),
      deleted(value: "e\u{301}", at: 2)]))
    XCTAssertEqual(plan.initialFrame.fields[0].letters.count, 3)
    let frame = plan.frame(through: 2)
    XCTAssertEqual(frame.presentation.glyphs.map(\.state), [.correct, .correct, .pending])
    XCTAssertEqual(frame.position, 2)
    let index = ReplayCharacterUTF16Index(characters: frame.presentation.glyphs.map(\.character))
    XCTAssertEqual(index.range(at: 1), NSRange(location: 1, length: 1))
    XCTAssertEqual(index.range(at: 2), NSRange(location: 2, length: 1))
  }

  func testNonBMPResizeDoesNotConvertUTF16LengthToLetterCount() throws {
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: "🙂ab", events: [
      inserted("🙂", value: "🙂", at: 0), inserted("x", value: "🙂x", at: 1),
      deleted(value: "🙂", at: 2)]))
    let frame = plan.frame(through: 2)
    XCTAssertEqual(frame.position, 2)
    XCTAssertEqual(frame.presentation.glyphs.map(\.state), [.correct, .incorrect, .pending])
  }

  func testLegacyMixedUnsegmentedAndInvalidTapesKeepFallbackWithoutInventingFields() throws {
    let result = try delayedResult()
    let legacy = result.replayEvents.map { TypingReplayEvent(offset: $0.offset, kind: $0.kind, text: $0.text) }
    let mixed = [result.replayEvents[0]] + legacy.dropFirst()
    for events in [legacy, mixed, [], [inserted("a", value: "a", field: Int.max, at: 0)],
      [inserted("a", value: "a", field: -1, at: 0)], [inserted("a", value: "a", at: -.infinity)],
      [inserted("a", value: "a", at: .nan)], [inserted("a", value: "a", at: -1)]] {
      XCTAssertNil(FieldReplayPlan.make(prompt: "ab", events: events))
    }
    XCTAssertEqual(FieldReplayPresentation.glyphs(prompt: result.prompt, events: legacy, through: 4),
      TypingReplay.inputGlyphs(prompt: result.prompt, events: legacy, through: 4))
    XCTAssertNil(FieldReplayPlan.make(prompt: "ab", events: [inserted("a", value: "a", at: 0)],
      configuration: .words(2).with(modifiers: [.noSpaces])))
  }

  func testZenUsesSavedInputTargetsWithoutAllocatingMissingFieldIndices() throws {
    let configuration = TestConfiguration(mode: .zen, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init())
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: "", events: [
      inserted("a", value: "a", at: 0), inserted("b", value: "b", field: Int.max, at: 1)],
      configuration: configuration))
    XCTAssertEqual(plan.initialFrame.fields.count, 2)
    XCTAssertEqual(plan.frame(through: 1).presentation.glyphs.map(\.state), [.correct, .correct])
  }

  func testPresentationDoesNotRewriteActualInputOrSavedSnapshots() throws {
    let result = try delayedResult(finish: true)
    let oldText = TypingReplay.typedText(events: result.replayEvents, through: 4)
    let oldFields = SavedTextInputHistoryPolicy.inputFields(events: result.replayEvents)
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: result.prompt, events: result.replayEvents))
    XCTAssertEqual(plan.frame(through: 4).presentation.text, "a \tb")
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 4), oldText)
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: result.replayEvents), oldFields)
    XCTAssertEqual(oldFields, ["a ", "\tb"])
    XCTAssertEqual(oldText, "a\t\tb")
  }

  func testIncrementalThousandWordPlaybackMatchesFreshProjectionWithoutDuplicateCues() throws {
    let prompt = Array(repeating: "a", count: 1_000).joined(separator: " ")
    var events: [TypingReplayEvent] = []
    for index in 0..<1_000 {
      events.append(inserted("a", value: "a", field: index, at: Double(index)))
      if index < 999 { events.append(inserted(" ", value: "a ", field: index, at: Double(index))) }
    }
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: prompt, events: events))
    var frame = plan.initialFrame
    var cueCount = 0
    for time in [0.0, 200, 500, 999] {
      cueCount += plan.advance(&frame, through: time).count
      XCTAssertEqual(frame, plan.frame(through: time))
      XCTAssertEqual(plan.advance(&frame, through: time), [])
    }
    XCTAssertEqual(cueCount, 2_998)
    XCTAssertEqual(frame.nextActionIndex, plan.actions.count)
    XCTAssertEqual(frame.presentation.glyphs.count, 1_999)
    XCTAssertTrue(frame.presentation.glyphs.allSatisfy { $0.state == .correct })
  }

  @MainActor func testNativeTargetPickerUpdatesStatesWhenTextDoesNotChange() throws {
    let picker = ReplayCharacterTextView()
    let glyphs: [TypingPromptGlyph] = [.init(character: "a", state: .correct),
      .init(character: "b", state: .incorrect), .init(character: "x", state: .extra)]
    picker.update(text: "abx", reachableIndices: [0, 1], selectedIndex: nil, glyphs: glyphs, errorIndices: [0, 1])
    let storage = try XCTUnwrap(picker.textStorage)
    XCTAssertEqual(storage.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor, .systemRed)
    XCTAssertEqual(storage.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor, .systemRed)
    XCTAssertEqual(storage.attribute(.underlineColor, at: 0, effectiveRange: nil) as? NSColor, .systemRed)
    XCTAssertEqual(picker.accessibilityLabel(), "回放目标字形")
    picker.update(text: "abx", reachableIndices: [0, 1], selectedIndex: 0,
      glyphs: [
        .init(character: "a", state: .pending), .init(character: "b", state: .pending), .init(character: "x", state: .pending)])
    XCTAssertEqual(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .controlAccentColor)
    XCTAssertEqual(storage.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor, .secondaryLabelColor)
    XCTAssertNil(storage.attribute(.underlineStyle, at: 1, effectiveRange: nil))
    picker.update(text: "abx", reachableIndices: [0], selectedIndex: nil)
    XCTAssertEqual(picker.accessibilityLabel(), "回放目标文本")
    XCTAssertEqual(storage.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor, .tertiaryLabelColor)
  }

  @MainActor func testNativeTargetPickerRetainsScalarStylesAcrossCombinedText() throws {
    let picker = ReplayCharacterTextView()
    picker.update(text: "e\u{301}x", reachableIndices: [0, 1, 2], selectedIndex: nil, glyphs: [
      .init(character: "e", state: .correct), .init(character: "\u{301}", state: .incorrect),
      .init(character: "x", state: .pending)])
    let storage = try XCTUnwrap(picker.textStorage)
    XCTAssertEqual(storage.length, 3)
    XCTAssertEqual(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .labelColor)
    XCTAssertEqual(storage.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor, .systemRed)
    XCTAssertEqual(storage.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor, .secondaryLabelColor)
  }

  func testResizeBeyondTargetAppendsAnExtraWithoutInventingAnIncorrectClass() throws {
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: "a", events: [
      inserted("a", value: "a", at: 0), deleted(value: "abc", at: 1),
      inserted("x", value: "abcx", at: 2)]))
    let frame = plan.frame(through: 2)
    XCTAssertEqual(frame.position, 4)
    XCTAssertEqual(frame.presentation.text, "ax")
    XCTAssertEqual(frame.presentation.glyphs.map(\.state), [.correct, .pending])
    XCTAssertTrue(frame.fields[0].letters[1].extra)
    XCTAssertFalse(frame.fields[0].letters[1].incorrect)
  }

  func testPortableAndArchiveTwelveRecreateFrameAndSeekWithoutRewritingMetrics() throws {
    let result = try delayedResult(finish: true)
    let portable = try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(result))
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [], at: start))
    XCTAssertEqual(archive.version, 12)
    let original = try XCTUnwrap(FieldReplayPlan.make(prompt: result.prompt, events: result.replayEvents))
    for restored in [portable, archive.results[0]] {
      XCTAssertEqual(restored.replayEvents, result.replayEvents)
      XCTAssertEqual(restored.inputMetrics, result.inputMetrics)
      XCTAssertEqual(restored.preciseWpm, result.preciseWpm)
      let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: restored.prompt, events: restored.replayEvents))
      XCTAssertEqual(plan.frame(through: 4), original.frame(through: 4))
      XCTAssertEqual(plan.seek(.init(word: 1, position: 1))?.frame,
        original.seek(.init(word: 1, position: 1))?.frame)
    }
  }

  @MainActor func testNativeTargetPickerDoesNotRebuildIdenticalStyledFrame() throws {
    let picker = ReplayCharacterTextView()
    let glyphs: [TypingPromptGlyph] = [.init(character: "a", state: .correct), .init(character: "b", state: .pending)]
    picker.update(text: "ab", reachableIndices: [0, 1], selectedIndex: nil, glyphs: glyphs)
    let storage = try XCTUnwrap(picker.textStorage)
    let unexpectedEdit = expectation(description: "相同目标字形帧不应重建")
    unexpectedEdit.isInverted = true
    let observer = NotificationCenter.default.addObserver(
      forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: nil
    ) { _ in unexpectedEdit.fulfill() }
    defer { NotificationCenter.default.removeObserver(observer) }
    picker.update(text: "ab", reachableIndices: [0, 1], selectedIndex: nil, glyphs: glyphs)
    wait(for: [unexpectedEdit], timeout: 0.02)
  }

  @MainActor func testNativeTargetPickerRejectsCanonicallyEquivalentButDifferentUTF16Glyphs() throws {
    let picker = ReplayCharacterTextView()
    picker.update(text: "é", reachableIndices: [0], selectedIndex: nil,
      glyphs: [.init(character: "e", state: .incorrect), .init(character: "\u{301}", state: .incorrect)])
    XCTAssertEqual(picker.string.utf16.count, 1)
    XCTAssertEqual(picker.accessibilityLabel(), "回放目标文本")
    XCTAssertEqual(try XCTUnwrap(picker.textStorage).attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .labelColor)
  }
}
