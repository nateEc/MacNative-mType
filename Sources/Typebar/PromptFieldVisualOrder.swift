import AppKit
import SwiftUI

/// Resolves the physical order of one unwrapped field without changing its
/// independently shaped drawing cells. Allocation and caret integration are
/// separate consumers; this does not mutate accepted input or identities.
@MainActor enum PromptFieldVisualOrder {
  static func cellIDs(_ cells: [PromptFieldTextRun.Cell], font: NSFont,
    rightToLeft: Bool) -> [Int] {
    var text = AttributedString(), ranges: [NSRange] = []
    var offset = 0
    for cell in cells {
      let main = ASLPromptGlyphContent(glyph: cell.glyph, text: cell.text).main
      let length = String(main.characters).utf16.count
      ranges.append(.init(location: offset, length: length))
      offset += length
      text += main
    }
    let storage = TapePromptTextStorage.prepare(text, font: font, rightToLeft: rightToLeft)
    let paragraph = NSMutableParagraphStyle()
    paragraph.baseWritingDirection = rightToLeft ? .rightToLeft : .leftToRight
    paragraph.alignment = .left
    storage.addAttribute(.paragraphStyle, value: paragraph, range: .init(location: 0, length: storage.length))
    let manager = NSLayoutManager()
    let container = NSTextContainer(size: .init(width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    manager.addTextContainer(container)
    storage.addLayoutManager(manager)
    manager.ensureLayout(for: container)
    let positions = ranges.map { range -> (rect: CGRect, level: UInt8)? in
      guard range.length > 0 else { return nil }
      let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
      guard glyphs.length > 0 else { return nil }
      var level: UInt8 = 0
      _ = manager.getGlyphs(in: .init(location: glyphs.location, length: 1), glyphs: nil,
        properties: nil, characterIndexes: nil, bidiLevels: &level)
      return (TapePromptTextStorage.advanceRect(glyphs, manager: manager, container: container), level)
    }
    var ordered = cells.indices.filter { positions[$0] != nil }.sorted { lhs, rhs in
      let first = positions[lhs]!, second = positions[rhs]!
      if first.rect.minY != second.rect.minY { return first.rect.minY < second.rect.minY }
      if first.rect.minX != second.rect.minX { return first.rect.minX < second.rect.minX }
      if first.level != second.level { return first.level < second.level }
      if first.level % 2 == 1 { return lhs > rhs }
      return lhs < rhs
    }.makeIterator()
    // Empty display cells keep their slots. Mixing source-index comparisons
    // for empty cells with visual-position comparisons can form a cycle.
    return cells.indices.map { index in
      positions[index] == nil ? cells[index].id : cells[ordered.next()!].id
    }
  }
}
