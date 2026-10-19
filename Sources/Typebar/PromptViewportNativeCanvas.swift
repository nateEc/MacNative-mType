import AppKit

/// A native drawing surface for measured, globally positioned field windows.
/// This is not yet the production scroll/caret host: incomplete snapshots
/// expose only measured prefix height, never a guessed full-page extent.
@MainActor final class PromptViewportNativeCanvas: NSView {
  private var snapshot: PromptViewportFieldLayoutSequence.DrawingSnapshot?
  private let caret = PromptCaretNativeView(frame: .zero)
  private var caretConfiguration: PromptCaretNativeView.Configuration?
  private var geometryRevision: UInt64 = 0
  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    caret.frame = bounds
    caret.isHidden = true
    addSubview(caret)
    setAccessibilityElement(true)
    setAccessibilityRole(.staticText)
  }
  required init?(coder: NSCoder) { fatalError("PromptViewportNativeCanvas is created in code") }

  func clear() {
    snapshot = nil
    caretConfiguration = nil
    caret.stop()
    caret.isHidden = true
    setAccessibilityValue("")
    invalidateIntrinsicContentSize()
    needsDisplay = true
  }

  private func retireSnapshotIfWidthChanged(from oldWidth: CGFloat) {
    guard snapshot != nil, abs(bounds.width - oldWidth) >= 0.001 else { return }
    clear()
  }
  override func setFrameSize(_ newSize: NSSize) {
    let oldWidth = bounds.width
    super.setFrameSize(newSize)
    retireSnapshotIfWidthChanged(from: oldWidth)
    caret.frame = bounds
  }
  override func setBoundsSize(_ newSize: NSSize) {
    let oldWidth = bounds.width
    super.setBoundsSize(newSize)
    retireSnapshotIfWidthChanged(from: oldWidth)
    caret.frame = bounds
  }

  @discardableResult func configure(snapshot next: PromptViewportFieldLayoutSequence.DrawingSnapshot) -> Bool {
    guard next.width.isFinite, next.width > 0,
      abs(bounds.width - next.width) < 0.001,
      next.measuredHeight.isFinite, next.measuredHeight >= 0,
      next.windows.allSatisfy({ $0.layout.size.height <= next.measuredHeight })
    else { return false }
    let oldSize = intrinsicContentSize
    snapshot = next
    geometryRevision &+= 1
    applyCaretConfiguration()
    setAccessibilityValue(next.accessibilityText)
    needsDisplay = true
    if intrinsicContentSize != oldSize { invalidateIntrinsicContentSize() }
    return true
  }

  var hasCompleteHeight: Bool { snapshot?.hasCompleteHeight ?? false }
  override var intrinsicContentSize: NSSize {
    guard let snapshot else { return .init(width: NSView.noIntrinsicMetric, height: 0) }
    return .init(width: snapshot.width, height: snapshot.measuredHeight)
  }
  func measuredRect(for id: Int) -> CGRect? {
    snapshot?.windows.reversed().compactMap { $0.layout.cellFrames[id] }.first
  }
  func measuredMainCaretRect(style: TypingCaretStyle) -> CGRect? {
    snapshot?.windows.compactMap { $0.layout.mainRect(style: style) }.first
  }
  var caretIsRetired: Bool { caret.isHidden }
  var hasVisibleMainMarker: Bool { caret.hasVisibleMainMarker }
  var hasVisiblePaceMarker: Bool { caret.hasVisiblePaceMarker }
  func configureCaret(_ configuration: PromptCaretNativeView.Configuration) {
    caretConfiguration = configuration
    applyCaretConfiguration()
  }
  func presentCaret(at time: TimeInterval) {
    guard snapshot != nil, caretConfiguration != nil else { return }
    caret.present(at: time)
  }
  private func applyCaretConfiguration() {
    guard snapshot != nil, var configuration = caretConfiguration else { return }
    let hasMainAnchor = measuredMainCaretRect(style: .bar) != nil
    let hasPaceFrame = configuration.paceStyle.drawsMarker && configuration.paceFrame != nil
    guard hasMainAnchor || hasPaceFrame else {
      caret.stop()
      caret.isHidden = true
      return
    }
    let originalPresentation = configuration.mainPresentation
    configuration.mainPresentation = { [weak self] in
      var presentation = originalPresentation?() ?? .init()
      if self?.measuredMainCaretRect(style: .bar) == nil { presentation.isVisible = false }
      return presentation
    }
    if let originalPaceFrame = configuration.paceFrame {
      configuration.paceFrame = { [weak self] in
        guard let frame = originalPaceFrame(), let target = frame.targetGlyphID,
          self?.snapshot?.windows.contains(where: {
            $0.layout.canonicalRect(target, after: frame.targetAfter) != nil
          }) == true else { return nil }
        return frame
      }
    }
    let perGlyph = configuration.fieldDirectionPerGlyph
    let fallbackDirection = configuration.rightToLeft
    configuration.geometryRevision = geometryRevision
    configuration.fieldMainRect = { [weak self] style in
      self?.measuredMainCaretRect(style: style)
    }
    configuration.fieldMainDirection = { [weak self] in
      self?.snapshot?.windows.first(where: { $0.layout.mainRect(style: .bar) != nil })?
        .layout.mainDirection(perGlyph: perGlyph) ?? fallbackDirection
    }
    configuration.fieldPaceRect = { [weak self] id, after in
      self?.snapshot?.windows.compactMap { $0.layout.canonicalRect(id, after: after) }.first
    }
    configuration.markedCellRect = { [weak self] id in self?.measuredRect(for: id) }
    caret.frame = bounds
    caret.isHidden = false
    caret.update(configuration)
  }
  func renderedCellText(for id: Int) -> AttributedString? {
    snapshot?.windows.reversed().lazy
      .flatMap(\.runs).lazy.flatMap(\.cells)
      .first(where: { $0.id == id })?.text
  }
  override func draw(_ dirtyRect: NSRect) {
    for window in snapshot?.windows ?? [] { window.layout.draw(in: dirtyRect) }
  }
}
