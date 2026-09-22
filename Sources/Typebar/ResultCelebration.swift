import SwiftUI

/// Original native celebration effect for result outcomes that the reference
/// product marks with a short confetti burst. The trigger policy is isolated
/// from the SwiftUI drawing code so its compatibility gates remain testable.
enum ResultCelebrationPolicy {
  static let particlesPerSide = 5
  static let launchDuration: TimeInterval = 0.125
  static let particleLifetime: TimeInterval = 0.85
  static let maximumParticles = 160

  static func shouldEmit(
    isNewPersonalBest: Bool, hasZeroSpeedFeedback: Bool, reducesMotion: Bool
  ) -> Bool {
    !reducesMotion && (isNewPersonalBest || hasZeroSpeedFeedback)
  }

  static func particles(at date: Date) -> [ResultCelebrationParticle] {
    particles(at: date) { Double.random(in: 0...1) }
  }

  static func position(
    for particle: ResultCelebrationParticle, at age: TimeInterval, in size: CGSize
  ) -> CGPoint {
    let clampedAge = max(0, age)
    let origin = CGPoint(x: particle.origin.x * size.width, y: particle.origin.y * size.height)
    return .init(
      x: origin.x + particle.velocity.width * clampedAge,
      y: origin.y + particle.velocity.height * clampedAge + 440 * clampedAge * clampedAge)
  }

  static func opacity(at age: TimeInterval) -> Double {
    max(0, 1 - max(0, age) / particleLifetime)
  }

  private static func particles(
    at date: Date, randomUnit: () -> Double
  ) -> [ResultCelebrationParticle] {
    ResultCelebrationSide.allCases.flatMap { side in
      (0..<particlesPerSide).map { _ in
        let horizontalVelocity = 230 + randomUnit() * 180
        return .init(
          id: UUID(),
          origin: .init(
            x: side == .leading ? 0 : 1,
            y: 0.24 + randomUnit() * 0.44),
          velocity: .init(
            width: side == .leading ? horizontalVelocity : -horizontalVelocity,
            height: -300 + randomUnit() * 180),
          createdAt: date,
          paletteIndex: Int((randomUnit() * 3).rounded(.down)).clamped(to: 0...2))
      }
    }
  }
}

private enum ResultCelebrationSide: CaseIterable {
  case leading
  case trailing
}

struct ResultCelebrationParticle: Identifiable {
  let id: UUID
  let origin: CGPoint
  let velocity: CGSize
  let createdAt: Date
  let paletteIndex: Int
}

/// A code-drawn, asset-free native equivalent of the reference confetti. It
/// launches five particles from each side per frame over the same short window.
struct ResultCelebrationView: View {
  let isNewPersonalBest: Bool
  let hasZeroSpeedFeedback: Bool
  let reducesMotion: Bool
  let accent: Color
  let text: Color
  let subduedText: Color
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @Environment(\.typebarAnimationFrameRate) private var animationFrameRate
  @State private var particles: [ResultCelebrationParticle] = []
  @State private var generation = 0
  @State private var hasPlayed = false

  var body: some View {
    TimelineView(
      .animation(minimumInterval: AnimationFrameRatePolicy.minimumInterval(for: animationFrameRate))
    ) { timeline in
      Canvas { context, size in
        for particle in particles {
          let age = timeline.date.timeIntervalSince(particle.createdAt)
          let opacity = ResultCelebrationPolicy.opacity(at: age)
          guard opacity > 0 else { continue }
          let position = ResultCelebrationPolicy.position(for: particle, at: age, in: size)
          let piece = Path(roundedRect: .init(x: position.x - 3, y: position.y - 4, width: 6, height: 8), cornerRadius: 1.5)
          context.fill(piece, with: .color(palette[particle.paletteIndex].opacity(opacity)))
        }
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
    .onAppear(perform: playIfNeeded)
    .onChange(of: shouldEmit) { _, _ in playIfNeeded() }
    .onDisappear {
      generation &+= 1
      particles = []
    }
  }

  private var palette: [Color] { [accent, text, subduedText] }

  private var shouldEmit: Bool {
    ResultCelebrationPolicy.shouldEmit(
      isNewPersonalBest: isNewPersonalBest,
      hasZeroSpeedFeedback: hasZeroSpeedFeedback,
      reducesMotion: reducesMotion || systemReduceMotion)
  }

  private func playIfNeeded() {
    guard shouldEmit, !hasPlayed else { return }
    hasPlayed = true
    generation &+= 1
    let activeGeneration = generation
    let frameInterval = AnimationFrameRatePolicy.minimumInterval(for: animationFrameRate)

    Task { @MainActor in
      let deadline = Date.now.addingTimeInterval(ResultCelebrationPolicy.launchDuration)
      while Date.now < deadline {
        guard activeGeneration == generation else { return }
        let emission = ResultCelebrationPolicy.particles(at: .now)
        particles = Array((particles + emission).suffix(ResultCelebrationPolicy.maximumParticles))
        do {
          try await Task.sleep(nanoseconds: UInt64(frameInterval * 1_000_000_000))
        } catch {
          return
        }
      }
      do {
        try await Task.sleep(nanoseconds: UInt64(ResultCelebrationPolicy.particleLifetime * 1_000_000_000))
      } catch {
        return
      }
      guard activeGeneration == generation else { return }
      particles = []
    }
  }
}
