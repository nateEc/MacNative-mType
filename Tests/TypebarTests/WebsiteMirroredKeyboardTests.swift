import AppKit
import XCTest
@testable import Typebar

@MainActor final class WebsiteMirroredKeyboardTests: XCTestCase {
  func testMirroredThumbKeysKeepTheirNewPayloadAndAlternateSpaceLayers() throws {
    let prsten = KeyboardGuideModel.mirroredThumbKeys(for: .prsten)
    XCTAssertEqual(prsten.map(\.id), ["space", "thumb-1"])
    XCTAssertEqual(VirtualKeyboardOutputPolicy.output(for: prsten[0], shift: false, option: false), "e")
    XCTAssertEqual(VirtualKeyboardOutputPolicy.output(for: prsten[1], shift: false, option: false), " ")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: " ", rows: [prsten]), "thumb-1")
    XCTAssertEqual(KeyboardGuideModel.highlightedLabel(for: "space", rows: [], thumbs: prsten), "E")
    XCTAssertEqual(KeyboardGuideModel.highlightedLabel(for: "thumb-1", rows: [], thumbs: prsten), "空格")
    let afnor = try XCTUnwrap(KeyboardGuideModel.mirroredThumbKeys(for: .frenchAzertyAFNOR).first)
    XCTAssertEqual(VirtualKeyboardOutputPolicy.output(for: afnor, shift: false, option: true), "\u{00A0}")
    XCTAssertEqual(VirtualKeyboardOutputPolicy.output(for: afnor, shift: true, option: true), "\u{202F}")
  }
  func testPinnedMirroredEmulatorGuideAndReverseLookupAcrossAllAuthoredLayouts() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let reference = environment["TYPEBAR_REFERENCE_ROOT"] ?? environment["TYPEBAR_LAYOUT_AUDIT_REFERENCE"] else { throw XCTSkip("Requires pinned reference") }
    struct Fixture: Decodable { let macCode: UInt16, row: Int, column: Int, flags: Int; let text: String?; let reverse: UInt16? }
    struct Layout: Decodable { let id: String, native: String; let fixtures: [Fixture] }
    struct Output: Decodable { let layouts: [Layout] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-mirrored-keyboard.mjs").path, reference]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.layouts.count, 239)
    var mismatches: [String] = [], total = 0
    for layout in output.layouts {
      let native = try XCTUnwrap(KeyboardLayout(rawValue: layout.native))
      let rows = KeyboardGuideModel.mirroredRows(for: native) + [KeyboardGuideModel.mirroredThumbKeys(for: native)]
      for f in layout.fixtures {
        var flags: NSEvent.ModifierFlags = []
        if f.flags & 1 != 0 { flags.insert(.shift) }; if f.flags & 2 != 0 { flags.insert(.option) }
        let actual = KeyboardLayoutEmulator.text(forKeyCode: f.macCode, modifierFlags: flags, mapping: .mirrored(native))
        if !equal(actual, f.text) { mismatches.append("\(layout.id) code \(f.macCode) layer \(f.flags): text \(String(reflecting: actual)) != \(String(reflecting: f.text))") }
        if let text = f.text {
          let reverse = KeyboardLayoutEmulator.keyCode(forOutput: text, mapping: .mirrored(native))
          if reverse != f.reverse { mismatches.append("\(layout.id) \(text.debugDescription): reverse \(String(describing: reverse)) != \(String(describing: f.reverse))") }
        }
        let key = try XCTUnwrap(rows[safe: f.row]?[safe: f.column])
        var legend = key.legend(style: .dynamic, modifierFlags: flags, capsLockEnabled: false)
        if (legend == "空格" || legend.isEmpty), key.characters.contains(" ") { legend = " " }
        if !equal(legend, f.text) { mismatches.append("\(layout.id) row \(f.row) column \(f.column) layer \(f.flags): legend \(legend.debugDescription) != \(String(reflecting: f.text))") }
        total += 1
      }
    }
    XCTAssertTrue(mismatches.isEmpty, "\(mismatches.count) mirror mismatches: \(mismatches.prefix(20).joined(separator: "\n"))")
    print("Mirrored source emulation/guide/reverse samples: \(total) across \(output.layouts.count) layouts")
  }
  private func equal(_ a: String?, _ b: String?) -> Bool {
    switch (a,b) { case (nil,nil): true; case let (.some(a),.some(b)): InputTextIdentity.matches(a,b); default: false }
  }
}

private extension Array {
  subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
