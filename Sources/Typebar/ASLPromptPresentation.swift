import AppKit
import SwiftUI

/// A cell consumes the common prompt's final attributes. It never decides
/// correctness, highlighting, typo replacement, composition or saved input.
struct ASLPromptGlyphContent {
  let text: AttributedString

  init(glyph: TypingPromptGlyph, text: AttributedString? = nil) {
    if let text {
      self.text = text
    } else {
      var value = AttributedString(String(glyph.typedCharacter ?? glyph.character))
      switch glyph.state {
      case .correct: value.foregroundColor = .primary
      case .incorrect, .extra: value.foregroundColor = .red
      case .current, .pending: value.foregroundColor = .secondary.opacity(0.55)
      case .hidden: value.foregroundColor = .clear
      }
      self.text = value
    }
  }

  static func make(glyphs: [TypingPromptGlyph], ids: [Int], rendering: PromptRendering?) -> [Self] {
    guard let rendering else { return glyphs.map { .init(glyph: $0) } }
    // Build Character indices and range boundaries once, not a scan from the
    // beginning of the whole prompt for every cell (quadratic on long text).
    let indices = Array(rendering.text.characters.indices) + [rendering.text.endIndex]
    let starts = Set(rendering.glyphCharacterOffsets.values).sorted()
    var texts: [Int: AttributedString] = [:]
    for (index, start) in starts.enumerated() {
      let end = index + 1 < starts.count ? starts[index + 1] : indices.count - 1
      guard start >= 0, end >= start, end < indices.count else { continue }
      texts[start] = AttributedString(rendering.text[indices[start]..<indices[end]])
    }
    return glyphs.enumerated().map { index, glyph in
      let text = ids.indices.contains(index)
        ? rendering.glyphCharacterOffsets[ids[index]].flatMap { texts[$0] } : nil
      return .init(glyph: glyph, text: text ?? AttributedString())
    }
  }

  var main: AttributedString {
    guard let hint = text.runs.first(where: { ($0.baselineOffset ?? 0) < 0 }) else { return text }
    return AttributedString(text[..<hint.range.lowerBound])
  }
  var hint: AttributedString? {
    guard let hint = text.runs.first(where: { ($0.baselineOffset ?? 0) < 0 }) else { return nil }
    return AttributedString(text[hint.range.lowerBound...])
  }
}

struct ASLPromptGlyphCell: View {
  let content: ASLPromptGlyphContent
  let size: CGFloat
  let font: NSFont

  var body: some View {
    glyph(content.main, size: size)
      .overlay(alignment: .bottomLeading) {
        if let hint = content.hint {
          glyph(hint, size: max(9, size * 0.48)).offset(y: size * 0.42)
        }
      }
  }

  @ViewBuilder private func glyph(_ text: AttributedString, size: CGFloat) -> some View {
    if text.characters.count == 1, let character = text.characters.first,
      ASLHandshapePolicy.handshape(for: character) != nil {
      ASLHandshapeGlyph(character: character, color: text.foregroundColor ?? .secondary,
        background: text.backgroundColor ?? .clear, size: size)
        .overlay(alignment: .bottom) {
          if text.underlineStyle != nil {
            Rectangle().fill(text.appKit.underlineColor.map { Color(nsColor: $0) }
              ?? text.foregroundColor ?? .secondary).frame(height: max(1, size * 0.05))
          }
        }
    } else {
      Text(text).font(Font(font))
    }
  }
}

struct ASLPromptBoundsKey: PreferenceKey {
  static var defaultValue: [Int: Anchor<CGRect>] { [:] }
  static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
    value.merge(nextValue(), uniquingKeysWith: { _, next in next })
  }
}

struct ASLPromptCaretBridge: NSViewRepresentable {
  let configuration: PromptCaretNativeView.Configuration
  let frames: [Int: CGRect]
  let glyphIDs: [Int]
  func makeNSView(context: Context) -> ASLPromptCaretContainer { ASLPromptCaretContainer() }
  func updateNSView(_ view: ASLPromptCaretContainer, context: Context) {
    view.configure(configuration, frames: frames, glyphIDs: glyphIDs)
  }
  static func dismantleNSView(_ view: ASLPromptCaretContainer, coordinator: ()) { view.stop() }
}

/// Owns no timer. Both markers use the shared native caret controller, with
/// actual SwiftUI cell bounds rather than a Latin-font TextKit approximation.
final class ASLPromptCaretContainer: NSView {
  private var frames: [Int: CGRect] = [:]
  private var glyphIDs: [Int] = []
  private var indexByID: [Int: Int] = [:]
  private var revision: UInt64 = 0
  private let caret = PromptCaretNativeView()
  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    caret.autoresizingMask = [.width, .height]
    addSubview(caret)
    setAccessibilityElement(false)
  }
  required init?(coder: NSCoder) { fatalError("ASLPromptCaretContainer is created in code") }

  func configure(_ config: PromptCaretNativeView.Configuration, frames: [Int: CGRect], glyphIDs: [Int]) {
    if self.frames != frames || self.glyphIDs != glyphIDs {
      if self.glyphIDs != glyphIDs {
        indexByID = Dictionary(glyphIDs.enumerated().map { ($0.element, $0.offset) },
          uniquingKeysWith: { first, _ in first })
      }
      self.frames = frames; self.glyphIDs = glyphIDs; revision &+= 1
    }
    var config = config
    config.geometryRevision = revision
    config.firstGlyphID = glyphIDs.first(where: { frames[$0] != nil }) ?? 0
    config.glyphRect = { [weak self] id in self?.rect(for: id) }
    caret.frame = bounds
    caret.update(config)
  }

  func rect(for id: Int) -> CGRect? {
    guard frames[id] != nil, let index = indexByID[id] else { return nil }
    for position in stride(from: index, through: 0, by: -1) {
      if let frame = frames[glyphIDs[position]], frame.width > 0, frame.height > 0 { return frame }
    }
    return nil
  }

  func measuredRect(for id: Int) -> CGRect? { frames[id] }

  override func layout() { super.layout(); caret.frame = bounds }
  override func viewWillMove(toSuperview newSuperview: NSView?) {
    if newSuperview == nil { stop() }
    super.viewWillMove(toSuperview: newSuperview)
  }
  func stop() { caret.stop() }
}
