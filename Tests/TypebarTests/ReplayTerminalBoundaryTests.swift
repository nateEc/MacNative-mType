@preconcurrency import AppKit
import SwiftUI
import XCTest
@testable import Typebar

final class ReplayTerminalBoundaryTests: XCTestCase {
  func testActionEndAgainstCompletePinnedReplayButtonAndTimerQueue() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct Event: Decodable { let index, time: Int; let value, text: String; let correct: Bool; let stopped, deletion: Bool? }
    struct Letter: Decodable { let text: String; let correct, incorrect, extra: Bool }
    struct Field: Decodable { let error: Bool; let letters: [Letter] }
    struct Frame: Decodable { let word, position: Int; let fields: [Field] }
    struct Fixture: Decodable {
      let targets: [String]; let tape: [Event]; let lastOffset: Double; let actionCount: Int
      let error: String?; let frame: Frame; let sounds: [String]
    }
    struct Output: Decodable { let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-replay-click.mjs").path, reference, "--terminal"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 6)
    for fixture in fixtures {
      let directory = ResultTargetWordDirectory(words: fixture.targets, noSpace: false)
      let events = fixture.tape.map { event in
        TypingReplayEvent(offset: Double(event.time) / 1000, kind: event.deletion == true ? .delete : .insert,
          text: event.text, forceError: !event.correct, inputStopped: event.stopped,
          inputField: .init(index: event.index, value: event.value))
      }
      let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: directory.words.joined(), events: events,
        configuration: .words(2), targetWordDirectory: directory))
      XCTAssertEqual(plan.actions.count, fixture.actionCount)
      XCTAssertEqual(ResultReplayAvailability.duration(events: events, fieldPlan: plan), fixture.lastOffset / 1000)
      XCTAssertEqual(ResultReplayAvailability.canPlay(events: events, fieldPlan: plan), fixture.error == nil)
      var frame = plan.initialFrame
      let cues = plan.advance(&frame, through: fixture.lastOffset / 1000)
      XCTAssertEqual(cues.map { $0 == .click ? "click" : "error" }, fixture.sounds)
      XCTAssertEqual(frame.word, fixture.frame.word); XCTAssertEqual(frame.position, fixture.frame.position)
      XCTAssertEqual(frame.fields.count, fixture.frame.fields.count)
      for (native, source) in zip(frame.fields, fixture.frame.fields) {
        XCTAssertEqual(native.isError, source.error)
        XCTAssertEqual(native.letters.map(\.text), source.letters.map(\.text))
        XCTAssertEqual(native.letters.map(\.correct), source.letters.map(\.correct))
        XCTAssertEqual(native.letters.map(\.incorrect), source.letters.map(\.incorrect))
        XCTAssertEqual(native.letters.map(\.extra), source.letters.map(\.extra))
      }
    }
  }

  @MainActor private final class Voice: TypingSoundVoice {
    var volume: Float = 1
    let played: () -> Void
    init(_ played: @escaping () -> Void) { self.played = played }
    func copyForPlayback() -> (any TypingSoundVoice)? { Voice(played) }
    func play(onFinish: @escaping () -> Void) -> Bool { played(); return true }
    func stop() {}
  }

  @MainActor func testNativeTransportEndsAtLastActionAndDisablesActionlessTape() async throws {
    for stoppedOnly in [false, true] {
      let suite = "typebar-replay-terminal-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      defer { defaults.removePersistentDomain(forName: suite) }
      var sounds = 0
      let player = TypingFeedbackSound(loadSound: { _ in Voice { sounds += 1 } }, beep: {})
      let settings = AppSettings(defaults: defaults, feedbackSound: player, localBackgroundStore: .inMemory())
      settings.playKeyclickSound = true
      let accepted: [TypingReplayEvent] = stoppedOnly ? [] : [
        .init(offset: 0, kind: .insert, text: "a", inputField: .init(index: 0, value: "a")),
        .init(offset: 0.05, kind: .insert, text: "b", inputField: .init(index: 0, value: "ab"))]
      let events = accepted + [.init(offset: 10, kind: .insert, text: "x", inputStopped: true,
        inputField: .init(index: 0, value: stoppedOnly ? "" : "ab"))]
      let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
      let bytes = try encoder.encode(events)
      let view = ReplayTimelineView(prompt: "ab", events: events, speedUnit: .wpm, configuration: .words(1),
        targetWordDirectory: .init(words: ["ab"], noSpace: false), sourceScoringBasis: nil,
        soundConfiguration: .init(settings: settings))
      let controller = NSHostingController(rootView: view.frame(width: 600, height: 260))
      let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 260),
        styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.contentViewController = controller
      defer { window.close() }
      let host = controller.view; host.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(30))
      func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
      func play() throws -> NSButton { try XCTUnwrap(views(host).compactMap { $0 as? NSButton }.first { $0.title == "播放" }) }
      let button = try play()
      XCTAssertEqual(button.isEnabled, !stoppedOnly)
      let slider = try XCTUnwrap(views(host).compactMap { $0 as? NSSlider }.first)
      XCTAssertEqual(slider.doubleValue, 0, accuracy: 0.0001)
      if !stoppedOnly {
        sounds = 0; button.performClick(nil)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(button.title, "播放")
        XCTAssertEqual(slider.doubleValue, 1, accuracy: 0.0001)
        XCTAssertEqual(sounds, 2)
        let picker = try XCTUnwrap(views(host).compactMap { $0 as? ReplayCharacterTextView }.first)
        XCTAssertEqual(picker.string, "ab")
        button.performClick(nil)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(button.title, "播放"); XCTAssertEqual(sounds, 4)
        XCTAssertEqual(slider.doubleValue, 1, accuracy: 0.0001)
      }
      XCTAssertEqual(try encoder.encode(events), bytes)
      XCTAssertFalse(window.isVisible)
    }
  }

  func testLegacyTimingUsesKnownAcceptedPrimitivesWithoutInventingFields() {
    let events: [TypingReplayEvent] = [
      .init(offset: 10, kind: .insert, text: "x", inputStopped: true),
      .init(offset: 0, kind: .insert, text: "ab"),
      .init(offset: 2, kind: .delete, text: "")]
    XCTAssertNil(FieldReplayPlan.make(prompt: "ab", events: events, configuration: .words(1)))
    XCTAssertEqual(ResultReplayAvailability.duration(events: events, fieldPlan: nil), 2)
    XCTAssertTrue(ResultReplayAvailability.canPlay(events: events, fieldPlan: nil))
    let stopped = [TypingReplayEvent(offset: 10, kind: .insert, text: "x", inputStopped: true)]
    XCTAssertEqual(ResultReplayAvailability.duration(events: stopped, fieldPlan: nil), 0)
    XCTAssertFalse(ResultReplayAvailability.canPlay(events: stopped, fieldPlan: nil))
  }
}
