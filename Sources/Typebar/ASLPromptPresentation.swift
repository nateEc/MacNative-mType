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
  let configuration: PromptCaretNativeView.Configuration?
  let frames: [Int: CGRect]
  let glyphIDs: [Int]
  var lineScroll: PromptLineScrollContext? = nil
  var caretGlyphID: Int? = nil
  var text = AttributedString()
  var font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @Environment(\.typebarAnimationFrameRate) private var frameRate
  func makeNSView(context: Context) -> ASLPromptCaretContainer { ASLPromptCaretContainer() }
  func updateNSView(_ view: ASLPromptCaretContainer, context: Context) {
    let lineScroll = lineScroll.map {
      PromptLineScrollContext(attemptID: $0.attemptID, activeWordID: $0.activeWordID,
        characterOffsets: $0.characterOffsets, smoothScroll: $0.smoothScroll,
        reducesMotion: $0.reducesMotion || systemReduceMotion, frameRate: frameRate,
        words: $0.words, firstRetainedWordIndex: $0.firstRetainedWordIndex,
        onRetire: $0.onRetire, followsWordReflow: $0.followsWordReflow, caretMotion: $0.caretMotion)
    }
    view.configure(configuration, frames: frames, glyphIDs: glyphIDs,
      lineScroll: lineScroll, caretGlyphID: caretGlyphID, text: text, font: font)
  }
  static func dismantleNSView(_ view: ASLPromptCaretContainer, coordinator: ()) { view.stop() }
}

/// Owns no timer. Its children use the shared scroll and caret controllers, with
/// actual SwiftUI cell bounds rather than a Latin-font TextKit approximation.
final class ASLPromptCaretContainer: NSView {
  private var frames: [Int: CGRect] = [:]
  private var glyphIDs: [Int] = []
  private var indexByID: [Int: Int] = [:]
  private var revision: UInt64 = 0
  private let caret = PromptCaretNativeView()
  private let follower = PromptAutoScrollView()
  private var lineGeometry = ASLPromptLineGeometry(frames: [:])
  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    caret.autoresizingMask = [.width, .height]
    addSubview(caret)
    follower.autoresizingMask = [.width, .height]
    addSubview(follower, positioned: .below, relativeTo: caret)
    setAccessibilityElement(false)
  }
  required init?(coder: NSCoder) { fatalError("ASLPromptCaretContainer is created in code") }

  func configure(_ config: PromptCaretNativeView.Configuration?, frames: [Int: CGRect], glyphIDs: [Int],
    lineScroll: PromptLineScrollContext? = nil, caretGlyphID: Int? = nil,
    text: AttributedString = AttributedString(), font: NSFont = .monospacedSystemFont(ofSize: 28, weight: .regular)) {
    if self.frames != frames || self.glyphIDs != glyphIDs {
      if self.glyphIDs != glyphIDs {
        indexByID = Dictionary(glyphIDs.enumerated().map { ($0.element, $0.offset) },
          uniquingKeysWith: { first, _ in first })
      }
      self.frames = frames; self.glyphIDs = glyphIDs; revision &+= 1
      lineGeometry = ASLPromptLineGeometry(frames: frames)
    }
    caret.frame = bounds
    caret.isHidden = config == nil
    if var config {
      config.geometryRevision = revision
      config.firstGlyphID = glyphIDs.first(where: { frames[$0] != nil }) ?? 0
      config.glyphRect = { [weak self] id in self?.rect(for: id) }
      caret.update(config)
    } else { caret.stop() }
    follower.frame = bounds
    follower.update(text: text, characterOffset: nil, font: font, lineSpacing: 12,
      isRightToLeft: false, lineScroll: lineScroll,
      customGeometry: .init(revision: revision, caretGlyphID: caretGlyphID,
        measure: { [weak self] active, previous, caret, words in
          self?.lineGeometry.measure(active: active, previous: previous, caret: caret, words: words)
        }))
  }

  func rect(for id: Int) -> CGRect? {
    guard frames[id] != nil, let index = indexByID[id] else { return nil }
    for position in stride(from: index, through: 0, by: -1) {
      if let frame = frames[glyphIDs[position]], frame.width > 0, frame.height > 0 { return frame }
    }
    return nil
  }

  func measuredRect(for id: Int) -> CGRect? { frames[id] }

  override func layout() { super.layout(); caret.frame = bounds; follower.frame = bounds }
  override func viewWillMove(toSuperview newSuperview: NSView?) {
    if newSuperview == nil { stop() }
    super.viewWillMove(toSuperview: newSuperview)
  }
  func stop() { caret.stop(); follower.cancelCaretMotion(); follower.stopLineScroll() }
}

/// Cached once per anchor revision. Mixed fallback glyphs may be taller than
/// hands; row steps come from placement, not an assumed font line height.
struct ASLPromptLineGeometry {
  let frames: [Int: CGRect]
  private let rows: [CGRect]
  private let rowByID: [Int: Int]
  let rowHeights: [CGFloat]

  init(frames: [Int: CGRect], rowSpacing: CGFloat = 12) {
    self.frames = frames
    var rows: [CGRect] = [], indices: [Int: Int] = [:]
    for (id, frame) in frames.sorted(by: { $0.value.minY < $1.value.minY })
      where frame.width > 0 && frame.height > 0 && frame.minY.isFinite && frame.maxY.isFinite {
      if let last = rows.last, abs(last.minY - frame.minY) < 0.5 {
        rows[rows.count - 1] = last.union(frame)
      } else { rows.append(frame) }
      indices[id] = rows.count - 1
    }
    self.rows = rows; rowByID = indices
    rowHeights = rows.indices.map { index in
      index + 1 < rows.count ? rows[index + 1].minY - rows[index].minY : rows[index].height + rowSpacing
    }
  }

  func measure(active: Int, previous: Int?, caret: Int?, words: [PromptLineScrollWord]) -> PromptLineScrollGeometry? {
    guard let row = rowByID[active] else { return nil }
    return .init(activeTop: rows[row].minY,
      previousWordTop: previous.flatMap { rowByID[$0] }.map { rows[$0].minY },
      previousLineTop: row > 0 ? rows[row - 1].minY : 0,
      caretBottom: caret.flatMap { rowByID[$0] }.map { rows[$0].maxY },
      wordTops: Dictionary(words.compactMap { word in
        rowByID[word.glyphID].map { (word.index, rows[$0].minY) }
      }, uniquingKeysWith: { first, _ in first }), activeRowHeight: rowHeights[row])
  }
}
