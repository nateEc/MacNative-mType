import AppKit

/// Stable target IDs let a word keep its identity when preceding hints or
/// extra glyphs change its rendered character offset.
struct PromptLineScrollContext {
  let attemptID: UUID
  let activeWordID: Int?
  let characterOffsets: [Int: Int]
  let smoothScroll: Bool
  let reducesMotion: Bool
  var frameRate = AnimationFrameRatePolicy.nativeFrameRate
}

enum PromptLineScrollMotion {
  static let duration: TimeInterval = 0.125

  static func frameInterval(frameRate: Int, displayFrameRate: Int) -> TimeInterval {
    let displayLimit = displayFrameRate > 0 ? displayFrameRate : 60
    return 1 / Double(min(AnimationFrameRatePolicy.normalized(frameRate), displayLimit))
  }

  static func progress(elapsed: TimeInterval) -> CGFloat {
    let fraction = min(1, max(0, elapsed / duration))
    return CGFloat(fraction * (2 - fraction))
  }
}

struct PromptLineScrollGeometry {
  let activeTop: CGFloat
  let previousWordTop: CGFloat?
  let previousLineTop: CGFloat
  var caretBottom: CGFloat? = nil

  static func measure(in text: AttributedString, activeOffset: Int, previousOffset: Int?,
    width: CGFloat, font: NSFont, lineSpacing: CGFloat, rightToLeft: Bool,
    caretOffset: Int? = nil) -> Self? {
    guard width > 0, activeOffset >= 0, activeOffset < text.characters.count else { return nil }
    let storage = PromptCaretLayout.preparedStorage(in: text, font: font,
      lineSpacing: lineSpacing, isRightToLeft: rightToLeft)
    let manager = NSLayoutManager()
    let container = NSTextContainer(size: .init(width: width, height: .greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    manager.addTextContainer(container)
    storage.addLayoutManager(manager)
    func line(at offset: Int, range: inout NSRange) -> CGRect? {
      guard offset >= 0, offset < text.characters.count else { return nil }
      let utf16 = String(text.characters.prefix(offset)).utf16.count
      let glyph = manager.glyphIndexForCharacter(at: utf16)
      return manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &range)
    }
    var activeRange = NSRange()
    guard let active = line(at: activeOffset, range: &activeRange) else { return nil }
    let previousLine = activeRange.location > 0
      ? manager.lineFragmentRect(forGlyphAt: activeRange.location - 1, effectiveRange: nil).minY : 0
    var previousRange = NSRange()
    let previous = previousOffset.flatMap { line(at: $0, range: &previousRange)?.minY }
    var caretRange = NSRange()
    let caretBottom = caretOffset.flatMap { line(at: $0, range: &caretRange)?.maxY }
    return .init(activeTop: active.minY, previousWordTop: previous, previousLineTop: previousLine,
      caretBottom: caretBottom)
  }

  func targetTop(previousTarget: CGFloat, recenter: Bool) -> CGFloat {
    if recenter { return previousLineTop }
    guard let previousWordTop else { return previousLineTop }
    if activeTop > previousWordTop { return max(previousTarget, previousWordTop) }
    // Native history navigation still permits returning to retained text.
    // Source deleted-word backspace bounds are tracked separately.
    return min(previousTarget, activeTop)
  }
}
