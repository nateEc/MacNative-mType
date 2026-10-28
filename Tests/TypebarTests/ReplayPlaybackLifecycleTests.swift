@preconcurrency import AppKit
import SwiftUI
import XCTest
@testable import Typebar

final class ReplayPlaybackLifecycleTests: XCTestCase {
  @MainActor private final class Voice: TypingSoundVoice {
    var volume: Float = 1
    let played: () -> Void
    init(_ played: @escaping () -> Void) { self.played = played }
    func copyForPlayback() -> (any TypingSoundVoice)? { Voice(played) }
    func play(onFinish: @escaping () -> Void) -> Bool { played(); return true }
    func stop() {}
  }

  @MainActor func testProductionButtonStartsImmediatelyResumesWithoutIdleAndRestartsZeroTimeTape() async throws {
    for zeroTime in [false, true] {
      let suite = "typebar-replay-playback-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      defer { defaults.removePersistentDomain(forName: suite) }
      var played = 0
      let player = TypingFeedbackSound(loadSound: { _ in Voice { played += 1 } }, beep: {})
      let settings = AppSettings(defaults: defaults, feedbackSound: player, localBackgroundStore: .inMemory())
      settings.playKeyclickSound = true
      let events: [TypingReplayEvent] = [
        .init(offset: zeroTime ? 0 : 0.7, kind: .insert, text: "a", inputField: .init(index: 0, value: "a")),
        .init(offset: zeroTime ? 0 : 5.7, kind: .insert, text: "b", inputField: .init(index: 0, value: "ab"))]
      let view = ReplayTimelineView(prompt: "ab", events: events, speedUnit: .wpm, configuration: .words(1),
        targetWordDirectory: .init(words: ["ab"], noSpace: false), sourceScoringBasis: nil,
        soundConfiguration: .init(settings: settings))
      let controller = NSHostingController(rootView: view.frame(width: 600, height: 260)
        .background(Color.white).environment(\.colorScheme, .light))
      let host = controller.view
      host.frame = NSRect(x: 0, y: 0, width: 600, height: 260)
      host.appearance = NSAppearance(named: .aqua)
      let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 260),
        styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.contentViewController = controller
      defer { window.close() }
      host.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(30))
      func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
      let picker = try XCTUnwrap(descendants(host).compactMap { $0 as? ReplayCharacterTextView }.first)
      func press(_ label: String) throws {
        let button = try XCTUnwrap(descendants(host).compactMap { $0 as? NSButton }.first { $0.title == label })
        XCTAssertTrue(button.isEnabled)
        XCTAssertEqual(button.accessibilityRole(), .button)
        button.performClick(nil)
      }
      func color(_ index: Int) -> NSColor? {
        picker.textStorage?.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
      }
      func resetEnabled() throws -> Bool {
        try XCTUnwrap(descendants(host).compactMap { $0 as? NSButton }.first { $0.title == "重置" }).isEnabled
      }
      XCTAssertEqual(picker.string, "ab"); XCTAssertEqual(color(0), .secondaryLabelColor)
      XCTAssertFalse(try resetEnabled())
      played = 0
      try press("播放")
      try await Task.sleep(for: .milliseconds(20))
      XCTAssertEqual(color(0), .labelColor)
      XCTAssertEqual(played, zeroTime ? 2 : 1)
      XCTAssertTrue(try resetEnabled())
      if !zeroTime {
        XCTAssertEqual(color(1), .secondaryLabelColor)
        try press("暂停")
        try await Task.sleep(for: .milliseconds(20))
        try press("播放")
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(played, 2)
      }
      XCTAssertEqual(color(1), .labelColor)
      try press("重置")
      try await Task.sleep(for: .milliseconds(20))
      XCTAssertEqual(color(0), .secondaryLabelColor); XCTAssertEqual(color(1), .secondaryLabelColor)
      XCTAssertEqual(played, 2)
      XCTAssertFalse(try resetEnabled())
      try press("播放")
      try await Task.sleep(for: .milliseconds(20))
      XCTAssertEqual(played, zeroTime ? 4 : 3)
      if !zeroTime { try press("暂停") }
      XCTAssertFalse(window.isVisible)
    }
  }

  func testPauseResumeAndRestartAgainstCompletePinnedButtonTimersAndDOM() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct Letter: Decodable { let text: String; let extra, correct, incorrect: Bool }
    struct Field: Decodable { let error: Bool; let letters: [Letter] }
    struct Frame: Decodable { let word, position: Int; let fields: [Field] }
    struct Event: Decodable { let index: Int; let value, text: String; let correct, deletion: Bool? }
    struct Fixture: Decodable {
      let targets: [String]; let tape: [Event]
      let leadingTime, firstOffset, resumedOffset, secondOffset: Double
      let opening, paused, resumed, immediate, secondResume, completed, restarted, restartImmediate: Frame
      let immediateSounds, completionSounds, restartSounds: [String]
    }
    struct Output: Decodable { let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-replay-click.mjs").path,
      reference, "--lifecycle"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 4)
    func compare(_ native: FieldReplayPlan.Frame, _ source: Frame) {
      XCTAssertEqual(native.word, source.word); XCTAssertEqual(native.position, source.position)
      XCTAssertEqual(native.fields.count, source.fields.count)
      for (a, b) in zip(native.fields, source.fields) {
        XCTAssertEqual(a.isError, b.error)
        XCTAssertEqual(a.letters.map(\.text), b.letters.map(\.text))
        XCTAssertEqual(a.letters.map(\.extra), b.letters.map(\.extra))
        XCTAssertEqual(a.letters.map(\.correct), b.letters.map(\.correct))
        XCTAssertEqual(a.letters.map(\.incorrect), b.letters.map(\.incorrect))
      }
    }
    func sounds(_ cues: [TypingReplaySoundCue]) -> [String] { cues.map { $0 == .click ? "click" : "error" } }
    for fixture in fixtures {
      let directory = ResultTargetWordDirectory(words: fixture.targets, noSpace: false)
      let events = fixture.tape.enumerated().map { index, event in
        TypingReplayEvent(offset: (fixture.leadingTime + Double(index) * 1000) / 1000,
          kind: event.deletion == true ? .delete : .insert, text: event.text,
          forceError: event.correct == false, inputField: .init(index: event.index, value: event.value))
      }
      let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: directory.words.joined(), events: events,
        configuration: .words(2), targetWordDirectory: directory))
      let opening = try XCTUnwrap(plan.playbackStart(from: plan.initialFrame))
      compare(opening.frame, fixture.opening)
      XCTAssertEqual(opening.nextOffset, fixture.firstOffset / 1000)
      let paused = plan.frame(through: fixture.leadingTime / 1000 + 2.5)
      compare(paused, fixture.paused)
      let resumed = try XCTUnwrap(plan.playbackStart(from: paused))
      compare(resumed.frame, fixture.resumed)
      XCTAssertEqual(resumed.nextOffset, fixture.resumedOffset / 1000)
      var frame = resumed.frame
      XCTAssertEqual(sounds(plan.advance(&frame, through: resumed.nextOffset)), fixture.immediateSounds)
      compare(frame, fixture.immediate)
      let second = try XCTUnwrap(plan.playbackStart(from: frame))
      compare(second.frame, fixture.secondResume)
      XCTAssertEqual(second.nextOffset, fixture.secondOffset / 1000)
      frame = second.frame
      XCTAssertEqual(sounds(plan.advance(&frame, through: events.last!.offset)), fixture.completionSounds)
      compare(frame, fixture.completed)
      let restarted = try XCTUnwrap(plan.playbackStart(from: frame))
      compare(restarted.frame, fixture.restarted)
      frame = restarted.frame
      XCTAssertEqual(sounds(plan.advance(&frame, through: restarted.nextOffset)), fixture.restartSounds)
      compare(frame, fixture.restartImmediate)
    }
  }
}
