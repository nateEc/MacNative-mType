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
    XCTAssertTrue(app.contains("if !visualFocus.isFocused && !(pageSessionStore.ownsConfigurationSelection && session.isFinished) {\n        configurationPanel"),
      "Hidden configuration must not remain in layout or keyboard navigation")
    XCTAssertTrue(app.contains("if !hasFocus || hasAttachedSheet { visualFocus.retire() }"))
    XCTAssertTrue(app.contains("if outcome != .active { visualFocus.retire() }"))
  }

  func testLiveFeedbackIsNotUsedAsSoleVisualFocusAdmissionSignal() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let app = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    XCTAssertTrue(app.contains("visualFocus.inputDidUpdate("), "Sound feedback can be empty after a partial batch changed text")
    XCTAssertFalse(app.contains("if !feedback.isEmpty, !session.isFinished { visualFocus.set(true) }"))
  }

  func testFocusedPracticeDoesNotReserveHiddenConfigurationHeight() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let app = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    let layout = try XCTUnwrap(app.components(separatedBy: "private var practiceLayout: some View {").dropFirst().first?.components(separatedBy: "private var header: some View {").first)
    XCTAssertTrue(layout.contains("if !visualFocus.isFocused && !(pageSessionStore.ownsConfigurationSelection && session.isFinished) {\n        configurationPanel"),
      "Focused practice must remove hidden setup controls from layout so the prompt stays visible in a short window")
    XCTAssertFalse(layout.contains("configurationPanel\n        .opacity(visualFocus.isFocused ? 0 : 1)"))
  }
}
