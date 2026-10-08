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
    mode: PracticeTapeMode, margin: Double, smoothScroll: Bool,
    carets: PromptCaretNativeView.Configuration, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
    let nextInput = carets.latestInput?()
    let resets = configuration == nil || configuration?.attemptID != carets.attemptID
      || configuration?.coordinator !== carets.coordinator || configuration?.font != carets.font
      || self.mode != mode || self.margin != margin || self.smoothScroll != smoothScroll
      || configuration?.reducesMotion != carets.reducesMotion
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
    self.mode = mode; self.margin = margin.clamped(to: 0...1); self.smoothScroll = smoothScroll
    lastInput = nextInput
    carets.coordinator.prepare(attemptID: carets.attemptID)
    if resets { carets.coordinator.resetLayout() }
    textView.configure(text: rendering.text, font: carets.font)
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
    config.geometryRevision = geometryRevision
    config.firstGlyphID = rendering.glyphCharacterOffsets.min { $0.value < $1.value }?.key ?? 0
    config.automaticallyPresents = false
    caretView.update(config); caretView.layoutSubtreeIfNeeded()
    let advance = textView.anchorX(at: anchorCharacterIndex, minimumOffset: wordStartCharacterOffsets[anchorCharacterIndex] ?? anchorCharacterIndex)
    if needsScroll || advance != lastScrollAdvance {
      config.coordinator.tapeScroll(to: -advance,
        duration: snapsScroll || !smoothScroll || config.reducesMotion ? 0 : 0.125, at: time)
      needsScroll = false; snapsScroll = false
      lastScrollAdvance = advance
    }
  }

  private func glyphRect(_ id: Int, main: Bool) -> CGRect? {
    guard let offset = rendering.characterOffset(forGlyphAt: id),
      var rect = textView.glyphRect(at: offset, minimumOffset: wordStartCharacterOffsets[offset] ?? offset) else { return nil }
    let base = bounds.width * margin
    if main {
      rect.origin.x = base + (mode == .word ? rect.minX - textView.anchorX(at: wordAnchorCharacterIndex, minimumOffset: wordAnchorCharacterIndex) : 0)
    } else { rect.origin.x += base }
    return rect
  }

  /// Deterministic component entry point; also used by the bounded native timer.
  func present(at time: TimeInterval) {
    guard let config = configuration else { return }
    config.coordinator.sample(at: time)
    textView.setFrameOrigin(.init(x: bounds.width * margin + config.coordinator.wordsTapeMargin, y: 0))
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
  private var characterRanges: [NSRange] = []
  var contentWidth: CGFloat { layoutManager.usedRect(for: container).maxX }
  override var isFlipped: Bool { true }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    container.lineFragmentPadding = 0
    layoutManager.addTextContainer(container); storage.addLayoutManager(layoutManager)
    setAccessibilityElement(false)
  }
  required init?(coder: NSCoder) { fatalError("TapePromptTextView is created in code") }

  func configure(text: AttributedString, font: NSFont) {
    guard self.text != text || self.font != font else { return }
    self.text = text; self.font = font
    let prepared = TapePromptTextStorage.prepare(text, font: font)
    storage.setAttributedString(prepared)
    let string = storage.string
    characterRanges = string.indices.map { index in
      NSRange(index..<string.index(after: index), in: string)
    }
    layoutManager.ensureLayout(for: container)
    needsDisplay = true
  }

  func glyphRect(at offset: Int, minimumOffset: Int) -> CGRect? {
    guard characterRanges.indices.contains(offset) else { return nil }
    var original: CGRect?
    for index in stride(from: offset, through: max(0, minimumOffset), by: -1) {
      let range = layoutManager.glyphRange(forCharacterRange: characterRanges[index], actualCharacterRange: nil)
      let rect = layoutManager.boundingRect(forGlyphRange: range, in: container)
      if index == offset { original = rect }
      if rect.width > 0, rect.height > 0 { return rect }
    }
    return original
  }

  func anchorX(at offset: Int, minimumOffset: Int) -> CGFloat {
    if offset == characterRanges.count { return contentWidth }
    return glyphRect(at: offset, minimumOffset: minimumOffset)?.minX ?? 0
  }

  override func draw(_ dirtyRect: NSRect) {
    let range = layoutManager.glyphRange(forBoundingRect: dirtyRect, in: container)
    layoutManager.drawBackground(forGlyphRange: range, at: .zero)
    layoutManager.drawGlyphs(forGlyphRange: range, at: .zero)
  }
}

enum TapePromptTextStorage {
  static func prepare(_ text: AttributedString, font: NSFont) -> NSTextStorage {
    let storage = PromptCaretLayout.preparedStorage(in: text, font: font, lineSpacing: 0, isRightToLeft: false)
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
