import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class WebsiteKeymapInterruptionTests: XCTestCase {
  private struct Entry: Decodable { let tick: Int, correct: Bool }
  private struct Instance: Decodable {
    let id: Int, at: Double, duration: Double
    let background: [Double], foreground: [Double]
    let initialBackground: Double, initialForeground: Double
  }
  private struct Frame: Decodable { let id: Int, at: Double, background: Double, foreground: Double }
  private struct Completion: Decodable { let id: Int, at: Double }
  private struct Checkpoint: Decodable {
    let at: Double, state: [String: Entry], background: Double, fading: Bool
  }
  private struct Fixture: Decodable {
    let rate: Int, scenario: String
    let instances: [Instance], frames: [Frame], completed: [Completion], checkpoints: [Checkpoint]
  }
  private func source() throws -> [Fixture] {
    let env = ProcessInfo.processInfo.environment
    guard let reference = env["TYPEBAR_REFERENCE_ROOT"] ?? env["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference checkout")
    }
    struct Output: Decodable { let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-keymap-interruption.mjs").path, reference]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 15)
    return fixtures
  }
  private func mix(_ range: [Double], _ progress: Double) -> Double { range[0] + (range[1] - range[0]) * progress }

  func testRealReactiveFramesDistinguishConstructionFromSameMillisecondTick() throws {
    var failures = 0, sameTimeFrames = 0, checked = 0
    for fixture in try source() {
      let instances = Dictionary(uniqueKeysWithValues: fixture.instances.map { ($0.id, $0) })
      for item in fixture.instances {
        let initial = WebsiteKeymapAnimationTiming.initial(duration: item.duration / 1000)
        XCTAssertEqual(mix(item.background, initial.progress), item.initialBackground, accuracy: 1e-8)
        XCTAssertEqual(mix(item.foreground, initial.progress), item.initialForeground, accuracy: 1e-8)
      }
      for frame in fixture.frames {
        let instance = try XCTUnwrap(instances[frame.id])
        let sample = WebsiteKeymapAnimationTiming.sample(elapsed: (frame.at - instance.at) / 1000,
          duration: instance.duration / 1000)
        if abs(mix(instance.background, sample.progress) - frame.background) > 1e-8
          || abs(mix(instance.foreground, sample.progress) - frame.foreground) > 1e-8 {
          failures += 1
        }
        if instance.duration > 0 && frame.at == instance.at { sameTimeFrames += 1 }
        checked += 1
      }
    }
    XCTAssertGreaterThan(checked, 1000)
    XCTAssertGreaterThan(sameTimeFrames, 0, "The oracle must exercise a real zero-elapsed engine tick")
    XCTAssertEqual(failures, 0)
    print("Actual reactive interruption: 15 cases / \(checked) frames / \(sameTimeFrames) same-time ticks")
  }

  @MainActor private final class Host {
    let suite = "typebar.keymap-interruption.\(UUID())"
    let defaults: UserDefaults, settings: AppSettings
    let clock = WebsiteKeymapPixelClock(), store = WebsiteKeymapFeedbackStore()
    let host: NSHostingView<AnyView>, window: NSWindow
    var mode: KeyboardGuideMode = .react
    var highlight: [UInt16]?
    init() throws {
      _ = NSApplication.shared
      defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      settings = AppSettings(defaults: defaults, feedbackSound: .init(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
      host = NSHostingView(rootView: AnyView(EmptyView()))
      window = NSWindow(contentRect: .init(x: 0, y: 0, width: 300, height: 120), styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.contentView = host
      show(.react)
    }
    func show(_ mode: KeyboardGuideMode) {
      self.mode = mode
      let rows: [[KeyboardGuideKey]] = [[], [KeyboardGuideKey("owned-a", label: "a", width: 40)
        .withWebsiteLegends(["a", "A", "", ""])], [], []]
      host.rootView = AnyView(KeyboardGuide(nextCharacter: nil, mode: mode, feedback: nil, accent: .blue, panel: .white,
        layout: .ansiQwerty, overrideRows: rows, overrideThumbKeys: [], websiteFeedback: store,
        websiteHighlight: .init(units: highlight), mirrored: false, scale: 1, legendStyle: .dynamic,
        keysMode: .minimal, style: .staggered, modifierFlags: [], capsLockEnabled: false)
        .environment(\.websiteKeymapAnimationClock, clock.environment)
        .modifier(PracticeAnimationFrameRate(settings: settings, timerHealth: .init()))
        .frame(width: 300, height: 120))
    }
    func flash(_ correct: Bool) {
      highlight = nil; store.receive([.init(units: [97], isCorrect: correct)]); show(mode)
    }
    func close() {
      host.rootView = AnyView(EmptyView()); window.contentView = nil; window.close()
      defaults.removePersistentDomain(forName: suite)
    }
  }

  func testActualRepeatedKeyRestartsAtSameTimeAndOldCompletionCannotClearIt() async throws {
    let fixture = try XCTUnwrap(source().first { $0.rate == 1000 && $0.scenario == "repeat" })
    let replay = try XCTUnwrap(fixture.instances.first { $0.duration > 0 && $0.at == 80 })
    let firstTick = try XCTUnwrap(fixture.frames.first { $0.id == replay.id && $0.at == 80 })
    let f = try Host(); defer { f.close() }
    f.flash(true); try await f.clock.wait(f.host) { !f.clock.waits.isEmpty }
    f.clock.samples.removeAll(); f.clock.creations.removeAll(); f.clock.time = 0.08; f.flash(false)
    try await f.clock.wait(f.host) { f.clock.samples.contains { $0.plan.background == [.error, .panel]
      && abs($0.progress - firstTick.foreground) < 1e-8 } }
    XCTAssertTrue(f.clock.creations.contains { $0.plan.background == [.error, .panel] && $0.progress == 0 })
    f.clock.samples.removeAll(); f.clock.time = 0.238
    try await f.clock.wait(f.host) { f.clock.samples.contains { $0.plan.background == [.error, .panel] && $0.progress > 0.8 } }
    XCTAssertEqual(f.store.state.entries[[97]]?.tick, 2)
    f.clock.time = 0.318
    try await f.clock.wait(f.host) { f.store.state.entries.isEmpty }
    XCTAssertFalse(f.window.isVisible)
  }

  func testActualFadeKeepsItsStartWhenReactOrNextReturns() async throws {
    let fixtures = try source()
    for scenario in ["fade-react", "fade-next"] {
      let expected = try XCTUnwrap(fixtures.first { $0.rate == 1000 && $0.scenario == scenario })
      let checkpoint = try XCTUnwrap(expected.checkpoints.first { $0.at == 80 })
      let f = try Host(); defer { f.close() }
      f.highlight = [97]; f.show(.next)
      try await f.clock.wait(f.host) { f.clock.samples.contains { $0.plan.background == [.accent] } }
      f.clock.time = 0.01; f.show(.staticGuide)
      try await f.clock.wait(f.host) { f.clock.samples.contains { $0.plan.fading } }
      f.clock.samples.removeAll(); f.clock.time = 0.08
      if scenario == "fade-react" { f.show(.react); f.flash(true) }
      else { f.highlight = [97]; f.show(.next) }
      try await f.clock.wait(f.host) { f.clock.samples.contains { $0.plan.fading && abs($0.progress - checkpoint.background) < 1e-8 } }
      XCTAssertEqual(f.store.state.entries.isEmpty, checkpoint.state.isEmpty)
      f.clock.time = 0.248
      try await f.clock.wait(f.host) { f.store.state.entries.isEmpty && f.clock.samples.contains { !$0.plan.fading && $0.progress == 1 } }
      XCTAssertFalse(f.window.isVisible)
    }
  }

  func testStaticCompletionAndUnmountMatchSourceRegistryLifetime() async throws {
    let fixtures = try source()
    for scenario in ["static", "unmount"] {
      let expected = try XCTUnwrap(fixtures.first { $0.rate == 1000 && $0.scenario == scenario })
      let checkpoint = try XCTUnwrap(expected.checkpoints.first { $0.at == 400 })
      let f = try Host(); defer { f.close() }
      f.flash(true); try await f.clock.wait(f.host) { !f.clock.waits.isEmpty }
      f.clock.time = 0.08
      if scenario == "static" {
        f.show(.staticGuide); try await f.clock.wait(f.host) { f.store.state.entries.isEmpty }
      } else {
        f.host.rootView = AnyView(EmptyView()); f.host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
      }
      let samples = f.clock.samples.count
      f.clock.time = 0.4; try await Task.sleep(for: .milliseconds(50))
      XCTAssertEqual(f.store.state.entries.isEmpty, checkpoint.state.isEmpty)
      XCTAssertEqual(f.clock.samples.count, samples, "Retired or constant keycaps must not keep delivering animation frames")
      XCTAssertFalse(f.window.isVisible)
    }
  }
}
