import Foundation

/// Owned low-register air burst and damped delay network. No recording,
/// impulse response or reference waveform is embedded in the application.
enum TypingFinishReverbSound {
  static let sampleRate = 22_050
  static let duration = 1.6
  static let dryDuration = 0.3

  static func samples() -> [Double] {
    let frameCount = Int(duration * Double(sampleRate))
    let delays = [0.031, 0.043, 0.059, 0.071]
    let feedback = [0.76, 0.73, 0.70, 0.69]
    var buffers = delays.map { Array(repeating: 0.0, count: Int($0 * Double(sampleRate))) }
    var positions = Array(repeating: 0, count: delays.count)
    var filtered = Array(repeating: 0.0, count: delays.count)
    var output = Array(repeating: 0.0, count: frameCount)
    var noiseState: UInt32 = 0x472b_61d9
    var phase = 0.0
    for frame in 0..<frameCount {
      let time = Double(frame) / Double(sampleRate)
      var dry = 0.0
      if time < dryDuration {
        let progress = time / dryDuration
        noiseState = 1_664_525 &* noiseState &+ 1_013_904_223
        let noise = Double(noiseState) / Double(UInt32.max) * 2 - 1
        phase += 2 * .pi * (108 - 65 * progress) / Double(sampleRate)
        let flutter = 0.55 + 0.45 * sin(2 * .pi * 23 * time)
        let envelope = min(1, time / 0.006) * pow(1 - progress, 1.2)
        dry = tanh(1.9 * (0.65 * sin(phase) + 0.35 * noise)) * flutter * envelope * 0.42
      }
      var wet = 0.0
      for channel in buffers.indices {
        let position = positions[channel]
        filtered[channel] = 0.45 * buffers[channel][position] + 0.55 * filtered[channel]
        buffers[channel][position] = dry + feedback[channel] * filtered[channel]
        wet += filtered[channel] / Double(delays.count)
        positions[channel] = (position + 1) % buffers[channel].count
      }
      let fade = min(1, max(0, (duration - time) / 0.08))
      output[frame] = (0.65 * dry + 0.55 * wet) * fade
    }
    return output
  }

  static func renderedWAVData() -> Data {
    let samples = samples()
    let byteCount = samples.count * MemoryLayout<Int16>.size
    var data = Data()
    func append16(_ value: UInt16) {
      data.append(UInt8(value & 0xff)); data.append(UInt8(value >> 8))
    }
    func append32(_ value: UInt32) {
      append16(UInt16(value & 0xffff)); append16(UInt16(value >> 16))
    }
    data.append(contentsOf: "RIFF".utf8); append32(UInt32(36 + byteCount))
    data.append(contentsOf: "WAVEfmt ".utf8); append32(16)
    append16(1); append16(1); append32(UInt32(sampleRate))
    append32(UInt32(sampleRate * 2)); append16(2); append16(16)
    data.append(contentsOf: "data".utf8); append32(UInt32(byteCount))
    for sample in samples {
      let pcm = Int16((sample.clamped(to: -1...1) * Double(Int16.max)).rounded())
      append16(UInt16(bitPattern: pcm))
    }
    return data
  }
}
