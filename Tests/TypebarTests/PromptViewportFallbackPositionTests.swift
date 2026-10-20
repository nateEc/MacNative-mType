import AppKit
import XCTest
@testable import Typebar

@MainActor final class PromptViewportFallbackPositionTests: XCTestCase {
  private final class Document: NSView { override var isFlipped: Bool { true } }

  private func fixture() -> (NSScrollView, NSView, NSView) {
    _ = NSApplication.shared
    let page = NSScrollView(frame: .init(x: 0, y: 0, width: 180, height: 100))
    let document = Document(frame: .init(x: 0, y: 0, width: 180, height: 1_000))
    let view = Document(frame: document.bounds)
    document.addSubview(view)
    page.documentView = document
    return (page, document, view)
  }

  private var position: PromptViewportNativeScrollHost.ReadingPosition {
    .init(attemptID: UUID(), promptTargetID: UUID(), character: 730,
      rowFraction: 0.25, selection: .init(location: NSNotFound, length: 0))
  }

  private func restore(_ handoff: PromptViewportFallbackPosition, _ position: PromptViewportNativeScrollHost.ReadingPosition,
    in view: NSView, targetID: UUID? = nil, attemptID: UUID? = nil) {
    handoff.restore(in: view, attemptID: attemptID ?? position.attemptID,
      targetID: targetID ?? position.promptTargetID) { character in
      XCTAssertEqual(character, position.character)
      return .init(x: 0, y: 400, width: 10, height: 40)
    }
  }

  func testWaitsForDocumentAdoptionThenRestoresExactlyOnce() {
    let (page, document, view) = fixture()
    let position = position
    let handoff = PromptViewportFallbackPosition()
    document.frame.size.height = 100
    handoff.capture(position, in: page)
    restore(handoff, position, in: view)
    XCTAssertEqual(page.contentView.bounds.minY, 0)
    document.frame.size.height = 1_000
    restore(handoff, position, in: view)
    XCTAssertEqual(page.contentView.bounds.minY, 410)
    page.contentView.scroll(to: .zero)
    restore(handoff, position, in: view)
    XCTAssertEqual(page.contentView.bounds.minY, 0, "Consumed anchors cannot override later browsing")
  }

  func testWrongAttemptOrTargetInvalidatesOldAnchor() {
    for wrongAttempt in [true, false] {
      let (page, _, view) = fixture()
      let position = position
      let handoff = PromptViewportFallbackPosition()
      handoff.capture(position, in: page)
      restore(handoff, position, in: view, targetID: wrongAttempt ? nil : UUID(),
        attemptID: wrongAttempt ? UUID() : nil)
      restore(handoff, position, in: view)
      XCTAssertEqual(page.contentView.bounds.minY, 0)
    }
  }

  func testNewPageNavigationSupersedesPendingAnchor() {
    let (page, _, view) = fixture()
    let position = position
    let handoff = PromptViewportFallbackPosition()
    handoff.capture(position, in: page)
    page.contentView.scroll(to: .init(x: 0, y: 100))
    NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: page.contentView)
    restore(handoff, position, in: view)
    XCTAssertEqual(page.contentView.bounds.minY, 100)
  }

  func testDifferentPageCannotConsumeTheAnchor() {
    let (page, _, view) = fixture()
    let (otherPage, _, otherView) = fixture()
    defer { withExtendedLifetime(otherPage) {} }
    let position = position
    let handoff = PromptViewportFallbackPosition()
    handoff.capture(position, in: page)
    restore(handoff, position, in: otherView)
    restore(handoff, position, in: view)
    XCTAssertEqual(page.contentView.bounds.minY, 0)
  }
}
