import AppKit
import XCTest
@testable import Typebar

@MainActor
final class FinishSoundTests: XCTestCase {
  private final class Voice: TypingSoundVoice {
    var volume: Float = 1
    var copies: [Voice] = []
    var starts = 0, stops = 0
    var copyAvailable = true, copyAliases = false, startsSuccessfully = true
    var finish: (() -> Void)?
    func copyForPlayback() -> (any TypingSoundVoice)? {
      guard copyAvailable else { return nil }
      if copyAliases { return self }
      let voice = Voice(); voice.startsSuccessfully = startsSuccessfully
      copies.append(voice); return voice
    }
    func play(onFinish: @escaping () -> Void) -> Bool {
      starts += 1; finish = onFinish; return startsSuccessfully
    }
    func stop() { stops += 1 }
  }

  private final class WeakBox<Value: AnyObject> {
    weak var value: Value?
    init(_ value: Value) { self.value = value }
  }

  private final class LifecycleTrace {
    var voices: [WeakBox<LifecycleVoice>] = []
    var completions: [() -> Void] = []
    var finishesDuringStart = false, startsSuccessfully = true
    var stops = 0
  }

  private final class LifecycleVoice: TypingSoundVoice {
    let trace: LifecycleTrace
    var volume: Float = 1
    init(_ trace: LifecycleTrace) { self.trace = trace }
    func copyForPlayback() -> (any TypingSoundVoice)? {
      let voice = LifecycleVoice(trace); trace.voices.append(WeakBox(voice)); return voice
    }
    func play(onFinish: @escaping () -> Void) -> Bool {
      trace.completions.append(onFinish)
      if trace.finishesDuringStart { onFinish() }
      return trace.startsSuccessfully
    }
    func stop() { trace.stops += 1 }
  }

  func testOnlyOfficialSixteenPlaysForEveryStartedFinishOutcomeButNotAbandonmentOrReplay() throws {
    let official = try XCTUnwrap(SoundCommandCatalog.target(for: "sound.playSoundOnClick.16"))
    XCTAssertEqual(official, .click(.frost))
    let allOutcomes: [TestOutcome] = [.active, .completed, .failed, .invalidAFK, .abandoned, .bailedOut]
    for style in TypingClickSoundStyle.allCases {
      for outcome in allOutcomes {
        let expected = style == .frost && [.completed, .failed, .invalidAFK, .bailedOut].contains(outcome)
        XCTAssertEqual(TypingFinishSoundPolicy.shouldPlay(previousOutcome: .active, outcome: outcome,
          hasStarted: true, clickEnabled: true, style: style), expected)
        XCTAssertFalse(TypingFinishSoundPolicy.shouldPlay(previousOutcome: .active, outcome: outcome,
          hasStarted: false, clickEnabled: true, style: style))
        XCTAssertFalse(TypingFinishSoundPolicy.shouldPlay(previousOutcome: .active, outcome: outcome,
          hasStarted: true, clickEnabled: false, style: style))
        XCTAssertFalse(TypingFinishSoundPolicy.shouldPlay(previousOutcome: .completed, outcome: outcome,
          hasStarted: true, clickEnabled: true, style: style))
      }
    }
  }

  func testPracticeFinishRoutesOneCueWithoutPreloadingClicksErrorsOrDrawingRandomness() {
    var loaded: [TypingClickPlaybackSource] = [], voices: [Voice] = []
    let player = TypingFeedbackSound(loadSound: {
      loaded.append($0); let voice = Voice(); voices.append(voice); return voice
    }, beep: { XCTFail("finish never beeps") }, randomUnit: { XCTFail("finish never draws"); return 0 })
    player.setVolume(0.4)
    player.playPracticeFinish(previousOutcome: .active, outcome: .failed, hasStarted: true,
      clickEnabled: true, style: .frost, volume: 0.9)
    XCTAssertEqual(loaded, [.finishReverb])
    XCTAssertEqual(voices.flatMap(\.copies).count, 1)
    XCTAssertEqual(voices.first?.copies.first?.starts, 1)
    XCTAssertEqual(voices.first?.copies.first?.volume, 0.4)
    for outcome in [TestOutcome.failed, .completed, .active, .abandoned] {
      player.playPracticeFinish(previousOutcome: .failed, outcome: outcome, hasStarted: true,
        clickEnabled: true, style: .frost, volume: 0.9)
    }
    XCTAssertEqual(voices.flatMap(\.copies).count, 1)
  }

  func testFinishRestartStopsOnlyPriorFinishAndAllSamplesStopTogetherOnPracticeReset() throws {
    var prototypes: [TypingClickPlaybackSource: Voice] = [:]
    let player = TypingFeedbackSound(loadSound: {
      let voice = Voice(); prototypes[$0] = voice; return voice
    }, beep: {}, randomUnit: { 0 })
    player.setVolume(0.6)
    player.recordKeyDown(keyCode: 12, modifierFlags: [])
    player.playClick(style: .pianoSine, volume: 0.5)
    player.playClick(style: .tink, volume: 0.5)
    player.playError(style: .basso, volume: 0.5)
    player.playTimeWarning(style: .glass, volume: 0.5)
    player.playFinishReverb(volume: 0.5)
    player.playFinishReverb(volume: 0.5)
    let finishes = try XCTUnwrap(prototypes[.finishReverb]?.copies)
    XCTAssertEqual(finishes.count, 2)
    guard finishes.count == 2 else { return }
    XCTAssertEqual(finishes[0].stops, 1)
    XCTAssertEqual(finishes[1].stops, 0)
    let click = try XCTUnwrap(prototypes[.system("Tink")]?.copies.first)
    let error = try XCTUnwrap(prototypes[.system("Basso")]?.copies.first)
    let warning = try XCTUnwrap(prototypes[.system("Glass")]?.copies.first)
    XCTAssertTrue([click, error, warning].allSatisfy { $0.stops == 0 })
    player.setVolume(0)
    XCTAssertTrue([click, error, warning, finishes[1]].allSatisfy { $0.volume == 0 })
    player.setVolume(0.2)
    XCTAssertEqual(finishes[0].volume, 0.6)
    XCTAssertTrue([click, error, warning, finishes[1]].allSatisfy { $0.volume == 0.2 })
    finishes[0].finish?()
    player.beginPracticeAttempt()
    XCTAssertEqual(finishes[0].stops, 1)
    XCTAssertTrue([click, error, warning, finishes[1]].allSatisfy { $0.stops == 1 })
    player.playFinishReverb(volume: 0.9)
    XCTAssertEqual(prototypes[.finishReverb]?.copies.count, 3)
    finishes[1].finish?()
    XCTAssertEqual(prototypes[.finishReverb]?.copies.last?.stops, 0)
    let music = prototypes.filter { if case .musical = $0.key { return true }; return false }.values
    XCTAssertTrue(music.allSatisfy { $0.starts == 1 && $0.stops == 0 && abs($0.volume - 0.06) < 0.0001 })
  }

  func testActualCompletedFailedBailedAndAFKSessionsRouteFinishBeforePersistenceEligibility() throws {
    let start = Date(timeIntervalSinceReferenceDate: 894_100_000)
    for expected in [TestOutcome.completed, .failed, .bailedOut, .invalidAFK, .abandoned] {
      var input = TypingSession(configuration: .timed(seconds: 10), prompt: "ab cd")
      input.insert("a", at: start)
      let previous = input.outcome
      switch expected {
      case .completed: input.insertBatch("b cd", at: start.addingTimeInterval(9)); input.tick(at: start.addingTimeInterval(10))
      case .failed: input.failForTimerHealth(at: start.addingTimeInterval(1))
      case .bailedOut: input.bailOut(at: start.addingTimeInterval(1))
      case .invalidAFK: input.tick(at: start.addingTimeInterval(10))
      case .abandoned: input.abandon(at: start.addingTimeInterval(1))
      case .active: XCTFail("invalid test scenario")
      }
      XCTAssertEqual(input.outcome, expected)
      let before = try XCTUnwrap(input.result(at: start.addingTimeInterval(10)))
      let encoded = try JSONEncoder().encode(before)
      var loaded: [TypingClickPlaybackSource] = [], prototypes: [Voice] = []
      let player = TypingFeedbackSound(loadSound: {
        loaded.append($0); let voice = Voice(); prototypes.append(voice); return voice
      }, beep: {}, randomUnit: { 0 })
      player.playPracticeFinish(previousOutcome: previous, outcome: input.outcome, hasStarted: input.hasStarted,
        clickEnabled: true, style: .frost, volume: 0.5)
      XCTAssertEqual(loaded, expected == .abandoned ? [] : [.finishReverb])
      XCTAssertEqual(prototypes.flatMap(\.copies).count, expected == .abandoned ? 0 : 1)
      let after = try XCTUnwrap(input.result(at: start.addingTimeInterval(10)))
      var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(after)) as? [String: Any])
      // result() generates a fresh identity; compare all actual result fields,
      // not JSON dictionary order or that unrelated factory identity.
      fields["id"] = before.id.uuidString
      let normalized = try JSONDecoder().decode(CompletedTestResult.self,
        from: JSONSerialization.data(withJSONObject: fields))
      XCTAssertEqual(normalized, try JSONDecoder().decode(CompletedTestResult.self, from: encoded))
      let cues = TypingReplay.soundTimeline(prompt: before.prompt, events: before.replayEvents, configuration: before.configuration)
      XCTAssertTrue(cues.allSatisfy { $0.cue == .click || $0.cue == .error })
      XCTAssertEqual(prototypes.flatMap(\.copies).count, expected == .abandoned ? 0 : 1)
    }
  }

  func testCurrentSettingsAtFinishChooseCueAndClickAuditionNeverTriggersIt() throws {
    let suite = "TypebarTests.FinishSelection.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var prototypes: [TypingClickPlaybackSource: Voice] = [:]
    let player = TypingFeedbackSound(loadSound: {
      let voice = Voice(); prototypes[$0] = voice; return voice
    }, beep: {}, randomUnit: { 0 })
    let settings = AppSettings(defaults: defaults, feedbackSound: player)
    SoundCommandTarget.click(.frost).apply(to: settings)
    player.previewClick(style: .frost, volume: settings.soundVolume)
    XCTAssertNil(prototypes[.finishReverb])
    SoundCommandTarget.click(.tink).apply(to: settings)
    player.playPracticeFinish(previousOutcome: .active, outcome: .completed, hasStarted: true,
      clickEnabled: settings.playKeyclickSound, style: settings.clickSoundStyle, volume: settings.soundVolume)
    XCTAssertNil(prototypes[.finishReverb])
    settings.clickSoundStyle = .frost
    settings.playKeyclickSound = false
    player.playPracticeFinish(previousOutcome: .active, outcome: .completed, hasStarted: true,
      clickEnabled: settings.playKeyclickSound, style: settings.clickSoundStyle, volume: settings.soundVolume)
    XCTAssertNil(prototypes[.finishReverb])
    settings.playKeyclickSound = true
    player.playPracticeFinish(previousOutcome: .active, outcome: .invalidAFK, hasStarted: true,
      clickEnabled: settings.playKeyclickSound, style: settings.clickSoundStyle, volume: settings.soundVolume)
    XCTAssertEqual(prototypes[.finishReverb]?.copies.count, 1)
  }

  func testOwnedBurstHasDeterministicDecayingWetTailAndNativeCopiesRemainUnplayed() throws {
    let samples = TypingFinishReverbSound.samples()
    XCTAssertEqual(samples.count, 35_280)
    XCTAssertEqual(samples, TypingFinishReverbSound.samples())
    XCTAssertTrue(samples.allSatisfy { $0.isFinite && abs($0) < 1 })
    XCTAssertEqual(samples[0], 0)
    func rms(from lower: Double, to upper: Double) -> Double {
      let frames = samples[Int(lower * 22_050)..<Int(upper * 22_050)]
      return sqrt(frames.reduce(0) { $0 + $1 * $1 } / Double(frames.count))
    }
    let dry = rms(from: 0.01, to: 0.15)
    let earlyTail = rms(from: 0.35, to: 0.55)
    let lateTail = rms(from: 1.1, to: 1.3)
    XCTAssertGreaterThan(dry, 0.01)
    XCTAssertGreaterThan(earlyTail, 0.00001)
    XCTAssertGreaterThan(lateTail, 0)
    XCTAssertLessThan(earlyTail, dry)
    XCTAssertLessThan(lateTail, earlyTail)
    XCTAssertLessThan(abs(try XCTUnwrap(samples.last)), 1 / Double(Int16.max))
    let data = TypingFinishReverbSound.renderedWAVData()
    XCTAssertEqual(data.count, 70_604)
    XCTAssertEqual(data, TypingFinishReverbSound.renderedWAVData())
    XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF")
    XCTAssertEqual(String(data: data[8..<12], encoding: .ascii), "WAVE")
    let sound = try XCTUnwrap(NSSound(data: data))
    XCTAssertEqual(sound.duration, 1.6, accuracy: 1 / 22_050)
    let prototype = NativeTypingSoundVoice(sound: sound)
    let first = try XCTUnwrap(prototype.copyForPlayback() as? NativeTypingSoundVoice)
    let second = try XCTUnwrap(prototype.copyForPlayback() as? NativeTypingSoundVoice)
    XCTAssertFalse(first.sound === second.sound)
    XCTAssertFalse(sound === first.sound)
    for candidate in [sound, first.sound, second.sound] {
      XCTAssertEqual(candidate.currentTime, 0)
      XCTAssertFalse(candidate.isPlaying)
      XCTAssertFalse(candidate.loops)
    }
    first.volume = 0.2
    XCTAssertEqual(second.volume, sound.volume)
  }

  func testUnavailableLoadCopyAliasAndFailedStartNeverBeepOrStealOtherChannels() throws {
    for scenario in 0..<4 {
      var unavailable = true, loads = 0
      let finishPrototype = Voice(), warningPrototype = Voice()
      let player = TypingFeedbackSound(loadSound: { source in
        guard source == .finishReverb else { return warningPrototype }
        loads += 1
        if scenario == 0 && unavailable { return nil }
        finishPrototype.copyAvailable = !(scenario == 1 && unavailable)
        finishPrototype.copyAliases = scenario == 2 && unavailable
        finishPrototype.startsSuccessfully = !(scenario == 3 && unavailable)
        return finishPrototype
      }, beep: { XCTFail("finish never beeps") }, randomUnit: { 0 })
      player.setVolume(0.5)
      player.playTimeWarning(style: .glass, volume: 0.5)
      let warning = try XCTUnwrap(warningPrototype.copies.first)
      player.playFinishReverb(volume: 0.5)
      XCTAssertEqual(warning.stops, 0)
      XCTAssertEqual(finishPrototype.starts, 0)
      let failed = finishPrototype.copies.first
      unavailable = false
      finishPrototype.copyAvailable = true
      finishPrototype.copyAliases = false
      finishPrototype.startsSuccessfully = true
      player.playFinishReverb(volume: 0.5)
      XCTAssertEqual(loads, scenario == 0 ? 2 : 1)
      let newest = try XCTUnwrap(finishPrototype.copies.last)
      XCTAssertEqual(newest.starts, 1)
      XCTAssertEqual(newest.stops, 0)
      failed?.finish?()
      player.setVolume(0.2)
      XCTAssertEqual(newest.volume, 0.2)
      XCTAssertEqual(warning.volume, 0.2)
      player.clearAllSounds()
      XCTAssertEqual(newest.stops, 1)
      XCTAssertEqual(warning.stops, 1)
    }
  }

  func testMutedFinishStillStartsAndCanUnmuteWithoutReloadingOrRestarting() throws {
    let prototype = Voice()
    var sources: [TypingClickPlaybackSource] = []
    let player = TypingFeedbackSound(loadSound: { sources.append($0); return prototype },
      beep: { XCTFail("no beep") }, randomUnit: { XCTFail("no draw"); return 0 })
    player.setVolume(0)
    player.playPracticeFinish(previousOutcome: .active, outcome: .bailedOut, hasStarted: true,
      clickEnabled: true, style: .frost, volume: 0.8)
    let voice = try XCTUnwrap(prototype.copies.first)
    XCTAssertEqual(voice.volume, 0)
    XCTAssertEqual(voice.starts, 1)
    player.setVolume(0.7)
    XCTAssertEqual(voice.volume, 0.7)
    XCTAssertEqual(voice.starts, 1)
    XCTAssertEqual(voice.stops, 0)
    player.beginPracticeAttempt()
    player.playFinishReverb(volume: 0.1)
    XCTAssertEqual(sources, [.finishReverb])
    XCTAssertEqual(prototype.copies.last?.volume, 0.7)
  }

  func testFinishCompletionResetAndControllerDeallocationReleaseVoicesDespiteLateCallbacks() throws {
    let trace = LifecycleTrace()
    var loads = 0
    var player: TypingFeedbackSound? = TypingFeedbackSound(loadSound: { _ in
      loads += 1; return LifecycleVoice(trace)
    }, beep: {}, randomUnit: { 0 })
    let controller = WeakBox(try XCTUnwrap(player))
    player?.playFinishReverb(volume: 0.5)
    XCTAssertNotNil(trace.voices[0].value)
    trace.completions[0]()
    XCTAssertNil(trace.voices[0].value)
    player?.playFinishReverb(volume: 0.5)
    trace.completions[0]()
    XCTAssertNotNil(trace.voices[1].value)
    player?.beginPracticeAttempt()
    XCTAssertNil(trace.voices[1].value)
    XCTAssertEqual(trace.stops, 1)
    player?.playFinishReverb(volume: 0.5)
    trace.completions[1]()
    XCTAssertNotNil(trace.voices[2].value)
    XCTAssertEqual(loads, 1)
    player = nil
    XCTAssertNil(controller.value)
    XCTAssertTrue(trace.voices.allSatisfy { $0.value == nil })
    for callback in trace.completions { callback() }
  }

  func testSynchronousFinishAndFailedStartNeverRetainFinishVoicesOrResurrectThem() {
    for synchronousFinish in [false, true] {
      let trace = LifecycleTrace()
      trace.finishesDuringStart = synchronousFinish
      trace.startsSuccessfully = synchronousFinish
      let player = TypingFeedbackSound(loadSound: { _ in LifecycleVoice(trace) }, beep: {}, randomUnit: { 0 })
      player.playFinishReverb(volume: 0.5)
      XCTAssertEqual(trace.voices.count, 1)
      XCTAssertNil(trace.voices.first?.value)
      player.clearAllSounds()
      XCTAssertEqual(trace.stops, 0)
      for callback in trace.completions { callback() }
      XCTAssertNil(trace.voices.first?.value)
    }
  }
}
