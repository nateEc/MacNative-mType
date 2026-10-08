import AppKit
import SwiftUI

struct PromptCaretInputIdentity: Equatable {
  let attemptID: UUID
  let typed: String
  let composition: String
  let glyphID: Int?
}

/// Presentation and pace deadlines have separate, bounded native timers.
/// TextKit runs on target changes, not on every animation frame.
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
    var mainPresentation: (() -> PromptCaretBlinkPresentation)? = nil
  }

  private var configuration: Configuration?
  private var mainHost: NSHostingView<PromptCaretMarkerView>?
  private var paceHost: NSHostingView<PromptCaretMarkerView>?
  private var timer: Timer?
  private var paceTimer: Timer?
  private var input: PromptCaretInputIdentity?
  private var mainOffset: Int?
  private var paceSequence: Double?
  private var paceAttemptID: UUID?
  private var measuredWidth: CGFloat = 0
  private var needsPosition = true
  private var needsSnap = true
  private var blinkClock = PromptCaretBlinkClock()

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
      if restarted { blinkClock = .init() }
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
    schedulePaceTimer(after: 0)
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
      schedulePaceTimer(after: 0)
    }
  }

  override func viewDidMoveToSuperview() {
    super.viewDidMoveToSuperview()
    if superview != nil, configuration != nil, timer == nil { scheduleTimer() }
    if superview != nil, paceTimer == nil { schedulePaceTimer(after: 0) }
  }

  override func viewWillMove(toSuperview newSuperview: NSView?) {
    if newSuperview == nil { stop() }
    super.viewWillMove(toSuperview: newSuperview)
  }

  func stop() {
    timer?.invalidate(); timer = nil
    paceTimer?.invalidate(); paceTimer = nil
    configuration?.coordinator.cancelCarets(at: ProcessInfo.processInfo.systemUptime)
    configuration = nil
    blinkClock = .init()
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

  private func schedulePaceTimer(after delay: TimeInterval) {
    paceTimer?.invalidate(); paceTimer = nil
    guard let config = configuration, config.paceStyle.drawsMarker, config.paceFrame != nil,
      bounds.width > 0, delay.isFinite, delay >= 0 else { return }
    let timer = Timer(timeInterval: delay, target: PromptCaretTimerTarget(owner: self),
      selector: #selector(PromptCaretTimerTarget.paceTick(_:)), userInfo: nil, repeats: false)
    paceTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  fileprivate func advancePace(_ timer: Timer) {
    guard timer === paceTimer else { timer.invalidate(); return }
    paceTimer = nil
    requestPacePosition(at: ProcessInfo.processInfo.systemUptime, fromDeadline: true)
  }

  /// Also permits deterministic component testing without launching the app.
  func present(at time: TimeInterval) {
    guard let config = configuration, bounds.width > 0 else { return }
    let coordinator = config.coordinator
    let latest = config.latestInput?()
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
    let paceFrame = requestPacePosition(at: time)
    let opacity = blinkClock.opacity(at: time, presentation: config.mainPresentation?() ?? .init(),
      motion: config.motion, reducesMotion: config.reducesMotion)
    paint(coordinator.documentRect(isPace: false), style: config.mainStyle,
      accent: config.accent, rightToLeft: config.rightToLeft, isPace: false, host: &mainHost)
    mainHost?.alphaValue = opacity
    paint(paceFrame == nil && config.paceOffset == nil ? nil : coordinator.documentRect(isPace: true),
      style: config.paceStyle, accent: config.accent.opacity(0.72), rightToLeft: config.rightToLeft,
      isPace: true, host: &paceHost)
  }

  /// Requests do not sample or paint. The deadline callback can run between
  /// presentation frames, reading the same fresh providers as the draw path.
  @discardableResult func requestPacePosition(at time: TimeInterval,
    fromDeadline: Bool = false) -> PromptPaceCaretInterpolation? {
    guard let config = configuration, bounds.width > 0, config.paceStyle.drawsMarker else { return nil }
    let attempt = config.latestInput?().attemptID ?? config.attemptID
    if paceAttemptID != attempt { paceSequence = nil; paceAttemptID = attempt }
    let coordinator = config.coordinator
    coordinator.prepare(attemptID: attempt)
    let frame = config.paceFrame?()
    let lostGeometry = coordinator.pace.position == nil
    if lostGeometry {
      coordinator.positionPace(at: measure(0, text: config.text, config: config), time: time, duration: 0)
    }
    if let frame {
      let rawRemaining = (1 - frame.fraction) * frame.stepDuration
      let remaining = rawRemaining.isFinite ? max(0, rawRemaining) : 0
      let changed = frame.sequence != paceSequence || lostGeometry
      if changed {
        // A missing/pruned target preserves the old position and folding flag.
        let rendering = config.latestRendering?()
        func endpoint(_ offset: Int?, after: Bool) -> CGRect? {
          guard let rect = measure(offset, text: rendering?.text ?? config.text, config: config) else { return nil }
          return PromptPaceCaretGeometry.rect(from: rect, to: rect,
            fromAfter: after, toAfter: after, style: config.paceStyle,
            rightToLeft: config.rightToLeft, fraction: 1, reducesMotion: true,
            afterWidth: (" " as NSString).size(withAttributes: [.font: config.font]).width)
        }
        // At an exact deadline, a skipped predecessor has zero (not negative)
        // duration. A resolved timer request writes it before starting the
        // latest tween; a coalesced draw read must not invent that write.
        if fromDeadline, !lostGeometry, !config.reducesMotion, frame.fraction == 0,
          remaining > 0, let previous = paceSequence, frame.sequence.isFinite,
          frame.sequence > previous + 1 {
          let predecessor = frame.zeroDeadlinePredecessor
          let offset = predecessor.flatMap { rendering?.characterOffset(forGlyphAt: $0.glyphIndex) }
            ?? (predecessor == nil ? frame.fromCharacterOffset : nil)
          coordinator.positionPace(at: endpoint(offset, after: predecessor?.after ?? frame.fromAfter),
            time: time, duration: 0)
        }
        let offset = frame.targetGlyphID.flatMap { rendering?.characterOffset(forGlyphAt: $0) }
          ?? (frame.targetGlyphID == nil ? frame.targetCharacterOffset : nil)
        if let target = endpoint(offset, after: frame.targetAfter) {
          coordinator.positionPace(at: target, time: time,
            duration: config.reducesMotion ? 0 : remaining)
        }
        paceSequence = frame.sequence
      }
      if changed || paceTimer == nil {
        if remaining > 0 { schedulePaceTimer(after: remaining) }
        else { paceTimer?.invalidate(); paceTimer = nil }
      }
    } else {
      paceTimer?.invalidate(); paceTimer = nil
      if config.paceFrame == nil, let offset = config.paceOffset {
        coordinator.positionPace(at: measure(offset, text: config.text, config: config), time: time, duration: 0)
      } else if config.paceOffset == nil { paceHost?.isHidden = true }
    }
    return frame
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
  @objc func paceTick(_ timer: Timer) {
    guard let owner else { timer.invalidate(); return }
    owner.advancePace(timer)
  }
}
