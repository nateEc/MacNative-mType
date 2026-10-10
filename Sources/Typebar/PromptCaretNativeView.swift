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
    // Custom renderers supply their actual untransformed glyph boxes by
    // canonical ID. Never reinterpret those IDs as text-character offsets.
    var mainGlyphID: Int? = nil
    var firstGlyphID = 0
    var glyphRect: ((Int) -> CGRect?)? = nil
    var glyphIsRightToLeft: ((Int) -> Bool)? = nil
    var geometryRevision: UInt64 = 0
    var mainGlyphRect: ((Int) -> CGRect?)? = nil
    // Field layouts resolve virtual IDs themselves; canonical pace IDs remain
    // a separate API and may alias several presentation slots.
    var fieldMainRect: ((TypingCaretStyle) -> CGRect?)? = nil
    var fieldMainDirection: (() -> Bool)? = nil
    var fieldDirectionPerGlyph = false
    var fieldPaceRect: ((Int, Bool) -> CGRect?)? = nil
    var fieldPaceDirection: ((Int, Bool) -> Bool)? = nil
    var automaticallyPresents = true
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
  private var paceGeometryNeedsUpdate = false
  private var paceTargetRect: CGRect?
  private var mainRightToLeft: Bool?
  private var paceRightToLeft: Bool?

  /// A fresh provider can rebuild a custom layout during this presentation,
  /// before SwiftUI delivers its next configuration/geometry revision.
  func invalidateGeometry() {
    needsPosition = true; paceGeometryNeedsUpdate = true
  }

  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  func update(_ next: Configuration) {
    let old = configuration
    let layoutChanged = old.map { $0.font != next.font || $0.lineSpacing != next.lineSpacing
      || $0.rightToLeft != next.rightToLeft
      || $0.fieldDirectionPerGlyph != next.fieldDirectionPerGlyph
      || ($0.fieldMainDirection != nil) != (next.fieldMainDirection != nil)
      || ($0.fieldPaceDirection != nil) != (next.fieldPaceDirection != nil)
      || ($0.glyphRect != nil) != (next.glyphRect != nil)
      || ($0.mainGlyphRect != nil) != (next.mainGlyphRect != nil)
      || ($0.fieldMainRect != nil) != (next.fieldMainRect != nil) } ?? false
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
      paceTargetRect = nil
      mainRightToLeft = nil; paceRightToLeft = nil
    }
    if old?.geometryRevision != next.geometryRevision {
      needsPosition = true; paceGeometryNeedsUpdate = true
    }
    if old?.mainGlyphID != next.mainGlyphID { needsPosition = true }
    if old?.reducesMotion != next.reducesMotion || old?.motion != next.motion {
      needsPosition = true; needsSnap = true
    }
    if old?.text != next.text, old?.firstRetainedWordIndex == next.firstRetainedWordIndex {
      needsPosition = true
    }
    configuration = next
    if !next.automaticallyPresents { timer?.invalidate(); timer = nil }
    else if timer == nil || old?.frameRate != next.frameRate { scheduleTimer() }
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
    paceTargetRect = nil; paceGeometryNeedsUpdate = false
  }

  private func scheduleTimer() {
    timer?.invalidate()
    guard let configuration, configuration.automaticallyPresents else { return }
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
    guard configuration?.attemptID == config.attemptID,
      configuration?.coordinator === coordinator else { return }
    let presentation = config.mainPresentation?() ?? .init()
    guard configuration?.attemptID == config.attemptID,
      configuration?.coordinator === coordinator else { return }
    coordinator.prepare(attemptID: latest?.attemptID ?? config.attemptID)
    coordinator.sample(at: time)
    let changed = latest.map { $0 != input } ?? (config.mainOffset != mainOffset)
    // Hidden/disabled main markers do not need text geometry. Leave their
    // input and invalidation pending so a fresh visible frame still resolves
    // current composition, rather than reusing a stale hidden snapshot.
    if presentation.isVisible, config.mainStyle.drawsMarker,
      changed || needsPosition || coordinator.main.position == nil {
      let rendering = config.latestRendering?()
      let glyphID = config.latestGlyphID?() ?? latest?.glyphID ?? config.mainGlyphID
      let offset = latest.flatMap { _ in rendering?.characterOffset(forGlyphAt: glyphID) }
        ?? (latest == nil ? config.mainOffset : nil)
      if config.mainStyle.drawsMarker {
        mainRightToLeft = config.fieldMainDirection?()
          ?? glyphID.flatMap { config.glyphIsRightToLeft?($0) } ?? config.rightToLeft
        let mainRect: CGRect?
        if let resolver = config.fieldMainRect { mainRect = resolver(config.mainStyle) }
        else if let rendering, let map = rendering.compositionTextMap {
          mainRect = map.caret.flatMap { anchor in map.inkRanges[anchor.cellID].flatMap { range in
            PromptCaretLayout.rect(in: rendering.text, utf16Range: range, containerSize: bounds.size,
              font: config.font, lineSpacing: config.lineSpacing, isRightToLeft: config.rightToLeft,
              followsWrappedWhitespace: !anchor.after).map { rect in
                PromptPaceCaretGeometry.rect(from: rect, to: rect, fromAfter: anchor.after, toAfter: anchor.after,
                  style: config.mainStyle, rightToLeft: mainRightToLeft ?? config.rightToLeft,
                  fraction: 1, reducesMotion: true,
                  afterWidth: (" " as NSString).size(withAttributes: [.font: config.font]).width)
              }
          } }
        } else if let resolver = config.mainGlyphRect { mainRect = glyphID.flatMap(resolver) }
        else { mainRect = measure(offset, text: rendering?.text ?? config.text, config: config, glyphID: glyphID) }
        coordinator.positionMain(at: mainRect,
          time: time, duration: needsSnap || config.reducesMotion ? 0 : config.motion.duration ?? 0)
      }
      input = latest; mainOffset = config.mainOffset
      needsPosition = false; needsSnap = false
    }
    let paceFrame = requestPacePosition(at: time)
    let opacity = blinkClock.opacity(at: time, presentation: presentation,
      motion: config.motion, reducesMotion: config.reducesMotion)
    paint(coordinator.documentRect(isPace: false), style: config.mainStyle,
      accent: config.accent, rightToLeft: mainRightToLeft ?? config.rightToLeft, isPace: false, host: &mainHost)
    mainHost?.alphaValue = opacity
    paint(paceFrame == nil && config.paceOffset == nil ? nil : coordinator.documentRect(isPace: true),
      style: config.paceStyle, accent: config.accent.opacity(0.72), rightToLeft: paceRightToLeft ?? config.rightToLeft,
      isPace: true, host: &paceHost)
  }

  /// Requests do not sample or paint. The deadline callback can run between
  /// presentation frames, reading the same fresh providers as the draw path.
  @discardableResult func requestPacePosition(at time: TimeInterval,
    fromDeadline: Bool = false) -> PromptPaceCaretInterpolation? {
    guard let config = configuration, bounds.width > 0, config.paceStyle.drawsMarker else { return nil }
    let attempt = config.latestInput?().attemptID ?? config.attemptID
    guard configuration?.attemptID == config.attemptID,
      configuration?.coordinator === config.coordinator else { return nil }
    if paceAttemptID != attempt { paceSequence = nil; paceAttemptID = attempt }
    let coordinator = config.coordinator
    coordinator.prepare(attemptID: attempt)
    let frame = config.paceFrame?()
    func direction(_ glyphID: Int?, after: Bool) -> Bool {
      glyphID.flatMap { config.fieldPaceDirection?($0, after) }
        ?? glyphID.flatMap { config.glyphIsRightToLeft?($0) } ?? config.rightToLeft
    }
    let lostGeometry = coordinator.pace.position == nil
    if lostGeometry {
      paceRightToLeft = direction(config.firstGlyphID, after: false)
      coordinator.positionPace(at: measure(0, text: config.text, config: config, glyphID: config.firstGlyphID), time: time, duration: 0)
    }
    if let frame {
      let rawRemaining = (1 - frame.fraction) * frame.stepDuration
      let remaining = rawRemaining.isFinite ? max(0, rawRemaining) : 0
      let changed = frame.sequence != paceSequence || lostGeometry
      if changed || paceGeometryNeedsUpdate {
        // A missing/pruned target preserves the old position and folding flag.
        let rendering = config.latestRendering?()
        func endpoint(_ offset: Int?, glyphID: Int?, after: Bool) -> CGRect? {
          let measured: CGRect?
          if let resolver = config.fieldPaceRect, let glyphID { measured = resolver(glyphID, after) }
          else if let rendering, let map = rendering.compositionTextMap, let glyphID {
            measured = map.range(forCanonicalGlyph: glyphID, after: after).flatMap {
              PromptCaretLayout.rect(in: rendering.text, utf16Range: $0, containerSize: bounds.size,
                font: config.font, lineSpacing: config.lineSpacing, isRightToLeft: config.rightToLeft,
                followsWrappedWhitespace: !after)
            }
          } else { measured = measure(offset, text: rendering?.text ?? config.text, config: config, glyphID: glyphID) }
          guard let rect = measured else { return nil }
          return PromptPaceCaretGeometry.rect(from: rect, to: rect,
            fromAfter: after, toAfter: after, style: config.paceStyle,
            rightToLeft: direction(glyphID, after: after),
            fraction: 1, reducesMotion: true,
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
          coordinator.positionPace(at: endpoint(offset, glyphID: predecessor?.glyphIndex ?? frame.fromGlyphID,
            after: predecessor?.after ?? frame.fromAfter),
            time: time, duration: 0)
        }
        let offset = frame.targetGlyphID.flatMap { rendering?.characterOffset(forGlyphAt: $0) }
          ?? (frame.targetGlyphID == nil ? frame.targetCharacterOffset : nil)
        if let target = endpoint(offset, glyphID: frame.targetGlyphID, after: frame.targetAfter) {
          paceRightToLeft = direction(frame.targetGlyphID, after: frame.targetAfter)
          if changed || target != paceTargetRect {
            coordinator.positionPace(at: target, time: time,
              duration: config.reducesMotion ? 0 : remaining)
          }
          paceTargetRect = target
        }
        paceSequence = frame.sequence
        paceGeometryNeedsUpdate = false
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

  private func measure(_ offset: Int?, text: AttributedString, config: Configuration, glyphID: Int? = nil) -> CGRect? {
    if let glyphRect = config.glyphRect { return glyphID.flatMap(glyphRect) }
    return offset.flatMap { PromptCaretLayout.rect(in: text, characterOffset: $0, containerSize: bounds.size,
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
    guard let host else { return }
    // Marker content is local: only size/style/color affect its SwiftUI body.
    // Native interpolation changes document position without replacing it.
    if host.rootView.style != style || host.rootView.accent != accent
      || host.rootView.rect.size != rect.size { host.rootView = marker }
    if host.frame != frame { host.frame = frame }
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
