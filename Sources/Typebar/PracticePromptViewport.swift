import AppKit
import SwiftUI

/// The bounded prompt scroller, shared by the practice screen and offscreen QA.
struct PracticePromptViewport<Content: View>: View {
  let text: AttributedString
  let font: NSFont
  let lineSpacing: CGFloat
  let isRightToLeft: Bool
  let lineCount: Int
  var maximumTextWidth: CGFloat? = nil
  var horizontalTextInset: CGFloat = 0
  var measuresTextRows = true
  @ViewBuilder var content: () -> Content
  @State private var measuredHeight: CGFloat?

  var body: some View {
    ScrollView {
      content().background {
        if measuresTextRows {
          GeometryReader { proxy in
            Color.clear.preference(key: PracticeViewportHeightKey.self,
              value: PromptViewportLayout.height(in: text,
                width: min(maximumTextWidth ?? .greatestFiniteMagnitude,
                  max(0, proxy.size.width - horizontalTextInset)),
                font: font, lineSpacing: lineSpacing, isRightToLeft: isRightToLeft,
                lineCount: lineCount))
          }
        }
      }
      // Keep a final active row movable even when fewer than three rows remain.
      .padding(.bottom, measuresTextRows
        ? measuredHeight ?? PromptViewportLayout.fallbackHeight(font: font, lineSpacing: lineSpacing, lineCount: lineCount)
        : 0)
    }
    .frame(height: measuresTextRows
      ? measuredHeight ?? PromptViewportLayout.fallbackHeight(font: font, lineSpacing: lineSpacing, lineCount: lineCount)
      : 184)
    .onPreferenceChange(PracticeViewportHeightKey.self) { height in
      if let height, measuredHeight != height { measuredHeight = height }
    }
  }
}

private struct PracticeViewportHeightKey: PreferenceKey {
  static let defaultValue: CGFloat? = nil
  static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
    if let next = nextValue() { value = next }
  }
}

enum PromptViewportLayout {
  static func height(forRowHeights rows: [CGFloat], lineCount: Int) -> CGFloat? {
    let visible = Array(rows.prefix(lineCount))
    guard !visible.isEmpty else { return nil }
    return (visible.reduce(0, +) / CGFloat(visible.count) * CGFloat(lineCount)).rounded(.up)
  }

  static func fallbackHeight(font: NSFont, lineSpacing: CGFloat, lineCount: Int) -> CGFloat {
    (NSLayoutManager().defaultLineHeight(for: font) + lineSpacing) * CGFloat(lineCount)
  }

  static func height(in text: AttributedString, width: CGFloat, font: NSFont,
    lineSpacing: CGFloat, isRightToLeft: Bool = false, lineCount: Int) -> CGFloat {
    let fallback = fallbackHeight(font: font, lineSpacing: lineSpacing, lineCount: lineCount)
    guard width.isFinite, width > 0, !text.characters.isEmpty else { return fallback }
    let storage = PromptCaretLayout.preparedStorage(in: text, font: font,
      lineSpacing: lineSpacing, isRightToLeft: isRightToLeft)
    let manager = NSLayoutManager()
    let container = NSTextContainer(size: .init(width: width, height: .greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    manager.addTextContainer(container)
    storage.addLayoutManager(manager)
    let glyphCount = manager.numberOfGlyphs
    var glyph = 0, rows: [CGFloat] = []
    while glyph < glyphCount, rows.count < lineCount {
      var range = NSRange()
      let rect = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &range)
      guard range.length > 0 else { break }
      let next = NSMaxRange(range)
      // TextKit omits inter-line spacing on the final fragment. The viewport
      // still reserves complete rows, including a short or empty prompt.
      rows.append(rect.height + (next == glyphCount ? lineSpacing : 0))
      glyph = next
    }
    return height(forRowHeights: rows, lineCount: lineCount) ?? fallback
  }
}
