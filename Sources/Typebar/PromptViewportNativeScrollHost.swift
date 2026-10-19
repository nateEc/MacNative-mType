import AppKit

@MainActor private final class PromptViewportReportingClipView: NSClipView {
  var didScroll: (() -> Void)?
  var didResize: (() -> Void)?
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
  override func setFrameSize(_ newSize: NSSize) {
    let oldWidth = bounds.width
    super.setFrameSize(newSize)
    if abs(bounds.width - oldWidth) >= 0.001 { didResize?() }
  }
  override func setBoundsSize(_ newSize: NSSize) {
    let oldWidth = bounds.width
    super.setBoundsSize(newSize)
    if abs(bounds.width - oldWidth) >= 0.001 { didResize?() }
  }
}

/// Native, offscreen-verifiable scrolling owner for a fixed viewport sequence.
/// It measures one additional batch only when the visible end approaches the
/// measured prefix, and retains drawing windows around the visible rectangle.
@MainActor final class PromptViewportNativeScrollHost: NSView {
  struct ReadingPosition {
    let attemptID: UUID
    let promptTargetID: UUID
    let character: Int
    let rowFraction: CGFloat
    let selection: NSRange
  }
  let canvas = PromptViewportNativeCanvas(frame: .zero)
  let scrollView = NSScrollView(frame: .zero)
  private let clip = PromptViewportReportingClipView(frame: .zero)
  private let preparation = PromptViewportPreparationTask()
  private var sequence: PromptViewportFieldLayoutSequence?
  private var batchSize = 0
  private var retained: [Int: PromptViewportFieldLayoutSequence.Window] = [:]
  private var pendingFieldScroll: Int?
  private var internalScrollDepth = 0
  private var usesPageScrolling = false
  private weak var observedPageClip: NSClipView?
  private weak var observedPageDocument: NSView?
  private(set) var preparationFailure: Error?
  var onPreparationFailure: ((Error) -> Void)?
  var onLayoutWidthChange: (() -> Void)?
  var onLayoutWillRetire: (() -> Void)?
  var onMeasuredHeightChange: ((CGFloat) -> Void)?
  var layoutWidth: CGFloat { clip.bounds.width }
  var visibleDocumentRect: CGRect { usesPageScrolling ? canvas.visibleRect : clip.documentVisibleRect }
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
    clip.didResize = { [weak self] in self?.clipWidthChanged() }
    canvas.accessibilityRectProvider = { [weak self] in self?.accessibilityTextRect(for: $0) }
    canvas.accessibilityLineProvider = { [weak self] in self?.accessibilityTextLine(for: $0) }
    canvas.accessibilityLineRangeProvider = { [weak self] in self?.accessibilityTextRange(forLine: $0) }
    canvas.accessibilitySelectionHandler = { [weak self] in self?.selectAccessibilityText($0) ?? false }
  }
  required init?(coder: NSCoder) { fatalError("PromptViewportNativeScrollHost is created in code") }

  convenience init(pageScrolling: Bool) {
    self.init(frame: .zero)
    usesPageScrolling = pageScrolling
    scrollView.hasVerticalScroller = !pageScrolling
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    observePageClip()
  }

  override func viewDidMoveToSuperview() {
    super.viewDidMoveToSuperview()
    observePageClip()
  }

  private func observePageClip() {
    let pageClip = usesPageScrolling ? enclosingScrollView?.contentView : nil
    let pageDocument = usesPageScrolling ? enclosingScrollView?.documentView : nil
    guard observedPageClip !== pageClip || observedPageDocument !== pageDocument else { return }
    if let observedPageClip {
      NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: observedPageClip)
    }
    if let observedPageDocument {
      NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: observedPageDocument)
    }
    observedPageClip = pageClip
    observedPageDocument = pageDocument
    if let pageClip {
      pageClip.postsBoundsChangedNotifications = true
      NotificationCenter.default.addObserver(self, selector: #selector(pageClipChanged),
        name: NSView.boundsDidChangeNotification, object: pageClip)
    }
    if let pageDocument {
      pageDocument.postsFrameChangedNotifications = true
      NotificationCenter.default.addObserver(self, selector: #selector(pageDocumentChanged),
        name: NSView.frameDidChangeNotification, object: pageDocument)
    }
    visibleRegionChanged()
  }

  func refreshPageVisibility() {
    guard usesPageScrolling else { return }
    observePageClip()
    visibleRegionChanged()
  }

  @objc private func pageDocumentChanged() { visibleRegionChanged() }

  @objc private func pageClipChanged() {
    if internalScrollDepth == 0, pendingFieldScroll != nil {
      pendingFieldScroll = nil
      preparation.cancel()
    }
    visibleRegionChanged()
  }

  private func scrollDocument(to y: CGFloat) {
    if usesPageScrolling, let page = enclosingScrollView, let document = page.documentView {
      let point = canvas.convert(.init(x: 0, y: y), to: document)
      var bounds = page.contentView.bounds
      bounds.origin.y = point.y
      page.contentView.scroll(to: page.contentView.constrainBoundsRect(bounds).origin)
      page.reflectScrolledClipView(page.contentView)
    } else {
      clip.scroll(to: .init(x: 0, y: y))
      scrollView.reflectScrolledClipView(clip)
    }
  }

  @discardableResult func configure(sequence next: PromptViewportFieldLayoutSequence,
    batchSize: Int) -> Bool {
    guard batchSize > 0, abs(layoutWidth - next.layoutWidth) < 0.001 else { return false }
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
    if visibleDocumentRect.minY >= 0.001 {
      return replaceRemoteSession(session, style: style, from: sequence)
    }
    guard let next = sequence.replacingSession(session, style: style),
      let first = next.append(fields: 0..<min(batchSize, next.fieldCount)),
      let snapshot = next.drawingSnapshot(windows: [first]) else { return false }
    cancelPreparation()
    self.sequence = next
    retained = [first.fields.lowerBound: first]
    canvas.frame = .init(x: 0, y: 0, width: next.layoutWidth,
      height: max(1, clip.bounds.height, snapshot.measuredHeight))
    guard canvas.configure(snapshot: snapshot) else { return false }
    requestMoreIfNeeded()
    return true
  }

  private func replaceRemoteSession(_ session: TypingSession, style: PromptRenderStyle,
    from old: PromptViewportFieldLayoutSequence) -> Bool {
    let visible = visibleDocumentRect
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
    cancelPreparation()
    self.sequence = next
    retained = Dictionary(uniqueKeysWithValues: visibleWindows.map { ($0.fields.lowerBound, $0) })
    canvas.frame = .init(x: 0, y: 0, width: next.layoutWidth,
      height: max(1, clip.bounds.height, snapshot.measuredHeight))
    guard canvas.configure(snapshot: snapshot) else { return false }
    resizeDocumentToMeasuredHeight()
    withInternalScroll { scrollDocument(to: newOrigin) }
    refreshVisibleWindows()
    requestMoreIfNeeded()
    return true
  }

  private func cancelPreparation() {
    preparation.cancel()
    pendingFieldScroll = nil
    preparationFailure = nil
  }

  func stop() {
    cancelPreparation()
    sequence = nil
    retained.removeAll()
    canvas.clear()
  }

  func configureCaret(_ configuration: PromptCaretNativeView.Configuration) {
    canvas.configureCaret(configuration)
  }

  func presentCaret(at time: TimeInterval) {
    canvas.presentCaret(at: time)
  }

  func captureReadingPosition() -> ReadingPosition? {
    let character = canvas.accessibilityVisibleCharacterRange().location
    guard let sequence, character != NSNotFound,
      let rect = canvas.measuredRect(for: character), rect.height > 0 else { return nil }
    return .init(attemptID: sequence.attemptID, promptTargetID: sequence.promptTargetID,
      character: character,
      rowFraction: max(0, min(1, (visibleDocumentRect.minY - rect.minY) / rect.height)),
      selection: canvas.accessibilitySelectedTextRange())
  }

  /// Reuses exact prefix measurement, never an estimated remote y coordinate.
  /// This is synchronous like AX geometry queries and is not a latency claim.
  @discardableResult func restoreReadingPosition(_ position: ReadingPosition) -> Bool {
    guard let sequence, sequence.attemptID == position.attemptID,
      sequence.promptTargetID == position.promptTargetID,
      let rect = accessibilityTextRect(for: .init(location: position.character, length: 1)) else { return false }
    withInternalScroll {
      scrollDocument(to: rect.minY + position.rowFraction * rect.height)
    }
    scrollView.reflectScrolledClipView(clip)
    visibleRegionChanged()
    canvas.restoreAccessibilitySelection(position.selection)
    return true
  }

  override func setFrameSize(_ newSize: NSSize) {
    let oldWidth = bounds.width
    super.setFrameSize(newSize)
    scrollView.frame = bounds
    if abs(newSize.width - oldWidth) >= 0.001 {
      if sequence != nil { onLayoutWillRetire?() }
      stop()
      canvas.frame.size.width = layoutWidth
    } else {
      resizeDocumentToMeasuredHeight()
      visibleRegionChanged()
    }
  }

  override func setBoundsSize(_ newSize: NSSize) {
    let oldWidth = bounds.width
    super.setBoundsSize(newSize)
    guard abs(newSize.width - oldWidth) >= 0.001 else { return }
    if sequence != nil { onLayoutWillRetire?() }
    stop()
    scrollView.frame = bounds
    canvas.frame.size.width = layoutWidth
  }

  func scrollToMeasuredEnd() {
    pendingFieldScroll = nil
    preparation.cancel()
    let bottom = max(0, canvas.frame.height - visibleDocumentRect.height)
    scrollDocument(to: bottom)
    scrollView.reflectScrolledClipView(clip)
    visibleRegionChanged()
  }

  func scrollToTop() {
    pendingFieldScroll = nil
    preparation.cancel()
    scrollDocument(to: 0)
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
    scrollDocument(to: y)
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

  private func clipWidthChanged() {
    guard let sequence, abs(sequence.layoutWidth - layoutWidth) >= 0.001 else { return }
    onLayoutWillRetire?()
    stop()
    canvas.frame.size.width = layoutWidth
    onLayoutWidthChange?()
  }

  private func withInternalScroll(_ body: () -> Void) {
    internalScrollDepth += 1
    defer { internalScrollDepth -= 1 }
    body()
  }

  /// AX text queries are synchronous. Measure only the required prefix, then
  /// reconstruct requested windows from checkpoints; do not scroll on reads.
  private func accessibilitySequence(preparedUntil ready: (PromptViewportFieldLayoutSequence) -> Bool)
    -> PromptViewportFieldLayoutSequence? {
    guard let sequence else { return nil }
    if ready(sequence) { return sequence }
    preparation.cancel()
    defer {
      resizeDocumentToMeasuredHeight()
      refreshVisibleWindows()
      requestMoreIfNeeded()
    }
    while !ready(sequence) {
      guard sequence.nextField < sequence.fieldCount, preparationFailure == nil else { return nil }
      let start = sequence.nextField
      let end = start + min(batchSize, sequence.fieldCount - start)
      guard sequence.append(fields: start..<end) != nil else {
        preparationFailure = PromptViewportPreparationTask.Failure.unsupportedWindow
        return nil
      }
    }
    return sequence
  }

  private func accessibilityTextRect(for range: NSRange) -> CGRect? {
    guard let current = sequence, range.location >= 0, range.location <= current.targetUTF16Count,
      range.length >= 0, range.length <= current.targetUTF16Count - range.location,
      current.targetUTF16Count > 0 else { return nil }
    let lastOffset = range.length == 0 ? min(range.location, current.targetUTF16Count - 1) : NSMaxRange(range) - 1
    guard let field = current.fieldIndex(containingUTF16: lastOffset),
      let measured = accessibilitySequence(preparedUntil: { $0.nextField > field }) else { return nil }
    return measured.measuredTextFrame(for: range)
  }

  private func accessibilityTextLine(for index: Int) -> Int? {
    guard let field = sequence?.fieldIndex(containingUTF16: index),
      let measured = accessibilitySequence(preparedUntil: { $0.nextField > field }) else { return nil }
    return measured.measuredTextLines.firstIndex { NSLocationInRange(index, $0.range) }
  }

  private func accessibilityTextRange(forLine line: Int) -> NSRange? {
    guard line >= 0, let measured = accessibilitySequence(preparedUntil: {
      $0.measuredTextLines.count > line + 1 || $0.nextField == $0.fieldCount
    }), measured.measuredTextLines.indices.contains(line) else { return nil }
    return measured.measuredTextLines[line].range
  }

  private func selectAccessibilityText(_ range: NSRange) -> Bool {
    guard let rect = accessibilityTextRect(for: range) else { return false }
    pendingFieldScroll = nil
    preparation.cancel()
    scrollDocument(to: rect.minY)
    scrollView.reflectScrolledClipView(clip)
    visibleRegionChanged()
    NSAccessibility.post(element: canvas, notification: .layoutChanged)
    return true
  }

  private func requestMoreIfNeeded() {
    guard let sequence, preparationFailure == nil,
      !preparation.isPreparing, sequence.nextField < sequence.fieldCount else { return }
    let visible = visibleDocumentRect
    let measured = sequence.contentHeight ?? 0
    guard usesPageScrolling || pendingFieldScroll != nil || measured <= visible.maxY + max(1, visible.height) else { return }
    let target = min(sequence.nextField + batchSize,
      (pendingFieldScroll.map { $0 + 1 } ?? sequence.fieldCount))
    preparation.start(sequence: sequence, batchSize: batchSize,
      throughFieldCount: target,
      isCurrent: { [weak self] in
        guard let self else { return false }
        return self.sequence === sequence
          && abs(self.layoutWidth - sequence.layoutWidth) < 0.001
      }, onBatch: { [weak self] snapshot in
        self?.publish(snapshot)
      }, completion: { [weak self] result in
        guard let self else { return }
        switch result {
        case .success: self.requestMoreIfNeeded()
        case .failure(let error):
          self.preparationFailure = error
          self.onPreparationFailure?(error)
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
    let height = max(1, usesPageScrolling ? 0 : clip.bounds.height, sequence.contentHeight ?? 0)
    if canvas.frame.width != sequence.layoutWidth || canvas.frame.height != height {
      withInternalScroll {
        canvas.frame = .init(x: 0, y: 0, width: sequence.layoutWidth, height: height)
      }
    }
    if !usesPageScrolling || sequence.nextField == sequence.fieldCount { onMeasuredHeightChange?(height) }
  }

  private func refreshVisibleWindows() {
    guard let sequence, !sequence.measuredSpans.isEmpty else { return }
    let visible = visibleDocumentRect
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
