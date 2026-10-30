import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class BelowCompositionControlWhitespaceTests: XCTestCase {
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
