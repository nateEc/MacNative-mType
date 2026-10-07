import AppKit

enum NativeSampleWaveform: Sendable {
  case click(TypingClickToneProfile)
  case finishReverb

  func renderedWAVData() -> Data {
    switch self {
    case .click(let profile): profile.renderedWAVData()
    case .finishReverb: TypingFinishReverbSound.renderedWAVData()
    }
  }
}

/// Serial CPU work outside MainActor; no NSSound or mutable voice crosses actors.
actor NativeSampleWaveformRenderer {
  private let render: @Sendable (NativeSampleWaveform) -> Data
  init(render: @escaping @Sendable (NativeSampleWaveform) -> Data = { $0.renderedWAVData() }) {
    self.render = render
  }
  func data(for waveform: NativeSampleWaveform) -> Data { render(waveform) }
}

@MainActor enum NativeSampleSoundPreparation {
  private static let renderer = NativeSampleWaveformRenderer()

  static func load(_ source: TypingClickPlaybackSource,
    using renderer: NativeSampleWaveformRenderer = renderer) async -> (any TypingSoundVoice)? {
    let sound: NSSound?
    switch source {
    case .system(let name): sound = NSSound(named:NSSound.Name(name))
    case .synthesized(let profile):
      let data = await renderer.data(for:.click(profile))
      guard !Task.isCancelled else { return nil }
      sound = NSSound(data:data)
    case .finishReverb:
      let data = await renderer.data(for:.finishReverb)
      guard !Task.isCancelled else { return nil }
      sound = NSSound(data:data)
    case .musical: return nil // Music retains its independent gain/envelope path.
    }
    return sound.map { NativeTypingSoundVoice(sound:$0) }
  }
}
