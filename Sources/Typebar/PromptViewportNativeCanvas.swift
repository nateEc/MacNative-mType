import AppKit

/// A native drawing surface for measured, globally positioned field windows.
/// This is not yet the production scroll/caret host: incomplete snapshots
/// expose only measured prefix height, never a guessed full-page extent.
@MainActor final class PromptViewportNativeCanvas: NSView {
  private var snapshot: PromptViewportFieldLayoutSequence.DrawingSnapshot?
  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setAccessibilityElement(true)
    setAccessibilityRole(.staticText)
  }
  required init?(coder: NSCoder) { fatalError("PromptViewportNativeCanvas is created in code") }

  private func retireSnapshotIfWidthChanged(from oldWidth: CGFloat) {
    guard snapshot != nil, abs(bounds.width - oldWidth) >= 0.001 else { return }
    snapshot = nil
    setAccessibilityValue("")
    invalidateIntrinsicContentSize()
    needsDisplay = true
  }
  override func setFrameSize(_ newSize: NSSize) {
    let oldWidth = bounds.width
    super.setFrameSize(newSize)
    retireSnapshotIfWidthChanged(from: oldWidth)
  }
  override func setBoundsSize(_ newSize: NSSize) {
    let oldWidth = bounds.width
    super.setBoundsSize(newSize)
    retireSnapshotIfWidthChanged(from: oldWidth)
  }

  @discardableResult func configure(snapshot next: PromptViewportFieldLayoutSequence.DrawingSnapshot) -> Bool {
    guard next.width.isFinite, next.width > 0,
      abs(bounds.width - next.width) < 0.001,
      next.measuredHeight.isFinite, next.measuredHeight >= 0,
      next.windows.allSatisfy({ $0.layout.size.height <= next.measuredHeight })
    else { return false }
    let oldSize = intrinsicContentSize
    snapshot = next
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
  override func draw(_ dirtyRect: NSRect) {
    for window in snapshot?.windows ?? [] { window.layout.draw(in: dirtyRect) }
  }
}
