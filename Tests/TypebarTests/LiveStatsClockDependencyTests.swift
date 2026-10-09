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
    var usesChildScope = false
    @State private var second = 0
    @State private var signal = LiveStatsClockSignal()
    @State private var session: TypingSession

    init(probe: Probe, readsDelivery: Bool, usesChildScope: Bool = false) {
      self.probe = probe
      self.readsDelivery = readsDelivery
      self.usesChildScope = usesChildScope
      var session = TypingSession(configuration: .timed(seconds: 30), prompt: "amber birch")
        .withElapsedClock(.init(now: { probe.now }))
      session.insert("a")
      _session = State(initialValue: session)
    }

    var body: some View {
      if readsDelivery { _ = second }
      probe.deliver = { if usesChildScope { signal.second = $0 } else { second = $0 } }
      return Group {
        if usesChildScope {
          LiveStatsClockContent(signal: signal) { countdown }
        } else {
          countdown
        }
      }
    }

    private var countdown: some View {
      let value = session.progressText() ?? "—"
      probe.displayed = value
      return Text(value)
    }
  }

  func testHostedCountdownNeedsAnObservedClockDeliveryDependency() throws {
    for (readsDelivery, usesChildScope) in [(false, false), (true, false), (false, true)] {
      let probe = Probe()
      let host = NSHostingView(rootView: Content(probe: probe, readsDelivery: readsDelivery,
        usesChildScope: usesChildScope))
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
        XCTAssertEqual(probe.displayed, (readsDelivery || usesChildScope) ? "\(30 - second)s" : "30s")
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
    let stats = source[start.lowerBound..<end.lowerBound]
    XCTAssertTrue(stats.contains("LiveStatsClockContent(signal: liveStatsClockSignal)"))
    XCTAssertFalse(stats.contains("_ = lastClockTickSecond"))
    XCTAssertTrue(source.contains("liveStatsClockSignal.second = lastDueSecond"))
    XCTAssertEqual(source.components(separatedBy: "liveStatsClockSignal.second = 0").count - 1, 2)
  }
}
