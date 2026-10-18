import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class PromptRenderingScaleTests: XCTestCase {
  func testFullASCIISelectionKeepsEveryOffsetAndText() {
    let glyphs = Array(repeating: TypingPromptGlyph(character: "a", state: .pending), count: 10_000)
    let started = ProcessInfo.processInfo.systemUptime
    let rendered = PromptRendering.make(glyphs: glyphs, indices: Array(glyphs.indices)) { _, _ in
      AttributedString("a")
    }
    print("full ASCII prompt rendering 10000 glyphs: \(ProcessInfo.processInfo.systemUptime - started) seconds")
    XCTAssertEqual(String(rendered.text.characters), String(repeating: "a", count: glyphs.count))
    XCTAssertEqual(rendered.glyphCharacterOffsets.count, glyphs.count)
    for index in glyphs.indices { XCTAssertEqual(rendered.glyphCharacterOffsets[index], index) }
  }

  func testMixedGraphemeAndAttributeBoundariesKeepCumulativeOffsets() {
    let source = ["e", "\u{301}", "👩", "\u{200D}", "💻", "a", "\n", "↵\n", "候"]
    let glyphs = source.map { _ in TypingPromptGlyph(character: "a", state: .pending) }
    let fragments = source.enumerated().map { index, value -> AttributedString in
      var fragment = AttributedString(value)
      fragment.foregroundColor = index.isMultiple(of: 2) ? .blue : .red
      return fragment
    }
    var expected = AttributedString()
    var offsets: [Int: Int] = [:]
    for index in fragments.indices {
      offsets[index] = expected.characters.count
      expected += fragments[index]
    }
    let rendered = PromptRendering.make(glyphs: glyphs, indices: Array(glyphs.indices)) { index, _ in
      fragments[index]
    }
    XCTAssertEqual(rendered.text, expected)
    XCTAssertEqual(rendered.glyphCharacterOffsets, offsets)
  }
}
