@preconcurrency import AppKit
import XCTest
@testable import Typebar

final class ZenReplayAccessTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 400)
  private var configuration: TestConfiguration {
    .init(mode: .zen, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init())
  }

  private func result() throws -> CompletedTestResult {
    var input = TestSessionFactory.make(configuration: configuration)
    input.insertBatch("a b", at: start)
    input.finishZen(at: start.addingTimeInterval(15))
    return try XCTUnwrap(input.result())
  }

  func testFinishedZenExposesReplayWithNoGeneratedPrompt() throws {
    let result = try result()
    XCTAssertEqual(result.prompt, "")
    XCTAssertTrue(ResultReplayAvailability.isAvailable(prompt: result.prompt, events: result.replayEvents,
      configuration: result.configuration))
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: result.prompt, events: result.replayEvents,
      configuration: result.configuration))
    XCTAssertEqual(plan.frame(through: 15).presentation.text, "a b")
    XCTAssertTrue(plan.frame(through: 15).presentation.glyphs.allSatisfy { $0.state == .correct })
  }

  func testRestoredZenResultHasTheSameReplayAvailability() throws {
    let original = try result()
    let restored = try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(original))
    XCTAssertEqual(restored, original)
    XCTAssertTrue(ResultReplayAvailability.isAvailable(prompt: restored.prompt, events: restored.replayEvents,
      configuration: restored.configuration))
  }

  func testLegacyZenWithoutFieldsRendersAcceptedInputWithoutTargetErrors() {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "ab"),
      .init(offset: 1, kind: .delete, text: ""),
      .init(offset: 2, kind: .insert, text: "c")]
    XCTAssertNil(FieldReplayPlan.make(prompt: "", events: events, configuration: configuration))
    let glyphs = FieldReplayPresentation.glyphs(prompt: "", events: events, through: 2,
      configuration: configuration)
    XCTAssertEqual(String(glyphs.map(\.character)), "ac")
    XCTAssertEqual(glyphs.map(\.state), [.correct, .correct])
    XCTAssertTrue(ResultReplayAvailability.isAvailable(prompt: "", events: events, configuration: configuration))
  }

  func testOrdinaryUnknownAndEmptyTapesKeepExistingVisibility() {
    let events: [TypingReplayEvent] = [.init(offset: 0, kind: .insert, text: "a")]
    for mode in TestMode.allCases where mode != .zen {
      let config = TestConfiguration(mode: mode, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init())
      XCTAssertFalse(ResultReplayAvailability.isAvailable(prompt: "", events: events, configuration: config))
      XCTAssertTrue(ResultReplayAvailability.isAvailable(prompt: "a", events: events, configuration: config))
    }
    XCTAssertFalse(ResultReplayAvailability.isAvailable(prompt: "", events: events, configuration: nil))
    XCTAssertFalse(ResultReplayAvailability.isAvailable(prompt: "", events: [], configuration: configuration))
    XCTAssertFalse(ResultReplayAvailability.isAvailable(prompt: "a", events: [], configuration: .words(1)))
    XCTAssertEqual(TypingReplay.inputGlyphs(prompt: "", events: events, through: 0).map(\.state), [.extra])
  }

  func testZeroTimeLegacyInsertionCanPlayWithoutInventingFieldActions() {
    let events: [TypingReplayEvent] = [.init(offset: 0, kind: .insert, text: "ab")]
    XCTAssertNil(FieldReplayPlan.make(prompt: "", events: events, configuration: configuration))
    XCTAssertTrue(ResultReplayAvailability.canPlay(duration: 0, events: events, fieldPlan: nil))
    let stopped: [TypingReplayEvent] = [.init(offset: 0, kind: .insert, text: "x", inputStopped: true)]
    XCTAssertFalse(ResultReplayAvailability.canPlay(duration: 0, events: stopped, fieldPlan: nil))
    XCTAssertFalse(ResultReplayAvailability.canPlay(duration: 0, events: [], fieldPlan: nil))
    XCTAssertTrue(ResultReplayAvailability.canPlay(duration: 1, events: stopped, fieldPlan: nil))
  }

  func testHistoryRecordUsesItsStoredZenConfigurationWithoutChangingPayloads() throws {
    let original = try result()
    let record = TestResultRecord(result: original)
    let configurationData = record.configurationData
    let replayData = record.replayEventsData
    XCTAssertTrue(ResultReplayAvailability.isAvailable(prompt: record.prompt, events: record.replayEvents,
      configuration: record.configuration))
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: record.prompt, events: record.replayEvents,
      configuration: record.configuration))
    _ = plan.frame(through: 15)
    XCTAssertEqual(record.configurationData, configurationData)
    XCTAssertEqual(record.replayEventsData, replayData)
    XCTAssertEqual(record.portableResult, original)
  }

  func testLegacyAdmissionFlagsDoNotControlReplayOrGetUpgraded() throws {
    for admission: Bool? in [nil, false, true] {
      var config = configuration
      config.zenUsesSourceInputAdmission = admission
      var input = TypingSession(configuration: config, prompt: "")
      input.insertBatch("a b", at: start)
      input.bailOut(at: start.addingTimeInterval(15))
      let saved = try XCTUnwrap(input.result())
      XCTAssertTrue(ResultReplayAvailability.isAvailable(prompt: "", events: saved.replayEvents,
        configuration: saved.configuration))
      XCTAssertEqual(saved.configuration.zenUsesSourceInputAdmission, admission)
      XCTAssertEqual(saved.outcome, .bailedOut)
      XCTAssertFalse(ResultSavingPolicy.shouldPersist(outcome: saved.outcome, enabled: true))
    }
  }

  func testStoppedOnlyZenTapeHasNoInventedCharactersActionsOrSounds() throws {
    let events: [TypingReplayEvent] = [.init(offset: 0, kind: .insert, text: "x", inputStopped: true,
      inputField: .init(index: 0, value: ""))]
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: "", events: events, configuration: configuration))
    XCTAssertTrue(ResultReplayAvailability.isAvailable(prompt: "", events: events, configuration: configuration))
    XCTAssertFalse(ResultReplayAvailability.canPlay(duration: 0, events: events, fieldPlan: plan))
    XCTAssertEqual(plan.frame(through: 1).presentation.text, "")
    XCTAssertTrue(plan.actions.isEmpty)
    XCTAssertTrue(TypingReplay.soundTimeline(prompt: "", events: events, configuration: configuration).isEmpty)
  }

  func testLegacyFallbackPreservesUnicodeControlsStoppedInputAndRawTape() throws {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "🙂e\u{301}\t\n"),
      .init(offset: 1, kind: .insert, text: "x", inputStopped: true),
      .init(offset: 2, kind: .delete, text: ""),
      .init(offset: 3, kind: .insert, text: "尾")]
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    let bytes = try encoder.encode(events)
    let glyphs = FieldReplayPresentation.glyphs(prompt: "", events: events, through: 3,
      configuration: configuration)
    XCTAssertEqual(String(glyphs.map(\.character)), "🙂e\u{301}\t尾")
    XCTAssertTrue(glyphs.allSatisfy { $0.state == .correct })
    XCTAssertEqual(try encoder.encode(events), bytes)
    XCTAssertNil(FieldReplayPlan.make(prompt: "", events: events, configuration: configuration))
  }

  func testZenSeekResumesEqualTimeActionsWithoutReplayingConsumedCues() throws {
    let saved = try result()
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: "", events: saved.replayEvents,
      configuration: saved.configuration))
    XCTAssertTrue(ResultReplayAvailability.canPlay(duration: 0, events: saved.replayEvents, fieldPlan: plan))
    let seek = try XCTUnwrap(plan.seek(.init(word: 1, position: 0)))
    XCTAssertEqual(seek.frame.coordinate, .init(word: 1, position: 0))
    var frame = seek.frame
    XCTAssertEqual(plan.advance(&frame, through: 0), [.click])
    XCTAssertEqual(plan.advance(&frame, through: 1), [])
    XCTAssertEqual(frame.presentation.text, "a b")
    XCTAssertEqual(frame, plan.frame(through: 1))
    XCTAssertEqual(plan.initialFrame.presentation.glyphs.map(\.state), [.pending, .pending, .pending])
  }

  func testZenDeletionReplaysAgainstTheFinalSavedInputWithoutTargetErrors() throws {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "a", inputField: .init(index: 0, value: "a")),
      .init(offset: 1, kind: .insert, text: "b", inputField: .init(index: 0, value: "ab")),
      .init(offset: 2, kind: .delete, text: "", inputField: .init(index: 0, value: "a")),
      .init(offset: 3, kind: .insert, text: "c", inputField: .init(index: 0, value: "ac"))]
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: "", events: events, configuration: configuration))
    XCTAssertEqual(plan.initialFrame.presentation.text, "ac")
    XCTAssertEqual(plan.frame(through: 1).presentation.glyphs.map(\.state), [.correct, .correct])
    XCTAssertEqual(plan.frame(through: 2).presentation.glyphs.map(\.state), [.correct, .pending])
    XCTAssertEqual(plan.frame(through: 3).presentation.glyphs.map(\.state), [.correct, .correct])
    var frame = plan.initialFrame
    XCTAssertEqual(plan.advance(&frame, through: 3), Array(repeating: .click, count: 4))
    XCTAssertEqual(frame.presentation.text, "ac")
    XCTAssertTrue(frame.presentation.errorIndices.isEmpty)
  }

  func testThousandFieldZenPlaybackRetainsAllTextAndSingleConsumption() throws {
    var input = TestSessionFactory.make(configuration: configuration)
    let text = String(repeating: "a ", count: 1_000) + "z"
    input.insertBatch(text, at: start)
    input.finishZen(at: start.addingTimeInterval(60))
    let saved = try XCTUnwrap(input.result())
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: "", events: saved.replayEvents,
      configuration: saved.configuration))
    XCTAssertEqual(plan.initialFrame.fields.count, 1_001)
    var frame = plan.initialFrame
    let cues = plan.advance(&frame, through: 60)
    XCTAssertEqual(cues, Array(repeating: .click, count: 3_001))
    XCTAssertEqual(plan.advance(&frame, through: 60), [])
    XCTAssertEqual(frame.presentation.text, text)
    XCTAssertEqual(frame.coordinate, .init(word: 1_000, position: 1))
  }

  @MainActor func testLegacyZenFallbackUpdatesActualAppKitTextWithoutWindowOrInventedTarget() {
    let events: [TypingReplayEvent] = [.init(offset: 0, kind: .insert, text: "🙂a\n")]
    let glyphs = FieldReplayPresentation.glyphs(prompt: "", events: events, through: 1,
      configuration: configuration)
    let view = ReplayInputTextView()
    XCTAssertTrue(view.update(glyphs: glyphs))
    XCTAssertEqual(view.string, "🙂a\n")
    XCTAssertFalse(view.update(glyphs: glyphs))
    XCTAssertTrue(view.update(glyphs: []))
    XCTAssertEqual(view.string, "等待播放")
  }

  func testCapturedEmptyZenInsertStillAdvancesTheSourceCursorAndClick() throws {
    for correctness: [Bool]? in [nil, []] {
      let events: [TypingReplayEvent] = [.init(offset: 0, kind: .insert, text: "",
        inputField: .init(index: 0, value: ""), inputCorrectness: correctness)]
      let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: "", events: events, configuration: configuration))
      var frame = plan.initialFrame
      XCTAssertEqual(plan.advance(&frame, through: 0), [.click])
      XCTAssertEqual(frame.coordinate, .init(word: 0, position: 1))
      XCTAssertEqual(frame.presentation.text, "")
      XCTAssertTrue(ResultReplayAvailability.canPlay(duration: 0, events: events, fieldPlan: plan))
    }
  }

  func testCapturedEmptyZenInsertAfterNavigationRetainsTheEmptyFieldAndOneAdvance() throws {
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, text: "a", inputField: .init(index: 0, value: "a")),
      .init(offset: 1, kind: .insert, text: "", inputField: .init(index: 1, value: ""))]
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: "", events: events, configuration: configuration))
    XCTAssertEqual(plan.initialFrame.fields.count, 2)
    var frame = plan.initialFrame
    XCTAssertEqual(plan.advance(&frame, through: 1), [.click, .click, .click])
    XCTAssertEqual(frame.coordinate, .init(word: 1, position: 1))
    XCTAssertEqual(frame.presentation.text, "a")
    XCTAssertEqual(SavedTextInputHistoryPolicy.inputFields(events: events), ["a", ""])
  }
}
