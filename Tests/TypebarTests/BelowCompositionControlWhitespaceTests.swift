import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class BelowCompositionControlWhitespaceTests: XCTestCase {
  func testAdvancingControlsKeepGraphemesAndRectsAcrossFontsAndDirections() throws {
    for font in [NSFont.monospacedSystemFont(ofSize: 28, weight: .regular), NSFont.systemFont(ofSize: 40)] {
      func root(_ text: String) -> some View {
        BelowCompositionPrompt(text: text, font: font, color: .blue)
          .frame(width: 800, height: 200, alignment: .top)
      }
      let host = NSHostingView(rootView: root("ab"))
      let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 800, height: 200),
        styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.contentView = host
      defer { window.contentView = nil; window.close() }
      func field(_ view: NSView) -> BelowCompositionField? {
        (view as? BelowCompositionField) ?? view.subviews.lazy.compactMap { field($0) }.first
      }
      func flush() {
        for _ in 0..<3 { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
      }
      flush()
      let original = try XCTUnwrap(field(host))
      for control in ["\u{000B}", "\u{000C}", "\u{0085}"] {
        for (candidate, offset) in [("😀\(control)e\u{301}", 2), ("سلام\(control)שלום", 4)] {
          host.rootView = root(candidate); flush()
          let current = try XCTUnwrap(field(host))
          XCTAssertTrue(current === original)
          XCTAssertEqual(current.stringValue, candidate)
          XCTAssertEqual(current.sourceText, candidate)
          // Fallback glyph metrics differ slightly between NSCell and TextKit.
          // Check actual first/last glyph rows and reserved height, rather than
          // equating an emoji/Arabic line with an ASCII font's line height.
          let first = try XCTUnwrap(current.markedScreenRect(for: .init(location: 0, length: 1), markedText: candidate))
          let last = try XCTUnwrap(current.markedScreenRect(for: .init(location: candidate.utf16.count - 1, length: 1), markedText: candidate))
          XCTAssertEqual(first.rect.minY, last.rect.minY, accuracy: 1)
          XCTAssertEqual(first.rect.height, last.rect.height, accuracy: 1)
          XCTAssertEqual(current.bounds.height, first.rect.height, accuracy: 1)
          XCTAssertEqual(current.font, font)
          XCTAssertEqual(current.textColor, .blue)
          let source = NSRange(location: offset, length: 1)
          let rect = try XCTUnwrap(current.markedScreenRect(for: source, markedText: candidate))
          XCTAssertEqual(rect.actualRange, source)
          XCTAssertGreaterThan(rect.rect.width, 0)
          let before = try XCTUnwrap(current.insertionScreenRect(at: offset, markedText: candidate))
          let after = try XCTUnwrap(current.insertionScreenRect(at: offset + 1, markedText: candidate))
          XCTAssertGreaterThan(abs(after.minX - before.minX), 0)
          if offset == 2 {
            let combined = try XCTUnwrap(current.markedScreenRect(for: .init(location: 4, length: 1), markedText: candidate))
            XCTAssertEqual(combined.actualRange, NSRange(location: 3, length: 2))
          }
        }
      }
      XCTAssertFalse(window.isVisible)
    }
  }

  func testZeroAdvanceControlsKeepSeparateWhitespaceRunsAndUTF16Mappings() {
    for control in ["\r", "\u{2028}", "\u{2029}"] {
      for (source, visible) in [("a\(control)b", "ab"), ("a \(control) b", "a  b"),
        (" \(control) b", " b"), ("a \(control) ", "a "), (control, "")] {
        XCTAssertEqual(BelowCompositionProjection(source).displayed, visible, source.debugDescription)
      }
      let projection = BelowCompositionProjection("a \(control) b")
      XCTAssertNil(projection.firstVisibleRange(for: .init(location: 2, length: 1)))
      for (sourceOffset, displayOffset) in [(1, 1), (3, 2)] {
        let range = projection.firstVisibleRange(for: .init(location: sourceOffset, length: 1))
        XCTAssertEqual(range?.display, NSRange(location: displayOffset, length: 1))
        XCTAssertEqual(range?.actual, NSRange(location: sourceOffset, length: 1))
      }
      XCTAssertEqual(projection.displayInsertionOffset(for: 2), 2)
      XCTAssertEqual(projection.displayInsertionOffset(for: 3), 2)
      let unicode = BelowCompositionProjection("😀 \(control) e\u{301}")
      XCTAssertEqual(unicode.displayed, "😀  e\u{301}")
      XCTAssertEqual(unicode.firstVisibleRange(for: .init(location: 6, length: 1))?.actual,
        NSRange(location: 5, length: 2))
      XCTAssertNil(unicode.firstVisibleRange(for: .init(location: 3, length: 1)))
    }
  }

  func testZeroAdvanceControlsKeepOneNativeRowAndTheOriginalCandidate() throws {
    let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
    func root(_ text: String) -> some View {
      BelowCompositionPrompt(text: text, font: font, color: .labelColor)
        .frame(width: 800, height: 200, alignment: .top)
    }
    let host = NSHostingView(rootView: root("ab"))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 800, height: 200),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.contentView = nil; window.close() }
    func flush() {
      for _ in 0..<3 {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
      }
    }
    func field(in view: NSView) -> BelowCompositionField? {
      (view as? BelowCompositionField) ?? view.subviews.lazy.compactMap { field(in: $0) }.first
    }
    flush()
    let original = try XCTUnwrap(field(in: host)), baselineHeight = original.bounds.height
    for control in ["\r", "\u{2028}", "\u{2029}"] {
      let candidate = "a \(control) b"
      host.rootView = root(candidate)
      flush()
      let current = try XCTUnwrap(field(in: host))
      XCTAssertTrue(current === original)
      XCTAssertEqual(current.stringValue, "a  b")
      XCTAssertEqual(current.bounds.height, baselineHeight, accuracy: 1)
      XCTAssertEqual(current.sourceText, candidate)
      XCTAssertEqual(current.accessibilityLabel(), "正在组合：\(candidate)")
    }
    XCTAssertFalse(window.isVisible)
    XCTAssertNil(window.attachedSheet)
  }
}
