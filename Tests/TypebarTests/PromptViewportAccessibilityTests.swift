import AppKit
import XCTest
@testable import Typebar

@MainActor final class PromptViewportAccessibilityTests: XCTestCase {
  private let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
  private let style = PromptRenderStyle(theme: .init(background: .white, panel: .white,
    accent: .blue, colorScheme: .light))

  private func makeHost(frame: NSRect) -> PromptViewportNativeScrollHost {
    _ = NSApplication.shared
    _ = NSScroller.preferredScrollerStyle
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    let host = PromptViewportNativeScrollHost()
    host.scrollView.scrollerStyle = .overlay
    host.frame = frame
    host.scrollView.tile()
    return host
  }

  private func waitUntil(_ predicate: () -> Bool) async throws {
    for _ in 0..<200 {
      if predicate() { return }
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("Accessibility viewport did not reach its target")
  }

  private func sequence(_ session: TypingSession, width: CGFloat = 180) throws -> PromptViewportFieldLayoutSequence {
    try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: XCTUnwrap(PromptViewportTargetDirectory(session: session)),
      style: style, width: width, font: font))
  }

  func testUnmeasuredRangeReportsFullTextAndExactScreenFrameThenSelectionRevealsIt() async throws {
    let prompt = (0..<60).map { "word\($0)" }.joined(separator: " ")
    let session = TypingSession(configuration: .words(60), prompt: prompt)
    let layout = try sequence(session)
    let host = makeHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
    let window = NSWindow(contentRect: .init(x: 180, y: 220, width: 180, height: 100),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { host.stop(); window.contentView = nil; window.close() }
    XCTAssertTrue(host.configure(sequence: layout, batchSize: 2))
    try await waitUntil { layout.nextField > 2 && !host.isPreparing }
    let initialCount = layout.nextField
    let target = NSRange(location: (0..<35).reduce(0) { $0 + "word\($1) ".utf16.count }, length: 4)
    XCTAssertEqual(host.canvas.accessibilityNumberOfCharacters(), prompt.utf16.count)
    XCTAssertEqual(host.canvas.accessibilityString(for: target), "word")
    XCTAssertEqual(host.canvas.accessibilityRange(for: target.location), .init(location: target.location, length: 1))
    XCTAssertEqual(layout.nextField, initialCount, "Reading source text must not materialize geometry")
    let fullMap = try XCTUnwrap(PromptRenderPlan(session: session, composition: "", style: style).render().compositionTextMap)
    let full = PromptFieldTextLayout(map: fullMap, width: 180, font: font)
    let frame = (target.location..<NSMaxRange(target)).compactMap { full.cellFrames[$0] }
      .reduce(CGRect.null) { $0.union($1) }
    let expected = window.convertToScreen(host.canvas.convert(frame, to: nil))
    XCTAssertEqual(host.canvas.accessibilityFrame(for: target), expected)
    XCTAssertEqual(host.scrollView.contentView.bounds.minY, 0, "A geometry query must not navigate")
    XCTAssertGreaterThan(layout.nextField, 35)
    XCTAssertLessThan(layout.nextField, layout.fieldCount)
    XCTAssertTrue(host.canvas.isAccessibilitySelectorAllowed(#selector(NSAccessibilityProtocol.setAccessibilitySelectedTextRange(_:))))
    host.canvas.setAccessibilitySelectedTextRange(target)
    try await waitUntil { NSLocationInRange(target.location, host.canvas.accessibilityVisibleCharacterRange()) }
    XCTAssertEqual(host.canvas.accessibilitySelectedTextRange(), target)
    XCTAssertEqual(host.canvas.accessibilitySelectedText(), "word")
    let visibleFrame = host.canvas.accessibilityFrame(for: target)
    XCTAssertTrue(window.convertToScreen(host.scrollView.convert(host.scrollView.bounds, to: nil)).intersects(visibleFrame))
    XCTAssertEqual(host.canvas.accessibilityRange(for: NSPoint(x: visibleFrame.minX + 1, y: visibleFrame.midY)),
      .init(location: target.location, length: 1))
    let selectedOrigin = host.scrollView.contentView.bounds.minY
    let future = NSRange(location: (0..<50).reduce(0) { $0 + "word\($1) ".utf16.count }, length: 3)
    XCTAssertNotEqual(host.canvas.accessibilityFrame(for: future), .zero)
    XCTAssertEqual(host.scrollView.contentView.bounds.minY, selectedOrigin)
    XCTAssertEqual(host.canvas.accessibilitySelectedTextRange(), target)
    XCTAssertTrue(session.typed.isEmpty)
    XCTAssertFalse(window.isVisible)
  }

  func testLineQueriesMatchCompleteLayoutAcrossBatchBoundariesAndReturns() async throws {
    for prompt in ["one two three four five six seven eight nine", "a\n\nb cd verylongfield tail\n"] {
      for width: CGFloat in [65, 180] {
        let session = TypingSession(configuration: .words(12), prompt: prompt)
        let layout = try sequence(session, width: width)
        let host = makeHost(frame: .init(x: 0, y: 0, width: width, height: 60))
        defer { host.stop() }
        XCTAssertTrue(host.configure(sequence: layout, batchSize: 2))
        try await waitUntil { layout.nextField > 0 && !host.isPreparing }
        let map = try XCTUnwrap(PromptRenderPlan(session: session, composition: "", style: style).render().compositionTextMap)
        let full = PromptFieldTextLayout(map: map, width: width, font: font)
        let rows = Dictionary(grouping: full.cellFrames.keys) { full.cellFrames[$0]!.minY }
          .sorted { $0.key < $1.key }.map { $0.value.sorted() }
        for (line, ids) in rows.enumerated() {
          let expected = NSRange(location: try XCTUnwrap(ids.first), length: ids.count)
          XCTAssertEqual(host.canvas.accessibilityRange(forLine: line), expected)
          for id in ids { XCTAssertEqual(host.canvas.accessibilityLine(for: id), line) }
          XCTAssertEqual(host.canvas.accessibilityString(for: expected), (prompt as NSString).substring(with: expected))
        }
        XCTAssertEqual(host.canvas.accessibilityRange(forLine: rows.count), .init(location: NSNotFound, length: 0))
      }
    }
  }

  func testInvalidQueriesAndRetiredSnapshotCannotReuseOldSelectionOrGeometry() async throws {
    let session = TypingSession(configuration: .words(20), prompt: Array(repeating: "oak", count: 20).joined(separator: " "))
    let layout = try sequence(session)
    let host = makeHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
    defer { host.stop() }
    XCTAssertTrue(host.configure(sequence: layout, batchSize: 2))
    try await waitUntil { layout.nextField > 0 && !host.isPreparing }
    let before = layout.nextField
    for range in [NSRange(location: NSNotFound, length: 1), .init(location: -1, length: 1),
      .init(location: 0, length: Int.max), .init(location: Int.max, length: Int.max)] {
      XCTAssertNil(host.canvas.accessibilityString(for: range))
      XCTAssertEqual(host.canvas.accessibilityFrame(for: range), .zero)
      host.canvas.setAccessibilitySelectedTextRange(range)
    }
    XCTAssertEqual(layout.nextField, before)
    XCTAssertEqual(host.canvas.accessibilitySelectedTextRange(), .init(location: NSNotFound, length: 0))
    host.canvas.setAccessibilitySelectedTextRange(.init(location: 0, length: 3))
    XCTAssertEqual(host.canvas.accessibilitySelectedText(), "oak")
    host.stop()
    XCTAssertEqual(host.canvas.accessibilityNumberOfCharacters(), 0)
    XCTAssertNil(host.canvas.accessibilityString(for: .init(location: 0, length: 1)))
    XCTAssertEqual(host.canvas.accessibilitySelectedTextRange(), .init(location: NSNotFound, length: 0))
  }

  func testSelectionInsideWrappedFieldKeepsItsRowAcrossInputAndClearsOnRestart() async throws {
    let sessionPrompt = String(repeating: "a", count: 120) + " tail final"
    var session = TypingSession(configuration: .words(3), prompt: sessionPrompt)
    let layout = try sequence(session, width: 65)
    let host = makeHost(frame: .init(x: 0, y: 0, width: 65, height: 60))
    let window = NSWindow(contentRect: .init(x: 100, y: 100, width: 65, height: 60),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { host.stop(); window.contentView = nil; window.close() }
    XCTAssertTrue(host.configure(sequence: layout, batchSize: 1))
    try await waitUntil { !host.isPreparing && layout.nextField > 0 }
    let selected = NSRange(location: 90, length: 2)
    host.canvas.setAccessibilitySelectedTextRange(selected)
    XCTAssertTrue(NSLocationInRange(selected.location, host.canvas.accessibilityVisibleCharacterRange()))
    let before = host.scrollView.contentView.bounds.minY
    XCTAssertGreaterThan(before, 0)
    session.insert("a", at: Date(timeIntervalSinceReferenceDate: 916_200_000))
    XCTAssertTrue(host.replaceVisibleSession(session, style: style))
    XCTAssertEqual(host.canvas.accessibilitySelectedTextRange(), selected)
    XCTAssertEqual(host.canvas.accessibilitySelectedText(), "aa")
    XCTAssertEqual(host.scrollView.contentView.bounds.minY, before)
    XCTAssertTrue(host.configure(sequence: try sequence(session.repeatedAttempt(), width: 65), batchSize: 1))
    try await waitUntil { !host.isPreparing }
    XCTAssertEqual(host.canvas.accessibilitySelectedTextRange(), .init(location: NSNotFound, length: 0))
  }

  func testZeroLengthEndAfterReturnUsesNextLogicalRow() async throws {
    for prompt in ["one", "one\n", "\n\n"] {
      let session = TypingSession(configuration: .words(3), prompt: prompt)
      let layout = try sequence(session)
      let host = makeHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
      let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = host
      defer { host.stop(); window.contentView = nil; window.close() }
      XCTAssertTrue(host.configure(sequence: layout, batchSize: 1))
      try await waitUntil { !host.isPreparing && layout.nextField > 0 }
      let map = try XCTUnwrap(PromptRenderPlan(session: session, composition: "", style: style).render().compositionTextMap)
      let full = PromptFieldTextLayout(map: map, width: 180, font: font)
      let last = try XCTUnwrap(full.cellFrames[prompt.utf16.count - 1])
      let expected = NSRect(x: prompt.hasSuffix("\n") ? 0 : last.maxX,
        y: prompt.hasSuffix("\n") ? full.size.height : last.minY, width: 0, height: last.height)
      XCTAssertEqual(host.canvas.accessibilityFrame(for: .init(location: prompt.utf16.count, length: 0)),
        window.convertToScreen(host.canvas.convert(expected, to: nil)))
    }
  }

  func testHundredThousandWordTextReadAvoidsGeometryAndFrameMeasuresOnlyRequiredPrefix() async throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["TYPEBAR_ENDURANCE_TESTS"] == "1",
      "Run explicitly with TYPEBAR_ENDURANCE_TESTS=1")
    let count = 100_001
    let session = TypingSession(configuration: .words(count), prompt: Array(repeating: "oak", count: count).joined(separator: " "))
    let layout = try sequence(session)
    let host = makeHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
    let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { host.stop(); window.contentView = nil; window.close() }
    XCTAssertTrue(host.configure(sequence: layout, batchSize: 32))
    try await waitUntil { layout.nextField == 32 && !host.isPreparing }
    XCTAssertEqual(host.canvas.accessibilityString(for: .init(location: count * 4 - 5, length: 4)), " oak")
    XCTAssertEqual(layout.nextField, 32)
    XCTAssertNotEqual(host.canvas.accessibilityFrame(for: .init(location: 40 * 4, length: 3)), .zero)
    XCTAssertEqual(layout.nextField, 64)
    XCTAssertLessThan(host.retainedWindowCount, layout.measuredSpans.count)
    XCTAssertFalse(host.canvas.hasCompleteHeight)
  }
}
