import AppKit
import XCTest
@testable import Typebar

@MainActor final class PromptViewportPageLifecycleTests: XCTestCase {
  private final class PageDocument: NSView { override var isFlipped: Bool { true } }
  private final class RecordingPage: NSScrollView {
    var received: [NSEvent] = []
    override func scrollWheel(with event: NSEvent) { received.append(event) }
  }
  private let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
  private let style = PromptRenderStyle(theme: .init(background: .white, panel: .white,
    accent: .blue, colorScheme: .light))

  private func sequence() throws -> PromptViewportFieldLayoutSequence {
    let session = TypingSession(configuration: .words(201),
      prompt: (0..<201).map { "word\($0)" }.joined(separator: " "))
    return try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: XCTUnwrap(PromptViewportTargetDirectory(session: session)),
      style: style, width: 180, font: font))
  }

  func testStopCancelsQueuedWholePageMeasurementDespiteAncestorNotifications() async throws {
    let page = NSScrollView(frame: .init(x: 0, y: 0, width: 200, height: 100))
    let document = PageDocument(frame: .init(x: 0, y: 0, width: 180, height: 1000))
    page.documentView = document
    let host = PromptViewportNativeScrollHost(pageScrolling: true)
    host.frame = .init(x: 0, y: 0, width: 180, height: 1)
    document.addSubview(host)
    host.refreshPageVisibility()
    let layout = try sequence()
    var callbacks = 0
    host.onMeasuredHeightChange = { _ in callbacks += 1 }
    host.onPreparationFailure = { _ in XCTFail("A stopped page must not deliver preparation failures") }
    XCTAssertTrue(host.configure(sequence: layout, batchSize: 2))
    XCTAssertTrue(host.isPreparing)
    host.stop()
    document.frame.size.height += 50
    NotificationCenter.default.post(name: NSView.frameDidChangeNotification, object: document)
    page.contentView.scroll(to: .init(x: 0, y: 20))
    NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: page.contentView)
    for _ in 0..<10 { await Task.yield() }
    XCTAssertEqual(layout.nextField, 0, "The cancelled task must not measure even its first queued batch")
    XCTAssertEqual(callbacks, 0)
    XCTAssertFalse(host.isPreparing)
    XCTAssertEqual(host.canvas.accessibilityNumberOfCharacters(), 0)
    host.removeFromSuperview()
  }

  func testRemovedPageOwnerReleasesWhileObservedAncestorsStayAlive() async throws {
    let page = NSScrollView(frame: .init(x: 0, y: 0, width: 200, height: 100))
    let document = PageDocument(frame: .init(x: 0, y: 0, width: 180, height: 1000))
    page.documentView = document
    weak var released: PromptViewportNativeScrollHost?
    do {
      let host = PromptViewportNativeScrollHost(pageScrolling: true)
      released = host
      host.frame = .init(x: 0, y: 0, width: 180, height: 1)
      document.addSubview(host)
      host.refreshPageVisibility()
      XCTAssertTrue(host.configure(sequence: try sequence(), batchSize: 2))
      host.stop()
      host.removeFromSuperview()
    }
    for _ in 0..<10 { await Task.yield() }
    XCTAssertNil(released, "Notifications and cancelled preparation must not retain a retired page owner")
    document.frame.size.height += 50
    NotificationCenter.default.post(name: NSView.frameDidChangeNotification, object: document)
    NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: page.contentView)
    XCTAssertTrue(page.documentView === document)
  }

  func testWheelAtPageBoundaryStillReportsANewerNavigationIntent() throws {
    let page = NSScrollView(frame: .init(x: 0, y: 0, width: 200, height: 100))
    let document = PageDocument(frame: .init(x: 0, y: 0, width: 180, height: 1000))
    page.documentView = document
    let host = PromptViewportNativeScrollHost(pageScrolling: true)
    host.frame = .init(x: 0, y: 0, width: 180, height: 100)
    document.addSubview(host)
    host.refreshPageVisibility()
    defer { host.stop(); host.removeFromSuperview() }
    var intents = 0
    host.onExternalNavigation = { intents += 1 }
    let up = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line,
      wheelCount: 1, wheel1: 8, wheel2: 0, wheel3: 0))
    host.scrollView.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: up)))
    XCTAssertEqual(page.contentView.bounds.minY, 0)
    XCTAssertGreaterThan(intents, 0, "A boundary wheel gesture must supersede a pending old reading anchor")
  }

  func testPageWheelRoutesToOuterOwnerEvenWhileInnerGeometryCanScroll() throws {
    for pageScrolling in [true, false] {
      let page = RecordingPage(frame: .init(x: 0, y: 0, width: 220, height: 120))
      let document = PageDocument(frame: .init(x: 0, y: 0, width: 200, height: 2000))
      page.documentView = document
      let host = PromptViewportNativeScrollHost(pageScrolling: pageScrolling)
      host.frame = .init(x: 0, y: 0, width: 180, height: 100)
      document.addSubview(host)
      // Measurement and parent layout are asynchronous. During that interval,
      // the inner clip can be smaller than its canvas, even in page mode.
      host.canvas.frame = .init(x: 0, y: 0, width: 180, height: 1000)
      host.scrollView.tile()
      defer { host.stop(); host.removeFromSuperview() }
      var intents = 0
      host.onExternalNavigation = { intents += 1 }
      for delta: Int32 in [-8, 8] {
        let cgEvent = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line,
          wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0))
        let event = try XCTUnwrap(NSEvent(cgEvent: cgEvent))
        let before = page.received.count
        host.scrollView.scrollWheel(with: event)
        XCTAssertEqual(page.received.count - before, pageScrolling ? 1 : 0)
        if pageScrolling {
          XCTAssertTrue(page.received.last === event, "Forward the original event without rebuilding its phases or deltas")
          XCTAssertEqual(host.scrollView.contentView.bounds.minY, 0)
        }
      }
      XCTAssertEqual(intents, pageScrolling ? 2 : 0)
    }
  }
}
