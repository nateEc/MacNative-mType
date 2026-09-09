import AppKit

/// Original Typebar sound selections backed by macOS system sounds or short
/// in-memory waveforms. The names intentionally do not correspond to web packs.
enum TypingClickSoundStyle: String, CaseIterable, Codable, Equatable, Identifiable {
  case tink
  case pop
  case ping
  case morse
  case ember
  case drift
  case quartz
  case ripple
  case reed
  case pebble
  case loom
  case orbit
  case pulse
  case velvet
  case copper
  case frost
  case lantern
  case meadow
  case prism
  case rain
  case slate
  case spark
  case tide
  case willow
  case zephyr
  case nocturne

  var id: Self { self }

  var displayName: String {
    switch self {
    case .tink: "清脆"
    case .pop: "轻弹"
    case .ping: "短鸣"
    case .morse: "电码"
    case .ember: "余烬"
    case .drift: "浮尘"
    case .quartz: "石英"
    case .ripple: "涟漪"
    case .reed: "苇音"
    case .pebble: "卵石"
    case .loom: "织机"
    case .orbit: "轨迹"
    case .pulse: "脉冲"
    case .velvet: "绒面"
    case .copper: "赤铜"
    case .frost: "霜点"
    case .lantern: "灯芯"
    case .meadow: "草野"
    case .prism: "棱镜"
    case .rain: "雨滴"
    case .slate: "青板"
    case .spark: "火花"
    case .tide: "潮汐"
    case .willow: "柳梢"
    case .zephyr: "微风"
    case .nocturne: "夜曲"
    }
  }

  var playbackSource: TypingClickPlaybackSource {
    switch self {
    case .tink: .system("Tink")
    case .pop: .system("Pop")
    case .ping: .system("Ping")
    case .morse: .system("Morse")
    case .ember:
      .synthesized(
        .init(
          waveform: .triangle, frequency: 245, overtone: 1.5, overtoneMix: 0.20, duration: 0.050,
          decay: 2.4))
    case .drift:
      .synthesized(
        .init(
          waveform: .sine, frequency: 310, overtone: 1.25, overtoneMix: 0.16, duration: 0.058,
          decay: 1.9))
    case .quartz:
      .synthesized(
        .init(
          waveform: .sine, frequency: 1_120, overtone: 2.1, overtoneMix: 0.18, duration: 0.030,
          decay: 3.2))
    case .ripple:
      .synthesized(
        .init(
          waveform: .triangle, frequency: 520, overtone: 1.8, overtoneMix: 0.24, duration: 0.064,
          decay: 2.0))
    case .reed:
      .synthesized(
        .init(
          waveform: .softSquare, frequency: 390, overtone: 2.0, overtoneMix: 0.12, duration: 0.046,
          decay: 2.7))
    case .pebble:
      .synthesized(
        .init(
          waveform: .noise, frequency: 720, overtone: 1.4, overtoneMix: 0.22, duration: 0.026,
          decay: 4.0))
    case .loom:
      .synthesized(
        .init(
          waveform: .softSquare, frequency: 205, overtone: 1.75, overtoneMix: 0.17, duration: 0.055,
          decay: 2.5))
    case .orbit:
      .synthesized(
        .init(
          waveform: .sine, frequency: 465, overtone: 2.5, overtoneMix: 0.14, duration: 0.070,
          decay: 1.7))
    case .pulse:
      .synthesized(
        .init(
          waveform: .softSquare, frequency: 610, overtone: 1.5, overtoneMix: 0.09, duration: 0.032,
          decay: 3.6))
    case .velvet:
      .synthesized(
        .init(
          waveform: .sine, frequency: 275, overtone: 2.0, overtoneMix: 0.10, duration: 0.072,
          decay: 2.2))
    case .copper:
      .synthesized(
        .init(
          waveform: .triangle, frequency: 340, overtone: 2.7, overtoneMix: 0.27, duration: 0.048,
          decay: 2.8))
    case .frost:
      .synthesized(
        .init(
          waveform: .noise, frequency: 980, overtone: 2.2, overtoneMix: 0.13, duration: 0.022,
          decay: 4.5))
    case .lantern:
      .synthesized(
        .init(
          waveform: .sine, frequency: 430, overtone: 1.6, overtoneMix: 0.26, duration: 0.060,
          decay: 2.1))
    case .meadow:
      .synthesized(
        .init(
          waveform: .triangle, frequency: 295, overtone: 1.33, overtoneMix: 0.15, duration: 0.067,
          decay: 1.8))
    case .prism:
      .synthesized(
        .init(
          waveform: .sine, frequency: 840, overtone: 2.4, overtoneMix: 0.25, duration: 0.038,
          decay: 3.0))
    case .rain:
      .synthesized(
        .init(
          waveform: .noise, frequency: 560, overtone: 1.7, overtoneMix: 0.30, duration: 0.034,
          decay: 3.3))
    case .slate:
      .synthesized(
        .init(
          waveform: .softSquare, frequency: 230, overtone: 2.25, overtoneMix: 0.08, duration: 0.040,
          decay: 3.1))
    case .spark:
      .synthesized(
        .init(
          waveform: .triangle, frequency: 1_280, overtone: 1.9, overtoneMix: 0.20, duration: 0.020,
          decay: 5.0))
    case .tide:
      .synthesized(
        .init(
          waveform: .sine, frequency: 185, overtone: 1.5, overtoneMix: 0.21, duration: 0.075,
          decay: 1.6))
    case .willow:
      .synthesized(
        .init(
          waveform: .triangle, frequency: 375, overtone: 1.2, overtoneMix: 0.12, duration: 0.062,
          decay: 2.3))
    case .zephyr:
      .synthesized(
        .init(
          waveform: .noise, frequency: 650, overtone: 1.3, overtoneMix: 0.18, duration: 0.044,
          decay: 2.6))
    case .nocturne:
      .synthesized(
        .init(
          waveform: .softSquare, frequency: 155, overtone: 1.6, overtoneMix: 0.14, duration: 0.080,
          decay: 1.5))
    }
  }
}

enum TypingClickPlaybackSource: Hashable {
  case system(String)
  case synthesized(TypingClickToneProfile)
}

struct TypingClickToneProfile: Hashable {
  enum Waveform: Hashable {
    case sine
    case triangle
    case softSquare
    case noise
  }

  let waveform: Waveform
  let frequency: Double
  let overtone: Double
  let overtoneMix: Double
  let duration: Double
  let decay: Double

  func renderedWAVData(sampleRate: Int = 22_050) -> Data {
    let frameCount = max(1, Int(duration * Double(sampleRate)))
    let dataByteCount = frameCount * MemoryLayout<Int16>.size
    var data = Data()

    func appendUInt16(_ value: UInt16) {
      data.append(UInt8(value & 0xff))
      data.append(UInt8((value >> 8) & 0xff))
    }
    func appendUInt32(_ value: UInt32) {
      data.append(UInt8(value & 0xff))
      data.append(UInt8((value >> 8) & 0xff))
      data.append(UInt8((value >> 16) & 0xff))
      data.append(UInt8((value >> 24) & 0xff))
    }

    data.append(contentsOf: "RIFF".utf8)
    appendUInt32(UInt32(36 + dataByteCount))
    data.append(contentsOf: "WAVEfmt ".utf8)
    appendUInt32(16)
    appendUInt16(1)
    appendUInt16(1)
    appendUInt32(UInt32(sampleRate))
    appendUInt32(UInt32(sampleRate * MemoryLayout<Int16>.size))
    appendUInt16(UInt16(MemoryLayout<Int16>.size))
    appendUInt16(16)
    data.append(contentsOf: "data".utf8)
    appendUInt32(UInt32(dataByteCount))

    var noiseState = UInt32(frequency.rounded()) &+ 0x9e37_79b9
    for frame in 0..<frameCount {
      let progress = Double(frame) / Double(frameCount)
      let attack = min(1, Double(frame) / Double(max(1, sampleRate / 500)))
      let envelope = attack * pow(1 - progress, decay)
      let phase = 2 * Double.pi * frequency * Double(frame) / Double(sampleRate)
      let fundamental: Double
      switch waveform {
      case .sine:
        fundamental = sin(phase)
      case .triangle:
        fundamental = 2 / Double.pi * asin(sin(phase))
      case .softSquare:
        fundamental = tanh(2.4 * sin(phase))
      case .noise:
        noiseState = 1_664_525 &* noiseState &+ 1_013_904_223
        let noise = Double(noiseState) / Double(UInt32.max) * 2 - 1
        fundamental = 0.58 * sin(phase) + 0.42 * noise
      }
      let harmonic = sin(phase * overtone)
      let sample = ((1 - overtoneMix) * fundamental + overtoneMix * harmonic) * envelope * 0.72
      let pcm = Int16((sample.clamped(to: -1...1) * Double(Int16.max)).rounded())
      appendUInt16(UInt16(bitPattern: pcm))
    }

    return data
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

/// Uses only local system sounds and in-memory waveforms. Playback is
/// best-effort: unavailable audio never affects input acceptance or scoring.
@MainActor
final class TypingFeedbackSound {
  static let shared = TypingFeedbackSound()

  private var cachedSounds: [String: NSSound] = [:]
  private var cachedClickSounds: [TypingClickSoundStyle: NSSound] = [:]

  private init() {}

  func playClick(style: TypingClickSoundStyle, volume: Double) {
    guard volume > 0 else { return }
    let sound: NSSound?
    if let cached = cachedClickSounds[style] {
      sound = cached
    } else {
      let loaded: NSSound?
      switch style.playbackSource {
      case .system(let name):
        loaded = NSSound(named: NSSound.Name(name))
      case .synthesized(let profile):
        loaded = NSSound(data: profile.renderedWAVData())
      }
      if let loaded { cachedClickSounds[style] = loaded }
      sound = loaded
    }
    guard let sound else { return }
    sound.stop()
    sound.volume = Float(volume.clamped(to: 0...1))
    _ = sound.play()
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
