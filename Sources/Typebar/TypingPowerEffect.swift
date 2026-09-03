import SwiftUI

/// Native counterpart to the reference product's hidden power-mode setting.
/// The effect is original: it uses code-drawn trails instead of web canvas code
/// or bundled visual assets.
enum TypingPowerMode: String, CaseIterable, Codable, Equatable, Identifiable {
  case off
  case mellow
  case high
  case ultra
  case over9000

  var id: Self { self }

  var displayName: String {
    switch self {
    case .off: "关闭"
    case .mellow: "柔和"
    case .high: "高能"
    case .ultra: "超载"
    case .over9000: "极限"
    }
  }

  var usesSpectrum: Bool { self == .high || self == .over9000 }
  var usesShake: Bool { self == .ultra || self == .over9000 }
  var isEnabled: Bool { self != .off }
}

enum TypingPowerTone: Equatable {
  case accent
  case error
  case spectrum
}

struct TypingPowerParticle: Identifiable, Equatable {
  let id: UUID
  let origin: CGPoint
  let velocity: CGSize
  let createdAt: Date
  let tone: TypingPowerTone
  let hue: Double
}

enum TypingPowerPolicy {
  static let minimumParticleCount = 6
  static let maximumParticleCount = 9
  static let maximumParticles = 96
  static let particleLifetime: TimeInterval = 0.9

  static func particleCount(randomUnit: Double) -> Int {
    let unit = randomUnit.clamped(to: 0...1)
    return Int((Double(minimumParticleCount) + unit * 3).rounded())
      .clamped(to: minimumParticleCount...maximumParticleCount)
  }

  static func tone(for mode: TypingPowerMode, isCorrect: Bool, isBlind: Bool) -> TypingPowerTone {
    if mode.usesSpectrum { return .spectrum }
    return isCorrect || isBlind ? .accent : .error
  }

  /// Keeps the emission near the active practice area without depending on
  /// copied browser caret geometry. The X position advances through a safe
  /// central band as the user moves through the prompt.
  static func origin(typedCharacters: Int, promptLength: Int) -> CGPoint {
    guard promptLength > 0 else { return .init(x: 0.5, y: 0.48) }
    let progress = Double(typedCharacters).clamped(to: 0...Double(promptLength)) / Double(promptLength)
    return .init(x: 0.22 + progress * 0.56, y: 0.48)
  }

  static func position(
    for particle: TypingPowerParticle, at age: TimeInterval, in size: CGSize
  ) -> CGPoint {
    let initial = CGPoint(x: particle.origin.x * size.width, y: particle.origin.y * size.height)
    let clampedAge = max(0, age)
    return .init(
      x: initial.x + particle.velocity.width * clampedAge,
      y: initial.y + particle.velocity.height * clampedAge + 330 * clampedAge * clampedAge)
  }

  static func opacity(at age: TimeInterval) -> Double {
    max(0, 1 - age / particleLifetime)
  }

  static func shakeOffset(xRandomUnit: Double, yRandomUnit: Double) -> CGSize {
    .init(
      width: (xRandomUnit.clamped(to: 0...1) - 0.5) * 10,
      height: (yRandomUnit.clamped(to: 0...1) - 0.5) * 10)
  }
}

struct TypingPowerOverlay: View {
  let particles: [TypingPowerParticle]
  let accent: Color
  let error: Color
  let reducesMotion: Bool
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
      Canvas { context, size in
        guard !reducesMotion, !systemReduceMotion else { return }
        for particle in particles {
          let age = timeline.date.timeIntervalSince(particle.createdAt)
          let opacity = TypingPowerPolicy.opacity(at: age)
          guard opacity > 0 else { continue }
          let previous = TypingPowerPolicy.position(
            for: particle, at: max(0, age - 1.0 / 30.0), in: size)
          let current = TypingPowerPolicy.position(for: particle, at: age, in: size)
          var trail = Path()
          trail.move(to: previous)
          trail.addLine(to: current)
          context.stroke(
            trail, with: .color(color(for: particle).opacity(opacity)), lineWidth: 3.5)
        }
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func color(for particle: TypingPowerParticle) -> Color {
    switch particle.tone {
    case .accent: accent
    case .error: error
    case .spectrum: Color(hue: particle.hue, saturation: 0.85, brightness: 1)
    }
  }
}
