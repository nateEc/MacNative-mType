import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class BelowCompositionPromptTests: XCTestCase {
  func testCollapsedWhitespaceAndComposedCharactersMapBackToWholeSourceRanges() {
    let spaces = BelowCompositionProjection("a \n b")
    XCTAssertEqual(spaces.displayed, "a b")
    XCTAssertEqual(spaces.firstVisibleRange(for: .init(location: 2, length: 1))?.display,
      NSRange(location: 1, length: 1))
    XCTAssertEqual(spaces.firstVisibleRange(for: .init(location: 2, length: 1))?.actual,
      NSRange(location: 1, length: 3))
    XCTAssertEqual(spaces.firstVisibleRange(for: .init(location: 4, length: 1))?.display,
      NSRange(location: 2, length: 1))
    let composed = BelowCompositionProjection("e\u{301} 😀")
    XCTAssertEqual(composed.firstVisibleRange(for: .init(location: 1, length: 1))?.actual,
      NSRange(location: 0, length: 2))
    XCTAssertEqual(composed.firstVisibleRange(for: .init(location: 4, length: 1))?.actual,
      NSRange(location: 3, length: 2))
    let leadingCombined = BelowCompositionProjection(" \u{0301}b")
    XCTAssertEqual(leadingCombined.displayed, "\u{0301}b",
      "CSS collapses the leading ASCII space even when a combining scalar follows")
    XCTAssertEqual(leadingCombined.firstVisibleRange(for: .init(location: 1, length: 1))?.actual,
      NSRange(location: 0, length: 2))
    XCTAssertNil(BelowCompositionProjection("\t  ").firstVisibleRange(for: .init(location: 1, length: 1)))
  }

  func testControlCharactersAndThemeUpdatesPreserveCandidateIdentityAndEmptyLine() throws {
    let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
    func root(_ text: String, _ color: NSColor) -> some View {
      BelowCompositionPrompt(text: text, font: font, color: color)
        .frame(width: 400)
        .frame(width: 500, height: 600, alignment: .top)
    }
    let host = NSHostingView(rootView: root("", .red))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 500, height: 600),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    func flush() {
      for _ in 0..<3 {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
      }
    }
    func fields(_ view: NSView) -> [NSTextField] {
      (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(fields)
    }
    flush()
    let field = try XCTUnwrap(fields(host).first)
    let emptyHeight = field.bounds.height
    let candidates: [(String, String)] = [
      ("首行\n次行\n末行", "首行 次行 末行"),
      ("a\n\n  b", "a b"),
      ("候\t选", "候 选"),
      ("  a \t\t b  ", "a b"),
      ("\t  ", " "),
      ("a\u{00A0}\u{00A0}b", "a\u{00A0}\u{00A0}b"),
      ("abc \u{2067}שלום\u{2069} xyz", "abc \u{2067}שלום\u{2069} xyz"),
      ("e\u{301} 😀", "e\u{301} 😀"),
    ]
    for (text, displayed) in candidates {
      host.rootView = root(text, .blue)
      flush()
      XCTAssertTrue(fields(host).first === field)
      XCTAssertEqual(Array(field.stringValue.utf16), Array(displayed.utf16))
      XCTAssertEqual(field.accessibilityLabel(), "正在组合：\(text)")
      XCTAssertEqual(field.textColor, .blue)
      XCTAssertEqual(field.font, font)
      XCTAssertTrue(host.bounds.contains(field.convert(field.bounds, to: host)))
      if text.contains("\n") {
        XCTAssertEqual(field.bounds.height, emptyHeight, accuracy: 1)
      }
      host.rootView = root("", .red)
      flush()
      XCTAssertTrue(fields(host).first === field)
      XCTAssertEqual(field.stringValue, " ")
      XCTAssertEqual(field.accessibilityLabel(), "组合输入候选行")
      XCTAssertEqual(field.textColor, .red)
      XCTAssertEqual(field.bounds.height, emptyHeight, accuracy: 1)
      XCTAssertFalse(window.isVisible)
    }
  }

  func testNarrowRTLAndMixedCandidatesResizeAndCancelWithoutReplacingNativeOwner() throws {
    let fonts = [NSFont.systemFont(ofSize: 28), NSFont.monospacedSystemFont(ofSize: 40, weight: .regular)]
    let candidates = ["سلام عالم שלום עולם", "候选中文 mixed שלום", "x̄ʌʃ café 한글"]
    for font in fonts {
      for candidateText in candidates {
        let text = Array(repeating: candidateText, count: 3).joined(separator: " ")
        func root(_ text: String, _ width: CGFloat, _ font: NSFont) -> some View {
          BelowCompositionPrompt(text: text, font: font, color: .secondaryLabelColor)
            .frame(width: width)
            .frame(width: 1200, height: 800, alignment: .top)
        }
        let host = NSHostingView(rootView: root(text, 1000, font))
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 1200, height: 800),
          styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        func flush() {
          for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
          }
        }
        func fields(_ view: NSView) -> [NSTextField] {
          (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(fields)
        }
        flush()
        let field = try XCTUnwrap(fields(host).first)
        let wideHeight = field.bounds.height
        host.rootView = root(text, 180, font)
        flush()
        XCTAssertTrue(fields(host).first === field)
        XCTAssertEqual(field.stringValue, text)
        XCTAssertEqual(field.font, font)
        XCTAssertEqual(field.alignment, .center)
        // AppKit adds two points of label bounds outside each alignment edge.
        XCTAssertEqual(field.alignmentRect(forFrame: field.frame).width, 180, accuracy: 1)
        XCTAssertGreaterThan(field.bounds.height, wideHeight)
        let measured = try XCTUnwrap(field.cell).cellSize(forBounds:
          CGRect(x: 0, y: 0, width: 180, height: CGFloat.greatestFiniteMagnitude))
        XCTAssertGreaterThanOrEqual(field.bounds.height, ceil(measured.height))
        XCTAssertTrue(host.bounds.contains(field.convert(field.bounds, to: host)))
        host.rootView = root("", 180, font)
        flush()
        XCTAssertTrue(fields(host).first === field)
        XCTAssertEqual(field.stringValue, " ")
        XCTAssertEqual(field.accessibilityLabel(), "组合输入候选行")
        XCTAssertLessThanOrEqual(field.bounds.height, wideHeight)
        XCTAssertGreaterThanOrEqual(field.bounds.height, font.ascender - font.descender)
        host.rootView = root(text, 1000, fonts[0])
        flush()
        XCTAssertTrue(fields(host).first === field)
        XCTAssertEqual(field.stringValue, text)
        XCTAssertEqual(field.font, fonts[0])
        XCTAssertEqual(field.alignmentRect(forFrame: field.frame).width, 1000, accuracy: 1)
        XCTAssertFalse(window.isVisible)
      }
    }
  }
}
