import AppKit
import XCTest
@testable import Typebar

@MainActor final class CompositionCandidateRectTests: XCTestCase {
  func testEmptyMarkedSelectionHasZeroWidthScreenInsertionRect() {
    let window = NSWindow(contentRect: .init(x: 180, y: 220, width: 320, height: 180),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let host = NSView(frame: .init(x: 0, y: 0, width: 320, height: 180))
    let input = TypingInputView(frame: .init(x: 2, y: 3, width: 1, height: 1))
    host.addSubview(input); window.contentView = host
    defer { window.contentView = nil; window.close() }

    input.setMarkedText("😀候", selectedRange: .init(location: 3, length: 0),
      replacementRange: .init(location: NSNotFound, length: 0))
    var actual = NSRange(location: NSNotFound, length: 0)
    let rect = input.firstRect(forCharacterRange: .init(location: 3, length: 0), actualRange: &actual)
    XCTAssertEqual(actual, NSRange(location: 3, length: 0))
    XCTAssertEqual(rect.width, 0, "An insertion point is not the hidden input view's 1pt box")
  }

  func testCandidateRectTracksPromptGeometryWithMarkerOffAndRejectsStaleAttempt() {
    let window = NSWindow(contentRect: .init(x: 180, y: 220, width: 320, height: 180),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let host = NSView(frame: .init(x: 0, y: 0, width: 320, height: 180))
    let input = TypingInputView(frame: .init(x: 2, y: 3, width: 1, height: 1))
    let caret = PromptCaretNativeView(frame: .init(x: 50, y: 40, width: 200, height: 100))
    host.addSubview(input); host.addSubview(caret); window.contentView = host
    defer { caret.stop(); window.contentView = nil; window.close() }

    let attempt = UUID(), anchor = PromptInsertionAnchor()
    var config = PromptCaretNativeView.Configuration(text: AttributedString("example"),
      mainOffset: nil, paceOffset: nil, mainStyle: .off, paceStyle: .off,
      font: .systemFont(ofSize: 20), lineSpacing: 12, rightToLeft: false,
      accent: .white, motion: .off, reducesMotion: true, frameRate: 60,
      attemptID: attempt, coordinator: PromptCaretMotionCoordinator())
    config.fieldMainRect = { _ in NSRect(x: 20, y: 10, width: 15, height: 24) }
    config.automaticallyPresents = false
    config.insertionAnchor = anchor
    caret.update(config)
    input.insertionAnchor = anchor
    input.insertionAttemptID = attempt
    let detached = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 100, height: 50))
    detached.update(config) // A stale renderer may register after the visible owner.
    defer { detached.stop() }

    let requested = NSRange(location: 0, length: 0)
    func expected() -> NSRect {
      window.convertToScreen(caret.convert(NSRect(x: 20, y: 10, width: 0, height: 24), to: nil))
    }
    XCTAssertEqual(input.firstRect(forCharacterRange: requested, actualRange: nil), expected())
    XCTAssertNil(caret.scheduledTimerIntervals.drawing)
    XCTAssertNotEqual(input.firstRect(forCharacterRange: .init(location: 1, length: 0),
      actualRange: nil), expected(), "Only the selected insertion range has this prompt anchor")
    caret.setFrameOrigin(.init(x: 85, y: 65))
    XCTAssertEqual(input.firstRect(forCharacterRange: requested, actualRange: nil), expected())

    input.insertionAttemptID = UUID()
    XCTAssertNotEqual(input.firstRect(forCharacterRange: requested, actualRange: nil), expected())
    input.insertionAttemptID = attempt
    caret.stop()
    XCTAssertNotEqual(input.firstRect(forCharacterRange: requested, actualRange: nil), expected())
  }

  func testRightToLeftCandidateAnchorFollowsScrolledPromptAndRejectsHiddenOwner() {
    let window = NSWindow(contentRect: .init(x: 180, y: 220, width: 320, height: 180),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let host = NSView(frame: .init(x: 0, y: 0, width: 320, height: 180))
    let input = TypingInputView(frame: .init(x: 2, y: 3, width: 1, height: 1))
    let scroll = NSScrollView(frame: .init(x: 30, y: 25, width: 260, height: 100))
    let document = NSView(frame: .init(x: 0, y: 0, width: 260, height: 500))
    let caret = PromptCaretNativeView(frame: .init(x: 10, y: 230, width: 200, height: 100))
    document.addSubview(caret); scroll.documentView = document
    host.addSubview(scroll); host.addSubview(input); window.contentView = host
    defer { caret.stop(); window.contentView = nil; window.close() }

    let attempt = UUID(), anchor = PromptInsertionAnchor()
    var config = PromptCaretNativeView.Configuration(text: AttributedString("אבג"),
      mainOffset: nil, paceOffset: nil, mainStyle: .off, paceStyle: .off,
      font: .systemFont(ofSize: 20), lineSpacing: 12, rightToLeft: true,
      accent: .white, motion: .off, reducesMotion: true, frameRate: 60,
      attemptID: attempt, coordinator: PromptCaretMotionCoordinator())
    config.fieldMainRect = { _ in NSRect(x: 40, y: 15, width: 12, height: 24) }
    config.automaticallyPresents = false
    config.insertionAnchor = anchor
    caret.update(config)
    input.insertionAnchor = anchor
    input.insertionAttemptID = attempt

    let requested = NSRange(location: 0, length: 0)
    let before = input.firstRect(forCharacterRange: requested, actualRange: nil)
    let trailing = window.convertToScreen(caret.convert(
      NSRect(x: 52, y: 15, width: 0, height: 24), to: nil))
    XCTAssertEqual(before, trailing)
    scroll.contentView.scroll(to: .init(x: 0, y: 45))
    scroll.reflectScrolledClipView(scroll.contentView)
    let after = input.firstRect(forCharacterRange: requested, actualRange: nil)
    XCTAssertEqual(after.minY, before.minY - 45, accuracy: 0.5)
    XCTAssertEqual(after.minX, before.minX, accuracy: 0.5)

    scroll.isHidden = true
    XCTAssertNotEqual(input.firstRect(forCharacterRange: requested, actualRange: nil), after)
  }
}
