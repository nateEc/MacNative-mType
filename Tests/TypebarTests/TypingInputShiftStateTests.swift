import AppKit
import IOKit.hidsystem
import XCTest
@testable import Typebar

@MainActor final class TypingInputShiftStateTests: XCTestCase {
  @MainActor private final class Practice {
    let input = TypingInputView(frame: .zero)
    var session: TypingSession
    var physical: [UInt16: Bool] = [:]
    init(_ target: String) {
      session = TypingSession(configuration: .words(1, rules: .init(oppositeShiftMode: .on)), prompt: target)
      input.keyboardInputMapping = .builtIn(.ansiQwerty)
      input.oppositeShiftMode = .on
      input.onInsert = { [weak self] text, forced in
        self?.session.insertBatch(text, forceError: forced, at: Date(timeIntervalSinceReferenceDate: 925_800_000))
      }
      input.onPhysicalKey = { [weak self] code, pressed, _ in self?.physical[code] = pressed }
    }
  }
  private let left = NSEvent.ModifierFlags.shift.union(.init(rawValue: UInt(NX_DEVICELSHIFTKEYMASK)))
  private let right = NSEvent.ModifierFlags.shift.union(.init(rawValue: UInt(NX_DEVICERSHIFTKEYMASK)))
  private func event(_ type: NSEvent.EventType, _ code: UInt16,
    _ flags: NSEvent.ModifierFlags, _ text: String = "") throws -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
      timestamp: 1, windowNumber: 0, context: nil, characters: text,
      charactersIgnoringModifiers: text.lowercased(), isARepeat: false, keyCode: code))
  }

  func testReleaseWithoutObservedPressDoesNotStopUnshiftedCorrectInput() throws {
    for (shift, code, target) in [(UInt16(56), UInt16(0), "a"), (60, 4, "h")] {
      let p = Practice(target); defer { p.input.retirePageCallbacks() }
      p.input.flagsChanged(with: try event(.flagsChanged, shift, []))
      p.input.keyDown(with: try event(.keyDown, code, [], target))
      XCTAssertEqual(p.physical[shift], false)
      XCTAssertEqual(p.session.typed, target)
      XCTAssertEqual(p.session.outcome, .completed)
      XCTAssertEqual(p.session.result()?.preciseAccuracy, 100)
    }
  }

  func testRepeatedDeviceDownDoesNotForgetTheHeldWrongHand() throws {
    for (shift, code, target, flags) in [(UInt16(56), UInt16(0), "A", left), (60, 4, "H", right)] {
      let p = Practice(target); defer { p.input.retirePageCallbacks() }
      let down = try event(.flagsChanged, shift, flags)
      p.input.flagsChanged(with: down); p.input.flagsChanged(with: down)
      p.input.keyDown(with: try event(.keyDown, code, flags, target))
      XCTAssertEqual(p.physical[shift], true)
      XCTAssertEqual(p.session.typed, "")
      XCTAssertFalse(p.session.isFinished)
    }
  }

  func testDeviceSnapshotIdentifiesOppositeSideWhenItsPressWasNotObserved() throws {
    let p = Practice("A"); defer { p.input.retirePageCallbacks() }
    // First observed transition is left release while right is still held.
    p.input.flagsChanged(with: try event(.flagsChanged, 56, right))
    p.input.keyDown(with: try event(.keyDown, 0, right, "A"))
    XCTAssertEqual(p.physical[56], false)
    XCTAssertEqual(p.session.typed, "A")
    XCTAssertEqual(p.session.outcome, .completed)
  }

  func testOrdinaryKeySnapshotRejectsWrongHandEvenWithoutModifierCallbacks() throws {
    let wrong = Practice("A"); defer { wrong.input.retirePageCallbacks() }
    wrong.input.keyDown(with: try event(.keyDown, 0, left, "A"))
    XCTAssertEqual(wrong.session.typed, "")
    XCTAssertFalse(wrong.session.isFinished)
    let correct = Practice("A"); defer { correct.input.retirePageCallbacks() }
    correct.input.keyDown(with: try event(.keyDown, 0, right, "A"))
    XCTAssertEqual(correct.session.typed, "A")
    XCTAssertEqual(correct.session.outcome, .completed)
  }

  func testUnshiftedKeyClearsAReleaseMissedAcrossFocusChanges() throws {
    let p = Practice("a"); defer { p.input.retirePageCallbacks() }
    p.input.flagsChanged(with: try event(.flagsChanged, 56, left))
    _ = p.input.resignFirstResponder()
    // A release delivered after the old focus was lost must remain released.
    p.input.flagsChanged(with: try event(.flagsChanged, 56, []))
    p.input.keyDown(with: try event(.keyDown, 0, [], "a"))
    XCTAssertEqual(p.session.typed, "a")
    XCTAssertEqual(p.session.outcome, .completed)
    let missed = Practice("a"); defer { missed.input.retirePageCallbacks() }
    missed.input.flagsChanged(with: try event(.flagsChanged, 56, left))
    missed.input.keyDown(with: try event(.keyDown, 0, [], "a"))
    XCTAssertEqual(missed.session.typed, "a")
    XCTAssertEqual(missed.session.outcome, .completed)
  }

  func testAggregateOnlySyntheticTransitionsKeepBothHandReleaseFallback() throws {
    let p = Practice("a"); defer { p.input.retirePageCallbacks() }
    for (code, flags, l, r) in [(UInt16(56), NSEvent.ModifierFlags.shift, true, false),
      (60, .shift, true, true), (56, .shift, false, true), (60, [], false, false)] {
      p.input.flagsChanged(with: try event(.flagsChanged, code, flags))
      XCTAssertEqual(p.physical[56] ?? false, l)
      XCTAssertEqual(p.physical[60] ?? false, r)
    }
    p.input.keyDown(with: try event(.keyDown, 0, [], "a"))
    XCTAssertEqual(p.session.outcome, .completed)
  }
}
