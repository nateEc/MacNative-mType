import XCTest
import AppKit
@testable import Typebar

@MainActor final class WebsiteConfigClipboardExportTests: XCTestCase {
  func testClipboardOutcomesMatchSourceAndFallbackReadsCurrentConfiguration() throws {
    for fixture in try WebsiteConfigExportSourceOracle.load() {
      var current = fixture.settingsJSON
      var copied: [String] = [], delays: [Int] = [], callbacks: [@MainActor () -> Void] = []
      let export = WebsiteConfigClipboardExport(write: { copied.append($0); return !fixture.failure },
        schedule: { delay, callback in delays.append(delay); callbacks.append(callback) })
      export.copy(read: { current })
      XCTAssertEqual(copied, [fixture.settingsJSON])
      XCTAssertEqual(delays, fixture.delays)
      XCTAssertNil(export.manualCopy)
      XCTAssertEqual(export.noticeDurationMilliseconds, fixture.failure ? 5000 : nil)
      if let fallback = fixture.fallbackJSON { current = fallback }
      callbacks.forEach { $0() }
      XCTAssertEqual(export.manualCopy?.json, fixture.fallbackJSON, fixture.label)
      XCTAssertEqual(current, fixture.fallbackJSON ?? fixture.settingsJSON)
      XCTAssertFalse(fixture.changedByExport)
      if fixture.failure {
        XCTAssertEqual(fixture.readOnly, true)
        XCTAssertEqual(fixture.clickToSelect, true)
      }
    }
  }

  func testManualCopyUsesSelectableReadOnlyTextAndPreservesUTF16() {
    let text = WebsiteConfigCopyTextView(frame: .init(x: 0, y: 0, width: 500, height: 300))
    let json = #"{"customBackground":"字😀\ud800"}"#
    text.string = json
    XCTAssertNotNil(text.textStorage)
    XCTAssertNotNil(text.layoutManager)
    XCTAssertTrue(text.string.utf8.elementsEqual(json.utf8))
    XCTAssertFalse(text.isEditable)
    XCTAssertTrue(text.isSelectable)
    text.selectAll(nil)
    XCTAssertEqual(text.selectedRange(), NSRange(location: 0, length: json.utf16.count))
    XCTAssertEqual(text.accessibilityIdentifier(), "website-config-manual-copy")
  }
}
