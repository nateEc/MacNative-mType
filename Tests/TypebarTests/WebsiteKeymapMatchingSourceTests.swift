import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class WebsiteKeymapMatchingSourceTests: XCTestCase {
  func testRapidPrimitiveFeedbackKeepsIndependentColorsAndClearsOnPhysicalKeyCompletion() async throws {
    let rows: [[KeyboardGuideKey]] = [[], ["a", "b", "ab"].map {
      KeyboardGuideKey($0, label: $0, characters: $0, width: 40).withWebsiteLegends([$0, $0, "", ""])
    }, [], []]
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 700, height: 180), styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let host = NSHostingView(rootView: AnyView(Color.white.frame(width: 700, height: 180)))
    window.contentView = host; defer { window.contentView = nil; window.close() }
    let store = WebsiteKeymapFeedbackStore()
    host.rootView = AnyView(KeyboardGuide(nextCharacter: nil, mode: .react,
        feedback: nil, accent: .blue, panel: .white,
        layout: .ansiQwerty, overrideRows: rows, overrideThumbKeys: [], websiteFeedback: store, mirrored: false, scale: 2,
        legendStyle: .dynamic, keysMode: .minimal, style: .staggered, modifierFlags: [], capsLockEnabled: false)
        .frame(width: 700, height: 180).background(Color.white).environment(\.colorScheme, .light))
    host.frame = .init(x: 0, y: 0, width: 700, height: 180)
    func capture(_ name: String) throws -> (red: Int, blue: Int, gray: Int) {
      host.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/typebar-keymap-rapid-\(name).png"))
      var red = 0, blue = 0, gray = 0
      for x in 0..<bitmap.pixelsWide { for y in 0..<bitmap.pixelsHigh {
        guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
        if r > 0.5 && r - g > 0.18 && r - b > 0.18 { red += 1 }
        if b > 0.5 && b - r > 0.18 && b - g > 0.08 { blue += 1 }
        if max(r, g, b) > 0.85 && max(r, g, b) < 0.98 { gray += 1 }
      } }
      return (red, blue, gray)
    }
    try await Task.sleep(for: .milliseconds(20)); host.layoutSubtreeIfNeeded()
    // No await or frame delivery between these input callbacks.
    store.receive([.init(units: [97], isCorrect: false)])
    store.receive([.init(units: [98], isCorrect: true)])
    try await Task.sleep(for: .milliseconds(20))
    let active = try capture("active")
    XCTAssertGreaterThan(active.red, 500); XCTAssertGreaterThan(active.blue, 500)
    let oldGeneration = store.generation
    store.reset(); store.receive([.init(units: [97], isCorrect: true)])
    store.complete(legends: [[97]], generation: oldGeneration, selection: store.state.first(for: [[97]]))
    XCTAssertEqual(store.state.entries[[97]]?.isCorrect, true, "Old completion cannot clear the replacement attempt")
    try await Task.sleep(for: .milliseconds(300))
    let ended = try capture("ended")
    XCTAssertEqual(ended.red, 0); XCTAssertEqual(ended.blue, 0); XCTAssertGreaterThan(ended.gray, 5000)
    XCTAssertFalse(window.isVisible)
    print("Hidden independent keymap pulses active=\(active), ended=\(ended)")
  }

  func testHiddenGuideHighlightsEveryExactMatchAndFlashesPrimitiveKeysInsteadOfCompoundLabel() async throws {
    func key(_ id: String, _ text: String) -> KeyboardGuideKey {
      KeyboardGuideKey(id, label: text, characters: text, width: 40).withWebsiteLegends([text, text, "", ""])
    }
    let rows: [[KeyboardGuideKey]] = [[], [key("nfc-1", "é"), key("nfc-2", "é"), key("nfd", "e\u{301}"), key("compound", "ab"), key("a", "a"), key("b", "b")], [], []]
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 900, height: 300), styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let host = NSHostingView(rootView: AnyView(Color.white.frame(width: 900, height: 300)))
    window.contentView = host; defer { window.contentView = nil; window.close() }
    let cases: [(String, KeyboardGuideMode, Character?, KeyboardGuideFeedback?, Int, Bool)] = [
      ("nfc", .next, "é", nil, 2, false),
      ("nfd", .next, "e\u{301}", nil, 1, false),
      ("static", .staticGuide, "é", nil, 0, false),
      ("compound", .react, nil, .init(sequence: 1, character: "b", isCorrect: true, events: [.init(units: [97], isCorrect: true), .init(units: [98], isCorrect: true)]), 2, false),
      ("error", .react, nil, .init(sequence: 2, character: "é", isCorrect: false, events: [.init(units: [233], isCorrect: false)]), 2, true),
    ]
    var starts: [[Int]] = []
    for (name, mode, next, feedback, count, red) in cases {
      let clock = WebsiteKeymapPixelClock()
      host.rootView = AnyView(KeyboardGuide(nextCharacter: next, mode: mode, feedback: feedback, accent: .blue, panel: .white,
        layout: .ansiQwerty, overrideRows: rows, overrideThumbKeys: [], mirrored: false, scale: 2,
        legendStyle: .dynamic, keysMode: .minimal, style: .staggered, modifierFlags: [], capsLockEnabled: false)
        .frame(width: 900, height: 300).background(Color.white).environment(\.colorScheme, .light)
        .environment(\.websiteKeymapAnimationClock, clock.environment).id(name))
      host.frame = .init(x: 0, y: 0, width: 900, height: 300)
      try await clock.wait(host) {
        mode == .react
          ? clock.samples.contains { $0.plan.duration > 0 && $0.plan.background.first == (red ? .error : .accent) }
          : clock.samples.count >= 6
      }
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/typebar-keymap-match-\(name).png"))
      var columns = Array(repeating: 0, count: bitmap.pixelsWide), backgrounds = 0
      for x in 0..<bitmap.pixelsWide { for y in 0..<bitmap.pixelsHigh {
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        let r = color.redComponent, g = color.greenComponent, b = color.blueComponent
        if red ? (r > 0.5 && r - g > 0.18 && r - b > 0.18) : (b > 0.5 && b - r > 0.18 && b - g > 0.08) { columns[x] += 1 }
        if max(r, g, b) > 0.85 && max(r, g, b) < 0.98 { backgrounds += 1 }
      } }
      let active = columns.indices.filter { columns[$0] > 5 }
      let clusters = active.filter { $0 == 0 || columns[$0 - 1] <= 5 }
      XCTAssertEqual(clusters.count, count, "\(name): \(clusters)")
      XCTAssertGreaterThan(backgrounds, 2000, "Keyboard must remain drawn: \(name)")
      let pixelsPerPoint = Double(bitmap.pixelsWide) / Double(host.bounds.width)
      starts.append(clusters.map { Int((Double($0) / pixelsPerPoint).rounded()) })
      XCTAssertFalse(window.isVisible)
    }
    if starts[1].count == 1, starts[3].count == 2 {
      XCTAssertEqual(starts[3][0] - starts[1][0], 176, accuracy: 5, "Source splits compound insertion into primitive events")
      XCTAssertEqual(starts[3][1] - starts[1][0], 264, accuracy: 5)
    }
    print("Hidden exact-match keycap positions: \(starts)")
  }

  func testActualPinnedHighlightEventAndAllExactMatchingKeysAcrossLayoutsAndMirrors() throws {
    let env = ProcessInfo.processInfo.environment
    guard let reference = env["TYPEBAR_REFERENCE_ROOT"] ?? env["TYPEBAR_LAYOUT_AUDIT_REFERENCE"] else { throw XCTSkip("Requires pinned reference") }
    struct Fixture: Decodable { let key: String; let matches: [Int] }
    struct Layout: Decodable { let id: String, native: String; let mirrored: Bool; let fixtures: [Fixture] }
    struct Output: Decodable { let layouts: [Layout] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-keymap-matching.mjs").path, reference]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.layouts.count, 478)
    var failures: [String] = [], total = 0, multiple = 0
    for layout in output.layouts {
      let native = try XCTUnwrap(KeyboardLayout(rawValue: layout.native))
      let rows = KeyboardGuideModel.websiteRows(for: native, mirrored: layout.mirrored)
        + [KeyboardGuideModel.websiteThumbKeys(for: native, mirrored: layout.mirrored)]
      for f in layout.fixtures {
        let expected = Set(f.matches.map { rows[$0 / 100][$0 % 100].id })
        let actual = KeyboardGuideModel.websiteMatchingKeys(for: f.key, rows: rows)
        if actual != expected { failures.append("\(layout.id) mirror=\(layout.mirrored) \(f.key.debugDescription): \(actual.sorted()) != \(expected.sorted())") }
        if expected.count > 1 { multiple += 1 }
        for style in [KeyboardGuideStyle.steno, .stenoMatrix] {
          XCTAssertTrue(KeyboardGuideModel.websiteMatchingKeys(for: f.key, rows: rows, style: style).isEmpty)
        }
        total += 1
      }
      XCTAssertTrue(KeyboardGuideModel.websiteMatchingKeys(for: nil, rows: rows).isEmpty)
    }
    XCTAssertGreaterThan(total, 40000); XCTAssertGreaterThan(multiple, 100)
    XCTAssertTrue(failures.isEmpty, "\(failures.count) exact highlight mismatches: \(failures.prefix(25).joined(separator: "\n"))")
    print("Pinned all-key matching queries: \(total), multiple-match queries: \(multiple), 239 layouts normal/mirrored")
  }
}
