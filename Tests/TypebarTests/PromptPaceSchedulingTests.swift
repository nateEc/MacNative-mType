import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class PromptPaceSchedulingTests: XCTestCase {
  private let text = "amber birch cedar delta elm fir oak pine"
  private let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .medium)

  private func configuration(_ motion: PromptCaretMotionCoordinator,
    attempt: UUID = UUID(), paceStyle: TypingCaretStyle = .bar,
    reducesMotion: Bool = false) -> PromptCaretNativeView.Configuration {
    .init(text: AttributedString(text), mainOffset: nil, paceOffset: nil,
      mainStyle: .off, paceStyle: paceStyle, font: font, lineSpacing: 12,
      rightToLeft: false, accent: .yellow, motion: .off, reducesMotion: reducesMotion,
      frameRate: 15, attemptID: attempt, coordinator: motion)
  }

  private func interpolation(_ session: TypingSession) -> PromptPaceCaretInterpolation? {
    guard let frame = session.paceCaretFrame() else { return nil }
    let from = session.paceCaretGlyphAnchor(for: frame.from)
    let target = session.paceCaretGlyphAnchor(for: frame.target)
    return .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
      fromAfter: from?.after ?? false, targetAfter: target?.after ?? false,
      fraction: frame.fraction, stepDuration: frame.stepDuration, sequence: frame.sequence,
      targetGlyphID: target?.glyphIndex)
  }

  private var rendering: PromptRendering {
    .init(text: AttributedString(text), glyphCharacterOffsets: Dictionary(
      uniqueKeysWithValues: (0..<text.count).map { ($0, $0) }))
  }

  func testActualDeadlineTimerGeneratesMoreTargetsThanFifteenFPSPolling() {
    let motion = PromptCaretMotionCoordinator()
    let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 600, height: 400))
    defer { view.stop() }
    let clock = PaceCaretClock.system
    var origin: Double?
    var session = TypingSession(configuration: .words(100), prompt: text)
    session.configurePace(wpm: 300, clock: .init { origin.map { max(0, clock.now() - $0) } ?? 0 })
    session.beginComposition(at: Date(timeIntervalSince1970: 0))
    var supplied = 0, requests: [Int] = []
    var config = configuration(motion)
    config.paceFrame = {
      let frame = self.interpolation(session)
      supplied = Int(frame?.sequence ?? 0)
      return frame
    }
    config.latestRendering = {
      if supplied > 0 { requests.append(supplied) }
      return self.rendering
    }
    view.update(config); view.layout(); view.present(at: ProcessInfo.processInfo.systemUptime)
    origin = clock.now() // Exclude initial native hosting/layout warm-up.
    RunLoop.main.run(until: Date().addingTimeInterval(0.26))
    XCTAssertGreaterThanOrEqual(Set(requests).count, 5,
      "40ms pace deadlines must not be reduced to 67ms drawing polls: \(requests)")
  }

  func testStartingPaceRequestsItsFirstTargetWithoutWaitingForAPresentation() {
    let motion = PromptCaretMotionCoordinator()
    let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 600, height: 400))
    defer { view.stop() }
    var config = configuration(motion)
    config.paceFrame = { .init(fromCharacterOffset: 0, targetCharacterOffset: 1,
      fromAfter: false, targetAfter: false, fraction: 0, stepDuration: 0.2, sequence: 1) }
    view.update(config); view.layout()
    RunLoop.main.run(until: Date().addingTimeInterval(0.06))
    XCTAssertNotNil(motion.pace.position)
    XCTAssertTrue(view.subviews.isEmpty, "A pace request must not draw either marker layer")
  }

  func testLateModelStepUsesRemainingDurationAndRepeatedReadsDoNotRestartIt() throws {
    let clock = PaceCaretTestClock()
    var session = TypingSession(configuration: .words(100), prompt: text)
    session.configurePace(wpm: 300, clock: clock.source)
    session.beginComposition(at: Date(timeIntervalSince1970: 0))
    let motion = PromptCaretMotionCoordinator()
    let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 600, height: 400))
    defer { view.stop() }
    var config = configuration(motion), reads = 0
    config.paceFrame = { self.interpolation(session) }
    config.latestRendering = { reads += 1; return self.rendering }
    view.update(config); view.layout(); view.present(at: 0)
    let before = motion.pace.position
    clock.time = 0.055
    view.requestPacePosition(at: 0.055)
    XCTAssertEqual(motion.pace.position, before, "Requesting a later step does not present it")
    clock.time = 0.06
    view.present(at: 0.06)
    let target = try XCTUnwrap(PromptCaretLayout.rect(in: AttributedString(text), characterOffset: 2,
      containerSize: view.bounds.size, font: font, lineSpacing: 12, isRightToLeft: false))
    XCTAssertEqual(try XCTUnwrap(motion.pace.position).minX,
      target.minX * (0.005 + PromptLineScrollMotion.autoplayLead) / 0.025, accuracy: 1e-6)
    clock.time = 0.061
    view.requestPacePosition(at: 0.061)
    motion.sample(at: 0.07)
    XCTAssertEqual(motion.pace.position, target)
    XCTAssertEqual(reads, 3, "Main initialization plus two logical pace requests, not repeated reads")
  }

  func testIndependentPrunedTargetPreservesReadyMarginAndDoesNotPaint() {
    let motion = PromptCaretMotionCoordinator()
    let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 600, height: 400))
    defer { view.stop() }
    var frame = PromptPaceCaretInterpolation(fromCharacterOffset: nil, targetCharacterOffset: nil,
      fromAfter: false, targetAfter: false, fraction: 0, stepDuration: 0.04,
      sequence: 1, targetGlyphID: 1)
    var config = configuration(motion)
    config.paceFrame = { frame }; config.latestRendering = { self.rendering }
    view.update(config); view.layout(); view.present(at: 0)
    let painted = view.subviews.map(\.frame)
    motion.lineJump(to: -45, duration: 0, at: 0.01)
    let visible = motion.pace.visibleRect
    frame.sequence = 2; frame.targetGlyphID = 999
    view.requestPacePosition(at: 0.04)
    XCTAssertEqual(motion.pace.visibleRect, visible)
    XCTAssertTrue(motion.pace.marginReady)
    frame.sequence = 3; frame.targetGlyphID = 2
    view.requestPacePosition(at: 0.08)
    XCTAssertEqual(motion.pace.visibleRect, visible)
    XCTAssertFalse(motion.pace.marginReady)
    XCTAssertEqual(motion.pace.margin, 0)
    XCTAssertEqual(view.subviews.map(\.frame), painted)
    XCTAssertEqual(motion.main.margin, 0)
  }

  func testLatestAttemptInvalidatesTheOldStepEvenBeforeAConfigurationUpdate() {
    let motion = PromptCaretMotionCoordinator()
    let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 600, height: 400))
    defer { view.stop() }
    var attempt = UUID(), target = 1
    var config = configuration(motion, attempt: attempt)
    config.latestInput = { .init(attemptID: attempt, typed: "", composition: "", glyphID: nil) }
    config.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
      fromAfter: false, targetAfter: false, fraction: 0, stepDuration: 0.04,
      sequence: 1, targetGlyphID: target) }
    config.latestRendering = { self.rendering }
    view.update(config); view.layout(); view.requestPacePosition(at: 0)
    motion.lineJump(to: -45, duration: 0.125, at: 0)
    motion.sample(at: 0.025)
    attempt = UUID(); target = 4
    view.requestPacePosition(at: 0.04)
    XCTAssertEqual(motion.pace.margin, 0)
    XCTAssertFalse(motion.pace.marginReady)
    XCTAssertEqual(motion.wordsMargin, 0)
    motion.sample(at: 0.2)
    let targetRect = PromptCaretLayout.rect(in: AttributedString(text), characterOffset: 4,
      containerSize: view.bounds.size, font: font, lineSpacing: 12, isRightToLeft: false)
    XCTAssertEqual(motion.pace.position, targetRect)
  }

  func testStopCancelsPendingRequestsAndReleasesCapturedProviders() {
    final class Token {}
    var token: Token? = Token()
    weak var released = token
    let motion = PromptCaretMotionCoordinator()
    let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 600, height: 400))
    var reads = 0, config = configuration(motion)
    config.paceFrame = { [owner = token!] in
      _ = owner; reads += 1
      return .init(fromCharacterOffset: 0, targetCharacterOffset: 1,
        fromAfter: false, targetAfter: false, fraction: 0, stepDuration: 0.02, sequence: 1)
    }
    view.update(config); view.layout(); view.requestPacePosition(at: 0)
    config.paceFrame = nil; token = nil
    view.stop()
    XCTAssertNil(released)
    let stopped = reads
    RunLoop.main.run(until: Date().addingTimeInterval(0.08))
    XCTAssertEqual(reads, stopped)
  }

  func testDisabledAndUnavailablePaceLeaveNoPendingDeadlinePolling() {
    let motion = PromptCaretMotionCoordinator()
    let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 600, height: 400))
    defer { view.stop() }
    var reads = 0
    let provider: () -> PromptPaceCaretInterpolation? = {
      reads += 1
      return .init(fromCharacterOffset: 0, targetCharacterOffset: 1,
        fromAfter: false, targetAfter: false, fraction: 0, stepDuration: 0.02, sequence: 1)
    }
    var config = configuration(motion)
    config.paceFrame = provider
    view.update(config); view.layout(); view.requestPacePosition(at: 0)
    config = configuration(motion, paceStyle: .off); config.paceFrame = provider
    view.update(config)
    let disabled = reads
    RunLoop.main.run(until: Date().addingTimeInterval(0.08))
    XCTAssertEqual(reads, disabled)
    config = configuration(motion); config.paceFrame = { reads += 1; return nil }
    view.update(config); view.requestPacePosition(at: 0.08)
    let unavailable = reads
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    XCTAssertEqual(reads, unavailable)
  }

  func testReducedMotionStillAcceptsEachIndependentLogicalStep() {
    let motion = PromptCaretMotionCoordinator()
    let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 600, height: 400))
    defer { view.stop() }
    var step = 1.0
    var config = configuration(motion, reducesMotion: true)
    config.paceFrame = { .init(fromCharacterOffset: 0, targetCharacterOffset: Int(step),
      fromAfter: false, targetAfter: false, fraction: 0, stepDuration: 0.04, sequence: step) }
    view.update(config); view.layout(); view.requestPacePosition(at: 0)
    let first = motion.pace.position
    step = 2; view.requestPacePosition(at: 0.04)
    XCTAssertNotEqual(motion.pace.position, first)
    XCTAssertTrue(view.subviews.isEmpty)
  }

  func testSiblingGeometryInvalidationRebuildsTheCurrentStepWithoutWaitingForTheNextOne() {
    let motion = PromptCaretMotionCoordinator()
    let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 600, height: 400))
    defer { view.stop() }
    var config = configuration(motion)
    config.paceFrame = { .init(fromCharacterOffset: 0, targetCharacterOffset: 4,
      fromAfter: false, targetAfter: false, fraction: 0, stepDuration: 0.2, sequence: 1) }
    view.update(config); view.layout(); view.requestPacePosition(at: 0)
    motion.sample(at: 0.3)
    let target = motion.pace.position
    motion.resetLayout() // The follower owns and may invalidate shared geometry.
    view.requestPacePosition(at: 0.31)
    motion.sample(at: 0.6)
    XCTAssertEqual(motion.pace.position, target)
  }
}
