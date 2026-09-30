@preconcurrency import AppKit
import SwiftUI

struct ReplayInputView: NSViewRepresentable {
  let glyphs: [TypingPromptGlyph]

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.documentView = ReplayInputTextView()
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard let view = scrollView.documentView as? ReplayInputTextView else { return }
    if view.update(glyphs: glyphs) {
      view.scrollToEndOfDocument(nil)
    }
  }
}

final class ReplayInputTextView: NSTextView {
  private var renderedGlyphs: [TypingPromptGlyph] = []
  private var utf16Offsets = [0]
  private var hasRendered = false

  override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
    super.init(frame: frameRect, textContainer: container)
    configure()
  }

  convenience init() {
    let storage = NSTextStorage()
    let layout = NSLayoutManager()
    let container = NSTextContainer(
      size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
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
    setAccessibilityLabel("回放实际输入")
  }

  @discardableResult
  func update(glyphs: [TypingPromptGlyph]) -> Bool {
    guard !hasRendered || glyphs != renderedGlyphs else { return false }
    guard let storage = textStorage else { return false }

    var matchingPrefix = 0
    while matchingPrefix < min(renderedGlyphs.count, glyphs.count),
      renderedGlyphs[matchingPrefix] == glyphs[matchingPrefix]
    {
      matchingPrefix += 1
    }

    let suffix = NSMutableAttributedString(string: "")
    let font = NSFont.monospacedSystemFont(
      ofSize: NSFont.smallSystemFontSize, weight: .regular)
    var newOffsets = Array(utf16Offsets.prefix(matchingPrefix + 1))
    for glyph in glyphs.dropFirst(matchingPrefix) {
      let character = String(glyph.character)
      suffix.append(NSAttributedString(
        string: character, attributes: Self.attributes(for: glyph.state, font: font)))
      newOffsets.append(newOffsets[newOffsets.count - 1] + character.utf16.count)
    }
    if glyphs.isEmpty {
      suffix.append(NSAttributedString(
        string: "等待播放", attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]))
    }

    storage.replaceCharacters(
      in: NSRange(location: utf16Offsets[matchingPrefix],
                  length: storage.length - utf16Offsets[matchingPrefix]),
      with: suffix)
    renderedGlyphs = glyphs
    utf16Offsets = newOffsets
    hasRendered = true
    setAccessibilityValue(glyphs.isEmpty ? "等待播放" : String(glyphs.map(\.character)))
    return true
  }

  private static func attributes(
    for state: TypingPromptCharacterState, font: NSFont
  ) -> [NSAttributedString.Key: Any] {
    var attributes: [NSAttributedString.Key: Any] = [.font: font]
    switch state {
    case .correct:
      attributes[.foregroundColor] = NSColor.labelColor
    case .incorrect:
      attributes[.foregroundColor] = NSColor.systemRed
      attributes[.backgroundColor] = NSColor.systemRed.withAlphaComponent(0.14)
    case .extra:
      attributes[.foregroundColor] = NSColor.systemRed
      attributes[.backgroundColor] = NSColor.systemRed.withAlphaComponent(0.1)
      attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
    case .pending, .current, .hidden:
      attributes[.foregroundColor] = NSColor.secondaryLabelColor
    }
    return attributes
  }
}
