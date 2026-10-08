import AppKit

struct PromptLineScrollWord {
  let index: Int
  let glyphID: Int
}

struct PromptWordRetirement: Equatable {
  let attemptID: UUID
  let firstRetainedWordIndex: Int
}

/// Stable target IDs let a word keep its identity when preceding hints or
/// extra glyphs change its rendered character offset.
struct PromptLineScrollContext {
  let attemptID: UUID
  let activeWordID: Int?
  let characterOffsets: [Int: Int]
  let smoothScroll: Bool
  let reducesMotion: Bool
  var frameRate = AnimationFrameRatePolicy.nativeFrameRate
  var words: [PromptLineScrollWord] = []
  var firstRetainedWordIndex = 0
  var onRetire: ((PromptWordRetirement) -> Void)? = nil
  var followsWordReflow = false
  var caretMotion: PromptCaretMotionCoordinator? = nil
  // Mirrors the raw showAllLines gate, not the effective bounded-height policy.
  var centersActiveLine = true
  // A host with config events can distinguish font measurement from a wrapper
  // update. Nil preserves geometry-driven behavior for standalone followers.
  var wrapperRevision: UInt64? = nil
}

/// Alternate layouts provide measured canonical glyph bounds, never Latin
/// character offsets masquerading as their geometry. The state machine stays shared.
struct PromptLineScrollCustomGeometry {
  let revision: UInt64
  let caretGlyphID: Int?
  let measure: (Int, Int?, Int?, [PromptLineScrollWord]) -> PromptLineScrollGeometry?
}

struct PromptWordReflowState {
  private(set) var baselineTop: CGFloat?
  private(set) var transitionStartTop: CGFloat = 0

  mutating func anchor(at top: CGFloat) { baselineTop = top }

  mutating func jumpFromTop(afterUpdate top: CGFloat, enabled: Bool, transitioning: Bool) -> CGFloat? {
    guard enabled, let baselineTop, top > baselineTop else { return nil }
    if !transitioning {
      transitionStartTop = top
      return baselineTop
    }
    return top > transitionStartTop ? baselineTop : nil
  }
}

enum PromptWordReflowPolicy {
  static func isEnabled(mode: TestMode, slowTimer: Bool, showAllLines: Bool) -> Bool {
    !showAllLines && (mode == .zen || slowTimer)
  }
}

enum PromptLineScrollMotion {
  static let duration: TimeInterval = 0.125
  static let autoplayLead: TimeInterval = 0.012

  static func frameInterval(frameRate: Int, displayFrameRate: Int) -> TimeInterval {
    let displayLimit = displayFrameRate > 0 ? displayFrameRate : 60
    return 1 / Double(min(AnimationFrameRatePolicy.normalized(frameRate), displayLimit))
  }

  static func progress(elapsed: TimeInterval) -> CGFloat {
    let fraction = min(1, max(0, elapsed / duration))
    return CGFloat(fraction * (2 - fraction))
  }
}

struct PromptLineScrollOverlap {
  private(set) var pendingJumps = 0
  private var baselineTop: CGFloat?

  mutating func begin(from baselineTop: CGFloat, rowHeight: CGFloat) -> CGFloat {
    pendingJumps += 1
    let origin = self.baselineTop ?? baselineTop
    self.baselineTop = origin
    return origin + rowHeight * CGFloat(pendingJumps)
  }
}

struct PromptLineScrollGeometry {
  let activeTop: CGFloat
  let previousWordTop: CGFloat?
  let previousLineTop: CGFloat
  var caretBottom: CGFloat? = nil
  var wordTops: [Int: CGFloat] = [:]
  var activeRowHeight: CGFloat = 0

  static func measure(in text: AttributedString, activeOffset: Int, previousOffset: Int?,
    width: CGFloat, font: NSFont, lineSpacing: CGFloat, rightToLeft: Bool,
    caretOffset: Int? = nil, words: [PromptLineScrollWord] = [],
    characterOffsets: [Int: Int] = [:]) -> Self? {
    guard width > 0, activeOffset >= 0, activeOffset < text.characters.count else { return nil }
    let storage = PromptCaretLayout.preparedStorage(in: text, font: font,
      lineSpacing: lineSpacing, isRightToLeft: rightToLeft)
    let manager = NSLayoutManager()
    let container = NSTextContainer(size: .init(width: width, height: .greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    manager.addTextContainer(container)
    storage.addLayoutManager(manager)
    var utf16Offsets = [0]
    if !words.isEmpty {
      for character in text.characters {
        utf16Offsets.append(utf16Offsets.last! + String(character).utf16.count)
      }
    }
    func line(at offset: Int, range: inout NSRange) -> CGRect? {
      guard offset >= 0, offset < text.characters.count else { return nil }
      let utf16 = words.isEmpty ? String(text.characters.prefix(offset)).utf16.count : utf16Offsets[offset]
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
    var wordTops: [Int: CGFloat] = [:]
    for word in words {
      var range = NSRange()
      if let offset = characterOffsets[word.glyphID], let rect = line(at: offset, range: &range) {
        wordTops[word.index] = rect.minY
      }
    }
    return .init(activeTop: active.minY, previousWordTop: previous, previousLineTop: previousLine,
      caretBottom: caretBottom, wordTops: wordTops,
      activeRowHeight: active.height + (NSMaxRange(activeRange) == manager.numberOfGlyphs ? lineSpacing : 0))
  }

  func retirementBoundary(before activeWordIndex: Int, hideBound: CGFloat? = nil) -> Int? {
    guard let previousWordTop = hideBound ?? previousWordTop, activeTop > previousWordTop else { return nil }
    // Browser offsetTop is integral; normalize native fractional row metrics
    // on both sides so words sharing one row cannot retire each other.
    return wordTops.filter { $0.key < activeWordIndex
      && $0.value.rounded(.down) < previousWordTop.rounded(.down) }.keys.max().map { $0 + 1 }
  }

  func recenterHideBound(before activeWordIndex: Int) -> CGFloat? {
    // Source centerActiveLine scans previous word containers, not the physical
    // row immediately above the active word (which may be inside a long token).
    wordTops.filter { $0.key < activeWordIndex && $0.value < activeTop }
      .max(by: { $0.key < $1.key })?.value
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
