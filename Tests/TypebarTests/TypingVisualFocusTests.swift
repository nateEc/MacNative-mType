import AppKit
import XCTest
@testable import Typebar

@MainActor final class TypingVisualFocusTests: XCTestCase {
  @MainActor private final class Frames {
    var callbacks: [@MainActor () -> Void] = []
    func flush() { let batch = callbacks; callbacks.removeAll(); batch.forEach { $0() } }
    func makeFocus() -> TypingVisualFocus { TypingVisualFocus { [weak self] in self?.callbacks.append($0) } }
  }

  func testEntryIsDeferredAndChecksCommittedRatherThanPendingState() {
    let frames = Frames(), focus = frames.makeFocus()
    focus.set(true); focus.set(false)
    XCTAssertFalse(focus.isFocused)
    frames.flush(); XCTAssertTrue(focus.isFocused)
    focus.set(false); focus.set(true)
    XCTAssertTrue(focus.isFocused)
    frames.flush(); XCTAssertFalse(focus.isFocused)
  }

  func testRepeatedSameTurnRequestsHaveOnlyOneQueuedCommit() {
    let frames = Frames(), focus = frames.makeFocus()
    for _ in 0..<100 { focus.set(true) }
    XCTAssertEqual(frames.callbacks.count, 1, "Repeated input must not grow a queue of stale commits")
    frames.flush(); XCTAssertTrue(focus.isFocused)
  }

  func testMovementPreservesStrictPositiveAxisThresholdAndTransitionGuard() {
    let frames = Frames(), focus = frames.makeFocus()
    focus.set(true); frames.flush()
    for (x, y) in [(3.0, 3.0), (-100.0, -100.0), (4.0, 5.0)] {
      focus.mouseMoved(x: x, y: y, transitioning: x == 4)
      frames.flush(); XCTAssertTrue(focus.isFocused)
    }
    focus.mouseMoved(x: 0, y: 3.001)
    XCTAssertTrue(focus.isFocused)
    frames.flush(); XCTAssertFalse(focus.isFocused)
  }

  func testActualPartialBatchEntersFocusEvenWhenItsFinalRejectionHasNoSoundFeedback() {
    let frames = Frames(), focus = frames.makeFocus()
    var session = TypingSession(configuration: .words(10), prompt: "amber tail")
    let before = session.typed
    let feedback = TypingLiveInputFeedback.insertBatch("a\n", into: &session)
    XCTAssertTrue(feedback.isEmpty); XCTAssertEqual(session.typed, "a")
    focus.inputDidUpdate(hasFeedback: !feedback.isEmpty,
      textChanged: session.typed != before, isFinished: session.isFinished)
    frames.flush(); XCTAssertTrue(focus.isFocused)
  }

  func testRejectedInputAndFinishedSessionDoNotEnterButStoppedErrorFeedbackDoes() {
    let frames = Frames(), focus = frames.makeFocus()
    var session = TypingSession(configuration: .words(10,
      rules: .init(stopOnErrorMode: .letter)), prompt: "amber tail")
    let before = session.typed
    let rejected = TypingLiveInputFeedback.insertBatch("\n", into: &session)
    focus.inputDidUpdate(hasFeedback: !rejected.isEmpty,
      textChanged: session.typed != before, isFinished: session.isFinished)
    frames.flush(); XCTAssertFalse(focus.isFocused)
    let stopped = TypingLiveInputFeedback.insertBatch("x", into: &session)
    XCTAssertEqual(stopped, [false]); XCTAssertEqual(session.typed, "")
    focus.inputDidUpdate(hasFeedback: !stopped.isEmpty, textChanged: false, isFinished: session.isFinished)
    frames.flush(); XCTAssertTrue(focus.isFocused)
    focus.retire()
    focus.inputDidUpdate(hasFeedback: true, textChanged: true, isFinished: true)
    frames.flush(); XCTAssertFalse(focus.isFocused)
  }

  func testRetirementInvalidatesPendingEntryAndAllowsANewAttempt() {
    let frames = Frames(), focus = frames.makeFocus()
    focus.set(true); focus.retire(); frames.flush()
    XCTAssertFalse(focus.isFocused)
    focus.set(true); frames.flush(); XCTAssertTrue(focus.isFocused)
    focus.mouseMoved(x: 10, y: 0); focus.retire()
    focus.set(true); frames.flush(); XCTAssertTrue(focus.isFocused)
  }

  func testQueuedCallbacksDoNotRetainRetiredWindowState() {
    let frames = Frames()
    weak var weakFocus: TypingVisualFocus?
    do { let focus = frames.makeFocus(); weakFocus = focus; focus.set(true) }
    XCTAssertNil(weakFocus); frames.flush()
  }

  func testDefaultSchedulerCommitsOnNativeNextTurn() async {
    let focus = TypingVisualFocus()
    focus.set(true); XCTAssertFalse(focus.isFocused)
    await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    XCTAssertTrue(focus.isFocused)
    focus.retire(); XCTAssertFalse(focus.isFocused)
  }

  func testVisualFocusFiltersButDoesNotRemoveOrdinaryNoticesOrTheirHistory() {
    let frames = Frames(), focus = frames.makeFocus(), notices = LocalNoticeCenter()
    defer { notices.clearAll() }
    notices.post("Owned ordinary", options: .init(durationMilliseconds: 0))
    notices.post("Owned important", options: .init(important: true, durationMilliseconds: 0))
    XCTAssertEqual(notices.visible(focused: focus.isFocused).count, 2)
    focus.set(true); frames.flush()
    XCTAssertEqual(notices.visible(focused: focus.isFocused).map(\.entry.message), ["Owned important"])
    focus.mouseMoved(x: 4, y: 0); frames.flush()
    XCTAssertEqual(notices.visible(focused: focus.isFocused).count, 2)
    XCTAssertEqual(notices.active.count, 2); XCTAssertEqual(notices.history.count, 2)
  }

  func testNativeStateAgainstCompletePinnedFocusAndDebouncedFrameModules() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Readiness supplies the pinned clean reference")
    }
    struct Action: Decodable { let kind: String; let value: Bool?; let x: Double?; let y: Double?; let transitioning: Bool? }
    struct Fixture: Decodable { let name: String; let actions: [Action]; let states: [Bool] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-visual-focus.mjs").path, reference, "--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile(), diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0, String(decoding: diagnostics, as: UTF8.self))
    guard process.terminationStatus == 0 else { return }
    let fixtures = try JSONDecoder().decode([Fixture].self, from: data)
    XCTAssertEqual(fixtures.count, 12)
    for fixture in fixtures {
      let frames = Frames(), focus = frames.makeFocus()
      XCTAssertEqual(fixture.actions.count, fixture.states.count)
      for (index, action) in fixture.actions.enumerated() {
        switch action.kind {
        case "set": focus.set(try XCTUnwrap(action.value))
        case "move": focus.mouseMoved(x: try XCTUnwrap(action.x), y: try XCTUnwrap(action.y), transitioning: try XCTUnwrap(action.transitioning))
        case "flush": frames.flush()
        default: XCTFail("Unknown source action: \(action.kind)")
        }
        XCTAssertEqual(focus.isFocused, fixture.states[index], "\(fixture.name), step \(index)")
      }
    }
  }
}

@MainActor final class TypingVisualFocusMouseTests: XCTestCase {
  private final class Window: NSWindow {
    var testIsKey = true
    var testSheet: NSWindow?
    override var isKeyWindow: Bool { testIsKey }
    override var attachedSheet: NSWindow? { testSheet }
  }

  func testAppKitTrackingAreaIsSingularWindowLocalAndDoesNotHitTest() throws {
    _ = NSApplication.shared
    let window = Window(contentRect: .init(x: 0, y: 0, width: 320, height: 200), styleMask: .borderless, backing: .buffered, defer: false)
    let view = TypingVisualFocusMouseView(frame: .init(x: 0, y: 0, width: 320, height: 200))
    window.isReleasedWhenClosed = false
    defer { window.contentView = nil; window.close() }
    window.contentView = view
    for _ in 0..<10 { view.updateTrackingAreas() }
    XCTAssertEqual(view.trackingAreas.count, 1)
    let area = try XCTUnwrap(view.trackingAreas.first)
    XCTAssertTrue(area.owner === view)
    XCTAssertEqual(area.options, [.mouseMoved, .activeInKeyWindow, .inVisibleRect])
    XCTAssertNil(view.hitTest(.init(x: 10, y: 10)))
    XCTAssertFalse(window.isVisible, "Never activate/orderFront a QA window")
    window.contentView = nil
    XCTAssertTrue(view.trackingAreas.isEmpty)
  }

  func testDirectAppKitDeliveryIgnoresOtherWindowsBackgroundAndDetachedViews() {
    _ = NSApplication.shared
    let window = Window(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
    let other = Window(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
    let view = TypingVisualFocusMouseView(frame: .zero)
    window.isReleasedWhenClosed = false; other.isReleasedWhenClosed = false
    defer { window.contentView = nil; window.close(); other.close() }
    var movements: [[Double]] = []
    view.onMovement = { movements.append([$0, $1]) }
    window.contentView = view
    view.receiveMovement(x: 4, y: -5, from: other)
    view.receiveMovement(x: 4, y: -5, from: nil)
    window.testIsKey = false; view.receiveMovement(x: 4, y: -5, from: window)
    window.testIsKey = true; window.testSheet = other
    view.receiveMovement(x: 4, y: -5, from: window)
    window.testSheet = nil
    XCTAssertTrue(movements.isEmpty)
    window.testIsKey = true; view.receiveMovement(x: 4, y: -5, from: window)
    XCTAssertEqual(movements, [[4, -5]])
    window.contentView = nil; view.receiveMovement(x: 9, y: 9, from: window)
    XCTAssertEqual(movements.count, 1)
    XCTAssertFalse(window.isVisible); XCTAssertFalse(other.isVisible)
  }

  func testAppKitViewCanMoveBetweenWindowsWithoutLeavingOldTrackingAreas() {
    _ = NSApplication.shared
    let first = Window(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
    let second = Window(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
    first.isReleasedWhenClosed = false; second.isReleasedWhenClosed = false
    let view = TypingVisualFocusMouseView(frame: .zero)
    defer { first.contentView = nil; second.contentView = nil; first.close(); second.close() }
    var deliveries = 0; view.onMovement = { _, _ in deliveries += 1 }
    first.contentView = view; XCTAssertEqual(view.trackingAreas.count, 1)
    first.contentView = nil; second.contentView = view
    XCTAssertEqual(view.trackingAreas.count, 1)
    view.receiveMovement(x: 4, y: 0, from: first); XCTAssertEqual(deliveries, 0)
    view.receiveMovement(x: 4, y: 0, from: second); XCTAssertEqual(deliveries, 1)
    TypingVisualFocusMouseBridge.dismantleNSView(view, coordinator: ())
    XCTAssertTrue(view.trackingAreas.isEmpty)
    view.receiveMovement(x: 4, y: 0, from: second); XCTAssertEqual(deliveries, 1)
    XCTAssertFalse(first.isVisible); XCTAssertFalse(second.isVisible)
  }
}
