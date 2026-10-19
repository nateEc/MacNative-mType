import AppKit

@MainActor private final class PromptViewportReportingClipView: NSClipView {
  var didScroll: (() -> Void)?
  override func setBoundsOrigin(_ newOrigin: NSPoint) {
    super.setBoundsOrigin(newOrigin)
    didScroll?()
  }
}

/// Native, offscreen-verifiable scrolling owner for a fixed viewport sequence.
/// It measures one additional batch only when the visible end approaches the
/// measured prefix, and retains drawing windows around the visible rectangle.
@MainActor final class PromptViewportNativeScrollHost: NSView {
  let canvas = PromptViewportNativeCanvas(frame: .zero)
  let scrollView = NSScrollView(frame: .zero)
  private let clip = PromptViewportReportingClipView(frame: .zero)
  private let preparation = PromptViewportPreparationTask()
  private var sequence: PromptViewportFieldLayoutSequence?
  private var batchSize = 0
  private var retained: [Int: PromptViewportFieldLayoutSequence.Window] = [:]
  private(set) var preparationFailure: Error?
  var isPreparing: Bool { preparation.isPreparing }
  var retainedWindowCount: Int { retained.count }
  var measuredFieldCount: Int { sequence?.nextField ?? 0 }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    scrollView.hasVerticalScroller = true
    scrollView.contentView = clip
    scrollView.documentView = canvas
    scrollView.frame = bounds
    addSubview(scrollView)
    clip.didScroll = { [weak self] in self?.visibleRegionChanged() }
  }
  required init?(coder: NSCoder) { fatalError("PromptViewportNativeScrollHost is created in code") }

  @discardableResult func configure(sequence next: PromptViewportFieldLayoutSequence,
    batchSize: Int) -> Bool {
    guard batchSize > 0, abs(bounds.width - next.layoutWidth) < 0.001 else { return false }
    stop()
    sequence = next
    self.batchSize = batchSize
    canvas.frame = .init(x: 0, y: 0, width: next.layoutWidth,
      height: max(1, clip.bounds.height))
    resizeDocumentToMeasuredHeight()
    refreshVisibleWindows()
    requestMoreIfNeeded()
    return true
  }

  /// Only the top view can be synchronously repainted from a changed input
  /// snapshot. A distant viewport or unsupported ink stays on the old host so
  /// the caller can choose its complete rendering fallback.
  @discardableResult func replaceVisibleSession(_ session: TypingSession,
    style: PromptRenderStyle) -> Bool {
    guard let sequence, clip.documentVisibleRect.minY < 0.001,
      let next = sequence.replacingSession(session, style: style),
      let first = next.append(fields: 0..<min(batchSize, next.fieldCount)),
      let snapshot = next.drawingSnapshot(windows: [first]) else { return false }
    stop()
    self.sequence = next
    retained[first.fields.lowerBound] = first
    canvas.frame = .init(x: 0, y: 0, width: next.layoutWidth,
      height: max(1, clip.bounds.height, snapshot.measuredHeight))
    guard canvas.configure(snapshot: snapshot) else { return false }
    requestMoreIfNeeded()
    return true
  }

  func stop() {
    preparation.cancel()
    sequence = nil
    retained.removeAll()
    preparationFailure = nil
    canvas.clear()
  }

  func configureCaret(_ configuration: PromptCaretNativeView.Configuration) {
    canvas.configureCaret(configuration)
  }

  func presentCaret(at time: TimeInterval) {
    canvas.presentCaret(at: time)
  }

  override func setFrameSize(_ newSize: NSSize) {
    let oldWidth = bounds.width
    super.setFrameSize(newSize)
    scrollView.frame = bounds
    if abs(newSize.width - oldWidth) >= 0.001 {
      stop()
      canvas.frame.size.width = newSize.width
    } else {
      resizeDocumentToMeasuredHeight()
      visibleRegionChanged()
    }
  }

  override func setBoundsSize(_ newSize: NSSize) {
    let oldWidth = bounds.width
    super.setBoundsSize(newSize)
    guard abs(newSize.width - oldWidth) >= 0.001 else { return }
    stop()
    canvas.frame.size.width = newSize.width
    scrollView.frame = bounds
  }

  func scrollToMeasuredEnd() {
    let bottom = max(0, canvas.frame.height - clip.bounds.height)
    clip.scroll(to: .init(x: 0, y: bottom))
    scrollView.reflectScrolledClipView(clip)
    visibleRegionChanged()
  }

  func scrollToTop() {
    clip.scroll(to: .zero)
    scrollView.reflectScrolledClipView(clip)
    visibleRegionChanged()
  }

  private func visibleRegionChanged() {
    refreshVisibleWindows()
    requestMoreIfNeeded()
  }

  private func requestMoreIfNeeded() {
    guard let sequence, preparationFailure == nil,
      !preparation.isPreparing, sequence.nextField < sequence.fieldCount else { return }
    let visible = clip.documentVisibleRect
    let measured = sequence.contentHeight ?? 0
    guard measured <= visible.maxY + max(1, visible.height) else { return }
    let target = sequence.nextField + min(batchSize, sequence.fieldCount - sequence.nextField)
    preparation.start(sequence: sequence, batchSize: batchSize,
      throughFieldCount: target,
      isCurrent: { [weak self] in
        guard let self else { return false }
        return self.sequence === sequence
          && abs(self.bounds.width - sequence.layoutWidth) < 0.001
      }, onBatch: { [weak self] snapshot in
        self?.publish(snapshot)
      }, completion: { [weak self] result in
        guard let self else { return }
        switch result {
        case .success: self.requestMoreIfNeeded()
        case .failure(let error): self.preparationFailure = error
        }
      })
  }

  private func publish(_ snapshot: PromptViewportFieldLayoutSequence.DrawingSnapshot) {
    for window in snapshot.windows { retained[window.fields.lowerBound] = window }
    resizeDocumentToMeasuredHeight()
    refreshVisibleWindows()
  }

  private func resizeDocumentToMeasuredHeight() {
    guard let sequence else { return }
    let height = max(1, clip.bounds.height, sequence.contentHeight ?? 0)
    if canvas.frame.width != sequence.layoutWidth || canvas.frame.height != height {
      canvas.frame = .init(x: 0, y: 0, width: sequence.layoutWidth, height: height)
    }
  }

  private func refreshVisibleWindows() {
    guard let sequence, !sequence.measuredSpans.isEmpty else { return }
    let visible = clip.documentVisibleRect
    let spans = sequence.measuredSpans.filter { span in
      guard let ink = span.inkY else { return false }
      return ink.lowerBound <= visible.maxY && ink.upperBound >= visible.minY
    }
    let selected = spans.isEmpty ? [sequence.measuredSpans.last!] : spans
    var next: [Int: PromptViewportFieldLayoutSequence.Window] = [:]
    for span in selected {
      if let window = retained[span.fields.lowerBound] ?? sequence.revisit(fields: span.fields) {
        next[span.fields.lowerBound] = window
      }
    }
    guard !next.isEmpty,
      let snapshot = sequence.drawingSnapshot(windows: next.values.sorted {
        $0.fields.lowerBound < $1.fields.lowerBound
      }), canvas.configure(snapshot: snapshot) else { return }
    retained = next
  }
}
