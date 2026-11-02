import AppKit
import XCTest
@testable import Typebar

@MainActor
private final class RetirementInputContext: NSTextInputContext {
  var onDiscard: () -> Void = {}
  override func discardMarkedText() { onDiscard() }
}

@MainActor
private final class RetirementInputView: TypingInputView {
  lazy var context = RetirementInputContext(client: self)
  override var inputContext: NSTextInputContext? { context }
}

@MainActor
final class TypingInputRetirementTests: XCTestCase {
  private let replacement = NSRange(location: NSNotFound, length: 0)

  func testRetirementClearsCandidateQueriesWithoutPublishingIntoTheDepartingPage() {
    let input = TypingInputView()
    var changes: [String] = []
    input.onCompositionChanged = { changes.append($0) }
    input.setMarkedText("😀候选", selectedRange: .init(location: 2, length: 1),
      replacementRange: replacement)
    XCTAssertTrue(input.hasMarkedText())
    input.retirePageCallbacks()

    XCTAssertFalse(input.hasMarkedText())
    XCTAssertEqual(input.markedRange(), replacement)
    XCTAssertEqual(input.selectedRange(), NSRange(location: 0, length: 0))
    var actual = NSRange(location: 0, length: 1)
    XCTAssertNil(input.attributedSubstring(forProposedRange: actual, actualRange: &actual))
    XCTAssertEqual(actual, replacement)
    XCTAssertEqual(changes, ["😀候选"], "Dismantling must not mutate the departing SwiftUI page")
    XCTAssertFalse(input.acceptsFirstResponder)
  }

  func testDiscardReentryCannotCommitOrRecreateTheRetiredCandidate() {
    let input = RetirementInputView()
    var commits: [String] = [], changes: [String] = []
    var starts = 0, completionChecks = 0, discards = 0
    input.onInsert = { text, _ in commits.append(text) }
    input.onCompositionChanged = { changes.append($0) }
    input.onCompositionStarted = { starts += 1 }
    input.shouldFinishWithComposition = { _, _ in completionChecks += 1; return false }
    input.setMarkedText("未确认", selectedRange: .init(location: 3, length: 0),
      replacementRange: replacement)
    input.context.onDiscard = {
      discards += 1
      XCTAssertFalse(input.hasMarkedText())
      XCTAssertFalse(input.acceptsTextInput)
      input.insertText("迟到确认", replacementRange: self.replacement)
      input.setMarkedText("迟到候选", selectedRange: .init(), replacementRange: self.replacement)
    }

    input.retirePageCallbacks()
    input.retirePageCallbacks()

    XCTAssertEqual(discards, 1)
    XCTAssertFalse(input.hasMarkedText())
    XCTAssertTrue(commits.isEmpty)
    XCTAssertEqual(changes, ["未确认"])
    XCTAssertEqual(starts, 1)
    XCTAssertEqual(completionChecks, 1)
  }

  func testLateConfigurationCannotReopenARetiredTextClient() {
    let input = TypingInputView()
    input.retirePageCallbacks()
    // A retained receiver remains terminal even if delayed configuration
    // enables admission or restores a callback after the page has gone.
    input.acceptsTextInput = true
    var commits: [String] = [], changes: [String] = []
    input.onInsert = { text, _ in commits.append(text) }
    input.onCompositionChanged = { changes.append($0) }
    input.insertText("旧页提交", replacementRange: replacement)
    input.setMarkedText("旧页候选", selectedRange: .init(), replacementRange: replacement)

    XCTAssertTrue(commits.isEmpty)
    XCTAssertTrue(changes.isEmpty)
    XCTAssertFalse(input.hasMarkedText())
    XCTAssertFalse(input.acceptsFirstResponder)
  }
}
