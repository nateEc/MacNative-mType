import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class ReplayTextIdentityTests: XCTestCase {
  private let aliases = [("é", "e\u{301}"), ("각", "\u{1100}\u{1161}\u{11a8}"),
    ("q\u{323}\u{301}", "q\u{301}\u{323}")]
  private func glyphs(_ text: String) -> [TypingPromptGlyph] {
    text.map { .init(character: $0, state: .correct) }
  }
  private func assertUnits(_ actual: String, _ expected: String,
    file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(Array(actual.utf16), Array(expected.utf16), file: file, line: line)
  }

  func testInputReplacesCanonicalAliasesAndKeepsExactUpdatesAsNoOps() {
    for (a, b) in aliases {
      XCTAssertEqual(a, b)
      for (old, new) in [(a, b), (b, a)] {
        let view = ReplayInputTextView()
        XCTAssertTrue(view.update(glyphs: glyphs(old + "x")))
        XCTAssertTrue(view.update(glyphs: glyphs(new + "x")))
        assertUnits(view.string, new + "x")
        XCTAssertFalse(view.update(glyphs: glyphs(new + "x")))
      }
    }
  }

  func testChangedPrefixSpellingRebuildsFollowingOffsetsThroughAppendAndRewind() throws {
    for (a, b) in aliases {
      for (old, new) in [(a, b), (b, a)] {
        let view = ReplayInputTextView()
        view.update(glyphs: glyphs(old + "x"))
        let changed = glyphs(new) + [.init(character: "y", state: .incorrect)]
        XCTAssertTrue(view.update(glyphs: changed))
        assertUnits(view.string, new + "y")
        let storage = try XCTUnwrap(view.textStorage)
        if storage.length == (new + "y").utf16.count {
          XCTAssertEqual(storage.attribute(.foregroundColor, at: new.utf16.count,
            effectiveRange: nil) as? NSColor, .systemRed)
        }
        XCTAssertTrue(view.update(glyphs: changed + [.init(character: "🙂", state: .extra)]))
        assertUnits(view.string, new + "y🙂")
        XCTAssertTrue(view.update(glyphs: glyphs(new)))
        assertUnits(view.string, new)
        XCTAssertTrue(view.update(glyphs: []))
        XCTAssertEqual(view.string, "等待播放")
      }
    }
  }

  func testPickerReplacesCanonicalTargetWithUnchangedInteractionState() {
    for (a, b) in aliases {
      for (old, new) in [(a, b), (b, a)] {
        let view = ReplayCharacterTextView()
        view.update(text: old + "x", reachableIndices: [0, 1], selectedIndex: 1)
        view.update(text: new + "x", reachableIndices: [0, 1], selectedIndex: 1)
        assertUnits(view.string, new + "x")
      }
    }
  }

  func testUnrenderedCanonicalTypedMetadataKeepsTheExistingNoOpBehavior() {
    let view = ReplayInputTextView()
    XCTAssertTrue(view.update(glyphs: [.init(character: "x", state: .correct, typedCharacter: "é")]))
    XCTAssertFalse(view.update(glyphs: [.init(character: "x", state: .correct,
      typedCharacter: Character("e\u{301}"))]))
    XCTAssertEqual(view.string, "x")
  }

  func testPickerReplacesCanonicalGlyphsAndMovesStylesToTheNewUnitOffset() throws {
    for (a, b) in aliases {
      let view = ReplayCharacterTextView()
      view.update(text: a + "x", reachableIndices: [0, 1], selectedIndex: 1,
        glyphs: glyphs(a + "x"), errorIndices: [1])
      view.update(text: b + "x", reachableIndices: [0, 1], selectedIndex: 1,
        glyphs: glyphs(b + "x"), errorIndices: [1])
      assertUnits(view.string, b + "x")
      let storage = try XCTUnwrap(view.textStorage)
      if storage.length == (b + "x").utf16.count {
        XCTAssertEqual(storage.attribute(.underlineColor, at: b.utf16.count,
          effectiveRange: nil) as? NSColor, .controlAccentColor)
      }
    }
  }

  private func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(descendants)
  }
  private func flush(_ host: NSView) {
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.03))
    host.layoutSubtreeIfNeeded()
  }

  func testSwiftUIInputBridgeDeliversRawAliasToTheSameNativeReceiver() throws {
    let host = NSHostingView(rootView: ReplayInputView(glyphs: glyphs("éx")))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 320, height: 100),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { window.contentView = nil; window.close() }
    flush(host)
    let view = try XCTUnwrap(descendants(host).compactMap { $0 as? ReplayInputTextView }.first)
    host.rootView = ReplayInputView(glyphs: glyphs("e\u{301}x"))
    flush(host)
    XCTAssertTrue(descendants(host).contains { $0 === view })
    assertUnits(view.string, "e\u{301}x")
    XCTAssertFalse(window.isVisible)
  }

  func testSwiftUITargetBridgeDeliversRawAliasToTheSameNativeReceiver() throws {
    let host = NSHostingView(rootView: ReplayCharacterPicker(text: "각x",
      reachableIndices: [0, 1], selectedIndex: nil, onSelect: { _ in }))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 320, height: 100),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { window.contentView = nil; window.close() }
    flush(host)
    let view = try XCTUnwrap(descendants(host).compactMap { $0 as? ReplayCharacterTextView }.first)
    host.rootView = ReplayCharacterPicker(text: "\u{1100}\u{1161}\u{11a8}x",
      reachableIndices: [0, 1], selectedIndex: nil, onSelect: { _ in })
    flush(host)
    XCTAssertTrue(descendants(host).contains { $0 === view })
    assertUnits(view.string, "\u{1100}\u{1161}\u{11a8}x")
    XCTAssertFalse(window.isVisible)
  }
}
