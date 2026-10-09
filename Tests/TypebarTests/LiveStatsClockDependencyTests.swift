import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class LiveStatsClockDependencyTests: XCTestCase {
  private final class Probe {
    var now: TimeInterval = 0
    var displayed = ""
    var deliver: ((Int) -> Void)?
  }

  private struct Content: View {
    let probe: Probe
    let readsDelivery: Bool
    @State private var second = 0
    @State private var session: TypingSession

    init(probe: Probe, readsDelivery: Bool) {
      self.probe = probe
      self.readsDelivery = readsDelivery
      var session = TypingSession(configuration: .timed(seconds: 30), prompt: "amber birch")
        .withElapsedClock(.init(now: { probe.now }))
      session.insert("a")
      _session = State(initialValue: session)
    }

    var body: some View {
      if readsDelivery { _ = second }
      probe.deliver = { second = $0 }
      let value = session.progressText() ?? "—"
      probe.displayed = value
      return Text(value)
    }
  }

  func testHostedCountdownNeedsAnObservedClockDeliveryDependency() throws {
    for readsDelivery in [false, true] {
      let probe = Probe()
      let host = NSHostingView(rootView: Content(probe: probe, readsDelivery: readsDelivery))
      let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 300, height: 100),
        styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = host
      defer { probe.deliver = nil; window.contentView = nil; window.close() }
      func flush() {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        host.layoutSubtreeIfNeeded()
      }
      flush()
      XCTAssertEqual(probe.displayed, "30s")
      for second in [1, 10, 20] {
        probe.now = Double(second)
        try XCTUnwrap(probe.deliver)(second)
        flush()
        XCTAssertEqual(probe.displayed, readsDelivery ? "\(30 - second)s" : "30s")
      }
      XCTAssertFalse(window.isVisible)
    }
  }

  func testProductionStatsReadsTheDeliveredSecond() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent(
      "Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    let start = try XCTUnwrap(source.range(of: "private var stats: some View {"))
    let end = try XCTUnwrap(source.range(of: "private var attentionWarnings:",
      range: start.upperBound..<source.endIndex))
    XCTAssertTrue(source[start.lowerBound..<end.lowerBound].contains("_ = lastClockTickSecond"))
  }
}
