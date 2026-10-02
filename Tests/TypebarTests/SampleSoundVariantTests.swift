import AppKit
import XCTest
@testable import Typebar

@MainActor
final class SampleSoundVariantTests: XCTestCase {
  private final class Voice: TypingSoundVoice {
    let onCopy: (() -> Void)?
    init(onCopy: (() -> Void)? = nil) { self.onCopy = onCopy }
    var volume: Float = 1
    var copies: [Voice] = []
    var starts = 0, stops = 0
    var finish: (() -> Void)?
    func copyForPlayback() -> (any TypingSoundVoice)? {
      onCopy?()
      let voice = Voice(); copies.append(voice); return voice
    }
    func play(onFinish: @escaping () -> Void) -> Bool {
      starts += 1; finish = onFinish; return true
    }
    func stop() { stops += 1 }
  }

  private var errorSources: [TypingClickPlaybackSource] {
    TypingErrorSoundStyle.allCases.flatMap { style in
      (0..<style.sampleVariantCount).compactMap { style.sampleSource(variantIndex: $0) }
    }
  }

  // Cardinality facts from the pinned public configuration, not source/assets.
  private func families() throws -> [(Int, TypingClickSoundStyle, Int)] {
    let facts = [(1, 3), (2, 3), (3, 3), (4, 6), (5, 6), (6, 3), (7, 3),
      (14, 8), (15, 5), (16, 8), (17, 10), (18, 10), (19, 10), (20, 10),
      (21, 10), (22, 10), (23, 10), (24, 10), (25, 10), (26, 10)]
    return try facts.map { id, count in
      guard case .click(let style?) = SoundCommandCatalog.target(for: "sound.playSoundOnClick.\(id)")
      else { throw NSError(domain: "MissingSampleSound", code: id) }
      return (id, style, count)
    }
  }

  func testAllOfficialSampleFamiliesHaveDistinctStableSourcesAndPinnedCardinality() throws {
    var total = 0
    for (id, style, expected) in try families() {
      XCTAssertEqual(style.sampleVariantCount, expected, "family \(id)")
      let sources = (0..<expected).compactMap { style.sampleSource(variantIndex: $0) }
      XCTAssertEqual(Set(sources).count, expected, "family \(id)")
      XCTAssertEqual(sources.first, style.playbackSource)
      XCTAssertEqual(sources, (0..<expected).compactMap { style.sampleSource(variantIndex: $0) })
      XCTAssertNil(style.sampleSource(variantIndex: -1))
      XCTAssertNil(style.sampleSource(variantIndex: expected))
      total += style.sampleVariantCount
    }
    XCTAssertEqual(total, 148)
  }

  func testLiveSampleSelectionDrawsOnceAndEveryUniformBucketLoadsItsOwnCachedPrototype() throws {
    for (id, style, count) in try families() {
      var sources: [TypingClickPlaybackSource] = []
      var selected: [TypingClickPlaybackSource] = []
      var draws = 0
      let player = TypingFeedbackSound(loadSound: { source in sources.append(source); return Voice(onCopy: { selected.append(source) }) }, beep: {}, randomUnit: {
        let value = (Double(draws % count) + 0.5) / Double(count)
        draws += 1; return value
      })
      for _ in 0..<(count * 2) { player.playClick(style: style, volume: 0.5) }
      XCTAssertEqual(draws, count * 2, "family \(id)")
      let family = (0..<count).compactMap { style.sampleSource(variantIndex: $0) }
      XCTAssertEqual(sources, errorSources + family, "family \(id) should cache independently")
      XCTAssertEqual(selected, family + family)
    }
  }

  func testFourthErrorFamilyRandomlyUsesTwoVariantsAndTheOtherFamiliesStillDrawOnce() {
    for style in TypingErrorSoundStyle.allCases {
      var sources: [TypingClickPlaybackSource] = []
      var selected: [TypingClickPlaybackSource] = []
      var draws = 0
      let count = style == .submarine ? 2 : 1
      let player = TypingFeedbackSound(loadSound: { source in sources.append(source); return Voice(onCopy: { selected.append(source) }) }, beep: {}, randomUnit: {
        let value = (Double(draws % count) + 0.5) / Double(count)
        draws += 1; return value
      })
      for _ in 0..<(count * 2) { player.playError(style: style, volume: 0.5) }
      XCTAssertEqual(style.sampleVariantCount, count)
      XCTAssertEqual(draws, count * 2)
      let family = (0..<count).compactMap { style.sampleSource(variantIndex: $0) }
      XCTAssertEqual(sources, errorSources)
      XCTAssertEqual(selected, family + family)
    }
  }

  func testSamplePreviewsAlwaysUseTheFirstVariantWithoutDrawingRandomness() throws {
    for (_, style, _) in try families() {
      var sources: [TypingClickPlaybackSource] = []
      var selected: [TypingClickPlaybackSource] = []
      let player = TypingFeedbackSound(loadSound: { source in sources.append(source); return Voice(onCopy: { selected.append(source) }) }, beep: {},
        randomUnit: { XCTFail("sample preview must not draw"); return 0.999 })
      player.previewClick(style: style, volume: 0.5)
      player.previewClick(style: style, volume: 0.5)
      XCTAssertEqual(sources, errorSources + [style.playbackSource])
      XCTAssertEqual(selected, [style.playbackSource, style.playbackSource])
    }
    for style in TypingErrorSoundStyle.allCases {
      var sources: [TypingClickPlaybackSource] = []
      var selected: [TypingClickPlaybackSource] = []
      let player = TypingFeedbackSound(loadSound: { source in sources.append(source); return Voice(onCopy: { selected.append(source) }) }, beep: {},
        randomUnit: { XCTFail("error preview must not draw"); return 0.999 })
      player.previewError(style: style, volume: 0.5)
      player.previewError(style: style, volume: 0.5)
      XCTAssertEqual(sources, errorSources)
      XCTAssertEqual(selected, Array(repeating: try XCTUnwrap(style.sampleSource(variantIndex: 0)), count: 2))
    }
  }

  func testBucketBoundariesAndInvalidInjectedDrawsRemainInsideTheirFamilies() throws {
    for (_, style, count) in try families() {
      let values: [Double] = [0, Double(1).nextDown, 1, -1, .nan, .infinity, -.infinity]
        + (1..<count).map { Double($0) / Double(count) }
      for value in values {
        var sources: [TypingClickPlaybackSource] = []
        var selected: [TypingClickPlaybackSource] = []
        let player = TypingFeedbackSound(loadSound: { source in sources.append(source); return Voice(onCopy: { selected.append(source) }) }, beep: {}, randomUnit: { value })
        player.playClick(style: style, volume: 0.5)
        let index = value.isFinite ? Int(value.clamped(to: 0...Double(1).nextDown) * Double(count)) : 0
        XCTAssertEqual(sources, errorSources + (0..<count).compactMap { style.sampleSource(variantIndex: $0) })
        XCTAssertEqual(selected, [try XCTUnwrap(style.sampleSource(variantIndex: index))])
      }
    }
  }

  func testDifferentVariantVoicesShareMasterGainAndResetButNotPlaybackIdentity() throws {
    var prototypes: [Voice] = [], draws = 0
    let player = TypingFeedbackSound(loadSound: { _ in
      let voice = Voice(); prototypes.append(voice); return voice
    }, beep: {}, randomUnit: { defer { draws += 1 }; return [0.0, 0.5, 0.99][draws % 3] })
    player.setVolume(0.8)
    for _ in 0..<4 { player.playClick(style: .tink, volume: 0.1) }
    XCTAssertEqual(prototypes.count, 8)
    let old = prototypes.flatMap(\.copies)
    XCTAssertEqual(Set(old.map(ObjectIdentifier.init)).count, 4)
    XCTAssertTrue(old.allSatisfy { $0.volume == 0.8 && $0.starts == 1 && $0.stops == 0 })
    player.setVolume(0); player.setVolume(0.2)
    XCTAssertTrue(old.allSatisfy { $0.volume == 0.2 && $0.stops == 0 })
    player.beginPracticeAttempt()
    XCTAssertTrue(old.allSatisfy { $0.stops == 1 })
    player.playClick(style: .tink, volume: 0.9)
    let newest = try XCTUnwrap(prototypes.flatMap(\.copies).last(where: { candidate in !old.contains { $0 === candidate } }))
    for voice in old { voice.finish?() }
    XCTAssertEqual(newest.stops, 0)
    XCTAssertEqual(newest.volume, 0.2, accuracy: 0.0001)
    XCTAssertEqual(prototypes.count, 8)
    player.clearAllSounds()
    XCTAssertEqual(newest.stops, 1)
  }

  func testSamplePreviewDoesNotAdvanceTheSharedLiveSampleAndScaleRandomStream() {
    var sources: [TypingClickPlaybackSource] = [], draws = 0
    var selected: [TypingClickPlaybackSource] = []
    let player = TypingFeedbackSound(loadSound: { source in sources.append(source); return Voice(onCopy: { selected.append(source) }) }, beep: {}, randomUnit: {
      defer { draws += 1 }; return [0.0, 0.99, 0.0, 0.0][draws]
    })
    player.previewClick(style: .tink, volume: 0.5)
    player.previewError(style: .submarine, volume: 0.5)
    XCTAssertEqual(draws, 0)
    player.playClick(style: .tink, volume: 0.5)
    player.previewClick(style: .tink, volume: 0.5)
    player.playClick(style: .tink, volume: 0.5)
    XCTAssertEqual(draws, 2)
    XCTAssertEqual(selected.last, TypingClickSoundStyle.tink.sampleSource(variantIndex: 2))
    player.playClick(style: .pentatonic, volume: 0.5)
    XCTAssertEqual(draws, 4)
    guard case .musical(_, let tone) = sources.last else { XCTFail("expected scale"); return }
    XCTAssertEqual(tone.frequency, 523.25)
  }

  func testUnavailableChosenVariantsDoNotReplaceOtherVoicesAndErrorPreviewUsesFirstFallback() {
    let clickFirst = TypingClickSoundStyle.tink.sampleSource(variantIndex: 0)
    let clickMissing = TypingClickSoundStyle.tink.sampleSource(variantIndex: 2)
    let errorMissing = TypingErrorSoundStyle.submarine.sampleSource(variantIndex: 1)
    var voices: [Voice] = [], sources: [TypingClickPlaybackSource] = [], draws = 0, beeps = 0
    var selected: [TypingClickPlaybackSource] = []
    let player = TypingFeedbackSound(loadSound: { source in
      sources.append(source)
      if source == clickMissing || source == errorMissing { return nil }
      let voice = Voice(onCopy: { selected.append(source) }); voices.append(voice); return voice
    }, beep: { beeps += 1 }, randomUnit: { defer { draws += 1 }; return draws == 0 ? 0 : 0.99 })
    player.playClick(style: .tink, volume: 0.5)
    player.playClick(style: .tink, volume: 0.5)
    XCTAssertEqual(beeps, 0)
    player.playError(style: .submarine, volume: 0.5)
    XCTAssertEqual(beeps, 1)
    player.previewError(style: .submarine, volume: 0.5)
    XCTAssertEqual(draws, 3)
    XCTAssertEqual(sources.first, errorSources.first)
    XCTAssertEqual(selected, [clickFirst, TypingErrorSoundStyle.submarine.sampleSource(variantIndex: 0)].compactMap { $0 })
    XCTAssertTrue(voices.flatMap(\.copies).allSatisfy { $0.stops == 0 && $0.starts == 1 })
    XCTAssertEqual(beeps, 1)
  }

  func testGlobalMutedSamplesAndErrorsStillDrawAndPlayMutedVoicesWithoutBeeping() {
    var prototypes: [Voice] = [], draws = 0
    let player = TypingFeedbackSound(loadSound: { _ in
      let voice = Voice(); prototypes.append(voice); return voice
    }, beep: { XCTFail("muted cue must not beep") }, randomUnit: { draws += 1; return 0.99 })
    player.setVolume(0)
    player.playClick(style: .tink, volume: 0.5)
    player.playError(style: .submarine, volume: 0.5)
    XCTAssertEqual(draws, 2)
    let voices = prototypes.flatMap(\.copies)
    XCTAssertEqual(voices.count, 2)
    XCTAssertTrue(voices.allSatisfy { $0.volume == 0 && $0.starts == 1 && $0.stops == 0 })
    player.setVolume(0.5)
    XCTAssertTrue(voices.allSatisfy { $0.volume == 0.5 && $0.stops == 0 })
  }

  func testAllOwnedVariantWAVsAreDistinctDecodableAndCopyableWithoutPlaying() throws {
    var sources: Set<TypingClickPlaybackSource> = []
    for style in TypingClickSoundStyle.allCases where style.musicMode == nil {
      for index in 0..<style.sampleVariantCount { sources.insert(try XCTUnwrap(style.sampleSource(variantIndex: index))) }
    }
    for style in TypingErrorSoundStyle.allCases {
      for index in 0..<style.sampleVariantCount { sources.insert(try XCTUnwrap(style.sampleSource(variantIndex: index))) }
    }
    XCTAssertEqual(sources.count, 159)
    var bytes: Set<Data> = [], profiles = 0
    for source in sources {
      guard case .synthesized(let profile) = source else { continue }
      let data = profile.renderedWAVData()
      XCTAssertTrue(bytes.insert(data).inserted)
      let sound = try XCTUnwrap(NSSound(data: data))
      XCTAssertEqual(sound.duration, profile.duration, accuracy: 1.0 / 22_050)
      sound.currentTime = sound.duration / 2; sound.loops = true
      let prototype = NativeTypingSoundVoice(sound: sound)
      let first = try XCTUnwrap(prototype.copyForPlayback() as? NativeTypingSoundVoice)
      let second = try XCTUnwrap(prototype.copyForPlayback() as? NativeTypingSoundVoice)
      XCTAssertFalse(first.sound === second.sound)
      XCTAssertEqual(first.sound.currentTime, 0)
      XCTAssertFalse(first.sound.loops)
      XCTAssertFalse(sound.isPlaying); XCTAssertFalse(first.sound.isPlaying); XCTAssertFalse(second.sound.isPlaying)
      profiles += 1
    }
    XCTAssertEqual(profiles, 151)
  }

  func testNativeExtensionsAndMusicalBranchesDoNotAcquireOfficialSampleVariants() throws {
    for style: TypingClickSoundStyle in [.ripple, .reed, .pebble, .loom, .orbit, .pulse] {
      XCTAssertEqual(style.sampleVariantCount, 1)
      XCTAssertEqual(style.sampleSource(variantIndex: 0), style.playbackSource)
      XCTAssertNil(style.sampleSource(variantIndex: 1))
    }
    for style in TypingClickSoundStyle.allCases where style.musicMode != nil {
      XCTAssertEqual(style.sampleVariantCount, 0)
      XCTAssertNil(style.sampleSource(variantIndex: 0))
    }
    let encoded = try JSONEncoder().encode(TypingClickSoundStyle.allCases)
    XCTAssertEqual(try JSONDecoder().decode([TypingClickSoundStyle].self, from: encoded), TypingClickSoundStyle.allCases)
    XCTAssertEqual(TypingClickSoundStyle.allCases.count, 32)
  }
}
