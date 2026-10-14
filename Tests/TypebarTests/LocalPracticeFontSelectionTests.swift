import Foundation
import XCTest
@testable import Typebar

final class LocalPracticeFontSelectionTests: XCTestCase {
  private let old = URL(fileURLWithPath: "/owned/local-practice-font-active-z.ttf")
  private let failedNew = URL(fileURLWithPath: "/owned/local-practice-font-active-a.ttf")

  func testLegacySelectionKeepsItsFirstFileUntilAChoiceIsRecorded() {
    let files = [failedNew, old]
    XCTAssertEqual(LocalPracticeFontSelection.selectedURL(in: files, selectedFilename: nil), failedNew)
    XCTAssertNil(LocalPracticeFontSelection.selectedURL(in: files, selectedFilename: ""),
      "An explicit empty selection must not activate a failed first import")
  }

  func testRecordedSelectionCannotSilentlySwitchToAFailedOrUnownedFile() {
    let files = [failedNew, old]
    XCTAssertEqual(LocalPracticeFontSelection.selectedURL(in: files,
      selectedFilename: old.lastPathComponent), old)
    XCTAssertNil(LocalPracticeFontSelection.selectedURL(in: files,
      selectedFilename: "missing.ttf"), "A stale choice must not fall through to an orphan")
    XCTAssertNil(LocalPracticeFontSelection.selectedURL(in: files,
      selectedFilename: "../\(old.lastPathComponent)"), "A stored value may name only an owned file")
  }

  func testLegacyChoiceAndEmptyFirstImportArePinnedBeforeAReplacementCanFail() throws {
    let suite = "typebar-font-selection-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let key = "selected-local-font"
    LocalPracticeFontSelection.pinLegacySelection(in: [old], defaults: defaults, key: key)
    XCTAssertEqual(defaults.string(forKey: key), old.lastPathComponent)
    LocalPracticeFontSelection.pinLegacySelection(in: [failedNew, old], defaults: defaults, key: key)
    XCTAssertEqual(defaults.string(forKey: key), old.lastPathComponent,
      "A retry must not replace a previously pinned choice")

    let firstImportKey = "first-import-selection"
    LocalPracticeFontSelection.pinLegacySelection(in: [], defaults: defaults, key: firstImportKey)
    XCTAssertEqual(defaults.string(forKey: firstImportKey), "")
    XCTAssertNil(LocalPracticeFontSelection.selectedURL(in: [failedNew],
      selectedFilename: defaults.string(forKey: firstImportKey)),
      "A failed first import may leave a file, but must not activate it")

    defaults.set(42, forKey: "invalid-selection")
    XCTAssertNil(LocalPracticeFontSelection.selectedURL(in: [failedNew, old],
      defaults: defaults, key: "invalid-selection"),
      "A malformed saved value must not be treated as an absent legacy setting")
  }
}
