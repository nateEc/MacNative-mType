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

  private func caretConfig(_ session: TypingSession,
    motion: PromptCaretMotionCoordinator) -> PromptCaretNativeView.Configuration {
    var configuration = PromptCaretNativeView.Configuration(text: AttributedString(),
      mainOffset: nil, paceOffset: nil, mainStyle: .bar, paceStyle: .off,
      font: font, lineSpacing: 12, rightToLeft: false, accent: .blue,
      motion: .off, reducesMotion: true, frameRate: 30,
      attemptID: session.automaticInputAttemptID, coordinator: motion,
      automaticallyPresents: false)
    configuration.mainGlyphID = session.promptCaretGlyphIndex
    return configuration
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

  func testScrollToUnmeasuredFieldPreparesThroughTargetAndShowsItsGlyph() async throws {
    let prompt = (0..<40).map { "word\($0)" }.joined(separator: " ")
    let session = TypingSession(configuration: .words(40), prompt: prompt)
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    let sequence = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: directory, style: style, width: 180, font: font))
    let host = PromptViewportNativeScrollHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
    defer { host.stop() }
    XCTAssertTrue(host.configure(sequence: sequence, batchSize: 2))
    try await waitUntil { sequence.nextField > 2 && !host.isPreparing }
    XCTAssertFalse(host.scrollToField(-1))
    XCTAssertFalse(host.scrollToField(directory.fieldCount))
    XCTAssertTrue(host.scrollToField(25))
    try await waitUntil { host.canvas.measuredRect(for: (0..<25).reduce(0) { $0 + "word\($1) ".utf16.count }) != nil
      && !host.isPreparing }
    let targetID = (0..<25).reduce(0) { $0 + "word\($1) ".utf16.count }
    let rect = try XCTUnwrap(host.canvas.measuredRect(for: targetID))
    XCTAssertTrue(host.scrollView.contentView.documentVisibleRect.intersects(rect))
    XCTAssertLessThan(sequence.nextField, sequence.fieldCount)
    XCTAssertFalse(host.canvas.hasCompleteHeight)
    XCTAssertLessThan(host.retainedWindowCount, sequence.measuredSpans.count)
  }

  func testNewAttemptCancelsPendingRemoteFieldScroll() async throws {
    let oldSession = TypingSession(configuration: .words(80),
      prompt: (0..<80).map { "old\($0)" }.joined(separator: " "))
    let oldDirectory = try XCTUnwrap(PromptViewportTargetDirectory(session: oldSession))
    let oldSequence = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: oldSession,
      directory: oldDirectory, style: style, width: 180, font: font))
    let host = PromptViewportNativeScrollHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
    defer { host.stop() }
    XCTAssertTrue(host.configure(sequence: oldSequence, batchSize: 2))
    try await waitUntil { oldSequence.nextField > 2 && !host.isPreparing }
    let oldMeasured = oldSequence.nextField
    XCTAssertTrue(host.scrollToField(70))
    let newSession = TypingSession(configuration: .words(3), prompt: "new round now")
    let newDirectory = try XCTUnwrap(PromptViewportTargetDirectory(session: newSession))
    let newSequence = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: newSession,
      directory: newDirectory, style: style, width: 180, font: font))
    XCTAssertTrue(host.configure(sequence: newSequence, batchSize: 2))
    try await waitUntil { !host.isPreparing }
    XCTAssertEqual(host.canvas.accessibilityValue() as? String, newSession.prompt)
    XCTAssertEqual(host.scrollView.contentView.bounds.minY, 0)
    XCTAssertEqual(oldSequence.nextField, oldMeasured)
  }

  func testManualTopScrollCancelsPendingDistantFieldRequest() async throws {
    let session = TypingSession(configuration: .words(80),
      prompt: (0..<80).map { "word\($0)" }.joined(separator: " "))
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    let sequence = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: directory, style: style, width: 180, font: font))
    let host = PromptViewportNativeScrollHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
    defer { host.stop() }
    XCTAssertTrue(host.configure(sequence: sequence, batchSize: 2))
    try await waitUntil { sequence.nextField > 2 && !host.isPreparing }
    XCTAssertTrue(host.scrollToField(70))
    host.scrollToTop()
    try await waitUntil { !host.isPreparing }
    XCTAssertLessThan(sequence.nextField, 70)
    XCTAssertEqual(host.scrollView.contentView.bounds.minY, 0)
    XCTAssertNotNil(host.canvas.measuredRect(for: 0))
  }

  func testClipScrollCancelsPendingDistantFieldRequest() async throws {
    let session = TypingSession(configuration: .words(80),
      prompt: (0..<80).map { "word\($0)" }.joined(separator: " "))
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    let sequence = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: directory, style: style, width: 180, font: font))
    let host = PromptViewportNativeScrollHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
    defer { host.stop() }
    XCTAssertTrue(host.configure(sequence: sequence, batchSize: 2))
    try await waitUntil { sequence.nextField > 2 && !host.isPreparing }
    XCTAssertTrue(host.scrollToField(70))
    host.scrollView.contentView.scroll(to: .init(x: 0, y: 20))
    host.scrollView.reflectScrolledClipView(host.scrollView.contentView)
    try await waitUntil { !host.isPreparing }
    XCTAssertLessThan(sequence.nextField, 70)
    XCTAssertLessThan(host.scrollView.contentView.bounds.minY, 100)
  }

  func testNewMeasuredFieldRequestSupersedesPendingDistantRequest() async throws {
    let session = TypingSession(configuration: .words(80),
      prompt: (0..<80).map { "word\($0)" }.joined(separator: " "))
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    let sequence = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: directory, style: style, width: 180, font: font))
    let host = PromptViewportNativeScrollHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
    defer { host.stop() }
    XCTAssertTrue(host.configure(sequence: sequence, batchSize: 2))
    try await waitUntil { sequence.nextField > 2 && !host.isPreparing }
    XCTAssertTrue(host.scrollToField(70))
    XCTAssertTrue(host.scrollToField(0))
    try await waitUntil { !host.isPreparing }
    XCTAssertLessThan(sequence.nextField, 70)
    XCTAssertEqual(host.scrollView.contentView.bounds.minY, 0)
    XCTAssertNotNil(host.canvas.measuredRect(for: 0))
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

  func testReplacingTopSessionAfterInputRepaintsFromCurrentState() async throws {
    var session = TypingSession(configuration: .words(8),
      prompt: "one two three four five six seven eight")
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    let sequence = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: directory, style: style, width: 180, font: font))
    let host = PromptViewportNativeScrollHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
    defer { host.stop() }
    XCTAssertTrue(host.configure(sequence: sequence, batchSize: 2))
    try await waitUntil { sequence.nextField > 0 && !host.isPreparing }
    let originalInk = try XCTUnwrap(host.canvas.renderedCellText(for: 0))
    session.insert("o", at: Date(timeIntervalSinceReferenceDate: 916_200_000))
    XCTAssertTrue(host.replaceVisibleSession(session, style: style))
    let currentInk = try XCTUnwrap(host.canvas.renderedCellText(for: 0))
    let complete = try XCTUnwrap(PromptRenderPlan(session: session,
      composition: "", style: style).render().compositionTextMap)
    XCTAssertEqual(currentInk, complete.fieldRuns.flatMap(\.cells).first?.text)
    XCTAssertNotEqual(currentInk, originalInk)
    XCTAssertEqual(host.canvas.accessibilityValue() as? String, session.prompt)
  }

  func testReplacingSessionRejectsNewAttemptWithoutPublishingOldInk() async throws {
    let session = TypingSession(configuration: .words(4), prompt: "one two three four")
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    let sequence = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: directory, style: style, width: 180, font: font))
    let host = PromptViewportNativeScrollHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
    defer { host.stop() }
    XCTAssertTrue(host.configure(sequence: sequence, batchSize: 2))
    try await waitUntil { sequence.nextField > 0 && !host.isPreparing }
    let originalInk = host.canvas.renderedCellText(for: 0)
    XCTAssertFalse(host.replaceVisibleSession(session.repeatedAttempt(), style: style))
    XCTAssertEqual(host.canvas.renderedCellText(for: 0), originalInk)
  }

  func testReplacingSessionRejectsFontMetricChangeUntilNewSequenceIsBuilt() async throws {
    let session = TypingSession(configuration: .words(4), prompt: "one two three four")
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    let sequence = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: directory, style: style, width: 180, font: font))
    let host = PromptViewportNativeScrollHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
    defer { host.stop() }
    XCTAssertTrue(host.configure(sequence: sequence, batchSize: 2))
    try await waitUntil { sequence.nextField > 0 && !host.isPreparing }
    var changedStyle = style
    changedStyle.fontSize = 36
    XCTAssertFalse(host.replaceVisibleSession(session, style: changedStyle))
    XCTAssertNotNil(host.canvas.measuredRect(for: 0))
  }

  func testWrongInputRepaintMatchesFullInkAndGeometry() async throws {
    var session = TypingSession(configuration: .words(4), prompt: "one two three four")
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    let sequence = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: directory, style: style, width: 180, font: font))
    let host = PromptViewportNativeScrollHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
    defer { host.stop() }
    XCTAssertTrue(host.configure(sequence: sequence, batchSize: 2))
    try await waitUntil { sequence.nextField > 0 && !host.isPreparing }
    session.insert("x", at: Date(timeIntervalSinceReferenceDate: 916_200_000))
    XCTAssertTrue(host.replaceVisibleSession(session, style: style))
    let complete = try XCTUnwrap(PromptRenderPlan(session: session,
      composition: "", style: style).render().compositionTextMap)
    let full = PromptFieldTextLayout(map: complete, width: 180, font: font)
    XCTAssertEqual(host.canvas.renderedCellText(for: 0),
      complete.fieldRuns.flatMap(\.cells).first?.text)
    XCTAssertEqual(host.canvas.measuredRect(for: 0), full.cellFrames[0])
  }

  func testRemoteViewportRejectsInputReplacementForCompletePathFallback() async throws {
    var session = TypingSession(configuration: .words(40),
      prompt: (0..<40).map { "word\($0)" }.joined(separator: " "))
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    let sequence = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: directory, style: style, width: 180, font: font))
    let host = PromptViewportNativeScrollHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
    defer { host.stop() }
    XCTAssertTrue(host.configure(sequence: sequence, batchSize: 2))
    try await waitUntil { sequence.nextField > 2 && !host.isPreparing }
    host.scrollToMeasuredEnd()
    try await waitUntil { host.scrollView.contentView.bounds.minY > 0 }
    session.insert("w", at: Date(timeIntervalSinceReferenceDate: 916_200_000))
    XCTAssertFalse(host.replaceVisibleSession(session, style: style))
  }

  func testReplacingDuringOldPendingBatchCannotRepublishOldInk() async throws {
    var session = TypingSession(configuration: .words(8),
      prompt: "one two three four five six seven eight")
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    let sequence = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: directory, style: style, width: 180, font: font))
    let host = PromptViewportNativeScrollHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
    defer { host.stop() }
    XCTAssertTrue(host.configure(sequence: sequence, batchSize: 2))
    session.insert("o", at: Date(timeIntervalSinceReferenceDate: 916_200_000))
    XCTAssertTrue(host.replaceVisibleSession(session, style: style))
    let expected = host.canvas.renderedCellText(for: 0)
    try await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(host.canvas.renderedCellText(for: 0), expected)
    XCTAssertNotNil(expected)
    XCTAssertEqual(sequence.nextField, 0, "Cancelled old sequence must not prepare a late batch")
  }

  func testHundredThousandWordTopInputRepaintsWithoutWholeProjection() async throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["TYPEBAR_ENDURANCE_TESTS"] == "1",
      "Run explicitly with TYPEBAR_ENDURANCE_TESTS=1")
    let count = 100_001
    let prompt = Array(repeating: "oak", count: count).joined(separator: " ")
    var session = TypingSession(configuration: .words(count), prompt: prompt)
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    let sequence = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: directory, style: style, width: 180, font: font))
    let host = PromptViewportNativeScrollHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
    defer { host.stop() }
    XCTAssertTrue(host.configure(sequence: sequence, batchSize: 32))
    try await waitUntil { host.measuredFieldCount == 32 && !host.isPreparing }
    let motion = PromptCaretMotionCoordinator()
    host.configureCaret(caretConfig(session, motion: motion))
    host.presentCaret(at: 0)
    XCTAssertEqual(motion.main.position, host.canvas.measuredRect(for: 0))
    let before = host.canvas.renderedCellText(for: 0)
    session.insert("o", at: Date(timeIntervalSinceReferenceDate: 916_200_000))
    XCTAssertTrue(host.replaceVisibleSession(session, style: style))
    host.configureCaret(caretConfig(session, motion: motion))
    host.presentCaret(at: 0.1)
    XCTAssertEqual(host.measuredFieldCount, 32)
    XCTAssertNotEqual(host.canvas.renderedCellText(for: 0), before)
    XCTAssertEqual(motion.main.position, host.canvas.measuredRect(for: 1))
    XCTAssertEqual(host.canvas.accessibilityValue() as? String, prompt)
    XCTAssertFalse(host.canvas.hasCompleteHeight)
  }

  func testUnsupportedExtraInputLeavesOldHostForCompletePathFallback() async throws {
    var session = TypingSession(configuration: .words(3), prompt: "a\nb cd")
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    let sequence = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: directory, style: style, width: 180, font: font))
    let host = PromptViewportNativeScrollHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
    defer { host.stop() }
    XCTAssertTrue(host.configure(sequence: sequence, batchSize: 2))
    try await waitUntil { sequence.nextField > 0 && !host.isPreparing }
    let before = host.canvas.renderedCellText(for: 0)
    session.insertBatch("ax", at: Date(timeIntervalSinceReferenceDate: 916_200_000))
    XCTAssertFalse(host.replaceVisibleSession(session, style: style))
    XCTAssertEqual(host.canvas.renderedCellText(for: 0), before)
  }

  func testNativeScrollHostCaretMovesWithAcceptedInputAndCurrentWindow() async throws {
    var session = TypingSession(configuration: .words(4), prompt: "one two three four")
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    let sequence = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: directory, style: style, width: 180, font: font))
    let host = PromptViewportNativeScrollHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
    defer { host.stop() }
    let motion = PromptCaretMotionCoordinator()
    XCTAssertTrue(host.configure(sequence: sequence, batchSize: 2))
    try await waitUntil { sequence.nextField > 0 && !host.isPreparing }
    host.configureCaret(caretConfig(session, motion: motion))
    host.presentCaret(at: 0)
    let initial = try XCTUnwrap(PromptRenderPlan(session: session,
      composition: "", style: style).render().compositionTextMap)
    XCTAssertEqual(motion.main.position,
      PromptFieldTextLayout(map: initial, width: 180, font: font).mainRect(style: .bar))
    session.insert("o", at: Date(timeIntervalSinceReferenceDate: 916_200_000))
    XCTAssertTrue(host.replaceVisibleSession(session, style: style))
    host.configureCaret(caretConfig(session, motion: motion))
    host.presentCaret(at: 0.1)
    let updated = try XCTUnwrap(PromptRenderPlan(session: session,
      composition: "", style: style).render().compositionTextMap)
    XCTAssertEqual(motion.main.position,
      PromptFieldTextLayout(map: updated, width: 180, font: font).mainRect(style: .bar))
  }
}
