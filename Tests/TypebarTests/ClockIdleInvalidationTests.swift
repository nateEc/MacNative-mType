import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class ClockIdleInvalidationTests: XCTestCase {
  private final class Probe {
    var bodyCount = 0
    var apply: (() -> Void)?
    var insert: (() -> Void)?
    var rules: InputRules?
    var hasStarted = false
    var typed = ""
  }

  private struct Content: View {
    let probe: Probe
    let synchronizes: Bool
    let ticks: Bool
    @State private var session = TypingSession(configuration: .timed(seconds: 30), prompt: "amber birch")
      .withElapsedClock(.system)

    var body: some View {
      probe.bodyCount += 1
      probe.rules = session.configuration.rules
      probe.hasStarted = session.hasStarted
      probe.typed = session.typed
      probe.apply = {
        if synchronizes { session.synchronizeLiveInputRules(.init()) }
        if ticks { session.tick() }
      }
      probe.insert = { session.insert("a") }
      return Text(session.prompt + session.typed).frame(width: 300, height: 100)
    }
  }

  func testIdleClockOperationsRecordActualHostedStateInvalidations() throws {
    for (synchronizes, ticks) in [(false, false), (true, false), (false, true), (true, true)] {
      let probe = Probe()
      let host = NSHostingView(rootView: Content(probe: probe, synchronizes: synchronizes, ticks: ticks))
      let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 300, height: 100),
        styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = host
      defer { probe.apply = nil; probe.insert = nil; window.contentView = nil; window.close() }
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
      print("idle-clock synchronizes=\(synchronizes) ticks=\(ticks) initial=\(initial) final=\(probe.bodyCount)")
      XCTAssertEqual(probe.rules, .init())
      XCTAssertFalse(probe.hasStarted)
      XCTAssertEqual(probe.typed, "")
      let beforeInput = probe.bodyCount
      try XCTUnwrap(probe.insert)()
      flush()
      XCTAssertGreaterThan(probe.bodyCount, beforeInput, "A real input is the positive control for view invalidation")
      XCTAssertTrue(probe.hasStarted)
      XCTAssertEqual(probe.typed, "a")
      let beforeActiveTicks = probe.bodyCount
      for _ in 0..<4 {
        try XCTUnwrap(probe.apply)()
        flush()
      }
      print("active-clock synchronizes=\(synchronizes) ticks=\(ticks) before=\(beforeActiveTicks) final=\(probe.bodyCount)")
      XCTAssertTrue(probe.hasStarted)
      XCTAssertEqual(probe.typed, "a")
      XCTAssertFalse(window.isVisible, "This probe must not display or launch an application window")
    }
  }
}
