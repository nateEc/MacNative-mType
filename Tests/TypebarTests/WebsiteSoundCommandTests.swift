import XCTest
@testable import Typebar

@MainActor final class SoundRecordingTrace {
  struct Event { let source: TypingClickPlaybackSource; let volume: Float }
  final class WeakVoice { weak var value: Voice?; init(_ voice: Voice) { value = voice } }
  final class Voice: TypingSoundVoice {
    unowned let trace: SoundRecordingTrace
    let source: TypingClickPlaybackSource
    var volume: Float = 1
    init(_ source: TypingClickPlaybackSource, trace: SoundRecordingTrace) { self.source = source; self.trace = trace }
    func copyForPlayback() -> (any TypingSoundVoice)? { Voice(source, trace: trace) }
    func play(onFinish: @escaping () -> Void) -> Bool {
      trace.events.append(.init(source: source, volume: volume)); trace.voices.append(.init(self)); return true
    }
    func stop() {}
  }
  var events: [Event] = []
  var voices: [WeakVoice] = []
  var beeps = 0
  func player() -> TypingFeedbackSound {
    .init(loadSound: { [self] in Voice($0, trace: self) }, beep: { [self] in beeps += 1 }, randomUnit: { 0 })
  }
}

@MainActor final class WebsiteSoundCommandTests: XCTestCase {
  func testActualPinnedSoundCommandsAndCustomVolumeCoercion() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else { throw XCTSkip("Requires pinned reference") }
    struct Call: Decodable { let name: String; let args: [WebsiteConfigValue]; let volume: Double }
    struct Fixture: Decodable {
      let key: String, value: WebsiteConfigValue, current: [String:WebsiteConfigValue], active: Bool
      let runtime: [String:WebsiteConfigValue], events: [WebsiteConfigApplicationEvent], saves: [String], hover: [Call], after: [Call]
    }
    struct Custom: Decodable { let raw: String; let canSubmit: Bool; let value: Double?; let runtime: Double; let calls: [Call] }
    struct Output: Decodable { let fixtures: [Fixture]; let custom: [Custom] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-config-schema.mjs").path, reference, "--sound-commands"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.fixtures.count, 160); XCTAssertEqual(output.custom.count, 14)
    let targets = SoundCommandCatalog.items.compactMap { SoundCommandCatalog.target(for: $0.id) }.filter { $0.websiteValue != .null }
    XCTAssertEqual(targets.count, 40)
    for f in output.fixtures {
      let target = try XCTUnwrap(targets.first { $0.websiteKey == f.key && $0.websiteValue == f.value })
      let result = try WebsiteConfigRuntimeProjector.edit(current: f.current, key: target.websiteKey, value: target.websiteValue,
        defaults: WebsiteConfigNativeProfile.defaultDocument().values, schema: .init(catalogs: WebsiteConfigNativeProfile.catalogs),
        context: .init(), testActive: f.active)
      XCTAssertEqual(result.runtime, f.runtime); XCTAssertEqual(result.events, f.events)
      XCTAssertEqual(result.events.map(\.key), f.saves); XCTAssertTrue(result.rejectedKeys.isEmpty)
      let off = f.value == .string("off")
      let hover = f.key == "playSoundOnClick" ? "previewClick" : f.key == "playSoundOnError" ? "previewError" : "playTimeWarning"
      let after = f.key == "playSoundOnClick" ? "playClick" : f.key == "playSoundOnError" ? "playError" : "playTimeWarning"
      XCTAssertEqual(f.hover.map(\.name), off || f.key == "soundVolume" ? [] : [hover])
      XCTAssertEqual(f.after.map(\.name), f.key == "soundVolume" || (off && f.key == "playTimeWarning") ? [] : [after])
      XCTAssertTrue(f.hover.allSatisfy { $0.volume == 0.37 })
    }
    for f in output.custom {
      let value = WebsiteConfigSoundEdit.volume(f.raw)
      XCTAssertEqual(value != nil, f.canSubmit); XCTAssertEqual(value, f.value); XCTAssertTrue(f.calls.isEmpty)
      XCTAssertEqual(f.runtime, value ?? 0.37)
    }
  }
  func testPrivateGainLiveVolumeAndBlindFeedbackDoNotChangeLegacyOrOtherWindowVoices() throws {
    let suite = "typebar.sound-selection.\(UUID())", trace = SoundRecordingTrace(), parent = trace.player()
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults, feedbackSound: parent, localBackgroundStore: .inMemory())
    settings.soundVolume = 0.9
    let first = WebsitePracticeSoundOutput(parent: parent), second = WebsitePracticeSoundOutput(parent: parent)
    defer { first.stop(); second.stop(); parent.clearAllSounds() }
    let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"soundVolume":0.2,"playSoundOnClick":"1","playSoundOnError":"1"}"#, pointsPerRem: 16, context: .init())
    let selection = PracticeSoundSelection(draft: draft, settings: settings, blindMode: false)
    first.apply(selection); second.apply(selection)
    selection.playInput(true, on: first.player)
    XCTAssertEqual(trace.events.last?.volume, 0.2)
    let firstVoice = try XCTUnwrap(trace.voices.last?.value)
    selection.playInput(true, on: second.player)
    let secondVoice = try XCTUnwrap(trace.voices.last?.value)
    let quieter = try WebsiteConfigNativeProfile.editDraft(draft, key: "soundVolume", value: .number(0.1), pointsPerRem: 16, context: .init())
    first.apply(.init(draft: quieter, settings: settings, blindMode: false))
    XCTAssertEqual(firstVoice.volume, 0.1); XCTAssertEqual(secondVoice.volume, 0.2)
    parent.setVolume(0.7)
    XCTAssertEqual(firstVoice.volume, 0.1); XCTAssertEqual(secondVoice.volume, 0.2)
    selection.playInput(false, on: second.player)
    XCTAssertEqual(trace.events.last?.source, TypingErrorSoundStyle.basso.sampleSource(variantIndex: 0))
    let blind = PracticeSoundSelection(draft: draft, settings: settings, blindMode: true)
    blind.playInput(false, on: second.player)
    XCTAssertEqual(trace.events.last?.source, TypingClickSoundStyle.tink.sampleSource(variantIndex: 0))
    XCTAssertEqual(settings.soundVolume, 0.9); XCTAssertEqual(trace.beeps, 0)
  }
  func testHoverDoesNotChangeSelectionOrTheLiveMusicalKey() throws {
    let trace = SoundRecordingTrace(), parent = trace.player(), child = parent.makeIsolatedPlayer()
    parent.recordKeyDown(keyCode: 6, modifierFlags: [])
    child.setVolume(0.4)
    child.previewClick(style: .pianoSine, volume: 0.4)
    let preview = try XCTUnwrap(trace.events.last)
    child.playClick(style: .pianoSine, volume: 0.4)
    XCTAssertEqual(trace.events.count, 2)
    let live = try XCTUnwrap(trace.events.last)
    XCTAssertNotEqual(preview.source, live.source)
    XCTAssertEqual(live.volume, 0.04, accuracy: 0.0001)
    parent.recordKeyDown(keyCode: 12, modifierFlags: [])
    child.playClick(style: .pianoSine, volume: 0.4)
    XCTAssertEqual(trace.events.last?.source, preview.source)
    parent.recordModifierTransition(keyCode: 56, isDown: true, modifierFlags: .shift)
    child.beginPracticeAttempt()
    parent.recordKeyDown(keyCode: 6, modifierFlags: .shift)
    child.playClick(style: .pianoSine, volume: 0.4)
    XCTAssertEqual(trace.events.last?.source, live.source, "A held Shift cannot reappear after reset")
    parent.recordModifierTransition(keyCode: 56, isDown: false, modifierFlags: [])
    parent.recordModifierTransition(keyCode: 56, isDown: true, modifierFlags: .shift)
    parent.recordKeyDown(keyCode: 6, modifierFlags: .shift)
    child.playClick(style: .pianoSine, volume: 0.4)
    XCTAssertEqual(trace.events.last?.source, preview.source)
    child.clearAllSounds()
  }
  func testProfileTimerFinishAndCommandPreviewsUseTheSelectedVolumeAndGates() throws {
    let trace = SoundRecordingTrace(), parent = trace.player()
    let suite = "typebar.sound-events.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults, feedbackSound: parent, localBackgroundStore: .inMemory())
    let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"soundVolume":0.23,"playSoundOnClick":"16","playTimeWarning":"3"}"#, pointsPerRem: 16, context: .init())
    let selection = PracticeSoundSelection(draft: draft, settings: settings, blindMode: false)
    let output = WebsitePracticeSoundOutput(parent: parent); output.apply(selection); defer { output.stop() }
    selection.playWarning(remaining: 3, previous: 4, on: output.player)
    XCTAssertEqual(trace.events.count, 1); XCTAssertEqual(trace.events.last?.volume, 0.23)
    selection.playWarning(remaining: 3, previous: 3, on: output.player)
    selection.playWarning(remaining: 2, previous: 3, on: output.player)
    XCTAssertEqual(trace.events.count, 1)
    selection.playFinish(previous: .active, outcome: .completed, started: true, on: output.player)
    XCTAssertEqual(trace.events.last?.source, .finishReverb); XCTAssertEqual(trace.events.last?.volume, 0.23)
    let count = trace.events.count
    selection.afterCommand(.volume(0.5), on: output.player)
    selection.hover(.volume(0.5), on: output.player)
    selection.hover(.timeWarning(.off), on: output.player)
    XCTAssertEqual(trace.events.count, count)
    selection.hover(.timeWarning(.oneSecond), on: output.player)
    XCTAssertEqual(trace.events.count, count + 1); XCTAssertEqual(trace.events.last?.volume, 0.23)
  }
  func testVolumeFormCapturesOneValueAndSuppressesCancelledLateSuccess() async throws {
    let form = WebsiteSoundVolumeForm(text: "0.37")
    var reply: CheckedContinuation<Void,Never>?
    defer { reply?.resume() }
    var values: [Double] = [], completed = 0
    let apply: @MainActor (Double) async throws -> Void = { value in values.append(value); await withCheckedContinuation { reply = $0 } }
    form.submit(apply: apply, completed: { completed += 1 }); form.text = "1"
    form.submit(apply: apply, completed: { completed += 1 })
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while reply == nil && ContinuousClock.now < deadline { await Task.yield() }
    XCTAssertEqual(values, [0.37]); XCTAssertTrue(form.isWorking)
    form.cancel(); let pending = reply; reply = nil; pending?.resume()
    for _ in 0..<20 { await Task.yield() }
    XCTAssertEqual(completed, 0); XCTAssertFalse(form.isWorking); XCTAssertNil(form.message)
  }
}
