import AppKit
import XCTest
@testable import Typebar

final class LiveInputFeedbackTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 906_100_000)

  private func insert(_ text: String, into input: inout TypingSession,
    forceError: Bool = false, at offset: TimeInterval = 0) -> [Bool] {
    TypingLiveInputFeedback.insertBatch(text, into: &input, forceError: forceError,
      at: start.addingTimeInterval(offset))
  }

  func testCorrectCommitAndEachAutomaticTabHaveSeparateLiveFeedback() {
    var input = TypingSession(configuration: .words(10, language: .codeSwift),
      prompt: "ab\n\t\tgo() tail")
    XCTAssertEqual(insert("ab", into: &input), [true])
    XCTAssertEqual(insert("\n", into: &input, at: 1), [true, true, true])
    XCTAssertEqual(input.typed, "ab\n\t\t")
  }

  func testManualTabAndRemainingAutomaticTabsHaveIndependentFeedback() {
    var input = TypingSession(configuration: .words(10, language: .codeSwift),
      prompt: "\t\t\tgo() tail")
    XCTAssertEqual(insert("\t", into: &input), [true, true, true])
    XCTAssertEqual(input.typed, "\t\t\t")
  }

  func testNestedEllipsisReplacementAndOuterFinalCharacterEachHaveOneFeedback() {
    var input = TypingSession(configuration: .words(10), prompt: "...xy tail")
    XCTAssertEqual(insert("…x", into: &input), [true, true])
    XCTAssertEqual(input.typed, "...x")
  }

  func testNestedDutchReplacementAndOuterFinalCharacterEachHaveOneFeedback() {
    var input = TypingSession(configuration: .words(10, language: .dutch), prompt: "ijxy tail")
    XCTAssertEqual(insert("ĳx", into: &input), [true, true])
    XCTAssertEqual(input.typed, "ijx")
  }

  func testLiveWordUnindentOnlyClicksOnceDespiteTwoReplayActions() throws {
    var input = TypingSession(configuration: .words(10,
      rules: .init(codeUnindentOnBackspace: true), language: .codeSwift),
      prompt: "first ab\n\tgo() tail")
    _ = insert("first ab\n", into: &input)
    XCTAssertEqual(TypingLiveInputFeedback.delete(from: &input, wholeWord: true,
      at: start.addingTimeInterval(1)), [true])
    XCTAssertEqual(input.typed, "first ")
    input.bailOut(at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(input.result())
    XCTAssertEqual(TypingReplay.soundCues(prompt: result.prompt, events: result.replayEvents,
      after: 0.5, through: 1.5), [.click, .click])
  }

  func testAutomaticErrorRecoveryDoesNotAddLiveDeletionClicks() {
    for mode in [DeleteOnErrorMode.letter, .word, .letterHard, .wordHard] {
      var input = TypingSession(configuration: .words(10,
        rules: .init(deleteOnErrorMode: mode)), prompt: "ab cd tail")
      _ = insert("ab ", into: &input)
      XCTAssertEqual(insert("x", into: &input, at: 1), [false], mode.rawValue)
    }
  }

  func testPreInsertionRejectionIsSilentAndDoesNotReplayStaleFeedback() {
    var input = TypingSession(configuration: .words(10), prompt: "abc tail")
    for rejected in ["", " ", "\n"] {
      XCTAssertEqual(insert(rejected, into: &input), [])
    }
    XCTAssertEqual(insert("a", into: &input), [true])
    XCTAssertEqual(insert("\n", into: &input, at: 1), [])
    XCTAssertEqual(insert("", into: &input, at: 2), [])
    XCTAssertEqual(input.typed, "a")
  }

  func testRejectedBatchFinalCharacterDoesNotSoundItsIntermediateAttempt() {
    var input = TypingSession(configuration: .words(10), prompt: "abc tail")
    XCTAssertEqual(insert("a\n", into: &input), [])
    XCTAssertEqual(input.typed, "a")
    XCTAssertEqual(insert("bx", into: &input, at: 1), [false])
    XCTAssertEqual(input.typed, "abx")
  }

  func testStoppedAndOppositeShiftAttemptsStillEmitOneErrorFeedback() {
    var stopped = TypingSession(configuration: .words(10,
      rules: .init(stopOnErrorMode: .letter)), prompt: "abc tail")
    XCTAssertEqual(insert("ax", into: &stopped), [false])
    XCTAssertEqual(stopped.typed, "a")
    var forced = TypingSession(configuration: .words(10,
      rules: .init(oppositeShiftMode: .on)), prompt: "abc tail")
    XCTAssertEqual(insert("a", into: &forced, forceError: true), [false])
    XCTAssertEqual(forced.typed, "")
  }

  func testRetainedWrongSeparatorDoesNotInventNavigationFeedback() {
    var input = TypingSession(configuration: .words(10,
      rules: .init(stopOnErrorMode: .word)), prompt: "ab cd tail")
    XCTAssertEqual(insert("a ", into: &input), [false])
    XCTAssertEqual(input.typed, "a ")
    XCTAssertEqual(insert("x", into: &input, at: 1), [false])
  }

  func testBatchCorrectFinalCharacterDoesNotSoundEarlierMistakes() {
    var input = TypingSession(configuration: .words(10), prompt: "abc tail")
    XCTAssertEqual(insert("xb", into: &input), [true])
    XCTAssertEqual(input.errors, 1)
    XCTAssertEqual(input.preciseAccuracy, 50)
  }

  func testNestedReplacementKeepsOwnFeedbackAndLiteralGlyphDoesNotExpand() {
    var wrong = TypingSession(configuration: .words(10), prompt: "...zy tail")
    XCTAssertEqual(insert("…x", into: &wrong), [true, false])
    var literal = TypingSession(configuration: .words(10), prompt: "…xy tail")
    XCTAssertEqual(insert("…x", into: &literal), [true])
    XCTAssertEqual(literal.typed, "…x")
  }

  func testFinishedRepeatedAndEmptyDeletionDoNotReuseInsertionFeedback() {
    var input = TypingSession(configuration: .words(1), prompt: "abc")
    XCTAssertEqual(insert("abc", into: &input), [true])
    XCTAssertEqual(input.outcome, .completed)
    XCTAssertEqual(insert("x", into: &input, at: 1), [])
    XCTAssertEqual(TypingLiveInputFeedback.delete(from: &input, wholeWord: true), [])
    var repeatAttempt = input.repeatedAttempt()
    XCTAssertEqual(insert("", into: &repeatAttempt), [])
    XCTAssertEqual(TypingLiveInputFeedback.delete(from: &repeatAttempt, wholeWord: false), [])
    XCTAssertEqual(insert("a", into: &repeatAttempt, at: 2), [true])
  }

  func testCompositionCandidatePolicyAndConfirmedBatchStaySeparate() {
    var input = TypingSession(configuration: .words(10, language: .simplifiedChinese), prompt: "拼音文字")
    input.beginComposition(at: start)
    XCTAssertTrue(TypingInputSoundPlan.isAudibleCompositionUpdate(previous: "", current: "pin"))
    XCTAssertFalse(TypingInputSoundPlan.isAudibleCompositionUpdate(previous: "pin", current: "pin"))
    XCTAssertFalse(TypingInputSoundPlan.isAudibleCompositionUpdate(previous: "pin", current: ""))
    XCTAssertEqual(insert("拼音", into: &input, at: 1), [true])
    XCTAssertEqual(input.typed, "拼音")
  }

  func testVirtualKeyboardRetainsOriginAndReceivesSameAutomaticFeedback() {
    var input = TypingSession(configuration: .words(10, language: .codeSwift),
      prompt: "ab \t\tgo() tail")
    XCTAssertEqual(TypingLiveInputFeedback.insertBatch("ab ", into: &input,
      origin: .virtualKeyboard, at: start), [true, true, true])
    XCTAssertTrue(input.hasAcceptedVirtualKeyboardInput)
    XCTAssertTrue(input.hasUsedOnlyVirtualKeyboard)
  }

  func testFeedbackDoesNotAlterResultsReplayHistoryOrPortableArchive() throws {
    let config = TestConfiguration.words(3, rules: .init(codeUnindentOnBackspace: true),
      language: .codeSwift)
    var routed = TypingSession(configuration: config, prompt: "ab \t\tgo() tail")
    var direct = routed
    _ = insert("ab ", into: &routed)
    direct.insertBatch("ab ", at: start)
    _ = insert("go() tail", into: &routed, at: 2)
    direct.insertBatch("go() tail", at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(routed.result()), control = try XCTUnwrap(direct.result())
    var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(result))
      as? [String: Any])
    fields["id"] = control.id.uuidString
    XCTAssertEqual(try JSONDecoder().decode(CompletedTestResult.self,
      from: JSONSerialization.data(withJSONObject: fields)), control)
    let portable = try XCTUnwrap(TestResultRecord(result: result).portableResult)
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [], at: start))
    for restored in [portable, archive.results[0]] {
      XCTAssertEqual(restored, result)
      XCTAssertEqual(TypingReplay.typedText(events: restored.replayEvents, through: 2), "ab \t\tgo() tail")
    }
  }

  @MainActor
  func testUnopenedResponderUsesSharedLiveEntryForInsertAndDelete() {
    var input = TypingSession(configuration: .words(10,
      rules: .init(codeUnindentOnBackspace: true), language: .codeSwift),
      prompt: "first ab \t\tgo() tail")
    var feedback: [Bool] = []
    let view = TypingInputView(frame: .zero)
    view.onInsert = { text, forced in feedback += self.insert(text, into: &input, forceError: forced) }
    view.onDeleteWord = { feedback += TypingLiveInputFeedback.delete(from: &input, wholeWord: true,
      at: self.start.addingTimeInterval(1)) }
    view.insertText("first ab ", replacementRange: .init())
    XCTAssertEqual(feedback, [true, true, true])
    view.doCommand(by: #selector(NSResponder.deleteWordBackward(_:)))
    XCTAssertEqual(feedback, [true, true, true, true])
    XCTAssertEqual(input.typed, "first ")
  }

  @MainActor private final class Trace {
    var voices: [WeakVoice] = []
    var sources: [TypingClickPlaybackSource] = []
    var stops = 0
  }
  @MainActor private final class WeakVoice {
    weak var value: Voice?
    init(_ value: Voice) { self.value = value }
  }
  @MainActor private final class Voice: TypingSoundVoice {
    let trace: Trace
    let source: TypingClickPlaybackSource
    var volume: Float = 0
    init(_ trace: Trace, source: TypingClickPlaybackSource) { self.trace = trace; self.source = source }
    func copyForPlayback() -> (any TypingSoundVoice)? { Voice(trace, source: source) }
    func play(onFinish: @escaping () -> Void) -> Bool {
      trace.voices.append(WeakVoice(self))
      trace.sources.append(source)
      return true
    }
    func stop() { trace.stops += 1 }
  }

  @MainActor
  func testRealSoundControllerRoutesEveryLiveFeedbackWithoutPlayingDeviceAudio() {
    for blind in [false, true] {
      for clickEnabled in [false, true] {
        for errorEnabled in [false, true] {
          let trace = Trace()
          let player = TypingFeedbackSound(loadSound: { Voice(trace, source: $0) }, beep: {}, randomUnit: { 0 })
          player.setVolume(0)
          var input = TypingSession(configuration: .words(10, language: .codeSwift),
            prompt: "\t\t\tgo() tail")
          let feedback = insert("\t", into: &input) + insert("x", into: &input, at: 1)
          XCTAssertEqual(feedback, [true, true, true, false])
          for correct in feedback {
            let plan = TypingInputSoundPlan(inputWasCorrect: correct, blindMode: blind,
              clickEnabled: clickEnabled, errorEnabled: errorEnabled)
            if plan.playsClick { player.playClick(style: .tink, volume: 0) }
            if plan.playsError { player.playError(style: .basso, volume: 0) }
          }
          let error = !blind && errorEnabled
          XCTAssertEqual(trace.sources.filter { $0 == .system("Basso") }.count, error ? 1 : 0)
          XCTAssertEqual(trace.sources.filter { $0 == .system("Tink") }.count,
            clickEnabled ? (error ? 3 : 4) : 0)
          XCTAssertEqual(Set(trace.voices.compactMap(\.value).map(ObjectIdentifier.init)).count, trace.voices.count)
          XCTAssertTrue(trace.voices.allSatisfy { $0.value?.volume == 0 })
          XCTAssertEqual(trace.stops, 0)
          player.beginPracticeAttempt()
          XCTAssertEqual(trace.stops, trace.voices.count)
          XCTAssertTrue(trace.voices.allSatisfy { $0.value == nil })
        }
      }
    }
  }
}
