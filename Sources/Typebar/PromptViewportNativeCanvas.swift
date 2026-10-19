import AppKit

/// A native drawing surface for measured, globally positioned field windows.
/// This is not yet the production scroll/caret host: incomplete snapshots
/// expose only measured prefix height, never a guessed full-page extent.
@MainActor final class PromptViewportNativeCanvas: NSView {
  private var snapshot: PromptViewportFieldLayoutSequence.DrawingSnapshot?
  private let caret = PromptCaretNativeView(frame: .zero)
  private var caretConfiguration: PromptCaretNativeView.Configuration?
  private var geometryRevision: UInt64 = 0
  private var accessibilitySource: NSString?
  private var accessibilitySelection = NSRange(location: NSNotFound, length: 0)
  var accessibilityRectProvider: ((NSRange) -> CGRect?)?
  var accessibilityLineProvider: ((Int) -> Int?)?
  var accessibilityLineRangeProvider: ((Int) -> NSRange?)?
  var accessibilitySelectionHandler: ((NSRange) -> Bool)?
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
    accessibilitySource = nil
    accessibilitySelection = .init(location: NSNotFound, length: 0)
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
    let targetChanged = snapshot?.promptTargetID != next.promptTargetID
    if targetChanged { accessibilitySource = next.accessibilityText as NSString }
    if targetChanged || snapshot?.attemptID != next.attemptID {
      accessibilitySelection = .init(location: NSNotFound, length: 0)
    }
    snapshot = next
    geometryRevision &+= 1
    applyCaretConfiguration()
    setAccessibilityValue(next.accessibilityText)
    needsDisplay = true
    if intrinsicContentSize != oldSize { invalidateIntrinsicContentSize() }
    if targetChanged { NSAccessibility.post(element: self, notification: .valueChanged) }
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
    if let snapshot, snapshot.attemptID != configuration.attemptID { return }
    caretConfiguration = configuration
    applyCaretConfiguration()
  }
  func presentCaret(at time: TimeInterval) {
    guard snapshot != nil, caretConfiguration != nil else { return }
    caret.present(at: time)
  }
  private func applyCaretConfiguration() {
    guard let snapshot, var configuration = caretConfiguration else { return }
    guard snapshot.attemptID == configuration.attemptID else {
      caretConfiguration = nil
      caret.stop()
      caret.isHidden = true
      return
    }
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

  private func validAccessibilityRange(_ range: NSRange) -> Bool {
    guard let accessibilitySource else { return false }
    return range.location >= 0 && range.location <= accessibilitySource.length
      && range.length >= 0 && range.length <= accessibilitySource.length - range.location
  }

  override func accessibilityNumberOfCharacters() -> Int { accessibilitySource?.length ?? 0 }
  override func accessibilityString(for range: NSRange) -> String? {
    guard validAccessibilityRange(range) else { return nil }
    return accessibilitySource?.substring(with: range)
  }
  override func accessibilityAttributedString(for range: NSRange) -> NSAttributedString? {
    accessibilityString(for: range).map { NSAttributedString(string: $0) }
  }
  override func accessibilityRange(for index: Int) -> NSRange {
    guard index >= 0, index < accessibilityNumberOfCharacters() else {
      return .init(location: NSNotFound, length: 0)
    }
    return .init(location: index, length: 1)
  }
  override func accessibilityFrame(for range: NSRange) -> NSRect {
    guard validAccessibilityRange(range), let window,
      let rect = accessibilityRectProvider?(range) else { return .zero }
    return window.convertToScreen(convert(rect, to: nil))
  }
  override func accessibilityLine(for index: Int) -> Int {
    guard index >= 0, index < accessibilityNumberOfCharacters() else { return NSNotFound }
    return accessibilityLineProvider?(index) ?? NSNotFound
  }
  override func accessibilityRange(forLine line: Int) -> NSRange {
    guard line >= 0, line < accessibilityNumberOfCharacters() else {
      return .init(location: NSNotFound, length: 0)
    }
    return accessibilityLineRangeProvider?(line) ?? .init(location: NSNotFound, length: 0)
  }
  override func accessibilityVisibleCharacterRange() -> NSRange {
    let visible = visibleRect
    let ids = snapshot?.windows.flatMap { window in
      window.layout.cellFrames.compactMap { visible.intersects($0.value) ? $0.key : nil }
    } ?? []
    guard let lower = ids.min(), let upper = ids.max() else { return .init(location: NSNotFound, length: 0) }
    return .init(location: lower, length: upper + 1 - lower)
  }
  override func accessibilityRange(for point: NSPoint) -> NSRange {
    guard let window else { return .init(location: NSNotFound, length: 0) }
    let local = convert(window.convertFromScreen(.init(origin: point, size: .zero)).origin, from: nil)
    guard visibleRect.contains(local), let id = snapshot?.windows.lazy.compactMap({ window in
      window.layout.cellFrames.first(where: { $0.value.contains(local) })?.key
    }).first else { return .init(location: NSNotFound, length: 0) }
    return .init(location: id, length: 1)
  }
  override func accessibilitySelectedTextRange() -> NSRange { accessibilitySelection }
  override func accessibilitySelectedText() -> String? { accessibilityString(for: accessibilitySelection) }
  override func setAccessibilitySelectedTextRange(_ range: NSRange) {
    guard validAccessibilityRange(range), accessibilitySelectionHandler?(range) == true else { return }
    restoreAccessibilitySelection(range)
  }
  /// Reflow preserves selection independently of the user's reading position.
  /// Unlike an accessibility selection action, this must not navigate.
  func restoreAccessibilitySelection(_ range: NSRange) {
    guard validAccessibilityRange(range) else { return }
    accessibilitySelection = range
    NSAccessibility.post(element: self, notification: .selectedTextChanged)
  }
  override func draw(_ dirtyRect: NSRect) {
    for window in snapshot?.windows ?? [] { window.layout.draw(in: dirtyRect) }
  }
}
