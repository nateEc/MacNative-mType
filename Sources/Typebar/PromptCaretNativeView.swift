import AppKit
import SwiftUI

struct PromptCaretInputIdentity: Equatable {
  let attemptID: UUID
  let typed: String
  let composition: String
  let glyphID: Int?
}

/// One bounded native clock drives both independent caret channels. TextKit
/// runs on target changes, not on every animation frame.
final class PromptCaretNativeView: NSView {
  struct Configuration {
    let text: AttributedString
    let mainOffset: Int?, paceOffset: Int?
    let mainStyle: TypingCaretStyle, paceStyle: TypingCaretStyle
    let font: NSFont
    let lineSpacing: CGFloat
    let rightToLeft: Bool
    let accent: Color
    let motion: SmoothCaretMotion
    let reducesMotion: Bool
    let frameRate: Int
    let attemptID: UUID
    let coordinator: PromptCaretMotionCoordinator
    var firstRetainedWordIndex = 0
    var latestInput: (() -> PromptCaretInputIdentity)? = nil
    var latestGlyphID: (() -> Int?)? = nil
    var latestRendering: (() -> PromptRendering)? = nil
    var paceFrame: (() -> PromptPaceCaretInterpolation?)? = nil
  }

  private var configuration: Configuration?
  private var mainHost: NSHostingView<PromptCaretMarkerView>?
  private var paceHost: NSHostingView<PromptCaretMarkerView>?
  private var timer: Timer?
  private var input: PromptCaretInputIdentity?
  private var mainOffset: Int?
  private var paceSequence: Double?
  private var measuredWidth: CGFloat = 0
  private var needsPosition = true
  private var needsSnap = true

  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  func update(_ next: Configuration) {
    let old = configuration
    let layoutChanged = old.map { $0.font != next.font || $0.lineSpacing != next.lineSpacing
      || $0.rightToLeft != next.rightToLeft } ?? false
    let styleChanged = old?.mainStyle != next.mainStyle || old?.paceStyle != next.paceStyle
    let restarted = old?.attemptID != next.attemptID || old?.coordinator !== next.coordinator
    next.coordinator.prepare(attemptID: next.attemptID)
    if layoutChanged || restarted || styleChanged {
      // A new marker or style does not own the sibling's running words tween.
      // prepare handles real attempt changes; only geometry invalidates both.
      if layoutChanged { next.coordinator.resetLayout() }
      input = nil; mainOffset = nil; paceSequence = nil
      needsPosition = true; needsSnap = true
    }
    if old?.reducesMotion != next.reducesMotion || old?.motion != next.motion {
      needsPosition = true; needsSnap = true
    }
    if old?.text != next.text, old?.firstRetainedWordIndex == next.firstRetainedWordIndex {
      needsPosition = true
    }
    configuration = next
    if timer == nil || old?.frameRate != next.frameRate { scheduleTimer() }
    // Defer to the next run-loop presentation: prefix deletion and a real
    // input may be coalesced in one SwiftUI update. Providers read latest state.
    needsLayout = true
  }

  override func layout() {
    super.layout()
    if measuredWidth != bounds.width {
      if measuredWidth > 0 { configuration?.coordinator.resetLayout() }
      measuredWidth = bounds.width
      needsPosition = true; needsSnap = true; paceSequence = nil
    }
  }

  override func viewDidMoveToSuperview() {
    super.viewDidMoveToSuperview()
    if superview != nil, configuration != nil, timer == nil { scheduleTimer() }
  }

  override func viewWillMove(toSuperview newSuperview: NSView?) {
    if newSuperview == nil { stop() }
    super.viewWillMove(toSuperview: newSuperview)
  }

  func stop() {
    timer?.invalidate(); timer = nil
    configuration?.coordinator.cancelCarets(at: ProcessInfo.processInfo.systemUptime)
    configuration = nil
  }

  private func scheduleTimer() {
    timer?.invalidate()
    guard let configuration else { return }
    let interval = PromptLineScrollMotion.frameInterval(frameRate: configuration.frameRate,
      displayFrameRate: window?.screen?.maximumFramesPerSecond ?? 60)
    let timer = Timer(timeInterval: interval, target: PromptCaretTimerTarget(owner: self),
      selector: #selector(PromptCaretTimerTarget.tick(_:)), userInfo: nil, repeats: true)
    self.timer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  fileprivate func advance(_ timer: Timer) {
    guard timer === self.timer else { timer.invalidate(); return }
    present(at: ProcessInfo.processInfo.systemUptime)
  }

  /// Also permits deterministic component testing without launching the app.
  func present(at time: TimeInterval) {
    guard let config = configuration, bounds.width > 0 else { return }
    let coordinator = config.coordinator
    let latest = config.latestInput?()
    if let latest, input?.attemptID != latest.attemptID { paceSequence = nil }
    coordinator.prepare(attemptID: latest?.attemptID ?? config.attemptID)
    coordinator.sample(at: time)
    let changed = latest.map { $0 != input } ?? (config.mainOffset != mainOffset)
    if changed || needsPosition || config.mainStyle.drawsMarker && coordinator.main.position == nil {
      let rendering = config.latestRendering?()
      let glyphID = config.latestGlyphID?() ?? latest?.glyphID
      let offset = latest.flatMap { _ in rendering?.characterOffset(forGlyphAt: glyphID) }
        ?? (latest == nil ? config.mainOffset : nil)
      if config.mainStyle.drawsMarker {
        coordinator.positionMain(at: measure(offset, text: rendering?.text ?? config.text, config: config),
          time: time, duration: needsSnap || config.reducesMotion ? 0 : config.motion.duration ?? 0)
      }
      input = latest; mainOffset = config.mainOffset
      needsPosition = false; needsSnap = false
    }
    let paceFrame = config.paceFrame?()
    if config.paceStyle.drawsMarker {
      if coordinator.pace.position == nil {
        coordinator.positionPace(at: measure(0, text: config.text, config: config), time: time, duration: 0)
      }
      if let frame = paceFrame, frame.sequence != paceSequence {
        // A missing/pruned target preserves the old position and folding flag.
        let rendering = config.latestRendering?()
        let offset = frame.targetGlyphID.flatMap { rendering?.characterOffset(forGlyphAt: $0) }
          ?? (frame.targetGlyphID == nil ? frame.targetCharacterOffset : nil)
        if let to = measure(offset, text: rendering?.text ?? config.text, config: config) {
          let endpoint = PromptPaceCaretGeometry.rect(from: to, to: to,
            fromAfter: frame.targetAfter, toAfter: frame.targetAfter, style: config.paceStyle,
            rightToLeft: config.rightToLeft, fraction: 1, reducesMotion: true,
            afterWidth: (" " as NSString).size(withAttributes: [.font: config.font]).width)
          coordinator.positionPace(at: endpoint, time: time,
            duration: config.reducesMotion ? 0 : max(0, (1 - frame.fraction) * frame.stepDuration))
        }
        paceSequence = frame.sequence
      } else if config.paceFrame == nil, let offset = config.paceOffset {
        coordinator.positionPace(at: measure(offset, text: config.text, config: config), time: time, duration: 0)
      }
    }
    paint(coordinator.documentRect(isPace: false), style: config.mainStyle,
      accent: config.accent, rightToLeft: config.rightToLeft, isPace: false, host: &mainHost)
    paint(paceFrame == nil && config.paceOffset == nil ? nil : coordinator.documentRect(isPace: true),
      style: config.paceStyle, accent: config.accent.opacity(0.72), rightToLeft: config.rightToLeft,
      isPace: true, host: &paceHost)
  }

  private func measure(_ offset: Int?, text: AttributedString, config: Configuration) -> CGRect? {
    offset.flatMap { PromptCaretLayout.rect(in: text, characterOffset: $0, containerSize: bounds.size,
      font: config.font, lineSpacing: config.lineSpacing, isRightToLeft: config.rightToLeft) }
  }

  private func paint(_ rect: CGRect?, style: TypingCaretStyle, accent: Color, rightToLeft: Bool,
    isPace: Bool, host: inout NSHostingView<PromptCaretMarkerView>?) {
    guard let rect, style.drawsMarker else { host?.isHidden = true; return }
    let marker = PromptCaretMarkerView(style: style, accent: accent, rect: rect)
    if host == nil {
      let created = NSHostingView(rootView: marker)
      created.setAccessibilityElement(false)
      if isPace { addSubview(created, positioned: .below, relativeTo: mainHost) }
      else { addSubview(created) }
      host = created
    }
    host?.isHidden = false
    let frame = CGRect(x: PromptCaretPlacementPolicy.horizontalAnchor(for: rect, style: style,
      isRightToLeft: rightToLeft) - rect.width / 2, y: rect.minY,
      width: max(1, rect.width), height: max(1, rect.height))
    if let host, host.frame == frame, host.rootView.style == style,
      host.rootView.accent == accent, host.rootView.rect.size == rect.size { return }
    host?.rootView = marker
    host?.frame = frame
  }
}

@MainActor private final class PromptCaretTimerTarget: NSObject {
  private weak var owner: PromptCaretNativeView?
  init(owner: PromptCaretNativeView) { self.owner = owner }
  @objc func tick(_ timer: Timer) {
    guard let owner else { timer.invalidate(); return }
    owner.advance(timer)
  }
}
