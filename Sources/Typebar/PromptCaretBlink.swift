import Foundation

struct PromptCaretBlinkPresentation: Equatable {
  var isVisible = true
  var isBlinking = true
  var revision: UInt64 = 0
}

/// One native second, with ease applied independently between keyframes.
/// The hard variant has a short fade between 50% and 51%, not a square wave.
enum PromptCaretBlinkCurve {
  static func opacity(elapsed: TimeInterval, smooth: Bool) -> Double {
    guard elapsed.isFinite else { return 1 }
    let phase = max(0, elapsed).truncatingRemainder(dividingBy: 1)
    if smooth {
      return phase <= 0.5 ? ease(phase * 2) : 1 - ease((phase - 0.5) * 2)
    }
    if phase <= 0.5 { return 1 }
    if phase >= 0.51 { return 0 }
    return 1 - ease((phase - 0.5) / 0.01)
  }

  private static func ease(_ x: Double) -> Double {
    // CSS ease: solve the x coordinate before sampling y, never use x as t.
    let x = min(1, max(0, x))
    var low = 0.0, high = 1.0
    for _ in 0..<40 {
      let t = (low + high) / 2, inverse = 1 - t
      let position = 3 * inverse * inverse * t * 0.25 + 3 * inverse * t * t * 0.25 + t * t * t
      if position < x { low = t } else { high = t }
    }
    let t = (low + high) / 2, inverse = 1 - t
    return 3 * inverse * inverse * t * 0.1 + 3 * inverse * t * t + t * t * t
  }
}

struct PromptCaretBlinkClock {
  private var startedAt: TimeInterval?
  private var smooth: Bool?
  private var revision: UInt64?

  mutating func opacity(at time: TimeInterval, presentation: PromptCaretBlinkPresentation,
    motion: SmoothCaretMotion, reducesMotion: Bool) -> Double {
    guard presentation.isVisible else { self = .init(); return 0 }
    guard presentation.isBlinking, !reducesMotion, time.isFinite else { self = .init(); return 1 }
    let nextSmooth = motion != .off
    if startedAt == nil || smooth != nextSmooth || revision != presentation.revision {
      startedAt = time; smooth = nextSmooth; revision = presentation.revision
    }
    return PromptCaretBlinkCurve.opacity(elapsed: max(0, time - (startedAt ?? time)), smooth: nextSmooth)
  }
}
