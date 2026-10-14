import AppKit
import Foundation
import XCTest
@testable import Typebar

/// An opt-in, read-only diagnostic of upstream key legends against native
/// physical-key emulation. A legend discrepancy is not automatically a typing
/// defect; macOS input fallthrough and non-text keys need separate triage. The
/// source layouts are never copied into the app, test bundle, or fixture.
final class OfficialLayoutOutputAuditTests: XCTestCase {
  private struct Mapping: Decodable {
    let referenceCommit: String
    let nativeExact: [String: String]
  }

  private struct ReferenceLayout: Decodable {
    let type: String
    let keys: Rows

    struct Rows: Decodable {
      let row1: [[String]]
      let row2: [[String]]
      let row3: [[String]]
      let row4: [[String]]
    }
  }

  private let ansiCodes: [[UInt16]] = [
    [50, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24],
    [12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30, 42],
    [0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39],
    [6, 7, 8, 9, 11, 45, 46, 43, 47, 44],
  ]

  func testANSIQwertyBackslashKeyMatchesOfficialBaseAndShift() {
    let rows = KeyboardGuideModel.rows(for: .ansiQwerty)
    XCTAssertEqual(rows[0].count, 13)
    XCTAssertEqual(rows[0].first?.label, "`")
    let row = rows[1]
    XCTAssertEqual(row.count, 13)
    XCTAssertEqual(row.last?.label, "\\")
    XCTAssertEqual(row.last?.shiftedLabel, "|")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 42, modifierFlags: [], mapping: .builtIn(.ansiQwerty)), "\\")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 42, modifierFlags: .shift, mapping: .builtIn(.ansiQwerty)), "|")
  }

  func testMacedonianQuestionMarkShiftMatchesOfficialLayout() {
    let lastKey = KeyboardGuideModel.rows(for: .macedonian)[3].last
    XCTAssertEqual(lastKey?.label, "/")
    XCTAssertEqual(lastKey?.shiftedLabel, "?")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 44, modifierFlags: [], mapping: .builtIn(.macedonian)), "/")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 44, modifierFlags: .shift, mapping: .builtIn(.macedonian)), "?")
  }

  func testColemakAndWorkmanVariantsKeepStandardANSIOuterKeys() {
    let layouts: [KeyboardLayout] = [
      .ansiColemak, .ansiColemakDH, .colemakDHMatrix, .colemakDHKANSI, .ansiWorkman,
    ]
    let outerKeys: [(UInt16, String, String)] = [
      (50, "`", "~"), (18, "1", "!"), (19, "2", "@"), (20, "3", "#"),
      (21, "4", "$"), (23, "5", "%"), (22, "6", "^"), (26, "7", "&"),
      (28, "8", "*"), (25, "9", "("), (29, "0", ")"), (27, "-", "_"),
      (24, "=", "+"), (42, "\\", "|"),
    ]
    for layout in layouts {
      let rows = KeyboardGuideModel.rows(for: layout)
      XCTAssertEqual(rows[0].count, 13, "\(layout) number row")
      XCTAssertEqual(rows[0].first?.label, "`", "\(layout) grave key")
      XCTAssertEqual(rows[1].count, 13, "\(layout) top row")
      XCTAssertEqual(rows[1].last?.label, "\\", "\(layout) backslash key")
      XCTAssertEqual(rows[1].last?.legend(
        style: .dynamic, modifierFlags: .shift, capsLockEnabled: false), "|", "\(layout) Shift backslash")
      for (keyCode, base, shifted) in outerKeys {
        XCTAssertEqual(KeyboardLayoutEmulator.text(
          forKeyCode: keyCode, modifierFlags: [], mapping: .builtIn(layout)), base,
          "\(layout) key \(keyCode) base")
        XCTAssertEqual(KeyboardLayoutEmulator.text(
          forKeyCode: keyCode, modifierFlags: .shift, mapping: .builtIn(layout)), shifted,
          "\(layout) key \(keyCode) Shift")
      }
    }
  }

  func testANSIDvorakRetainsItsOwnNumberRowAndBackslash() {
    let rows = KeyboardGuideModel.rows(for: .ansiDvorak)
    XCTAssertEqual(rows[0].count, 13)
    XCTAssertEqual(rows[0].first?.label, "`")
    XCTAssertEqual(rows[0].suffix(2).map(\.label), ["[", "]"])
    XCTAssertEqual(rows[1].count, 13)
    XCTAssertEqual(rows[1].last?.label, "\\")
    let outerKeys: [(UInt16, String, String)] = [
      (50, "`", "~"), (18, "1", "!"), (19, "2", "@"), (20, "3", "#"),
      (21, "4", "$"), (23, "5", "%"), (22, "6", "^"), (26, "7", "&"),
      (28, "8", "*"), (25, "9", "("), (29, "0", ")"), (27, "[", "{"),
      (24, "]", "}"), (42, "\\", "|"),
    ]
    for (keyCode, base, shifted) in outerKeys {
      XCTAssertEqual(KeyboardLayoutEmulator.text(
        forKeyCode: keyCode, modifierFlags: [], mapping: .builtIn(.ansiDvorak)), base)
      XCTAssertEqual(KeyboardLayoutEmulator.text(
        forKeyCode: keyCode, modifierFlags: .shift, mapping: .builtIn(.ansiDvorak)), shifted)
    }
  }

  func testPinnedBaseAndShiftLegendsAgreeWithNativeEmulation() throws {
    guard let root = ProcessInfo.processInfo.environment["TYPEBAR_LAYOUT_AUDIT_REFERENCE"] else {
      throw XCTSkip("Set TYPEBAR_LAYOUT_AUDIT_REFERENCE to a pinned read-only checkout")
    }
    let reference = URL(fileURLWithPath: root, isDirectory: true)
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let mapping = try JSONDecoder().decode(Mapping.self, from: Data(contentsOf:
      repository.appendingPathComponent("Compatibility/official-layouts.json")))

    let git = Process(), output = Pipe()
    git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    git.arguments = ["-C", reference.path, "rev-parse", "HEAD"]
    git.standardOutput = output
    git.standardError = Pipe()
    try git.run()
    git.waitUntilExit()
    let actualCommit = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    XCTAssertEqual(git.terminationStatus, 0)
    XCTAssertEqual(actualCommit, mapping.referenceCommit, "Do not compare against a moving reference")
    guard git.terminationStatus == 0, actualCommit == mapping.referenceCommit else { return }

    var mismatches: [String] = []
    var mismatchCount = 0
    var mismatchesByLayout: [String: Int] = [:]
    var firstMismatchByLayout: [String: String] = [:]
    var deferredCount = 0
    var explicitDifferentCount = 0
    var deferredByLayout: [String: Int] = [:]
    var explicitByLayout: [String: Int] = [:]
    var checkedLayers = 0
    for officialID in mapping.nativeExact.keys.sorted() {
      let rawValue = try XCTUnwrap(mapping.nativeExact[officialID])
      let native = try XCTUnwrap(KeyboardLayout(rawValue: rawValue))
      let sourceURL = reference.appendingPathComponent("frontend/static/layouts/\(officialID).json")
      let source = try JSONDecoder().decode(ReferenceLayout.self, from: Data(contentsOf: sourceURL))
      let codes: [[UInt16]]
      switch source.type {
      case "ansi":
        codes = ansiCodes
      case "iso":
        codes = [ansiCodes[0], Array(ansiCodes[1].dropLast()),
          ansiCodes[2] + [42], [10] + ansiCodes[3]]
      default:
        XCTFail("Unknown layout type for \(officialID): \(source.type)")
        continue
      }
      let rows = [source.keys.row1, source.keys.row2, source.keys.row3, source.keys.row4]
      for row in rows.indices {
        XCTAssertEqual(rows[row].count, codes[row].count, "\(officialID) row \(row + 1)")
        guard rows[row].count == codes[row].count else { continue }
        for column in rows[row].indices {
          let legends = rows[row][column]
          guard let base = legends.first else { continue }
          let keyCode = codes[row][column]
          let expected = [(base, NSEvent.ModifierFlags())]
            + (legends.count > 1 ? [(legends[1], NSEvent.ModifierFlags.shift)] : [])
          for (text, modifiers) in expected {
            checkedLayers += 1
            let actual = KeyboardLayoutEmulator.text(
              forKeyCode: keyCode, modifierFlags: modifiers, mapping: .builtIn(native))
            if actual != text {
              mismatchCount += 1
              mismatchesByLayout[officialID, default: 0] += 1
              if actual == nil {
                deferredCount += 1
                deferredByLayout[officialID, default: 0] += 1
              } else {
                explicitDifferentCount += 1
                explicitByLayout[officialID, default: 0] += 1
              }
              if firstMismatchByLayout[officialID] == nil {
                firstMismatchByLayout[officialID] = "\(officialID) row \(row + 1) key \(column + 1) "
                  + "\(modifiers.contains(.shift) ? "Shift" : "base"): "
                  + "expected \(text.debugDescription), got \(actual.debugDescription)"
              }
              if mismatches.count < 12 {
                mismatches.append("\(officialID) row \(row + 1) key \(column + 1) "
                  + "\(modifiers.contains(.shift) ? "Shift" : "base"): "
                  + "expected \(text.debugDescription), got \(actual.debugDescription)")
              }
            }
          }
        }
      }
    }
    XCTAssertGreaterThan(checkedLayers, 20_000)
    let byLayout = mismatchesByLayout.sorted {
      $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
    }.map { "\($0.key):\($0.value)" }
    XCTAssertEqual(mismatchCount, 0, "\(mismatchCount) of \(checkedLayers) base/Shift outputs differ "
      + "(\(explicitDifferentCount) explicit, \(deferredCount) deferred to macOS) "
      + "across \(mismatchesByLayout.count) layouts. By layout: \(byLayout.joined(separator: ", ")). "
      + "Explicit by layout: \(explicitByLayout.sorted { $0.key < $1.key }). "
      + "Deferred by layout: \(deferredByLayout.sorted { $0.key < $1.key }). "
      + "First per layout:\n\(firstMismatchByLayout.keys.sorted().compactMap { firstMismatchByLayout[$0] }.joined(separator: "\n"))\n"
      + "First mismatches:\n\(mismatches.joined(separator: "\n"))")
  }
}
