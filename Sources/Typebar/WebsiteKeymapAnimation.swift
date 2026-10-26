import Foundation
import AppKit
import SwiftUI

/// Production uses monotonic time. Hidden pixel fixtures can hold a frame
/// while AppKit rasterizes it, without changing the animation's curve or plan.
struct WebsiteKeymapAnimationClock: Sendable {
  var now: @MainActor @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
  var didSample: @MainActor @Sendable (WebsiteKeymapAnimationState.Plan, Double) -> Void = { _, _ in }
  var didWait: @MainActor @Sendable (TimeInterval) -> Void = { _ in }
}
private struct WebsiteKeymapAnimationClockKey: EnvironmentKey {
  static let defaultValue = WebsiteKeymapAnimationClock()
}
extension EnvironmentValues {
  var websiteKeymapAnimationClock: WebsiteKeymapAnimationClock {
    get { self[WebsiteKeymapAnimationClockKey.self] }
    set { self[WebsiteKeymapAnimationClockKey.self] = newValue }
  }
}

@MainActor final class WebsiteKeymapAnimationCadence: PracticeDisplayFrameRateConsumer {
  var frameRate = AnimationFrameRatePolicy.nativeFrameRate
  var displayFrameRate = 60
  func interval(capturedFrameRate: Int) -> TimeInterval {
    PromptLineScrollMotion.frameInterval(
      frameRate: min(AnimationFrameRatePolicy.normalized(capturedFrameRate),
        AnimationFrameRatePolicy.normalized(frameRate)), displayFrameRate: displayFrameRate)
  }
}

struct WebsiteKeymapAnimationScheduling: Sendable {
  var interval: @MainActor @Sendable (Int) -> TimeInterval = {
    PromptLineScrollMotion.frameInterval(frameRate: $0, displayFrameRate: 60)
  }
}
private struct WebsiteKeymapAnimationSchedulingKey: EnvironmentKey {
  static let defaultValue = WebsiteKeymapAnimationScheduling()
}
extension EnvironmentValues {
  var websiteKeymapAnimationScheduling: WebsiteKeymapAnimationScheduling {
    get { self[WebsiteKeymapAnimationSchedulingKey.self] }
    set { self[WebsiteKeymapAnimationSchedulingKey.self] = newValue }
  }
}

struct WebsiteKeymapAnimationState {
  enum Role: String, Decodable, Hashable { case accent, panel, background, secondary, error }
  struct Plan: Equatable, Decodable {
    let fading: Bool
    let background: [Role]
    let foreground: [Role]
    let duration: Double
  }
  private var previousMode: KeyboardGuideMode?
  private var previousMatch = false
  private var fading = false
  mutating func complete() { fading = false }
  mutating func update(mode: KeyboardGuideMode, steno: Bool, matches: Bool, tick: Int, correct: Bool) -> Plan {
    let next = mode == .next && !steno && matches
    let flash = mode == .react && !steno && tick > 0
    if previousMode == .next, mode != .next, previousMatch { fading = true }
    previousMode = mode; previousMatch = matches && !steno
    if fading { return .init(fading: true, background: [.accent, .panel], foreground: [.background, .secondary], duration: 250) }
    if flash { return .init(fading: false, background: [correct ? .accent : .error, next ? .accent : .panel],
      foreground: [.background, next ? .background : .secondary], duration: 250) }
    return .init(fading: false, background: [next ? .accent : .panel], foreground: [next ? .background : .secondary], duration: 0)
  }
  static func progress(elapsed: Double, duration: Double = 0.25) -> Double {
    guard duration > 0 else { return 1 }
    let t = min(1, max(0, elapsed / duration))
    return 1 - (1 - t) * (1 - t)
  }
}

enum WebsiteKeymapAnimationTiming {
  static let autoplayLead: TimeInterval = 0.012
  struct Sample: Equatable {
    let progress: Double
    let complete: Bool
  }
  static func sample(elapsed: TimeInterval, duration: TimeInterval) -> Sample {
    // Construction publishes the starting value. Subsequent engine ticks
    // include the pinned engine's autoplay lead; seek curves do not.
    let phase = elapsed > 0 && duration > 0 ? elapsed + autoplayLead : elapsed
    return .init(progress: WebsiteKeymapAnimationState.progress(elapsed: phase, duration: duration),
      complete: phase >= duration)
  }
}

struct WebsiteKeymapRGBA: Equatable {
  let red: Double, green: Double, blue: Double, alpha: Double
  func mixed(with other: Self, progress: Double) -> Self {
    .init(red: red + (other.red - red) * progress, green: green + (other.green - green) * progress,
      blue: blue + (other.blue - blue) * progress, alpha: alpha + (other.alpha - alpha) * progress)
  }
  var color: Color { Color(red: red, green: green, blue: blue, opacity: alpha) }
}

struct WebsiteKeymapPalette: Equatable {
  let accent: Color, panel: Color, background: Color, secondary: Color, error: Color
  func resolved(scheme: ColorScheme) -> [WebsiteKeymapAnimationState.Role: WebsiteKeymapRGBA] {
    let colors: [WebsiteKeymapAnimationState.Role: Color] = [.accent: accent, .panel: panel,
      .background: background, .secondary: secondary, .error: error]
    var result: [WebsiteKeymapAnimationState.Role: WebsiteKeymapRGBA] = [:]
    NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
      for (role, color) in colors {
        if let c = NSColor(color).usingColorSpace(.sRGB) {
          result[role] = .init(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: c.alphaComponent)
        }
      }
    }
    return result
  }
}
