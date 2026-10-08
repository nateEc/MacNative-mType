import SwiftUI

/// Ownership is target/session metadata, not the possibly replaced display
/// string. IDs survive reordered extras and retirement of the visible prefix.
struct ASLPromptWordPlan {
  let wordByGlyphID: [Int: Int]
  let placeholderGlyphID: Int?

  init(glyphs: [TypingPromptGlyph], ids: [Int], words: [TypingPromptWordPresentation]?, placeholderGlyphID: Int? = nil) {
    self.placeholderGlyphID = placeholderGlyphID
    var owners: [Int: Int] = [:]
    if let words {
      let visibleIDs = Set(ids)
      let firstID = ids.min(), lastID = ids.max()
      let separators = Set(glyphs.enumerated().compactMap { index, glyph in
        ids.indices.contains(index) && glyph.state != .extra && (glyph.character == " " || glyph.character == "\n")
          ? ids[index] : nil
      })
      for word in words {
        let owner = word.range.lowerBound
        if !word.range.isEmpty, let firstID, let lastID {
          let lower = max(word.range.lowerBound, firstID), upper = min(word.range.upperBound - 1, lastID)
          if lower <= upper {
            for id in lower...upper where visibleIDs.contains(id) { owners[id] = owner }
          }
        }
        for id in word.extraGlyphIndices where visibleIDs.contains(id) { owners[id] = owner }
        // End positions without a real separator may instead be an extra ID.
        // Adjacent no-space words already have their own target ranges.
        if separators.contains(word.range.upperBound) { owners[word.range.upperBound] = owner }
      }
    } else {
      var owner = ids.first ?? 0
      for (index, glyph) in glyphs.enumerated() where ids.indices.contains(index) {
        owners[ids[index]] = owner
        if glyph.state != .extra && (glyph.character == " " || glyph.character == "\n"), index + 1 < ids.count {
          owner = ids[index + 1]
        }
      }
    }
    wordByGlyphID = owners
  }

  func measuredWords(frames: [Int: CGRect], glyphs: [TypingPromptGlyph], ids: [Int]) -> [Int: CGRect] {
    var words: [Int: CGRect] = [:]
    for (index, glyph) in glyphs.enumerated() where ids.indices.contains(index) {
      guard !(glyph.character == " " && glyph.state != .extra && ids[index] != placeholderGlyphID),
        let owner = wordByGlyphID[ids[index]], let frame = frames[ids[index]],
        frame.width > 0, frame.height > 0 else { continue }
      words[owner] = words[owner].map { $0.union(frame) } ?? frame
    }
    return words
  }
}

struct ASLPromptWordIDKey: LayoutValueKey { static let defaultValue = 0 }
struct ASLPromptLineBreakKey: LayoutValueKey { static let defaultValue = false }
struct ASLPromptSeparatorKey: LayoutValueKey { static let defaultValue = false }

/// An outer word owns its full allocated width even if its last inner line is
/// short. Inter-word gaps remain native separator cells, not copied CSS/assets.
struct ASLPromptFlowGeometry {
  struct Cell {
    let size: CGSize
    let wordID: Int
    var isLineBreak = false
    var isSeparator = false
  }
  let positions: [CGPoint]
  let size: CGSize

  init(cells: [Cell], width: CGFloat?, rowSpacing: CGFloat = 12) {
    let naturalWidth = cells.reduce(CGFloat.zero) { $0 + $1.size.width }
    let proposedWidth = width.flatMap { $0.isFinite ? max(0, $0) : nil }
    let limit = proposedWidth ?? naturalWidth
    var positions = Array(repeating: CGPoint.zero, count: cells.count)
    var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maximumX: CGFloat = 0
    var start = 0
    while start < cells.count {
      var end = start + 1
      // Return is the final measured cell of its word, not a zero-size node
      // preceding it. A newline-only word therefore has a full line height.
      while !cells[end - 1].isLineBreak, end < cells.count,
        cells[end].wordID == cells[start].wordID { end += 1 }
      let natural = cells[start..<end].reduce(CGFloat.zero) { $0 + $1.size.width }
      let allocated = min(natural, limit)
      if x > 0 && x + allocated > limit {
        maximumX = max(maximumX, x); x = 0; y += rowHeight + rowSpacing; rowHeight = 0
      }
      var innerX: CGFloat = 0, innerY: CGFloat = 0, innerHeight: CGFloat = 0
      for index in start..<end {
        let cell = cells[index]
        // A trailing gap has no ink and must not create a blank inner row.
        if !cell.isSeparator && innerX > 0 && innerX + cell.size.width > allocated {
          innerX = 0; innerY += innerHeight + rowSpacing; innerHeight = 0
        }
        positions[index] = .init(x: x + innerX, y: y + innerY)
        innerX += cell.size.width; innerHeight = max(innerHeight, cell.size.height)
      }
      x += allocated; rowHeight = max(rowHeight, innerY + innerHeight)
      if cells[end - 1].isLineBreak {
        maximumX = max(maximumX, x); x = 0; y += rowHeight + rowSpacing; rowHeight = 0
      }
      start = end
    }
    self.positions = positions
    size = .init(width: proposedWidth ?? max(maximumX, x), height: y + rowHeight)
  }
}

struct ASLPromptFlowLayout: Layout {
  private func geometry(_ subviews: Subviews, width: CGFloat?) -> ASLPromptFlowGeometry {
    .init(cells: subviews.map {
      .init(size: $0.sizeThatFits(.unspecified), wordID: $0[ASLPromptWordIDKey.self],
        isLineBreak: $0[ASLPromptLineBreakKey.self], isSeparator: $0[ASLPromptSeparatorKey.self])
    }, width: width)
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    geometry(subviews, width: proposal.width).size
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let result = geometry(subviews, width: bounds.width)
    for (index, subview) in subviews.enumerated() {
      subview.place(at: result.positions[index].applying(.init(translationX: bounds.minX, y: bounds.minY)),
        anchor: .topLeading, proposal: .unspecified)
    }
  }
}
