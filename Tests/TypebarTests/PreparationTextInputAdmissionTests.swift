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
}
