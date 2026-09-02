import AppKit

enum TimeWarningOffset: Int, CaseIterable, Codable, Equatable, Identifiable {
  case off = 0
  case oneSecond = 1
  case threeSeconds = 3
  case fiveSeconds = 5
  case tenSeconds = 10

  var id: Self { self }

  var displayName: String {
    switch self {
    case .off: "关闭"
    case .oneSecond: "结束前 1 秒"
    case .threeSeconds: "结束前 3 秒"
    case .fiveSeconds: "结束前 5 秒"
    case .tenSeconds: "结束前 10 秒"
    }
  }

  var remainingSeconds: Int? { self == .off ? nil : rawValue }
}

enum TimeWarningPolicy {

  static func shouldPlay(remainingSeconds: Int?, previousSecond: Int?, offset: TimeWarningOffset)
    -> Bool
  {
    guard let warningSecond = offset.remainingSeconds, remainingSeconds == warningSecond else {
      return false
    }
    return previousSecond != remainingSeconds
  }
}

/// Uses only sounds supplied by macOS. Playback is intentionally best-effort:
/// a missing system sound never affects input acceptance or test scoring.
@MainActor
final class TypingFeedbackSound {
  static let shared = TypingFeedbackSound()

  private let click = NSSound(named: NSSound.Name("Tink"))
  private let error = NSSound(named: NSSound.Name("Basso"))

  private init() {}

  func playClick(volume: Double) {
    play(click, volume: volume)
  }

  func playError(volume: Double) {
    if error == nil, volume > 0 {
      NSSound.beep()
      return
    }
    play(error, volume: volume)
  }

  private func play(_ sound: NSSound?, volume: Double) {
    guard let sound, volume > 0 else { return }
    sound.stop()
    sound.volume = Float(volume.clamped(to: 0...1))
    sound.play()
  }
}
