import AppKit
import XCTest
@testable import Typebar

@MainActor final class OppositeShiftKeymapSourceTests: XCTestCase {
  func testActualPinnedKeydownConverterAndShiftTrackerAcrossModesAndLayouts() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else { throw XCTSkip("Requires pinned reference") }
    struct Fixture: Decodable {
      let mode: String, guide: String, macCode: UInt16, key: String, left: Bool, right: Bool, correct: Bool
    }
    struct Output: Decodable { let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-opposite-shift.mjs").path, reference]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 3600)
    for f in fixtures {
      let view = TypingInputView(frame: .zero)
      view.keyboardInputMapping = .builtIn(.ansiQwerty)
      view.oppositeShiftMode = try XCTUnwrap(OppositeShiftMode(rawValue: f.mode))
      switch f.guide {
      case "overrideSync": view.oppositeShiftKeymap = .system
      case "qwerty": view.oppositeShiftKeymap = .builtIn(.ansiQwerty)
      case "dvorak": view.oppositeShiftKeymap = .builtIn(.ansiDvorak)
      case "colemak": view.oppositeShiftKeymap = .builtIn(.ansiColemak)
      case "azerty": view.oppositeShiftKeymap = .builtIn(.frenchAzerty)
      default: return XCTFail("Unexpected source guide")
      }
      for code: UInt16 in (f.left ? [56] : []) + (f.right ? [60] : []) {
        view.flagsChanged(with: try XCTUnwrap(NSEvent.keyEvent(with: .flagsChanged, location: .zero,
          modifierFlags: [.shift], timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)))
      }
      var forced: Bool?
      view.onInsert = { _, error in forced = error }
      view.keyDown(with: try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
        modifierFlags: f.left || f.right ? [.shift] : [], timestamp: 0, windowNumber: 0, context: nil,
        characters: f.key, charactersIgnoringModifiers: f.key, isARepeat: false, keyCode: f.macCode)))
      XCTAssertEqual(forced, !f.correct, "\(f)")
    }
  }

  func testCurrentShiftContextOverridesBothCachedFieldsAndRetiresWithTheControl() throws {
    let view = TypingInputView(frame: .zero)
    view.keyboardInputMapping = .builtIn(.ansiQwerty)
    view.oppositeShiftMode = .off; view.oppositeShiftKeymap = .system
    var current = OppositeShiftInputContext(mode: .keymap, keymap: .builtIn(.ansiDvorak)), calls = 0
    view.oppositeShiftContextProvider = { calls += 1; return current }
    view.flagsChanged(with: try XCTUnwrap(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: [.shift],
      timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 56)))
    let p = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.shift], timestamp: 0,
      windowNumber: 0, context: nil, characters: "P", charactersIgnoringModifiers: "p", isARepeat: false, keyCode: 35))
    var errors: [Bool] = []; view.onInsert = { _, error in errors.append(error) }
    view.keyDown(with: p)
    current = .init(mode: .on, keymap: .builtIn(.ansiDvorak)); view.keyDown(with: p)
    current = .init(mode: .off, keymap: .builtIn(.ansiDvorak)); view.keyDown(with: p)
    XCTAssertEqual(errors, [true, false, false]); XCTAssertEqual(calls, 3)
    view.retirePageCallbacks(); XCTAssertNil(view.oppositeShiftContextProvider)
    view.keyDown(with: p); XCTAssertEqual(calls, 3); XCTAssertEqual(errors.count, 3)
  }

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

  func testExactVisualCharacterDoesNotFoldTurkishOrCustomCaseAcrossHands() throws {
    XCTAssertEqual(KeyboardLayoutEmulator.keyCode(for: "i", layout: .turkishQ), 39,
      "Turkish dotted i is on the home row, not the earlier dotless-I key")
    XCTAssertEqual(KeyboardLayoutEmulator.keyCode(for: "I", layout: .turkishQ), 34)

    let custom = try XCTUnwrap(CustomKeyboardGuideLayoutPolicy.make(
      name: "Split I", numberRow: "I", topRow: "abcdefghji", homeRow: "k", bottomRow: "l",
      shiftedNumberRow: "I", shiftedTopRow: "ABCDEFGHJI"))
    XCTAssertEqual(KeyboardLayoutEmulator.keyCode(for: "i", mapping: .custom(custom)), 35)
    XCTAssertFalse(try forcedError(
      inputMapping: .builtIn(.ansiQwerty), oppositeShiftKeymap: .custom(custom),
      logicalCharacter: "i"), "The displayed right-hand i permits left Shift")
  }
}
