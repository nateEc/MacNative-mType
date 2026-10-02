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
  case pianoSine
  case pianoSaw
  case pianoSquare
  case pianoTriangle
  case pentatonic
  case wholeTone

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
    case .pianoSine: "键位正弦"
    case .pianoSaw: "键位锯齿"
    case .pianoSquare: "键位方波"
    case .pianoTriangle: "键位三角"
    case .pentatonic: "五声音阶"
    case .wholeTone: "全音音阶"
    }
  }

  var playbackSource: TypingClickPlaybackSource {
    if let musicMode { return .musical(musicMode, musicMode.representativeTone) }
    return switch self {
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
    case .pianoSine, .pianoSaw, .pianoSquare, .pianoTriangle, .pentatonic, .wholeTone:
      preconditionFailure("Music is routed above")
    }
  }

  var sampleVariantCount: Int {
    switch self {
    case .tink, .pop, .ping, .drift, .quartz: 3
    case .morse, .ember: 6
    case .velvet, .frost: 8
    case .copper: 5
    case .lantern, .meadow, .prism, .rain, .slate, .spark, .tide, .willow, .zephyr, .nocturne: 10
    case .ripple, .reed, .pebble, .loom, .orbit, .pulse: 1
    case .pianoSine, .pianoSaw, .pianoSquare, .pianoTriangle, .pentatonic, .wholeTone: 0
    }
  }

  func sampleSource(variantIndex: Int) -> TypingClickPlaybackSource? {
    guard (0..<sampleVariantCount).contains(variantIndex) else { return nil }
    let first = playbackSource
    guard variantIndex > 0 else { return first }
    let base: TypingClickToneProfile
    if case .synthesized(let profile) = first { base = profile }
    else {
      // Owned seeds for variations of the four retained macOS selections.
      switch self {
      case .tink: base = .init(waveform: .sine, frequency: 1_460, overtone: 2.3, overtoneMix: 0.12, duration: 0.035, decay: 4)
      case .pop: base = .init(waveform: .triangle, frequency: 240, overtone: 1.4, overtoneMix: 0.18, duration: 0.050, decay: 2.6)
      case .ping: base = .init(waveform: .sine, frequency: 930, overtone: 2.6, overtoneMix: 0.23, duration: 0.055, decay: 3.1)
      case .morse: base = .init(waveform: .softSquare, frequency: 690, overtone: 1.7, overtoneMix: 0.09, duration: 0.042, decay: 2.9)
      default: return nil
      }
    }
    return .synthesized(base.sampleVariation(variantIndex))
  }

  var musicMode: TypingMusicMode? {
    switch self {
    case .pianoSine: .keys(.sine)
    case .pianoSaw: .keys(.sawtooth)
    case .pianoSquare: .keys(.square)
    case .pianoTriangle: .keys(.triangle)
    case .pentatonic: .pentatonic
    case .wholeTone: .wholeTone
    default: nil
    }
  }
}

enum TypingClickPlaybackSource: Hashable {
  case system(String)
  case synthesized(TypingClickToneProfile)
  case musical(TypingMusicMode, TypingMusicTone)
  case finishReverb
}

enum TypingFinishSoundPolicy {
  static func shouldPlay(previousOutcome: TestOutcome, outcome: TestOutcome, hasStarted: Bool,
    clickEnabled: Bool, style: TypingClickSoundStyle) -> Bool {
    guard previousOutcome == .active, hasStarted, clickEnabled, style == .frost else { return false }
    switch outcome {
    case .completed, .failed, .invalidAFK, .bailedOut: return true
    case .active, .abandoned: return false
    }
  }
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

  /// A small owned timbre lattice, not a reproduction of any web WAV pack.
  func sampleVariation(_ index: Int) -> Self {
    let offset = Double(index)
    return .init(waveform: waveform, frequency: frequency * pow(2, offset / 40),
      overtone: overtone + offset * 0.06, overtoneMix: min(0.45, overtoneMix + offset * 0.008),
      duration: duration * (1 + offset * 0.02), decay: decay + offset * 0.04)
  }

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

  var sampleVariantCount: Int { self == .submarine ? 2 : 1 }
  func sampleSource(variantIndex: Int) -> TypingClickPlaybackSource? {
    guard (0..<sampleVariantCount).contains(variantIndex) else { return nil }
    if variantIndex == 0 { return .system(systemSoundName) }
    return .synthesized(.init(waveform: .triangle, frequency: 198, overtone: 2.35,
      overtoneMix: 0.22, duration: 0.14, decay: 2.1))
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

/// Produces the missed whole-second ticks from a test's original start time.
/// This keeps countdown side effects on the same grid after a brief run-loop
/// stall instead of silently skipping them based on the recovery instant.
enum ClockTickPolicy {
  static func dueSeconds(after previousSecond: Int, startedAt: Date, now: Date) -> [Int] {
    let elapsedSecond = max(0, Int(now.timeIntervalSince(startedAt).rounded(.down)))
    let lastDeliveredSecond = max(0, previousSecond)
    guard elapsedSecond > lastDeliveredSecond else { return [] }
    return Array((lastDeliveredSecond + 1)...elapsedSecond)
  }

  static func remainingSeconds(duration: TimeInterval, elapsedSecond: Int) -> Int {
    max(0, Int((duration - Double(max(0, elapsedSecond))).rounded(.up)))
  }
}

/// The audio-device boundary; playback ownership remains in the controller.
@MainActor
protocol TypingSoundVoice: AnyObject {
  var volume: Float { get set }
  func copyForPlayback() -> (any TypingSoundVoice)?
  func play(onFinish: @escaping () -> Void) -> Bool
  func stop()
}

@MainActor
final class NativeTypingSoundVoice: NSObject, TypingSoundVoice, NSSoundDelegate {
  let sound: NSSound
  private var onFinish: (() -> Void)?

  init(sound: NSSound) {
    self.sound = sound
    super.init()
  }

  var volume: Float {
    get { sound.volume }
    set { sound.volume = newValue }
  }

  func copyForPlayback() -> (any TypingSoundVoice)? {
    guard let copy = sound.copy() as? NSSound, copy !== sound else { return nil }
    copy.loops = false
    return NativeTypingSoundVoice(sound: copy)
  }

  func play(onFinish: @escaping () -> Void) -> Bool {
    self.onFinish = onFinish
    sound.delegate = self
    let started = sound.play()
    if !started { self.onFinish = nil }
    return started
  }

  func stop() { _ = sound.stop() }

  func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
    guard sound === self.sound else { return }
    let finished = onFinish
    onFinish = nil
    finished?()
  }
}

/// Uses only local system sounds and in-memory waveforms. Playback is
/// best-effort: unavailable audio never affects input acceptance or scoring.
@MainActor
final class TypingFeedbackSound {
  static let shared = TypingFeedbackSound(loadSound: { source in
    let sound: NSSound?
    switch source {
    case .system(let name): sound = NSSound(named: NSSound.Name(name))
    case .synthesized(let profile): sound = NSSound(data: profile.renderedWAVData())
    case .musical(_, let tone): sound = NSSound(data: tone.renderedWAVData())
    case .finishReverb: sound = NSSound(data: TypingFinishReverbSound.renderedWAVData())
    }
    return sound.map { NativeTypingSoundVoice(sound: $0) }
  }, beep: { NSSound.beep() })

  private var cachedSources: [TypingClickPlaybackSource: any TypingSoundVoice] = [:]
  private var loadingSources: Set<TypingClickPlaybackSource> = []
  private var configuredClickStyle: TypingClickSoundStyle?
  private var activeVoices: [ObjectIdentifier: any TypingSoundVoice] = [:]
  private var musicalVoices: [ObjectIdentifier: any TypingSoundVoice] = [:]
  private var currentKeyCode: UInt16 = 0
  private var currentModifierFlags: NSEvent.ModifierFlags = []
  private var practiceShiftKeys: Set<UInt16> = []
  private var scaleStates: [TypingMusicMode: TypingMusicScaleState] = [:]
  private var previewScaleStates: [TypingMusicMode: TypingMusicScaleState] = [:]
  private var configuredVolume: Double?
  private weak var warningVoice: (any TypingSoundVoice)?
  private weak var finishVoice: (any TypingSoundVoice)?
  private enum RestartingSampleChannel { case timeWarning, finishReverb }
  private let loadSound: (TypingClickPlaybackSource) -> (any TypingSoundVoice)?
  private let beep: () -> Void
  private let randomUnit: () -> Double

  init(loadSound: @escaping (TypingClickPlaybackSource) -> (any TypingSoundVoice)?,
    beep: @escaping () -> Void, randomUnit: @escaping () -> Double = { Double.random(in: 0..<1) }) {
    self.loadSound = loadSound
    self.beep = beep
    self.randomUnit = randomUnit
  }

  /// Configuration changes affect already playing sample voices and future
  /// requests. Invalid values do not replace the last valid global setting.
  func setVolume(_ volume: Double) {
    guard volume.isFinite, (0...1).contains(volume) else { return }
    configuredVolume = volume
    let voices = Array(activeVoices.values)
    for voice in voices { voice.volume = Float(volume) }
  }

  /// A non-off configuration change prepares resources without creating a
  /// playback instance. Preview targets do not replace the configured family.
  func configureClickSound(style: TypingClickSoundStyle?) {
    configuredClickStyle = style
    if let style { prepareClickSamples(style: style) }
  }

  private func prepareErrorSamples() {
    for style in TypingErrorSoundStyle.allCases {
      for index in 0..<style.sampleVariantCount {
        if let source = style.sampleSource(variantIndex: index) { _ = prototype(for: source) }
      }
    }
  }

  private func prepareClickSamples(style: TypingClickSoundStyle?) {
    prepareErrorSamples()
    guard let style else { return }
    for index in 0..<style.sampleVariantCount {
      if let source = style.sampleSource(variantIndex: index) { _ = prototype(for: source) }
    }
  }

  private func prototype(for source: TypingClickPlaybackSource) -> (any TypingSoundVoice)? {
    if let cached = cachedSources[source] { return cached }
    // The synchronous native loader can be injected/reentered. Never load
    // the same resource recursively; failed loads remain retryable.
    guard loadingSources.insert(source).inserted else { return nil }
    defer { loadingSources.remove(source) }
    guard let loaded = loadSound(source) else { return nil }
    cachedSources[source] = loaded
    return loaded
  }

  func clearAllSounds() {
    let voices = Array(activeVoices.values)
    activeVoices.removeAll(keepingCapacity: true)
    warningVoice = nil
    finishVoice = nil
    // Clear ownership first: NSSound.stop may complete synchronously, and an
    // older queued completion must not affect a replacement attempt.
    for voice in voices { voice.stop() }
  }

  /// Call only after a replacement attempt is accepted. Sample-only cleanup
  /// must not reset modifiers; Caps Lock, key code and music state survive.
  func beginPracticeAttempt() {
    resetPracticeShift()
    clearAllSounds()
  }

  func resetPracticeShift() {
    practiceShiftKeys.removeAll(keepingCapacity: true)
    currentModifierFlags.remove(.shift)
  }

  private func playbackVolume(_ requested: Double) -> Double? {
    if let configuredVolume { return configuredVolume }
    guard requested > 0 else { return nil }
    return requested.clamped(to: 0...1)
  }

  func playClick(style: TypingClickSoundStyle, volume: Double) {
    if let mode = style.musicMode {
      playMusic(mode: mode, requestedVolume: volume, isPreview: false)
      return
    }
    prepareClickSamples(style: style)
    guard let source = style.sampleSource(variantIndex: randomSampleIndex(count: style.sampleVariantCount)) else { return }
    _ = play(source: source, volume: volume)
  }

  func recordKeyDown(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
    currentKeyCode = keyCode
    // A letter's raw Shift flag is not a new Shift press. After a practice
    // reset, an already held physical Shift must stay logically clear.
    synchronizeCapsLock(modifierFlags.contains(.capsLock))
  }

  /// Explicit context initialization, not observation of ordinary key flags.
  func updateModifierFlags(_ flags: NSEvent.ModifierFlags) {
    currentModifierFlags = flags
    practiceShiftKeys = flags.contains(.shift) ? [56] : []
  }

  func recordModifierTransition(keyCode: UInt16, isDown: Bool, modifierFlags: NSEvent.ModifierFlags,
    tracksPracticeShift: Bool = true) {
    if tracksPracticeShift && (keyCode == 56 || keyCode == 60) {
      if isDown { practiceShiftKeys.insert(keyCode) }
      else { practiceShiftKeys.remove(keyCode) }
      if practiceShiftKeys.isEmpty { currentModifierFlags.remove(.shift) }
      else { currentModifierFlags.insert(.shift) }
    }
    synchronizeCapsLock(modifierFlags.contains(.capsLock))
    if isDown { currentKeyCode = keyCode }
  }

  func synchronizeCapsLock(_ isEnabled: Bool) {
    if isEnabled { currentModifierFlags.insert(.capsLock) }
    else { currentModifierFlags.remove(.capsLock) }
  }

  func previewClick(style: TypingClickSoundStyle, volume: Double, usesPracticeShift: Bool = true) {
    if let mode = style.musicMode {
      if case .keys = mode { currentKeyCode = 12 }
      playMusic(mode: mode, requestedVolume: volume, isPreview: true, usesPracticeShift: usesPracticeShift)
    } else {
      prepareClickSamples(style: configuredClickStyle)
      _ = play(source: style.playbackSource, volume: volume)
    }
  }

  private func playMusic(mode: TypingMusicMode, requestedVolume: Double, isPreview: Bool,
    usesPracticeShift: Bool = true) {
    let tone: TypingMusicTone
    switch mode {
    case .keys(let waveform):
      guard let semitone = TypingMusicPitch.semitone(keyCode: currentKeyCode) else { return }
      let raised = currentModifierFlags.contains(.capsLock)
        || (usesPracticeShift && currentModifierFlags.contains(.shift))
      tone = .key(waveform: waveform, semitone: semitone, octave: raised ? 4 : 3)
    case .pentatonic, .wholeTone:
      var state = (isPreview ? previewScaleStates[mode] : scaleStates[mode]) ?? .init()
      guard let next = state.nextTone(mode: mode, randomUnit: randomUnit) else { return }
      if isPreview { previewScaleStates[mode] = state } else { scaleStates[mode] = state }
      tone = next
    }
    guard let voice = loadSound(.musical(mode, tone)) else { return }
    let identity = ObjectIdentifier(voice)
    musicalVoices[identity] = voice
    // The music branch owns its starting gain and exponential envelope.
    // Later sample-volume changes and sample resets intentionally do not
    // change or stop an already scheduled note.
    let volume = configuredVolume ?? (requestedVolume.isFinite ? requestedVolume.clamped(to: 0...1) : 0)
    voice.volume = Float(volume / 10)
    let started = voice.play { [weak self, weak voice] in
      guard let self, let voice, self.musicalVoices[identity] === voice else { return }
      self.musicalVoices.removeValue(forKey: identity)
    }
    if !started { musicalVoices.removeValue(forKey: identity) }
  }

  func playError(style: TypingErrorSoundStyle, volume: Double) {
    prepareErrorSamples()
    guard let source = style.sampleSource(variantIndex: randomSampleIndex(count: style.sampleVariantCount)) else { return }
    if !play(source: source, volume: volume), (playbackVolume(volume) ?? 0) > 0 {
      beep()
    }
  }

  func previewError(style: TypingErrorSoundStyle, volume: Double) {
    prepareErrorSamples()
    if !play(source: .system(style.systemSoundName), volume: volume), (playbackVolume(volume) ?? 0) > 0 { beep() }
  }

  private func randomSampleIndex(count: Int) -> Int {
    let value = randomUnit()
    // Production draws are in 0..<1. Keep injected invalid values from
    // trapping during Double-to-Int conversion or escaping the family.
    guard value.isFinite else { return 0 }
    return Int(value.clamped(to: 0...Double(1).nextDown) * Double(count))
  }

  func playTimeWarning(style: TimeWarningSoundStyle, volume: Double) {
    if !play(source: .system(style.systemSoundName), volume: volume, restarting: .timeWarning),
      (playbackVolume(volume) ?? 0) > 0 {
      beep()
    }
  }

  func playFinishReverb(volume: Double) {
    _ = play(source: .finishReverb, volume: volume, restarting: .finishReverb)
  }

  func playPracticeFinish(previousOutcome: TestOutcome, outcome: TestOutcome, hasStarted: Bool,
    clickEnabled: Bool, style: TypingClickSoundStyle, volume: Double) {
    guard TypingFinishSoundPolicy.shouldPlay(previousOutcome: previousOutcome, outcome: outcome,
      hasStarted: hasStarted, clickEnabled: clickEnabled, style: style) else { return }
    playFinishReverb(volume: volume)
  }

  @discardableResult
  private func play(source: TypingClickPlaybackSource, volume: Double,
    restarting: RestartingSampleChannel? = nil) -> Bool {
    guard let effectiveVolume = playbackVolume(volume) else { return false }
    guard let prototype = prototype(for: source),
      let voice = prototype.copyForPlayback(), voice !== prototype else {
      return false
    }

    // Click/error requests never steal a voice. Countdown and finish cues
    // each restart only their own channel, matching their explicit stop.
    let previous: (any TypingSoundVoice)?
    switch restarting {
    case .timeWarning: previous = warningVoice; warningVoice = nil
    case .finishReverb: previous = finishVoice; finishVoice = nil
    case nil: previous = nil
    }
    if let previous {
      activeVoices.removeValue(forKey: ObjectIdentifier(previous))
      previous.stop()
    }
    let identity = ObjectIdentifier(voice)
    activeVoices[identity] = voice
    switch restarting {
    case .timeWarning: warningVoice = voice
    case .finishReverb: finishVoice = voice
    case nil: break
    }
    voice.volume = Float(effectiveVolume)
    let started = voice.play { [weak self, weak voice] in
      guard let self, let voice, self.activeVoices[identity] === voice else { return }
      self.activeVoices.removeValue(forKey: identity)
    }
    if !started { activeVoices.removeValue(forKey: identity) }
    return started
  }
}
