import AppKit
import SwiftUI
import XCTest
@testable import Typebar

final class PromptRenderingAssemblyTests: XCTestCase {
  @MainActor func testNativeTextHostingRecordsInitialAndChangedLayoutWithoutLaunchingApplication() {
    for count in [60, 300, 1_200] {
      let glyphs = Array(repeating: TypingPromptGlyph(character: "a", state: .pending), count: count)
      func rendering(completed: Bool) -> PromptRendering {
        PromptRendering.make(glyphs: glyphs, indices: Array(glyphs.indices)) { index, _ in
          var cell = AttributedString(index.isMultiple(of: 7) ? " " : "a")
          cell.foregroundColor = completed && index == 0 ? .orange : .gray
          return cell
        }
      }
      func content(_ rendering: PromptRendering) -> some View {
        Text(rendering.text)
          .font(.system(size: 28, weight: .medium, design: .monospaced))
          .lineSpacing(12).textSelection(.disabled)
          .fixedSize(horizontal: false, vertical: true)
          .frame(width: 400, alignment: .leading)
      }
      let initial = rendering(completed: false), changed = rendering(completed: true)
      let start = ProcessInfo.processInfo.systemUptime
      let host = NSHostingView(rootView: content(initial))
      let size = host.fittingSize
      host.frame = CGRect(origin: .zero, size: size)
      host.layoutSubtreeIfNeeded()
      let initialElapsed = ProcessInfo.processInfo.systemUptime - start
      let updateStart = ProcessInfo.processInfo.systemUptime
      host.rootView = content(changed)
      let updatedSize = host.fittingSize
      host.frame = CGRect(origin: .zero, size: updatedSize)
      host.layoutSubtreeIfNeeded()
      let updateElapsed = ProcessInfo.processInfo.systemUptime - updateStart
      print("prompt-text-host glyphs=\(count) initial=\(initialElapsed) changed=\(updateElapsed)")
      XCTAssertGreaterThan(size.height, 28)
      XCTAssertEqual(size, updatedSize, "A color-only input update must not change text geometry")
      XCTAssertEqual(changed.glyphCharacterOffsets[count - 1], count - 1)
      XCTAssertNil(host.window, "This diagnostic must not launch or display an application window")
    }
  }

  func testAssemblyPreservesAttributedPrefixOffsetsAcrossUnicodeBoundaries() {
    let cases = [
      ["amber", " ", "birch", ""],
      ["a", "\u{301}", "b", "🙂"],
      ["\r", "\n", "x"],
      ["🇺", "🇸", "🇨", "🇦"],
      ["👩", "\u{200D}", "💻", "尾"],
      ["س", "لام", " ", "候选🙂"],
      ["", "", "a", "\n", "b"]
    ]
    for chunks in cases {
      let glyphs = chunks.map { _ in TypingPromptGlyph(character: "a", state: .pending) }
      var expected = AttributedString(), offsets: [Int: Int] = [:]
      let cells = chunks.enumerated().map { index, chunk in
        var cell = AttributedString(chunk)
        cell.foregroundColor = index.isMultiple(of: 2) ? .orange : .blue
        return cell
      }
      for index in chunks.indices {
        offsets[index] = expected.characters.count
        expected += cells[index]
      }
      var rendered: [Int] = []
      let actual = PromptRendering.make(glyphs: glyphs, indices: Array(glyphs.indices),
        emptyWordPlaceholderGlyphID: glyphs.count - 1) { index, _ in
        rendered.append(index)
        return cells[index]
      }
      XCTAssertEqual(actual.text, expected)
      XCTAssertEqual(actual.glyphCharacterOffsets, offsets)
      XCTAssertEqual(rendered, Array(glyphs.indices))
      XCTAssertEqual(actual.emptyWordPlaceholderGlyphID, glyphs.count - 1)
    }
  }

  func testLongASCIIAssemblyKeepsEveryOffsetAndEmitsBoundedTimingEvidence() {
    for count in [100, 500, 2_000] {
      let glyphs = Array(repeating: TypingPromptGlyph(character: "a", state: .pending), count: count)
      var cell = AttributedString("a ")
      cell.foregroundColor = .orange
      let start = ProcessInfo.processInfo.systemUptime
      let result = PromptRendering.make(glyphs: glyphs, indices: Array(glyphs.indices)) { _, _ in cell }
      let elapsed = ProcessInfo.processInfo.systemUptime - start
      print("prompt-assembly glyphs=\(count) seconds=\(elapsed)")
      XCTAssertEqual(String(result.text.characters), String(repeating: "a ", count: count))
      XCTAssertEqual(result.glyphCharacterOffsets, Dictionary(uniqueKeysWithValues: (0..<count).map { ($0, $0 * 2) }))
    }
  }
}
