import AppKit
import XCTest

@testable import Typebar

final class VirtualKeyboardTests: XCTestCase {
  func testQwertyLettersAndSymbolsUseVisibleKeyLayers() throws {
    let keys = KeyboardGuideModel.rows(for: .ansiQwerty).flatMap { $0 }
    let letter = try XCTUnwrap(keys.first(where: { $0.label.lowercased() == "q" }))
    let digit = try XCTUnwrap(keys.first(where: { $0.label == "1" }))
    XCTAssertEqual(VirtualKeyboardOutputPolicy.output(for: letter, shift: false, option: false), "q")
    XCTAssertEqual(VirtualKeyboardOutputPolicy.output(for: letter, shift: true, option: false), "Q")
    XCTAssertEqual(VirtualKeyboardOutputPolicy.output(for: digit, shift: true, option: false), "!")
    XCTAssertEqual(VirtualKeyboardOutputPolicy.output(for: letter, shift: false, option: true), "q")
    XCTAssertEqual(VirtualKeyboardOutputPolicy.output(for: letter, shift: true, option: true), "Q")
  }

  func testSpaceAndNonTypingKeysHaveExplicitOutcomes() {
    let space = KeyboardGuideKey("space", label: "空格", characters: " ")
    let control = KeyboardGuideKey("control", label: "⌃", characters: "")
    let blankControl = KeyboardGuideKey("blank-control", label: "", characters: "")
    XCTAssertEqual(VirtualKeyboardOutputPolicy.output(for: space, shift: false, option: false), " ")
    XCTAssertNil(VirtualKeyboardOutputPolicy.output(for: control, shift: false, option: false))
    XCTAssertNil(VirtualKeyboardOutputPolicy.output(for: blankControl, shift: false, option: false))
  }

  func testOfficialVisuallyBlankSpaceKeysRemainClickableOnEveryLayer() {
    let keys = [
      KeyboardGuideModel.rows(for: .latinAmericanQwerty)[2][11],
      KeyboardGuideModel.rows(for: .whix2)[0][10],
    ]
    for key in keys {
      XCTAssertEqual(key.label, "")
      XCTAssertTrue(key.characters.contains(" "))
      for (shift, option) in [(false, false), (true, false), (false, true), (true, true)] {
        XCTAssertEqual(VirtualKeyboardOutputPolicy.output(
          for: key, shift: shift, option: option), " ")
      }
    }
  }

  func testSelectedNonLatinLayoutKeepsItsOwnVisibleCharacters() throws {
    let keys = KeyboardGuideModel.rows(for: .russianJcuken).flatMap { $0 }
    let letter = try XCTUnwrap(keys.first(where: { $0.label == "Й" }))
    XCTAssertEqual(VirtualKeyboardOutputPolicy.output(for: letter, shift: false, option: false), "й")
    XCTAssertEqual(VirtualKeyboardOutputPolicy.output(for: letter, shift: true, option: false), "Й")
  }

  func testOptionLayerAndNativeTypingSessionShareCharacterSemantics() throws {
    let key = KeyboardGuideKey(
      "accent", label: "a", characters: "aAäÄ",
      shiftedLabel: "A", optionLabel: "ä", shiftedOptionLabel: "Ä")
    XCTAssertEqual(VirtualKeyboardOutputPolicy.output(for: key, shift: false, option: true), "ä")
    let output = try XCTUnwrap(
      VirtualKeyboardOutputPolicy.output(for: key, shift: true, option: true))
    XCTAssertEqual(output, "Ä")

    var session = TypingSession(configuration: .words(2), prompt: "Ä bay")
    session.insertBatch(output, forceError: false)
    XCTAssertEqual(session.typed, "Ä")
    XCTAssertEqual(session.errors, 0)
    session.deleteBackward()
    XCTAssertEqual(session.typed, "")
  }

  func testPinnedHandedDvorakOptionFallsBackToTypedBaseAndShift() throws {
    for layout in [KeyboardLayout.dvorakLeft, .dvorakRight] {
      let rows = KeyboardGuideModel.rows(for: layout)
      let key = try XCTUnwrap(rows[0].first { $0.label == "f" })
      XCTAssertNil(key.optionLabel)
      XCTAssertNil(key.shiftedOptionLabel)
      XCTAssertNil(KeyboardGuideModel.highlightedKey(for: "ƒ", layout: layout))
      for (flags, shifted, expected) in [
        (NSEvent.ModifierFlags.option, false, key.label),
        (NSEvent.ModifierFlags([.option, .shift]), true, key.label.uppercased()),
      ] {
        XCTAssertEqual(key.legend(
          style: .dynamic, modifierFlags: flags, capsLockEnabled: false), expected)
        XCTAssertEqual(VirtualKeyboardOutputPolicy.output(
          for: key, shift: shifted, option: true), expected)
      }
    }
  }
}
