import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class PracticeAnimationFrameRateTests: XCTestCase {
  @Observable final class Model { var health = TimerHealthState() }
  private final class Readout: NSView { var frameRate = 0 }
  private struct Reader: NSViewRepresentable {
    @Environment(\.typebarAnimationFrameRate) var frameRate
    func makeNSView(context: Context) -> Readout { Readout() }
    func updateNSView(_ view: Readout, context: Context) { view.frameRate = frameRate }
  }
  private struct Root: View {
    let settings: AppSettings
    let model: Model
    var body: some View {
      Reader().modifier(PracticeAnimationFrameRate(settings: settings, timerHealth: model.health))
    }
  }

  private func withFixture(_ verify: (AppSettings, Model, () throws -> Int) throws -> Void) throws {
    let suite = "TypebarTests.practice-fps.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults), model = Model()
    let host = NSHostingView(rootView: Root(settings: settings, model: model))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 120, height: 60),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    defer { window.contentView = nil }
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    try verify(settings, model) {
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.04))
      XCTAssertFalse(window.isVisible)
      return try XCTUnwrap(descendants(host).compactMap { $0 as? Readout }.first).frameRate
    }
  }

  func testSlowTimerOverridesEvenALowerRequestedFrameRateAndStaysUntilCleared() {
    var health = TimerHealthState()
    for rate in [15, 24, 30, 60, 120, 1_000] {
      XCTAssertEqual(health.animationFrameRate(requested: rate), rate)
    }
    health.observe(drift: 0.125, configuration: .timed(seconds: 15))
    XCTAssertEqual(health.animationFrameRate(requested: 15), 15)
    health.observe(drift: 0.126, configuration: .timed(seconds: 15))
    health.observe(drift: 0, configuration: .timed(seconds: 15))
    for rate in [15, 24, 30, 60, 120, 1_000] {
      XCTAssertEqual(health.animationFrameRate(requested: rate), 30)
    }
    health = .init()
    XCTAssertEqual(health.animationFrameRate(requested: 15), 15)
  }

  func testProductionEnvironmentRestoresChangedSettingWithoutResettingDriftCount() throws {
    try withFixture { settings, model, frameRate in
      settings.animationFrameRate = 15
      XCTAssertEqual(try frameRate(), 15)
      model.health.observe(drift: 0.26, configuration: .words(25),
        animationSettingsRevision: settings.animationFrameRateRevision)
      XCTAssertEqual(try frameRate(), 30)
      settings.animationFrameRate = 60
      XCTAssertEqual(try frameRate(), 60)
      XCTAssertEqual(model.health.severeDriftCount, 1)
      model.health.observe(drift: 0, configuration: .words(25),
        animationSettingsRevision: settings.animationFrameRateRevision)
      XCTAssertEqual(try frameRate(), 60)
      model.health.observe(drift: 0.126, configuration: .words(25),
        animationSettingsRevision: settings.animationFrameRateRevision)
      XCTAssertEqual(try frameRate(), 30)
      model.health = .init()
      XCTAssertEqual(try frameRate(), 60)
    }
  }

  func testReapplyingNativeSettingClearsTemporaryOverrideEvenWithoutAValueChange() throws {
    try withFixture { settings, model, frameRate in
      XCTAssertEqual(try frameRate(), 1_000)
      model.health.observe(drift: 0.26, configuration: .timed(seconds: 30),
        animationSettingsRevision: settings.animationFrameRateRevision)
      XCTAssertEqual(try frameRate(), 30)
      settings.animationFrameRate = 1_000
      XCTAssertEqual(try frameRate(), 1_000)
      XCTAssertEqual(model.health.severeDriftCount, 1)
      model.health.observe(drift: 0.26, configuration: .timed(seconds: 30),
        animationSettingsRevision: settings.animationFrameRateRevision)
      XCTAssertEqual(try frameRate(), 30)
      XCTAssertEqual(model.health.severeDriftCount, 2)
    }
  }

  func testTemporaryOverrideNeverPersistsAsTheRequestedPreference() throws {
    let suite = "TypebarTests.practice-fps-persistence.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    settings.animationFrameRate = 15
    let revision = settings.animationFrameRateRevision
    var health = TimerHealthState()
    health.observe(drift: 0.26, configuration: .words(25))
    XCTAssertEqual(health.animationFrameRate(requested: settings.animationFrameRate), 30)
    XCTAssertEqual(settings.animationFrameRateRevision, revision)
    XCTAssertEqual(settings.animationFrameRate, 15)
    XCTAssertEqual(AppSettings(defaults: defaults).animationFrameRate, 15)
    let data = try JSONEncoder().encode(settings.snapshot)
    let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertNil(encoded["animationFrameRateRevision"])
    let restored = try JSONDecoder().decode(AppSettingsSnapshot.self, from: data)
    XCTAssertEqual(restored.animationFrameRate, 15)
    health.restoreAnimationFrameRate()
    XCTAssertEqual(health.animationFrameRate(requested: restored.animationFrameRate), 15)
    XCTAssertEqual(health.severeDriftCount, 1)
  }

  func testSettingsImportAlsoRestoresTheProductionEnvironment() throws {
    try withFixture { settings, model, frameRate in
      XCTAssertEqual(try frameRate(), 1_000)
      model.health.observe(drift: 0.26, configuration: .words(25),
        animationSettingsRevision: settings.animationFrameRateRevision)
      XCTAssertEqual(try frameRate(), 30)
      settings.apply(.init(animationFrameRate: 24))
      XCTAssertEqual(try frameRate(), 24)
      XCTAssertEqual(model.health.severeDriftCount, 1)
      model.health.observe(drift: 0.26, configuration: .words(25),
        animationSettingsRevision: settings.animationFrameRateRevision)
      XCTAssertEqual(try frameRate(), 30)
    }
  }

  func testCompletePinnedAnimationModuleAndTimerFunctionsMatchNativeLifecycle() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference checkout and QA-only Anime.js archive")
    }
    struct Action: Decodable { let kind: String, value: Double }
    struct Step: Decodable {
      let action: Action, frameRate: Int, requested: Int, severeDrifts: Int, failed: Bool, slowTimer: Bool
    }
    struct Fixture: Decodable { let initial: Int, mode: String, limit: Int, steps: [Step] }
    let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules",
      project.appendingPathComponent("Scripts/check-source-animation-frame-rate.mjs").path,
      reference, "--emit-fixtures"]
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode([Fixture].self, from: data)
    XCTAssertEqual(fixtures.count, 50)
    for fixture in fixtures {
      let mode = try XCTUnwrap(TestMode(rawValue: fixture.mode))
      let configuration = TestConfiguration(mode: mode,
        duration: mode == .time || mode == .custom ? Double(fixture.limit) : nil,
        wordLimit: mode == .words ? fixture.limit : nil, difficulty: .normal, rules: .init())
      var health = TimerHealthState(), requested = fixture.initial, revision = 0
      XCTAssertEqual(fixture.steps.count, 11)
      for step in fixture.steps {
        switch step.action.kind {
        case "observe": health.observe(drift: step.action.value / 1_000, configuration: configuration,
          animationSettingsRevision: revision)
        case "set": requested = Int(step.action.value); revision += 1
        case "clear": health.restoreAnimationFrameRate()
        default: XCTFail("Unknown source action: \(step.action.kind)")
        }
        let context = "\(fixture.mode)/\(fixture.limit)/\(fixture.initial)/\(step.action.kind)/\(step.action.value)"
        XCTAssertEqual(health.animationFrameRate(requested: requested, settingsRevision: revision), step.frameRate, context)
        XCTAssertEqual(requested, step.requested, context)
        XCTAssertEqual(health.severeDriftCount, step.severeDrifts, context)
        XCTAssertEqual(health.shouldFail, step.failed, context)
        XCTAssertEqual(health.usesSlowTimer, step.slowTimer, context)
      }
    }
  }

  func testChangingSettingThenObservingNewDriftInOneRenderPassKeepsTheNewOverride() throws {
    try withFixture { settings, model, frameRate in
      XCTAssertEqual(try frameRate(), 1_000)
      model.health.observe(drift: 0.26, configuration: .words(25),
        animationSettingsRevision: settings.animationFrameRateRevision)
      XCTAssertEqual(try frameRate(), 30)
      settings.animationFrameRate = 60
      model.health.observe(drift: 0.126, configuration: .words(25),
        animationSettingsRevision: settings.animationFrameRateRevision)
      XCTAssertEqual(try frameRate(), 30)
      XCTAssertEqual(try frameRate(), 30)
      XCTAssertEqual(model.health.severeDriftCount, 1)
    }
  }
}
