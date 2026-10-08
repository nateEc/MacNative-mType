import AppKit
import SwiftUI

/// A single native presentation clock drives the tape text and its sibling
/// markers. Pace deadlines remain independent; no SwiftUI per-frame rebuild.
final class TapePromptNativeView: NSView {
  private let textView = TapePromptTextView()
  private let caretView = PromptCaretNativeView()
  private var configuration: PromptCaretNativeView.Configuration?
  private var rendering = PromptRendering(text: AttributedString(), glyphCharacterOffsets: [:])
  private var anchorCharacterIndex = 0
  private var wordAnchorCharacterIndex = 0
  private var wordStartCharacterOffsets: [Int: Int] = [:]
  private var checksDirectionPerGlyph = false
  private var mode: PracticeTapeMode = .off
  private var margin = 0.0
  private var smoothScroll = false
  private var lastInput: PromptCaretInputIdentity?
  private var lastWidth: CGFloat = 0
  private var geometryRevision: UInt64 = 0
  private var timer: Timer?
  private var needsScroll = false
  private var snapsScroll = true
  private var lastScrollAdvance: CGFloat?

  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true; layer?.masksToBounds = true
    addSubview(textView); addSubview(caretView)
    setAccessibilityElement(true); setAccessibilityRole(.staticText)
  }
  required init?(coder: NSCoder) { fatalError("TapePromptNativeView is created in code") }

  func configure(rendering: PromptRendering, anchorCharacterIndex: Int, wordAnchorCharacterIndex: Int,
    wordStartCharacterOffsets: [Int: Int] = [:],
    checksDirectionPerGlyph: Bool = false,
    mode: PracticeTapeMode, margin: Double, smoothScroll: Bool,
    carets: PromptCaretNativeView.Configuration, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
    let nextInput = carets.latestInput?()
    let resets = configuration == nil || configuration?.attemptID != carets.attemptID
      || configuration?.coordinator !== carets.coordinator || configuration?.font != carets.font
      || self.mode != mode || self.margin != margin || self.smoothScroll != smoothScroll
      || configuration?.reducesMotion != carets.reducesMotion
      || configuration?.rightToLeft != carets.rightToLeft || self.checksDirectionPerGlyph != checksDirectionPerGlyph
    needsScroll = needsScroll || resets || self.anchorCharacterIndex != anchorCharacterIndex
      || nextInput != lastInput
    snapsScroll = snapsScroll || resets
    if resets || self.rendering.text != rendering.text || self.rendering.glyphCharacterOffsets != rendering.glyphCharacterOffsets
      || self.wordStartCharacterOffsets != wordStartCharacterOffsets {
      geometryRevision &+= 1
    }
    configuration = carets; self.rendering = rendering
    self.anchorCharacterIndex = anchorCharacterIndex; self.wordAnchorCharacterIndex = wordAnchorCharacterIndex
    self.wordStartCharacterOffsets = wordStartCharacterOffsets
    self.checksDirectionPerGlyph = checksDirectionPerGlyph
    self.mode = mode; self.margin = margin.clamped(to: 0...1); self.smoothScroll = smoothScroll
    lastInput = nextInput
    carets.coordinator.prepare(attemptID: carets.attemptID)
    if resets { carets.coordinator.resetLayout() }
    textView.configure(text: rendering.text, font: carets.font, rightToLeft: carets.rightToLeft)
    setAccessibilityLabel(String(rendering.text.characters))
    updateGeometry(at: time)
    // Input/configuration requests do not advance animations between frames.
    // Initial/re-anchored geometry has no running layout to preserve.
    if resets { present(at: time) }
    schedulePresentation()
  }

  override func layout() {
    super.layout()
    guard configuration != nil, lastWidth != bounds.width else { return }
    needsScroll = true; snapsScroll = true
    updateGeometry(at: ProcessInfo.processInfo.systemUptime)
    present(at: ProcessInfo.processInfo.systemUptime)
    schedulePresentation()
  }

  private func updateGeometry(at time: TimeInterval) {
    guard var config = configuration, bounds.width > 0 else { return }
    if lastWidth != bounds.width {
      lastWidth = bounds.width; geometryRevision &+= 1
      config.coordinator.resetLayout()
    }
    textView.setFrameSize(.init(width: max(bounds.width, textView.contentWidth), height: bounds.height))
    caretView.frame = bounds
    config.glyphRect = { [weak self] id in self?.glyphRect(id, main: false) }
    config.mainGlyphRect = { [weak self] id in self?.glyphRect(id, main: true) }
    config.glyphIsRightToLeft = { [weak self] id in self?.isRightToLeft(id) ?? false }
    config.geometryRevision = geometryRevision
    config.firstGlyphID = rendering.glyphCharacterOffsets.min { $0.value < $1.value }?.key ?? 0
    config.automaticallyPresents = false
    caretView.update(config); caretView.layoutSubtreeIfNeeded()
    let advance = textView.advance(at: anchorCharacterIndex,
      wordStart: wordStartCharacterOffsets[anchorCharacterIndex], mode: mode, rightToLeft: config.rightToLeft)
    if needsScroll || advance != lastScrollAdvance {
      config.coordinator.tapeScroll(to: config.rightToLeft ? advance : -advance,
        duration: snapsScroll || !smoothScroll || config.reducesMotion ? 0 : 0.125, at: time)
      needsScroll = false; snapsScroll = false
      lastScrollAdvance = advance
    }
  }

  private func glyphRect(_ id: Int, main: Bool) -> CGRect? {
    guard let offset = rendering.characterOffset(forGlyphAt: id),
      var rect = textView.glyphRect(at: offset, minimumOffset: wordStartCharacterOffsets[offset] ?? offset) else { return nil }
    if main {
      let rtl = isRightToLeft(id)
      let base = bounds.width * (rtl ? 1 - margin : margin)
      if mode == .word, let word = textView.wordRect(at: wordAnchorCharacterIndex, start: wordAnchorCharacterIndex) {
        rect.origin.x += base - (rtl ? word.maxX : word.minX)
      } else { rect.origin.x = base - (rtl ? rect.width : 0) }
    } else { rect.origin.x += textOrigin }
    return rect
  }

  private var textOrigin: CGFloat {
    let rtl = configuration?.rightToLeft ?? false
    return bounds.width * (rtl ? 1 - margin : margin) - textView.leadingEdge(rightToLeft: rtl)
  }

  private func isRightToLeft(_ id: Int) -> Bool {
    guard let offset = rendering.characterOffset(forGlyphAt: id) else { return configuration?.rightToLeft ?? false }
    return textView.direction(at: offset, wordStart: wordStartCharacterOffsets[offset],
      perGlyph: checksDirectionPerGlyph, fallback: configuration?.rightToLeft ?? false)
  }

  /// Deterministic component entry point; also used by the bounded native timer.
  func present(at time: TimeInterval) {
    guard let config = configuration else { return }
    config.coordinator.sample(at: time)
    textView.setFrameOrigin(.init(x: textOrigin + config.coordinator.wordsTapeMargin, y: 0))
    caretView.present(at: time)
    if !config.coordinator.isAnimatingTape, !config.mainStyle.drawsMarker, !config.paceStyle.drawsMarker {
      timer?.invalidate(); timer = nil
    }
  }

  private func schedulePresentation() {
    guard let config = configuration,
      config.mainStyle.drawsMarker || config.paceStyle.drawsMarker || config.coordinator.isAnimatingTape else { return }
    let interval = PromptLineScrollMotion.frameInterval(frameRate: config.frameRate,
      displayFrameRate: window?.screen?.maximumFramesPerSecond ?? 60)
    if timer?.timeInterval == interval { return }
    timer?.invalidate()
    let timer = Timer(timeInterval: interval, target: TapePromptTimerTarget(owner: self),
      selector: #selector(TapePromptTimerTarget.tick(_:)), userInfo: nil, repeats: true)
    self.timer = timer; RunLoop.main.add(timer, forMode: .common)
  }

  fileprivate func advance(_ timer: Timer) {
    guard timer === self.timer else { timer.invalidate(); return }
    present(at: ProcessInfo.processInfo.systemUptime)
  }

  func stop() {
    timer?.invalidate(); timer = nil
    caretView.stop()
    configuration?.coordinator.cancel(at: ProcessInfo.processInfo.systemUptime)
    configuration = nil; lastInput = nil
    lastScrollAdvance = nil
    needsScroll = false; snapsScroll = true
  }

  override func viewWillMove(toSuperview newSuperview: NSView?) {
    if newSuperview == nil { stop() }
    super.viewWillMove(toSuperview: newSuperview)
  }
}

@MainActor private final class TapePromptTimerTarget: NSObject {
  private weak var owner: TapePromptNativeView?
  init(owner: TapePromptNativeView) { self.owner = owner }
  @objc func tick(_ timer: Timer) {
    guard let owner else { timer.invalidate(); return }
    owner.advance(timer)
  }
}

/// Drawing and measuring share this one prepared native text storage. Colors,
/// hint metrics and hidden listening text are not approximated by fixed widths.
private final class TapePromptTextView: NSView {
  private let layoutManager = NSLayoutManager()
  private let container = NSTextContainer(size: .init(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
  private var storage = NSTextStorage()
  private var text = AttributedString()
  private var font: NSFont?
  private var rightToLeft = false
  private var characters: [Character] = []
  private var characterRanges: [NSRange] = []
  private var leadingLeft: CGFloat = 0
  private var leadingRight: CGFloat = 0
  var contentWidth: CGFloat { layoutManager.usedRect(for: container).maxX }
  override var isFlipped: Bool { true }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    container.lineFragmentPadding = 0
    layoutManager.addTextContainer(container); storage.addLayoutManager(layoutManager)
    setAccessibilityElement(false)
  }
  required init?(coder: NSCoder) { fatalError("TapePromptTextView is created in code") }

  func configure(text: AttributedString, font: NSFont, rightToLeft: Bool) {
    guard self.text != text || self.font != font || self.rightToLeft != rightToLeft else { return }
    self.text = text; self.font = font; self.rightToLeft = rightToLeft
    let prepared = TapePromptTextStorage.prepare(text, font: font, rightToLeft: rightToLeft)
    storage.setAttributedString(prepared)
    let string = storage.string
    characters = Array(string)
    characterRanges = string.indices.map { index in
      NSRange(index..<string.index(after: index), in: string)
    }
    layoutManager.ensureLayout(for: container)
    let first = wordRect(at: 0, start: 0)
    leadingLeft = first?.minX ?? 0; leadingRight = first?.maxX ?? 0
    needsDisplay = true
  }

  func glyphRect(at offset: Int, minimumOffset: Int) -> CGRect? {
    guard characterRanges.indices.contains(offset) else { return nil }
    var original: CGRect?
    for index in stride(from: offset, through: max(0, minimumOffset), by: -1) {
      let range = layoutManager.glyphRange(forCharacterRange: characterRanges[index], actualCharacterRange: nil)
      let rect = TapePromptTextStorage.advanceRect(range, manager: layoutManager, container: container)
      if index == offset { original = rect }
      if rect.width > 0, rect.height > 0 { return rect }
    }
    return original
  }

  private func wordRange(at offset: Int, start: Int?) -> Range<Int>? {
    guard characters.indices.contains(offset) else { return nil }
    var lower = start ?? offset
    if start == nil { while lower > 0 && !characters[lower - 1].isWhitespace { lower -= 1 } }
    var upper = lower
    while upper < characters.count && !characters[upper].isWhitespace { upper += 1 }
    return lower..<upper
  }

  private func rect(for range: Range<Int>) -> CGRect? {
    guard let first = range.first, let last = range.last,
      characterRanges.indices.contains(first), characterRanges.indices.contains(last) else { return nil }
    let nativeRange = NSUnionRange(characterRanges[first], characterRanges[last])
    return TapePromptTextStorage.advanceRect(layoutManager.glyphRange(forCharacterRange: nativeRange,
      actualCharacterRange: nil), manager: layoutManager, container: container)
  }

  func wordRect(at offset: Int, start: Int?) -> CGRect? {
    wordRange(at: offset, start: start).flatMap { rect(for: $0) }
  }

  func leadingEdge(rightToLeft: Bool) -> CGFloat {
    rightToLeft ? leadingRight : leadingLeft
  }

  func advance(at offset: Int, wordStart: Int?, mode: PracticeTapeMode, rightToLeft: Bool) -> CGFloat {
    if offset == characterRanges.count { return contentWidth }
    guard let range = wordRange(at: offset, start: wordStart), let word = rect(for: range) else { return 0 }
    let before = rightToLeft ? leadingEdge(rightToLeft: true) - word.maxX : word.minX - leadingEdge(rightToLeft: false)
    guard mode == .letter, offset > range.lowerBound else { return before }
    var within = rect(for: range.lowerBound..<offset)?.width ?? 0
    if glyphRect(at: offset, minimumOffset: offset)?.width == 0 {
      for index in stride(from: offset - 1, through: range.lowerBound, by: -1) {
        if let previous = glyphRect(at: index, minimumOffset: index), previous.width > 0 {
          within -= previous.width; break
        }
      }
    }
    return before + within
  }

  func direction(at offset: Int, wordStart: Int?, perGlyph: Bool, fallback: Bool) -> Bool {
    guard characters.indices.contains(offset) else { return fallback }
    let text: String
    if perGlyph { text = String(characters[offset]) }
    else if let range = wordRange(at: offset, start: wordStart) { text = String(characters[range]) }
    else { return fallback }
    return PracticeTapePolicy.isRightToLeft(text, fallback: fallback)
  }

  override func draw(_ dirtyRect: NSRect) {
    let range = layoutManager.glyphRange(forBoundingRect: dirtyRect, in: container)
    layoutManager.drawBackground(forGlyphRange: range, at: .zero)
    layoutManager.drawGlyphs(forGlyphRange: range, at: .zero)
  }
}

enum TapePromptTextStorage {
  static func advanceRect(_ range: NSRange, manager: NSLayoutManager, container: NSTextContainer) -> CGRect {
    var result = CGRect.null
    manager.enumerateEnclosingRects(forGlyphRange: range,
      withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { rect, _ in
      result = result.union(rect)
    }
    // Zero-width controls may not have an enclosing advance rectangle.
    return result.isNull ? manager.boundingRect(forGlyphRange: range, in: container) : result
  }

  static func prepare(_ text: AttributedString, font: NSFont, rightToLeft: Bool = false) -> NSTextStorage {
    let storage = PromptCaretLayout.preparedStorage(in: text, font: font, lineSpacing: 0, isRightToLeft: rightToLeft)
    // Unbounded tape must have a finite natural origin even for RTL. Direction
    // shapes the native line; the tape owner positions that line in its viewport.
    let paragraph = NSMutableParagraphStyle()
    paragraph.baseWritingDirection = rightToLeft ? .rightToLeft : .leftToRight
    paragraph.alignment = .left
    storage.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: storage.length))
    // Each reference word is an independent inline box. Embeddings preserve
    // that order without injecting direction controls into input or replay.
    let direction = (rightToLeft ? NSWritingDirection.rightToLeft : .leftToRight).rawValue
      | NSWritingDirectionFormatType.embedding.rawValue
    for word in storage.string.split(whereSeparator: \.isWhitespace) {
      storage.addAttribute(.writingDirection, value: [direction],
        range: NSRange(word.startIndex..<word.endIndex, in: storage.string))
    }
    // Foundation retains SwiftUI attributes under SwiftUI.* keys. AppKit's
    // glyph drawer needs explicit native colors and line styles instead.
    var offset = 0
    for run in text.runs {
      let length = String(text[run.range].characters).utf16.count
      let range = NSRange(location: offset, length: length)
      if let color = run.foregroundColor { storage.addAttribute(.foregroundColor, value: NSColor(color), range: range) }
      if let color = run.backgroundColor { storage.addAttribute(.backgroundColor, value: NSColor(color), range: range) }
      if run.underlineStyle != nil { storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
      if let baseline = run.baselineOffset { storage.addAttribute(.baselineOffset, value: Double(baseline), range: range) }
      if let kern = run.kern { storage.addAttribute(.kern, value: Double(kern), range: range) }
      offset += length
    }
    return storage
  }
}
