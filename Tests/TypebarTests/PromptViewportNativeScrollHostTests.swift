import AppKit
import XCTest
@testable import Typebar

@MainActor final class PromptViewportNativeScrollHostTests: XCTestCase {
  private let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
  private let style = PromptRenderStyle(theme: .init(background: .white, panel: .white,
    accent: .blue, colorScheme: .light))

  private func makeHost(frame: NSRect) -> PromptViewportNativeScrollHost {
    // The first preferred-style read schedules AppKit's initial refresh.
    // Deliver it before pinning this fixed-width fixture to overlay scrollers.
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
    let host = makeHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
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
    let host = makeHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
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
    let host = makeHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
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
    let host = makeHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
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
    let host = makeHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
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
    let host = makeHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
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
    let host = makeHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
    defer { host.stop() }
    XCTAssertTrue(host.configure(sequence: sequence, batchSize: 2))
    try await waitUntil { sequence.nextField > 0 }
    host.frame.size.width = 160
    host.layoutSubtreeIfNeeded()
    XCTAssertNil(host.canvas.measuredRect(for: 0))
    XCTAssertFalse(host.isPreparing)
  }

  func testLegacyScrollerMeasuresClipWidthAndStyleChangeRetiresGeometry() async throws {
    let session = TypingSession(configuration: .words(8), prompt: "one two three four five six seven eight")
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    let host = makeHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
    defer { host.stop() }
    host.scrollView.scrollerStyle = .legacy
    host.scrollView.tile()
    XCTAssertLessThan(host.layoutWidth, host.bounds.width)
    let sequence = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: directory, style: style, width: host.layoutWidth, font: font))
    XCTAssertTrue(host.configure(sequence: sequence, batchSize: 2))
    try await waitUntil { sequence.nextField > 0 && !host.isPreparing }
    XCTAssertEqual(host.canvas.frame.width, host.scrollView.contentView.bounds.width)
    XCTAssertNotNil(host.canvas.measuredRect(for: 0))
    host.scrollView.scrollerStyle = .overlay
    host.scrollView.tile()
    XCTAssertNil(host.canvas.measuredRect(for: 0))
    XCTAssertFalse(host.isPreparing)
  }

  func testBoundsWidthChangeAlsoRetiresOldMeasuredCanvas() async throws {
    let session = TypingSession(configuration: .words(4), prompt: "one two three four")
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    let sequence = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: directory, style: style, width: 180, font: font))
    let host = makeHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
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
    let host = makeHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
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
    let host = makeHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
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
    let host = makeHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
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
    let host = makeHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
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
    let host = makeHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
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
    let host = makeHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
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
    let host = makeHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
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

  func testRemoteViewportReplaysCurrentSessionAndPreservesVisibleField() async throws {
    var session = TypingSession(configuration: .words(40),
      prompt: (0..<40).map { "word\($0)" }.joined(separator: " "))
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    let sequence = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: directory, style: style, width: 180, font: font))
    let host = makeHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
    defer { host.stop() }
    XCTAssertTrue(host.configure(sequence: sequence, batchSize: 2))
    try await waitUntil { sequence.nextField > 2 && !host.isPreparing }
    host.scrollToMeasuredEnd()
    try await waitUntil { host.scrollView.contentView.bounds.minY > 0 }
    let oldOrigin = host.scrollView.contentView.bounds.minY
    let oldInk = host.canvas.renderedCellText(for: 0)
    session.insert("w", at: Date(timeIntervalSinceReferenceDate: 916_200_000))
    XCTAssertTrue(host.replaceVisibleSession(session, style: style))
    XCTAssertGreaterThan(host.scrollView.contentView.bounds.minY, 0)
    XCTAssertEqual(host.scrollView.contentView.bounds.minY, oldOrigin, accuracy: 1)
    host.scrollToTop()
    let complete = try XCTUnwrap(PromptRenderPlan(session: session,
      composition: "", style: style).render().compositionTextMap)
    XCTAssertEqual(host.canvas.renderedCellText(for: 0), complete.fieldRuns.flatMap(\.cells).first?.text)
    XCTAssertNotEqual(host.canvas.renderedCellText(for: 0), oldInk)
  }

  func testRemoteViewportRepaintsAcceptedInputAtVisibleField() async throws {
    let prompt = (0..<30).map { "word\($0)" }.joined(separator: " ")
    var session = TypingSession(configuration: .words(30), prompt: prompt)
    let prefix = (0..<10).map { "word\($0) " }.joined()
    session.insertBatch(prefix, at: Date(timeIntervalSinceReferenceDate: 916_200_000))
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    let sequence = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: directory, style: style, width: 180, font: font))
    let host = makeHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
    defer { host.stop() }
    XCTAssertTrue(host.configure(sequence: sequence, batchSize: 2))
    XCTAssertTrue(host.scrollToField(10))
    let targetID = prefix.utf16.count
    try await waitUntil { host.canvas.measuredRect(for: targetID) != nil && !host.isPreparing }
    let oldInk = host.canvas.renderedCellText(for: targetID)
    session.insert("w", at: Date(timeIntervalSinceReferenceDate: 916_200_001))
    XCTAssertTrue(host.replaceVisibleSession(session, style: style))
    let complete = try XCTUnwrap(PromptRenderPlan(session: session,
      composition: "", style: style).render().compositionTextMap)
    XCTAssertEqual(host.canvas.renderedCellText(for: targetID),
      complete.fieldRuns.flatMap(\.cells).first(where: { $0.id == targetID })?.text)
    XCTAssertEqual(host.canvas.measuredRect(for: targetID),
      PromptFieldTextLayout(map: complete, width: 180, font: font).cellFrames[targetID])
    XCTAssertNotEqual(host.canvas.renderedCellText(for: targetID), oldInk)
    XCTAssertTrue(host.scrollView.contentView.documentVisibleRect.intersects(
      try XCTUnwrap(host.canvas.measuredRect(for: targetID))))
  }

  func testInputReplacementPreservesCaretAndNativeInsertionAnchorAtTopAndRemote() async throws {
    for field in [0, 10] {
      let prompt = (0..<30).map { "word\($0)" }.joined(separator: " ")
      var session = TypingSession(configuration: .words(30), prompt: prompt)
      let prefix = (0..<field).map { "word\($0) " }.joined()
      if !prefix.isEmpty {
        session.insertBatch(prefix, at: Date(timeIntervalSinceReferenceDate: 916_200_000))
      }
      let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
      let sequence = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
        directory: directory, style: style, width: 180, font: font))
      let root = NSView(frame: .init(x: 0, y: 0, width: 400, height: 220))
      let host = makeHost(frame: .init(x: 30, y: 40, width: 180, height: 100))
      let input = TypingInputView(frame: .init(x: 1, y: 1, width: 1, height: 1))
      let window = NSWindow(contentRect: .init(x: 180, y: 220, width: 400, height: 220),
        styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      root.addSubview(host); root.addSubview(input); window.contentView = root
      defer { host.stop(); window.contentView = nil; window.close() }
      XCTAssertTrue(host.configure(sequence: sequence, batchSize: 2))
      XCTAssertTrue(host.scrollToField(field))
      try await waitUntil { host.canvas.measuredMainCaretRect(style: .bar) != nil && !host.isPreparing }
      let anchor = PromptInsertionAnchor(), motion = PromptCaretMotionCoordinator()
      var carets = caretConfig(session, motion: motion)
      carets.insertionAnchor = anchor
      carets.latestInput = { .init(attemptID: session.automaticInputAttemptID,
        typed: session.typed, composition: "", glyphID: session.promptCaretGlyphIndex) }
      host.configureCaret(carets)
      input.insertionAnchor = anchor
      input.insertionAttemptID = session.automaticInputAttemptID
      host.presentCaret(at: 0)
      XCTAssertNotNil(anchor.screenRect(attemptID: session.automaticInputAttemptID, in: window))

      session.insert("w", at: Date(timeIntervalSinceReferenceDate: 916_200_001))
      XCTAssertTrue(host.replaceVisibleSession(session, style: style))
      let cell = try XCTUnwrap(host.canvas.measuredMainCaretRect(style: .bar))
      let insertion = NSRect(x: cell.minX, y: cell.minY, width: 0, height: cell.height)
      let expected = window.convertToScreen(host.canvas.convert(insertion, to: nil))
      XCTAssertEqual(anchor.screenRect(attemptID: session.automaticInputAttemptID, in: window), expected)
      XCTAssertEqual(input.firstRect(forCharacterRange: .init(location: 0, length: 0), actualRange: nil), expected)
      host.presentCaret(at: 0.1)
      XCTAssertTrue(host.canvas.hasVisibleMainMarker, "field=\(field)")
      XCTAssertEqual(motion.main.position, cell, "field=\(field)")
      XCTAssertFalse(window.isVisible)
      host.stop()
      XCTAssertNil(anchor.screenRect(attemptID: session.automaticInputAttemptID, in: window))
    }
  }

  func testNewAttemptSnapshotRejectsOldCaretConfiguration() throws {
    var oldSession = TypingSession(configuration: .words(4), prompt: "one two three four")
    oldSession.insert("o", at: Date(timeIntervalSinceReferenceDate: 916_200_000))
    let newSession = oldSession.repeatedAttempt()
    let canvas = PromptViewportNativeCanvas(frame: .init(x: 0, y: 0, width: 180, height: 100))
    defer { canvas.clear() }
    func snapshot(_ session: TypingSession) throws -> PromptViewportFieldLayoutSequence.DrawingSnapshot {
      let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
      let sequence = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
        directory: directory, style: style, width: 180, font: font))
      let window = try XCTUnwrap(sequence.append(fields: 0..<2))
      return try XCTUnwrap(sequence.drawingSnapshot(windows: [window]))
    }
    let oldMotion = PromptCaretMotionCoordinator()
    let oldCarets = caretConfig(oldSession, motion: oldMotion)
    XCTAssertTrue(canvas.configure(snapshot: try snapshot(oldSession)))
    canvas.configureCaret(oldCarets)
    canvas.presentCaret(at: 0)
    let oldPosition = try XCTUnwrap(oldMotion.main.position)
    XCTAssertTrue(canvas.configure(snapshot: try snapshot(newSession)))
    XCTAssertTrue(canvas.caretIsRetired)
    canvas.configureCaret(oldCarets)
    canvas.presentCaret(at: 0.1)
    XCTAssertTrue(canvas.caretIsRetired)
    XCTAssertEqual(oldMotion.main.position, oldPosition)
    let newMotion = PromptCaretMotionCoordinator()
    canvas.configureCaret(caretConfig(newSession, motion: newMotion))
    canvas.presentCaret(at: 0.2)
    XCTAssertTrue(canvas.hasVisibleMainMarker)
    XCTAssertEqual(newMotion.main.position, canvas.measuredMainCaretRect(style: .bar))
    canvas.configureCaret(oldCarets)
    canvas.presentCaret(at: 0.3)
    XCTAssertEqual(oldMotion.main.position, oldPosition)
    XCTAssertTrue(canvas.hasVisibleMainMarker)
  }

  func testUnsupportedRemoteInputLeavesOldSnapshotAndPositionForFallback() async throws {
    let prompt = "a\nb cd " + (0..<20).map { "word\($0)" }.joined(separator: " ")
    var session = TypingSession(configuration: .words(23), prompt: prompt)
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    let sequence = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: directory, style: style, width: 180, font: font))
    let host = makeHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
    defer { host.stop() }
    XCTAssertTrue(host.configure(sequence: sequence, batchSize: 2))
    try await waitUntil { sequence.nextField > 0 && !host.isPreparing }
    XCTAssertTrue(host.scrollToField(10))
    try await waitUntil { host.scrollView.contentView.bounds.minY > 0 }
    let origin = host.scrollView.contentView.bounds.minY
    let targetID = try XCTUnwrap(directory.materialize(fields: 10..<11)?.cells.first?.id)
    let oldInk = try XCTUnwrap(host.canvas.renderedCellText(for: targetID))
    XCTAssertFalse(host.replaceVisibleSession(session.repeatedAttempt(), style: style))
    var changedStyle = style
    changedStyle.fontSize = 36
    XCTAssertFalse(host.replaceVisibleSession(session, style: changedStyle))
    session.insertBatch("ax", at: Date(timeIntervalSinceReferenceDate: 916_200_000))
    XCTAssertFalse(host.replaceVisibleSession(session, style: style))
    XCTAssertEqual(host.scrollView.contentView.bounds.minY, origin)
    XCTAssertEqual(host.canvas.renderedCellText(for: targetID), oldInk)
  }

  func testReplacingDuringOldPendingBatchCannotRepublishOldInk() async throws {
    var session = TypingSession(configuration: .words(8),
      prompt: "one two three four five six seven eight")
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    let sequence = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: directory, style: style, width: 180, font: font))
    let host = makeHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
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
    let host = makeHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
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
    host.presentCaret(at: 0.1)
    XCTAssertEqual(host.measuredFieldCount, 32)
    XCTAssertNotEqual(host.canvas.renderedCellText(for: 0), before)
    XCTAssertEqual(motion.main.position, host.canvas.measuredRect(for: 1))
    XCTAssertEqual(host.canvas.accessibilityValue() as? String, prompt)
    XCTAssertFalse(host.canvas.hasCompleteHeight)
  }

  func testHundredThousandWordRemoteInputRepaintsMeasuredPrefixOnly() async throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["TYPEBAR_ENDURANCE_TESTS"] == "1",
      "Run explicitly with TYPEBAR_ENDURANCE_TESTS=1")
    let count = 100_001
    let prompt = Array(repeating: "oak", count: count).joined(separator: " ")
    var session = TypingSession(configuration: .words(count), prompt: prompt)
    session.insertBatch(String(repeating: "oak ", count: 10),
      at: Date(timeIntervalSinceReferenceDate: 916_200_000))
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    let sequence = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: directory, style: style, width: 180, font: font))
    let host = makeHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
    defer { host.stop() }
    XCTAssertTrue(host.configure(sequence: sequence, batchSize: 32))
    try await waitUntil { host.measuredFieldCount == 32 && !host.isPreparing }
    XCTAssertTrue(host.scrollToField(10))
    let targetID = 40
    try await waitUntil { host.canvas.measuredRect(for: targetID) != nil }
    let motion = PromptCaretMotionCoordinator()
    host.configureCaret(caretConfig(session, motion: motion))
    host.presentCaret(at: 0)
    XCTAssertEqual(motion.main.position, host.canvas.measuredRect(for: targetID))
    let oldInk = host.canvas.renderedCellText(for: targetID)
    session.insert("o", at: Date(timeIntervalSinceReferenceDate: 916_200_001))
    XCTAssertTrue(host.replaceVisibleSession(session, style: style))
    host.presentCaret(at: 0.1)
    XCTAssertEqual(motion.main.position, host.canvas.measuredRect(for: targetID + 1))
    XCTAssertLessThanOrEqual(host.measuredFieldCount, 64)
    XCTAssertNotEqual(host.canvas.renderedCellText(for: targetID), oldInk)
    XCTAssertEqual(host.canvas.accessibilityValue() as? String, prompt)
    XCTAssertFalse(host.canvas.hasCompleteHeight)
  }

  func testUnsupportedExtraInputLeavesOldHostForCompletePathFallback() async throws {
    var session = TypingSession(configuration: .words(3), prompt: "a\nb cd")
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    let sequence = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: directory, style: style, width: 180, font: font))
    let host = makeHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
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
    let host = makeHost(frame: .init(x: 0, y: 0, width: 180, height: 100))
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
