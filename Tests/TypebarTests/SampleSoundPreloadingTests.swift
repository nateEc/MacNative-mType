import AppKit
import XCTest
@testable import Typebar

@MainActor
final class SampleSoundPreloadingTests: XCTestCase {
  private final class Voice: TypingSoundVoice {
    var volume: Float = 1
    var copies: [Voice] = []
    var starts = 0, stops = 0
    var finish: (() -> Void)?
    func copyForPlayback() -> (any TypingSoundVoice)? {
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

  private func family(_ style: TypingClickSoundStyle) -> [TypingClickPlaybackSource] {
    (0..<style.sampleVariantCount).compactMap { style.sampleSource(variantIndex: $0) }
  }

  func testLiveClickPreloadsErrorsAndWholeFamilyBeforeItsOnlyRandomDraw() {
    var loaded: [TypingClickPlaybackSource] = [], voices: [Voice] = [], draws = 0
    let expected = errorSources + family(.velvet)
    let player = TypingFeedbackSound(loadSound: {
      loaded.append($0); let voice = Voice(); voices.append(voice); return voice
    }, beep: { XCTFail("preload must not beep") }, randomUnit: {
      XCTAssertEqual(loaded, expected)
      XCTAssertTrue(voices.allSatisfy { $0.copies.isEmpty && $0.starts == 0 && $0.stops == 0 })
      draws += 1; return 0.99
    })
    player.playClick(style: .velvet, volume: 0.5)
    XCTAssertEqual(loaded, expected)
    XCTAssertEqual(draws, 1)
    XCTAssertEqual(voices.flatMap(\.copies).count, 1)
    XCTAssertEqual(voices.last?.copies.first?.starts, 1)
  }

  func testPreviewPreloadsConfiguredFamilyButOnlyFirstResourceOfDifferentTarget() {
    var loaded: [TypingClickPlaybackSource] = [], voices: [Voice] = []
    let player = TypingFeedbackSound(loadSound: {
      loaded.append($0); let voice = Voice(); voices.append(voice); return voice
    }, beep: {}, randomUnit: { XCTFail("no preview/preload RNG"); return 0 })
    player.configureClickSound(style: .velvet)
    XCTAssertEqual(loaded, errorSources + family(.velvet))
    XCTAssertTrue(voices.allSatisfy { $0.copies.isEmpty && $0.starts == 0 && $0.stops == 0 })
    player.previewClick(style: .rain, volume: 0.5)
    player.previewClick(style: .rain, volume: 0.5)
    XCTAssertEqual(loaded, errorSources + family(.velvet) + [.rainFirst])
    XCTAssertEqual(voices.last?.copies.count, 2)
    player.configureClickSound(style: nil)
    player.previewClick(style: .tink, volume: 0.5)
    XCTAssertEqual(loaded, errorSources + family(.velvet) + [.rainFirst, .system("Tink")])
  }

  func testErrorPlaybackAndPreviewPreloadAllFiveErrorsAndNoClickFamily() {
    for preview in [false, true] {
      var loaded: [TypingClickPlaybackSource] = [], voices: [Voice] = [], draws = 0
      let player = TypingFeedbackSound(loadSound: {
        loaded.append($0); let voice = Voice(); voices.append(voice); return voice
      }, beep: {}, randomUnit: { draws += 1; return 0.99 })
      if preview { player.previewError(style: .submarine, volume: 0.5) }
      else { player.playError(style: .submarine, volume: 0.5) }
      XCTAssertEqual(loaded, errorSources)
      XCTAssertEqual(draws, preview ? 0 : 1)
      XCTAssertEqual(voices.flatMap(\.copies).count, 1)
      let selected = preview ? 3 : 4
      XCTAssertEqual(voices.indices.contains(selected) ? voices[selected].copies.first?.starts : nil, 1)
    }
  }

  func testMusicConfigurationWarmsOnlyErrorsButColdMusicPlaybackBypassesPreloading() {
    var loaded: [TypingClickPlaybackSource] = []
    let player = TypingFeedbackSound(loadSound: { loaded.append($0); return Voice() }, beep: {},
      randomUnit: { XCTFail("keyboard music does not draw"); return 0 })
    player.configureClickSound(style: nil)
    player.setVolume(0)
    XCTAssertTrue(loaded.isEmpty)
    player.previewClick(style: .pianoSine, volume: 0.5)
    XCTAssertEqual(loaded.count, 1)
    guard case .musical = loaded[0] else { XCTFail("expected music"); return }
    player.configureClickSound(style: .pianoSine)
    XCTAssertEqual(Array(loaded.dropFirst()), errorSources)
    player.configureClickSound(style: .pianoTriangle)
    XCTAssertEqual(loaded.count, 6)
  }

  func testSavedSettingsSynchronizeFinalFamilyWithoutLoadingDefaultIntermediate() throws {
    let suite = "TypebarTests.PreloadSaved.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let snapshot = AppSettingsSnapshot(playKeyclickSound: true, clickSoundStyle: .rain, soundVolume: 0.25)
    let data = try JSONEncoder().encode(snapshot)
    defaults.set(data, forKey: "appSettings.v1")
    var loaded: [TypingClickPlaybackSource] = [], voices: [Voice] = []
    let player = TypingFeedbackSound(loadSound: {
      loaded.append($0); let voice = Voice(); voices.append(voice); return voice
    }, beep: {}, randomUnit: { 0 })
    let settings = AppSettings(defaults: defaults, feedbackSound: player)
    XCTAssertEqual(settings.clickSoundStyle, .rain)
    XCTAssertEqual(loaded, errorSources + family(.rain))
    XCTAssertEqual(defaults.data(forKey: "appSettings.v1"), data)
    XCTAssertTrue(voices.allSatisfy { $0.copies.isEmpty && $0.starts == 0 && $0.stops == 0 })
    player.playClick(style: .rain, volume: 0.9)
    XCTAssertEqual(voices.flatMap(\.copies).first?.volume, 0.25)
  }

  func testAllFamilySwitchesAndPracticeResetsKeepOnlyOnePrototypePerResourceWithoutPlayback() {
    var loaded: [TypingClickPlaybackSource] = [], voices: [Voice] = []
    let player = TypingFeedbackSound(loadSound: {
      loaded.append($0); let voice = Voice(); voices.append(voice); return voice
    }, beep: { XCTFail("preloading never beeps") }, randomUnit: { XCTFail("preloading never draws"); return 0 })
    let styles = TypingClickSoundStyle.allCases.filter { $0.musicMode == nil }
    for _ in 0..<2 {
      for style in styles {
        player.configureClickSound(style: style)
        player.beginPracticeAttempt()
        player.configureClickSound(style: nil)
      }
    }
    XCTAssertEqual(loaded, errorSources + styles.flatMap(family))
    XCTAssertEqual(loaded.count, 159)
    XCTAssertEqual(Set(loaded).count, 159)
    XCTAssertTrue(voices.allSatisfy { $0.copies.isEmpty && $0.starts == 0 && $0.stops == 0 })
  }

  func testRealSettingsCommandsBindingsAndSnapshotApplyWarmOnlyTheirFinalEnabledFamily() throws {
    let suite = "TypebarTests.PreloadSwitch.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var loaded: [TypingClickPlaybackSource] = []
    let player = TypingFeedbackSound(loadSound: { loaded.append($0); return Voice() }, beep: {}, randomUnit: { 0 })
    let settings = AppSettings(defaults: defaults, feedbackSound: player)
    settings.clickSoundStyle = .tink
    settings.playErrorBeep = true
    settings.errorSoundStyle = .funk
    settings.soundVolume = 0.2
    XCTAssertTrue(loaded.isEmpty)
    SoundCommandTarget.click(.rain).apply(to: settings)
    XCTAssertEqual(loaded, errorSources + family(.rain))
    settings.clickSoundStyle = .velvet // The real preference binding path.
    XCTAssertEqual(loaded, errorSources + family(.rain) + family(.velvet))
    SoundCommandTarget.click(nil).apply(to: settings)
    settings.clickSoundStyle = .ember
    XCTAssertEqual(loaded.count, 23)
    settings.apply(AppSettingsSnapshot(playKeyclickSound: true, clickSoundStyle: .copper, soundVolume: 0.7))
    XCTAssertEqual(loaded, errorSources + family(.rain) + family(.velvet) + family(.copper))
    let stored = try JSONDecoder().decode(AppSettingsSnapshot.self, from: XCTUnwrap(defaults.data(forKey: "appSettings.v1")))
    XCTAssertTrue(stored.playKeyclickSound)
    XCTAssertEqual(stored.clickSoundStyle, .copper)
    XCTAssertEqual(stored.soundVolume, 0.7)
    settings.restoreDefaults(customizationTombstoneStore: .init(defaults: defaults))
    XCTAssertEqual(loaded.count, 28)
    player.previewClick(style: .tink, volume: 0.9)
    XCTAssertEqual(loaded, errorSources + family(.rain) + family(.velvet) + family(.copper) + [.system("Tink")])
  }

  func testUnavailablePreloadedResourceIsRetryableAndDoesNotBeepOrPreventOtherSamples() {
    let missing = TypingErrorSoundStyle.basso.sampleSource(variantIndex: 0)
    var available = false, beeps = 0
    var loaded: [TypingClickPlaybackSource] = [], voices: [Voice] = []
    let player = TypingFeedbackSound(loadSound: { source in
      loaded.append(source)
      if source == missing && !available { return nil }
      let voice = Voice(); voices.append(voice); return voice
    }, beep: { beeps += 1 }, randomUnit: { 0 })
    player.configureClickSound(style: .tink)
    XCTAssertEqual(loaded, errorSources + family(.tink))
    XCTAssertEqual(beeps, 0)
    player.playClick(style: .tink, volume: 0.5)
    XCTAssertEqual(loaded.filter { $0 == missing }.count, 2)
    XCTAssertEqual(voices.flatMap(\.copies).count, 1)
    player.playError(style: .basso, volume: 0.5)
    XCTAssertEqual(beeps, 1)
    XCTAssertEqual(loaded.filter { $0 == missing }.count, 4)
    available = true
    player.previewError(style: .basso, volume: 0.5)
    player.previewError(style: .basso, volume: 0.5)
    XCTAssertEqual(loaded.filter { $0 == missing }.count, 5)
    XCTAssertEqual(voices.flatMap(\.copies).count, 3)
    XCTAssertTrue(voices.flatMap(\.copies).allSatisfy { $0.starts == 1 && $0.stops == 0 })
    XCTAssertEqual(beeps, 1)
  }

  func testSynchronousLoaderReentryDoesNotRecursivelyLoadTheSameResource() {
    var player: TypingFeedbackSound!
    var loaded: [TypingClickPlaybackSource] = []
    player = TypingFeedbackSound(loadSound: { source in
      loaded.append(source)
      if loaded.count == 1 { player.configureClickSound(style: .tink) }
      return Voice()
    }, beep: { XCTFail("preload must not beep") }, randomUnit: { 0 })
    player.configureClickSound(style: .tink)
    XCTAssertEqual(loaded, errorSources + family(.tink))
    player.configureClickSound(style: .tink)
    XCTAssertEqual(loaded.count, 8)
    player = nil
  }

  func testFamilyPreloadPreservesActiveVoicesAndHonorsReentrantMasterVolumeChange() throws {
    var player: TypingFeedbackSound!
    var voices: [Voice] = [], loaded: [TypingClickPlaybackSource] = []
    player = TypingFeedbackSound(loadSound: { source in
      loaded.append(source)
      if source == TypingClickSoundStyle.rain.playbackSource { player.setVolume(0.3) }
      let voice = Voice(); voices.append(voice); return voice
    }, beep: {}, randomUnit: { 0 })
    player.setVolume(0.8)
    player.recordKeyDown(keyCode: 12, modifierFlags: [])
    player.playClick(style: .pianoSine, volume: 0.5)
    let music = try XCTUnwrap(voices.first)
    player.playClick(style: .tink, volume: 0.5)
    let sample = try XCTUnwrap(voices.flatMap(\.copies).first)
    player.configureClickSound(style: .rain)
    XCTAssertEqual(sample.starts, 1)
    XCTAssertEqual(sample.stops, 0)
    XCTAssertEqual(sample.volume, 0.3, accuracy: 0.0001)
    XCTAssertEqual(music.volume, 0.08, accuracy: 0.0001)
    XCTAssertEqual(music.stops, 0)
    player.previewClick(style: .rain, volume: 0.9)
    let newest = try XCTUnwrap(voices.flatMap(\.copies).last)
    XCTAssertEqual(newest.volume, 0.3, accuracy: 0.0001)
    player.beginPracticeAttempt()
    XCTAssertEqual(sample.stops, 1)
    XCTAssertEqual(newest.stops, 1)
    XCTAssertEqual(music.stops, 0)
    let count = loaded.count
    player.previewClick(style: .rain, volume: 0.9)
    XCTAssertEqual(loaded.count, count)
    sample.finish?(); newest.finish?()
    XCTAssertEqual(voices.flatMap(\.copies).last?.stops, 0)
    player = nil
  }

  func testColdWarningOnlyLoadsItsOwnResourceAndDoesNotWarmErrorsOrClickSamples() {
    var loaded: [TypingClickPlaybackSource] = []
    let player = TypingFeedbackSound(loadSound: { loaded.append($0); return Voice() }, beep: {},
      randomUnit: { XCTFail("warning never draws"); return 0 })
    player.playTimeWarning(style: .glass, volume: 0.5)
    player.playTimeWarning(style: .glass, volume: 0.5)
    XCTAssertEqual(loaded, [.system("Glass")])
  }
}

private extension TypingClickPlaybackSource {
  static var rainFirst: Self { TypingClickSoundStyle.rain.playbackSource }
}
