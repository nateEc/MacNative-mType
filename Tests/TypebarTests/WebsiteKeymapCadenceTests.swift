import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class WebsiteKeymapCadenceTests: XCTestCase {
  func testActualKeycapUsesTheGlobalFifteenFPSSetting() async throws {
    _ = NSApplication.shared
    let suite = "typebar.keymap-cadence.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults,
      feedbackSound: .init(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
    settings.animationFrameRate = 15
    let clock = WebsiteKeymapPixelClock()
    let rows: [[KeyboardGuideKey]] = [[], [KeyboardGuideKey("owned-a", label: "a", width: 40)
      .withWebsiteLegends(["a", "A", "", ""])], [], []]
    func content(sequence: Int) -> AnyView {
      AnyView(KeyboardGuide(nextCharacter: nil, mode: .react,
      feedback: .init(sequence: sequence, character: "a", isCorrect: true,
        events: [.init(units: [97], isCorrect: true)]), accent: .blue, panel: .white,
      layout: .ansiQwerty, overrideRows: rows, overrideThumbKeys: [], mirrored: false,
      scale: 1, legendStyle: .dynamic, keysMode: .minimal, style: .staggered,
      modifierFlags: [], capsLockEnabled: false)
      .environment(\.websiteKeymapAnimationClock, clock.environment)
      .modifier(PracticeAnimationFrameRate(settings: settings, timerHealth: .init()))
      .frame(width: 300, height: 120))
    }
    let host = NSHostingView(rootView: content(sequence: 1))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 300, height: 120),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { host.rootView = AnyView(EmptyView()); window.contentView = nil; window.close() }
    try await clock.wait(host) { !clock.waits.isEmpty }
    XCTAssertEqual(try XCTUnwrap(clock.waits.first), 1.0 / 15, accuracy: 0.000_001)
    clock.waits.removeAll(); settings.animationFrameRate = 120
    try await clock.wait(host) { !clock.waits.isEmpty }
    XCTAssertEqual(try XCTUnwrap(clock.waits.first), 1.0 / 15, accuracy: 0.000_001,
      "Raising the global cap cannot rewrite the current animation's captured rate")
    clock.waits.removeAll(); host.rootView = content(sequence: 2)
    let expected = 1 / Double(min(120, window.screen?.maximumFramesPerSecond ?? 60))
    try await clock.wait(host) { clock.waits.contains { abs($0 - expected) < 0.000_001 } }
    clock.samples.removeAll(); clock.time = 0.0505
    try await clock.wait(host) { clock.samples.contains { abs($0.progress - 0.434496) < 1e-10 } }
    clock.waits.removeAll(); clock.samples.removeAll(); settings.animationFrameRate = 30
    try await clock.wait(host) { clock.waits.contains { abs($0 - 1.0 / 30) < 0.000_001 } }
    XCTAssertTrue(clock.samples.contains { abs($0.progress - 0.434496) < 1e-10 }, "Changing the cap must not restart the fade")
    clock.waits.removeAll(); clock.time = 0.237
    try await clock.wait(host) { !clock.waits.isEmpty }
    XCTAssertEqual(try XCTUnwrap(clock.waits.first), 1.0 / 30, accuracy: 0.000_001,
      "The final frame must remain subject to the FPS cap")
    XCTAssertFalse(window.isVisible)
  }

  func testActualEngineCapturedAndFreshRatesBoundNativeCadence() throws {
    let env = ProcessInfo.processInfo.environment
    guard let reference = env["TYPEBAR_REFERENCE_ROOT"] ?? env["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference checkout")
    }
    struct Step: Decodable {
      let frameRate: Int, existingAnimationFrameRate: Int, freshAnimationFrameRate: Int
    }
    struct Fixture: Decodable { let initial: Int, steps: [Step] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules",
      root.appendingPathComponent("Scripts/check-source-animation-frame-rate.mjs").path, reference, "--emit-fixtures"]
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode([Fixture].self, from: data)
    XCTAssertEqual(fixtures.count, 50)
    let cadence = WebsiteKeymapAnimationCadence()
    for fixture in fixtures {
      for step in fixture.steps {
        XCTAssertEqual(step.existingAnimationFrameRate, fixture.initial)
        XCTAssertEqual(step.freshAnimationFrameRate, step.frameRate)
        cadence.frameRate = step.frameRate
        for display in [0, 60, 120, 240] {
          cadence.displayFrameRate = display
          let limit = display > 0 ? display : 60
          XCTAssertEqual(cadence.interval(capturedFrameRate: step.existingAnimationFrameRate),
            1 / Double(min(limit, step.frameRate, step.existingAnimationFrameRate)), accuracy: 0.000_001)
          XCTAssertEqual(cadence.interval(capturedFrameRate: step.freshAnimationFrameRate),
            1 / Double(min(limit, step.frameRate)), accuracy: 0.000_001)
        }
      }
    }
  }
}
