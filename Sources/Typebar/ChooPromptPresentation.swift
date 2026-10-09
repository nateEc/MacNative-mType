import AppKit
import SwiftUI

/// Rotation owns transforms, never correctness or display policy. Select the
/// same attributed cells as ASL, preserving IDs and anonymous retired rows.
struct ChooPromptPresentation {
  let cells: [ASLPromptCellPlan.Cell]
  let structuralBreaksBefore: [Int: Int]
  let trailingStructuralBreaks: Int
  let compositionMap: PromptCompositionTextMap?
  let projectedSeparators: Set<Int>

  init(glyphs: [TypingPromptGlyph], ids: [Int], rendering: PromptRendering) {
    cells = ASLPromptCellPlan(glyphs: glyphs, ids: ids, rendering: rendering).cells
    compositionMap = rendering.compositionTextMap
    projectedSeparators = Set(compositionMap?.fieldRuns.flatMap(\.cells).filter(\.isGap).map(\.id) ?? [])
    if let map = compositionMap {
      var offset = 0, pending = 0, before: [Int: Int] = [:]
      for field in map.fieldRuns {
        pending += field.removedReturns
        if !field.cells.isEmpty {
          if pending > 0 { before[offset] = pending; pending = 0 }
          offset += field.cells.count
        }
      }
      structuralBreaksBefore = before
      trailingStructuralBreaks = pending
      return
    }
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

/// Independent rotation layers retain field allocation and slot identities.
/// Layer ink has the existing two-point overhang; allocation never includes it.
@MainActor struct ChooPromptFieldLayout {
  static let inkOverhang: CGFloat = 2
  let frames: [CGRect]
  let height: CGFloat

  init(presentation: ChooPromptPresentation, font: NSFont, width: CGFloat) {
    guard let map = presentation.compositionMap else { frames = []; height = 0; return }
    let lineHeight = ceil(font.ascender - font.descender + font.leading)
    var items: [ASLPromptFlowGeometry.Cell] = [], indices: [Int] = [], contents: [ASLPromptGlyphContent] = []
    for (group, field) in map.fieldRuns.enumerated() {
      for (index, cell) in field.cells.enumerated() {
        let content = ASLPromptGlyphContent(glyph: cell.glyph, text: cell.text)
        let advance = max(1, ceil(ChooPromptPresentation.nativeText(content.main, font: font).size().width))
        indices.append(items.count); contents.append(content)
        items.append(.init(size: .init(width: advance, height: lineHeight), wordID: group,
          isLineBreak: field.endsWithReturn && index == field.cells.count - 1, isSeparator: cell.isGap))
      }
      for _ in 0..<field.removedReturns {
        items.append(.init(size: .init(width: 0, height: lineHeight), wordID: group, isLineBreak: true))
      }
    }
    let geometry = ASLPromptFlowGeometry(cells: items, width: max(1, width))
    var frames: [CGRect] = [], bottom = geometry.size.height
    for (index, item) in indices.enumerated() {
      let frame = CGRect(origin: geometry.positions[item],
        size: .init(width: items[item].size.width + Self.inkOverhang, height: lineHeight))
      frames.append(frame)
      if let hint = contents[index].hint {
        let metrics = ChooPromptPresentation.nativeHint(hint, font: font)
        bottom = max(bottom, frame.minY + metrics.top + metrics.height)
      }
    }
    if items.last?.isLineBreak == true { bottom = max(bottom, geometry.size.height + lineHeight) }
    self.frames = frames; height = max(lineHeight, bottom)
  }
}
