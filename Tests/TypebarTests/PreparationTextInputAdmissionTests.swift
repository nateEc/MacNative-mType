import AppKit
import XCTest
@testable import Typebar

@MainActor final class PreparationTextInputAdmissionTests: XCTestCase {
  func testDisablingTextInputClearsCandidateAndRejectsPendingTextUntilEnabled() {
    let input = TypingInputView()
    var inserted: [String] = [], compositions: [String] = []
    input.onInsert = { text, _ in inserted.append(text) }
    input.onCompositionChanged = { compositions.append($0) }
    let replacement = NSRange(location: NSNotFound, length: 0)
    input.setMarkedText("候选", selectedRange: .init(location: 2, length: 0), replacementRange: replacement)
    XCTAssertTrue(input.hasMarkedText())
    input.acceptsTextInput = false
    XCTAssertFalse(input.hasMarkedText())
    let before = compositions
    input.insertText("old", replacementRange: replacement)
    input.setMarkedText("旧", selectedRange: .init(location: 1, length: 0), replacementRange: replacement)
    XCTAssertFalse(input.hasMarkedText())
    XCTAssertEqual(compositions, before)
    XCTAssertTrue(inserted.isEmpty)
    input.acceptsTextInput = true
    input.insertText("ready", replacementRange: replacement)
    XCTAssertEqual(inserted, ["ready"])
  }

  func testClosedAdmissionRejectsEditingCommandsUntilReenabled() {
    let input = TypingInputView(); defer { input.retirePageCallbacks() }
    input.acceptsNewlineInput = true
    input.acceptsTabInput = true
    var commits: [String] = [], deletions = 0
    input.onInsert = { text, _ in commits.append(text) }
    input.onDelete = { deletions += 1 }
    input.onDeleteWord = { deletions += 1 }
    let commands = [#selector(NSResponder.deleteBackward(_:)),
      #selector(NSResponder.deleteWordBackward(_:)), #selector(NSResponder.insertNewline(_:)),
      #selector(NSResponder.insertLineBreak(_:)), #selector(NSResponder.insertTab(_:))]
    input.acceptsTextInput = false
    for command in commands { input.doCommand(by: command) }
    XCTAssertTrue(commits.isEmpty)
    XCTAssertEqual(deletions, 0)
    input.acceptsTextInput = true
    for command in commands { input.doCommand(by: command) }
    XCTAssertEqual(commits, ["\n", "\n", "\t"])
    XCTAssertEqual(deletions, 2)
  }

  func testClosedAdmissionRejectsEmulatedTextAndLiteralReturnButKeepsRestart() throws {
    for (code, text, expected) in [(UInt16(0), "a", "a"), (36, "\r", "\n")] {
      let input = TypingInputView(); defer { input.retirePageCallbacks() }
      input.keyboardInputMapping = .builtIn(.ansiQwerty)
      input.acceptsNewlineInput = true
      var inserted: [String] = [], restarts = 0
      input.onInsert = { text, _ in inserted.append(text) }
      input.onRestart = { restarts += 1 }
      input.acceptsTextInput = false
      let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
        modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil,
        characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code))
      input.keyDown(with: event)
      XCTAssertTrue(inserted.isEmpty, "closed admission: \(code)")
      input.keyDown(with: try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
        modifierFlags: .command, timestamp: 2, windowNumber: 0, context: nil,
        characters: "r", charactersIgnoringModifiers: "r", isARepeat: false, keyCode: 15)))
      XCTAssertEqual(restarts, 1)
      input.acceptsTextInput = true
      input.keyDown(with: event)
      XCTAssertEqual(inserted, [expected])
    }
  }
}
