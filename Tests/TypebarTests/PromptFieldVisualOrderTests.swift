import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class PromptFieldVisualOrderTests: XCTestCase {
  private let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)

  private func cells(_ text: String) -> [PromptFieldTextRun.Cell] {
    text.enumerated().map { index, character in
      .init(id: index, glyph: .init(character: character, state: .pending),
        text: AttributedString(String(character)), isGap: false)
    }
  }

  func testHebrewOrderIsIndependentOfOuterParagraphDirection() {
    for rtl in [false, true] {
      XCTAssertEqual(PromptFieldVisualOrder.cellIDs(cells("אב"), font: font, rightToLeft: rtl), [1, 0])
    }
  }

  func testLatinAndNumbersKeepTheirInternalOrderInsideRTLField() {
    XCTAssertEqual(PromptFieldVisualOrder.cellIDs(cells("אב12גד"), font: font, rightToLeft: false),
      [5, 4, 2, 3, 1, 0])
    XCTAssertEqual(PromptFieldVisualOrder.cellIDs(cells("abאב"), font: font, rightToLeft: false),
      [0, 1, 3, 2])
    XCTAssertEqual(PromptFieldVisualOrder.cellIDs(cells("abאב"), font: font, rightToLeft: true),
      [3, 2, 0, 1])
  }

  func testEmptyAndLatinFieldsPreserveIdentitiesAndDoNotMutateCells() {
    XCTAssertEqual(PromptFieldVisualOrder.cellIDs([], font: font, rightToLeft: false), [])
    let value = cells("abc"), saved = value
    XCTAssertEqual(PromptFieldVisualOrder.cellIDs(value, font: font, rightToLeft: false), [0, 1, 2])
    XCTAssertEqual(value, saved)
  }

  func testEmptyDisplaySlotStaysStableBetweenReversedCells() {
    var value = cells("אXב")
    value[1] = .init(id: 1, glyph: value[1].glyph, text: AttributedString(), isGap: false)
    XCTAssertEqual(PromptFieldVisualOrder.cellIDs(value, font: font, rightToLeft: false), [2, 1, 0])
  }

  func testArabicLigatureAnalysisStillOrdersIndependentCellIdentities() {
    XCTAssertEqual(PromptFieldVisualOrder.cellIDs(cells("سلام"), font: font, rightToLeft: false),
      [3, 2, 1, 0])
  }
}
