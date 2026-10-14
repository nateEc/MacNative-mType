import AppKit
import XCTest
@testable import Typebar

@MainActor final class OppositeShiftKeymapSourceTests: XCTestCase {
  private func forcedError(
    inputMapping: KeyboardInputMapping, oppositeShiftKeymap: KeyboardInputMapping,
    mode: OppositeShiftMode = .keymap, physicalKeyCode: UInt16 = 4,
    logicalCharacter: String = "p"
  ) throws -> Bool {
    let view = TypingInputView(frame: .zero)
    view.keyboardInputMapping = inputMapping
    view.oppositeShiftKeymap = oppositeShiftKeymap
    view.oppositeShiftMode = mode
    var insertions: [(String, Bool)] = []
    view.onInsert = { insertions.append(($0, $1)) }

    let leftShift = try XCTUnwrap(NSEvent.keyEvent(
      with: .flagsChanged, location: .zero, modifierFlags: [.shift], timestamp: 0,
      windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
      isARepeat: false, keyCode: 56))
    view.flagsChanged(with: leftShift)
    let rightPhysicalKey = try XCTUnwrap(NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: [.shift], timestamp: 0.1,
      windowNumber: 0, context: nil, characters: logicalCharacter,
      charactersIgnoringModifiers: logicalCharacter,
      isARepeat: false, keyCode: physicalKeyCode))
    view.keyDown(with: rightPhysicalKey)
    XCTAssertEqual(insertions.count, 1)
    return try XCTUnwrap(insertions.first).1
  }

  func testExplicitVisualKeymapOwnsOppositeShiftSideWhenInputEmulatorDiffers() throws {
    XCTAssertEqual(KeyboardLayoutEmulator.keyCode(for: "p", layout: .ansiQwerty), 35)
    XCTAssertEqual(KeyboardLayoutEmulator.keyCode(for: "p", layout: .ansiDvorak), 15)
    XCTAssertFalse(try forcedError(
      inputMapping: .builtIn(.ansiDvorak), oppositeShiftKeymap: .builtIn(.ansiQwerty)))
    XCTAssertTrue(try forcedError(
      inputMapping: .builtIn(.ansiQwerty), oppositeShiftKeymap: .builtIn(.ansiDvorak)))
    XCTAssertFalse(try forcedError(
      inputMapping: .builtIn(.ansiQwerty), oppositeShiftKeymap: .builtIn(.ansiDvorak), mode: .on))
    XCTAssertFalse(try forcedError(
      inputMapping: .builtIn(.ansiQwerty), oppositeShiftKeymap: .builtIn(.ansiDvorak),
      physicalKeyCode: 0, logicalCharacter: "🦄"),
      "An absent key in an explicit keymap is neutral, not classified by its physical side")
  }

  func testSynchronizedAndSystemKeymapsUseThePhysicalKeyEvenWhenLogicalTextMapsElsewhere() throws {
    for source in [KeyboardGuideLayoutSource.inputEmulation, .systemInput] {
      let keymap = source.oppositeShiftMapping(
        selectedLayout: .ansiDvorak, customLayout: nil, layoutFluid: false)
      XCTAssertEqual(keymap, .system)
      XCTAssertFalse(try forcedError(
        inputMapping: .builtIn(.ansiDvorak), oppositeShiftKeymap: keymap), source.rawValue)
      XCTAssertTrue(try forcedError(
        inputMapping: .builtIn(.ansiDvorak), oppositeShiftKeymap: keymap,
        physicalKeyCode: 0), source.rawValue)
    }
    XCTAssertEqual(KeyboardGuideLayoutSource.builtIn.oppositeShiftMapping(
      selectedLayout: .ansiDvorak, customLayout: nil, layoutFluid: true), .system)
  }

  func testCustomVisualKeymapIsIndependentOfInputEmulationAndMissingSelectionFallsBack() throws {
    let custom = CustomKeyboardGuideLayout(
      name: "Left P", numberRow: "123", topRow: "pabc", homeRow: "def", bottomRow: "ghi")
    let customKeymap = KeyboardGuideLayoutSource.custom.oppositeShiftMapping(
      selectedLayout: .ansiQwerty, customLayout: custom, layoutFluid: false)
    XCTAssertEqual(customKeymap, .custom(custom))
    XCTAssertTrue(try forcedError(
      inputMapping: .builtIn(.ansiQwerty), oppositeShiftKeymap: customKeymap))
    XCTAssertEqual(KeyboardGuideLayoutSource.custom.oppositeShiftMapping(
      selectedLayout: .ansiQwerty, customLayout: nil, layoutFluid: false),
      .builtIn(.ansiQwerty))
    XCTAssertEqual(KeyboardGuideLayoutSource.builtIn.oppositeShiftMapping(
      selectedLayout: .ansiQwerty, customLayout: custom, layoutFluid: false),
      .builtIn(.ansiQwerty))
  }

  func testRepeatedVisualLabelsUseTheFirstDisplayedKeyPosition() throws {
    let layout = try XCTUnwrap(CustomKeyboardGuideLayoutPolicy.make(
      name: "Repeated A", numberRow: "aaaaaaaaaaaaa", topRow: "aaaaaaaaaaaaa",
      homeRow: "aaaaaaaaaaa", bottomRow: "aaaaaaaaaa"))
    XCTAssertTrue(layout.supportsPhysicalInputMapping)
    for _ in 0..<8 {
      XCTAssertEqual(KeyboardLayoutEmulator.keyCode(for: "a", mapping: .custom(layout)), 50,
        "A visual lookup must use the first row and first key, as the displayed layout does")
    }
    XCTAssertTrue(try forcedError(
      inputMapping: .builtIn(.ansiQwerty), oppositeShiftKeymap: .custom(layout),
      logicalCharacter: "a"))
  }
}
