import AppKit
import XCTest
@testable import Typebar

final class CompositionHotkeyTests: XCTestCase {
  @MainActor
  private func escape(
    modifiers: NSEvent.ModifierFlags = [], repeatKey: Bool = false, kind: NSEvent.EventType = .keyDown
  ) throws -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(
      with: kind, location: .zero, modifierFlags: modifiers, timestamp: 1,
      windowNumber: 0, context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}",
      isARepeat: repeatKey, keyCode: 53))
  }

  @MainActor
  func testMarkedEscapeDoesNotOpenTheCommandPaletteAndStillReportsThePhysicalKey() throws {
    let input = TypingInputView(frame: .zero)
    var palettes = 0
    var inserts = [String]()
    var physicalKeys = [UInt16]()
    input.onOpenCommandPalette = { palettes += 1 }
    input.onInsert = { text, _ in inserts.append(text) }
    input.onPhysicalKey = { code, down, _ in if down { physicalKeys.append(code) } }
    input.setMarkedText("候选", selectedRange: .init(), replacementRange: .init())
    input.keyDown(with: try escape())
    XCTAssertEqual(palettes, 0)
    XCTAssertTrue(inserts.isEmpty)
    XCTAssertEqual(physicalKeys, [53])
  }

  @MainActor
  func testMarkedEscapeDoesNotRestartOrDisplayLongTestRestartProtection() throws {
    for protected in [false, true] {
      let input = TypingInputView(frame: .zero)
      input.quickRestartKey = .escape
      input.requiresShiftQuickRestart = protected
      var restarts = 0
      var protections = 0
      input.onRestart = { restarts += 1 }
      input.onQuickRestartProtectionRequired = { protections += 1 }
      input.setMarkedText("候选", selectedRange: .init(), replacementRange: .init())
      input.keyDown(with: try escape())
      XCTAssertEqual(restarts, 0)
      XCTAssertEqual(protections, 0)
    }
  }

  @MainActor
  func testCompositionCancelCommandClearsMarkedTextWithoutCommitting() {
    let input = TypingInputView(frame: .zero)
    var marked = [String]()
    var inserts = [String]()
    input.onCompositionChanged = { marked.append($0) }
    input.onInsert = { text, _ in inserts.append(text) }
    input.setMarkedText("候选", selectedRange: .init(), replacementRange: .init())
    input.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
    XCTAssertFalse(input.hasMarkedText())
    XCTAssertEqual(input.markedRange().location, NSNotFound)
    XCTAssertEqual(marked.last, "")
    XCTAssertTrue(inserts.isEmpty)
  }

  @MainActor
  func testEscapeShortcutsResumeOnceMarkedTextHasEnded() throws {
    for restartKey in [QuickRestartKey.off, .escape] {
      let input = TypingInputView(frame: .zero)
      input.quickRestartKey = restartKey
      var palettes = 0
      var restarts = 0
      input.onOpenCommandPalette = { palettes += 1 }
      input.onRestart = { restarts += 1 }
      input.setMarkedText("候选", selectedRange: .init(), replacementRange: .init())
      input.unmarkText()
      input.keyDown(with: try escape())
      XCTAssertEqual(palettes, restartKey == .off ? 1 : 0)
      XCTAssertEqual(restarts, restartKey == .escape ? 1 : 0)
    }
  }

  @MainActor
  func testShiftEscapeStillUsesTheExplicitConfiguredRestart() throws {
    let input = TypingInputView(frame: .zero)
    input.quickRestartKey = .escape
    var restarts = 0
    input.onRestart = { restarts += 1 }
    input.setMarkedText("候选", selectedRange: .init(), replacementRange: .init())
    input.keyDown(with: try escape(modifiers: [.shift]))
    XCTAssertEqual(restarts, 1)
  }

  @MainActor
  func testCompositionEscapeReleaseIsReportedEvenAfterCompositionHasEnded() throws {
    let input = TypingInputView(frame: .zero)
    var physical = [String]()
    var palettes = 0
    input.onPhysicalKey = { code, down, _ in physical.append("\(code):\(down)") }
    input.onOpenCommandPalette = { palettes += 1 }
    input.setMarkedText("候选", selectedRange: .init(), replacementRange: .init())
    input.keyDown(with: try escape())
    input.unmarkText()
    input.keyUp(with: try escape(kind: .keyUp))
    XCTAssertEqual(physical, ["53:true", "53:false"])
    XCTAssertEqual(palettes, 0)

    input.keyDown(with: try escape())
    input.keyUp(with: try escape(kind: .keyUp))
    XCTAssertEqual(physical, ["53:true", "53:false"])
    XCTAssertEqual(palettes, 1)
  }
}
