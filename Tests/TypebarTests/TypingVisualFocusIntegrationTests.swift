import Foundation
import XCTest

final class TypingVisualFocusIntegrationTests: XCTestCase {
  func testVisualFocusHasItsOwnProductionStateAndMouseEntry() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let app = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    XCTAssertTrue(app.contains("@State private var visualFocus = TypingVisualFocus()"))
    XCTAssertTrue(app.contains("focused: visualFocus.isFocused"), "Notice visibility must not be inferred from first responder or elapsed typing")
    XCTAssertTrue(app.contains("TypingVisualFocusMouseBridge("), "The native practice surface must receive mouse movement")
    XCTAssertFalse(app.contains("focused: inputHasFocus && typingWindowHasFocus && session.hasStarted"))
    XCTAssertTrue(app.contains(".disabled(visualFocus.isFocused)"), "Hidden configuration must not remain keyboard editable")
    XCTAssertTrue(app.contains("if !hasFocus || hasAttachedSheet { visualFocus.retire() }"))
    XCTAssertTrue(app.contains("if outcome != .active { visualFocus.retire() }"))
  }

  func testLiveFeedbackIsNotUsedAsSoleVisualFocusAdmissionSignal() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let app = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    XCTAssertTrue(app.contains("visualFocus.inputDidUpdate("), "Sound feedback can be empty after a partial batch changed text")
    XCTAssertFalse(app.contains("if !feedback.isEmpty, !session.isFinished { visualFocus.set(true) }"))
  }
}
