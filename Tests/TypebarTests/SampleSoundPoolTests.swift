import AppKit
import XCTest
@testable import Typebar

@MainActor final class SampleSoundPoolTests: XCTestCase {
  private final class Voice: TypingSoundVoice {
    var volume: Float = 1
    var position = 0.0
    var copies: [Voice] = []
    var rewinds = 0, starts = 0, stops = 0
    var startsSuccessfully = true, finishesDuringStart = false
    var canReuseAfterCompletion = true
    var isPlaying = false
    var completions: [() -> Void] = []
    func copyForPlayback() -> (any TypingSoundVoice)? {
      let voice = Voice(); voice.startsSuccessfully = startsSuccessfully
      voice.finishesDuringStart = finishesDuringStart
      copies.append(voice); return voice
    }
    func rewind() { position = 0; rewinds += 1 }
    func play(onFinish: @escaping () -> Void) -> Bool {
      starts += 1; completions.append(onFinish); position = 0.25; isPlaying = true
      if finishesDuringStart { onFinish() }
      return startsSuccessfully
    }
    func stop() { stops += 1; isPlaying = false }
    func finish() { position = 1; isPlaying = false; completions.last?() }
  }

  func testFinishedSampleReusesItsOwnVoiceFromBeginningWithNewVolume() throws {
    let prototype = Voice()
    let player = TypingFeedbackSound(loadSound:{ _ in prototype },beep:{},randomUnit:{ 0 })
    player.playClick(style:.tink,volume:0.2)
    let first = try XCTUnwrap(prototype.copies.first)
    first.finish()
    player.playClick(style:.tink,volume:0.8)
    XCTAssertEqual(prototype.copies.count,1,"A finished sample must reuse an idle voice, not allocate every key")
    XCTAssertEqual(first.starts,2)
    XCTAssertEqual(first.rewinds,2,"Every sample starts at zero, including reused playback")
    XCTAssertEqual(first.volume,0.8)
  }

  func testOldCompletionCannotReleaseTheSameVoiceInANewerPlayback() throws {
    let prototype = Voice()
    let player = TypingFeedbackSound(loadSound:{ _ in prototype },beep:{},randomUnit:{ 0 })
    player.playError(style:.basso,volume:0.2)
    let voice = try XCTUnwrap(prototype.copies.first), old = try XCTUnwrap(voice.completions.first)
    voice.finish(); player.playError(style:.basso,volume:0.8)
    XCTAssertEqual(prototype.copies.count,1)
    old(); old()
    player.setVolume(0.4)
    XCTAssertEqual(voice.volume,0.4,"A late callback from its prior playback must not remove the reused voice")
    XCTAssertEqual(voice.starts,2)
  }

  func testBurstNeverStealsActiveVoicesAndRetainsAtMostFiveIdlePerResource() {
    let prototype = Voice()
    let player = TypingFeedbackSound(loadSound:{ _ in prototype },beep:{},randomUnit:{ 0 })
    for _ in 0..<32 { player.playClick(style:.tink,volume:0.2) }
    XCTAssertEqual(prototype.copies.count,32)
    XCTAssertTrue(prototype.copies.allSatisfy { $0.stops == 0 && $0.starts == 1 })
    for voice in prototype.copies { voice.finish() }
    for _ in 0..<6 { player.playClick(style:.tink,volume:0.8) }
    XCTAssertEqual(prototype.copies.count,33,"Five idle resources, not an active voice limit")
    XCTAssertEqual(prototype.copies.filter { $0.starts == 2 }.count,5)
    player.setVolume(0.4)
    XCTAssertEqual(prototype.copies.filter { $0.volume == 0.4 }.count,6)
  }

  func testPoolIsSeparatedByExactSampleAndVariantNotJustSoundFamily() throws {
    var prototypes: [TypingClickPlaybackSource:Voice] = [:], draw = 0.0
    let player = TypingFeedbackSound(loadSound:{ source in
      let value = Voice(); prototypes[source] = value; return value
    },beep:{},randomUnit:{ draw })
    player.playClick(style:.tink,volume:0.2)
    let first = try XCTUnwrap(prototypes[.system("Tink")]?.copies.first)
    first.finish(); draw = 0.99; player.playClick(style:.tink,volume:0.2)
    draw = 0; player.playError(style:.basso,volume:0.2)
    player.playClick(style:.tink,volume:0.8)
    XCTAssertEqual(first.starts,2)
    XCTAssertEqual(prototypes.values.flatMap(\.copies).count,3)
    XCTAssertEqual(prototypes[.system("Basso")]?.copies.first?.starts,1)
  }

  func testClearDiscardsStoppedVoicesButKeepsFinishedIdleResourcesAndIgnoresLateCallbacks() throws {
    let prototype = Voice()
    let player = TypingFeedbackSound(loadSound:{ _ in prototype },beep:{},randomUnit:{ 0 })
    player.playClick(style:.tink,volume:0.2); player.playClick(style:.tink,volume:0.2)
    let idle = prototype.copies[0], stopped = prototype.copies[1]
    idle.finish(); player.clearAllSounds()
    XCTAssertEqual(idle.stops,0); XCTAssertEqual(stopped.stops,1)
    player.playClick(style:.tink,volume:0.8)
    stopped.completions.last?(); idle.completions.first?()
    player.setVolume(0.4)
    XCTAssertEqual(prototype.copies.count,2); XCTAssertEqual(idle.starts,2)
    XCTAssertEqual(idle.volume,0.4); XCTAssertEqual(stopped.starts,1)
  }

  func testFinishedWarningAndFinishReuseWithoutStoppingInactiveOrOtherChannels() throws {
    var prototypes: [TypingClickPlaybackSource:Voice] = [:]
    let player = TypingFeedbackSound(loadSound:{ source in
      let value = Voice(); prototypes[source] = value; return value
    },beep:{},randomUnit:{ 0 })
    player.playTimeWarning(style:.glass,volume:0.2)
    let warning = try XCTUnwrap(prototypes[.system("Glass")]?.copies.first)
    warning.finish(); player.playTimeWarning(style:.glass,volume:0.8)
    player.playFinishReverb(volume:0.5)
    let finish = try XCTUnwrap(prototypes[.finishReverb]?.copies.first)
    finish.finish(); player.playFinishReverb(volume:0.8)
    XCTAssertEqual(warning.starts,2); XCTAssertEqual(warning.stops,0)
    XCTAssertEqual(finish.starts,2); XCTAssertEqual(finish.stops,0)
    player.playTimeWarning(style:.glass,volume:0.5)
    XCTAssertEqual(warning.stops,1); XCTAssertEqual(finish.stops,0)
  }

  func testFailedStartAndFailedCompletionAreNotCachedEvenAfterSynchronousCallback() throws {
    for synchronous in [false,true] {
      let prototype = Voice(); prototype.startsSuccessfully = false; prototype.finishesDuringStart = synchronous
      var beeps = 0
      let player = TypingFeedbackSound(loadSound:{ _ in prototype },beep:{ beeps += 1 },randomUnit:{ 0 })
      player.playError(style:.basso,volume:0.2)
      prototype.startsSuccessfully = true; prototype.finishesDuringStart = false
      player.playError(style:.basso,volume:0.2)
      XCTAssertEqual(prototype.copies.count,2); XCTAssertEqual(beeps,1)
      let voice = try XCTUnwrap(prototype.copies.last)
      voice.canReuseAfterCompletion = false; voice.finish()
      player.playError(style:.basso,volume:0.2)
      XCTAssertEqual(prototype.copies.count,3)
    }
  }

  func testNativeCompletionIsOneShotBoundToSoundAndCanBeInvalidatedWithoutPlayingAudio() throws {
    let sound = try XCTUnwrap(NSSound(named:NSSound.Name("Tink")))
    let other = try XCTUnwrap(sound.copy() as? NSSound)
    var flags: [Bool] = []
    let first = NativeTypingSoundCompletion(sound:sound) { flags.append($0) }
    first.sound(other,didFinishPlaying:true); XCTAssertTrue(flags.isEmpty)
    first.sound(sound,didFinishPlaying:true); first.sound(sound,didFinishPlaying:false)
    XCTAssertEqual(flags,[true])
    let canceled = NativeTypingSoundCompletion(sound:sound) { flags.append($0) }
    canceled.invalidate(); canceled.sound(sound,didFinishPlaying:true)
    XCTAssertEqual(flags,[true]); XCTAssertFalse(sound.isPlaying)
  }

  func testActualNativeRewindResetsExistingSoundWithoutCopyOrPlayback() throws {
    let sound = try XCTUnwrap(NSSound(named:NSSound.Name("Tink")))
    let copy = try XCTUnwrap(sound.copy() as? NSSound), voice = NativeTypingSoundVoice(sound:copy)
    copy.currentTime = copy.duration/2
    voice.rewind()
    XCTAssertTrue(voice.sound === copy); XCTAssertEqual(copy.currentTime,0)
    XCTAssertFalse(copy.isPlaying); XCTAssertFalse(voice.canReuseAfterCompletion)
  }

  func testPinnedHowlerPlayEndResetAndPoolDrainSequencesMatchNativeAllocationBehavior() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let reference = environment["TYPEBAR_REFERENCE_ROOT"], let archive = environment["TYPEBAR_HOWLER_SOURCE_ARCHIVE"] else {
      throw XCTSkip("Requires pinned reference and verified QA-only Howler archive")
    }
    struct Step: Decodable { let kind:String; let source:String?; let index:Int?; let reused:Bool?; let seek:Double?; let active:Int }
    struct Fixture: Decodable { let steps:[Step]; let allocations:Int }
    let project = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath:"/usr/bin/env")
    process.arguments = ["node",project.appendingPathComponent("Scripts/check-source-sample-sound-pool.mjs").path,reference,archive,"--emit-fixtures"]
    process.standardOutput = output; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); XCTAssertEqual(process.terminationStatus,0)
    let fixtures = try JSONDecoder().decode([Fixture].self,from:data)
    XCTAssertEqual(fixtures.count,5)
    for fixture in fixtures {
      var prototypes: [Voice] = [], played: [Voice] = []
      let player = TypingFeedbackSound(loadSound:{ _ in
        let value = Voice(); prototypes.append(value); return value
      },beep:{ XCTFail("source fixture should not fail") },randomUnit:{ 0 })
      for step in fixture.steps {
        if step.kind == "play" {
          let before = Dictionary(uniqueKeysWithValues:prototypes.flatMap(\.copies).map { (ObjectIdentifier($0),$0.starts) })
          switch step.source {
          case "click": player.playClick(style:.tink,volume:0.5)
          case "error": player.playError(style:.basso,volume:0.5)
          case "warning": player.playTimeWarning(style:.glass,volume:0.5)
          case "finish": player.playFinishReverb(volume:0.5)
          default: XCTFail("unexpected fixture source")
          }
          let voice = try XCTUnwrap(prototypes.flatMap(\.copies).first { $0.starts > (before[ObjectIdentifier($0)] ?? 0) })
          XCTAssertEqual(before[ObjectIdentifier(voice)] != nil,step.reused)
          XCTAssertEqual(voice.rewinds,voice.starts)
          XCTAssertEqual(step.seek,0); played.append(voice)
        } else { played[try XCTUnwrap(step.index)].finish() }
        XCTAssertEqual(prototypes.flatMap(\.copies).filter(\.isPlaying).count,step.active)
      }
      XCTAssertEqual(prototypes.flatMap(\.copies).count,fixture.allocations)
    }
  }
}
