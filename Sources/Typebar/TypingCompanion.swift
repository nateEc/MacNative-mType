import SwiftUI

/// Tracks the physical hand associated with held keys. Centre keys alternate
/// hands so a single Space, Y, B or 6 press never lights both hands at once.
struct TypingCompanionHands: Equatable {
  private var heldHands: [UInt16: PhysicalKeyboardHand] = [:]
  private var lastCentreHand: PhysicalKeyboardHand = .right

  var leftIsActive: Bool { heldHands.values.contains(.left) }
  var rightIsActive: Bool { heldHands.values.contains(.right) }

  mutating func handle(keyCode: UInt16, isKeyDown: Bool, isRepeat: Bool = false) {
    if isKeyDown {
      guard !isRepeat, heldHands[keyCode] == nil else { return }
      let candidates = PhysicalKeyboardHandMap.hands(for: keyCode)
      guard !candidates.isEmpty else { return }
      let hand: PhysicalKeyboardHand
      if candidates.count == 2 {
        hand = lastCentreHand == .left ? .right : .left
        lastCentreHand = hand
      } else {
        hand = candidates.first!
      }
      heldHands[keyCode] = hand
    } else {
      heldHands.removeValue(forKey: keyCode)
    }
  }

  mutating func reset() {
    heldHands = [:]
  }
}

enum TypingCompanionMotion {
  static let fastThreshold: Double = 130
  static let fastestThreshold: Double = 180

  static func fastBlend(for wpm: Double) -> Double {
    ((wpm - fastThreshold) / (fastestThreshold - fastThreshold)).clamped(to: 0...1)
  }
}

/// An original code-drawn typing companion. It visualizes physical hand use
/// and speed without bundling or reproducing any third-party art assets.
struct TypingCompanion: View {
  let hands: TypingCompanionHands
  let wpm: Double
  let accent: Color
  let panel: Color
  let reduceMotion: Bool
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

  private var fastBlend: Double { TypingCompanionMotion.fastBlend(for: wpm) }
  private var motionIsReduced: Bool { reduceMotion || systemReduceMotion }

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
      let pulse = motionIsReduced ? 0 : sin(timeline.date.timeIntervalSinceReferenceDate * (2 + fastBlend * 12))
      ZStack {
        RoundedRectangle(cornerRadius: 15)
          .fill(panel.opacity(0.92))
          .overlay {
            RoundedRectangle(cornerRadius: 15)
              .stroke(accent.opacity(0.22 + fastBlend * 0.35), lineWidth: 1)
          }
        companionBody(pulse: pulse)
      }
      .frame(width: 112, height: 70)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityDescription)
    .accessibilityHint("显示当前物理键盘的左右手按键状态与练习速度")
  }

  private func companionBody(pulse: Double) -> some View {
    let leftOffset: CGFloat = hands.leftIsActive ? -5 - CGFloat(pulse * 2) : 0
    let rightOffset: CGFloat = hands.rightIsActive ? 5 + CGFloat(pulse * 2) : 0
    return ZStack {
      Circle()
        .fill(accent.opacity(0.14 + fastBlend * 0.26))
        .frame(width: 48 + fastBlend * 12)
        .blur(radius: 8)
      VStack(spacing: 4) {
        HStack(spacing: 8) {
          Circle().fill(accent).frame(width: 7, height: 7)
          Circle().fill(accent).frame(width: 7, height: 7)
        }
        Capsule()
          .fill(accent.opacity(0.9))
          .frame(width: 33, height: 18)
      }
      HStack(spacing: 37) {
        hand(active: hands.leftIsActive)
          .offset(x: leftOffset, y: hands.leftIsActive ? -3 : 4)
        hand(active: hands.rightIsActive)
          .offset(x: rightOffset, y: hands.rightIsActive ? -3 : 4)
      }
      .offset(y: 22)
    }
  }

  private func hand(active: Bool) -> some View {
    Capsule()
      .fill(active ? accent : accent.opacity(0.24))
      .frame(width: 24, height: 10)
      .shadow(color: active ? accent.opacity(0.42) : .clear, radius: 5)
  }

  private var accessibilityDescription: String {
    let left = hands.leftIsActive ? "左手按下" : "左手空闲"
    let right = hands.rightIsActive ? "右手按下" : "右手空闲"
    return "节奏伙伴，\(left)，\(right)，当前 \(Int(wpm.rounded())) WPM"
  }
}
