import Foundation
import Observation

/// Visual quietness is independent of both first responder and key window.
/// The scheduler is a native next-turn boundary, not a browser frame clock.
@MainActor @Observable final class TypingVisualFocus {
  private(set) var isFocused = false
  private(set) var caretIsBlinking = true
  private(set) var caretBlinkRevision: UInt64 = 0
  @ObservationIgnored private var generation: UInt64 = 0
  @ObservationIgnored private var hasQueuedCommit = false
  @ObservationIgnored private let schedule: (@escaping @MainActor () -> Void) -> Void

  init(schedule: @escaping (@escaping @MainActor () -> Void) -> Void = { callback in
    DispatchQueue.main.async { callback() }
  }) {
    self.schedule = schedule
  }

  func set(_ value: Bool) {
    // Check committed state, not a pending request. Opposite same-turn calls
    // therefore do not always cancel each other (as in the pinned controller).
    guard value != isFocused else { return }
    guard !hasQueuedCommit else { return }
    hasQueuedCommit = true
    generation &+= 1
    let ticket = generation
    schedule { [weak self] in
      guard let self, self.generation == ticket else { return }
      self.hasQueuedCommit = false
      self.isFocused = value
      if value { self.stopCaretBlinking() } else { self.startCaretBlinking() }
    }
  }

  func inputDidUpdate(hasFeedback: Bool, textChanged: Bool, isFinished: Bool) {
    guard !isFinished, hasFeedback || textChanged else { return }
    set(true)
    stopCaretBlinking()
  }

  func startCaretBlinking() {
    guard !caretIsBlinking else { return }
    caretIsBlinking = true
    caretBlinkRevision &+= 1
  }

  /// A hide/show pair may happen between native presentation frames.
  /// Re-entry explicitly starts a new epoch even if blinking was already on.
  func caretDidBecomeVisible() {
    caretIsBlinking = true
    caretBlinkRevision &+= 1
  }

  func stopCaretBlinking() {
    guard caretIsBlinking else { return }
    caretIsBlinking = false
    caretBlinkRevision &+= 1
  }

  func mouseMoved(x: Double, y: Double, transitioning: Bool = false) {
    guard isFocused, !transitioning, x > 3 || y > 3 else { return }
    set(false)
  }

  /// Native window/sheet retirement must invalidate queued entry immediately.
  /// It must never retain callbacks into a detached or background practice page.
  func retire() {
    generation &+= 1
    hasQueuedCommit = false
    isFocused = false
    startCaretBlinking()
  }
}
