import AppKit
import XCTest
@testable import Typebar

@MainActor final class WebsiteCapsLockEmulationTests: XCTestCase {
  func testCapsLockKeepsSystemCustomAndNativeExtensionMappingsOnTheirExistingPaths() throws {
    XCTAssertNil(KeyboardLayoutEmulator.text(forKeyCode: 0, modifierFlags: [.capsLock], mapping: .system))
    let custom = CustomKeyboardGuideLayout(name: "Native caps policy", numberRow: "1", topRow: "q", homeRow: "a", bottomRow: "z")
    for shift in [false, true] {
      let before: NSEvent.ModifierFlags = shift ? [.shift] : []
      XCTAssertEqual(KeyboardLayoutEmulator.text(forKeyCode: 0, modifierFlags: before.union(.capsLock), mapping: .custom(custom)), shift ? "A" : "a")
      XCTAssertEqual(KeyboardLayoutEmulator.text(forKeyCode: 0, modifierFlags: before.union(.capsLock), mapping: .builtIn(.nordicQwerty)),
        KeyboardLayoutEmulator.text(forKeyCode: 0, modifierFlags: before, mapping: .builtIn(.nordicQwerty)))
    }
    XCTAssertNil(KeyboardLayoutEmulator.text(forKeyCode: 0, modifierFlags: [.command, .capsLock], mapping: .builtIn(.ansiQwerty)))
    XCTAssertNil(KeyboardLayoutEmulator.text(forKeyCode: 0, modifierFlags: [.control, .capsLock], mapping: .mirrored(.ansiQwerty)))
  }
  func testActualPinnedCapsLockAcrossAllLayoutsLayersAndMirrors() throws {
    let env = ProcessInfo.processInfo.environment
    guard let reference = env["TYPEBAR_REFERENCE_ROOT"] ?? env["TYPEBAR_LAYOUT_AUDIT_REFERENCE"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct Fixture: Decodable { let macCode: UInt16, flags: Int; let text: String? }
    struct Layout: Decodable { let id: String, native: String; let mirrored: Bool; let fixtures: [Fixture] }
    struct Output: Decodable { let layouts: [Layout] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-mirrored-keyboard.mjs").path, reference, "--caps-lock"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.layouts.count, 478)
    var failures: [String] = [], total = 0
    for layout in output.layouts {
      let native = try XCTUnwrap(KeyboardLayout(rawValue: layout.native))
      for f in layout.fixtures {
        var flags: NSEvent.ModifierFlags = [.capsLock]
        if f.flags & 1 != 0 { flags.insert(.shift) }
        if f.flags & 2 != 0 { flags.insert(.option) }
        let text = KeyboardLayoutEmulator.text(forKeyCode: f.macCode, modifierFlags: flags,
          mapping: layout.mirrored ? .mirrored(native) : .builtIn(native))
        let same = text == nil && f.text == nil || text.flatMap { value in f.text.map { InputTextIdentity.matches(value, $0) } } == true
        if !same { failures.append("\(layout.id) mirror=\(layout.mirrored) key=\(f.macCode) flags=\(f.flags): \(String(reflecting: text)) != \(String(reflecting: f.text))") }
        total += 1
      }
    }
    XCTAssertEqual(total, 92120)
    XCTAssertTrue(failures.isEmpty, "\(failures.count) Caps Lock mismatches: \(failures.prefix(25).joined(separator: "\n"))")
    print("Caps Lock source samples: \(total), 239 layouts, normal and mirrored")
  }
}
