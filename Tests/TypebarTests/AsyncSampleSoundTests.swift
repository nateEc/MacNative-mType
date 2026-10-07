import AppKit
import XCTest
@testable import Typebar

@MainActor final class AsyncSampleSoundTests: XCTestCase {
  private final class Voice: TypingSoundVoice {
    var volume: Float = 1
    var copies: [Voice] = []
    var startedVolumes: [Float] = []
    var stops = 0, rewinds = 0
    var startsSuccessfully = true
    var onStart: (() -> Void)?
    var completion: (() -> Void)?
    func copyForPlayback() -> (any TypingSoundVoice)? {
      let voice = Voice(); voice.startsSuccessfully = startsSuccessfully; copies.append(voice); return voice
    }
    func rewind() { rewinds += 1 }
    func play(onFinish: @escaping () -> Void) -> Bool {
      startedVolumes.append(volume); completion = onFinish; onStart?(); return startsSuccessfully
    }
    func stop() { stops += 1 }
  }

  @MainActor private final class Loader {
    var calls: [TypingClickPlaybackSource] = []
    var waiting: [TypingClickPlaybackSource:CheckedContinuation<(any TypingSoundVoice)?,Never>] = [:]
    func load(_ source: TypingClickPlaybackSource) async -> (any TypingSoundVoice)? {
      calls.append(source)
      return await withCheckedContinuation { waiting[source] = $0 }
    }
    func finish(_ source: TypingClickPlaybackSource, _ voice: Voice?) {
      waiting.removeValue(forKey:source)?.resume(returning:voice)
    }
    func finishAll() {
      let pending = Array(waiting.values); waiting.removeAll()
      for continuation in pending { continuation.resume(returning:nil) }
    }
  }

  private func settle() async { for _ in 0..<100 { await Task.yield() } }

  func testSameResourceRequestsWaitForSinglePreparationThenStartInOrder() async throws {
    let loader = Loader(), prototype = Voice()
    let player = TypingFeedbackSound(loadSound:{ _ in XCTFail("sample must use async preparation"); return nil },
      beep:{},randomUnit:{ 0 },loadSampleSound:{ await loader.load($0) })
    player.playClick(style:.tink,volume:0.2); player.playClick(style:.tink,volume:0.8)
    await settle()
    XCTAssertEqual(loader.calls.filter { $0 == .system("Tink") }.count,1)
    XCTAssertTrue(prototype.copies.isEmpty)
    loader.finish(.system("Tink"),prototype); await settle()
    XCTAssertEqual(prototype.copies.flatMap(\.startedVolumes),[0.2,0.8])
    XCTAssertEqual(prototype.copies.map(\.rewinds),[2,1])
    loader.finishAll(); await settle()
  }

  func testResetRemovesOldRequestsButKeepsPreparationForTheNewAttempt() async {
    let loader = Loader(), prototype = Voice()
    let player = TypingFeedbackSound(loadSound:{ _ in nil },beep:{ XCTFail("canceled request must not beep") },
      randomUnit:{ 0 },loadSampleSound:{ await loader.load($0) })
    player.playTimeWarning(style:.glass,volume:0.2); await settle()
    player.beginPracticeAttempt()
    player.playTimeWarning(style:.glass,volume:0.8)
    loader.finish(.system("Glass"),prototype); await settle()
    XCTAssertEqual(loader.calls,[.system("Glass")])
    XCTAssertEqual(prototype.copies.flatMap(\.startedVolumes),[0.8])
    XCTAssertEqual(prototype.copies.map(\.stops),[0])
    player.playTimeWarning(style:.glass,volume:0.4)
    XCTAssertEqual(loader.calls.count,1)
    XCTAssertEqual(prototype.copies.flatMap(\.startedVolumes),[0.8,0.4])
    loader.finishAll(); await settle()
  }

  func testPrefetchWarmsWholeFamilyWithoutPlayingOrDrawingAndCoalescesLiveRequests() async {
    let loader = Loader(), prototype = Voice()
    var draws = 0
    let player = TypingFeedbackSound(loadSound:{ _ in nil },beep:{ XCTFail("prefetch is silent") },
      randomUnit:{ draws += 1; return 0 },loadSampleSound:{ await loader.load($0) })
    player.configureClickSound(style:.velvet); player.configureClickSound(style:.velvet)
    await settle()
    XCTAssertEqual(loader.calls.count,13); XCTAssertEqual(Set(loader.calls).count,13)
    XCTAssertEqual(draws,0); XCTAssertTrue(prototype.copies.isEmpty)
    player.playClick(style:.velvet,volume:0.5); await settle()
    XCTAssertEqual(loader.calls.count,13); XCTAssertEqual(draws,1)
    loader.finish(TypingClickSoundStyle.velvet.playbackSource,prototype); await settle()
    XCTAssertEqual(prototype.copies.flatMap(\.startedVolumes),[0.5])
    loader.finishAll(); await settle()
  }

  func testMasterVolumeAtDeliveryOverridesWaitingRequestsIncludingMuteAndFailureBeep() async {
    for volume in [0.0,0.4] {
      let loader = Loader(), prototype = Voice()
      var beeps = 0
      let player = TypingFeedbackSound(loadSound:{ _ in nil },beep:{ beeps += 1 },
        loadSampleSound:{ await loader.load($0) })
      player.playTimeWarning(style:.glass,volume:0.8); await settle()
      player.setVolume(volume)
      loader.finish(.system("Glass"),prototype); await settle()
      XCTAssertEqual(prototype.copies.flatMap(\.startedVolumes),[Float(volume)])
      player.playTimeWarning(style:.hero,volume:0.8); await settle()
      loader.finish(.system("Hero"),nil); await settle()
      XCTAssertEqual(beeps,volume == 0 ? 0 : 1)
      loader.finishAll(); await settle()
    }
  }

  func testFailedPreloadIsSilentAndLaterRequestRetriesWithoutNegativeCaching() async {
    let loader = Loader(), prototype = Voice()
    var beeps = 0
    let player = TypingFeedbackSound(loadSound:{ _ in nil },beep:{ beeps += 1 },randomUnit:{ 0 },
      loadSampleSound:{ await loader.load($0) })
    player.configureClickSound(style:.tink); await settle()
    loader.finishAll(); await settle(); XCTAssertEqual(beeps,0)
    player.playError(style:.basso,volume:0.5); await settle()
    loader.finish(.system("Basso"),nil); await settle(); XCTAssertEqual(beeps,1)
    player.playError(style:.basso,volume:0.5); await settle()
    loader.finish(.system("Basso"),prototype); await settle()
    XCTAssertEqual(loader.calls.filter { $0 == .system("Basso") }.count,3)
    XCTAssertEqual(prototype.copies.flatMap(\.startedVolumes),[0.5]); XCTAssertEqual(beeps,1)
    loader.finishAll(); await settle()
  }

  func testResetCancelsAllWaitingChannelsAndTheirFailureFallbacks() async {
    let loader = Loader()
    var beeps = 0
    let player = TypingFeedbackSound(loadSound:{ _ in nil },beep:{ beeps += 1 },randomUnit:{ 0 },
      loadSampleSound:{ await loader.load($0) })
    player.playClick(style:.tink,volume:0.5); player.playError(style:.basso,volume:0.5)
    player.playTimeWarning(style:.glass,volume:0.5); player.playFinishReverb(volume:0.5)
    await settle(); player.clearAllSounds(); loader.finishAll(); await settle()
    XCTAssertEqual(beeps,0)
    XCTAssertFalse(loader.calls.isEmpty)
  }

  func testLatestRestartRequestWinsAcrossOutOfOrderResourcesButFinishIsIndependent() async {
    let loader = Loader(), old = Voice(), new = Voice(), finish = Voice()
    let player = TypingFeedbackSound(loadSound:{ _ in nil },beep:{ XCTFail("no fallback expected") },
      loadSampleSound:{ await loader.load($0) })
    player.playTimeWarning(style:.glass,volume:0.2)
    player.playTimeWarning(style:.hero,volume:0.8)
    player.playFinishReverb(volume:0.5); await settle()
    loader.finish(.system("Hero"),new); loader.finish(.finishReverb,finish); await settle()
    loader.finish(.system("Glass"),old); await settle()
    XCTAssertTrue(old.copies.isEmpty)
    XCTAssertEqual(new.copies.flatMap(\.startedVolumes),[0.8])
    XCTAssertEqual(finish.copies.flatMap(\.startedVolumes),[0.5])
    XCTAssertEqual(new.copies.map(\.stops),[0]); XCTAssertEqual(finish.copies.map(\.stops),[0])
    loader.finishAll(); await settle()
  }

  func testFailedStartAfterReadyFallsBackOnceAndDoesNotEnterTheIdlePool() async {
    let loader = Loader(), prototype = Voice()
    prototype.startsSuccessfully = false
    var beeps = 0
    let player = TypingFeedbackSound(loadSound:{ _ in nil },beep:{ beeps += 1 },randomUnit:{ 0 },
      loadSampleSound:{ await loader.load($0) })
    player.playError(style:.basso,volume:0.5); await settle()
    loader.finish(.system("Basso"),prototype); await settle()
    XCTAssertEqual(beeps,1)
    prototype.startsSuccessfully = true
    player.playError(style:.basso,volume:0.5)
    XCTAssertEqual(prototype.copies.count,2); XCTAssertEqual(beeps,1)
    XCTAssertEqual(prototype.copies.last?.startedVolumes,[0.5])
    loader.finishAll(); await settle()
  }

  func testLoadingDoesNotRetainControllerAndCompletionAfterDeallocationCannotPlay() async {
    let loader = Loader(), prototype = Voice()
    var player: TypingFeedbackSound? = TypingFeedbackSound(loadSound:{ _ in nil },beep:{ XCTFail("no owner") },
      loadSampleSound:{ await loader.load($0) })
    weak var weakPlayer = player
    player?.playTimeWarning(style:.glass,volume:0.5); await settle()
    player = nil; XCTAssertNil(weakPlayer)
    loader.finish(.system("Glass"),prototype); await settle()
    XCTAssertTrue(prototype.copies.isEmpty)
    loader.finishAll(); await settle()
  }

  func testReadyBatchKeepsFIFOThroughReentryAndResetInvalidatesRemainingOldRequests() async {
    for resets in [false,true] {
      let loader = Loader(), prototype = Voice()
      let player = TypingFeedbackSound(loadSound:{ _ in nil },beep:{},randomUnit:{ 0 },
        loadSampleSound:{ await loader.load($0) })
      for value in [0.2,0.4,0.6] { player.playClick(style:.tink,volume:value) }
      await settle()
      // Install the reentrant boundary on copied voices, not on the prototype.
      let reentrant = ReentrantPrototype(prototype:prototype) {
        if resets { player.beginPracticeAttempt() }
        player.playClick(style:.tink,volume:0.8)
      }
      loader.waiting.removeValue(forKey:.system("Tink"))?.resume(returning:reentrant)
      await settle()
      XCTAssertEqual(prototype.copies.flatMap(\.startedVolumes),resets ? [0.2,0.8] : [0.2,0.4,0.6,0.8])
      loader.finishAll(); await settle()
    }
  }

  private final class ReentrantPrototype: TypingSoundVoice {
    var volume: Float = 1
    let prototype: Voice
    var callback: (() -> Void)?
    init(prototype:Voice,callback:@escaping () -> Void) { self.prototype = prototype; self.callback = callback }
    func copyForPlayback() -> (any TypingSoundVoice)? {
      let voice = prototype.copyForPlayback() as? Voice
      if let callback { self.callback = nil; voice?.onStart = callback }
      return voice
    }
    func play(onFinish:@escaping () -> Void) -> Bool { XCTFail("prototype cannot play"); return false }
    func stop() { XCTFail("prototype cannot stop") }
  }

  func testMusicStartsIndependentlyDuringSampleLoadAndSurvivesSampleResetAndVolumeChange() async throws {
    let loader = Loader(), music = Voice()
    let player = TypingFeedbackSound(loadSound:{ source in
      guard case .musical = source else { XCTFail("sample used sync path"); return nil }; return music
    },beep:{},randomUnit:{ 0 },loadSampleSound:{ await loader.load($0) })
    player.setVolume(0.8); player.playClick(style:.tink,volume:0.5)
    player.recordKeyDown(keyCode:12,modifierFlags:[])
    player.playClick(style:.pianoSine,volume:0.5)
    XCTAssertEqual(music.startedVolumes,[0.08]); XCTAssertEqual(music.stops,0)
    await settle(); player.beginPracticeAttempt(); player.setVolume(0.2)
    loader.finishAll(); await settle()
    XCTAssertEqual(music.volume,0.08); XCTAssertEqual(music.stops,0)
  }

  func testPinnedLoadingCommandsWaitForReadinessAndNativeDrainsEachAcceptedRequestOnce() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let reference = environment["TYPEBAR_REFERENCE_ROOT"], let archive = environment["TYPEBAR_HOWLER_SOURCE_ARCHIVE"] else {
      throw XCTSkip("Requires pinned reference and verified QA-only Howler archive")
    }
    struct Fixture: Decodable { let requests:Int; let queued:Int; let starts:Int; let distinctRequestedIDs:Int; let seeks:[Double] }
    let project = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath:"/usr/bin/env")
    process.arguments = ["node",project.appendingPathComponent("Scripts/check-source-sample-loading.mjs").path,reference,archive,"--emit-fixtures"]
    process.standardOutput = output; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); XCTAssertEqual(process.terminationStatus,0)
    let fixtures = try JSONDecoder().decode([Fixture].self,from:data)
    XCTAssertEqual(fixtures.map(\.requests),[1,2,8,32,128])
    for fixture in fixtures {
      // Howler's queued seek internally restarts its first ID: not native polyphony parity.
      XCTAssertEqual(fixture.queued,fixture.requests*2); XCTAssertEqual(fixture.starts,fixture.requests*2-1)
      XCTAssertEqual(fixture.distinctRequestedIDs,1); XCTAssertTrue(fixture.seeks.allSatisfy { $0 == 0 })
      let loader = Loader(), prototype = Voice()
      let player = TypingFeedbackSound(loadSound:{ _ in nil },beep:{},randomUnit:{ 0 },
        loadSampleSound:{ await loader.load($0) })
      for _ in 0..<fixture.requests { player.playClick(style:.tink,volume:0.5) }
      await settle(); XCTAssertTrue(prototype.copies.isEmpty)
      XCTAssertEqual(loader.calls.filter { $0 == .system("Tink") }.count,1)
      loader.finish(.system("Tink"),prototype); await settle()
      XCTAssertEqual(prototype.copies.count,fixture.requests)
      XCTAssertEqual(prototype.copies.map(\.rewinds),[fixture.requests]+Array(repeating:1,count:fixture.requests-1))
      XCTAssertTrue(prototype.copies.allSatisfy { $0.startedVolumes == [0.5] })
      loader.finishAll(); await settle()
    }
  }

  func testDefaultSerialRendererPreservesOwnedWaveformBytesAndFinishDecodesWithoutPlaying() async throws {
    let renderer = NativeSampleWaveformRenderer()
    for style in [TypingClickSoundStyle.ember,.quartz,.rain,.velvet] {
      guard case .synthesized(let profile) = style.playbackSource else { XCTFail("expected owned waveform"); continue }
      let data = await renderer.data(for:.click(profile))
      XCTAssertEqual(data,profile.renderedWAVData())
    }
    let data = await renderer.data(for:.finishReverb)
    XCTAssertEqual(data,TypingFinishReverbSound.renderedWAVData())
    let loaded = await NativeSampleSoundPreparation.load(.finishReverb)
    let voice = try XCTUnwrap(loaded as? NativeTypingSoundVoice)
    XCTAssertEqual(voice.sound.duration,TypingFinishReverbSound.duration,accuracy:0.001)
    XCTAssertFalse(voice.sound.isPlaying)
  }

  func testNativeRendererIsOffMainWhileMainActorRemainsResponsiveAndProducesRealNSSoundWithoutPlaying() async throws {
    let entered = XCTestExpectation(description:"render started"), release = DispatchSemaphore(value:0)
    let renderer = NativeSampleWaveformRenderer { waveform in
      XCTAssertFalse(Thread.isMainThread); entered.fulfill()
      XCTAssertEqual(release.wait(timeout:.now()+3),.success)
      return waveform.renderedWAVData()
    }
    let preparing = Task { await NativeSampleSoundPreparation.load(TypingClickSoundStyle.quartz.playbackSource,using:renderer) as? NativeTypingSoundVoice }
    let result = await XCTWaiter.fulfillment(of:[entered],timeout:3)
    XCTAssertEqual(result,.completed); XCTAssertTrue(Thread.isMainThread)
    release.signal()
    let prepared = await preparing.value
    let voice = try XCTUnwrap(prepared)
    XCTAssertGreaterThan(voice.sound.duration,0); XCTAssertFalse(voice.sound.isPlaying)
    let music = await NativeSampleSoundPreparation.load(.musical(.pentatonic,TypingMusicMode.pentatonic.representativeTone))
    XCTAssertNil(music)
  }
}
