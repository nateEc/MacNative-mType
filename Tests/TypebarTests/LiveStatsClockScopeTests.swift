import AppKit
import Observation
import SwiftUI
import XCTest

@MainActor final class LiveStatsClockScopeTests: XCTestCase {
  @Observable final class Clock { var second = 0 }
  private final class Probe {
    var parentBodies = 0
    var displayed = -1
    var changeCaption: (() -> Void)?
    var caption = ""
  }

  private struct Child: View {
    let clock: Clock
    let probe: Probe
    let caption: String
    var body: some View {
      probe.displayed = clock.second
      probe.caption = caption
      return Text("\(caption):\(clock.second)")
    }
  }

  private struct Parent: View {
    let clock: Clock
    let probe: Probe
    let readsInParent: Bool
    @State private var caption = "first"
    var body: some View {
      probe.parentBodies += 1
      probe.changeCaption = { caption = "second" }
      if readsInParent { _ = clock.second }
      return Child(clock: clock, probe: probe, caption: caption)
    }
  }

  func testChildObservationUpdatesClockWithoutInvalidatingUnrelatedParent() throws {
    for readsInParent in [true, false] {
      let clock = Clock(), probe = Probe()
      let host = NSHostingView(rootView: Parent(clock: clock, probe: probe,
        readsInParent: readsInParent))
      let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 300, height: 100),
        styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = host
      defer { probe.changeCaption = nil; window.contentView = nil; window.close() }
      func flush() {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        host.layoutSubtreeIfNeeded()
      }
      flush()
      let initial = probe.parentBodies
      for second in [1, 10, 20] {
        clock.second = second
        flush()
        XCTAssertEqual(probe.displayed, second)
      }
      let afterClock = probe.parentBodies
      if readsInParent { XCTAssertGreaterThan(afterClock, initial) }
      else { XCTAssertEqual(afterClock, initial) }
      try XCTUnwrap(probe.changeCaption)()
      flush()
      XCTAssertEqual(probe.caption, "second", "Parent changes must still reach the clock child")
      XCTAssertGreaterThan(probe.parentBodies, afterClock)
      XCTAssertEqual(probe.displayed, 20)
      XCTAssertFalse(window.isVisible)
      print("clock-scope parentReads=\(readsInParent) initial=\(initial) afterClock=\(afterClock)")
    }
  }
}
