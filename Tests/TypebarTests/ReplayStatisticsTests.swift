@preconcurrency import AppKit
import SwiftUI
import XCTest
@testable import Typebar

final class ReplayStatisticsTests: XCTestCase {
  private struct Event: Decodable { let time: Double; let index: Int; let value, text: String; let correct: Bool; let deletion: Bool? }
  private struct Step: Decodable { let kind: String; let now: Double; let label: String; let offset, end: Double? }
  private struct Fixture: Decodable { let mode, target: String; let targets: [String]?; let end: Double; let tape: [Event]; let history: [Double]; let trace: [Step] }
  private struct Output: Decodable { let fixtures: [Fixture] }

  private func source() throws -> [Fixture] {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else { throw XCTSkip("Requires pinned reference") }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-replay-click.mjs").path, reference, "--statistics"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    return try JSONDecoder().decode(Output.self, from: data).fixtures
  }

  func testStatisticsAgainstCompletePinnedReplayStatsAndStopwatches() throws {
    let fixtures = try source(); XCTAssertEqual(fixtures.count, 15)
    for fixture in fixtures {
      let configuration: TestConfiguration = fixture.mode == "time" ? .timed(seconds: 30)
        : fixture.mode == "zen" ? .init(mode: .zen, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()) : .words(fixture.targets?.count ?? 1)
      let directory = fixture.mode == "zen" ? nil : ResultTargetWordDirectory(words: fixture.targets ?? [fixture.target], noSpace: false)
      let prompt = fixture.mode == "zen" ? "" : fixture.target
      let events = fixture.tape.map { TypingReplayEvent(offset: $0.time, kind: $0.deletion == true ? .delete : .insert, text: $0.text,
        forceError: !$0.correct, inputField: .init(index: $0.index, value: $0.value)) }
      let history = try XCTUnwrap(ResultPerformanceTrace.replayWPMHistory(prompt: prompt, events: events,
        duration: fixture.end, configuration: configuration, targetWordDirectory: directory))
      for index in 0..<(fixture.history.count + 2) {
        let expected = index == 0 || index > fixture.history.count ? 0 : fixture.history[index - 1]
        XCTAssertEqual(history.wpm(at: Double(index)), expected)
      }
      var clock = ReplayStatisticsClock()
      for step in fixture.trace {
        switch step.kind {
        case "load": clock.seek(to: try XCTUnwrap(step.offset))
        case "play": clock.play(from: try XCTUnwrap(step.offset), through: try XCTUnwrap(step.end), at: step.now)
        case "advance": clock.advance(to: step.now)
        case "pause": clock.pause(at: step.now)
        default: XCTFail("Unknown operation")
        }
        let parts = step.label.replacingOccurrences(of: "wpm", with: "").replacingOccurrences(of: "s", with: "").split(separator: "\t")
        let wpm = try XCTUnwrap(parts.first.flatMap { Double($0) }), seconds = try XCTUnwrap(parts.last.flatMap { Double($0) })
        XCTAssertEqual(history.wpm(at: clock.seconds), wpm, "\(fixture.mode) \(step.kind) at \(step.now)")
        XCTAssertEqual(clock.seconds, seconds, "\(fixture.mode) \(step.kind) at \(step.now)")
      }
    }
  }

  func testLongHistoryAndClockAvoidPerSecondStorageAndPendingWork() throws {
    let events = [TypingReplayEvent(offset: 0, kind: .insert, text: "a", inputField: .init(index: 0, value: "a"))]
    let history = try XCTUnwrap(ResultPerformanceTrace.replayWPMHistory(prompt: "a", events: events,
      duration: 1_000_000_000, configuration: .words(1), targetWordDirectory: .init(words: ["a"], noSpace: false)))
    XCTAssertEqual(history.changes.count, 1)
    XCTAssertEqual(history.wpm(at: 1), 12); XCTAssertEqual(history.wpm(at: 1_000_000_000), 0)
    var clock = ReplayStatisticsClock()
    clock.play(from: 0, through: 1_000_000_000, at: 10)
    clock.advance(to: 1_000_000_010)
    XCTAssertEqual(clock.seconds, 1_000_000_000); XCTAssertFalse(clock.hasPending)
    clock.play(from: 0.7, through: 2.6, at: 1_000_000_011)
    clock.seek(to: 1.7); clock.advance(to: 2_000_000_000)
    XCTAssertEqual(clock.seconds, 1); XCTAssertFalse(clock.hasPending)
    let legacy = [TypingReplayEvent(offset: 0, kind: .insert, text: "a")]
    XCTAssertNil(ResultPerformanceTrace.replayWPMHistory(prompt: "a", events: legacy, duration: 2,
      configuration: .words(1), targetWordDirectory: nil))
    XCTAssertNil(ResultPerformanceTrace.replayWPMHistory(prompt: "a", events: events, duration: 2,
      configuration: nil, targetWordDirectory: nil))
    XCTAssertNil(ResultPerformanceTrace.replayWPMHistory(prompt: "a", events: events, duration: 2,
      configuration: .words(1), targetWordDirectory: nil), "Missing captured targets must not be reconstructed for source statistics")
  }

  @MainActor func testLegacyAndInvalidClockEvidenceKeepCompatibilityWithoutRewritingRecords() throws {
    var session = TypingSession(configuration: .words(1), prompt: "ab")
    let start = Date(timeIntervalSinceReferenceDate: 918_500_000)
    session.insert("a", at: start); session.insert("b", at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    XCTAssertNil(result.replayStatisticsDuration)
    let record = TestResultRecord(result: result)
    XCTAssertNil(record.replayStatisticsDuration)
    let bytes = try JSONEncoder().encode(ResultElapsedTime(seconds: 1))
    record.elapsedTimeData = bytes
    XCTAssertEqual(record.replayStatisticsDuration, 1)
    XCTAssertEqual(record.elapsedTimeData, bytes)
    let originalDirectory = record.targetWordDirectoryData
    let brokenDirectory = Data("invalid targets".utf8)
    record.targetWordDirectoryData = brokenDirectory
    XCTAssertNil(record.replayStatisticsDuration)
    XCTAssertEqual(record.targetWordDirectoryData, brokenDirectory)
    record.targetWordDirectoryData = originalDirectory
    record.terminalTimingData = try JSONEncoder().encode(ResultTerminalTiming(version: 1,
      endMilliseconds: 1000, lastKeypressMilliseconds: 500))
    XCTAssertNil(record.replayStatisticsDuration, "Completed words cannot claim Zen/bailout trim evidence")
    record.terminalTimingData = nil
    let malformed = Data("invalid clock".utf8)
    record.elapsedTimeData = malformed
    XCTAssertNil(record.replayStatisticsDuration)
    XCTAssertEqual(record.elapsedTimeData, malformed)
  }

  @MainActor func testNativeStatisticsLabelUsesHistoryAndUpdatesAfterLetterPlaybackEnds() async throws {
    let suite = "typebar-replay-statistics-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let player = TypingFeedbackSound(loadSound: { _ in nil }, beep: {})
    let settings = AppSettings(defaults: defaults, feedbackSound: player, localBackgroundStore: .inMemory())
    let events: [TypingReplayEvent] = [
      .init(offset: 0.51, kind: .insert, text: "a", inputField: .init(index: 0, value: "a")),
      .init(offset: 0.61, kind: .insert, text: "b", inputField: .init(index: 0, value: "ab"))]
    let view = ReplayTimelineView(prompt: "ab", events: events, speedUnit: .wpm, configuration: .words(1),
      targetWordDirectory: .init(words: ["ab"], noSpace: false), statisticsDuration: 0.61,
      sourceScoringBasis: nil, soundConfiguration: .init(settings: settings))
    let controller = NSHostingController(rootView: view.frame(width: 600, height: 260))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 260),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentViewController = controller
    defer { window.close() }
    controller.view.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(30))
    func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
    let label = try XCTUnwrap(views(controller.view).compactMap { $0 as? NSTextField }.first { $0.accessibilityIdentifier() == "replay.statistics" })
    let play = try XCTUnwrap(views(controller.view).compactMap { $0 as? NSButton }.first { $0.title == "播放" })
    XCTAssertEqual(label.stringValue, "0 WPM · 0 秒")
    play.performClick(nil)
    try await Task.sleep(for: .milliseconds(200))
    XCTAssertEqual(play.title, "播放")
    XCTAssertEqual(label.stringValue, "0 WPM · 0 秒")
    try await Task.sleep(for: .milliseconds(600))
    XCTAssertEqual(label.stringValue, "39 WPM · 1 秒")
    XCTAssertEqual(label.accessibilityValue() as? String, label.stringValue)
    XCTAssertTrue(label.toolTip?.contains("0.6 / 0.6") == true)
    let reset = try XCTUnwrap(views(controller.view).compactMap { $0 as? NSButton }.first { $0.title == "重置" })
    reset.performClick(nil)
    try await Task.sleep(for: .milliseconds(30))
    XCTAssertEqual(label.stringValue, "0 WPM · 0 秒")
    let incomplete = [TypingReplayEvent(offset: 0, kind: .insert, text: "b", inputField: .init(index: 1, value: "b"))]
    controller.rootView = ReplayTimelineView(prompt: "a b", events: incomplete, speedUnit: .wpm,
      configuration: .words(2), targetWordDirectory: .init(words: ["a ","b"], noSpace: false),
      statisticsDuration: 1, sourceScoringBasis: nil, soundConfiguration: .init(settings: settings))
      .frame(width: 600, height: 260)
    try await Task.sleep(for: .milliseconds(30))
    XCTAssertTrue(label.stringValue.contains(" / "), "A partial replay plan must retain compatibility presentation")
    XCTAssertFalse(window.isVisible)
  }
}
