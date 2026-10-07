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
      starts += 1; completions.append(onFinish); position = 0; isPlaying = true
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

  func testBurstNeverStealsActiveVoicesAndDrainsAfterTheFirstIdleSeekReservation() {
    let prototype = Voice()
    let player = TypingFeedbackSound(loadSound:{ _ in prototype },beep:{},randomUnit:{ 0 })
    for _ in 0..<32 { player.playClick(style:.tink,volume:0.2) }
    XCTAssertEqual(prototype.copies.count,32)
    XCTAssertTrue(prototype.copies.allSatisfy { $0.stops == 0 && $0.starts == 1 })
    for voice in prototype.copies { voice.finish() }
    for _ in 0..<6 { player.playClick(style:.tink,volume:0.8) }
    XCTAssertEqual(prototype.copies.count,32,"The first idle slot is reserved before the five-idle drain")
    XCTAssertEqual(prototype.copies.filter { $0.starts == 2 }.count,6)
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

  func testPinnedWebAudioSeekPlayAndDrainMatchNativeSlotsAndPositions() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let reference = environment["TYPEBAR_REFERENCE_ROOT"], let archive = environment["TYPEBAR_HOWLER_SOURCE_ARCHIVE"] else {
      throw XCTSkip("Requires pinned reference and verified QA-only Howler archive")
    }
    struct Operation: Decodable { let kind:String; let source:String?; let preview:Bool?; let amount:Double?; let slot:Int? }
    struct Snapshot: Decodable, Equatable { let source:String; let slot:Int; let position:Double }
    struct Fixture: Decodable { let operations:[Operation]; let snapshots:[[Snapshot]]; let allocations:[String:Int] }
    let project = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath:"/usr/bin/env")
    process.arguments = ["node",project.appendingPathComponent("Scripts/check-source-sample-seek.mjs").path,reference,archive,"--emit-fixtures"]
    process.standardOutput = output; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); XCTAssertEqual(process.terminationStatus,0)
    let fixtures = try JSONDecoder().decode([Fixture].self,from:data)
    XCTAssertEqual(fixtures.count,7)
    for fixture in fixtures {
      var prototypes: [TypingClickPlaybackSource:Voice] = [:]
      let player = TypingFeedbackSound(loadSound:{ source in
        let value = Voice(); prototypes[source] = value; return value
      },beep:{ XCTFail("source fixture should not fail") },randomUnit:{ 0 })
      let sources: [(String,TypingClickPlaybackSource)] = [("click",.system("Tink")),("error",.system("Basso"))]
      for (index,operation) in fixture.operations.enumerated() {
        switch operation.kind {
        case "play":
          if operation.source == "error" { player.playError(style:.basso,volume:0.5) }
          else if operation.preview == true { player.previewClick(style:.tink,volume:0.5) }
          else { player.playClick(style:.tink,volume:0.5) }
        case "advance":
          for voice in prototypes.values.flatMap(\.copies) where voice.isPlaying { voice.position += try XCTUnwrap(operation.amount) }
        case "finish":
          let source = try XCTUnwrap(sources.first { $0.0 == operation.source }?.1)
          let prototype = try XCTUnwrap(prototypes[source]), slot = try XCTUnwrap(operation.slot)
          guard prototype.copies.indices.contains(slot) else { XCTFail("missing fixture slot"); continue }
          prototype.copies[slot].finish()
        default: XCTFail("unexpected source operation")
        }
        var snapshots: [Snapshot] = []
        for (name,source) in sources {
          for (slot,voice) in (prototypes[source]?.copies ?? []).enumerated() where voice.isPlaying {
            snapshots.append(.init(source:name,slot:slot,position:(voice.position*1_000_000).rounded()/1_000_000))
          }
        }
        XCTAssertEqual(snapshots,fixture.snapshots[index],"transition \(index)")
      }
      for (name,count) in fixture.allocations {
        let source = try XCTUnwrap(sources.first { $0.0 == name }?.1)
        XCTAssertEqual(prototypes[source]?.copies.count,count)
      }
    }
  }
}
