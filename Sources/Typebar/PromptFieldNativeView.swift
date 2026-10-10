import AppKit
import SwiftUI

struct PromptFieldPracticePrompt: View {
  let rendering: PromptRendering
  let font: NSFont
  let lineSpacing: CGFloat
  let rightToLeft: Bool
  let joinsLetters: Bool
  let carets: PromptCaretNativeView.Configuration
  var lineScroll: PromptLineScrollContext? = nil
  var viewportLineCount: Int? = nil
  @State private var viewportHeight: CGFloat?

  var body: some View {
    PromptFieldBridge(rendering: rendering, font: font, lineSpacing: lineSpacing,
      rightToLeft: rightToLeft, joinsLetters: joinsLetters, carets: carets, lineScroll: lineScroll,
      viewportLineCount: viewportLineCount, onViewportHeight: { viewportHeight = $0 })
      .preference(key: PracticeViewportHeightKey.self, value: viewportHeight)
  }
}

private struct PromptFieldBridge: NSViewRepresentable {
  let rendering: PromptRendering
  let font: NSFont
  let lineSpacing: CGFloat
  let rightToLeft: Bool
  let joinsLetters: Bool
  let carets: PromptCaretNativeView.Configuration
  let lineScroll: PromptLineScrollContext?
  let viewportLineCount: Int?
  let onViewportHeight: (CGFloat?) -> Void
  func makeNSView(context: Context) -> PromptFieldNativeView { PromptFieldNativeView() }
  func updateNSView(_ view: PromptFieldNativeView, context: Context) {
    view.configure(rendering: rendering, font: font, lineSpacing: lineSpacing,
      rightToLeft: rightToLeft, joinsLetters: joinsLetters, carets: carets, lineScroll: lineScroll,
      viewportLineCount: viewportLineCount, onViewportHeight: onViewportHeight)
  }
  func sizeThatFits(_ proposal: ProposedViewSize, nsView: PromptFieldNativeView, context: Context) -> CGSize? {
    nsView.measure(width: max(1, proposal.width ?? nsView.bounds.width))
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
  private var invalidatesModel = true
  private var modelWidth: CGFloat = 0
  private(set) var geometryRevision: UInt64 = 0
  private var viewportLineCount: Int?
  private var onViewportHeight: ((CGFloat?) -> Void)?
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
    onViewportHeight: ((CGFloat?) -> Void)? = nil) {
    let previousSize = intrinsicContentSize
    let changed = self.font != font || self.lineSpacing != lineSpacing
      || self.rightToLeft != rightToLeft || self.joinsLetters != joinsLetters
      || self.rendering.compositionTextMap?.fieldRuns != rendering.compositionTextMap?.fieldRuns
      || self.rendering.compositionTextMap?.canonicalAliases != rendering.compositionTextMap?.canonicalAliases
      || self.rendering.compositionTextMap?.caret != rendering.compositionTextMap?.caret
    if changed { invalidatesModel = true }
    self.rendering = rendering; self.font = font; self.lineSpacing = lineSpacing
    self.rightToLeft = rightToLeft; self.joinsLetters = joinsLetters
    self.configuration = carets; self.lineScroll = lineScroll
    self.viewportLineCount = viewportLineCount; self.onViewportHeight = onViewportHeight
    notificationRevision &+= 1
    _ = measure(width: max(1, bounds.width))
    deliverHeight()
    configureControllers()
    setAccessibilityValue(String(rendering.text.characters))
    needsDisplay = true
    if intrinsicContentSize != previousSize {
      invalidateIntrinsicContentSize()
      needsLayout = true
    }
  }

  @discardableResult func measure(width: CGFloat) -> CGSize {
    guard let map = rendering.compositionTextMap else {
      model = nil; return .init(width: width, height: 0)
    }
    if model == nil || invalidatesModel || modelWidth != width {
      modelWidth = width
      model = PromptFieldTextLayout(map: map, width: width, font: font, lineSpacing: lineSpacing,
        rightToLeft: rightToLeft, joinsLetters: joinsLetters, reusing: model)
      invalidatesModel = false
      geometryRevision &+= 1
      caret.invalidateGeometry()
      deliverHeight()
    }
    return model?.size ?? .zero
  }

  private func refreshRendering() -> PromptRendering {
    if let next = configuration?.latestRendering?() {
      if rendering.compositionTextMap?.fieldRuns != next.compositionTextMap?.fieldRuns
        || rendering.compositionTextMap?.canonicalAliases != next.compositionTextMap?.canonicalAliases
        || rendering.compositionTextMap?.caret != next.compositionTextMap?.caret {
        let previousSize = intrinsicContentSize
        rendering = next; invalidatesModel = true; notificationRevision &+= 1
        _ = measure(width: max(1, bounds.width))
        updateFollower(); needsDisplay = true
        if intrinsicContentSize != previousSize {
          invalidateIntrinsicContentSize()
          needsLayout = true
        }
        setAccessibilityValue(String(next.text.characters))
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
    caret.stop(); follower.cancelCaretMotion(); follower.stopLineScroll()
    lineScroll = nil
    follower.update(text: AttributedString(), characterOffset: nil, font: font,
      lineSpacing: lineSpacing, isRightToLeft: rightToLeft)
  }
}
