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
    XCTAssertNil(VirtualKeyboardOutputPolicy.output(for: letter, shift: false, option: true))
  }

  func testSpaceAndNonTypingKeysHaveExplicitOutcomes() {
    let space = KeyboardGuideKey("space", label: "空格", characters: " ")
    let control = KeyboardGuideKey("control", label: "⌃", characters: "")
    XCTAssertEqual(VirtualKeyboardOutputPolicy.output(for: space, shift: false, option: false), " ")
    XCTAssertNil(VirtualKeyboardOutputPolicy.output(for: control, shift: false, option: false))
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
}
