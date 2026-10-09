import AppKit
import SwiftUI

/// Rotation owns transforms, never correctness or display policy. Select the
/// same attributed cells as ASL, preserving IDs and anonymous retired rows.
struct ChooPromptPresentation {
  let cells: [ASLPromptCellPlan.Cell]
  let structuralBreaksBefore: [Int: Int]
  let trailingStructuralBreaks: Int

  init(glyphs: [TypingPromptGlyph], ids: [Int], rendering: PromptRendering) {
    cells = ASLPromptCellPlan(glyphs: glyphs, ids: ids, rendering: rendering).cells
    let breaks = rendering.structuralNewlineOffsets.values.sorted()
    var next = 0, before: [Int: Int] = [:]
    for (index, cell) in cells.enumerated() {
      guard let offset = rendering.characterOffset(forGlyphAt: cell.id) else { continue }
      let start = next
      while next < breaks.count, breaks[next] < offset { next += 1 }
      if next > start { before[index] = next - start }
    }
    structuralBreaksBefore = before
    trailingStructuralBreaks = breaks.count - next
  }

  static func nativeText(_ text: AttributedString, font: NSFont) -> NSAttributedString {
    let value = PromptCaretLayout.preparedStorage(in: text, font: font,
      lineSpacing: 0, isRightToLeft: false)
    // Core Animation draws AppKit attributes, not SwiftUI's environment.
    let string = String(text.characters)
    for run in text.runs {
      guard let lower = String.Index(run.range.lowerBound, within: string),
        let upper = String.Index(run.range.upperBound, within: string) else { continue }
      let range = NSRange(lower..<upper, in: string)
      if let color = run.foregroundColor { value.addAttribute(.foregroundColor, value: NSColor(color), range: range) }
      if let color = run.backgroundColor { value.addAttribute(.backgroundColor, value: NSColor(color), range: range) }
      if run.underlineStyle != nil { value.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
    }
    return value
  }

  static func nativeHint(_ hint: AttributedString, font: NSFont)
    -> (text: NSAttributedString, top: CGFloat, height: CGFloat) {
    // A baseline displacement must include the two fonts' ascent difference.
    let offset = -(hint.runs.first?.baselineOffset ?? 0)
    var hint = hint
    hint.baselineOffset = nil; hint.kern = nil
    let text = nativeText(hint, font: font)
    let hintFont = text.length > 0 ? text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont : nil
    let metrics = hintFont ?? font
    return (text, offset + font.ascender - metrics.ascender,
      ceil(metrics.ascender - metrics.descender + metrics.leading))
  }
}
