import AppKit
import SwiftUI

/// Browser-like whitespace display with a UTF-16 back-map for AppKit IME
/// queries. Collapsed runs share one visible space and one source range.
struct BelowCompositionProjection {
  let displayed: String
  let sourceRanges: [NSRange]
  let displayRanges: [NSRange?]
  let actualRanges: [NSRange]

  init(_ source: String) {
    var output = String.UnicodeScalarView()
    var scalarSources: [NSRange] = [], scalarDisplays: [NSRange?] = [], scalarActuals: [NSRange] = []
    var sourceUnit = 0, displayUnit = 0, pending: [Int] = [], hasLineContent = false
    for scalar in source.unicodeScalars {
      let raw = NSRange(location: sourceUnit, length: String(scalar).utf16.count)
      sourceUnit += raw.length
      scalarSources.append(raw); scalarDisplays.append(nil); scalarActuals.append(raw)
      let index = scalarSources.count - 1
      if scalar == " " || scalar == "\t" || scalar == "\n" {
        if hasLineContent { pending.append(index) }
        continue
      }
      if let first = pending.first, let last = pending.last {
        let space = NSRange(location: displayUnit, length: 1)
        let group = NSRange(location: scalarSources[first].location,
          length: NSMaxRange(scalarSources[last]) - scalarSources[first].location)
        output.append(" "); displayUnit += 1
        for pendingIndex in pending { scalarDisplays[pendingIndex] = space; scalarActuals[pendingIndex] = group }
        pending.removeAll(keepingCapacity: true)
      }
      // These dynamic DOM controls have no advance, but separate collapsible
      // whitespace runs. Flush the preceding run before omitting the control.
      if scalar == "\r" || scalar == "\u{2028}" || scalar == "\u{2029}" {
        hasLineContent = true
        continue
      }
      scalarDisplays[index] = NSRange(location: displayUnit, length: raw.length)
      output.append(scalar); displayUnit += raw.length
      hasLineContent = true
    }
    var sourceRanges: [NSRange] = [], displayRanges: [NSRange?] = [], actualRanges: [NSRange] = []
    var characterUnit = 0, scalarIndex = 0
    for character in source {
      let raw = NSRange(location: characterUnit, length: String(character).utf16.count)
      characterUnit += raw.length
      var display: NSRange?, actual = raw
      while scalarIndex < scalarSources.count && scalarSources[scalarIndex].location < NSMaxRange(raw) {
        if let segment = scalarDisplays[scalarIndex] {
          let lower = min(display?.location ?? segment.location, segment.location)
          let upper = max(display.map(NSMaxRange) ?? NSMaxRange(segment), NSMaxRange(segment))
          display = NSRange(location: lower, length: upper - lower)
          let mapped = scalarActuals[scalarIndex]
          let sourceLower = min(actual.location, mapped.location)
          actual = NSRange(location: sourceLower,
            length: max(NSMaxRange(actual), NSMaxRange(mapped)) - sourceLower)
        }
        scalarIndex += 1
      }
      sourceRanges.append(raw); displayRanges.append(display); actualRanges.append(actual)
    }
    displayed = String(output)
    self.sourceRanges = sourceRanges
    self.displayRanges = displayRanges
    self.actualRanges = actualRanges
  }

  func firstVisibleRange(for proposed: NSRange) -> (display: NSRange, actual: NSRange)? {
    guard proposed.location != NSNotFound, proposed.location >= 0, proposed.length > 0,
      let last = sourceRanges.last, proposed.location < NSMaxRange(last) else { return nil }
    let end = proposed.location + min(proposed.length, NSMaxRange(last) - proposed.location)
    for index in sourceRanges.indices where sourceRanges[index].location < end
      && NSMaxRange(sourceRanges[index]) > proposed.location {
      if let display = displayRanges[index] { return (display, actualRanges[index]) }
    }
    return nil
  }

  func displayInsertionOffset(for sourceOffset: Int) -> Int? {
    guard sourceOffset >= 0, sourceOffset <= sourceRanges.last.map(NSMaxRange) ?? 0,
      !displayed.isEmpty else { return nil }
    var preceding: Int?
    for index in sourceRanges.indices {
      guard let display = displayRanges[index] else { continue }
      let source = sourceRanges[index]
      if sourceOffset <= source.location { return display.location }
      if sourceOffset < NSMaxRange(source) { return display.location }
      preceding = NSMaxRange(display)
    }
    return preceding
  }
}

@MainActor final class BelowCompositionField: NSTextField {
  weak var insertionAnchor: PromptInsertionAnchor?
  var attemptID: UUID?
  var sourceText = ""

  private func measuredLayout(markedText: String) ->
    (projection: BelowCompositionProjection, drawing: NSRect, storage: NSTextStorage,
      layout: NSLayoutManager, container: NSTextContainer)? {
    guard sourceText == markedText, window != nil, bounds.width > 0, bounds.height > 0,
      let font, let cell else { return nil }
    let projection = BelowCompositionProjection(sourceText)
    guard !projection.displayed.isEmpty else { return nil }
    let drawing = cell.drawingRect(forBounds: bounds)
    guard drawing.width > 0, drawing.height > 0 else { return nil }
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byWordWrapping
    let storage = NSTextStorage(string: projection.displayed,
      attributes: [.font: font, .paragraphStyle: paragraph])
    let layout = NSLayoutManager()
    // Include one extra line because TextKit's line height can be a few
    // points taller than NSCell's, but do not lay out an unbounded tail.
    let visibleHeight = drawing.height + max(font.boundingRectForFont.height, font.ascender - font.descender)
    let container = NSTextContainer(size: .init(width: drawing.width, height: visibleHeight))
    container.lineFragmentPadding = 0
    storage.addLayoutManager(layout)
    layout.addTextContainer(container)
    layout.ensureLayout(for: container)
    return (projection, drawing, storage, layout, container)
  }

  private func screenRect(for glyphRect: NSRect, drawing: NSRect) -> NSRect? {
    guard let window, glyphRect.minX.isFinite, glyphRect.minY.isFinite,
      glyphRect.width.isFinite, glyphRect.height.isFinite,
      glyphRect.width > 0, glyphRect.height > 0 else { return nil }
    let local = NSRect(x: drawing.minX + glyphRect.minX,
      y: isFlipped ? drawing.minY + glyphRect.minY : drawing.maxY - glyphRect.maxY,
      width: glyphRect.width, height: glyphRect.height)
    let visible = local.intersection(drawing)
    guard visible.width > 0, visible.height > 0 else { return nil }
    return window.convertToScreen(convert(visible, to: nil))
  }

  func markedScreenRect(for proposed: NSRange, markedText: String) -> (rect: NSRect, actualRange: NSRange)? {
    guard let measured = measuredLayout(markedText: markedText),
      let selected = measured.projection.firstVisibleRange(for: proposed) else { return nil }
    let layout = measured.layout, container = measured.container
    let glyphs = layout.glyphRange(forCharacterRange: selected.display, actualCharacterRange: nil)
    guard glyphs.length > 0 else { return nil }
    let glyphRect = layout.boundingRect(forGlyphRange: glyphs, in: container)
    guard let rect = screenRect(for: glyphRect, drawing: measured.drawing) else { return nil }
    return (rect, selected.actual)
  }

  func insertionScreenRect(at sourceOffset: Int, markedText: String) -> NSRect? {
    guard let measured = measuredLayout(markedText: markedText),
      let offset = measured.projection.displayInsertionOffset(for: sourceOffset) else { return nil }
    let layout = measured.layout, container = measured.container
    let textLength = measured.projection.displayed.utf16.count
    let character = min(offset, textLength - 1)
    let glyph = layout.glyphIndexForCharacter(at: character)
    let glyphRect = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
    guard let screen = screenRect(for: glyphRect, drawing: measured.drawing) else { return nil }
    var bidi: UInt8 = 0
    withUnsafeMutablePointer(to: &bidi) { pointer in
      _ = layout.getGlyphs(in: NSRange(location: glyph, length: 1), glyphs: nil,
        properties: nil, characterIndexes: nil, bidiLevels: pointer)
    }
    let after = offset > character
    let rightToLeft = bidi & 1 == 1
    let x = after ? (rightToLeft ? screen.minX : screen.maxX)
      : (rightToLeft ? screen.maxX : screen.minX)
    return NSRect(x: x, y: screen.minY, width: 0, height: screen.height)
  }
}

/// A separate candidate row; empty composition still reserves one text line.
struct BelowCompositionPrompt: NSViewRepresentable {
  let text: String
  let font: NSFont
  let color: NSColor
  var insertionAnchor: PromptInsertionAnchor? = nil
  var attemptID: UUID? = nil

  func makeNSView(context: Context) -> BelowCompositionField {
    let view = BelowCompositionField(wrappingLabelWithString: " ")
    view.alignment = .center
    view.isSelectable = false
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return view
  }

  func updateNSView(_ view: BelowCompositionField, context: Context) {
    let displayed = BelowCompositionProjection(text).displayed
    view.stringValue = displayed.isEmpty ? " " : displayed
    view.font = font
    view.textColor = color
    view.sourceText = text
    if view.insertionAnchor !== insertionAnchor { view.insertionAnchor?.unregisterBelow(view) }
    view.insertionAnchor = insertionAnchor
    view.attemptID = attemptID
    if let insertionAnchor, let attemptID { insertionAnchor.registerBelow(view, attemptID: attemptID) }
    else { insertionAnchor?.unregisterBelow(view) }
    view.setAccessibilityLabel(text.isEmpty ? "组合输入候选行" : "正在组合：\(text)")
  }

  static func dismantleNSView(_ nsView: BelowCompositionField, coordinator: ()) {
    nsView.insertionAnchor?.unregisterBelow(nsView)
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView: BelowCompositionField, context: Context) -> CGSize? {
    let width = max(1, proposal.width ?? nsView.bounds.width)
    let height = nsView.cell?.cellSize(forBounds:
      .init(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)).height
      ?? font.boundingRectForFont.height
    return .init(width: width, height: ceil(max(height, font.ascender - font.descender)))
  }
}
