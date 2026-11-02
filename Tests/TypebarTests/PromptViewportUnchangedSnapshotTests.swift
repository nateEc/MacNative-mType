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
    XCTAssertTrue(first.canReuseUnstartedViewportSource(first))
    var changed = first
    let start = Date(timeIntervalSinceReferenceDate: 920_500_000)
    changed.insert("x", at: start)
    XCTAssertFalse(changed.canReuseUnstartedViewportSource(first))
    changed.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertTrue(changed.typed.isEmpty)
    XCTAssertFalse(changed.canReuseUnstartedViewportSource(first))
    XCTAssertFalse(first.canReuseUnstartedViewportSource(changed))
    let another = TypingSession(configuration: .words(4), prompt: first.prompt)
    XCTAssertFalse(another.canReuseUnstartedViewportSource(first))
  }

  func testUnrelatedParentRefreshPreservesFullyMeasuredPrefixAndReadiness() throws {
    let count = 257
    let session = TypingSession(configuration: .words(count),
      prompt: Array(repeating: "oak", count: count).joined(separator: " "))
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
    }
    XCTAssertFalse(window.isVisible)
  }
}
