import AppKit

enum TypingMusicMode: Hashable {
  case keys(TypingMusicTone.Waveform)
  case pentatonic
  case wholeTone

  var scaleSteps: [Int]? {
    switch self {
    case .keys: nil
    case .pentatonic: [0, 2, 4, 7, 9]
    case .wholeTone: Array(stride(from: 0, to: 12, by: 2))
    }
  }

  /// Catalog identity only; real scale previews use their own random walk.
  var representativeTone: TypingMusicTone {
    switch self {
    case .keys(let waveform): .key(waveform: waveform, semitone: 0, octave: 4)
    case .pentatonic, .wholeTone: .scale(semitone: 0, octave: 4)
    }
  }
}

/// A native equal-temperament calculation, not a copied frequency corpus.
/// The piano rows use the existing ANSI *physical* key adapter, never the
/// active input layout, typed character, or IME candidate text.
enum TypingMusicPitch {
  static func frequency(semitone: Int, octave: Int) -> Double {
    let midiNote = 12 * (octave + 1) + semitone
    return (440 * pow(2, Double(midiNote - 69) / 12) * 100).rounded() / 100
  }

  static func semitone(keyCode: UInt16) -> Int? {
    guard let physical = KeyboardLayoutEmulator.character(
      forKeyCode: keyCode, modifierFlags: [], layout: .ansiQwerty)
    else { return nil }
    let naturalSteps = [0, 2, 4, 5, 7, 9, 11]
    for (whites, blacks, offset) in [("zxcvbnm,./", "sd ghj l;", 0),
      ("qwertyuiop[]", "23 567 90 =", 12)] {
      if let index = Array(whites).firstIndex(of: physical) {
        return offset + (index / 7) * 12 + naturalSteps[index % 7]
      }
      if physical != " ", let index = Array(blacks).firstIndex(of: physical) {
        return offset + (index / 7) * 12 + naturalSteps[index % 7] + 1
      }
    }
    return nil
  }
}

struct TypingMusicScaleState {
  private(set) var octave = 4
  private var direction = 1

  mutating func nextTone(mode: TypingMusicMode, randomUnit: () -> Double) -> TypingMusicTone? {
    guard let steps = mode.scaleSteps else { return nil }
    if randomUnit() < 0.5 { octave += direction }
    if octave == 6 { direction = -1 }
    else if octave == 4 { direction = 1 }
    let step = steps[Int(randomUnit() * Double(steps.count))]
    return .scale(semitone: step, octave: octave)
  }
}

struct TypingMusicTone: Hashable {
  enum Waveform: Hashable { case sine, sawtooth, square, triangle }
  let waveform: Waveform
  let frequency: Double
  let duration: Double
  let decayTime: Double

  static func key(waveform: Waveform, semitone: Int, octave: Int) -> Self {
    .init(waveform: waveform, frequency: TypingMusicPitch.frequency(semitone: semitone, octave: octave),
      duration: 0.5, decayTime: 0.15)
  }

  static func scale(semitone: Int, octave: Int) -> Self {
    .init(waveform: .sine, frequency: TypingMusicPitch.frequency(semitone: semitone, octave: octave),
      duration: 2, decayTime: 0.3)
  }

  func sample(at time: Double, sampleRate: Int = 48_000) -> Double {
    guard time >= 0, time < duration else { return 0 }
    let turns = time * frequency
    let phase = turns - floor(turns)
    let signal: Double
    switch waveform {
    case .sine: signal = sin(2 * .pi * phase)
    case .triangle: signal = 2 / .pi * asin(sin(2 * .pi * phase))
    case .sawtooth:
      let shifted = (phase + 0.5).truncatingRemainder(dividingBy: 1)
      signal = 2 * shifted - 1 - edgeCorrection(shifted, width: frequency / Double(sampleRate))
    case .square:
      let opposite = (phase + 0.5).truncatingRemainder(dividingBy: 1)
      signal = (phase < 0.5 ? 1 : -1)
        + edgeCorrection(phase, width: frequency / Double(sampleRate))
        - edgeCorrection(opposite, width: frequency / Double(sampleRate))
    }
    return signal * exp(-time / decayTime)
  }

  /// Smooth the discontinuities over one sample interval. This is our own
  /// band-edge approximation, not a claim of browser-identical DSP output.
  private func edgeCorrection(_ phase: Double, width: Double) -> Double {
    if phase < width {
      let x = phase / width
      return 2 * x - x * x - 1
    }
    if phase > 1 - width {
      let x = (phase - 1) / width
      return x * x + 2 * x + 1
    }
    return 0
  }

  func renderedWAVData(sampleRate: Int = 48_000) -> Data {
    let frames = Int(duration * Double(sampleRate))
    var result = Data()
    func little(_ value: UInt32, bytes: Int = 4) {
      for byte in 0..<bytes { result.append(UInt8(truncatingIfNeeded: value >> (8 * byte))) }
    }
    result.append(contentsOf: "RIFF".utf8)
    little(UInt32(36 + frames * 2))
    result.append(contentsOf: "WAVEfmt ".utf8)
    little(16)
    little(1, bytes: 2)
    little(1, bytes: 2)
    little(UInt32(sampleRate))
    little(UInt32(sampleRate * 2))
    little(2, bytes: 2)
    little(16, bytes: 2)
    result.append(contentsOf: "data".utf8)
    little(UInt32(frames * 2))
    result.reserveCapacity(44 + frames * 2)
    for frame in 0..<frames {
      let value = sample(at: Double(frame) / Double(sampleRate), sampleRate: sampleRate)
      let pcm = Int16((value.clamped(to: -1...1) * Double(Int16.max)).rounded())
      little(UInt32(UInt16(bitPattern: pcm)), bytes: 2)
    }
    return result
  }
}
