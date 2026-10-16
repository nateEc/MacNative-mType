import AppKit
import XCTest
@testable import Typebar

@MainActor final class CompositionSubstringTests: XCTestCase {
  func testMutableInputIsSnapshottedUntilExplicitCandidateUpdate() throws {
    let input = TypingInputView(frame: .zero)
    let candidate = NSMutableAttributedString(string: "中文", attributes: [.underlineStyle: 1])
    var changes = [String]()
    input.onCompositionChanged = { changes.append($0) }
    input.setMarkedText(candidate, selectedRange: .init(location: 2, length: 0),
      replacementRange: .init(location: NSNotFound, length: 0))
    candidate.replaceCharacters(in: .init(location: 0, length: 2), with: "候")
    candidate.addAttribute(.underlineStyle, value: 2, range: .init(location: 0, length: 1))
    let stored = try XCTUnwrap(input.attributedSubstring(
      forProposedRange: .init(location: 0, length: 2), actualRange: nil))
    XCTAssertEqual(stored.string, "中文")
    XCTAssertEqual(stored.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int, 1)
    XCTAssertEqual(input.markedRange(), NSRange(location: 0, length: 2))
    XCTAssertEqual(input.selectedRange(), NSRange(location: 2, length: 0))
    XCTAssertEqual(changes, ["中文"])
    input.setMarkedText(candidate, selectedRange: .init(location: 1, length: 0),
      replacementRange: .init(location: NSNotFound, length: 0))
    XCTAssertEqual(input.attributedSubstring(forProposedRange: .init(location: 0, length: 1),
      actualRange: nil)?.string, "候")
    XCTAssertEqual(input.markedRange(), NSRange(location: 0, length: 1))
    XCTAssertEqual(changes, ["中文", "候"])
  }

  func testCandidateReadbackPreservesAttributesAndExpandsUnicodeBoundaries() throws {
    let input = TypingInputView(frame: .zero)
    let candidate = NSAttributedString(string: "😀e\u{301}候", attributes: [.underlineStyle: 1])
    input.setMarkedText(candidate, selectedRange: .init(location: 2, length: 2),
      replacementRange: .init(location: NSNotFound, length: 0))
    var actual = NSRange(location: NSNotFound, length: 0)
    let emoji = try XCTUnwrap(input.attributedSubstring(
      forProposedRange: .init(location: 1, length: 1), actualRange: &actual))
    XCTAssertEqual(emoji.string, "😀")
    XCTAssertEqual(actual, NSRange(location: 0, length: 2))
    XCTAssertEqual(emoji.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int, 1)
    let combining = try XCTUnwrap(input.attributedSubstring(
      forProposedRange: .init(location: 3, length: 1), actualRange: &actual))
    XCTAssertEqual(combining.string, "e\u{301}")
    XCTAssertEqual(actual, NSRange(location: 2, length: 2))
    XCTAssertEqual(input.selectedRange(), NSRange(location: 2, length: 2))
    XCTAssertTrue(input.hasMarkedText(), "Readback must not confirm the candidate")
    XCTAssertEqual(input.attributedSubstring(forProposedRange: .init(location: 0, length: 5),
      actualRange: nil)?.string, candidate.string)
  }

  func testOversizedAndOutsideRequestsAreSafeAndCancelledTextIsUnavailable() {
    let input = TypingInputView(frame: .zero)
    input.setMarkedText("中文", selectedRange: .init(),
      replacementRange: .init(location: NSNotFound, length: 0))
    var actual = NSRange(location: 99, length: 99)
    XCTAssertEqual(input.attributedSubstring(forProposedRange: .init(location: 1, length: Int.max),
      actualRange: &actual)?.string, "文")
    XCTAssertEqual(actual, NSRange(location: 1, length: 1))
    for range in [NSRange(location: NSNotFound, length: 0), NSRange(location: 3, length: 1)] {
      actual = .init(location: 99, length: 99)
      XCTAssertNil(input.attributedSubstring(forProposedRange: range, actualRange: &actual))
      XCTAssertEqual(actual, NSRange(location: NSNotFound, length: 0))
    }
    XCTAssertEqual(input.attributedSubstring(forProposedRange: .init(location: 1, length: 0),
      actualRange: &actual)?.string, "")
    XCTAssertEqual(actual, NSRange(location: 1, length: 0))
    input.unmarkText()
    XCTAssertNil(input.attributedSubstring(forProposedRange: .init(location: 0, length: 2),
      actualRange: &actual))
    XCTAssertEqual(actual, NSRange(location: NSNotFound, length: 0))
  }

  func testEmptyReadAtMarkedUTF16EndIsValidWithoutConfirmingTheCandidate() throws {
    let input = TypingInputView(frame: .zero)
    input.setMarkedText("😀候", selectedRange: .init(location: 3, length: 0),
      replacementRange: .init(location: NSNotFound, length: 0))
    var actual = NSRange(location: NSNotFound, length: 0)
    let empty = try XCTUnwrap(input.attributedSubstring(
      forProposedRange: .init(location: 3, length: 0), actualRange: &actual))
    XCTAssertEqual(empty.string, "")
    XCTAssertEqual(actual, NSRange(location: 3, length: 0))
    XCTAssertEqual(input.selectedRange(), NSRange(location: 3, length: 0))
    XCTAssertTrue(input.hasMarkedText())
    XCTAssertNil(input.attributedSubstring(
      forProposedRange: .init(location: 3, length: 1), actualRange: &actual))
    XCTAssertEqual(actual, NSRange(location: NSNotFound, length: 0))
    XCTAssertNil(input.attributedSubstring(
      forProposedRange: .init(location: 4, length: 0), actualRange: &actual))
    XCTAssertEqual(actual, NSRange(location: NSNotFound, length: 0))
  }
}
