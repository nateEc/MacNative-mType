import AppKit
import XCTest
@testable import Typebar

@MainActor final class PromptViewportNativeScrollHostTests: XCTestCase {
  private let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
  private let style = PromptRenderStyle(theme: .init(background: .white, panel: .white,
    accent: .blue, colorScheme: .light))

  private func waitUntil(_ predicate: () -> Bool) async throws {
    for _ in 0..<200 {
      if predicate() { return }
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("Viewport did not reach the expected state")
  }

  func testNativeScrollerDemandsMoreAtMeasuredEndAndRevisitsEvictedTop() async throws {
    let prompt = (0..<80).map { "word\($0)" }.joined(separator: " ")
    let session = TypingSession(configuration: .words(80), prompt: prompt)
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    let sequence = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: directory, style: style, width: 180, font: font))
    let host = PromptViewportNativeScrollHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
    let window = NSWindow(contentRect: host.frame, styleMask: .borderless,
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { host.stop(); window.contentView = nil; window.close() }
    XCTAssertTrue(host.configure(sequence: sequence, batchSize: 2))
    try await waitUntil { sequence.nextField > 2 && !host.isPreparing }
    let firstStop = sequence.nextField
    XCTAssertLessThan(firstStop, directory.fieldCount, "Initial view must not prepare the whole page")
    XCTAssertFalse(host.canvas.hasCompleteHeight)
    XCTAssertNotNil(host.canvas.measuredRect(for: 0))
    XCTAssertEqual(host.canvas.accessibilityValue() as? String, prompt)
    host.scrollToMeasuredEnd()
    try await waitUntil { sequence.nextField > firstStop && !host.isPreparing }
    XCTAssertNil(host.canvas.measuredRect(for: 0), "Top drawing window should be evicted")
    host.scrollToTop()
    try await waitUntil { host.canvas.measuredRect(for: 0) != nil }
    XCTAssertEqual(host.canvas.accessibilityValue() as? String, prompt)
    XCTAssertFalse(window.isVisible)
  }

  func testWidthChangeRetiresOldMeasuredCanvas() async throws {
    let session = TypingSession(configuration: .words(4), prompt: "one two three four")
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    let sequence = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: directory, style: style, width: 180, font: font))
    let host = PromptViewportNativeScrollHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
    defer { host.stop() }
    XCTAssertTrue(host.configure(sequence: sequence, batchSize: 2))
    try await waitUntil { sequence.nextField > 0 }
    host.frame.size.width = 160
    host.layoutSubtreeIfNeeded()
    XCTAssertNil(host.canvas.measuredRect(for: 0))
    XCTAssertFalse(host.isPreparing)
  }

  func testBoundsWidthChangeAlsoRetiresOldMeasuredCanvas() async throws {
    let session = TypingSession(configuration: .words(4), prompt: "one two three four")
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    let sequence = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: directory, style: style, width: 180, font: font))
    let host = PromptViewportNativeScrollHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
    defer { host.stop() }
    XCTAssertTrue(host.configure(sequence: sequence, batchSize: 2))
    try await waitUntil { sequence.nextField > 0 }
    host.bounds.size.width = 160
    host.layoutSubtreeIfNeeded()
    XCTAssertNil(host.canvas.measuredRect(for: 0))
    XCTAssertFalse(host.isPreparing)
  }

  func testRepeatedScrollToEndReachesExactFullLayoutHeight() async throws {
    let prompt = (0..<40).map { "word\($0)" }.joined(separator: " ")
    let session = TypingSession(configuration: .words(40), prompt: prompt)
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    let sequence = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: directory, style: style, width: 180, font: font))
    let fullMap = try XCTUnwrap(PromptRenderPlan(session: session,
      composition: "", style: style).render().compositionTextMap)
    let full = PromptFieldTextLayout(map: fullMap, width: 180, font: font)
    let host = PromptViewportNativeScrollHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
    defer { host.stop() }
    XCTAssertTrue(host.configure(sequence: sequence, batchSize: 2))
    try await waitUntil { sequence.nextField > 0 && !host.isPreparing }
    for _ in 0..<40 where sequence.nextField < sequence.fieldCount {
      let before = sequence.nextField
      host.scrollToMeasuredEnd()
      try await waitUntil { sequence.nextField > before && !host.isPreparing }
    }
    XCTAssertEqual(sequence.nextField, sequence.fieldCount)
    XCTAssertTrue(host.canvas.hasCompleteHeight)
    XCTAssertEqual(host.canvas.intrinsicContentSize.height, full.size.height)
    host.scrollToMeasuredEnd()
    XCTAssertLessThan(host.retainedWindowCount, sequence.measuredSpans.count,
      "The scrolling host must not retain every drawable layout")
    XCTAssertEqual(host.canvas.measuredRect(for: prompt.utf16.count - 1),
      full.cellFrames[prompt.utf16.count - 1])
  }

  func testHundredThousandWordNativeScrollerStopsAfterInitialVisibleDemand() async throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["TYPEBAR_ENDURANCE_TESTS"] == "1",
      "Run explicitly with TYPEBAR_ENDURANCE_TESTS=1")
    let count = 100_001
    let prompt = Array(repeating: "oak", count: count).joined(separator: " ")
    let session = TypingSession(configuration: .words(count), prompt: prompt)
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    let sequence = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: directory, style: style, width: 180, font: font))
    let host = PromptViewportNativeScrollHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
    defer { host.stop() }
    XCTAssertTrue(host.configure(sequence: sequence, batchSize: 32))
    try await waitUntil { sequence.nextField > 0 && !host.isPreparing }
    XCTAssertEqual(sequence.nextField, 32)
    XCTAssertLessThan(sequence.nextField, directory.fieldCount)
    XCTAssertFalse(host.canvas.hasCompleteHeight)
    XCTAssertEqual(host.canvas.accessibilityValue() as? String, prompt)
  }

  func testConfiguringAlreadyMeasuredSequenceShowsTopWithoutNewDemand() throws {
    let prompt = (0..<30).map { "word\($0)" }.joined(separator: " ")
    let session = TypingSession(configuration: .words(30), prompt: prompt)
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    let sequence = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: directory, style: style, width: 180, font: font))
    _ = try XCTUnwrap(sequence.append(fields: 0..<20))
    let host = PromptViewportNativeScrollHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
    defer { host.stop() }
    XCTAssertTrue(host.configure(sequence: sequence, batchSize: 2))
    XCTAssertNotNil(host.canvas.measuredRect(for: 0))
    XCTAssertEqual(sequence.nextField, 20)
    XCTAssertFalse(host.isPreparing)
  }
}
