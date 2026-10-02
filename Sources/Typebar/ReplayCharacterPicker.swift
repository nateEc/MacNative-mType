@preconcurrency import AppKit
import SwiftUI

struct ReplayCharacterUTF16Index {
  private let offsets: [Int]

  init(_ text: String) {
    self.init(characters: Array(text))
  }

  init(characters: [Character]) {
    var offsets = [0]
    offsets.reserveCapacity(characters.count + 1)
    for character in characters {
      offsets.append(offsets[offsets.count - 1] + String(character).utf16.count)
    }
    self.offsets = offsets
  }

  func range(at characterIndex: Int) -> NSRange? {
    guard (0..<(offsets.count - 1)).contains(characterIndex) else { return nil }
    return NSRange(
      location: offsets[characterIndex],
      length: offsets[characterIndex + 1] - offsets[characterIndex])
  }

  func characterIndex(containing offset: Int) -> Int? {
    guard offset >= 0, offset < offsets[offsets.count - 1] else { return nil }
    var lower = 0
    var upper = offsets.count - 1
    while lower + 1 < upper {
      let middle = (lower + upper) / 2
      if offsets[middle] <= offset {
        lower = middle
      } else {
        upper = middle
      }
    }
    return lower
  }

  func characterIndices(overlapping range: NSRange) -> Range<Int>? {
    guard range.length > 0,
      let first = characterIndex(containing: range.location),
      let last = characterIndex(containing: min(NSMaxRange(range) - 1, offsets[offsets.count - 1] - 1))
    else { return nil }
    return first..<(last + 1)
  }
}

struct ReplayCharacterPicker: NSViewRepresentable {
  let text: String
  let reachableIndices: Set<Int>
  let selectedIndex: Int?
  var glyphs: [TypingPromptGlyph]? = nil
  var errorIndices: Set<Int> = []
  let onSelect: (Int) -> Void

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.documentView = ReplayCharacterTextView()
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard let view = scrollView.documentView as? ReplayCharacterTextView else { return }
    view.onSelect = onSelect
    view.update(
      text: text,
      reachableIndices: reachableIndices,
      selectedIndex: selectedIndex, glyphs: glyphs, errorIndices: errorIndices)
  }
}

final class ReplayCharacterTextView: NSTextView {
  var onSelect: (Int) -> Void = { _ in }
  private var utf16Index = ReplayCharacterUTF16Index("")
  private var renderedText: String?
  private var reachableIndices: Set<Int> = []
  private var renderedSelection: Int?
  private var renderedGlyphs: [TypingPromptGlyph]?
  private var renderedErrors: Set<Int> = []

  override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
    super.init(frame: frameRect, textContainer: container)
    configure()
  }

  convenience init() {
    let storage = NSTextStorage()
    let layout = NSLayoutManager()
    let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
    storage.addLayoutManager(layout)
    layout.addTextContainer(container)
    self.init(frame: .zero, textContainer: container)
  }

  required init?(coder: NSCoder) { nil }

  private func configure() {
    isEditable = false
    isSelectable = false
    isVerticallyResizable = true
    isHorizontallyResizable = false
    autoresizingMask = [.width]
    maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    drawsBackground = false
    textContainerInset = NSSize(width: 8, height: 6)
    textContainer?.lineFragmentPadding = 0
    textContainer?.widthTracksTextView = true
    textContainer?.maximumNumberOfLines = 0
    textContainer?.lineBreakMode = .byWordWrapping
    setAccessibilityElement(true)
    setAccessibilityRole(.staticText)
    setAccessibilityLabel("回放目标文本")
    setAccessibilityHelp("可用鼠标点选已输入的字符定位；也可使用下方滑杆定位")
  }

  func update(text: String, reachableIndices: Set<Int>, selectedIndex: Int?,
    glyphs: [TypingPromptGlyph]? = nil, errorIndices: Set<Int> = []) {
    let validGlyphs = glyphs.flatMap {
      String($0.map(\.character)).utf16.elementsEqual(text.utf16) ? $0 : nil
    }
    guard renderedText != text || self.reachableIndices != reachableIndices
      || renderedSelection != selectedIndex || renderedGlyphs != validGlyphs || renderedErrors != errorIndices
    else { return }
    let characters = validGlyphs?.map(\.character) ?? Array(text)
    utf16Index = ReplayCharacterUTF16Index(characters: characters)
    renderedText = text
    self.reachableIndices = reachableIndices
    renderedSelection = selectedIndex
    renderedGlyphs = validGlyphs
    renderedErrors = errorIndices
    let rendered = NSMutableAttributedString()
    let font = NSFont.monospacedSystemFont(
      ofSize: NSFont.smallSystemFontSize, weight: .regular)
    for (index, character) in characters.enumerated() {
      let color: NSColor
      if let state = validGlyphs?[index].state {
        switch state {
        case .correct: color = .labelColor
        case .incorrect, .extra: color = .systemRed
        default: color = .secondaryLabelColor
        }
      } else {
        color = reachableIndices.contains(index) ? .labelColor : .tertiaryLabelColor
      }
      var attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
      ]
      if errorIndices.contains(index) {
        attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        attributes[.underlineColor] = NSColor.systemRed
      }
      if selectedIndex == index {
        attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        attributes[.underlineColor] = NSColor.controlAccentColor
        attributes[.foregroundColor] = NSColor.controlAccentColor
      }
      rendered.append(NSAttributedString(string: String(character), attributes: attributes))
    }
    textStorage?.setAttributedString(rendered)
    setAccessibilityLabel(validGlyphs == nil ? "回放目标文本" : "回放目标字形")
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
    guard let characterIndex = self.utf16Index.characterIndex(containing: utf16Index),
          reachableIndices.contains(characterIndex)
    else { return }
    onSelect(characterIndex)
  }

  override func resetCursorRects() {
    super.resetCursorRects()
    guard let layoutManager, let textContainer else { return }
    let visibleTextRect = visibleRect.offsetBy(
      dx: -textContainerInset.width, dy: -textContainerInset.height)
    let visibleGlyphs = layoutManager.glyphRange(
      forBoundingRect: visibleTextRect, in: textContainer)
    guard visibleGlyphs.length > 0 else { return }
    let visibleCharacters = layoutManager.characterRange(
      forGlyphRange: visibleGlyphs, actualGlyphRange: nil)
    guard let indices = utf16Index.characterIndices(overlapping: visibleCharacters) else { return }
    for characterIndex in indices where reachableIndices.contains(characterIndex) {
      guard let utf16Range = utf16Index.range(at: characterIndex) else { continue }
      let glyphRange = layoutManager.glyphRange(
        forCharacterRange: utf16Range, actualCharacterRange: nil)
      let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        .offsetBy(dx: textContainerInset.width, dy: textContainerInset.height)
      addCursorRect(rect, cursor: .pointingHand)
    }
  }

}
