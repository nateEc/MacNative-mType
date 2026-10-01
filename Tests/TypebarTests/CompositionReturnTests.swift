import AppKit
import XCTest
@testable import Typebar

// Model the unstable input-method boundary, not the typing engine. The real
// AppKit interpretation path must reach this context to confirm the candidate.
@MainActor
private final class CandidateInputContext: NSTextInputContext {
  override func handleEvent(_ event: NSEvent) -> Bool {
    guard client.hasMarkedText(),
      event.charactersIgnoringModifiers == "\r" || event.charactersIgnoringModifiers == "\n"
    else { return false }
    client.insertText("候选", replacementRange: .init(location: NSNotFound, length: 0))
    return true
  }
}

@MainActor
private final class CandidateInputView: TypingInputView {
  private lazy var candidateContext = CandidateInputContext(client: self)
  override var inputContext: NSTextInputContext? { candidateContext }
}

final class CompositionReturnTests: XCTestCase {
  @MainActor
  private func key(
    text: String = "\r", code: UInt16 = 36, modifiers: NSEvent.ModifierFlags = [],
    kind: NSEvent.EventType = .keyDown
  ) throws -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(
      with: kind, location: .zero, modifierFlags: modifiers, timestamp: 1,
      windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text,
      isARepeat: false, keyCode: code))
  }

  @MainActor
  func testReturnConfirmsCandidateInsteadOfInsertingNewlineIntoMultilinePractice() throws {
    for restartKey in [QuickRestartKey.off, .enter] {
      for text in ["\r", "\n"] {
        let input = CandidateInputView(frame: .zero)
        input.acceptsNewlineInput = true
        input.quickRestartKey = restartKey
        var inserts = [String]()
        var physical = [String]()
        var restarts = 0
        input.onInsert = { text, _ in inserts.append(text) }
        input.onRestart = { restarts += 1 }
        input.onPhysicalKey = { code, down, _ in physical.append("\(code):\(down)") }
        input.setMarkedText("候选", selectedRange: .init(), replacementRange: .init())

        input.keyDown(with: try key(text: text))
        input.keyUp(with: try key(text: text, kind: .keyUp))

        XCTAssertEqual(inserts, ["候选"])
        XCTAssertFalse(input.hasMarkedText())
        XCTAssertEqual(restarts, 0)
        XCTAssertEqual(physical, ["36:true", "36:false"])
        input.keyDown(with: try key(text: text))
        XCTAssertEqual(inserts, ["候选", "\n"])
      }
    }
  }

  @MainActor
  func testCandidateReturnAndLaterNewlineCompleteAndReplayMultilinePractice() throws {
    let configuration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init())
    let prompt = "候选\n尾词"
    var session = TypingSession(configuration: configuration, prompt: prompt)
    let input = CandidateInputView(frame: .zero)
    input.acceptsNewlineInput = true
    var now = Date(timeIntervalSince1970: 1_700_000_000)
    let start = now
    input.onCompositionStarted = { session.beginComposition(at: now) }
    input.shouldFinishWithComposition = { text, forced in
      session.shouldFinishWithComposition(text, forceError: forced, at: now)
    }
    input.onInsert = { text, forced in session.insertBatch(text, forceError: forced, at: now) }
    input.setMarkedText("候选", selectedRange: .init(), replacementRange: .init())
    XCTAssertTrue(session.typed.isEmpty)

    now = start.addingTimeInterval(1)
    input.keyDown(with: try key())
    XCTAssertEqual(session.typed, "候选")
    XCTAssertEqual(session.outcome, .active)
    now = start.addingTimeInterval(2)
    input.keyDown(with: try key())
    XCTAssertEqual(session.typed, "候选\n")
    now = start.addingTimeInterval(3)
    input.insertText("尾词", replacementRange: .init())
    XCTAssertEqual(session.typed, prompt)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
    let result = try XCTUnwrap(session.result(at: now))
    XCTAssertEqual(
      TypingReplay.typedText(events: result.replayEvents, through: result.elapsedDuration), prompt)
  }

  @MainActor
  func testReturnWithoutCompositionStillInsertsOneNewline() throws {
    let input = CandidateInputView(frame: .zero)
    input.acceptsNewlineInput = true
    input.quickRestartKey = .enter
    var inserts = [String]()
    input.onInsert = { text, _ in inserts.append(text) }
    input.keyDown(with: try key())
    XCTAssertEqual(inserts, ["\n"])
  }

  @MainActor
  func testShiftReturnStillRestartsMultilinePracticeInsteadOfConfirmingCandidate() throws {
    let input = CandidateInputView(frame: .zero)
    input.acceptsNewlineInput = true
    input.quickRestartKey = .enter
    var restarts = 0
    var inserts = [String]()
    input.onRestart = { restarts += 1 }
    input.onInsert = { text, _ in inserts.append(text) }
    input.setMarkedText("候选", selectedRange: .init(), replacementRange: .init())
    input.keyDown(with: try key(modifiers: [.shift]))
    XCTAssertEqual(restarts, 1)
    XCTAssertTrue(inserts.isEmpty)
  }

  @MainActor
  func testShiftReturnStillFinishesZenWithoutCommittingCandidate() throws {
    let input = CandidateInputView(frame: .zero)
    input.acceptsNewlineInput = true
    input.finishesOnShiftEnter = true
    var finishes = 0
    var inserts = [String]()
    input.onFinishZen = { finishes += 1 }
    input.onInsert = { text, _ in inserts.append(text) }
    input.setMarkedText("候选", selectedRange: .init(), replacementRange: .init())
    input.keyDown(with: try key(modifiers: [.shift]))
    XCTAssertEqual(finishes, 1)
    XCTAssertTrue(inserts.isEmpty)
  }

  @MainActor
  func testDoubleShiftReturnStillBailsOutOfLongPracticeWithoutCommittingCandidate() throws {
    let input = CandidateInputView(frame: .zero)
    input.acceptsNewlineInput = true
    input.quickRestartKey = .enter
    input.disablesQuickRestart = true
    input.enablesLongTestBailout = true
    input.bailoutClock = { Date(timeIntervalSince1970: 1) }
    var armed = 0
    var bailouts = 0
    var inserts = [String]()
    input.onBailoutArmed = { armed += 1 }
    input.onBailout = { bailouts += 1 }
    input.onInsert = { text, _ in inserts.append(text) }
    input.setMarkedText("候选", selectedRange: .init(), replacementRange: .init())
    input.keyDown(with: try key(modifiers: [.shift]))
    input.keyDown(with: try key(modifiers: [.shift]))
    XCTAssertEqual(armed, 1)
    XCTAssertEqual(bailouts, 1)
    XCTAssertTrue(inserts.isEmpty)
  }

  @MainActor
  func testPlainReturnStillRestartsWhenPromptDoesNotAcceptNewlines() throws {
    let input = CandidateInputView(frame: .zero)
    input.quickRestartKey = .enter
    var restarts = 0
    var inserts = [String]()
    input.onRestart = { restarts += 1 }
    input.onInsert = { text, _ in inserts.append(text) }
    input.setMarkedText("候选", selectedRange: .init(), replacementRange: .init())
    input.keyDown(with: try key())
    XCTAssertEqual(restarts, 1)
    XCTAssertTrue(inserts.isEmpty)
  }

  @MainActor
  func testTabStillUsesTheReferenceExplicitInsertionDuringComposition() throws {
    let input = CandidateInputView(frame: .zero)
    input.acceptsTabInput = true
    var inserts = [String]()
    input.onInsert = { text, _ in inserts.append(text) }
    input.setMarkedText("候选", selectedRange: .init(), replacementRange: .init())
    input.keyDown(with: try key(text: "\t", code: 48))
    XCTAssertEqual(inserts, ["\t"])
  }
}
