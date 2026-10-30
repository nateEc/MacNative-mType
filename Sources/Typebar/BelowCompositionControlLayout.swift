import AppKit
import CoreText

/// Keep the original control characters while laying out their actual font's
/// missing glyph. The delegate is the manager itself, so it cannot expire
/// between measurement and a later IME geometry query.
final class BelowCompositionControlLayout: NSLayoutManager, NSLayoutManagerDelegate {
  override init() { super.init(); delegate = self }
  required init?(coder: NSCoder) { super.init(coder: coder); delegate = self }

  static func containsControl(_ text: String) -> Bool {
    text.utf16.contains { $0 == 11 || $0 == 12 || $0 == 133 }
  }

  private func isControl(_ index: Int) -> Bool {
    guard let text = textStorage?.string as NSString?, index < text.length else { return false }
    return [11, 12, 133].contains(Int(text.character(at: index)))
  }

  private func missingGlyphFont(_ font: NSFont) -> NSFont {
    if CTFontCreatePathForGlyph(font as CTFont, 0, nil) != nil { return font }
    // SF Mono's .notdef has an advance but no outline. Menlo supplies an
    // actual missing-glyph box rather than a replacement-character symbol.
    return NSFont(name: "Menlo-Regular", size: font.pointSize) ?? .systemFont(ofSize: font.pointSize)
  }

  func layoutManager(_ manager: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction,
    forControlCharacterAt index: Int) -> NSLayoutManager.ControlCharacterAction {
    isControl(index) ? .whitespace : action
  }

  func layoutManager(_ manager: NSLayoutManager, boundingBoxForControlGlyphAt glyphIndex: Int,
    for container: NSTextContainer, proposedLineFragment: NSRect, glyphPosition: NSPoint,
    characterIndex: Int) -> NSRect {
    guard isControl(characterIndex),
      let original = textStorage?.attribute(.font, at: characterIndex, effectiveRange: nil) as? NSFont else { return .zero }
    let font = missingGlyphFont(original)
    var glyph: CGGlyph = 0
    var advance = CGSize.zero
    CTFontGetAdvancesForGlyphs(font as CTFont, .horizontal, &glyph, &advance, 1)
    return NSRect(x: 0, y: 0, width: advance.width, height: defaultLineHeight(for: font))
  }

  override func drawGlyphs(forGlyphRange range: NSRange, at origin: NSPoint) {
    super.drawGlyphs(forGlyphRange: range, at: origin)
    guard let graphics = NSGraphicsContext.current else { return }
    for glyphIndex in range.location..<NSMaxRange(range) {
      let index = characterIndexForGlyph(at: glyphIndex)
      guard isControl(index), let storage = textStorage,
        let original = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont else { continue }
      let font = missingGlyphFont(original)
      guard let path = CTFontCreatePathForGlyph(font as CTFont, 0, nil) else { continue }
      let line = lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
      let position = location(forGlyphAt: glyphIndex)
      let color = storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor ?? .labelColor
      let context = graphics.cgContext
      context.saveGState()
      context.translateBy(x: origin.x + line.minX + position.x, y: origin.y + line.minY + position.y)
      if graphics.isFlipped { context.scaleBy(x: 1, y: -1) }
      context.setFillColor(color.cgColor)
      context.addPath(path)
      context.fillPath()
      context.restoreGState()
    }
  }

  static func text(_ text: String, font: NSFont, color: NSColor, width: CGFloat) ->
    (storage: NSTextStorage, layout: BelowCompositionControlLayout, container: NSTextContainer) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byWordWrapping
    let storage = NSTextStorage(string: text,
      attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    let layout = BelowCompositionControlLayout()
    let container = NSTextContainer(size: .init(width: max(1, width), height: .greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    storage.addLayoutManager(layout); layout.addTextContainer(container)
    layout.ensureLayout(for: container)
    return (storage, layout, container)
  }
}

final class BelowCompositionControlCell: NSTextFieldCell {
  override func cellSize(forBounds rect: NSRect) -> NSSize {
    guard BelowCompositionControlLayout.containsControl(stringValue), let font else { return super.cellSize(forBounds: rect) }
    let text = BelowCompositionControlLayout.text(stringValue, font: font,
      color: textColor ?? .labelColor, width: max(1, rect.width - 4))
    defer { withExtendedLifetime(text.storage) {} }
    let used = text.layout.usedRect(for: text.container)
    return .init(width: ceil(used.width) + 4, height: ceil(used.height))
  }

  override func drawInterior(withFrame rect: NSRect, in view: NSView) {
    guard BelowCompositionControlLayout.containsControl(stringValue), let font else {
      super.drawInterior(withFrame: rect, in: view); return
    }
    if drawsBackground, let backgroundColor { backgroundColor.setFill(); rect.fill() }
    let drawing = drawingRect(forBounds: rect)
    let text = BelowCompositionControlLayout.text(stringValue, font: font,
      color: textColor ?? .labelColor, width: drawing.width)
    defer { withExtendedLifetime(text.storage) {} }
    text.layout.drawGlyphs(forGlyphRange: text.layout.glyphRange(for: text.container), at: drawing.origin)
  }
}
