import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class BelowCompositionPromptTests: XCTestCase {
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
