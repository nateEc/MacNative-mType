import AppKit
import XCTest
@testable import Typebar

@MainActor final class CompositionCandidateRectTests: XCTestCase {
  func testOffAndBelowDoNotMisreportTargetInkAsMarkedSelectionGeometry() throws {
    let session = TypingSession(configuration: .words(2), prompt: "abcdef gh")
    for style in [CompositionDisplayStyle.off, .below] {
      let presentation = try XCTUnwrap(PromptCompositionPresentation(
        session: session, composition: "候选", style: style))
      let rendering = presentation.render { _, glyph, marked in
        AttributedString(marked.map { presentation.markedText(for: $0, glyph: glyph) }
          ?? String(glyph.character))
      }
      let map = try XCTUnwrap(rendering.compositionTextMap)
      XCTAssertNil(map.firstVisibleMarkedCell(for: .init(location: 0, length: 2)),
        "\(style) has no marked ink in the prompt; below owns a separate candidate row")
    }
  }

  func testReplaceCompositionNonemptyRangeUsesFirstProjectedGlyphAndReportsItsActualRange() throws {
    let window = NSWindow(contentRect: .init(x: 180, y: 220, width: 480, height: 200),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let host = NSView(frame: .init(x: 0, y: 0, width: 480, height: 200))
    let input = TypingInputView(frame: .init(x: 2, y: 3, width: 1, height: 1))
    let field = PromptFieldNativeView(frame: .init(x: 40, y: 30, width: 360, height: 120))
    host.addSubview(input); host.addSubview(field); window.contentView = host
    defer { field.stop(); window.contentView = nil; window.close() }

    var session = TypingSession(configuration: .words(2), prompt: "abcdef gh")
    session.insertBatch("a", at: Date(timeIntervalSinceReferenceDate: 916_100_000))
    let marked = "😀候"
    let presentation = try XCTUnwrap(PromptCompositionPresentation(
      session: session, composition: marked, style: .replace))
    let rendering = presentation.render { _, glyph, marked in
      AttributedString(marked.map { presentation.markedText(for: $0, glyph: glyph) }
        ?? String(glyph.character))
    }
    let map = try XCTUnwrap(rendering.compositionTextMap)
    let firstID = try XCTUnwrap(presentation.projection.markedCells.first?.id)
    let selected = try XCTUnwrap(map.firstVisibleMarkedCell(for: .init(location: 0, length: 3)))
    XCTAssertEqual(selected.id, firstID)
    let font = NSFont.monospacedSystemFont(ofSize: 24, weight: .regular)

    let attempt = UUID(), anchor = PromptInsertionAnchor()
    var config = PromptCaretNativeView.Configuration(text: rendering.text,
      mainOffset: nil, paceOffset: nil, mainStyle: .off, paceStyle: .off,
      font: font, lineSpacing: 12, rightToLeft: false,
      accent: .white, motion: .off, reducesMotion: true, frameRate: 60,
      attemptID: attempt, coordinator: PromptCaretMotionCoordinator())
    config.automaticallyPresents = false
    config.insertionAnchor = anchor
    config.latestInput = { .init(attemptID: attempt, typed: "a", composition: marked, glyphID: nil) }
    field.configure(rendering: rendering, font: font, carets: config)
    field.layoutSubtreeIfNeeded()
    let firstRect = try XCTUnwrap(field.measuredRect(for: firstID))
    let expected = window.convertToScreen(field.convert(firstRect, to: nil))
    input.insertionAnchor = anchor
    input.insertionAttemptID = attempt
    input.setMarkedText(marked, selectedRange: .init(location: 3, length: 0),
      replacementRange: .init(location: NSNotFound, length: 0))

    var actual = NSRange(location: NSNotFound, length: 0)
    let rect = input.firstRect(forCharacterRange: .init(location: 0, length: 3), actualRange: &actual)
    XCTAssertEqual(actual, NSRange(location: 0, length: 2))
    XCTAssertEqual(rect, expected)
    XCTAssertEqual(input.firstRect(forCharacterRange: .init(location: 1, length: 1),
      actualRange: &actual), expected)
    XCTAssertEqual(actual, NSRange(location: 0, length: 2), "A UTF-16 surrogate half owns one visible emoji")
    let secondID = try XCTUnwrap(presentation.projection.markedCells.last?.id)
    let secondRect = try XCTUnwrap(field.measuredRect(for: secondID))
    let expectedSecond = window.convertToScreen(field.convert(secondRect, to: nil))
    XCTAssertEqual(input.firstRect(forCharacterRange: .init(location: 2, length: 1),
      actualRange: &actual), expectedSecond)
    XCTAssertEqual(actual, NSRange(location: 2, length: 1))
    XCTAssertEqual(input.firstRect(forCharacterRange: .init(location: 2, length: 100),
      actualRange: &actual), expectedSecond)
    XCTAssertEqual(actual, NSRange(location: 2, length: 1), "A proposed range may extend beyond marked text")
    field.setFrameOrigin(.init(x: 70, y: 40))
    let moved = window.convertToScreen(field.convert(firstRect, to: nil))
    XCTAssertEqual(input.firstRect(forCharacterRange: .init(location: 0, length: 3),
      actualRange: nil), moved)
    input.setMarkedText("改", selectedRange: .init(location: 1, length: 0),
      replacementRange: .init(location: NSNotFound, length: 0))
    XCTAssertNotEqual(input.firstRect(forCharacterRange: .init(location: 0, length: 1),
      actualRange: nil), moved, "A newer candidate cannot borrow the prior rendering")
    input.setMarkedText(marked, selectedRange: .init(location: 3, length: 0),
      replacementRange: .init(location: NSNotFound, length: 0))
    input.insertionAttemptID = UUID()
    XCTAssertNotEqual(input.firstRect(forCharacterRange: .init(location: 0, length: 3),
      actualRange: nil), moved)
    input.insertionAttemptID = attempt
    field.isHidden = true
    XCTAssertNotEqual(input.firstRect(forCharacterRange: .init(location: 0, length: 3),
      actualRange: nil), moved)
  }

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
