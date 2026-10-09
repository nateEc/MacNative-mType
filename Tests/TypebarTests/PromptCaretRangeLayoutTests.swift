import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class PromptCaretRangeLayoutTests: XCTestCase {
  private let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .medium)

  private func fullLayoutRect(_ text: AttributedString, range: NSRange,
    width: CGFloat, rtl: Bool, followsWhitespace: Bool, requestsTargetRange: Bool = false) -> CGRect? {
    let storage = PromptCaretLayout.preparedStorage(in: text, font: font, lineSpacing: 12, isRightToLeft: rtl)
    guard range.location >= 0, range.length > 0, range.location < storage.length,
      range.length <= storage.length - range.location else { return nil }
    let layout = NSLayoutManager()
    let container = NSTextContainer(size: .init(width: width, height: .greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    layout.addTextContainer(container); storage.addLayoutManager(layout)
    if requestsTargetRange { layout.ensureLayout(forCharacterRange: range) }
    else { layout.ensureLayout(for: container) }
    let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
    guard glyphs.length > 0 else { return nil }
    let rect = layout.boundingRect(forGlyphRange: glyphs, in: container).integral
    if followsWhitespace,
      (storage.string as NSString).substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      NSMaxRange(range) < storage.length {
      let nextRange = NSRange(location: NSMaxRange(range), length: 1)
      if requestsTargetRange { layout.ensureLayout(forCharacterRange: nextRange) }
      let next = layout.glyphRange(forCharacterRange: nextRange, actualCharacterRange: nil)
      let nextRect = layout.boundingRect(forGlyphRange: next, in: container).integral
      if nextRect.minY > rect.minY { return nextRect }
    }
    return rect
  }

  func testRangeAndCharacterGeometryMatchFullContainerLayoutAtEveryTarget() {
    for string in ["amber birch cedar tail", "a\nb\n\nc", "a\tbb cc", "a\u{301} 🙂 👩‍💻 🇺🇸 end", "سلام عالم نهاية", "abc سلام end", "\r\nxy"] {
      var text = AttributedString(string)
      text.foregroundColor = .orange
      for width: CGFloat in [32, 95, 350] {
        for rtl in [false, true] {
          for (offset, index) in string.indices.enumerated() {
            let range = NSRange(index..<string.index(after: index), in: string)
            let expected = fullLayoutRect(text, range: range, width: width, rtl: rtl, followsWhitespace: true)
            XCTAssertEqual(PromptCaretLayout.rect(in: text, characterOffset: offset,
              containerSize: .init(width: width, height: 100), font: font, lineSpacing: 12, isRightToLeft: rtl), expected)
            for followsWhitespace in [false, true] {
              XCTAssertEqual(fullLayoutRect(text, range: range, width: width, rtl: rtl,
                followsWhitespace: followsWhitespace, requestsTargetRange: true),
                fullLayoutRect(text, range: range, width: width, rtl: rtl, followsWhitespace: followsWhitespace))
              XCTAssertEqual(PromptCaretLayout.rect(in: text, utf16Range: range,
                containerSize: .init(width: width, height: 100), font: font, lineSpacing: 12,
                isRightToLeft: rtl, followsWrappedWhitespace: followsWhitespace),
                fullLayoutRect(text, range: range, width: width, rtl: rtl, followsWhitespace: followsWhitespace))
            }
          }
        }
      }
    }
  }

  func testLongPromptPrefixMiddleAndHintTailKeepFullLayoutGeometry() {
    for repetitions in [10, 200, 1_000] {
      var text = AttributedString(String(repeating: "amber birch ", count: repetitions))
      var hint = AttributedString("候选🙂")
      hint.font = .system(size: 13, weight: .semibold, design: .monospaced)
      hint.baselineOffset = -12; hint.kern = -18
      text += hint
      let string = String(text.characters)
      for offset in [0, string.count / 2, string.count - 1] {
        let index = string.index(string.startIndex, offsetBy: offset)
        let range = NSRange(index..<string.index(after: index), in: string)
        let fullStart = ProcessInfo.processInfo.systemUptime
        let expected = fullLayoutRect(text, range: range, width: 350, rtl: false, followsWhitespace: true)
        let fullElapsed = ProcessInfo.processInfo.systemUptime - fullStart
        let partialStart = ProcessInfo.processInfo.systemUptime
        let candidate = fullLayoutRect(text, range: range, width: 350, rtl: false,
          followsWhitespace: true, requestsTargetRange: true)
        let partialElapsed = ProcessInfo.processInfo.systemUptime - partialStart
        print("caret-range characters=\(string.count) offset=\(offset) full=\(fullElapsed) target=\(partialElapsed)")
        XCTAssertNotNil(expected)
        XCTAssertEqual(candidate, expected)
        XCTAssertEqual(PromptCaretLayout.rect(in: text, characterOffset: offset,
          containerSize: .init(width: 350, height: 135), font: font, lineSpacing: 12), expected)
        XCTAssertEqual(PromptCaretLayout.rect(in: text, utf16Range: range,
          containerSize: .init(width: 350, height: 135), font: font, lineSpacing: 12), expected)
      }
    }
    XCTAssertNil(PromptCaretLayout.rect(in: AttributedString("a"), characterOffset: 2,
      containerSize: .init(width: 350, height: 135), font: font, lineSpacing: 12))
    XCTAssertNil(PromptCaretLayout.rect(in: AttributedString("a"), utf16Range: .init(location: 1, length: 1),
      containerSize: .init(width: 350, height: 135), font: font, lineSpacing: 12))
  }
}
