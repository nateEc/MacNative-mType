import AppKit
import XCTest
@testable import Typebar

@MainActor final class CompositionSelectionTests: XCTestCase {
  func testMarkedSelectionUsesUTF16OffsetsAndClearsBeforeCommitCallback() {
    let input = TypingInputView(frame: .zero)
    let candidate = "😀e\u{301}候"
    var commits = [String]()
    input.onInsert = { text, _ in
      XCTAssertFalse(input.hasMarkedText())
      XCTAssertEqual(input.selectedRange(), NSRange(location: 0, length: 0))
      commits.append(text)
    }
    input.setMarkedText(candidate, selectedRange: .init(location: 2, length: 2),
      replacementRange: .init(location: NSNotFound, length: 0))
    XCTAssertEqual(input.markedRange(), NSRange(location: 0, length: 5))
    XCTAssertEqual(input.selectedRange(), NSRange(location: 2, length: 2))
    XCTAssertTrue(commits.isEmpty)
    input.setMarkedText(NSAttributedString(string: candidate),
      selectedRange: .init(location: 5, length: 0),
      replacementRange: .init(location: NSNotFound, length: 0))
    XCTAssertEqual(input.selectedRange(), NSRange(location: 5, length: 0))
    input.insertText(candidate, replacementRange: .init(location: NSNotFound, length: 0))
    XCTAssertEqual(commits, [candidate])
  }

  func testCandidateSelectionIsBoundedAndCancellationClearsIt() {
    let input = TypingInputView(frame: .zero)
    for (selection, expected) in [
      (NSRange(location: 1, length: Int.max), NSRange(location: 1, length: 1)),
      (NSRange(location: 99, length: 4), NSRange(location: 2, length: 0)),
      (NSRange(location: NSNotFound, length: 0), NSRange(location: NSNotFound, length: 0))
    ] {
      input.setMarkedText("中文", selectedRange: selection,
        replacementRange: .init(location: NSNotFound, length: 0))
      XCTAssertEqual(input.selectedRange(), expected)
      input.unmarkText()
      XCTAssertFalse(input.hasMarkedText())
      XCTAssertEqual(input.selectedRange(), NSRange(location: 0, length: 0))
    }
  }

  func testEmptyUpdateAndAutomaticCompletionDoNotLeaveStaleSelection() {
    let input = TypingInputView(frame: .zero)
    var commits = [String]()
    input.onInsert = { text, _ in
      XCTAssertEqual(input.selectedRange(), NSRange(location: 0, length: 0))
      commits.append(text)
    }
    input.setMarkedText("中文", selectedRange: .init(location: 2, length: 0),
      replacementRange: .init(location: NSNotFound, length: 0))
    input.setMarkedText("", selectedRange: .init(location: 2, length: 0),
      replacementRange: .init(location: NSNotFound, length: 0))
    XCTAssertFalse(input.hasMarkedText())
    XCTAssertEqual(input.selectedRange(), NSRange(location: 0, length: 0))
    XCTAssertTrue(commits.isEmpty)
    input.shouldFinishWithComposition = { _, _ in true }
    input.setMarkedText("中文", selectedRange: .init(location: 2, length: 0),
      replacementRange: .init(location: NSNotFound, length: 0))
    XCTAssertFalse(input.hasMarkedText())
    XCTAssertEqual(commits, ["中文"])
  }
}
