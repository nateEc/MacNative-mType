import AppKit
import Observation
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class WebsiteLayoutFluidFadeTests: XCTestCase {
  func testCadenceUsesCurrentSettingsAndTheOwningHiddenWindow() async throws {
    let cadence = WebsiteLayoutFluidFadeCadence()
    cadence.displayFrameRate = 120
    cadence.frameRate = 15; XCTAssertEqual(cadence.interval, 1.0 / 15)
    cadence.frameRate = 1000; XCTAssertEqual(cadence.interval, 1.0 / 120)
    cadence.displayFrameRate = 60; XCTAssertEqual(cadence.interval, 1.0 / 60)
    _ = NSApplication.shared
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 120, height: 60),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let reader = WebsiteLayoutFluidDisplayCadenceView()
    var reports: [Int] = []; reader.onRate = { reports.append($0) }
    window.contentView = reader
    defer { window.contentView = nil; window.close() }
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while reports.isEmpty, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    XCTAssertEqual(reports.last, window.screen?.maximumFramesPerSecond ?? 60)
    let count = reports.count
    reader.report(); window.contentView = nil
    NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: window)
    try await Task.sleep(for: .milliseconds(20))
    XCTAssertEqual(reports.count, count, "A detached reader must not deliver a screen update")
    XCTAssertFalse(window.isVisible)
  }

  @MainActor @Observable final class Probe {
    var countdown = WebsiteLayoutFluidCountdown()
    @ObservationIgnored var clock = 0.0
    @ObservationIgnored var authority: UUID?
    @ObservationIgnored var samples: [(UUID?, Double)] = []
  }
  private struct Surface: View {
    let probe: Probe
    let reducedMotion: Bool
    var body: some View {
      HStack(spacing: 0) {
        Color(red: 1, green: 0, blue: 0).frame(width: 120, height: 60)
          .modifier(WebsiteLayoutFluidFadeModifier(request: probe.countdown.animationRequest,
            currentRequestID: { probe.authority }, reducedMotion: reducedMotion,
            now: { probe.clock }, didSample: { probe.samples.append(($0, $1)) }))
          .background(Color.white)
        Color(red: 1, green: 0, blue: 0).frame(width: 120, height: 60)
        Color.white.frame(width: 120, height: 60)
      }
    }
  }

  func testHiddenPixelsForRepeatedShowInterruptedHideReducedMotionAndRetirement() async throws {
    _ = NSApplication.shared
    for reduced in [false, true] {
      let probe = Probe()
      let host = NSHostingView(rootView: AnyView(Surface(probe: probe, reducedMotion: reduced)))
      let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 360, height: 60),
        styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.contentView = host
      defer { host.rootView = AnyView(EmptyView()); window.contentView = nil; window.close() }
      func settle(_ ready: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !ready(), ContinuousClock.now < deadline {
          host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(ready())
      }
      func sample(_ id: UUID?, _ value: Double) async throws {
        try await settle { probe.samples.last.map { $0.0 == id && abs($0.1 - value) < 0.000001 } == true }
      }
      func green(_ name: String, column: Int = 0) throws -> Double {
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to:
          URL(fileURLWithPath: "/tmp/typebar-layout-fade-\(reduced)-\(name).png"))
        let context = try XCTUnwrap(CGContext(data: nil, width: bitmap.pixelsWide, height: bitmap.pixelsHigh,
          bitsPerComponent: 8, bytesPerRow: 0, space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(try XCTUnwrap(bitmap.cgImage), in: .init(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
        let converted = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
        let color = try XCTUnwrap(converted.colorAt(x: converted.pixelsWide * (2 * column + 1) / 6,
          y: converted.pixelsHigh / 2)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(color.redComponent, 0.95)
        return color.greenComponent
      }
      try await settle { !probe.samples.isEmpty }
      let initial = try green("initial")
      let opaque = try green("opaque-control", column: 1), white = try green("white-control", column: 2)
      XCTAssertEqual(initial, white, accuracy: 0.01)
      probe.countdown.apply([.show, .text("next")])
      let first = try XCTUnwrap(probe.countdown.animationRequest)
      probe.authority = first.id
      try await sample(first.id, reduced ? 1 : 0)
      if reduced {
        XCTAssertEqual(try green("shown"), opaque, accuracy: 0.01)
        probe.countdown.apply([.hide])
        probe.authority = probe.countdown.animationRequest?.id
        try await sample(probe.countdown.animationRequest?.id, 0)
        XCTAssertEqual(try green("hidden"), white, accuracy: 0.01)
      } else {
        probe.clock = 0.03125; try await sample(first.id, 0.4375)
        let showing = try green("showing")
        XCTAssertLessThan(showing, initial); XCTAssertGreaterThan(showing, opaque)
        probe.countdown.apply([.show])
        let repeated = try XCTUnwrap(probe.countdown.animationRequest)
        probe.authority = repeated.id
        XCTAssertNotEqual(first.id, repeated.id)
        try await sample(repeated.id, 0.4375)
        probe.countdown.apply([.text("changed without restarting")])
        XCTAssertEqual(probe.countdown.animationRequest?.id, repeated.id)
        probe.clock = 0.0625; try await sample(repeated.id, 0.68359375)
        let showingAgain = try green("repeated")
        XCTAssertLessThan(showingAgain, showing)
        probe.countdown.apply([.hide])
        let hiding = try XCTUnwrap(probe.countdown.animationRequest)
        probe.authority = hiding.id
        try await sample(hiding.id, 0.68359375)
        probe.clock = 0.09375; try await sample(hiding.id, 0.384521484375)
        XCTAssertGreaterThan(try green("hiding"), showingAgain)
        // Retire ownership without changing the observed request: the old
        // view task is still present until SwiftUI processes a later update.
        probe.authority = nil
        let count = probe.samples.count
        probe.clock = 1
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(probe.samples.count, count, "A retired animation must not write another frame")
        probe.countdown = .init(); try await sample(nil, 0)
        XCTAssertEqual(try green("retired"), white, accuracy: 0.01)
      }
      XCTAssertFalse(window.isVisible)
    }
  }

  func testActualTimerDurationsAndPinnedEngineOpacitySamples() throws {
    let env = ProcessInfo.processInfo.environment
    guard let reference = env["TYPEBAR_REFERENCE_ROOT"] ?? env["TYPEBAR_LAYOUT_AUDIT_REFERENCE"],
      env["TYPEBAR_LINE_SCROLL_ANIME_ARCHIVE"] != nil else { throw XCTSkip("Requires pinned reference and animation engine") }
    struct Sample: Decodable { let elapsed: Double, opacity: Double }
    struct Fixture: Decodable { let reduceMotion: Bool, from: Double, target: Double, duration: Double, samples: [Sample] }
    struct Output: Decodable { let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-layout-countdown-animation.mjs").path, reference]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 12)
    for f in fixtures {
      let duration = WebsiteLayoutFluidFade.duration(reducedMotion: f.reduceMotion)
      XCTAssertEqual(duration * 1000, f.duration)
      for s in f.samples {
        XCTAssertEqual(WebsiteLayoutFluidFade.opacity(from: f.from, target: f.target, elapsed: s.elapsed, duration: duration),
          s.opacity, accuracy: 0.000001, "from=\(f.from), target=\(f.target), reduced=\(f.reduceMotion), elapsed=\(s.elapsed)")
      }
    }
  }
}
