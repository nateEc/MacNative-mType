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
      let row5: [[String]]
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

  func testOfficialOptionFallbackDoesNotChangeSystemCustomLegacyOrGlyphKeys() {
    let qwerty = KeyboardInputMapping.builtIn(.ansiQwerty)
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 12, modifierFlags: .option, mapping: qwerty), "q")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 12, modifierFlags: [.option, .shift], mapping: qwerty), "Q")
    for flags: NSEvent.ModifierFlags in [[], .shift, .option, [.option, .shift]] {
      XCTAssertEqual(KeyboardLayoutEmulator.text(
        forKeyCode: 49, modifierFlags: flags, mapping: qwerty), " ")
    }

    let optimot = KeyboardInputMapping.builtIn(.optimot)
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 22, modifierFlags: .option, mapping: optimot), "×")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 22, modifierFlags: [.option, .shift], mapping: optimot), "6")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 11, modifierFlags: .option, mapping: optimot), "⌫")

    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 29, modifierFlags: .option, mapping: .builtIn(.whix2)), " ")
    XCTAssertNil(KeyboardLayoutEmulator.text(
      forKeyCode: 42, modifierFlags: .option, mapping: .builtIn(.urduPhonetic)))
    XCTAssertNil(KeyboardLayoutEmulator.text(
      forKeyCode: 12, modifierFlags: .option, mapping: .system))
    let custom = CustomKeyboardGuideLayout(
      name: "Custom", numberRow: "1", topRow: "q", homeRow: "a", bottomRow: "z")
    XCTAssertNil(KeyboardLayoutEmulator.text(
      forKeyCode: 12, modifierFlags: .option, mapping: .custom(custom)))
  }

  func testOfficialTwoLayerLayoutsIgnoreNativeMacOnlyOptionSymbols() {
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 12, modifierFlags: .option, mapping: .builtIn(.brazilianABNT2)), "q")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 12, modifierFlags: [.option, .shift], mapping: .builtIn(.brazilianABNT2)), "Q")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 18, modifierFlags: .option, mapping: .builtIn(.dvorakLeft)), "[")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 18, modifierFlags: [.option, .shift], mapping: .builtIn(.dvorakLeft)), "{")
  }

  func testOfficialPashtoUsesPinnedPhysicalKeysAndSingleLayerFallback() {
    let mapping = KeyboardInputMapping.builtIn(.pashto)
    let rows = KeyboardGuideModel.rows(for: .pashto)
    XCTAssertEqual(rows[0][0].label, "`")
    XCTAssertEqual(rows[0][2].label, "2")
    XCTAssertEqual(rows[3][0].label, "ظ")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 50, modifierFlags: [], mapping: mapping), "`")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 18, modifierFlags: .shift, mapping: mapping), "!")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 12, modifierFlags: .shift, mapping: mapping), "ض")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 42, modifierFlags: .option, mapping: mapping), "\"")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 6, modifierFlags: [.option, .shift], mapping: mapping), "ئ")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 11, modifierFlags: .shift, mapping: mapping), "ذ")
    XCTAssertNil(KeyboardLayoutEmulator.keyCode(for: "ؤ", layout: .pashto))
  }

  func testOfficialHindiInscriptUsesPinnedNumberAndBottomRows() {
    let mapping = KeyboardInputMapping.builtIn(.hindiInscript)
    let rows = KeyboardGuideModel.rows(for: .hindiInscript)
    XCTAssertEqual(rows[0][0].label, "ॊ")
    XCTAssertEqual(rows[0][1].label, "1")
    XCTAssertEqual(rows[3][0].label, "ॆ")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 50, modifierFlags: [], mapping: mapping), "ॊ")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 23, modifierFlags: .shift, mapping: mapping), "5")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 24, modifierFlags: [], mapping: mapping), "ऋ")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 6, modifierFlags: [.option, .shift], mapping: mapping), "ऎ")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 45, modifierFlags: .shift, mapping: mapping), "ळ")
    XCTAssertNil(KeyboardLayoutEmulator.keyCode(forOutput: "क्ष", layout: .hindiInscript))
  }

  func testOfficialThaiPattachoteUsesPinnedNumberAndBottomRows() {
    let mapping = KeyboardInputMapping.builtIn(.thaiPattachote)
    let rows = KeyboardGuideModel.rows(for: .thaiPattachote)
    XCTAssertEqual(rows[0][0].label, "฿")
    XCTAssertEqual(rows[0][1].label, "ๅ")
    XCTAssertEqual(rows[3][0].label, "ฃ")
    XCTAssertEqual(rows[3][9].label, "จ")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 50, modifierFlags: [], mapping: mapping), "฿")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 50, modifierFlags: .shift, mapping: mapping), "~")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 18, modifierFlags: .option, mapping: mapping), "ๅ")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 6, modifierFlags: [.option, .shift], mapping: mapping), "ฅ")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 44, modifierFlags: .shift, mapping: mapping), "ฉ")
    XCTAssertNil(KeyboardLayoutEmulator.keyCode(for: "ฬ", layout: .thaiPattachote))
  }

  func testOfficialArabicMacUsesPinnedNumberAndHomeRows() {
    let mapping = KeyboardInputMapping.builtIn(.arabicMac)
    let rows = KeyboardGuideModel.rows(for: .arabicMac)
    XCTAssertEqual(rows[0][0].label, "§")
    XCTAssertEqual(rows[0][1].label, "1")
    XCTAssertEqual(rows[2][0].shiftedLabel, "«")
    XCTAssertEqual(rows[2][1].shiftedLabel, "»")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 50, modifierFlags: [], mapping: mapping), "§")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 50, modifierFlags: [.option, .shift], mapping: mapping), "±")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 18, modifierFlags: .option, mapping: mapping), "1")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 0, modifierFlags: .shift, mapping: mapping), "«")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 1, modifierFlags: [.option, .shift], mapping: mapping), "»")
    XCTAssertNil(KeyboardLayoutEmulator.keyCode(for: "∞", layout: .arabicMac))
  }

  func testOfficialWhix2BlankLegendsEmitRealSpacesOnEveryLayer() {
    let mapping = KeyboardInputMapping.builtIn(.whix2)
    let rows = KeyboardGuideModel.rows(for: .whix2)
    XCTAssertEqual(rows[0][10].label, "")
    XCTAssertEqual(rows[0][10].characters, Set(" "))
    XCTAssertEqual(rows[1][12].characters, Set(" "))
    XCTAssertEqual(rows[2][10].characters, Set(" "))
    for keyCode: UInt16 in [29, 27, 24, 33, 30, 42, 39] {
      for flags: NSEvent.ModifierFlags in [[], .shift, .option, [.option, .shift]] {
        XCTAssertEqual(KeyboardLayoutEmulator.text(
          forKeyCode: keyCode, modifierFlags: flags, mapping: mapping), " ")
      }
    }
  }

  func testOfficialPersianStandardUsesPinnedANSIRowsAndSingleLayerFallback() {
    let mapping = KeyboardInputMapping.builtIn(.persianStandard)
    let rows = KeyboardGuideModel.rows(for: .persianStandard)
    XCTAssertEqual(rows.map(\.count), [13, 13, 11, 10])
    XCTAssertEqual(rows[0][0].label, "\u{0060}")
    XCTAssertEqual(rows[0][4].shiftedLabel, "۴")
    XCTAssertEqual(rows[1][11].shiftedLabel, "}")
    XCTAssertEqual(rows[1][12].shiftedLabel, "{")
    XCTAssertEqual(rows[3][9].shiftedLabel, "?")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 50, modifierFlags: [], mapping: mapping), "\u{0060}")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 21, modifierFlags: [.option, .shift], mapping: mapping), "۴")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 30, modifierFlags: .shift, mapping: mapping), "}")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 42, modifierFlags: .shift, mapping: mapping), "{")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 11, modifierFlags: .shift, mapping: mapping), "ذ")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 44, modifierFlags: .shift, mapping: mapping), "?")
    XCTAssertNil(KeyboardLayoutEmulator.text(
      forKeyCode: 10, modifierFlags: [], mapping: mapping))
    XCTAssertNil(KeyboardLayoutEmulator.keyCode(for: "\u{200D}", layout: .persianStandard))
  }

  func testOfficialMongolianUsesPinnedBackslashKey() {
    let mapping = KeyboardInputMapping.builtIn(.mongolianCyrillic)
    let key = KeyboardGuideModel.rows(for: .mongolianCyrillic)[1][12]
    XCTAssertEqual(key.label, "\\")
    XCTAssertEqual(key.shiftedLabel, "|")
    for flags: NSEvent.ModifierFlags in [[], .option] {
      XCTAssertEqual(KeyboardLayoutEmulator.text(
        forKeyCode: 42, modifierFlags: flags, mapping: mapping), "\\")
    }
    for flags: NSEvent.ModifierFlags in [.shift, [.option, .shift]] {
      XCTAssertEqual(KeyboardLayoutEmulator.text(
        forKeyCode: 42, modifierFlags: flags, mapping: mapping), "|")
    }
  }

  func testOfficialPersianFarsiAndPolishProgrammersUsePinnedFallbacks() {
    let farsi = KeyboardInputMapping.builtIn(.persianFarsi)
    let farsiRows = KeyboardGuideModel.rows(for: .persianFarsi)
    XCTAssertEqual(farsiRows.map(\.count), [13, 13, 11, 10])
    XCTAssertEqual(farsiRows[1][3].shiftedLabel, "ق")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 15, modifierFlags: .shift, mapping: farsi), "ق")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 15, modifierFlags: [.option, .shift], mapping: farsi), "ق")
    XCTAssertNil(KeyboardLayoutEmulator.text(
      forKeyCode: 10, modifierFlags: [], mapping: farsi))

    let polish = KeyboardInputMapping.builtIn(.polishProgrammers)
    let polishRows = KeyboardGuideModel.rows(for: .polishProgrammers)
    XCTAssertEqual(polishRows.map(\.count), [13, 13, 11, 10])
    XCTAssertEqual(polishRows[1][6].characters, Set("u"))
    XCTAssertEqual(polishRows[1][12].label, "\\")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 32, modifierFlags: .option, mapping: polish), "u")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 32, modifierFlags: [.option, .shift], mapping: polish), "U")
  }

  @MainActor
  func testOfficialFrenchAzertyUsesPinnedISOAndAltGrKeys() throws {
    let mapping = KeyboardInputMapping.builtIn(.frenchAzerty)
    let rows = KeyboardGuideModel.rows(for: .frenchAzerty)
    XCTAssertEqual(rows.map(\.count), [13, 12, 12, 11])
    XCTAssertEqual(rows[0][0].label, "`")
    XCTAssertEqual(rows[0][0].shiftedLabel, "`")
    XCTAssertEqual(rows[0][2].optionLabel, "~")
    XCTAssertEqual(rows[0][2].legend(
      style: .dynamic, modifierFlags: [.option, .shift], capsLockEnabled: false), "2")
    XCTAssertEqual(rows[1][11].optionLabel, "¤")
    XCTAssertEqual(rows[2][11].label, "*")
    XCTAssertEqual(rows[2][11].shiftedLabel, "µ")
    XCTAssertEqual(rows[3][0].label, "<")
    XCTAssertEqual(rows[3][0].shiftedLabel, ">")
    for flags: NSEvent.ModifierFlags in [[], .shift, .option, [.shift, .option]] {
      XCTAssertEqual(KeyboardLayoutEmulator.text(
        forKeyCode: 50, modifierFlags: flags, mapping: mapping), "`")
    }
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 19, modifierFlags: .option, mapping: mapping), "~")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 19, modifierFlags: [.option, .shift], mapping: mapping), "2")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 30, modifierFlags: .option, mapping: mapping), "¤")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 42, modifierFlags: .shift, mapping: mapping), "µ")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 10, modifierFlags: [], mapping: mapping), "<")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 10, modifierFlags: .shift, mapping: mapping), ">")

    var inserted = [String]()
    let inputView = TypingInputView()
    inputView.keyboardInputMapping = mapping
    inputView.onInsert = { text, _ in inserted.append(text) }
    for (keyCode, flags, characters) in [
      (UInt16(50), NSEvent.ModifierFlags(), "`"),
      (UInt16(19), NSEvent.ModifierFlags.option, "2"),
      (UInt16(42), NSEvent.ModifierFlags.shift, "µ"),
      (UInt16(10), NSEvent.ModifierFlags(), "<"),
    ] {
      let event = try XCTUnwrap(NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
        context: nil, characters: characters, charactersIgnoringModifiers: characters,
        isARepeat: false, keyCode: keyCode))
      inputView.keyDown(with: event)
    }
    XCTAssertEqual(inserted, ["`", "~", "µ", "<"])

    let suiteName = "TypebarTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = AppSettings(defaults: defaults)
    settings.keyboardLayout = .frenchAzerty
    settings.keyboardInputLayout = .frenchAzerty
    settings.layoutFluidLayouts = [.frenchAzerty, .ansiQwerty]
    let restored = AppSettings(defaults: defaults)
    XCTAssertEqual(restored.keyboardLayout, .frenchAzerty)
    XCTAssertEqual(restored.keyboardInputLayout, .frenchAzerty)
    XCTAssertEqual(restored.layoutFluidLayouts, [.frenchAzerty, .ansiQwerty])
  }

  func testOfficialColemakDHWideKeepsPinnedFirstAndHashKeys() {
    for layout in [KeyboardLayout.colemakDHWideANSI, .colemakDHWideISO] {
      let mapping = KeyboardInputMapping.builtIn(layout)
      let rows = KeyboardGuideModel.rows(for: layout)
      XCTAssertEqual(rows[0].count, 13)
      XCTAssertEqual(rows[0][0].label, "`")
      for (flags, expected) in [
        (NSEvent.ModifierFlags(), "`"), (.shift, "~"), (.option, "`"),
        ([.option, .shift], "~"),
      ] {
        XCTAssertEqual(KeyboardLayoutEmulator.text(
          forKeyCode: 50, modifierFlags: flags, mapping: mapping), expected)
      }
    }
    let iso = KeyboardInputMapping.builtIn(.colemakDHWideISO)
    XCTAssertEqual(KeyboardGuideModel.rows(for: .colemakDHWideISO)[3][6].shiftedLabel, "#")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 45, modifierFlags: .shift, mapping: iso), "#")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 45, modifierFlags: [.option, .shift], mapping: iso), "#")
  }

  @MainActor
  func testOfficialLatinAmericanBlankHomeKeyTypesSpace() throws {
    let mapping = KeyboardInputMapping.builtIn(.latinAmericanQwerty)
    let rows = KeyboardGuideModel.rows(for: .latinAmericanQwerty)
    XCTAssertEqual(rows.map(\.count), [13, 12, 12, 11])
    XCTAssertEqual(rows[2].last?.label, "")
    XCTAssertEqual(rows[2].last?.characters, Set(" "))
    for flags: NSEvent.ModifierFlags in [[], .shift, .option, [.option, .shift]] {
      XCTAssertEqual(KeyboardLayoutEmulator.text(
        forKeyCode: 42, modifierFlags: flags, mapping: mapping), " ")
    }
    var inserted = [String]()
    let inputView = TypingInputView()
    inputView.keyboardInputMapping = mapping
    inputView.onInsert = { text, _ in inserted.append(text) }
    let event = try XCTUnwrap(NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
      context: nil, characters: "\\", charactersIgnoringModifiers: "\\",
      isARepeat: false, keyCode: 42))
    inputView.keyDown(with: event)
    XCTAssertEqual(inserted, [" "])

    let suiteName = "TypebarTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = AppSettings(defaults: defaults)
    settings.keyboardLayout = .latinAmericanQwerty
    settings.keyboardInputLayout = .latinAmericanQwerty
    settings.layoutFluidLayouts = [.latinAmericanQwerty, .ansiQwerty]
    let restored = AppSettings(defaults: defaults)
    XCTAssertEqual(restored.keyboardLayout, .latinAmericanQwerty)
    XCTAssertEqual(restored.keyboardInputLayout, .latinAmericanQwerty)
    XCTAssertEqual(restored.layoutFluidLayouts, [.latinAmericanQwerty, .ansiQwerty])
  }

  @MainActor
  func testOfficialOptimotGlyphFollowsPinnedInsertionPath() throws {
    let mapping = KeyboardInputMapping.builtIn(.optimot)
    let guide = KeyboardGuideModel.rows(for: .optimot)[3][5]
    XCTAssertEqual(guide.label, "⌫")
    XCTAssertTrue(guide.characters.contains("⌫"))
    var inserted = [String]()
    var deletions = 0
    let inputView = TypingInputView()
    inputView.keyboardInputMapping = mapping
    inputView.onInsert = { text, _ in inserted.append(text) }
    inputView.onDelete = { deletions += 1 }
    for flags: NSEvent.ModifierFlags in [[], .shift, .option, [.option, .shift]] {
      XCTAssertEqual(KeyboardLayoutEmulator.text(
        forKeyCode: 11, modifierFlags: flags, mapping: mapping), "⌫")
      let event = try XCTUnwrap(NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
        context: nil, characters: "b", charactersIgnoringModifiers: "b",
        isARepeat: false, keyCode: 11))
      inputView.keyDown(with: event)
    }
    XCTAssertEqual(inserted, ["⌫", "⌫", "⌫", "⌫"])
    XCTAssertEqual(deletions, 0)
  }

  func testOfficialTamil99UsesPinnedShiftOutputs() {
    let mapping = KeyboardInputMapping.builtIn(.tamil99)
    let rows = KeyboardGuideModel.rows(for: .tamil99)
    XCTAssertEqual(rows[0][0].label, "\u{0060}")
    XCTAssertEqual(rows[1][4].shiftedLabel, "ஏ")
    XCTAssertEqual(rows[1][5].shiftedLabel, "ள")
    XCTAssertEqual(rows[1][7].shiftedLabel, ":")
    XCTAssertEqual(rows[2][8].shiftedLabel, "௱")
    XCTAssertEqual(rows[3][5].shiftedLabel, "ௐ")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 50, modifierFlags: [], mapping: mapping), "\u{0060}")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 17, modifierFlags: .shift, mapping: mapping), "ஏ")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 16, modifierFlags: .shift, mapping: mapping), "ள")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 34, modifierFlags: .shift, mapping: mapping), ":")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 37, modifierFlags: .shift, mapping: mapping), "௱")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 45, modifierFlags: [.option, .shift], mapping: mapping), "ௐ")
    XCTAssertNil(KeyboardLayoutEmulator.keyCode(forOutput: "ஸ்ரீ", layout: .tamil99))
  }

  func testOfficialArabic102UsesPinnedPresentationFormsAndZeroWidthShift() {
    let mapping = KeyboardInputMapping.builtIn(.arabic102)
    let rows = KeyboardGuideModel.rows(for: .arabic102)
    XCTAssertEqual(rows[1][4].shiftedLabel, "ﻹ")
    XCTAssertEqual(rows[2][1].shiftedLabel, "\u{200B}")
    XCTAssertEqual(rows[2][4].shiftedLabel, "ﻷ")
    XCTAssertEqual(rows[3][5].label, "ﻻ")
    XCTAssertEqual(rows[3][5].shiftedLabel, "ﻵ")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "ﻻ", layout: .arabic102), "bottom-5")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 17, modifierFlags: .shift, mapping: mapping), "ﻹ")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 1, modifierFlags: [.option, .shift], mapping: mapping), "\u{200B}")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 5, modifierFlags: .shift, mapping: mapping), "ﻷ")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 11, modifierFlags: .option, mapping: mapping), "ﻻ")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 11, modifierFlags: [.option, .shift], mapping: mapping), "ﻵ")
  }

  func testOfficialArabic101UsesPinnedPresentationForms() {
    let mapping = KeyboardInputMapping.builtIn(.arabic101)
    let rows = KeyboardGuideModel.rows(for: .arabic101)
    XCTAssertEqual(rows[1][4].shiftedLabel, "ﻹ")
    XCTAssertEqual(rows[2][4].shiftedLabel, "ﻷ")
    XCTAssertEqual(rows[3][5].label, "ﻻ")
    XCTAssertEqual(rows[3][5].shiftedLabel, "ﻵ")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "ﻻ", layout: .arabic101), "bottom-5")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 17, modifierFlags: .shift, mapping: mapping), "ﻹ")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 5, modifierFlags: [.option, .shift], mapping: mapping), "ﻷ")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 11, modifierFlags: .option, mapping: mapping), "ﻻ")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 11, modifierFlags: [.option, .shift], mapping: mapping), "ﻵ")
  }

  func testOfficialUkrainianUsesPinnedAnsiAndAltGrKeys() {
    let mapping = KeyboardInputMapping.builtIn(.ukrainianJcuken)
    let rows = KeyboardGuideModel.rows(for: .ukrainianJcuken)
    XCTAssertEqual(rows.map(\.count), [13, 13, 11, 10])
    XCTAssertEqual(rows[0][0].label, "'")
    XCTAssertEqual(rows[0][0].shiftedLabel, "₴")
    XCTAssertEqual(rows[1][6].optionLabel, "ґ")
    XCTAssertEqual(rows[1][6].shiftedOptionLabel, "Ґ")
    XCTAssertEqual(rows[1][12].label, "ґ")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 50, modifierFlags: [], mapping: mapping), "'")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 50, modifierFlags: .shift, mapping: mapping), "₴")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 32, modifierFlags: .option, mapping: mapping), "ґ")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 32, modifierFlags: [.option, .shift], mapping: mapping), "Ґ")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 42, modifierFlags: [], mapping: mapping), "ґ")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 42, modifierFlags: .shift, mapping: mapping), "Ґ")
    XCTAssertNil(KeyboardLayoutEmulator.text(
      forKeyCode: 10, modifierFlags: [], mapping: mapping))
  }

  func testOfficialEstonianUsesPinnedFirstNumberKey() {
    let mapping = KeyboardInputMapping.builtIn(.estonian)
    let first = KeyboardGuideModel.rows(for: .estonian)[0][0]
    XCTAssertEqual(first.label, "~")
    XCTAssertEqual(first.shiftedLabel, "^")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 50, modifierFlags: [], mapping: mapping), "~")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 50, modifierFlags: .shift, mapping: mapping), "^")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 50, modifierFlags: .option, mapping: mapping), "~")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 50, modifierFlags: [.option, .shift], mapping: mapping), "^")
    XCTAssertNil(KeyboardLayoutEmulator.keyCode(for: "ˇ", layout: .estonian))
  }

  func testOfficialHebrewUsesPinnedFirstNumberKey() {
    let mapping = KeyboardInputMapping.builtIn(.hebrew)
    let first = KeyboardGuideModel.rows(for: .hebrew)[0][0]
    XCTAssertEqual(first.label, "~")
    XCTAssertEqual(first.shiftedLabel, ";")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 50, modifierFlags: [], mapping: mapping), "~")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 50, modifierFlags: .shift, mapping: mapping), ";")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 50, modifierFlags: .option, mapping: mapping), "~")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 50, modifierFlags: [.option, .shift], mapping: mapping), ";")
  }

  func testOfficialTurkishFUsesPinnedAnsiRows() {
    let mapping = KeyboardInputMapping.builtIn(.turkishF)
    let rows = KeyboardGuideModel.rows(for: .turkishF)
    XCTAssertEqual(rows.map(\.count), [13, 13, 11, 10])
    XCTAssertEqual(rows[0][0].label, "*")
    XCTAssertEqual(rows[0][0].shiftedLabel, "+")
    XCTAssertEqual(rows[1].last?.label, "X")
    XCTAssertEqual(rows[2].last?.label, "Ş")
    XCTAssertEqual(rows[3][0].label, "J")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 50, modifierFlags: [], mapping: mapping), "*")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 50, modifierFlags: .shift, mapping: mapping), "+")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 50, modifierFlags: .option, mapping: mapping), "*")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 50, modifierFlags: [.option, .shift], mapping: mapping), "+")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 42, modifierFlags: [], mapping: mapping), "x")
    XCTAssertNil(KeyboardLayoutEmulator.text(
      forKeyCode: 10, modifierFlags: [], mapping: mapping))
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

  func testColemakISOLayoutsKeepTheirDistinctExtraKeys() {
    let variants: [(KeyboardLayout, String, String)] = [
      (.colemakDHISO, "\\", "|"), (.colemakDHKISO, "#", "'"),
    ]
    let numberKeys: [(UInt16, String, String)] = [
      (50, "`", "~"), (18, "1", "!"), (19, "2", "@"), (20, "3", "#"),
      (21, "4", "$"), (23, "5", "%"), (22, "6", "^"), (26, "7", "&"),
      (28, "8", "*"), (25, "9", "("), (29, "0", ")"), (27, "-", "_"),
      (24, "=", "+"),
    ]
    for (layout, isoHomeBase, isoHomeShift) in variants {
      let rows = KeyboardGuideModel.rows(for: layout)
      XCTAssertEqual(rows[0].count, 13, "\(layout) number row")
      XCTAssertEqual(rows[0].first?.label, "`", "\(layout) grave key")
      XCTAssertEqual(rows[2].count, 12, "\(layout) ISO home row")
      XCTAssertEqual(rows[2].last?.label, isoHomeBase, "\(layout) extra home key")
      XCTAssertEqual(rows[2].last?.shiftedLabel, isoHomeShift, "\(layout) extra home Shift")
      XCTAssertEqual(rows[3].count, 11, "\(layout) ISO bottom row")
      XCTAssertEqual(rows[3][5].label, "\\", "\(layout) bottom backslash")
      XCTAssertEqual(rows[3][5].legend(
        style: .dynamic, modifierFlags: .shift, capsLockEnabled: false), "|", "\(layout) bottom Shift")
      for (keyCode, base, shifted) in numberKeys {
        XCTAssertEqual(KeyboardLayoutEmulator.text(
          forKeyCode: keyCode, modifierFlags: [], mapping: .builtIn(layout)), base)
        XCTAssertEqual(KeyboardLayoutEmulator.text(
          forKeyCode: keyCode, modifierFlags: .shift, mapping: .builtIn(layout)), shifted)
      }
      XCTAssertEqual(KeyboardLayoutEmulator.text(
        forKeyCode: 42, modifierFlags: [], mapping: .builtIn(layout)), isoHomeBase)
      XCTAssertEqual(KeyboardLayoutEmulator.text(
        forKeyCode: 42, modifierFlags: .shift, mapping: .builtIn(layout)), isoHomeShift)
      XCTAssertEqual(KeyboardLayoutEmulator.text(
        forKeyCode: 11, modifierFlags: [], mapping: .builtIn(layout)), "\\")
      XCTAssertEqual(KeyboardLayoutEmulator.text(
        forKeyCode: 11, modifierFlags: .shift, mapping: .builtIn(layout)), "|")
    }
  }

  func testNorwegianAndNordicKeepDistinctFirstNumberKeys() {
    let norwegian = KeyboardGuideModel.rows(for: .norwegianQwerty)[0][0]
    XCTAssertEqual(norwegian.label, "|")
    XCTAssertEqual(norwegian.shiftedLabel, "§")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 50, modifierFlags: [], mapping: .builtIn(.norwegianQwerty)), "|")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 50, modifierFlags: .shift, mapping: .builtIn(.norwegianQwerty)), "§")

    let nordic = KeyboardGuideModel.rows(for: .nordicQwerty)[0][0]
    XCTAssertEqual(nordic.label, "§")
    XCTAssertEqual(nordic.shiftedLabel, "°")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 50, modifierFlags: [], mapping: .builtIn(.nordicQwerty)), "§")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 50, modifierFlags: .shift, mapping: .builtIn(.nordicQwerty)), "°")
  }

  func testOfficialUrduPhoneticKeepsSingleLayerTextWithoutChangingLegacyLayout() {
    guard let official = KeyboardLayout(rawValue: "urduPhoneticOfficial") else {
      XCTFail("Official Urdu Phonetic must have a distinct persisted layout identity")
      return
    }
    let mapping = KeyboardInputMapping.builtIn(official)
    for (keyCode, expected) in [(UInt16(12), "ق"), (0, "ا"), (9, "ڈ")] {
      XCTAssertEqual(KeyboardLayoutEmulator.text(
        forKeyCode: keyCode, modifierFlags: [], mapping: mapping), expected)
      XCTAssertEqual(KeyboardLayoutEmulator.text(
        forKeyCode: keyCode, modifierFlags: .shift, mapping: mapping), expected)
      XCTAssertEqual(KeyboardLayoutEmulator.text(
        forKeyCode: keyCode, modifierFlags: .option, mapping: mapping), expected)
      XCTAssertEqual(KeyboardLayoutEmulator.text(
        forKeyCode: keyCode, modifierFlags: [.shift, .option], mapping: mapping), expected)
    }
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 18, modifierFlags: [], mapping: mapping), "1")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 18, modifierFlags: .shift, mapping: mapping), "!")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 18, modifierFlags: .option, mapping: mapping), "1")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 18, modifierFlags: [.shift, .option], mapping: mapping), "!")

    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 18, modifierFlags: [], mapping: .builtIn(.urduPhonetic)), "۱")
    XCTAssertEqual(KeyboardLayoutEmulator.text(
      forKeyCode: 18, modifierFlags: .shift, mapping: .builtIn(.urduPhonetic)), "1")
  }

  func testPinnedGuideLegendsMatchReferenceLayers() throws {
    guard let root = ProcessInfo.processInfo.environment["TYPEBAR_LAYOUT_GUIDE_AUDIT_REFERENCE"] else {
      throw XCTSkip("Set TYPEBAR_LAYOUT_GUIDE_AUDIT_REFERENCE to a pinned read-only checkout")
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

    let onlyOfficialID = ProcessInfo.processInfo.environment["TYPEBAR_LAYOUT_GUIDE_AUDIT_ONLY"]
    let auditedIDs: [String]
    if let onlyOfficialID {
      _ = try XCTUnwrap(mapping.nativeExact[onlyOfficialID], "Unknown official layout: \(onlyOfficialID)")
      auditedIDs = [onlyOfficialID]
    } else {
      auditedIDs = mapping.nativeExact.keys.sorted()
    }

    let modifiers: [NSEvent.ModifierFlags] = [[], .shift, .option, [.shift, .option]]
    var mismatchCount = 0
    var checkedLegends = 0
    var mismatchesByLayout: [String: Int] = [:]
    var firstMismatchByLayout: [String: String] = [:]
    var examples: [String] = []
    var visuallyBlankSpaces = 0
    for officialID in auditedIDs {
      let native = try XCTUnwrap(KeyboardLayout(rawValue: try XCTUnwrap(mapping.nativeExact[officialID])))
      let sourceURL = reference.appendingPathComponent("frontend/static/layouts/\(officialID).json")
      let source = try JSONDecoder().decode(ReferenceLayout.self, from: Data(contentsOf: sourceURL))
      let sourceRows = [source.keys.row1, source.keys.row2, source.keys.row3, source.keys.row4]
      let guideRows = KeyboardGuideModel.rows(for: native)
      if guideRows.count != sourceRows.count {
        mismatchCount += 1
        mismatchesByLayout[officialID, default: 0] += 1
        let detail = "\(officialID): expected \(sourceRows.count) rows, got \(guideRows.count)"
        firstMismatchByLayout[officialID] = detail
        examples.append(detail)
        continue
      }
      for row in sourceRows.indices {
        if guideRows[row].count != sourceRows[row].count {
          mismatchCount += 1
          mismatchesByLayout[officialID, default: 0] += 1
          let detail = "\(officialID) row \(row + 1): expected \(sourceRows[row].count) keys, got \(guideRows[row].count)"
          if firstMismatchByLayout[officialID] == nil { firstMismatchByLayout[officialID] = detail }
          if examples.count < 20 {
            examples.append(detail)
          }
          continue
        }
        for column in sourceRows[row].indices {
          let layers = sourceRows[row][column]
          guard let base = layers.first else { continue }
          for flags in modifiers {
            let shifted = flags.contains(.shift)
            let alternateIndex = flags.contains(.option) && layers.count > 2 ? 2 : 0
            let preferredIndex = alternateIndex + (shifted ? 1 : 0)
            let preferred = layers.indices.contains(preferredIndex) ? layers[preferredIndex] : ""
            let plainIndex = shifted ? 1 : 0
            let plain = layers.indices.contains(plainIndex) ? layers[plainIndex] : ""
            let expected = preferred.isEmpty ? (plain.isEmpty ? base : plain) : preferred
            let key = guideRows[row][column]
            let actual = key.legend(
              style: .dynamic, modifierFlags: flags, capsLockEnabled: false)
            checkedLegends += 1
            // A literal Space has no visible glyph. Keep it blank only when
            // the guide still advertises that the physical key can type it.
            if expected == " ", actual.isEmpty, key.characters.contains(" ") {
              visuallyBlankSpaces += 1
              continue
            }
            if actual != expected {
              mismatchCount += 1
              mismatchesByLayout[officialID, default: 0] += 1
              let detail = "\(officialID) row \(row + 1) key \(column + 1) "
                + "\(flags.contains(.option) ? "Option+" : "")\(shifted ? "Shift" : "base"): "
                + "expected \(expected.debugDescription), got \(actual.debugDescription)"
              if firstMismatchByLayout[officialID] == nil { firstMismatchByLayout[officialID] = detail }
              if examples.count < 20 {
                examples.append(detail)
              }
            }
          }
        }
      }
    }
    let byLayout = mismatchesByLayout.sorted {
      $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
    }.map { "\($0.key):\($0.value)" }
    XCTAssertEqual(mismatchCount, 0,
      "\(mismatchCount) of \(checkedLegends) visual legends or rows differ across "
        + "\(mismatchesByLayout.count) layouts (\(visuallyBlankSpaces) verified blank Space legends). "
        + "By layout: \(byLayout.joined(separator: ", ")). "
        + "First per layout:\n\(firstMismatchByLayout.keys.sorted().compactMap { firstMismatchByLayout[$0] }.joined(separator: "\n"))\n"
        + "First mismatches:\n\(examples.joined(separator: "\n"))")
  }

  func testArmenianThreeLayerGuideFallsBackToShiftOnOptionShift() {
    let key = KeyboardGuideModel.rows(for: .armenianHMQwerty)[0][4]
    XCTAssertEqual(key.shiftedLabel, "$")
    XCTAssertEqual(key.optionLabel, "¢")
    XCTAssertNil(key.shiftedOptionLabel)
    XCTAssertEqual(key.legend(
      style: .dynamic, modifierFlags: [.option, .shift], capsLockEnabled: false), "$")
    XCTAssertEqual(VirtualKeyboardOutputPolicy.output(
      for: key, shift: true, option: true), "$")
  }

  func testTurkishGuidesKeepDottedAndDotlessBaseLettersDistinct() {
    let cases: [(KeyboardLayout, Int, Int, String, String)] = [
      (.turkishF, 1, 3, "ı", "I"),
      (.turkishF, 2, 1, "i", "İ"),
      (.turkishE, 2, 2, "i", "İ"),
      (.turkishE, 2, 3, "ı", "I"),
    ]
    for (layout, row, column, base, shifted) in cases {
      let key = KeyboardGuideModel.rows(for: layout)[row][column]
      XCTAssertEqual(key.legend(style: .dynamic, modifierFlags: [], capsLockEnabled: false), base)
      XCTAssertEqual(key.legend(style: .dynamic, modifierFlags: .shift, capsLockEnabled: false), shifted)
      XCTAssertEqual(key.legend(style: .dynamic, modifierFlags: .option, capsLockEnabled: false), base)
      XCTAssertEqual(key.legend(style: .dynamic, modifierFlags: [.option, .shift], capsLockEnabled: false), shifted)
    }
  }

  func testRussianGuidePreservesOfficialUppercaseBaseKeys() {
    let cases: [(KeyboardLayout, Int, Int, String, String)] = [
      (.redaktor, 0, 11, "Ъ", "Ь"),
      (.juiyaf, 1, 11, "Ь", "Ъ"),
    ]
    for (layout, row, column, base, shifted) in cases {
      let key = KeyboardGuideModel.rows(for: layout)[row][column]
      XCTAssertEqual(key.legend(style: .dynamic, modifierFlags: [], capsLockEnabled: false), base)
      XCTAssertEqual(key.legend(style: .dynamic, modifierFlags: .option, capsLockEnabled: false), base)
      XCTAssertEqual(key.legend(style: .dynamic, modifierFlags: .shift, capsLockEnabled: false), shifted)
    }
  }

  func testDvorakAndSwedishColemakGuidesShowPinnedISOSymbols() {
    let cases: [(KeyboardLayout, Int, Int, String)] = [
      (.spanishDvorak, 3, 0, ">"),
      (.swedishDvorak, 3, 0, ">"),
      (.swedishDvorak, 3, 1, ":"),
      (.swedishColemak, 1, 11, "^"),
    ]
    for (layout, row, column, expected) in cases {
      let key = KeyboardGuideModel.rows(for: layout)[row][column]
      XCTAssertEqual(key.legend(
        style: .dynamic, modifierFlags: .shift, capsLockEnabled: false), expected)
      XCTAssertEqual(key.legend(
        style: .dynamic, modifierFlags: [.option, .shift], capsLockEnabled: false), expected)
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

    let onlyOfficialID = ProcessInfo.processInfo.environment["TYPEBAR_LAYOUT_AUDIT_ONLY"]
    let allLayers = ProcessInfo.processInfo.environment["TYPEBAR_LAYOUT_AUDIT_ALL_LAYERS"] == "1"
    let auditedIDs: [String]
    if let onlyOfficialID {
      _ = try XCTUnwrap(mapping.nativeExact[onlyOfficialID], "Unknown official layout: \(onlyOfficialID)")
      auditedIDs = [onlyOfficialID]
    } else {
      auditedIDs = mapping.nativeExact.keys.sorted()
    }

    var mismatches: [String] = []
    var mismatchCount = 0
    var mismatchesByLayout: [String: Int] = [:]
    var firstMismatchByLayout: [String: String] = [:]
    var deferredCount = 0
    var explicitDifferentCount = 0
    var deferredByLayout: [String: Int] = [:]
    var explicitByLayout: [String: Int] = [:]
    var checkedLayers = 0
    for officialID in auditedIDs {
      let rawValue = try XCTUnwrap(mapping.nativeExact[officialID])
      let native = try XCTUnwrap(KeyboardLayout(rawValue: rawValue))
      let sourceURL = reference.appendingPathComponent("frontend/static/layouts/\(officialID).json")
      let source = try JSONDecoder().decode(ReferenceLayout.self, from: Data(contentsOf: sourceURL))
      let sourceHasAltGr = [
        source.keys.row1, source.keys.row2, source.keys.row3, source.keys.row4, source.keys.row5,
      ].joined().contains { $0.count > 2 }
      XCTAssertEqual(native.hasPinnedAltGrLayer, sourceHasAltGr, "\(officialID) AltGr declaration")
      var codes: [[UInt16]]
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
      var rows = [source.keys.row1, source.keys.row2, source.keys.row3, source.keys.row4]
      if allLayers {
        let space = try XCTUnwrap(source.keys.row5.first, "\(officialID) needs a Space key")
        rows.append([space])
        codes.append([49])
      }
      for row in rows.indices {
        XCTAssertEqual(rows[row].count, codes[row].count, "\(officialID) row \(row + 1)")
        guard rows[row].count == codes[row].count else { continue }
        for column in rows[row].indices {
          let legends = rows[row][column]
          guard let base = legends.first else { continue }
          let keyCode = codes[row][column]
          let expected: [(String, NSEvent.ModifierFlags)]
          if allLayers {
            let modifiers: [NSEvent.ModifierFlags] = [[], .shift, .option, [.shift, .option]]
            expected = modifiers.map { flags in
              let shifted = flags.contains(.shift)
              let alternateIndex = flags.contains(.option) && legends.count > 2 ? 2 : 0
              let preferredIndex = alternateIndex + (shifted ? 1 : 0)
              let preferred = legends.indices.contains(preferredIndex) ? legends[preferredIndex] : ""
              let plainIndex = shifted ? 1 : 0
              let plain = legends.indices.contains(plainIndex) ? legends[plainIndex] : ""
              return (preferred.isEmpty ? (plain.isEmpty ? base : plain) : preferred, flags)
            }
          } else {
            expected = [(base, NSEvent.ModifierFlags())]
              + (legends.count > 1 ? [(legends[1], NSEvent.ModifierFlags.shift)] : [])
          }
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
                  + "\(modifiers.contains(.option) ? "Option+" : "")\(modifiers.contains(.shift) ? "Shift" : "base"): "
                  + "expected \(text.debugDescription), got \(actual.debugDescription)"
              }
              if mismatches.count < (onlyOfficialID == nil ? 12 : 100) {
                mismatches.append("\(officialID) row \(row + 1) key \(column + 1) "
                  + "\(modifiers.contains(.option) ? "Option+" : "")\(modifiers.contains(.shift) ? "Shift" : "base"): "
                  + "expected \(text.debugDescription), got \(actual.debugDescription)")
              }
            }
          }
        }
      }
    }
    XCTAssertGreaterThan(checkedLayers, onlyOfficialID == nil ? 20_000 : 0)
    if onlyOfficialID == "urdu_phonetic", allLayers {
      XCTAssertEqual(checkedLayers, 192, "The official Urdu check must include 48 keys and four layers")
    }
    let byLayout = mismatchesByLayout.sorted {
      $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
    }.map { "\($0.key):\($0.value)" }
    XCTAssertEqual(mismatchCount, 0, "\(mismatchCount) of \(checkedLayers) \(allLayers ? "all-layer" : "base/Shift") outputs differ "
      + "(\(explicitDifferentCount) explicit, \(deferredCount) deferred to macOS) "
      + "across \(mismatchesByLayout.count) layouts. By layout: \(byLayout.joined(separator: ", ")). "
      + "Explicit by layout: \(explicitByLayout.sorted { $0.key < $1.key }). "
      + "Deferred by layout: \(deferredByLayout.sorted { $0.key < $1.key }). "
      + "First per layout:\n\(firstMismatchByLayout.keys.sorted().compactMap { firstMismatchByLayout[$0] }.joined(separator: "\n"))\n"
      + "First mismatches:\n\(mismatches.joined(separator: "\n"))")
  }
}
