import AppKit

/// Process-local presentation state; never part of results or archives.
struct PromptCaretChannel {
  enum Curve {
    case position, line, linear
    func value(_ t: Double) -> CGFloat {
      switch self {
      case .position: CGFloat(t < 0.5 ? pow(t * 2, 1.25) / 2 : 1 - pow((1 - t) * 2, 1.25) / 2)
      case .line: CGFloat(t * (2 - t))
      case .linear: CGFloat(t)
      }
    }
  }
  private struct Tween {
    let from: CGRect, to: CGRect
    let started: TimeInterval, duration: TimeInterval
    let curve: Curve
    func fraction(at time: TimeInterval) -> Double {
      // A request does not advance itself until the next presentation tick.
      if time <= started { return 0 }
      // Addition/subtraction can round an exact endpoint (e.g. 153/563ms)
      // one ULP above its clock value. Admit that representational neighbor,
      // not an earlier real frame, before computing the elapsed fraction.
      if time >= (started + (duration - PromptLineScrollMotion.autoplayLead)).nextDown { return 1 }
      return min(1, max(0, (time - started + PromptLineScrollMotion.autoplayLead) / duration))
    }
    func value(at time: TimeInterval) -> CGRect {
      let t = curve.value(fraction(at: time))
      return .init(x: from.minX + (to.minX - from.minX) * t,
        y: from.minY + (to.minY - from.minY) * t,
        width: from.width + (to.width - from.width) * t,
        height: from.height + (to.height - from.height) * t)
    }
  }
  private(set) var position: CGRect?
  private(set) var margin: CGFloat = 0
  private(set) var marginReady = false
  private(set) var tapeMargin: CGFloat = 0
  private(set) var tapeMarginReady = false
  private(set) var cumulativeTapeCorrection: CGFloat = 0
  private var positionTween: Tween?
  private var marginTween: Tween?
  private var tapeTween: Tween?

  var isAnimatingTape: Bool { tapeTween != nil }

  mutating func sample(at time: TimeInterval) {
    if let tween = positionTween {
      position = tween.value(at: time)
      if tween.fraction(at: time) == 1 { positionTween = nil }
    }
    if let tween = marginTween {
      margin = tween.value(at: time).minY
      if tween.fraction(at: time) == 1 { marginTween = nil; marginReady = true }
    }
    if let tween = tapeTween {
      tapeMargin = tween.value(at: time).minX
      if tween.fraction(at: time) == 1 { tapeTween = nil; tapeMarginReady = true }
    }
  }
  mutating func goTo(_ target: CGRect?, at time: TimeInterval,
    duration: TimeInterval, curve: Curve = .position) {
    guard let target else { return }
    // Requests replace animation targets from the last presented state. A
    // timer/input callback between frames must not render either channel or
    // complete a sibling margin that the display has not presented yet.
    if marginReady {
      position = position?.offsetBy(dx: 0, dy: margin)
      margin = 0
      marginReady = false
    }
    if tapeMarginReady {
      position = position?.offsetBy(dx: tapeMargin, dy: 0)
      cumulativeTapeCorrection += tapeMargin
      tapeMargin = 0; tapeMarginReady = false
    }
    let destination = target.offsetBy(dx: -tapeMargin, dy: -margin)
    if duration > 0, let position {
      positionTween = .init(from: position, to: destination, started: time,
        duration: duration, curve: curve)
    } else { positionTween = nil; position = destination }
  }
  mutating func tapeScroll(to value: CGFloat, at time: TimeInterval, duration: TimeInterval) {
    tapeMarginReady = false
    let destination = value - cumulativeTapeCorrection
    if duration > 0 {
      tapeTween = .init(from: .init(x: tapeMargin, y: 0, width: 0, height: 0),
        to: .init(x: destination, y: 0, width: 0, height: 0), started: time,
        duration: duration, curve: .position)
    } else { tapeTween = nil; tapeMargin = destination; tapeMarginReady = true }
  }
  mutating func tapeWordsRemoved(width: CGFloat) { cumulativeTapeCorrection += width }
  mutating func shiftTapeOrigin(by width: CGFloat) {
    // Prefix removal changes the words origin immediately, before replacing
    // its scroll tween. Marker corrections are owned separately.
    tapeMargin += width
    tapeTween = nil
  }
  mutating func lineJump(to margin: CGFloat, at time: TimeInterval,
    duration: TimeInterval, isPace: Bool) {
    guard duration > 0 || isPace else { return }
    if marginReady { self.margin = 0 }
    marginReady = false
    if duration > 0 {
      marginTween = .init(from: .init(x: 0, y: self.margin, width: 0, height: 0),
        to: .init(x: 0, y: margin, width: 0, height: 0), started: time,
        duration: duration, curve: .line)
    } else { marginTween = nil; self.margin = margin; marginReady = true }
  }
  mutating func cancel(at _: TimeInterval) {
    positionTween = nil
    marginTween = nil
    tapeTween = nil
  }
  mutating func finishLine() {
    margin = 0; marginReady = false; marginTween = nil
  }
  var visibleRect: CGRect? { position?.offsetBy(dx: tapeMargin, dy: margin) }
}

/// Shared by the native follower and marker layer. No callbacks or timers:
/// detaching either view cannot retain its hosting tree through this state.
@MainActor final class PromptCaretMotionCoordinator {
  private(set) var main = PromptCaretChannel()
  private(set) var pace = PromptCaretChannel()
  private var words = PromptCaretChannel()
  private(set) var programmaticScroll: CGFloat = 0
  private var attemptID: UUID?

  var wordsMargin: CGFloat { words.margin }
  var wordsTapeMargin: CGFloat { words.tapeMargin }
  var isAnimatingTape: Bool { words.isAnimatingTape }

  func prepare(attemptID: UUID) {
    guard self.attemptID != attemptID else { return }
    self.attemptID = attemptID
    resetLayout()
  }

  func resetLayout() {
    main = .init(); pace = .init(); words = .init()
    programmaticScroll = 0
  }

  func sample(at time: TimeInterval) {
    main.sample(at: time); pace.sample(at: time); words.sample(at: time)
  }

  func lineJump(to margin: CGFloat, duration: TimeInterval, at time: TimeInterval) {
    main.lineJump(to: margin, at: time, duration: duration, isPace: false)
    pace.lineJump(to: margin, at: time, duration: duration, isPace: true)
    // Immediate source deletion never assigns a words margin.
    if duration > 0 { words.lineJump(to: margin, at: time, duration: duration, isPace: true) }
  }

  func wordsDidFinish(at _: TimeInterval) {
    // The follower owns words completion, not a presentation of the carets.
    // Source lineJump resets only words.marginTop. An independent scrollTape
    // may still own marginLeft (including a running tween) at this instant.
    words.finishLine()
  }

  func reportProgrammaticScroll(_ offset: CGFloat) { programmaticScroll = offset }

  func tapeScroll(to value: CGFloat, duration: TimeInterval, at time: TimeInterval) {
    // The source main caret is locked. Only words and pace receive tape margins.
    words.tapeScroll(to: value, at: time, duration: duration)
    pace.tapeScroll(to: value, at: time, duration: duration)
  }

  func tapeWordsRemoved(width: CGFloat) {
    words.shiftTapeOrigin(by: width)
    main.tapeWordsRemoved(width: width); pace.tapeWordsRemoved(width: width)
  }

  func positionMain(at rect: CGRect?, time: TimeInterval, duration: TimeInterval) {
    main.goTo(rect?.offsetBy(dx: 0, dy: words.margin), at: time, duration: duration)
  }

  func positionPace(at rect: CGRect?, time: TimeInterval, duration: TimeInterval) {
    pace.goTo(rect?.offsetBy(dx: words.tapeMargin, dy: words.margin), at: time, duration: duration, curve: .linear)
  }

  func cancel(at time: TimeInterval) {
    cancelCarets(at: time); words.cancel(at: time)
  }

  func cancelCarets(at time: TimeInterval) {
    main.cancel(at: time); pace.cancel(at: time)
  }

  func documentRect(isPace: Bool) -> CGRect? {
    (isPace ? pace : main).visibleRect?.offsetBy(dx: 0, dy: programmaticScroll)
  }
}
