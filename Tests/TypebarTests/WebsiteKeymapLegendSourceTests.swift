import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class WebsiteKeymapLegendSourceTests: XCTestCase {
  func testHiddenProductionGuideDrawsBlankMissingOptionLayerWhileMouseInputKeepsItsFallback() async throws {
    let rows = KeyboardGuideModel.websiteRows(for: .ansiQwerty, mirrored: false)
    let thumbs = KeyboardGuideModel.websiteThumbKeys(for: .ansiQwerty, mirrored: false)
    XCTAssertEqual(rows[1][0].legend(style: .dynamic, modifierFlags: .option, capsLockEnabled: false), "")
    XCTAssertEqual(VirtualKeyboardOutputPolicy.output(for: rows[1][0], shift: false, option: true), "q")
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 900, height: 300), styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let host = NSHostingView(rootView: AnyView(Color.white.frame(width: 900, height: 300)))
    window.contentView = host
    defer { window.contentView = nil; window.close() }
    var ink: [Int] = [], keycaps: [Int] = []
    for option in [false, true] {
      let view = KeyboardGuide(nextCharacter: nil, mode: .staticGuide, feedback: nil, accent: .blue, panel: .white,
        layout: .ansiQwerty, overrideRows: rows, overrideThumbKeys: thumbs, mirrored: false, scale: 2,
        legendStyle: .dynamic, keysMode: .minimal, style: .staggered,
        modifierFlags: option ? .option : [], capsLockEnabled: false)
        .frame(width: 900, height: 300).background(Color.white).environment(\.colorScheme, .light)
      host.rootView = AnyView(view)
      host.frame = .init(x: 0, y: 0, width: 900, height: 300)
      try await Task.sleep(for: .milliseconds(80)); host.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/typebar-keymap-display-\(option ? "option" : "base").png"))
      var count = 0, background = 0
      for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
        if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
          let maximum = max(color.redComponent, color.greenComponent, color.blueComponent)
          if maximum < 0.75 { count += 1 }
          if maximum > 0.85 && maximum < 0.98 { background += 1 }
        }
      } }
      ink.append(count)
      keycaps.append(background)
      XCTAssertFalse(window.isVisible)
    }
    XCTAssertGreaterThan(ink[0], 100, "Baseline must actually render keyboard text")
    XCTAssertLessThan(ink[1], ink[0] / 4, "Missing Option layers must visibly remove typing legends: \(ink)")
    XCTAssertGreaterThan(keycaps[0], 5000); XCTAssertGreaterThan(keycaps[1], 5000)
    XCTAssertLessThan(abs(keycaps[0] - keycaps[1]), keycaps[0] / 10, "Blank text must retain the rendered keyboard: \(keycaps)")
    print("Hidden keymap text pixels: \(ink), keycap pixels: \(keycaps)")
  }

  func testActualPinnedMacDisplaySelectionAcrossAllLayoutsMirrorsStylesAndModifierStates() throws {
    let env = ProcessInfo.processInfo.environment
    guard let reference = env["TYPEBAR_REFERENCE_ROOT"] ?? env["TYPEBAR_LAYOUT_AUDIT_REFERENCE"] else { throw XCTSkip("Requires pinned reference") }
    struct Layout: Decodable { let id: String, native: String; let mirrored: Bool; let rows: [[[String]]] }
    struct Output: Decodable { let styles: [String]; let layouts: [Layout] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-keymap-legends.mjs").path, reference]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.layouts.count, 478); XCTAssertEqual(output.styles, ["blank", "lowercase", "uppercase", "dynamic"])
    var failures: [String] = [], total = 0
    for layout in output.layouts {
      let native = try XCTUnwrap(KeyboardLayout(rawValue: layout.native))
      let rows = KeyboardGuideModel.websiteRows(for: native, mirrored: layout.mirrored)
        + [KeyboardGuideModel.websiteThumbKeys(for: native, mirrored: layout.mirrored)]
      XCTAssertEqual(rows.map(\.count), layout.rows.map(\.count), layout.id)
      guard rows.map(\.count) == layout.rows.map(\.count) else { continue }
      for (r, row) in layout.rows.enumerated() { for (c, labels) in row.enumerated() {
        XCTAssertEqual(labels.count, 32)
        for (s, style) in output.styles.enumerated() { for flags in 0..<8 {
          var modifiers: NSEvent.ModifierFlags = []
          if flags & 1 != 0 { modifiers.insert(.shift) }; if flags & 2 != 0 { modifiers.insert(.option) }
          let actual = rows[r][c].legend(style: try XCTUnwrap(KeyboardGuideLegendStyle(rawValue: style)), modifierFlags: modifiers, capsLockEnabled: flags & 4 != 0)
          let expected = labels[s * 8 + flags]
          if !InputTextIdentity.matches(actual, expected) {
            failures.append("\(layout.id) mirror=\(layout.mirrored) row=\(r) col=\(c) \(style) flags=\(flags): \(actual.debugDescription) != \(expected.debugDescription)")
          }
          total += 1
        } }
      } }
    }
    XCTAssertGreaterThan(total, 730000)
    if !failures.isEmpty {
      print("Display mismatch layouts: \(Dictionary(grouping: failures, by: { $0.components(separatedBy: " ").first ?? "" }).mapValues(\.count))")
    }
    XCTAssertTrue(failures.isEmpty, "\(failures.count) display mismatches: \(failures.prefix(25).joined(separator: "\n"))")
    print("Pinned macOS keymap display samples: \(total), 239 layouts, normal/mirror, four styles, eight modifier states")
  }
}
