import AppKit
import XCTest
@testable import Typebar

/// Only the unstable audio-device boundary is stubbed. Every request goes
/// through the production sound controller, not a parallel voice model.
final class FeedbackSoundVoiceTests: XCTestCase {
  private func assertUnchangedResult(_ input: TypingSession, _ before: CompletedTestResult,
    file: StaticString = #filePath, line: UInt = #line) throws {
    let after = try XCTUnwrap(input.result(), file: file, line: line)
    var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(after))
      as? [String: Any], file: file, line: line)
    // Each result() call intentionally assigns a fresh UUID; compare every
    // other field without treating that factory behavior as playback mutation.
    fields["id"] = before.id.uuidString
    let normalized = try JSONDecoder().decode(CompletedTestResult.self,
      from: JSONSerialization.data(withJSONObject: fields))
    XCTAssertEqual(normalized, before, file: file, line: line)
  }
  private final class WeakSound {
    weak var value: RecordingSound?
    init(_ value: RecordingSound) { self.value = value }
  }

  private final class Trace {
    enum CopyMode { case independent, unavailable, alias }
    var voices: [WeakSound] = []
    var volumes: [Float] = []
    var stops = 0
    var starts = 0
    var succeeds = true
    var copies = 0
    var copyMode = CopyMode.independent
    var completions: [() -> Void] = []
    var finishesDuringStart = false
    var completesOnStop = false
  }

  @MainActor private final class RecordingSound: TypingSoundVoice {
    let trace: Trace
    var volume: Float = 0.4
    var started = false
    var playCount = 0
    private var onFinish: (() -> Void)?

    init(_ trace: Trace) { self.trace = trace }

    func copyForPlayback() -> (any TypingSoundVoice)? {
      trace.copies += 1
      switch trace.copyMode {
      case .independent: return RecordingSound(trace)
      case .unavailable: return nil
      case .alias: return self
      }
    }

    func play(onFinish: @escaping () -> Void) -> Bool {
      self.onFinish = onFinish
      playCount += 1
      trace.starts += 1
      trace.volumes.append(volume)
      trace.voices.append(WeakSound(self))
      trace.completions.append(onFinish)
      started = trace.succeeds
      if trace.finishesDuringStart { finish(true) }
      return started
    }

    func finish(_ success: Bool) {
      started = false
      let finished = onFinish
      onFinish = nil
      finished?()
    }

    func stop() {
      trace.stops += 1
      started = false
      if trace.completesOnStop { finish(false) }
    }
  }

  @MainActor func testThreeSameTickClicksHaveIndependentVoicesAndVolumes() {
    let trace = Trace()
    let prototype = RecordingSound(trace)
    var loads = 0
    let player = TypingFeedbackSound(loadSound: { _ in loads += 1; return prototype }, beep: {})
    for volume in [0.2, 0.6, 1.0] { player.playClick(style: .tink, volume: volume) }
    XCTAssertEqual(loads, 1)
    XCTAssertEqual(trace.starts, 3)
    XCTAssertEqual(trace.stops, 0)
    XCTAssertEqual(prototype.playCount, 0)
    XCTAssertEqual(trace.volumes, [0.2, 0.6, 1])
    XCTAssertEqual(Set(trace.voices.compactMap { $0.value.map(ObjectIdentifier.init) }).count, 3)
    XCTAssertTrue(trace.voices.allSatisfy { $0.value?.started == true })
  }

  @MainActor func testConsecutiveErrorVoicesDoNotRestartEachOther() {
    let trace = Trace()
    let prototype = RecordingSound(trace)
    var beeps = 0
    let player = TypingFeedbackSound(loadSound: { _ in prototype }, beep: { beeps += 1 })
    player.playError(style: .basso, volume: 0.25)
    player.playError(style: .basso, volume: 0.75)
    XCTAssertEqual(trace.stops, 0)
    XCTAssertEqual(Set(trace.voices.compactMap { $0.value.map(ObjectIdentifier.init) }).count, 2)
    XCTAssertEqual(trace.voices.first?.value?.volume, 0.25)
    XCTAssertEqual(beeps, 0)
  }

  @MainActor func testMixedHardRecoveryKeepsAllFourSoundsAlive() {
    let click = Trace()
    let error = Trace()
    let clickPrototype = RecordingSound(click)
    let errorPrototype = RecordingSound(error)
    let player = TypingFeedbackSound(loadSound: {
      $0 == .system("Basso") ? errorPrototype : clickPrototype
    }, beep: {})
    for cue in [TypingReplaySoundCue.error, .error, .click, .click] {
      if cue == .error { player.playError(style: .basso, volume: 0.5) }
      else { player.playClick(style: .tink, volume: 0.5) }
    }
    XCTAssertEqual(click.stops + error.stops, 0)
    let voices = (click.voices + error.voices).compactMap { $0.value }
    XCTAssertEqual(Set(voices.map(ObjectIdentifier.init)).count, 4)
    XCTAssertTrue(voices.allSatisfy { $0.started })
  }

  @MainActor func testSuccessfulCompletionReleasesOnlyTheFinishedVoice() {
    let trace = Trace()
    let prototype = RecordingSound(trace)
    let player = TypingFeedbackSound(loadSound: { _ in prototype }, beep: {})
    player.playClick(style: .quartz, volume: 0.5)
    player.playClick(style: .quartz, volume: 0.5)
    trace.voices[1].value?.finish(true)
    XCTAssertNil(trace.voices[1].value)
    XCTAssertNotNil(trace.voices[0].value)
    XCTAssertTrue(trace.voices[0].value?.started == true)
    trace.voices[0].value?.finish(true)
    XCTAssertNil(trace.voices[0].value)
    XCTAssertEqual(trace.stops, 0)
  }

  @MainActor func testUnsuccessfulCompletionAlsoReleasesItsVoice() {
    let trace = Trace()
    let prototype = RecordingSound(trace)
    let player = TypingFeedbackSound(loadSound: { _ in prototype }, beep: {})
    player.playError(style: .funk, volume: 0.5)
    trace.voices[0].value?.finish(false)
    XCTAssertNil(trace.voices[0].value)
    XCTAssertEqual(prototype.playCount, 0)
  }

  @MainActor func testFailedStartDoesNotRetainAVoiceAndAllowsLaterPlayback() {
    let trace = Trace()
    trace.succeeds = false
    let prototype = RecordingSound(trace)
    var beeps = 0
    let player = TypingFeedbackSound(loadSound: { _ in prototype }, beep: { beeps += 1 })
    player.playError(style: .sosumi, volume: 0.5)
    XCTAssertNil(trace.voices[0].value)
    XCTAssertEqual(beeps, 1)
    trace.succeeds = true
    player.playError(style: .sosumi, volume: 0.5)
    XCTAssertNotNil(trace.voices[1].value)
    XCTAssertEqual(beeps, 1)
    XCTAssertEqual(trace.stops, 0)
  }

  @MainActor func testWarningRestartStopsOnlyThePreviousWarningEvenAcrossStyles() {
    var traces: [TypingClickPlaybackSource: Trace] = [:]
    let player = TypingFeedbackSound(loadSound: { source in
      let trace = Trace()
      traces[source] = trace
      return RecordingSound(trace)
    }, beep: {})
    player.playClick(style: .tink, volume: 0.5)
    player.playError(style: .basso, volume: 0.5)
    player.playTimeWarning(style: .glass, volume: 0.5)
    player.playTimeWarning(style: .hero, volume: 0.5)
    XCTAssertEqual(traces[.system("Tink")]?.stops, 0)
    XCTAssertEqual(traces[.system("Basso")]?.stops, 0)
    XCTAssertEqual(traces[.system("Glass")]?.stops, 1)
    XCTAssertEqual(traces[.system("Hero")]?.stops, 0)
    XCTAssertNil(traces[.system("Glass")]?.voices[0].value)
    XCTAssertTrue(traces[.system("Hero")]?.voices[0].value?.started == true)
  }

  @MainActor func testDuplicateAndLateCompletionCannotReleaseANewerVoice() {
    let trace = Trace()
    let prototype = RecordingSound(trace)
    let player = TypingFeedbackSound(loadSound: { _ in prototype }, beep: {})
    player.playTimeWarning(style: .glass, volume: 0.5)
    player.playTimeWarning(style: .glass, volume: 0.5)
    trace.completions[0]()
    trace.completions[0]()
    XCTAssertNil(trace.voices[0].value)
    XCTAssertTrue(trace.voices[1].value?.started == true)
    trace.voices[1].value?.finish(true)
    player.playTimeWarning(style: .glass, volume: 0.5)
    trace.completions[1]()
    XCTAssertTrue(trace.voices[2].value?.started == true)
    XCTAssertEqual(trace.stops, 1)
  }

  @MainActor func testCompletionDuringStartDoesNotResurrectTheFinishedVoice() {
    let trace = Trace()
    trace.finishesDuringStart = true
    let prototype = RecordingSound(trace)
    let player = TypingFeedbackSound(loadSound: { _ in prototype }, beep: {})
    player.playClick(style: .ember, volume: 0.5)
    XCTAssertEqual(trace.starts, 1)
    XCTAssertNil(trace.voices[0].value)
    XCTAssertEqual(trace.stops, 0)
  }

  @MainActor func testCallbacksDoNotKeepTheControllerOrFinishedVoicesAlive() {
    let trace = Trace()
    let prototype = RecordingSound(trace)
    var player: TypingFeedbackSound? = TypingFeedbackSound(loadSound: { _ in prototype }, beep: {})
    weak var weakPlayer = player
    player?.playClick(style: .pop, volume: 0.5)
    player = nil
    XCTAssertNil(weakPlayer)
    XCTAssertNil(trace.voices[0].value)
    trace.completions[0]()
    XCTAssertEqual(trace.stops, 0)
  }

  @MainActor func testMutedAndNonPositiveRequestsDoNotLoadCopyStopOrBeep() {
    let trace = Trace()
    let prototype = RecordingSound(trace)
    var loads = 0
    var beeps = 0
    let player = TypingFeedbackSound(loadSound: { _ in loads += 1; return prototype }, beep: { beeps += 1 })
    player.playTimeWarning(style: .glass, volume: 0.5)
    for volume in [0.0, -1, -Double.infinity, Double.nan] {
      player.playClick(style: .pop, volume: volume)
      player.playError(style: .basso, volume: volume)
      player.playTimeWarning(style: .hero, volume: volume)
    }
    XCTAssertEqual(loads, 1)
    XCTAssertEqual(trace.copies, 1)
    XCTAssertEqual(trace.starts, 1)
    XCTAssertEqual(trace.stops, 0)
    XCTAssertEqual(beeps, 0)
    XCTAssertTrue(trace.voices[0].value?.started == true)
  }

  @MainActor func testUnavailableOrAliasedCopyNeverPlaysThePrototype() {
    for copyMode in [Trace.CopyMode.unavailable, .alias] {
      let trace = Trace()
      trace.copyMode = copyMode
      let prototype = RecordingSound(trace)
      var beeps = 0
      let player = TypingFeedbackSound(loadSound: { _ in prototype }, beep: { beeps += 1 })
      player.playClick(style: .tink, volume: 0.5)
      player.playError(style: .funk, volume: 0.5)
      player.playTimeWarning(style: .glass, volume: 0.5)
      XCTAssertEqual(trace.starts, 0)
      XCTAssertEqual(trace.stops, 0)
      XCTAssertEqual(prototype.playCount, 0)
      XCTAssertEqual(beeps, 2)
    }
  }

  @MainActor func testFailedLoadsRetryWithoutChangingExistingVoices() {
    let trace = Trace()
    let prototype = RecordingSound(trace)
    var available = false
    var loads = 0
    var beeps = 0
    let player = TypingFeedbackSound(loadSound: { _ in
      loads += 1
      return available ? prototype : nil
    }, beep: { beeps += 1 })
    player.playError(style: .basso, volume: 0.5)
    available = true
    player.playError(style: .basso, volume: 0.5)
    player.playError(style: .basso, volume: 0.5)
    XCTAssertEqual(loads, 2)
    XCTAssertEqual(beeps, 1)
    XCTAssertEqual(trace.starts, 2)
    XCTAssertEqual(trace.stops, 0)
    XCTAssertEqual(Set(trace.voices.compactMap { $0.value.map(ObjectIdentifier.init) }).count, 2)
  }

  @MainActor func testVolumeClampAndAllNativeStylesKeepTheirPlaybackSources() {
    var sources: [TypingClickPlaybackSource] = []
    let trace = Trace()
    let player = TypingFeedbackSound(loadSound: { source in
      sources.append(source)
      return RecordingSound(trace)
    }, beep: {})
    for style in TypingClickSoundStyle.allCases {
      player.playClick(style: style, volume: 2)
      player.playClick(style: style, volume: Double.infinity)
    }
    for style in TypingErrorSoundStyle.allCases { player.playError(style: style, volume: 0.5) }
    for style in TimeWarningSoundStyle.allCases { player.playTimeWarning(style: style, volume: 0.5) }
    XCTAssertEqual(Array(sources.prefix(26)), TypingClickSoundStyle.allCases.map(\.playbackSource))
    XCTAssertEqual(sources.count, 34)
    XCTAssertEqual(trace.starts, 60)
    XCTAssertEqual(Array(trace.volumes.prefix(52)), Array(repeating: 1, count: 52))
    XCTAssertEqual(trace.stops, 3)
    XCTAssertEqual(trace.voices.filter { $0.value != nil }.count, 57)
  }

  @MainActor func testBurstLargerThanAnIdlePoolDoesNotStealActiveVoices() {
    let trace = Trace()
    let prototype = RecordingSound(trace)
    var loads = 0
    let player = TypingFeedbackSound(loadSound: { _ in loads += 1; return prototype }, beep: {})
    for _ in 0..<256 { player.playClick(style: .quartz, volume: 0.5) }
    XCTAssertEqual(loads, 1)
    XCTAssertEqual(trace.starts, 256)
    XCTAssertEqual(trace.stops, 0)
    XCTAssertEqual(Set(trace.voices.compactMap { $0.value.map(ObjectIdentifier.init) }).count, 256)
    for index in trace.voices.indices.reversed() { trace.voices[index].value?.finish(true) }
    XCTAssertTrue(trace.voices.allSatisfy { $0.value == nil })
  }

  @MainActor func testActualSynthesizedNSSoundCopiesAreDistinctAndResetPlaybackWithoutPlaying() throws {
    var count = 0
    for style in TypingClickSoundStyle.allCases {
      guard case .synthesized(let profile) = style.playbackSource else { continue }
      let sound = try XCTUnwrap(NSSound(data: profile.renderedWAVData()), style.rawValue)
      sound.volume = 0.4
      sound.currentTime = profile.duration / 2
      sound.loops = true
      let prototype = NativeTypingSoundVoice(sound: sound)
      let first = try XCTUnwrap(prototype.copyForPlayback() as? NativeTypingSoundVoice)
      let second = try XCTUnwrap(prototype.copyForPlayback() as? NativeTypingSoundVoice)
      XCTAssertFalse(first.sound === sound)
      XCTAssertFalse(second.sound === sound)
      XCTAssertFalse(first.sound === second.sound)
      XCTAssertEqual(first.sound.currentTime, 0)
      XCTAssertFalse(first.sound.loops)
      first.volume = 0.8
      XCTAssertEqual(second.volume, 0.4, accuracy: 0.001)
      XCTAssertEqual(sound.volume, 0.4, accuracy: 0.001)
      XCTAssertFalse(sound.isPlaying)
      XCTAssertFalse(first.sound.isPlaying)
      XCTAssertFalse(second.sound.isPlaying)
      count += 1
    }
    XCTAssertEqual(count, 22)
  }

  @MainActor func testActualSystemSoundCopiesAreIndependentWithoutPlaying() throws {
    for name in ["Tink", "Pop", "Ping", "Morse", "Basso", "Funk", "Sosumi", "Submarine",
      "Glass", "Hero", "Bottle", "Frog"] {
      let sound = try XCTUnwrap(NSSound(named: NSSound.Name(name)), name)
      let prototype = NativeTypingSoundVoice(sound: sound)
      let first = try XCTUnwrap(prototype.copyForPlayback() as? NativeTypingSoundVoice)
      let second = try XCTUnwrap(prototype.copyForPlayback() as? NativeTypingSoundVoice)
      XCTAssertFalse(first.sound === sound)
      XCTAssertFalse(first.sound === second.sound)
      first.volume = 0.25
      second.volume = 0.75
      XCTAssertEqual(first.volume, 0.25, accuracy: 0.001)
      XCTAssertFalse(sound.isPlaying)
      XCTAssertFalse(first.sound.isPlaying)
      XCTAssertFalse(second.sound.isPlaying)
    }
  }

  @MainActor func testSynchronousStopCompletionCannotClearTheReplacementWarning() {
    let trace = Trace()
    trace.completesOnStop = true
    let prototype = RecordingSound(trace)
    let player = TypingFeedbackSound(loadSound: { _ in prototype }, beep: {})
    player.playTimeWarning(style: .glass, volume: 0.5)
    player.playTimeWarning(style: .glass, volume: 0.5)
    XCTAssertNil(trace.voices[0].value)
    XCTAssertTrue(trace.voices[1].value?.started == true)
    XCTAssertEqual(trace.stops, 1)
  }

  @MainActor func testFailedWarningRestartKeepsClickVoicesAndDoesNotRetainFailedWarnings() {
    let clicks = Trace()
    let warnings = Trace()
    let clickPrototype = RecordingSound(clicks)
    let warningPrototype = RecordingSound(warnings)
    var beeps = 0
    let player = TypingFeedbackSound(loadSound: {
      $0 == .system("Tink") ? clickPrototype : warningPrototype
    }, beep: { beeps += 1 })
    player.playClick(style: .tink, volume: 0.5)
    player.playTimeWarning(style: .glass, volume: 0.5)
    warnings.succeeds = false
    player.playTimeWarning(style: .hero, volume: 0.5)
    XCTAssertTrue(clicks.voices[0].value?.started == true)
    XCTAssertEqual(clicks.stops, 0)
    XCTAssertNil(warnings.voices[0].value)
    XCTAssertNil(warnings.voices[1].value)
    XCTAssertEqual(warnings.stops, 1)
    XCTAssertEqual(beeps, 1)
  }

  @MainActor func testActualAutomaticIndentTimelineRoutesThreeIndependentClickVoices() throws {
    let start = Date(timeIntervalSinceReferenceDate: 875_200_000)
    var input = TypingSession(configuration: .words(3, language: .codeSwift), prompt: "ab\n\tgo()\ntail")
    input.insertBatch("ab", at: start)
    input.insertBatch("\n", at: start.addingTimeInterval(1))
    input.bailOut(at: start.addingTimeInterval(5))
    let result = try XCTUnwrap(input.result())
    let trace = Trace()
    let prototype = RecordingSound(trace)
    let player = TypingFeedbackSound(loadSound: { _ in prototype }, beep: {})
    let cues = TypingReplay.soundCues(prompt: result.prompt, events: result.replayEvents,
      after: 0.5, through: 1.5, configuration: result.configuration)
    XCTAssertEqual(cues, [.click, .click, .click])
    for cue in cues {
      let route = TypingReplaySoundRoute.resolve(cue: cue, playsClicks: true, playsErrors: true)
      XCTAssertEqual(route, .click)
      if route == .click { player.playClick(style: .quartz, volume: 0.5) }
    }
    XCTAssertEqual(Set(trace.voices.compactMap { $0.value.map(ObjectIdentifier.init) }).count, 3)
    XCTAssertEqual(trace.stops, 0)
    try assertUnchangedResult(input, result)
  }

  @MainActor func testActualHardRecoveryTimelineRoutesFourVoicesAndPreservesTheResult() throws {
    let start = Date(timeIntervalSinceReferenceDate: 875_200_000)
    var input = TypingSession(configuration: .words(2, rules: .init(deleteOnErrorMode: .wordHard)), prompt: "ab cd")
    input.insertBatch("ab ", at: start)
    input.insertBatch("x", at: start.addingTimeInterval(1))
    input.bailOut(at: start.addingTimeInterval(5))
    let result = try XCTUnwrap(input.result())
    for playsErrors in [true, false] {
      let trace = Trace()
      let player = TypingFeedbackSound(loadSound: { _ in RecordingSound(trace) }, beep: {})
      let cues = TypingReplay.soundCues(prompt: result.prompt, events: result.replayEvents,
        after: 0.5, through: 1.5, configuration: result.configuration)
      XCTAssertEqual(cues, [.error, .error, .click, .click])
      for cue in cues {
        switch TypingReplaySoundRoute.resolve(cue: cue, playsClicks: true, playsErrors: playsErrors) {
        case .click: player.playClick(style: .tink, volume: 0.5)
        case .error: player.playError(style: .basso, volume: 0.5)
        case .none: XCTFail("Expected enabled feedback or click fallback")
        }
      }
      XCTAssertEqual(Set(trace.voices.compactMap { $0.value.map(ObjectIdentifier.init) }).count, 4)
      XCTAssertEqual(trace.stops, 0)
      try assertUnchangedResult(input, result)
    }
  }
}
