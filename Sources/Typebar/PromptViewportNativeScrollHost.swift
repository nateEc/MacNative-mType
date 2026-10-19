import AppKit

@MainActor private final class PromptViewportReportingClipView: NSClipView {
  var didScroll: (() -> Void)?
  private var boundsRevision = 0
  override func setBoundsOrigin(_ newOrigin: NSPoint) {
    let oldOrigin = bounds.origin
    super.setBoundsOrigin(newOrigin)
    if bounds.origin != oldOrigin {
      boundsRevision += 1
      didScroll?()
    }
  }
  override func scroll(to newOrigin: NSPoint) {
    let oldOrigin = bounds.origin
    let oldRevision = boundsRevision
    super.scroll(to: newOrigin)
    if bounds.origin != oldOrigin, boundsRevision == oldRevision { didScroll?() }
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
  private var pendingFieldScroll: Int?
  private var internalScrollDepth = 0
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
    clip.didScroll = { [weak self] in self?.clipScrolled() }
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

  /// Rebuilds the measured prefix from the current input before publishing.
  /// Unsupported ink leaves the old host intact for the complete fallback.
  @discardableResult func replaceVisibleSession(_ session: TypingSession,
    style: PromptRenderStyle) -> Bool {
    guard let sequence else { return false }
    if clip.documentVisibleRect.minY >= 0.001 {
      return replaceRemoteSession(session, style: style, from: sequence)
    }
    guard let next = sequence.replacingSession(session, style: style),
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

  private func replaceRemoteSession(_ session: TypingSession, style: PromptRenderStyle,
    from old: PromptViewportFieldLayoutSequence) -> Bool {
    let visible = clip.documentVisibleRect
    let spans = old.measuredSpans.filter { span in
      guard let ink = span.inkY else { return false }
      return ink.lowerBound <= visible.maxY && ink.upperBound >= visible.minY
    }
    guard let anchor = spans.first ?? old.measuredSpans.last,
      let oldTop = old.measuredTop(forField: anchor.fields.lowerBound),
      let next = old.replacingSession(session, style: style) else { return false }
    let visibleStarts = Set((spans.isEmpty ? [anchor] : spans).map { $0.fields.lowerBound })
    var visibleWindows: [PromptViewportFieldLayoutSequence.Window] = []
    for span in old.measuredSpans {
      guard let window = next.append(fields: span.fields) else { return false }
      if visibleStarts.contains(span.fields.lowerBound) { visibleWindows.append(window) }
    }
    guard let newTop = next.measuredTop(forField: anchor.fields.lowerBound),
      let snapshot = next.drawingSnapshot(windows: visibleWindows) else { return false }
    let newOrigin = max(0, visible.minY + newTop - oldTop)
    stop()
    canvas.frame = .init(x: 0, y: 0, width: next.layoutWidth,
      height: max(1, clip.bounds.height, snapshot.measuredHeight))
    self.sequence = next
    retained = Dictionary(uniqueKeysWithValues: visibleWindows.map { ($0.fields.lowerBound, $0) })
    guard canvas.configure(snapshot: snapshot) else { return false }
    withInternalScroll { clip.scroll(to: .init(x: 0, y: newOrigin)) }
    scrollView.reflectScrolledClipView(clip)
    refreshVisibleWindows()
    requestMoreIfNeeded()
    return true
  }

  func stop() {
    preparation.cancel()
    pendingFieldScroll = nil
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
    pendingFieldScroll = nil
    preparation.cancel()
    let bottom = max(0, canvas.frame.height - clip.bounds.height)
    clip.scroll(to: .init(x: 0, y: bottom))
    scrollView.reflectScrolledClipView(clip)
    visibleRegionChanged()
  }

  func scrollToTop() {
    pendingFieldScroll = nil
    preparation.cancel()
    clip.scroll(to: .zero)
    scrollView.reflectScrolledClipView(clip)
    visibleRegionChanged()
  }

  /// A distant target is reached by bounded sequential measurement; unknown
  /// geometry is never estimated as a complete document height.
  @discardableResult func scrollToField(_ index: Int) -> Bool {
    guard let sequence, index >= 0, index < sequence.fieldCount else { return false }
    if index < sequence.nextField {
      pendingFieldScroll = nil
      preparation.cancel()
      return revealMeasuredField(index, in: sequence)
    }
    pendingFieldScroll = index
    preparation.cancel()
    requestMoreIfNeeded()
    return true
  }

  @discardableResult private func revealMeasuredField(_ index: Int,
    in sequence: PromptViewportFieldLayoutSequence) -> Bool {
    guard let y = sequence.measuredTop(forField: index) else { return false }
    clip.scroll(to: .init(x: 0, y: y))
    scrollView.reflectScrolledClipView(clip)
    visibleRegionChanged()
    return true
  }

  private func visibleRegionChanged() {
    refreshVisibleWindows()
    requestMoreIfNeeded()
  }

  private func clipScrolled() {
    if internalScrollDepth == 0, pendingFieldScroll != nil {
      pendingFieldScroll = nil
      preparation.cancel()
    }
    visibleRegionChanged()
  }

  private func withInternalScroll(_ body: () -> Void) {
    internalScrollDepth += 1
    defer { internalScrollDepth -= 1 }
    body()
  }

  private func requestMoreIfNeeded() {
    guard let sequence, preparationFailure == nil,
      !preparation.isPreparing, sequence.nextField < sequence.fieldCount else { return }
    let visible = clip.documentVisibleRect
    let measured = sequence.contentHeight ?? 0
    guard pendingFieldScroll != nil || measured <= visible.maxY + max(1, visible.height) else { return }
    let target = min(sequence.nextField + batchSize,
      (pendingFieldScroll.map { $0 + 1 } ?? sequence.fieldCount))
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
    if let target = pendingFieldScroll, let sequence, target < sequence.nextField {
      pendingFieldScroll = nil
      _ = revealMeasuredField(target, in: sequence)
    }
  }

  private func resizeDocumentToMeasuredHeight() {
    guard let sequence else { return }
    let height = max(1, clip.bounds.height, sequence.contentHeight ?? 0)
    if canvas.frame.width != sequence.layoutWidth || canvas.frame.height != height {
      withInternalScroll {
        canvas.frame = .init(x: 0, y: 0, width: sequence.layoutWidth, height: height)
      }
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
