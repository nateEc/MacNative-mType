import AppKit
import SwiftUI

/// Actual field and slot ownership survives concatenated grapheme fusion.
/// Nil ownership is explicit; it never borrows an adjacent field's identity.
struct PromptFieldTextRun: Equatable {
  struct Cell: Equatable {
    let id: Int
    let glyph: TypingPromptGlyph
    let text: AttributedString
    let isGap: Bool
  }
  let fieldID: Int?
  var cells: [Cell]
  var removedReturns = 0
}

/// Ordinary letters are independent boxes. Joining scripts shape within a
/// field only. Hints are separate drawing layers, never advances or caret ink.
@MainActor final class PromptFieldTextLayout {
  private final class Box {
    let manager = NSLayoutManager()
    let container = NSTextContainer(size: .init(width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude))
    let storage: NSTextStorage
    let ranges: [Int: NSRange]
    let hints: [Int: AttributedString]
    let cells: [PromptFieldTextRun.Cell]
    let fieldID: Int?
    let isGap: Bool
    let breaks: Bool
    var bounds: CGRect = .zero

    init(cells: [PromptFieldTextRun.Cell], fieldID: Int?, breaks: Bool,
      font: NSFont, rightToLeft: Bool, spacing: CGFloat, width: CGFloat) {
      self.cells = cells; self.fieldID = fieldID; self.breaks = breaks
      isGap = cells.count == 1 && cells[0].isGap
      var text = AttributedString(), ranges: [Int: NSRange] = [:], hints: [Int: AttributedString] = [:], unit = 0
      for cell in cells {
        let content = ASLPromptGlyphContent(glyph: cell.glyph, text: cell.text)
        let main = content.main
        ranges[cell.id] = .init(location: unit, length: String(main.characters).utf16.count)
        unit += ranges[cell.id]!.length; text += main
        hints[cell.id] = content.hint
      }
      self.ranges = ranges; self.hints = hints
      storage = TapePromptTextStorage.prepare(text, font: font, rightToLeft: rightToLeft)
      let paragraph = NSMutableParagraphStyle()
      paragraph.baseWritingDirection = rightToLeft ? .rightToLeft : .leftToRight
      paragraph.alignment = .left; paragraph.lineSpacing = spacing; paragraph.lineBreakMode = .byCharWrapping
      storage.addAttribute(.paragraphStyle, value: paragraph, range: .init(location: 0, length: storage.length))
      container.lineFragmentPadding = 0; manager.addTextContainer(container); storage.addLayoutManager(manager)
      manager.ensureLayout(for: container)
      bounds = occupiedBounds()
      if bounds.width > width, cells.count > 1 {
        container.containerSize.width = max(1, width)
        manager.ensureLayout(for: container); bounds = occupiedBounds()
        // A wrapped word owns its full allocation, not just the last row.
        bounds.size.width = max(bounds.width, width)
      }
      if storage.length == 0 || bounds.height == 0 { bounds.size.height = manager.defaultLineHeight(for: font) }
    }
    private func occupiedBounds() -> CGRect {
      TapePromptTextStorage.advanceRect(.init(location: 0, length: manager.numberOfGlyphs), manager: manager, container: container)
    }
    func rect(_ id: Int, origin: CGPoint) -> CGRect? {
      guard let range = ranges[id], range.length > 0 else { return nil }
      let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
      return TapePromptTextStorage.advanceRect(glyphs, manager: manager, container: container)
        .offsetBy(dx: origin.x - bounds.minX, dy: origin.y - bounds.minY)
    }
  }

  private var boxes: [Box] = []
  private var origins: [CGPoint] = []
  private var boxByCell: [Int: Int] = [:]
  private var followingCell: [Int: Int] = [:]
  private let aliases: [Int: [Int]]
  private let anchor: PromptCompositionProjection.Anchor?
  private let rightToLeft: Bool
  private let font: NSFont
  private let width: CGFloat
  private let joinsLetters: Bool
  private(set) var cellFrames: [Int: CGRect] = [:]
  private(set) var fieldFrames: [Int: CGRect] = [:]
  private(set) var size: CGSize = .zero
  let lineSpacing: CGFloat

  init(map: PromptCompositionTextMap, width: CGFloat, font: NSFont, lineSpacing: CGFloat = 12,
    rightToLeft: Bool = false, joinsLetters: Bool = false, reusing previous: PromptFieldTextLayout? = nil) {
    self.aliases = map.canonicalAliases; anchor = map.caret; self.rightToLeft = rightToLeft
    self.font = font; self.lineSpacing = lineSpacing
    let limit = width.isFinite ? max(1, width) : 1
    self.width = limit; self.joinsLetters = joinsLetters
    // Only immutable text/metrics are reused. Positions, identities, aliases,
    // anchors and groups belong to this snapshot; no old layout is mutated.
    let reuse = previous.flatMap {
      $0.width == limit && $0.font == font && $0.lineSpacing == lineSpacing
        && $0.rightToLeft == rightToLeft && $0.joinsLetters == joinsLetters ? $0 : nil
    }
    var groups: [Int] = []
    for (group, field) in map.fieldRuns.enumerated() {
      func append(_ cells: [PromptFieldTextRun.Cell], breaks: Bool = false) {
        let old: Box? = cells.first.flatMap { cell in
          guard let reuse, let index = reuse.boxByCell[cell.id] else { return nil }
          return reuse.boxes[index]
        }
        let box: Box
        if let old, old.cells == cells, old.fieldID == field.fieldID, old.breaks == breaks { box = old }
        else { box = Box(cells: cells, fieldID: field.fieldID, breaks: breaks,
          font: font, rightToLeft: rightToLeft, spacing: lineSpacing, width: limit) }
        for id in box.ranges.keys { boxByCell[id] = boxes.count }
        boxes.append(box); groups.append(group)
      }
      var pending: [PromptFieldTextRun.Cell] = []
      for cell in field.cells {
        let breaks = cell.glyph.character == "\n" && cell.glyph.state != .extra
        if joinsLetters && !cell.isGap {
          pending.append(cell)
          if breaks { append(pending, breaks: true); pending = [] }
        } else {
          if !pending.isEmpty { append(pending); pending = [] }
          append([cell], breaks: breaks)
        }
      }
      if !pending.isEmpty { append(pending) }
      for _ in 0..<field.removedReturns { append([], breaks: true) }
    }
    let geometry = ASLPromptFlowGeometry(cells: boxes.enumerated().map { index, box in
      .init(size: box.bounds.size, wordID: groups[index], isLineBreak: box.breaks, isSeparator: box.isGap)
    }, width: limit, rowSpacing: lineSpacing)
    size = geometry.size
    for (index, box) in boxes.enumerated() {
      let point = geometry.positions[index]
      let origin = CGPoint(x: rightToLeft ? limit - point.x - box.bounds.width : point.x, y: point.y)
      origins.append(origin)
      for id in box.ranges.keys { cellFrames[id] = box.rect(id, origin: origin) }
      if let owner = box.fieldID, !box.isGap, !box.ranges.isEmpty {
        let frame = CGRect(origin: origin, size: box.bounds.size)
        fieldFrames[owner] = fieldFrames[owner].map { $0.union(frame) } ?? frame
      }
    }
    let ids = map.fieldRuns.flatMap { $0.cells.map(\.id) }
    for (id, next) in zip(ids, ids.dropFirst()) { followingCell[id] = next }
    for box in boxes {
      for id in box.hints.keys {
        if let rect = cellFrames[id] { size.height = max(size.height, rect.maxY + max(9, font.pointSize * 0.48) * 1.4) }
      }
    }
  }

  private func caretRect(_ id: Int, after: Bool) -> CGRect? {
    guard let rect = cellFrames[id] else { return nil }
    if !after, let index = boxByCell[id], boxes[index].isGap,
      let next = followingCell[id].flatMap({ cellFrames[$0] }), next.minY > rect.minY {
      return next
    }
    return rect
  }
  func canonicalRect(_ id: Int, after: Bool) -> CGRect? {
    let ids = aliases[id] ?? (cellFrames[id] == nil ? [] : [id])
    return (after ? ids.last : ids.first).flatMap { caretRect($0, after: after) }
  }
  func mainRect(style: TypingCaretStyle) -> CGRect? {
    guard let anchor, let rect = caretRect(anchor.cellID, after: anchor.after) else { return nil }
    return PromptPaceCaretGeometry.rect(from: rect, to: rect, fromAfter: anchor.after, toAfter: anchor.after,
      style: style, rightToLeft: rightToLeft, fraction: 1, reducesMotion: true,
      afterWidth: (" " as NSString).size(withAttributes: [.font: font]).width)
  }
  var lineGeometry: ASLPromptLineGeometry {
    ASLPromptLineGeometry(frames: cellFrames, rowSpacing: lineSpacing, wordFrames: fieldFrames)
  }
  func draw(in dirtyRect: CGRect) {
    for (index, box) in boxes.enumerated() {
      let position = origins[index]
      let origin = CGPoint(x: position.x - box.bounds.minX, y: position.y - box.bounds.minY)
      let range = NSRange(location: 0, length: box.manager.numberOfGlyphs)
      // Zero-advance marks and overhangs still draw. This expands only dirty
      // testing, never layout allocation, text, or caret identity.
      if CGRect(origin: position, size: box.bounds.size).insetBy(dx: -font.pointSize, dy: -lineSpacing).intersects(dirtyRect) {
        box.manager.drawBackground(forGlyphRange: range, at: origin)
        box.manager.drawGlyphs(forGlyphRange: range, at: origin)
      }
      for (id, hint) in box.hints {
        guard let rect = cellFrames[id] else { continue }
        var text = hint; text.baselineOffset = nil; text.kern = nil
        let small = NSFont.monospacedSystemFont(ofSize: max(9, font.pointSize * 0.48), weight: .semibold)
        let prepared = TapePromptTextStorage.prepare(text, font: small)
        prepared.addAttribute(.font, value: small, range: .init(location: 0, length: prepared.length))
        let hintRect = CGRect(x: rect.minX, y: rect.maxY, width: max(rect.width, prepared.size().width), height: small.pointSize * 1.4)
        if hintRect.intersects(dirtyRect) { prepared.draw(at: hintRect.origin) }
      }
    }
  }
}
