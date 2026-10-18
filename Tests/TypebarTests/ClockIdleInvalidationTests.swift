import AppKit
import SwiftUI
import XCTest

@testable import Typebar

@MainActor final class ClockIdleInvalidationTests: XCTestCase {
  private struct LockContent: View {
    let settings: AppSettings
    let probe: Probe

    var body: some View {
      probe.bodyCount += 1
      return Text(settings.allowsRestartingConfigurationChange ? "unlocked" : "locked")
        .frame(width: 300, height: 100)
    }
  }

  func testRepeatedNoQuitLockUpdateDoesNotInvalidateHostedContent() throws {
    let suite = "ClockLockObservationTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    let probe = Probe()
    let host = NSHostingView(rootView: LockContent(settings: settings, probe: probe))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 300, height: 100),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.contentView = nil; window.close() }
    func flush() {
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.02))
      host.layoutSubtreeIfNeeded()
    }
    flush()
    let owner = UUID()
    settings.setNoQuitConfigurationLock(true, for: owner)
    flush()
    XCTAssertFalse(settings.allowsRestartingConfigurationChange)
    let lockedBodyCount = probe.bodyCount
    settings.setNoQuitConfigurationLock(true, for: owner)
    flush()
    XCTAssertEqual(probe.bodyCount, lockedBodyCount)
    settings.setNoQuitConfigurationLock(false, for: owner)
    flush()
    XCTAssertTrue(settings.allowsRestartingConfigurationChange)
    XCTAssertGreaterThan(probe.bodyCount, lockedBodyCount)
    XCTAssertFalse(window.isVisible)
  }

  private final class Probe {
    var bodyCount = 0
    var apply: (() -> Void)?
    var insert: (() -> Void)?
    var rules: InputRules?
    var hasStarted = false
    var typed = ""
    var capsLock = false
    var setCapsLock: ((Bool) -> Void)?
  }

  private struct Content: View {
    let probe: Probe
    let synchronizes: Bool
    let ticks: Bool
    var monitorsCapsLock = false
    @State private var capsLock = false
    @State private var session = TypingSession(
      configuration: .timed(seconds: 30), prompt: "amber birch"
    )
    .withElapsedClock(.system)

    var body: some View {
      probe.bodyCount += 1
      probe.rules = session.configuration.rules
      probe.hasStarted = session.hasStarted
      probe.typed = session.typed
      probe.capsLock = capsLock
      probe.setCapsLock = { capsLock = $0 }
      probe.apply = {
        if synchronizes { session.synchronizeLiveInputRules(.init()) }
        if monitorsCapsLock { capsLock = probe.capsLock }
        if ticks { session.tick() }
      }
      probe.insert = { session.insert("a") }
      return Text(session.prompt + session.typed + (capsLock ? " CAPS" : "")).frame(
        width: 300, height: 100)
    }
  }

  func testIdleClockOperationsRecordActualHostedStateInvalidations() throws {
    for monitorsCapsLock in [false, true] {
      for (synchronizes, ticks) in [(false, false), (true, false), (false, true), (true, true)] {
        let probe = Probe()
        let host = NSHostingView(
          rootView: Content(
            probe: probe, synchronizes: synchronizes, ticks: ticks,
            monitorsCapsLock: monitorsCapsLock))
        let window = NSWindow(
          contentRect: .init(x: 0, y: 0, width: 300, height: 100),
          styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
          probe.apply = nil
          probe.insert = nil
          probe.setCapsLock = nil
          window.contentView = nil
          window.close()
        }
        func flush() {
          host.layoutSubtreeIfNeeded()
          RunLoop.main.run(until: Date().addingTimeInterval(0.03))
          host.layoutSubtreeIfNeeded()
        }
        flush()
        let initial = probe.bodyCount
        XCTAssertGreaterThan(initial, 0)
        for _ in 0..<4 {
          try XCTUnwrap(probe.apply)()
          flush()
        }
        print(
          "idle-clock caps=\(monitorsCapsLock) synchronizes=\(synchronizes) ticks=\(ticks) initial=\(initial) final=\(probe.bodyCount)"
        )
        XCTAssertEqual(probe.rules, .init())
        XCTAssertFalse(probe.hasStarted)
        XCTAssertEqual(probe.typed, "")
        let beforeInput = probe.bodyCount
        try XCTUnwrap(probe.insert)()
        flush()
        XCTAssertGreaterThan(
          probe.bodyCount, beforeInput, "A real input is the positive control for view invalidation"
        )
        XCTAssertTrue(probe.hasStarted)
        XCTAssertEqual(probe.typed, "a")
        let beforeActiveTicks = probe.bodyCount
        for _ in 0..<4 {
          try XCTUnwrap(probe.apply)()
          flush()
        }
        print(
          "active-clock caps=\(monitorsCapsLock) synchronizes=\(synchronizes) ticks=\(ticks) before=\(beforeActiveTicks) final=\(probe.bodyCount)"
        )
        XCTAssertTrue(probe.hasStarted)
        XCTAssertEqual(probe.typed, "a")
        let beforeCapsChange = probe.bodyCount
        try XCTUnwrap(probe.setCapsLock)(true)
        flush()
        XCTAssertTrue(probe.capsLock)
        XCTAssertGreaterThan(
          probe.bodyCount, beforeCapsChange,
          "A real Caps Lock change must still update its presentation")
        XCTAssertFalse(
          window.isVisible, "This probe must not display or launch an application window")
      }
    }
  }
}
