import AppKit
import SwiftUI

struct PromptFieldPracticePrompt: View {
  private let renderingSnapshot: PromptFieldRenderingSnapshot
  let font: NSFont
  let lineSpacing: CGFloat
  let rightToLeft: Bool
  let joinsLetters: Bool
  let carets: PromptCaretNativeView.Configuration
  var lineScroll: PromptLineScrollContext? = nil
  var viewportLineCount: Int? = nil
  var preparedLayout: PromptFieldTextLayout? = nil
  var accessibilityText: String? = nil
  var onMeasuredWidth: ((CGFloat) -> Void)? = nil
  @State private var viewportHeight: CGFloat?

  init(rendering: PromptRendering, font: NSFont, lineSpacing: CGFloat,
    rightToLeft: Bool, joinsLetters: Bool, carets: PromptCaretNativeView.Configuration,
    lineScroll: PromptLineScrollContext? = nil, viewportLineCount: Int? = nil,
    preparedLayout: PromptFieldTextLayout? = nil,
    accessibilityText: String? = nil,
    onMeasuredWidth: ((CGFloat) -> Void)? = nil) {
    renderingSnapshot = PromptFieldRenderingSnapshot(rendering)
    self.font = font; self.lineSpacing = lineSpacing
    self.rightToLeft = rightToLeft; self.joinsLetters = joinsLetters
    self.carets = carets; self.lineScroll = lineScroll
    self.viewportLineCount = viewportLineCount; self.preparedLayout = preparedLayout
    self.accessibilityText = accessibilityText
    self.onMeasuredWidth = onMeasuredWidth
  }

  var body: some View {
    PromptFieldBridge(renderingSnapshot: renderingSnapshot, font: font, lineSpacing: lineSpacing,
      rightToLeft: rightToLeft, joinsLetters: joinsLetters, carets: carets, lineScroll: lineScroll,
      viewportLineCount: viewportLineCount, preparedLayout: preparedLayout,
      accessibilityText: accessibilityText,
      onMeasuredWidth: onMeasuredWidth, onViewportHeight: { viewportHeight = $0 })
      .preference(key: PracticeViewportHeightKey.self, value: viewportHeight)
  }
}

/// The immutable snapshot is new for each presentation. SwiftUI can compare the
/// reference without recursively comparing every field run and attributed cell.
private final class PromptFieldRenderingSnapshot {
  let value: PromptRendering
  init(_ value: PromptRendering) { self.value = value }
}

private struct PromptFieldBridge: NSViewRepresentable {
  let renderingSnapshot: PromptFieldRenderingSnapshot
  let font: NSFont
  let lineSpacing: CGFloat
  let rightToLeft: Bool
  let joinsLetters: Bool
  let carets: PromptCaretNativeView.Configuration
  let lineScroll: PromptLineScrollContext?
  let viewportLineCount: Int?
  let preparedLayout: PromptFieldTextLayout?
  let accessibilityText: String?
  let onMeasuredWidth: ((CGFloat) -> Void)?
  let onViewportHeight: (CGFloat?) -> Void
  func makeNSView(context: Context) -> PromptFieldNativeView { PromptFieldNativeView() }
  func updateNSView(_ view: PromptFieldNativeView, context: Context) {
    view.configure(rendering: renderingSnapshot.value, font: font, lineSpacing: lineSpacing,
      rightToLeft: rightToLeft, joinsLetters: joinsLetters, carets: carets, lineScroll: lineScroll,
      viewportLineCount: viewportLineCount, preparedLayout: preparedLayout,
      accessibilityText: accessibilityText,
      onMeasuredWidth: onMeasuredWidth, onViewportHeight: onViewportHeight)
  }
  func sizeThatFits(_ proposal: ProposedViewSize, nsView: PromptFieldNativeView, context: Context) -> CGSize? {
    nsView.proposalSize(width: max(1, proposal.width ?? nsView.bounds.width))
  }
  static func dismantleNSView(_ view: PromptFieldNativeView, coordinator: ()) { view.stop() }
}

/// One cached field/slot layout supplies drawing, both carets, row following
/// and viewport metrics. The owner adds no timer and never opens a window.
final class PromptFieldNativeView: NSView {
  private let caret = PromptCaretNativeView()
  private let follower = PromptAutoScrollView()
  private var rendering = PromptRendering(text: AttributedString(), glyphCharacterOffsets: [:])
  private var font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
  private var lineSpacing: CGFloat = 12
  private var rightToLeft = false, joinsLetters = false
  private var configuration: PromptCaretNativeView.Configuration?
  private var lineScroll: PromptLineScrollContext?
  private var model: PromptFieldTextLayout?
  private var preparedLayout: PromptFieldTextLayout?
  private var invalidatesModel = true
  private var modelWidth: CGFloat = 0
  private(set) var geometryRevision: UInt64 = 0
  private(set) var usedPreparedLayout = false
  private var viewportLineCount: Int?
  private var onViewportHeight: ((CGFloat?) -> Void)?
  private var onMeasuredWidth: ((CGFloat) -> Void)?
  private var accessibilityTextOverride: String?
  private var reportedWidth: CGFloat?
  private var reportedHeight: CGFloat?
  private var notificationRevision: UInt64 = 0
  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    addSubview(follower); addSubview(caret)
    setAccessibilityElement(true); setAccessibilityRole(.staticText)
  }
  required init?(coder: NSCoder) { fatalError("PromptFieldNativeView is created in code") }

  func configure(rendering: PromptRendering, font: NSFont, lineSpacing: CGFloat = 12,
    rightToLeft: Bool = false, joinsLetters: Bool = false, carets: PromptCaretNativeView.Configuration,
    lineScroll: PromptLineScrollContext? = nil, viewportLineCount: Int? = nil,
    preparedLayout: PromptFieldTextLayout? = nil,
    accessibilityText: String? = nil,
    onMeasuredWidth: ((CGFloat) -> Void)? = nil,
    onViewportHeight: ((CGFloat?) -> Void)? = nil) {
    let previousSize = intrinsicContentSize
    let changed = self.font != font || self.lineSpacing != lineSpacing
      || self.rightToLeft != rightToLeft || self.joinsLetters != joinsLetters
      || self.rendering.compositionTextMap?.fieldRuns != rendering.compositionTextMap?.fieldRuns
      || self.rendering.compositionTextMap?.canonicalAliases != rendering.compositionTextMap?.canonicalAliases
      || self.rendering.compositionTextMap?.caret != rendering.compositionTextMap?.caret
      || self.rendering.compositionTextMap?.markedInputRanges != rendering.compositionTextMap?.markedInputRanges
      || self.rendering.compositionTextMap?.markedCellIDs != rendering.compositionTextMap?.markedCellIDs
      || self.rendering.compositionTextMap?.compositionStyle != rendering.compositionTextMap?.compositionStyle
    if changed || preparedLayout != nil && model !== preparedLayout { invalidatesModel = true }
    self.rendering = rendering; self.font = font; self.lineSpacing = lineSpacing
    self.rightToLeft = rightToLeft; self.joinsLetters = joinsLetters
    self.configuration = carets; self.lineScroll = lineScroll
    self.preparedLayout = preparedLayout; self.onMeasuredWidth = onMeasuredWidth
    accessibilityTextOverride = accessibilityText
    self.viewportLineCount = viewportLineCount; self.onViewportHeight = onViewportHeight
    notificationRevision &+= 1
    _ = measure(width: max(1, bounds.width))
    deliverHeight()
    configureControllers()
    setAccessibilityValue(accessibilityTextOverride ?? String(rendering.text.characters))
    needsDisplay = true
    if intrinsicContentSize != previousSize {
      invalidateIntrinsicContentSize()
      needsLayout = true
    }
  }

  @discardableResult func measure(width: CGFloat) -> CGSize {
    if width > 1, width.isFinite, onMeasuredWidth != nil, reportedWidth != width {
      DispatchQueue.main.async { [weak self] in
        guard let self, self.onMeasuredWidth != nil, self.reportedWidth != width else { return }
        self.reportedWidth = width; self.onMeasuredWidth?(width)
      }
    }
    guard let map = rendering.compositionTextMap else {
      model = nil; return .init(width: width, height: 0)
    }
    if model == nil || invalidatesModel || modelWidth != width {
      modelWidth = width
      if let preparedLayout, preparedLayout.matchesMetrics(width: width, font: font,
        lineSpacing: lineSpacing, rightToLeft: rightToLeft, joinsLetters: joinsLetters) {
        model = preparedLayout
        usedPreparedLayout = true
      } else {
        model = PromptFieldTextLayout(map: map, width: width, font: font, lineSpacing: lineSpacing,
          rightToLeft: rightToLeft, joinsLetters: joinsLetters, reusing: model)
        usedPreparedLayout = false
      }
      invalidatesModel = false
      geometryRevision &+= 1
      caret.invalidateGeometry()
      deliverHeight()
    }
    return model?.size ?? .zero
  }

  /// SwiftUI may ask for several candidate widths after the view has already
  /// been laid out. A proposal measures its own snapshot; only the actual
  /// bounds may replace the model used by draw, carets and scrolling.
  func proposalSize(width: CGFloat) -> CGSize {
    let width = width.isFinite ? max(1, width) : 1
    guard let map = rendering.compositionTextMap else { return .init(width: width, height: 0) }
    if !invalidatesModel, modelWidth == width, let model { return model.size }
    if let preparedLayout, preparedLayout.matchesMetrics(width: width, font: font,
      lineSpacing: lineSpacing, rightToLeft: rightToLeft, joinsLetters: joinsLetters) {
      return preparedLayout.size
    }
    return PromptFieldTextLayout(map: map, width: width, font: font, lineSpacing: lineSpacing,
      rightToLeft: rightToLeft, joinsLetters: joinsLetters, reusing: model).size
  }

  private func refreshRendering() -> PromptRendering {
    if let next = configuration?.latestRendering?() {
      if rendering.compositionTextMap?.fieldRuns != next.compositionTextMap?.fieldRuns
        || rendering.compositionTextMap?.canonicalAliases != next.compositionTextMap?.canonicalAliases
        || rendering.compositionTextMap?.caret != next.compositionTextMap?.caret
        || rendering.compositionTextMap?.markedInputRanges != next.compositionTextMap?.markedInputRanges
        || rendering.compositionTextMap?.markedCellIDs != next.compositionTextMap?.markedCellIDs
        || rendering.compositionTextMap?.compositionStyle != next.compositionTextMap?.compositionStyle {
        let previousSize = intrinsicContentSize
        rendering = next; invalidatesModel = true; notificationRevision &+= 1
        _ = measure(width: max(1, bounds.width))
        updateFollower(); needsDisplay = true
        if intrinsicContentSize != previousSize {
          invalidateIntrinsicContentSize()
          needsLayout = true
        }
        setAccessibilityValue(accessibilityTextOverride ?? String(next.text.characters))
      }
    }
    return rendering
  }
  private func configureControllers() {
    caret.frame = bounds; follower.frame = bounds
    guard var config = configuration else { return }
    config.geometryRevision = geometryRevision
    config.firstGlyphID = rendering.compositionTextMap?.canonicalAliases.keys.min() ?? 0
    config.glyphRect = { [weak self] id in self?.model?.canonicalRect(id, after: false) }
    config.latestRendering = { [weak self] in self?.refreshRendering() ?? .init(text: AttributedString(), glyphCharacterOffsets: [:]) }
    let perGlyph = config.fieldDirectionPerGlyph
    config.fieldMainRect = { [weak self] style in self?.model?.mainRect(style: style, perGlyph: perGlyph) }
    config.markedCellRect = { [weak self] id in self?.model?.cellFrames[id] }
    config.fieldMainDirection = { [weak self] in self?.model?.mainDirection(perGlyph: perGlyph) ?? false }
    config.fieldPaceRect = { [weak self] id, after in self?.model?.canonicalRect(id, after: after) }
    let fallbackDirection = config.rightToLeft
    config.fieldPaceDirection = { [weak self] id, after in
      self?.model?.canonicalDirection(id, after: after, perGlyph: perGlyph) ?? fallbackDirection
    }
    caret.update(config); updateFollower()
  }
  private func updateFollower() {
    follower.update(text: rendering.text, characterOffset: nil, font: font, lineSpacing: lineSpacing,
      isRightToLeft: rightToLeft, lineScroll: lineScroll,
      customGeometry: .init(revision: geometryRevision, caretGlyphID: rendering.compositionTextMap?.caret?.cellID,
        measure: { [weak self] active, previous, caret, words in
          self?.model?.lineGeometry.measure(active: active, previous: previous, caret: caret, words: words)
        }))
  }
  private func deliverHeight() {
    guard let count = viewportLineCount, let model, let notify = onViewportHeight,
      let height = PromptViewportLayout.height(forRowHeights: model.lineGeometry.rowHeights, lineCount: count),
      height != reportedHeight else { return }
    let revision = notificationRevision
    DispatchQueue.main.async { [weak self] in
      guard let self, self.configuration != nil, self.notificationRevision == revision,
        self.reportedHeight != height else { return }
      self.reportedHeight = height; notify(height)
    }
  }

  func measuredRect(for id: Int) -> CGRect? { model?.cellFrames[id] }
  func measuredMainCaretRect() -> CGRect? { model?.mainRect(style: .bar) }
  func renderedCellText(for id: Int) -> AttributedString? { rendering.compositionTextMap?.cellTexts[id] }
  func usesLayout(_ layout: PromptFieldTextLayout) -> Bool { model === layout }
  var reusedGeometryFromPrevious: Bool { model?.reusedGeometryFromPrevious ?? false }
  func measuredFieldRect(for id: Int) -> CGRect? { model?.fieldFrames[id] }
  func present(at time: TimeInterval) { caret.present(at: time) }
  override var intrinsicContentSize: NSSize { model?.size ?? .init(width: NSView.noIntrinsicMetric, height: 0) }
  override func layout() {
    super.layout()
    _ = measure(width: max(1, bounds.width)); configureControllers()
  }
  override func draw(_ dirtyRect: NSRect) { model?.draw(in: dirtyRect) }
  override func viewWillMove(toSuperview newSuperview: NSView?) {
    if newSuperview == nil { stop() }
    super.viewWillMove(toSuperview: newSuperview)
  }
  func stop() {
    notificationRevision &+= 1; configuration = nil; onViewportHeight = nil
    onMeasuredWidth = nil; preparedLayout = nil; reportedWidth = nil
    accessibilityTextOverride = nil
    caret.stop(); follower.cancelCaretMotion(); follower.stopLineScroll()
    lineScroll = nil
    follower.update(text: AttributedString(), characterOffset: nil, font: font,
      lineSpacing: lineSpacing, isRightToLeft: rightToLeft)
  }
}
