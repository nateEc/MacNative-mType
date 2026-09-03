import AppKit

/// Original Typebar sound selections backed only by macOS-provided system
/// sounds. The names intentionally do not correspond to any web sound packs.
enum TypingClickSoundStyle: String, CaseIterable, Codable, Equatable, Identifiable {
  case tink
  case pop
  case ping
  case morse

  var id: Self { self }

  var displayName: String {
    switch self {
    case .tink: "清脆"
    case .pop: "轻弹"
    case .ping: "短鸣"
    case .morse: "电码"
    }
  }

  fileprivate var systemSoundName: String {
    switch self {
    case .tink: "Tink"
    case .pop: "Pop"
    case .ping: "Ping"
    case .morse: "Morse"
    }
  }
}

enum TypingErrorSoundStyle: String, CaseIterable, Codable, Equatable, Identifiable {
  case basso
  case funk
  case sosumi
  case submarine

  var id: Self { self }

  var displayName: String {
    switch self {
    case .basso: "低音"
    case .funk: "断奏"
    case .sosumi: "提示"
    case .submarine: "回声"
    }
  }

  fileprivate var systemSoundName: String {
    switch self {
    case .basso: "Basso"
    case .funk: "Funk"
    case .sosumi: "Sosumi"
    case .submarine: "Submarine"
    }
  }
}

enum TimeWarningSoundStyle: String, CaseIterable, Codable, Equatable, Identifiable {
  case glass
  case hero
  case bottle
  case frog

  var id: Self { self }

  var displayName: String {
    switch self {
    case .glass: "玻璃"
    case .hero: "提示号"
    case .bottle: "瓶音"
    case .frog: "蛙鸣"
    }
  }

  fileprivate var systemSoundName: String {
    switch self {
    case .glass: "Glass"
    case .hero: "Hero"
    case .bottle: "Bottle"
    case .frog: "Frog"
    }
  }
}

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

  private var cachedSounds: [String: NSSound] = [:]

  private init() {}

  func playClick(style: TypingClickSoundStyle, volume: Double) {
    _ = play(systemSoundNamed: style.systemSoundName, volume: volume)
  }

  func playError(style: TypingErrorSoundStyle, volume: Double) {
    if !play(systemSoundNamed: style.systemSoundName, volume: volume), volume > 0 {
      NSSound.beep()
    }
  }

  func playTimeWarning(style: TimeWarningSoundStyle, volume: Double) {
    if !play(systemSoundNamed: style.systemSoundName, volume: volume), volume > 0 {
      NSSound.beep()
    }
  }

  @discardableResult
  private func play(systemSoundNamed name: String, volume: Double) -> Bool {
    guard volume > 0 else { return false }
    let sound: NSSound?
    if let cached = cachedSounds[name] {
      sound = cached
    } else {
      let loaded = NSSound(named: NSSound.Name(name))
      if let loaded { cachedSounds[name] = loaded }
      sound = loaded
    }
    guard let sound else { return false }
    sound.stop()
    sound.volume = Float(volume.clamped(to: 0...1))
    return sound.play()
  }
}
