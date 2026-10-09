import AppKit
import XCTest
@testable import Typebar

@MainActor final class TypingWindowFocusDeliveryTests: XCTestCase {
  private final class Window: NSWindow {
    var key = false
    var testSheet: NSWindow?
    override var isKeyWindow: Bool { key }
    override var attachedSheet: NSWindow? { testSheet }
  }

  private func window() -> Window {
    let window = Window(contentRect: .init(x: 0, y: 0, width: 300, height: 100),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    return window
  }

  func testRepeatedRefreshDoesNotRedeliverUnchangedFocus() {
    let window = window(), input = TypingInputView(frame: .zero)
    var states: [String] = []
    input.onWindowFocusChanged = { states.append("\($0):\($1)") }
    window.contentView = input
    defer { window.contentView = nil; window.close() }
    for _ in 0..<20 { input.refreshWindowFocusState() }
    XCTAssertEqual(states, ["false:false"])
    window.key = true
    NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
    input.refreshWindowFocusState()
    XCTAssertEqual(states, ["false:false", "true:false"])
    window.key = false
    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
    input.refreshWindowFocusState()
    XCTAssertEqual(states, ["false:false", "true:false", "false:false"])
    XCTAssertFalse(window.isVisible)
  }

  func testSheetChangesAndWindowMigrationStillDeliverEvenWhenKeyStateMatches() {
    let first = window(), second = window(), sheet = window()
    let input = TypingInputView(frame: .zero)
    var states: [String] = []
    input.onWindowFocusChanged = { states.append("\($0):\($1)") }
    first.key = true; second.key = true
    first.contentView = input
    defer {
      first.testSheet = nil; second.testSheet = nil
      first.contentView = nil; second.contentView = nil
      first.close(); second.close(); sheet.close()
    }
    first.testSheet = sheet
    input.refreshWindowFocusState(); input.refreshWindowFocusState()
    first.testSheet = nil
    input.refreshWindowFocusState(); input.refreshWindowFocusState()
    first.contentView = nil
    second.contentView = input
    input.refreshWindowFocusState()
    XCTAssertEqual(states, ["true:false", "true:true", "true:false", "true:false"])
    second.contentView = nil
    first.contentView = input
    input.refreshWindowFocusState()
    XCTAssertEqual(states.last, "true:false")
    XCTAssertEqual(states.count, 5, "Reattaching a view must establish focus again")
    XCTAssertFalse(first.isVisible); XCTAssertFalse(second.isVisible); XCTAssertFalse(sheet.isVisible)
  }

  func testSynchronousRefreshInsideReceiverDoesNotReenterDelivery() {
    let window = window(), input = TypingInputView(frame: .zero)
    var deliveries = 0
    input.onWindowFocusChanged = { [weak input] _, _ in
      deliveries += 1
      if deliveries < 3 { input?.refreshWindowFocusState() }
    }
    window.contentView = input
    defer { input.onWindowFocusChanged = { _, _ in }; window.contentView = nil; window.close() }
    XCTAssertEqual(deliveries, 1)
    window.key = true
    input.refreshWindowFocusState()
    XCTAssertEqual(deliveries, 2)
  }

  func testRetiredWindowNotificationsCannotChangeCurrentFocus() {
    let first = window(), second = window(), input = TypingInputView(frame: .zero)
    var states: [Bool] = []
    input.onWindowFocusChanged = { isKey, _ in states.append(isKey) }
    first.contentView = input
    first.contentView = nil
    second.contentView = input
    defer { second.contentView = nil; first.close(); second.close() }
    NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: first)
    XCTAssertEqual(states, [false, false])
    second.key = true
    NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: second)
    XCTAssertEqual(states, [false, false, true])
  }
}
