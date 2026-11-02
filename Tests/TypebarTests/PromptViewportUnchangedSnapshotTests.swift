import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class PromptViewportUnchangedSnapshotTests: XCTestCase {
  func testSequenceCaretRemainsWithItsSnapshotAndReplacementUsesCurrentInput() throws {
    var session = TypingSession(configuration: .words(70),
      prompt: Array(repeating: "oak", count: 70).joined(separator: " "))
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
    let style = PromptRenderStyle(theme: .init(background: .white, panel: .white,
      accent: .blue, colorScheme: .light), fontSize: 28)
    let old = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: directory, style: style, width: 800, font: font))
    let opening = try XCTUnwrap(old.append(fields: 0..<32))
    XCTAssertEqual(opening.layout.mainRect(style: .bar), opening.layout.cellFrames[0])
    session.insert("o", at: Date(timeIntervalSinceReferenceDate: 920_500_000))
    let replacement = try XCTUnwrap(old.replacingSession(session, style: style))
    let updated = try XCTUnwrap(replacement.append(fields: 0..<32))
    XCTAssertEqual(updated.layout.mainRect(style: .bar), updated.layout.cellFrames[1])
    XCTAssertEqual(opening.layout.mainRect(style: .bar), opening.layout.cellFrames[0])
    let distant = try XCTUnwrap(old.append(fields: 32..<64))
    XCTAssertNil(distant.layout.mainRect(style: .bar))
  }

  func testInitialReuseRejectsInputEvenAfterDeletionAndAnotherAttempt() {
    let first = TypingSession(configuration: .words(4), prompt: "oak ash elm pine")
    XCTAssertTrue(first.canReuseViewportSource(first))
    var changed = first
    let start = Date(timeIntervalSinceReferenceDate: 920_500_000)
    changed.insert("x", at: start)
    XCTAssertFalse(changed.canReuseViewportSource(first))
    changed.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertTrue(changed.typed.isEmpty)
    XCTAssertFalse(changed.canReuseViewportSource(first))
    XCTAssertFalse(first.canReuseViewportSource(changed))
    let another = TypingSession(configuration: .words(4), prompt: first.prompt)
    XCTAssertFalse(another.canReuseViewportSource(first))
  }

  func testStartedReuseRejectsAcceptedInputStoppedInputRulesAndTerminalState() {
    let start = Date(timeIntervalSinceReferenceDate: 920_500_000)
    var session = TypingSession(configuration: .words(3), prompt: "oak ash elm")
    session.insert("o", at: start)
    XCTAssertTrue(session.canReuseViewportSource(session))
    var next = session
    next.insert("a", at: start.addingTimeInterval(1))
    XCTAssertFalse(next.canReuseViewportSource(session))
    XCTAssertFalse(session.canReuseViewportSource(next))
    next = session
    next.bailOut(at: start.addingTimeInterval(2))
    XCTAssertFalse(next.canReuseViewportSource(session))
    next = session
    var rules = next.configuration.rules
    rules.blindMode = true
    next.synchronizeLiveInputRules(rules)
    XCTAssertFalse(next.canReuseViewportSource(session))

    var stopped = TypingSession(configuration: .words(3,
      rules: .init(stopOnErrorMode: .letter)), prompt: session.prompt)
    stopped.insertBatch("o", at: start)
    let before = stopped
    stopped.insertBatch("x", at: start.addingTimeInterval(1))
    XCTAssertEqual(stopped.typed, before.typed)
    XCTAssertNotEqual(stopped.promptGlyphs, before.promptGlyphs)
    XCTAssertFalse(stopped.canReuseViewportSource(before))
    XCTAssertFalse(before.canReuseViewportSource(stopped))
  }

  func testUnrelatedParentRefreshPreservesFullyMeasuredPrefixAndReadiness() throws {
    try assertUnrelatedRefreshPreservesMeasurement(started: false)
  }

  func testStartedUnrelatedParentRefreshPreservesFullyMeasuredPrefixAndReadiness() throws {
    try assertUnrelatedRefreshPreservesMeasurement(started: true)
  }

  func testPaceDeliveryInvalidatesUnchangedAcceptedText() throws {
    let clock = PaceCaretTestClock()
    let start = Date(timeIntervalSinceReferenceDate: 920_500_000)
    clock.set(at: start)
    var session = TypingSession(configuration: .words(3), prompt: "oak ash elm")
    session.configurePace(wpm: 60, clock: clock.source)
    session.insert("o", at: start)
    let previous = session
    let ticket = try XCTUnwrap(session.paceCaretPendingTicket)
    let delay = try XCTUnwrap(session.paceCaretPendingDelay)
    clock.set(at: start.addingTimeInterval(delay + 0.01))
    XCTAssertTrue(session.deliverPaceCaretTimer(ticket))
    XCTAssertEqual(session.typed, previous.typed)
    XCTAssertNotEqual(session.paceCaretFrame(), previous.paceCaretFrame())
    XCTAssertFalse(session.canReuseViewportSource(previous))
  }

  private func assertUnrelatedRefreshPreservesMeasurement(started: Bool) throws {
    let count = 257
    var session = TypingSession(configuration: .words(count),
      prompt: Array(repeating: "oak", count: count).joined(separator: " "))
    if started { session.insert("o", at: Date(timeIntervalSinceReferenceDate: 920_500_000)) }
    let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
    let style = PromptRenderStyle(theme: .init(background: .white, panel: .white,
      accent: .blue, colorScheme: .light), fontSize: 28)
    let coordinator = PromptCaretMotionCoordinator()
    func root(_ refresh: Int) -> some View {
      VStack {
        ScrollView {
          PromptViewportPracticePrompt(session: session, style: style, font: font,
            carets: .init(text: AttributedString(session.prompt), mainOffset: nil, paceOffset: nil,
              mainStyle: .off, paceStyle: .off, font: font, lineSpacing: 12,
              rightToLeft: false, accent: .blue, motion: .off, reducesMotion: true,
              frameRate: 60, attemptID: session.automaticInputAttemptID, coordinator: coordinator),
            onFailure: { _ in XCTFail("Unchanged source should remain admitted") })
            .frame(width: 800)
        }.frame(width: 800, height: 300)
        Text("Refresh \(refresh)")
      }.frame(width: 800, height: 330)
    }
    let host = NSHostingView(rootView: AnyView(root(0)))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 800, height: 330),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { host.rootView = AnyView(EmptyView()); window.contentView = nil; window.close() }
    func native(in view: NSView) -> PromptViewportPracticeNativeView? {
      (view as? PromptViewportPracticeNativeView) ?? view.subviews.lazy.compactMap { native(in: $0) }.first
    }
    let deadline = Date().addingTimeInterval(10)
    while native(in: host)?.viewport.canvas.hasCompleteHeight != true && Date() < deadline {
      host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    let original = try XCTUnwrap(native(in: host))
    XCTAssertTrue(original.viewport.canvas.hasCompleteHeight)
    XCTAssertEqual(original.viewport.measuredFieldCount, count)
    let caret = try XCTUnwrap(original.viewport.canvas.measuredMainCaretRect(style: .bar))
    XCTAssertEqual(caret, original.viewport.canvas.measuredRect(for: started ? 1 : 0))
    let pendingInk = try XCTUnwrap(original.viewport.canvas.renderedCellText(for: started ? 1 : 0))
    for refresh in 1...3 {
      host.rootView = AnyView(root(refresh))
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.005))
      let current = try XCTUnwrap(native(in: host))
      XCTAssertTrue(current === original)
      XCTAssertEqual(current.viewport.measuredFieldCount, count,
        "An unchanged source must not lose completed measurement")
      XCTAssertTrue(current.viewport.canvas.hasCompleteHeight,
        "A label-only parent refresh must not retire readiness")
      XCTAssertEqual(current.viewport.canvas.measuredMainCaretRect(style: .bar), caret)
      XCTAssertEqual(current.viewport.canvas.renderedCellText(for: started ? 1 : 0), pendingInk)
      XCTAssertEqual(current.viewport.canvas.accessibilityValue() as? String, session.prompt)
    }
    session.insert(started ? "a" : "o", at: Date(timeIntervalSinceReferenceDate: 920_500_001))
    host.rootView = AnyView(root(4))
    host.layoutSubtreeIfNeeded()
    XCTAssertTrue(original.viewport.canvas.hasCompleteHeight,
      "Color-only input must retain the exact complete page height")
    XCTAssertEqual(original.viewport.measuredFieldCount, count)
    XCTAssertEqual(original.viewport.canvas.measuredMainCaretRect(style: .bar),
      original.viewport.canvas.measuredRect(for: started ? 2 : 1),
      "Actual input must publish a new caret rather than reuse old ink")
    XCTAssertNotEqual(original.viewport.canvas.measuredMainCaretRect(style: .bar), caret)
    XCTAssertNotEqual(original.viewport.canvas.renderedCellText(for: started ? 1 : 0), pendingInk)
    XCTAssertFalse(window.isVisible)
  }
}
