import AppKit
import XCTest
@testable import Typebar

@MainActor final class InputViewLifecycleTests: XCTestCase {
  private final class Probe { var calls = 0 }
  private final class Owner {
    let probe: Probe
    init(_ probe: Probe) { self.probe = probe }
    func called() { probe.calls += 1 }
  }

  func testDismantlingRetainedInputReleasesEveryPageCallbackAndRejectsLateEvents() {
    let view = TypingInputView()
    XCTAssertTrue(view.acceptsFirstResponder)
    let probe = Probe()
    weak var released: Owner?
    do {
      let owner = Owner(probe)
      released = owner
      view.onInsert = { [owner] _, _ in owner.called() }
      view.onDelete = { [owner] in owner.called() }
      view.onDeleteWord = { [owner] in owner.called() }
      view.onRestart = { [owner] in owner.called() }
      view.onOpenCommandPalette = { [owner] in owner.called() }
      view.onBailoutArmed = { [owner] in owner.called() }
      view.onBailout = { [owner] in owner.called() }
      view.onQuickRestartProtectionRequired = { [owner] in owner.called() }
      view.onFinishZen = { [owner] in owner.called() }
      view.onFocusChanged = { [owner] _ in owner.called() }
      view.onWindowFocusChanged = { [owner] _, _ in owner.called() }
      view.onCompositionStarted = { [owner] in owner.called() }
      view.onCompositionChanged = { [owner] _ in owner.called() }
      view.shouldFinishWithComposition = { [owner] _, _ in owner.called(); return true }
      view.onModifierFlagsChanged = { [owner] _ in owner.called() }
      view.onKeyDown = { [owner] _, _, _, _ in owner.called() }
      view.onPhysicalKey = { [owner] _, _, _ in owner.called() }
      view.bailoutClock = { [owner] in owner.called(); return .distantPast }
    }
    XCTAssertNotNil(released, "The native callbacks must really own the page before dismantling")
    NativeTypingInput.dismantleNSView(view, coordinator: NativeTypingInput.Coordinator())
    XCTAssertFalse(view.acceptsFirstResponder, "A retired input must not accept an already queued focus request")
    XCTAssertNil(released, "An AppKit-retained input must not keep its retired page/query owner alive")
    view.onInsert("x", false)
    view.onDelete(); view.onDeleteWord(); view.onRestart(); view.onOpenCommandPalette()
    view.onBailoutArmed(); view.onBailout(); view.onQuickRestartProtectionRequired(); view.onFinishZen()
    view.onFocusChanged(false); view.onWindowFocusChanged(false, false)
    view.onCompositionStarted(); view.onCompositionChanged("x")
    XCTAssertFalse(view.shouldFinishWithComposition("x", false))
    view.onModifierFlagsChanged([]); view.onKeyDown(0, "x", [], false); view.onPhysicalKey(0, false, false)
    XCTAssertNotEqual(view.bailoutClock(), .distantPast)
    XCTAssertEqual(probe.calls, 0, "Late native events must not invoke retired page callbacks")
  }
}
