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
  var structuralReturn: Bool? = nil
  var endsWithReturn: Bool {
    structuralReturn ?? cells.contains { $0.glyph.character == "\n" && $0.glyph.state != .extra }
  }
}

/// Ordinary letters are independent boxes. Joining scripts shape within a
/// field only. Hints are separate drawing layers, never advances or caret ink.
@MainActor final class PromptFieldTextLayout {
  private struct FieldRow: Hashable {
    let group: Int
    let y: CGFloat
  }
  private struct ContentProjection {
    let text: AttributedString
    let ownsLineBreak: Bool
    let main: AttributedString
    let hint: AttributedString?
  }
  /// Shared only inside a compatible layout snapshot. Text and metrics are
  /// immutable after construction; slot ownership and positions never live here.
  private final class TextShape {
    let text: AttributedString
    let wraps: Bool
    let manager = NSLayoutManager()
    let container = NSTextContainer(size: .init(width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude))
    let storage: NSTextStorage
    var bounds: CGRect = .zero
    init(text: AttributedString, wraps: Bool,
      font: NSFont, rightToLeft: Bool, spacing: CGFloat, width: CGFloat) {
      self.text = text; self.wraps = wraps
      storage = TapePromptTextStorage.prepare(text, font: font, rightToLeft: rightToLeft)
      let paragraph = NSMutableParagraphStyle()
      paragraph.baseWritingDirection = rightToLeft ? .rightToLeft : .leftToRight
      paragraph.alignment = .left; paragraph.lineSpacing = spacing; paragraph.lineBreakMode = .byCharWrapping
      storage.addAttribute(.paragraphStyle, value: paragraph, range: .init(location: 0, length: storage.length))
      container.lineFragmentPadding = 0; manager.addTextContainer(container); storage.addLayoutManager(manager)
      manager.ensureLayout(for: container)
      bounds = occupiedBounds()
      if bounds.width > width, wraps {
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
  }
  private final class Box {
    let shape: TextShape
    var manager: NSLayoutManager { shape.manager }
    var container: NSTextContainer { shape.container }
    var bounds: CGRect { shape.bounds }
    let multipleRanges: [Int: NSRange]
    let multipleHints: [Int: AttributedString]
    let multipleCells: [PromptFieldTextRun.Cell]
    let singleCell: PromptFieldTextRun.Cell?
    let singleRange: NSRange?
    let singleHint: AttributedString?
    let fieldID: Int?
    let isGap: Bool
    let breaks: Bool

    init(cells: [PromptFieldTextRun.Cell], fieldID: Int?, breaks: Bool,
      contentFor: (PromptFieldTextRun.Cell) -> ContentProjection,
      shapeFor: (AttributedString, Bool) -> TextShape) {
      self.fieldID = fieldID; self.breaks = breaks
      isGap = cells.count == 1 && cells[0].isGap
      if cells.count == 1 {
        let cell = cells[0], content = contentFor(cell)
        singleCell = cell
        singleRange = .init(location: 0, length: String(content.main.characters).utf16.count)
        singleHint = content.hint
        multipleCells = []; multipleRanges = [:]; multipleHints = [:]
        shape = shapeFor(content.main, false)
        return
      }
      multipleCells = cells; singleCell = nil; singleRange = nil; singleHint = nil
      var text = AttributedString(), ranges: [Int: NSRange] = [:], hints: [Int: AttributedString] = [:], unit = 0
      for cell in cells {
        let content = contentFor(cell)
        let main = content.main
        ranges[cell.id] = .init(location: unit, length: String(main.characters).utf16.count)
        unit += ranges[cell.id]!.length; text += main
        hints[cell.id] = content.hint
      }
      multipleRanges = ranges; multipleHints = hints
      shape = shapeFor(text, cells.count > 1)
    }
    func rect(_ id: Int, origin: CGPoint) -> CGRect? {
      let range = singleCell?.id == id ? singleRange : multipleRanges[id]
      guard let range, range.length > 0 else { return nil }
      let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
      return TapePromptTextStorage.advanceRect(glyphs, manager: manager, container: container)
        .offsetBy(dx: origin.x - bounds.minX, dy: origin.y - bounds.minY)
    }
    func matches(_ other: [PromptFieldTextRun.Cell], fieldID: Int?, breaks: Bool,
      textUnits: (AttributedString) -> [UInt16]) -> Bool {
      guard self.fieldID == fieldID, self.breaks == breaks else { return false }
      if let singleCell {
        return other.count == 1 && singleCell == other[0]
          && textUnits(singleCell.text) == textUnits(other[0].text)
      }
      return multipleCells == other && zip(multipleCells, other).allSatisfy {
        textUnits($0.text) == textUnits($1.text)
      }
    }
    var allCells: [PromptFieldTextRun.Cell] { singleCell.map { [$0] } ?? multipleCells }
  }

  private var boxes: [Box] = []
  var shapingResourceCount: Int { Set(boxes.map { ObjectIdentifier($0.manager) }).count }
  private(set) var preparedContentProjectionCount = 0
  private var origins: [CGPoint] = []
  private var boxByCell: [Int: Int] = [:]
  private var followingCell: [Int: Int] = [:]
  private let aliases: [Int: [Int]]
  private let anchor: PromptCompositionProjection.Anchor?
  private let rightToLeft: Bool
  private let font: NSFont
  private let width: CGFloat
  private let joinsLetters: Bool
  private let unbounded: Bool
  private(set) var cellFrames: [Int: CGRect] = [:]
  private(set) var fieldFrames: [Int: CGRect] = [:]
  private(set) var size: CGSize = .zero
  let lineSpacing: CGFloat

  convenience init(map: PromptCompositionTextMap, width: CGFloat, font: NSFont, lineSpacing: CGFloat = 12,
    rightToLeft: Bool = false, joinsLetters: Bool = false, unbounded: Bool = false,
    reusing previous: PromptFieldTextLayout? = nil) {
    self.init(fieldRuns: map.fieldRuns, aliases: map.canonicalAliases, anchor: map.caret,
      width: width, font: font, lineSpacing: lineSpacing, rightToLeft: rightToLeft,
      joinsLetters: joinsLetters, unbounded: unbounded, reusing: previous)
  }

  private init(aliases: [Int: [Int]], anchor: PromptCompositionProjection.Anchor?, width: CGFloat,
    font: NSFont, lineSpacing: CGFloat, rightToLeft: Bool, joinsLetters: Bool, unbounded: Bool) {
    self.aliases = aliases; self.anchor = anchor; self.rightToLeft = rightToLeft
    self.font = font; self.lineSpacing = lineSpacing
    self.width = width.isFinite ? max(1, width) : 1
    self.joinsLetters = joinsLetters; self.unbounded = unbounded
  }

  convenience init(fieldRuns: [PromptFieldTextRun], aliases: [Int: [Int]] = [:],
    anchor: PromptCompositionProjection.Anchor? = nil, width: CGFloat, font: NSFont,
    lineSpacing: CGFloat = 12, rightToLeft: Bool = false, joinsLetters: Bool = false, unbounded: Bool = false,
    reusing previous: PromptFieldTextLayout? = nil) {
    self.init(aliases: aliases, anchor: anchor, width: width, font: font, lineSpacing: lineSpacing,
      rightToLeft: rightToLeft, joinsLetters: joinsLetters, unbounded: unbounded)
    let builder = Builder(layout: self, previous: previous)
    for (group, field) in fieldRuns.enumerated() { builder.append(field, group: group) }
    builder.finish()
  }

  static func makeCooperatively(map: PromptCompositionTextMap, width: CGFloat, font: NSFont,
    lineSpacing: CGFloat = 12, rightToLeft: Bool = false, joinsLetters: Bool = false,
    unbounded: Bool = false, reusing previous: PromptFieldTextLayout? = nil,
    batchSize: Int = 256, didPrepare: (Int) -> Void = { _ in }, didPlace: (Int) -> Void = { _ in }
  ) async throws -> PromptFieldTextLayout {
    try Task.checkCancellation()
    let layout = PromptFieldTextLayout(aliases: map.canonicalAliases, anchor: map.caret,
      width: width, font: font, lineSpacing: lineSpacing, rightToLeft: rightToLeft,
      joinsLetters: joinsLetters, unbounded: unbounded)
    let builder = Builder(layout: layout, previous: previous)
    let interval = max(1, batchSize)
    for (group, field) in map.fieldRuns.enumerated() {
      builder.append(field, group: group)
      if (group + 1).isMultiple(of: interval) {
        didPrepare(group + 1)
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    if !map.fieldRuns.count.isMultiple(of: interval) { didPrepare(map.fieldRuns.count) }
    try Task.checkCancellation()
    try await builder.finishCooperatively(batchSize: interval, didPlace: didPlace)
    try Task.checkCancellation()
    return layout
  }

  @MainActor private final class Builder {
    let layout: PromptFieldTextLayout
    let reuse: PromptFieldTextLayout?
    var groups: [Int] = []
    var projections: [[UInt16]: [ContentProjection]] = [:]
    var shapes: [[UInt16]: [TextShape]] = [:]
    var lastCellID: Int?

    init(layout: PromptFieldTextLayout, previous: PromptFieldTextLayout?) {
      self.layout = layout
      // Only immutable text/metrics are reused. Positions, identities, aliases,
      // anchors and groups belong to this snapshot; no old layout is mutated.
      reuse = previous.flatMap {
        $0.width == layout.width && $0.font == layout.font && $0.lineSpacing == layout.lineSpacing
          && $0.rightToLeft == layout.rightToLeft && $0.joinsLetters == layout.joinsLetters
          && $0.unbounded == layout.unbounded ? $0 : nil
      }
    }

    // Projection depends on the complete authored attributes and structural
    // Return ownership, never the slot ID or its position. Keep this cache local.
    // Swift String/AttributedString equality is canonically equivalent, but
    // TextKit ranges address exact UTF-16 storage. Never merge those encodings.
    func textUnits(_ text: AttributedString) -> [UInt16] { Array(String(text.characters).utf16) }
    func contentFor(_ cell: PromptFieldTextRun.Cell) -> ContentProjection {
      let content = ASLPromptGlyphContent(glyph: cell.glyph, text: cell.text)
      let key = textUnits(content.text)
      if let projection = projections[key]?.first(where: {
        $0.ownsLineBreak == content.ownsLineBreak && $0.text == content.text
      }) { return projection }
      let projection = ContentProjection(text: content.text, ownsLineBreak: content.ownsLineBreak,
        main: content.main, hint: content.hint)
      projections[key, default: []].append(projection)
      layout.preparedContentProjectionCount += 1
      return projection
    }
    func shapeFor(_ text: AttributedString, _ wraps: Bool) -> TextShape {
      let key = textUnits(text)
      if let shape = shapes[key]?.first(where: { $0.wraps == wraps && $0.text == text }) { return shape }
      let shape = TextShape(text: text, wraps: wraps, font: layout.font, rightToLeft: layout.rightToLeft,
        spacing: layout.lineSpacing, width: layout.unbounded ? .greatestFiniteMagnitude : layout.width)
      shapes[key, default: []].append(shape)
      return shape
    }

    func append(_ field: PromptFieldTextRun, group: Int) {
      for cell in field.cells {
        if let lastCellID { layout.followingCell[lastCellID] = cell.id }
        lastCellID = cell.id
      }
      func append(_ cells: [PromptFieldTextRun.Cell], breaks: Bool = false) {
        let old: Box? = cells.first.flatMap { cell in
          guard let reuse, let index = reuse.boxByCell[cell.id] else { return nil }
          return reuse.boxes[index]
        }
        let box: Box
        if let old, old.matches(cells, fieldID: field.fieldID, breaks: breaks, textUnits: textUnits) {
          box = old
          let key = textUnits(old.shape.text)
          if !(shapes[key]?.contains(where: { $0 === old.shape }) ?? false) {
            shapes[key, default: []].append(old.shape)
          }
        } else {
          box = Box(cells: cells, fieldID: field.fieldID, breaks: breaks,
            contentFor: contentFor, shapeFor: shapeFor)
        }
        if let cell = box.singleCell { layout.boxByCell[cell.id] = layout.boxes.count }
        else { for id in box.multipleRanges.keys { layout.boxByCell[id] = layout.boxes.count } }
        layout.boxes.append(box); groups.append(group)
      }
      var pending: [PromptFieldTextRun.Cell] = []
      // A Return icon is a letter inside the word. The structural boundary
      // follows the entire container, including accepted/marked extras.
      let breaksAfterField = field.endsWithReturn
      for (index, cell) in field.cells.enumerated() {
        let breaks = breaksAfterField && index == field.cells.count - 1
        if layout.joinsLetters && !cell.isGap {
          pending.append(cell)
        } else {
          if !pending.isEmpty { append(pending); pending = [] }
          append([cell], breaks: breaks)
        }
      }
      if !pending.isEmpty { append(pending, breaks: breaksAfterField) }
      for _ in 0..<field.removedReturns { append([], breaks: true) }
    }

    func finish() {
      prepareGeometry()
      for indices in visualRows() { orderVisualRow(indices) }
      for index in layout.boxes.indices { placeFrame(at: index) }
    }

    func finishCooperatively(batchSize: Int,
      didPlace: (Int) -> Void) async throws {
      prepareGeometry()
      try Task.checkCancellation()
      await Task.yield()
      let rows = visualRows()
      for (index, indices) in rows.enumerated() {
        orderVisualRow(indices)
        if (index + 1).isMultiple(of: batchSize) {
          try Task.checkCancellation()
          await Task.yield()
        }
      }
      try Task.checkCancellation()
      await Task.yield()
      for index in layout.boxes.indices {
        placeFrame(at: index)
        if (index + 1).isMultiple(of: batchSize) {
          didPlace(index + 1)
          try Task.checkCancellation()
          await Task.yield()
        }
      }
      if !layout.boxes.count.isMultiple(of: batchSize) { didPlace(layout.boxes.count) }
      try Task.checkCancellation()
    }

    private func prepareGeometry() {
      let boxes = layout.boxes
      // Tape mirrors around the measured natural extent, not the no-wrap
      // proposal. Ordinary bounded wrapping keeps its existing width.
      let flowWidth = layout.unbounded ? max(1, boxes.reduce(CGFloat.zero) { $0 + $1.bounds.width }) : layout.width
      let geometry = ASLPromptFlowGeometry(cells: boxes.enumerated().map { index, box in
        .init(size: box.bounds.size, wordID: groups[index], isLineBreak: box.breaks, isSeparator: box.isGap)
      }, width: flowWidth, rowSpacing: layout.lineSpacing)
      layout.size = geometry.size
      layout.origins = boxes.enumerated().map { index, box in
        let point = geometry.positions[index]
        return CGPoint(x: layout.rightToLeft ? flowWidth - point.x - box.bounds.width : point.x, y: point.y)
      }
    }

    private func visualRows() -> [[Int]] {
      guard !layout.joinsLetters else { return [] }
      var rows: [FieldRow: [Int]] = [:]
      for (index, box) in layout.boxes.enumerated() where !box.isGap {
        if box.singleCell != nil {
          rows[.init(group: groups[index], y: layout.origins[index].y), default: []].append(index)
        }
      }
      return Array(rows.values)
    }

    private func orderVisualRow(_ indices: [Int]) {
      let boxes = layout.boxes
      let cells = indices.compactMap { boxes[$0].singleCell }
      guard layout.rightToLeft || cells.contains(where: {
        PracticeTapePolicy.isRightToLeft(String($0.glyph.character), fallback: false)
      }) else { return }
      let order = PromptFieldVisualOrder.cellIDs(cells, font: layout.font, rightToLeft: layout.rightToLeft)
      let byID = Dictionary(uniqueKeysWithValues: indices.compactMap { index in
        boxes[index].singleCell.map { ($0.id, index) }
      })
      var x = indices.map { layout.origins[$0].x }.min() ?? 0
      for id in order {
        guard let index = byID[id] else { continue }
        layout.origins[index].x = x
        x += boxes[index].bounds.width
      }
    }

    private func placeFrame(at index: Int) {
      let box = layout.boxes[index], origin = layout.origins[index]
      if let cell = box.singleCell { layout.cellFrames[cell.id] = box.rect(cell.id, origin: origin) }
      else { for id in box.multipleRanges.keys { layout.cellFrames[id] = box.rect(id, origin: origin) } }
      if let owner = box.fieldID, !box.isGap, box.singleCell != nil || !box.multipleRanges.isEmpty {
        let frame = CGRect(origin: origin, size: box.bounds.size)
        layout.fieldFrames[owner] = layout.fieldFrames[owner].map { $0.union(frame) } ?? frame
      }
      let hintHeight = max(9, layout.font.pointSize * 0.48) * 1.4
      if let cell = box.singleCell, box.singleHint != nil,
        let rect = layout.cellFrames[cell.id] {
        layout.size.height = max(layout.size.height, rect.maxY + hintHeight)
      }
      for id in box.multipleHints.keys {
        if let rect = layout.cellFrames[id] {
          layout.size.height = max(layout.size.height, rect.maxY + hintHeight)
        }
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
  func mainDirection(perGlyph: Bool) -> Bool {
    guard let anchor else { return rightToLeft }
    return direction(at: anchor.cellID, perGlyph: perGlyph)
  }
  func canonicalDirection(_ id: Int, after: Bool, perGlyph: Bool) -> Bool? {
    let ids = aliases[id] ?? (cellFrames[id] == nil ? [] : [id])
    guard let cell = after ? ids.last : ids.first else { return nil }
    return direction(at: cell, perGlyph: perGlyph)
  }
  private func direction(at cellID: Int, perGlyph: Bool) -> Bool {
    guard let index = boxByCell[cellID] else { return rightToLeft }
    let box = boxes[index]
    let cells = perGlyph ? box.allCells.filter { $0.id == cellID }
      : box.fieldID.map { owner in boxes.filter { $0.fieldID == owner }.flatMap(\.allCells) } ?? box.allCells
    let text = cells.map { String(ASLPromptGlyphContent(glyph: $0.glyph, text: $0.text).main.characters) }.joined()
    return PracticeTapePolicy.isRightToLeft(text, fallback: rightToLeft)
  }
  func mainRect(style: TypingCaretStyle, perGlyph: Bool? = nil) -> CGRect? {
    guard let anchor, let rect = caretRect(anchor.cellID, after: anchor.after) else { return nil }
    return PromptPaceCaretGeometry.rect(from: rect, to: rect, fromAfter: anchor.after, toAfter: anchor.after,
      style: style, rightToLeft: perGlyph.map { mainDirection(perGlyph: $0) } ?? rightToLeft,
      fraction: 1, reducesMotion: true,
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
      var hints = box.multipleHints
      if let cell = box.singleCell, let hint = box.singleHint { hints[cell.id] = hint }
      for (id, hint) in hints {
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
