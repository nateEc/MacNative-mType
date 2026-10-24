import AppKit
import XCTest
@testable import Typebar

@MainActor final class WebsiteArrowInputTests: XCTestCase {
  private func event(_ text: String, code: UInt16, flags: NSEvent.ModifierFlags = [], repeatKey: Bool = false,
    ignoring: String? = nil) throws -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
      timestamp: 1, windowNumber: 0, context: nil, characters: text,
      charactersIgnoringModifiers: ignoring ?? text, isARepeat: repeatKey, keyCode: code))
  }

  func testWebsiteLetterBindingsAndPhysicalArrowsInsertOnce() throws {
    for (text, code, direction) in [("a", 0, "←"), ("s", 1, "↓"), ("w", 13, "↑"), ("d", 2, "→"),
      ("j", 38, "←"), ("k", 40, "↓"), ("i", 34, "↑"), ("l", 37, "→"),
      ("", 123, "←"), ("", 125, "↓"), ("", 126, "↑"), ("", 124, "→")] {
      let input = TypingInputView(frame: .zero)
      input.mapsArrowKeysToInput = true
      input.mapsArrowLetterKeysToInput = true
      var inserts: [String] = []
      input.onInsert = { text, forced in XCTAssertFalse(forced); inserts.append(text) }
      input.keyDown(with: try event(text, code: UInt16(code)))
      input.keyDown(with: try event(text, code: UInt16(code), repeatKey: true))
      XCTAssertEqual(inserts, [direction])
    }
  }

  func testLegacyArrowModeDoesNotRemapLettersAndDisabledSourceCannotInsert() throws {
    let input = TypingInputView(frame: .zero)
    input.mapsArrowKeysToInput = true
    var inserts: [String] = []
    input.onInsert = { text, _ in inserts.append(text) }
    input.keyDown(with: try event("a", code: 0))
    XCTAssertEqual(inserts, ["a"])
    input.mapsArrowLetterKeysToInput = true
    input.acceptsTextInput = false
    input.keyDown(with: try event("a", code: 0))
    input.keyDown(with: try event("", code: 126))
    XCTAssertEqual(inserts, ["a"])
  }

  func testControlLetterKeepsItsLogicalKeyAndShiftDoesNotCaseFold() throws {
    let input = TypingInputView(frame: .zero)
    input.mapsArrowLetterKeysToInput = true
    var inserts: [String] = []
    input.onInsert = { text, _ in inserts.append(text) }
    input.keyDown(with: try event("\u{1}", code: 0, flags: .control, ignoring: "a"))
    XCTAssertEqual(inserts, ["←"])
    input.keyDown(with: try event("A", code: 0, flags: .shift))
    XCTAssertEqual(inserts.last, "A")
  }
}
