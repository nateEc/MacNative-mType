@preconcurrency import AppKit
import SwiftUI

struct ReplayCharacterPicker: NSViewRepresentable {
  let text: String
  let reachableIndices: Set<Int>
  let selectedIndex: Int?
  let onSelect: (Int) -> Void

  func makeNSView(context: Context) -> ReplayCharacterTextView {
    ReplayCharacterTextView()
  }

  func updateNSView(_ view: ReplayCharacterTextView, context: Context) {
    view.onSelect = onSelect
    view.update(
      text: text,
      reachableIndices: reachableIndices,
      selectedIndex: selectedIndex)
  }
}

final class ReplayCharacterTextView: NSTextView {
  var onSelect: (Int) -> Void = { _ in }
  private var replayText = ""
  private var reachableIndices: Set<Int> = []

  override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
    super.init(frame: frameRect, textContainer: container)
    configure()
  }

  convenience init() {
    self.init(frame: .zero, textContainer: nil)
  }

  required init?(coder: NSCoder) { nil }

  private func configure() {
    isEditable = false
    isSelectable = false
    drawsBackground = false
    textContainerInset = NSSize(width: 8, height: 6)
    textContainer?.lineFragmentPadding = 0
    textContainer?.widthTracksTextView = true
    textContainer?.maximumNumberOfLines = 2
    textContainer?.lineBreakMode = .byTruncatingTail
    setAccessibilityElement(true)
    setAccessibilityRole(.staticText)
    setAccessibilityLabel("回放目标文本")
    setAccessibilityHelp("可用鼠标点选已输入的字符定位；也可使用下方滑杆定位")
  }

  func update(text: String, reachableIndices: Set<Int>, selectedIndex: Int?) {
    replayText = text
    self.reachableIndices = reachableIndices
    let rendered = NSMutableAttributedString()
    let font = NSFont.monospacedSystemFont(
      ofSize: NSFont.smallSystemFontSize, weight: .regular)
    for (index, character) in text.enumerated() {
      var attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: reachableIndices.contains(index)
          ? NSColor.labelColor : NSColor.tertiaryLabelColor,
      ]
      if selectedIndex == index {
        attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        attributes[.underlineColor] = NSColor.controlAccentColor
        attributes[.foregroundColor] = NSColor.controlAccentColor
      }
      rendered.append(NSAttributedString(string: String(character), attributes: attributes))
    }
    textStorage?.setAttributedString(rendered)
    setAccessibilityValue(text)
    window?.invalidateCursorRects(for: self)
    needsDisplay = true
  }

  override func mouseDown(with event: NSEvent) {
    guard let layoutManager, let textContainer else { return }
    let localPoint = convert(event.locationInWindow, from: nil)
    let textPoint = NSPoint(
      x: localPoint.x - textContainerInset.width,
      y: localPoint.y - textContainerInset.height)
    let glyphIndex = layoutManager.glyphIndex(for: textPoint, in: textContainer)
    guard glyphIndex < layoutManager.numberOfGlyphs else { return }
    let glyphRect = layoutManager.boundingRect(
      forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
    guard glyphRect.insetBy(dx: -2, dy: -2).contains(textPoint) else { return }
    let utf16Index = layoutManager.characterIndexForGlyph(at: glyphIndex)
    guard let characterIndex = characterIndex(containingUTF16Offset: utf16Index),
          reachableIndices.contains(characterIndex)
    else { return }
    onSelect(characterIndex)
  }

  override func resetCursorRects() {
    super.resetCursorRects()
    guard let layoutManager, let textContainer else { return }
    for characterIndex in reachableIndices {
      guard let utf16Range = utf16Range(forCharacterAt: characterIndex) else { continue }
      let glyphRange = layoutManager.glyphRange(
        forCharacterRange: utf16Range, actualCharacterRange: nil)
      let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        .offsetBy(dx: textContainerInset.width, dy: textContainerInset.height)
      addCursorRect(rect, cursor: .pointingHand)
    }
  }

  private func characterIndex(containingUTF16Offset offset: Int) -> Int? {
    var location = 0
    for (index, character) in replayText.enumerated() {
      let length = String(character).utf16.count
      if (location..<(location + length)).contains(offset) { return index }
      location += length
    }
    return nil
  }

  private func utf16Range(forCharacterAt targetIndex: Int) -> NSRange? {
    var location = 0
    for (index, character) in replayText.enumerated() {
      let length = String(character).utf16.count
      if index == targetIndex { return NSRange(location: location, length: length) }
      location += length
    }
    return nil
  }
}
