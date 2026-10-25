import Foundation
import AppKit
import SwiftUI

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
  static func progress(elapsed: Double) -> Double {
    let t = min(1, max(0, elapsed / 0.25))
    return 1 - (1 - t) * (1 - t)
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
