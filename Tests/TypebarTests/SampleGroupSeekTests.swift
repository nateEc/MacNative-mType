import XCTest
@testable import Typebar

@MainActor final class SampleGroupSeekTests: XCTestCase {
  private final class Voice: TypingSoundVoice {
    var volume: Float = 1
    var copies: [Voice] = []
    var position = 0.0
    var starts = 0, rewinds = 0, stops = 0
    var playing = false
    var completion: (() -> Void)?
    var onRewind: (() -> Void)?
    var onCopy: ((Voice) -> Void)?
    func copyForPlayback() -> (any TypingSoundVoice)? { let voice = Voice(); copies.append(voice); onCopy?(voice); return voice }
    func rewind() { position = 0; rewinds += 1; onRewind?() }
    func play(onFinish:@escaping () -> Void) -> Bool { starts += 1; playing = true; completion = onFinish; return true }
    func stop() { stops += 1; playing = false }
    func finish() { playing = false; completion?() }
  }

  func testRepeatedSampleRewindsFirstActiveVoiceButDoesNotRestartOtherActiveVoices() {
    let prototype = Voice()
    let player = TypingFeedbackSound(loadSound:{ _ in prototype },beep:{},randomUnit:{ 0 })
    player.playClick(style:.tink,volume:0.5)
    prototype.copies[0].position = 0.2
    player.playClick(style:.tink,volume:0.5)
    prototype.copies[0].position = 0.2; prototype.copies[1].position = 0.2
    player.previewClick(style:.tink,volume:0.5)
    XCTAssertEqual(prototype.copies.map(\.position),[0,0.2,0])
    XCTAssertEqual(prototype.copies.map(\.rewinds),[3,1,1])
    XCTAssertEqual(prototype.copies.map(\.starts),[1,1,1])
    XCTAssertEqual(prototype.copies.map(\.stops),[0,0,0])
  }

  func testIdleSelectionUsesCreationOrderRatherThanLastCompletionOrder() {
    let prototype = Voice()
    let player = TypingFeedbackSound(loadSound:{ _ in prototype },beep:{},randomUnit:{ 0 })
    for _ in 0..<3 { player.playClick(style:.tink,volume:0.5) }
    prototype.copies[1].finish(); prototype.copies[2].finish()
    player.playClick(style:.tink,volume:0.5)
    XCTAssertEqual(prototype.copies.map(\.starts),[1,2,1])
  }

  func testFirstIdleSeekPrecedesDeferredDrainAndKeepsSixReusableSlots() {
    let prototype = Voice()
    let player = TypingFeedbackSound(loadSound:{ _ in prototype },beep:{},randomUnit:{ 0 })
    for _ in 0..<8 { player.playClick(style:.tink,volume:0.5) }
    for voice in prototype.copies.reversed() { voice.finish() }
    for _ in 0..<6 { player.playClick(style:.tink,volume:0.5) }
    XCTAssertEqual(prototype.copies.count,8)
    XCTAssertEqual(prototype.copies.map(\.starts),[2,2,2,2,2,2,1,1])
    XCTAssertEqual(prototype.copies.map(\.rewinds),[14,2,2,2,2,2,1,1])
  }

  func testGroupSeekOnlyAffectsExactResourceAndNeverMusicOrOtherVariant() throws {
    var prototypes: [TypingClickPlaybackSource:Voice] = [:], draw = 0.0
    let player = TypingFeedbackSound(loadSound:{ source in
      let voice = Voice(); prototypes[source] = voice; return voice
    },beep:{},randomUnit:{ draw })
    player.playClick(style:.tink,volume:0.5); player.playError(style:.basso,volume:0.5)
    player.recordKeyDown(keyCode:12,modifierFlags:[]); player.playClick(style:.pianoSine,volume:0.5)
    let click = try XCTUnwrap(prototypes[.system("Tink")]?.copies.first)
    let error = try XCTUnwrap(prototypes[.system("Basso")]?.copies.first)
    let music = try XCTUnwrap(prototypes.first { if case .musical = $0.key { true } else { false } }?.value)
    click.position = 0.3; error.position = 0.4; music.position = 0.5
    player.previewError(style:.basso,volume:0.5)
    XCTAssertEqual(click.position,0.3); XCTAssertEqual(error.position,0); XCTAssertEqual(music.position,0.5)
    draw = 0.99; player.playClick(style:.tink,volume:0.5)
    XCTAssertEqual(click.position,0.3); XCTAssertEqual(music.position,0.5); XCTAssertEqual(music.stops,0)
  }

  func testSeekKeepsCompletionOwnershipAndOldFinishedPlayCannotReleaseItsReuse() throws {
    let prototype = Voice()
    let player = TypingFeedbackSound(loadSound:{ _ in prototype },beep:{},randomUnit:{ 0 })
    player.playClick(style:.tink,volume:0.5)
    let first = prototype.copies[0], old = try XCTUnwrap(first.completion)
    player.playClick(style:.tink,volume:0.5)
    first.finish(); player.playClick(style:.tink,volume:0.8)
    old(); player.setVolume(0.6)
    XCTAssertEqual(first.starts,2); XCTAssertEqual(first.volume,0.6)
    XCTAssertEqual(prototype.copies[1].volume,0.6)
    XCTAssertEqual(prototype.copies.map(\.stops),[0,0])
  }

  func testReentrantResetDuringGroupSeekPreventsTheOldRequestFromStarting() {
    let prototype = Voice()
    let player = TypingFeedbackSound(loadSound:{ _ in prototype },beep:{ XCTFail("canceled request") },randomUnit:{ 0 })
    player.playClick(style:.tink,volume:0.5)
    prototype.copies[0].onRewind = { player.beginPracticeAttempt() }
    player.playClick(style:.tink,volume:0.5)
    XCTAssertEqual(prototype.copies.count,1); XCTAssertEqual(prototype.copies[0].stops,1)
    player.playClick(style:.tink,volume:0.5)
    XCTAssertEqual(prototype.copies.map(\.starts),[1,1])
  }

  func testReentrantResetDuringFreshRewindDoesNotStartOrBeep() {
    let prototype = Voice()
    let player = TypingFeedbackSound(loadSound:{ _ in prototype },beep:{ XCTFail("canceled request") },randomUnit:{ 0 })
    prototype.onCopy = { voice in voice.onRewind = { player.beginPracticeAttempt() } }
    player.playError(style:.basso,volume:0.5)
    XCTAssertEqual(prototype.copies.count,1)
    XCTAssertEqual(prototype.copies[0].starts,0); XCTAssertEqual(prototype.copies[0].stops,1)
  }
}
