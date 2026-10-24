import AppKit
import XCTest
@testable import Typebar

@MainActor final class AccountingInputTests: XCTestCase {
  private func enter(_ code: UInt16, flags: NSEvent.ModifierFlags = [], repeatKey: Bool = false) throws -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
      timestamp: 1, windowNumber: 0, context: nil, characters: code == 76 ? "\u{3}" : "\r",
      charactersIgnoringModifiers: code == 76 ? "\u{3}" : "\r", isARepeat: repeatKey, keyCode: code))
  }

  func testAccountingEnterEmulatesSpaceBeforeRestartNewlineBailoutAndZenHandlers() throws {
    for code: UInt16 in [36, 76] {
      for flags: NSEvent.ModifierFlags in [[], .shift, .command, .option, .control] {
        let input = TypingInputView(frame: .zero)
        input.mapsEnterToSpace = true
        input.acceptsNewlineInput = true
        input.quickRestartKey = .enter
        input.disablesQuickRestart = true
        input.enablesLongTestBailout = true
        input.finishesOnShiftEnter = true
        var inserts: [String] = [], otherActions = 0
        input.onInsert = { text, forced in XCTAssertFalse(forced); inserts.append(text) }
        input.onRestart = { otherActions += 1 }
        input.onBailoutArmed = { otherActions += 1 }
        input.onBailout = { otherActions += 1 }
        input.onFinishZen = { otherActions += 1 }
        input.onQuickRestartProtectionRequired = { otherActions += 1 }
        input.keyDown(with: try enter(code, flags: flags))
        input.keyDown(with: try enter(code, flags: flags, repeatKey: true))
        XCTAssertEqual(inserts, [" "], "\(code), \(flags)")
        XCTAssertEqual(otherActions, 0)
      }
    }
  }

  func testDisabledEmulationRetainsExistingReturnRestart() throws {
    let input = TypingInputView(frame: .zero)
    XCTAssertFalse(input.mapsEnterToSpace)
    input.quickRestartKey = .enter
    var restarts = 0
    input.onRestart = { restarts += 1 }
    input.onInsert = { _, _ in XCTFail("Legacy Return must not become space") }
    input.keyDown(with: try enter(36))
    XCTAssertEqual(restarts, 1)
  }

  func testDisabledTextAdmissionConsumesEmulatedEnterWithoutAction() throws {
    let input = TypingInputView(frame: .zero)
    input.mapsEnterToSpace = true
    input.acceptsTextInput = false
    input.quickRestartKey = .enter
    input.onInsert = { _, _ in XCTFail("Loading input must not insert") }
    input.onRestart = { XCTFail("Emulated Enter cannot fall through to restart") }
    input.keyDown(with: try enter(36))
  }

  func testActualAccountingSessionCanAdvanceWithReturnThenCompleteAndReplay() async throws {
    let draft = try WebsiteConfigNativeProfile.prepareDraft(
      #"{"mode":"words","words":2,"funbox":["58008"]}"#, pointsPerRem: 16,
      context: .init(authenticated: true))
    let ready = try await WebsiteConfigSessionBuilder.prepare(draft: draft, scope: .init(),
      random: .init(contentUnit: { 0.5 }))
    var session = ready.session
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let input = TypingInputView(frame: .zero)
    input.mapsEnterToSpace = WebsiteRandomWordGenerator.selected(for: session.configuration) == .accounting
    input.onInsert = { text, forced in session.insertBatch(text, forceError: forced, at: start.addingTimeInterval(1)) }
    session.insertBatch("5555", at: start)
    input.keyDown(with: try enter(76))
    XCTAssertEqual(session.typed, "5555 ")
    session.insertBatch("5555", at: start.addingTimeInterval(2))
    XCTAssertEqual(session.outcome, .completed)
    let result = try XCTUnwrap(session.result(at: start.addingTimeInterval(2)))
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: result.elapsedDuration), "5555 5555")
  }
}
