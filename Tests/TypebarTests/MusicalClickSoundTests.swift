import AppKit
import XCTest
@testable import Typebar

final class MusicalClickSoundTests: XCTestCase {
  @MainActor private final class Voice: TypingSoundVoice {
    var volume: Float = 1
    var starts = 0
    var stops = 0
    var finish: (() -> Void)?
    var copies: [Voice] = []
    var succeeds = true
    var finishesDuringStart = false
    func copyForPlayback() -> (any TypingSoundVoice)? {
      let copy = Voice(); copies.append(copy); return copy
    }
    func play(onFinish: @escaping () -> Void) -> Bool {
      starts += 1
      finish = onFinish
      if finishesDuringStart { onFinish() }
      return succeeds
    }
    func stop() { stops += 1 }
  }

  private final class WeakVoice {
    weak var value: Voice?
    init(_ value: Voice) { self.value = value }
  }

  @MainActor private func style(_ id: Int) throws -> TypingClickSoundStyle {
    guard case .click(let value?) = SoundCommandCatalog.target(for: "sound.playSoundOnClick.\(id)")
    else { throw NSError(domain: "MissingSound", code: id) }
    return value
  }

  private func pitch(_ source: TypingClickPlaybackSource) -> Double? {
    if case .synthesized(let tone) = source { return tone.frequency }
    if case .musical(_, let tone) = source { return tone.frequency }
    return nil
  }

  private func duration(_ source: TypingClickPlaybackSource) -> Double? {
    if case .synthesized(let tone) = source { return tone.duration }
    if case .musical(_, let tone) = source { return tone.duration }
    return nil
  }

  @MainActor func testFourOfficialOscillatorPreviewsPlayQAtMiddleCForHalfASecond() throws {
    for id in 8...11 {
      var sources: [TypingClickPlaybackSource] = []
      let player = TypingFeedbackSound(loadSound: { sources.append($0); return Voice() }, beep: {})
      player.previewClick(style: try style(id), volume: 0.5)
      XCTAssertEqual(sources.count, 1)
      XCTAssertEqual(pitch(sources[0]), 261.63)
      XCTAssertEqual(duration(sources[0]), 0.5)
    }
  }

  @MainActor func testPhysicalZAndQSelectDifferentOctavesRatherThanAFixedClick() throws {
    for id in 8...11 {
      var sources: [TypingClickPlaybackSource] = []
      let player = TypingFeedbackSound(loadSound: { sources.append($0); return Voice() }, beep: {})
      player.recordKeyDown(keyCode: 6, modifierFlags: [])
      player.playClick(style: try style(id), volume: 0.5)
      player.recordKeyDown(keyCode: 12, modifierFlags: [])
      player.playClick(style: try style(id), volume: 0.5)
      XCTAssertEqual(sources.compactMap(pitch), [130.81, 261.63])
    }
  }

  @MainActor func testUnmappedPhysicalKeysAreSilentWithoutFallingBackToAKey() throws {
    for id in 8...11 {
      var loads = 0
      let player = TypingFeedbackSound(loadSound: { _ in loads += 1; return Voice() }, beep: { XCTFail("no beep") })
      for key: UInt16 in [0, 49, 51, 36, 123, 65535] {
        player.recordKeyDown(keyCode: key, modifierFlags: [])
        player.playClick(style: try style(id), volume: 0.5)
      }
      XCTAssertEqual(loads, 0)
    }
  }

  @MainActor func testShiftOrCapsLockRaisesOneOctaveNotTwoAndUsesLatestModifiers() throws {
    var sources: [TypingClickPlaybackSource] = []
    let player = TypingFeedbackSound(loadSound: { sources.append($0); return Voice() }, beep: {})
    let sine = try style(8)
    player.recordKeyDown(keyCode: 12, modifierFlags: [])
    for flags: NSEvent.ModifierFlags in [.shift, .capsLock, [.shift, .capsLock], []] {
      player.updateModifierFlags(flags)
      player.playClick(style: sine, volume: 0.5)
    }
    XCTAssertEqual(sources.compactMap(pitch), [523.25, 523.25, 523.25, 261.63])
  }

  @MainActor func testTwoOfficialScalesUseTwoSecondNotesRegardlessOfPhysicalKey() throws {
    for id in 12...13 {
      var sources: [TypingClickPlaybackSource] = []
      let player = TypingFeedbackSound(loadSound: { sources.append($0); return Voice() }, beep: {})
      player.recordKeyDown(keyCode: 51, modifierFlags: [.shift, .capsLock])
      player.playClick(style: try style(id), volume: 0.5)
      XCTAssertEqual(sources.count, 1)
      XCTAssertEqual(duration(sources[0]), 2)
      XCTAssertTrue((261.63...1975.53).contains(pitch(sources[0]) ?? 0))
    }
  }

  @MainActor func testExistingMusicEnvelopeKeepsItsVolumeAndSurvivesSampleReset() throws {
    var loaded: [Voice] = []
    let player = TypingFeedbackSound(loadSound: { _ in
      let voice = Voice(); loaded.append(voice); return voice
    }, beep: {})
    player.setVolume(0.5)
    player.previewClick(style: try style(8), volume: 0.9)
    // Sample prototypes are not started; music is a fresh, directly played voice.
    let musicalVoice = try XCTUnwrap(loaded.first)
    XCTAssertEqual(musicalVoice.starts, 1)
    XCTAssertEqual(musicalVoice.volume, 0.05, accuracy: 0.0001)
    player.setVolume(0)
    player.clearAllSounds()
    XCTAssertEqual(musicalVoice.volume, 0.05, accuracy: 0.0001)
    XCTAssertEqual(musicalVoice.stops, 0)
    musicalVoice.finish?()
  }

  func testPhysicalPianoHasThirtySevenKeysAndRejectsOtherNativeCodes() throws {
    let mapped = (UInt16(0)..<128).compactMap { code -> (UInt16, Int)? in
      TypingMusicPitch.semitone(keyCode: code).map { (code, $0) }
    }
    XCTAssertEqual(mapped.count, 37)
    XCTAssertEqual(mapped.map(\.1).min(), 0)
    XCTAssertEqual(mapped.map(\.1).max(), 31)
    for (key, step) in mapped {
      for flags: NSEvent.ModifierFlags in [[], .shift, .capsLock, [.shift, .capsLock]] {
        let octave = flags.isEmpty ? 3 : 4
        let frequency = TypingMusicPitch.frequency(semitone: step, octave: octave)
        XCTAssertGreaterThanOrEqual(frequency, 130.81)
        XCTAssertLessThanOrEqual(frequency, 1567.98)
        XCTAssertNotNil(KeyboardLayoutEmulator.character(forKeyCode: key, modifierFlags: [], layout: .ansiQwerty))
      }
    }
    // Neighboring piano black keys and overlapping upper/lower rows.
    XCTAssertEqual(TypingMusicPitch.semitone(keyCode: 1), 1) // S: C sharp
    XCTAssertEqual(TypingMusicPitch.semitone(keyCode: 2), 3) // D: E flat
    XCTAssertEqual(TypingMusicPitch.semitone(keyCode: 19), 13) // 2: C sharp, next octave
    XCTAssertEqual(TypingMusicPitch.semitone(keyCode: 24), 30) // equals: F sharp
    XCTAssertEqual(TypingMusicPitch.semitone(keyCode: 30), 31) // right bracket: G
    XCTAssertEqual(TypingMusicPitch.semitone(keyCode: 43), TypingMusicPitch.semitone(keyCode: 12))
  }

  @MainActor func testFourOfficialIDsRouteToFourDistinctWaveforms() throws {
    let waveforms: [TypingMusicTone.Waveform] = [.sine, .sawtooth, .square, .triangle]
    for (index, waveform) in waveforms.enumerated() {
      var sources: [TypingClickPlaybackSource] = []
      let player = TypingFeedbackSound(loadSound: { sources.append($0); return Voice() }, beep: {})
      player.previewClick(style: try style(index + 8), volume: 0.5)
      XCTAssertEqual(sources, [.musical(.keys(waveform), .key(waveform: waveform, semitone: 0, octave: 4))])
    }
  }

  @MainActor func testScaleBounceMatchesFixedRandomWalkAndConsumesTwoDrawsPerNote() throws {
    for id in 12...13 {
      var sources: [TypingClickPlaybackSource] = []
      var draws = 0
      let player = TypingFeedbackSound(loadSound: { sources.append($0); return Voice() }, beep: {},
        randomUnit: { draws += 1; return draws.isMultiple(of: 2) ? 0 : 0.1 })
      for _ in 0..<5 { player.playClick(style: try style(id), volume: 0.5) }
      XCTAssertEqual(sources.compactMap(pitch), [523.25, 1046.5, 523.25, 261.63, 523.25])
      XCTAssertEqual(draws, 10)
    }
  }

  @MainActor func testScaleNoteSetsArePentatonicAndWholeToneNotChromatic() throws {
    for (id, expected) in [(12, [261.63, 293.66, 329.63, 392.0, 440.0]),
      (13, [261.63, 293.66, 329.63, 369.99, 415.3, 466.16])] {
      var sources: [TypingClickPlaybackSource] = []
      var draws = 0
      let player = TypingFeedbackSound(loadSound: { sources.append($0); return Voice() }, beep: {}, randomUnit: {
        let draw = draws; draws += 1
        return draw.isMultiple(of: 2) ? 0.75 : (Double(draw / 2) + 0.5) / Double(expected.count)
      })
      for _ in expected { player.playClick(style: try style(id), volume: 0.5) }
      XCTAssertEqual(sources.compactMap(pitch), expected)
    }
  }

  @MainActor func testScalePreviewAndLiveAndDifferentScalesKeepIndependentStateAcrossReset() throws {
    var sources: [TypingClickPlaybackSource] = []
    let player = TypingFeedbackSound(loadSound: { sources.append($0); return Voice() }, beep: {}, randomUnit: { 0 })
    let five = try style(12), whole = try style(13)
    player.previewClick(style: five, volume: 0.5)
    player.previewClick(style: five, volume: 0.5)
    player.playClick(style: five, volume: 0.5)
    player.playClick(style: whole, volume: 0.5)
    player.clearAllSounds()
    player.playClick(style: five, volume: 0.5)
    player.previewClick(style: whole, volume: 0.5)
    XCTAssertEqual(sources.compactMap(pitch), [523.25, 1046.5, 523.25, 523.25, 1046.5, 523.25])
  }

  @MainActor func testPracticeResetKeepsScaleWalksMusicVoicesAndSampleMasterAndCache() throws {
    var sources: [TypingClickPlaybackSource] = []
    var music: [Voice] = []
    let sample = Voice()
    var sampleLoads = 0
    let player = TypingFeedbackSound(loadSound: { source in
      if case .musical = source {
        sources.append(source)
        let voice = Voice(); music.append(voice); return voice
      }
      sampleLoads += 1; return sample
    }, beep: {}, randomUnit: { 0 })
    player.setVolume(0.8)
    for id in [12, 13] {
      player.previewClick(style: try style(id), volume: 0.1)
      player.playClick(style: try style(id), volume: 0.1)
    }
    player.playClick(style: .tink, volume: 0.1)
    let oldSample = try XCTUnwrap(sample.copies.first)
    player.beginPracticeAttempt()
    XCTAssertEqual(oldSample.stops, 1)
    XCTAssertTrue(music.allSatisfy { $0.stops == 0 && $0.starts == 1 })
    for id in [12, 13] {
      player.previewClick(style: try style(id), volume: 0.1)
      player.playClick(style: try style(id), volume: 0.1)
    }
    XCTAssertEqual(sources.compactMap(pitch), [523.25, 523.25, 523.25, 523.25, 1046.5, 1046.5, 1046.5, 1046.5])
    XCTAssertTrue(music.allSatisfy { abs($0.volume - 0.08) < 0.0001 })
    player.playClick(style: .tink, volume: 0.1)
    XCTAssertEqual(sampleLoads, 1)
    XCTAssertEqual(sample.copies.count, 2)
    XCTAssertEqual(try XCTUnwrap(sample.copies.last).volume, 0.8, accuracy: 0.0001)
  }

  func testRandomWalkThresholdIsStrictAndBoundaryDirectionDoesNotDriftOutOfRange() throws {
    var state = TypingMusicScaleState()
    var draws = 0
    let stayed = try XCTUnwrap(state.nextTone(mode: .pentatonic, randomUnit: {
      draws += 1; return draws == 1 ? 0.5 : 0
    }))
    XCTAssertEqual(stayed.frequency, 261.63)
    var octaves: Set<Int> = []
    for _ in 0..<1000 {
      _ = state.nextTone(mode: .wholeTone, randomUnit: { 0 })
      octaves.insert(state.octave)
    }
    XCTAssertEqual(octaves, [4, 5, 6])
  }

  @MainActor func testSampleVolumeAndResetDoNotAlterMusicButStillControlSampleVoices() throws {
    let sample = Voice()
    var music: [Voice] = []
    let player = TypingFeedbackSound(loadSound: { source in
      if case .musical = source { let voice = Voice(); music.append(voice); return voice }
      return sample
    }, beep: {})
    player.setVolume(0.8)
    player.previewClick(style: try style(10), volume: 0.1)
    player.playClick(style: .tink, volume: 0.1)
    let sampleVoice = try XCTUnwrap(sample.copies.first)
    player.setVolume(0.2)
    XCTAssertEqual(sampleVoice.volume, 0.2, accuracy: 0.0001)
    XCTAssertEqual(music[0].volume, 0.08, accuracy: 0.0001)
    player.clearAllSounds()
    XCTAssertEqual(sampleVoice.stops, 1)
    XCTAssertEqual(music[0].stops, 0)
    player.previewClick(style: try style(10), volume: 0.9)
    XCTAssertEqual(music[1].volume, 0.02, accuracy: 0.0001)
  }

  @MainActor func testMutedMusicKeepsItsSilentEnvelopeWhileFutureNotesUseNewVolume() throws {
    var voices: [Voice] = []
    let player = TypingFeedbackSound(loadSound: { _ in let v = Voice(); voices.append(v); return v }, beep: {})
    player.setVolume(0)
    player.previewClick(style: try style(8), volume: 1)
    player.setVolume(1)
    player.previewClick(style: try style(8), volume: 0)
    XCTAssertEqual(voices.map(\.volume), [0, 0.1])
    XCTAssertEqual(voices.map(\.starts), [1, 1])
    XCTAssertEqual(voices.map(\.stops), [0, 0])
  }

  @MainActor func testMusicCompletionReleasesVoicesAndLateCallbacksCannotDropNewNotes() throws {
    var references: [WeakVoice] = []
    var callbacks: [() -> Void] = []
    let player = TypingFeedbackSound(loadSound: { _ in
      let voice = Voice(); references.append(WeakVoice(voice)); return voice
    }, beep: {})
    for _ in 0..<3 {
      player.previewClick(style: try style(8), volume: 0.5)
      callbacks.append(try XCTUnwrap(references.last?.value?.finish))
    }
    XCTAssertTrue(references.allSatisfy { $0.value != nil })
    callbacks[1]()
    XCTAssertNil(references[1].value)
    callbacks[0]()
    player.previewClick(style: try style(8), volume: 0.5)
    callbacks[0](); callbacks[1]()
    XCTAssertNotNil(references[2].value)
    XCTAssertNotNil(references[3].value)
    callbacks[2]()
    references[3].value?.finish?()
    XCTAssertTrue(references.allSatisfy { $0.value == nil })
  }

  @MainActor func testFailedLoadStartAndSynchronousFinishAreBestEffortAndReleaseMusic() throws {
    for scenario in 0..<3 {
      var reference: WeakVoice?
      let player = TypingFeedbackSound(loadSound: { _ in
        if scenario == 0 { return nil }
        let voice = Voice(); voice.succeeds = scenario != 1; voice.finishesDuringStart = scenario == 2
        reference = WeakVoice(voice); return voice
      }, beep: { XCTFail("music does not fall back to a beep") })
      player.previewClick(style: try style(11), volume: 0.5)
      XCTAssertNil(reference?.value)
      player.clearAllSounds()
    }
  }

  @MainActor func testRepeatedNotesHaveFreshVoicesWithoutAPitchCacheOrVoiceStealing() throws {
    var references: [WeakVoice] = []
    let player = TypingFeedbackSound(loadSound: { _ in
      let voice = Voice(); references.append(WeakVoice(voice)); return voice
    }, beep: {})
    for _ in 0..<256 { player.previewClick(style: try style(8), volume: 0.5) }
    XCTAssertEqual(references.count, 256)
    XCTAssertEqual(Set(references.compactMap { $0.value.map(ObjectIdentifier.init) }).count, 256)
    XCTAssertTrue(references.allSatisfy { $0.value?.starts == 1 && $0.value?.stops == 0 })
    for reference in references { reference.value?.finish?() }
    XCTAssertTrue(references.allSatisfy { $0.value == nil })
  }

  func testExponentialEnvelopeAndScheduledStopsUseSecondsRatherThanShortClickProgress() {
    let key = TypingMusicTone.key(waveform: .sine, semitone: 9, octave: 4)
    let scale = TypingMusicTone.scale(semitone: 9, octave: 4)
    for tone in [key, scale] {
      XCTAssertEqual(tone.sample(at: -0.1), 0)
      XCTAssertEqual(tone.sample(at: tone.duration), 0)
      XCTAssertEqual(tone.sample(at: tone.duration + 1), 0)
      for time in [0.001, 0.01, 0.1, 0.2] {
        XCTAssertEqual(tone.sample(at: time), sin(2 * .pi * 440 * time) * exp(-time / tone.decayTime), accuracy: 1e-12)
      }
    }
    XCTAssertEqual(key.decayTime, 0.15)
    XCTAssertEqual(scale.decayTime, 0.3)
  }

  @MainActor func testActualNativeWAVNotesDecodeAndStayUnplayedWithExpectedDuration() throws {
    for waveform: TypingMusicTone.Waveform in [.sine, .sawtooth, .square, .triangle] {
      let tone = TypingMusicTone.key(waveform: waveform, semitone: 0, octave: 4)
      let data = tone.renderedWAVData()
      XCTAssertEqual(data.count, 44 + 48_000)
      let sound = try XCTUnwrap(NSSound(data: data))
      XCTAssertEqual(sound.duration, 0.5, accuracy: 0.001)
      XCTAssertFalse(sound.isPlaying)
      for time in stride(from: 0.0, to: 0.5, by: 1 / 48_000.0) {
        XCTAssertTrue(tone.sample(at: time).isFinite)
        XCTAssertLessThanOrEqual(abs(tone.sample(at: time)), 1.00001)
      }
    }
    let scale = try XCTUnwrap(NSSound(data: TypingMusicTone.scale(semitone: 0, octave: 6).renderedWAVData()))
    XCTAssertEqual(scale.duration, 2, accuracy: 0.001)
    XCTAssertFalse(scale.isPlaying)
  }

  @MainActor func testActualNativeRemappedInputRecordsPhysicalKeyBeforeEmittingDifferentText() throws {
    let player = TypingFeedbackSound(loadSound: { source in
      XCTAssertEqual(self.pitch(source), 329.63); return Voice()
    }, beep: {})
    let view = TypingInputView(frame: .zero)
    view.keyboardInputMapping = .builtIn(.ansiColemak)
    var inserted: [String] = []
    view.onKeyDown = { key, _, flags, _ in player.recordKeyDown(keyCode: key, modifierFlags: flags) }
    view.onInsert = { text, _ in
      inserted.append(text)
      player.playClick(style: .pianoSine, volume: 0.5)
    }
    let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
      timestamp: 0, windowNumber: 0, context: nil, characters: "e", charactersIgnoringModifiers: "e",
      isARepeat: false, keyCode: 14))
    view.keyDown(with: event)
    XCTAssertEqual(inserted, ["f"])
  }

  func testAllOldSoundValuesAndNewMusicRoundTripWithoutReassigningOldPreferences() throws {
    let oldValues = ["tink", "pop", "ping", "morse", "ember", "drift", "quartz", "ripple", "reed",
      "pebble", "loom", "orbit", "pulse", "velvet", "copper", "frost", "lantern", "meadow", "prism",
      "rain", "slate", "spark", "tide", "willow", "zephyr", "nocturne"]
    for raw in oldValues {
      let snapshot = try JSONDecoder().decode(AppSettingsSnapshot.self, from: Data("{\"clickSoundStyle\":\"\(raw)\"}".utf8))
      XCTAssertEqual(snapshot.clickSoundStyle.rawValue, raw)
      XCTAssertNil(snapshot.clickSoundStyle.musicMode)
    }
    for style in TypingClickSoundStyle.allCases where style.musicMode != nil {
      let original = AppSettingsSnapshot(clickSoundStyle: style)
      XCTAssertEqual(try JSONDecoder().decode(AppSettingsSnapshot.self, from: JSONEncoder().encode(original)), original)
    }
  }
}
