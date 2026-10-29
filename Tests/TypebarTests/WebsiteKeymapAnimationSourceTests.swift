import XCTest
import AppKit
import SwiftUI
@testable import Typebar

@MainActor final class WebsiteKeymapAnimationSourceTests: XCTestCase {
  func testCompletedThenRepeatedLogicalKeyGetsNewIdentityEvenWhenItsSourceTickRestarts() throws {
    let env = ProcessInfo.processInfo.environment
    guard let reference = env["TYPEBAR_REFERENCE_ROOT"] ?? env["TYPEBAR_LAYOUT_AUDIT_REFERENCE"] else { throw XCTSkip("Requires pinned reference") }
    struct Replay: Decodable { let sameTick: Bool, sameIdentity: Bool }
    struct Output: Decodable { let replay: Replay }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-keymap-matching.mjs").path, reference, "--flash-state"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let source = try JSONDecoder().decode(Output.self, from: data).replay
    let store = WebsiteKeymapFeedbackStore(), events = [WebsiteKeymapInputEvent(units: [97], isCorrect: true)]
    store.receive(events)
    let first = try XCTUnwrap(store.state.first(for: [[97]]))
    store.complete(legends: [[97]], generation: store.generation, selection: first)
    store.receive(events)
    let second = try XCTUnwrap(store.state.first(for: [[97]]))
    XCTAssertEqual(first.tick == second.tick, source.sameTick)
    XCTAssertEqual(first == second, source.sameIdentity)
    store.complete(legends: [[97]], generation: store.generation, selection: first)
    XCTAssertNotNil(store.state.entries[[97]], "Old completion cannot remove a repeated logical key after tick reset")
  }

  func testHiddenKeycapKeepsNextExitTransitionAndUsesThemeRoles() async throws {
    let clock = WebsiteKeymapPixelClock()
    let rows: [[KeyboardGuideKey]] = [[], [KeyboardGuideKey("a", label: "a", width: 40).withWebsiteLegends(["a", "A", "", ""])], [], []]
    let palette = WebsiteKeymapPalette(accent: .blue, panel: Color(red: 0, green: 1, blue: 0), background: .white, secondary: .black, error: .red)
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 500, height: 200), styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let host = NSHostingView(rootView: AnyView(Color.white.frame(width: 500, height: 200)))
    window.contentView = host; defer { window.contentView = nil; window.close() }
    func update(_ mode: KeyboardGuideMode) {
      host.rootView = AnyView(KeyboardGuide(nextCharacter: "a", mode: mode, feedback: nil, accent: .blue, panel: .white,
        layout: .ansiQwerty, overrideRows: rows, overrideThumbKeys: [], websitePalette: palette,
        mirrored: false, scale: 2, legendStyle: .dynamic, keysMode: .minimal, style: .staggered,
        modifierFlags: [], capsLockEnabled: false).frame(width: 500, height: 200).background(Color.white).environment(\.colorScheme, .light)
        .environment(\.websiteKeymapAnimationClock, clock.environment))
      host.frame = .init(x: 0, y: 0, width: 500, height: 200)
    }
    func capture(_ name: String) throws -> (green: Double, blue: Double) {
      host.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/typebar-keymap-fade-\(name).png"))
      // cacheDisplay uses the attached monitor's ICC profile (including HDR).
      // Convert its tagged CGImage before interpreting numeric RGB channels.
      let context = try XCTUnwrap(CGContext(data: nil, width: bitmap.pixelsWide, height: bitmap.pixelsHigh,
        bitsPerComponent: 8, bytesPerRow: 0, space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(try XCTUnwrap(bitmap.cgImage), in: .init(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
      let sample = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
      var count = 0, green = 0.0, blue = 0.0
      for x in 0..<bitmap.pixelsWide { for y in 0..<bitmap.pixelsHigh {
        if let c = sample.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.redComponent < 0.2 {
          count += 1; green += c.greenComponent; blue += c.blueComponent
        }
      } }
      XCTAssertGreaterThan(count, 2000, "Keyboard must actually be drawn")
      return (green / Double(max(1, count)), blue / Double(max(1, count)))
    }
    update(.next)
    try await clock.wait(host) { clock.samples.contains { $0.plan.background == [.accent] } }
    let initial = try capture("initial")
    clock.samples.removeAll()
    update(.staticGuide)
    try await clock.wait(host) { clock.creations.contains { $0.plan.fading && $0.progress == 0 } }
    clock.samples.removeAll(); clock.time = 0.0505
    try await clock.wait(host) { clock.samples.contains { $0.plan.fading && abs($0.progress - 0.434496) < 1e-10 } }
    let middle = try capture("middle")
    clock.samples.removeAll(); clock.time = 0.238
    try await clock.wait(host) { clock.samples.contains { !$0.plan.fading && $0.progress == 1 } }
    let ended = try capture("ended")
    XCTAssertGreaterThan(initial.blue, 0.9)
    XCTAssertGreaterThan(middle.blue, 0.1); XCTAssertLessThan(middle.blue, 0.9)
    XCTAssertGreaterThan(middle.green, initial.green)
    XCTAssertLessThan(ended.blue, 0.05); XCTAssertGreaterThan(ended.green, 0.85)
    XCTAssertFalse(window.isVisible)
    print("Hidden next-exit palette samples: \(initial), \(middle), \(ended)")
  }

  func testActualKeyFadePlansAndPinnedEngineCurve() throws {
    let env = ProcessInfo.processInfo.environment
    guard let reference = env["TYPEBAR_REFERENCE_ROOT"] ?? env["TYPEBAR_LAYOUT_AUDIT_REFERENCE"] else { throw XCTSkip("Requires pinned reference") }
    struct Step: Decodable { let mode: String; let matches: Bool; let tick: Int; let correct: Bool; let complete: Bool; let expected: WebsiteKeymapAnimationState.Plan }
    struct Fixture: Decodable { let steno: Bool; let steps: [Step] }
    struct Sample: Decodable { let elapsed: Double, progress: Double }
    struct Output: Decodable { let fixtures: [Fixture], curve: [Sample] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-keymap-animation.mjs").path, reference]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.fixtures.count, 288)
    var failures = 0
    for fixture in output.fixtures {
      var state = WebsiteKeymapAnimationState()
      for step in fixture.steps {
        if step.complete { state.complete() }
        let actual = state.update(mode: try XCTUnwrap(KeyboardGuideMode(rawValue: step.mode)), steno: fixture.steno,
          matches: step.matches, tick: step.tick, correct: step.correct)
        if actual != step.expected { failures += 1 }
      }
    }
    XCTAssertEqual(failures, 0)
    for sample in output.curve { XCTAssertEqual(WebsiteKeymapAnimationState.progress(elapsed: sample.elapsed), sample.progress, accuracy: 0.000001) }
    print("Pinned keymap animation plans: \(output.fixtures.count * 4), actual engine seek samples: \(output.curve.count)")
  }
}
