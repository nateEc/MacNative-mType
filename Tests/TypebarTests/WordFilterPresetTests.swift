import XCTest

@testable import Typebar

final class WordFilterPresetTests: XCTestCase {
  func testQwertyHandPresetsSelectOnlyTheirPhysicalSide() throws {
    let left = try XCTUnwrap(LocalWordFilterPreset.leftHand.criteria(layout: .ansiQwerty))
    let right = try XCTUnwrap(LocalWordFilterPreset.rightHand.criteria(layout: .ansiQwerty))
    let words = ["red", "Sad", "SAD", "cab", "milk", "pony", "type", "jam"]
    XCTAssertEqual(try LocalWordFilter.words(in: words, matching: left).get(),
      ["red", "Sad", "SAD", "cab"])
    XCTAssertEqual(try LocalWordFilter.words(in: words, matching: right).get(),
      ["milk", "pony"])
    XCTAssertTrue(left.exactCharactersOnly)
    XCTAssertTrue(right.exactCharactersOnly)
  }

  func testRowPresetsFollowTheSelectedLayoutWithoutNumberKeys() throws {
    let home = try XCTUnwrap(LocalWordFilterPreset.homeRow.criteria(layout: .ansiQwerty))
    let homeKeys = try XCTUnwrap(LocalWordFilterPreset.homeKeys.criteria(layout: .ansiQwerty))
    let top = try XCTUnwrap(LocalWordFilterPreset.topRow.criteria(layout: .ansiQwerty))
    let bottom = try XCTUnwrap(LocalWordFilterPreset.bottomRow.criteria(layout: .ansiQwerty))
    XCTAssertEqual(try LocalWordFilter.words(
      in: ["ask", "gash", "tree", "mvm", "a1"], matching: homeKeys).get(), ["ask"])
    XCTAssertEqual(try LocalWordFilter.words(
      in: ["ask", "gash", "tree", "mvm", "a1"], matching: home).get(),
      ["ask", "gash"])
    XCTAssertEqual(try LocalWordFilter.words(
      in: ["ask", "gash", "tree", "mvm", "a1"], matching: top).get(), ["tree"])
    XCTAssertEqual(try LocalWordFilter.words(
      in: ["ask", "gash", "tree", "mvm", "a1"], matching: bottom).get(), ["mvm"])

    let dvorakLeft = try XCTUnwrap(LocalWordFilterPreset.leftHand.criteria(layout: .ansiDvorak))
    XCTAssertEqual(try LocalWordFilter.words(in: ["you", "red"], matching: dvorakLeft).get(),
      ["you"])
    let qwertyLeft = try XCTUnwrap(
      LocalWordFilterPreset.leftHand.criteria(layout: .ansiQwerty))
    XCTAssertEqual(try LocalWordFilter.words(in: ["you", "red"], matching:
      qwertyLeft).get(), ["red"])
  }

  func testAllBuiltInLayoutsProvidePresetCharactersWithoutCrashing() {
    for layout in KeyboardLayout.allCases {
      for preset in LocalWordFilterPreset.allCases {
        let criteria = preset.criteria(layout: layout)
        XCTAssertNotNil(criteria, "\(layout.rawValue): \(preset.rawValue)")
        XCTAssertFalse(criteria?.includeCharacters.isEmpty ?? true)
      }
    }
  }

  func testManualIncludeExcludeAreCaseInsensitiveLikeLayoutPresets() throws {
    let criteria = LocalWordFilter.Criteria(
      includeCharacters: "A", excludeCharacters: "R")
    XCTAssertEqual(try LocalWordFilter.words(
      in: ["Atlas", "BAR", "saga"], matching: criteria).get(), ["Atlas", "saga"])
  }
}
