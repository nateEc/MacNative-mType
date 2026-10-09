import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class TapePromptRetirementTests: XCTestCase {
  private let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .medium)
  private let text = "aaa bbb ccc ddd eee fff ggg"

  private func configure(_ view: TapePromptNativeView, _ coordinator: PromptCaretMotionCoordinator,
    attempt: UUID, active: Int, retained: Int = 0, rtl: Bool = false, smooth: Bool = false,
    mode: PracticeTapeMode = .word,
    pace: Int? = nil,
    at time: Double, notify: @escaping (PromptWordRetirement) -> Void) {
    let string = String(text.dropFirst(retained * 4))
    var attributed = AttributedString(string); attributed.foregroundColor = .gray
    let rendering = PromptRendering(text: attributed,
      glyphCharacterOffsets: Dictionary(uniqueKeysWithValues: string.enumerated().map {
        (retained * 4 + $0.offset, $0.offset)
      }))
    let words = (0..<7).map { PromptLineScrollWord(index: $0, glyphID: $0 * 4) }
    var config = PromptCaretNativeView.Configuration(text: rendering.text, mainOffset: nil, paceOffset: nil,
      mainStyle: .bar, paceStyle: pace == nil ? .off : .outline, font: font, lineSpacing: 0, rightToLeft: rtl,
      accent: .yellow, motion: .off, reducesMotion: false, frameRate: 60, attemptID: attempt,
      coordinator: coordinator, mainGlyphID: active * 4)
    config.mainPresentation = { .init(isVisible: true, isBlinking: false) }
    if let pace {
      config.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
        fromAfter: false, targetAfter: false, fraction: 1, targetGlyphID: pace * 4) }
    }
    view.configure(rendering: rendering, anchorCharacterIndex: (active - retained) * 4,
      wordAnchorCharacterIndex: (active - retained) * 4, mode: mode, margin: 0.25,
      smoothScroll: smooth, retirement: .init(attemptID: attempt, activeWordID: active * 4,
        characterOffsets: rendering.glyphCharacterOffsets, smoothScroll: smooth, reducesMotion: false,
        words: words, firstRetainedWordIndex: retained, onRetire: notify), carets: config, at: time)
  }

  private func drain() { RunLoop.main.run(until: Date().addingTimeInterval(0.003)) }

  func testStrictIntegralOverflowThresholdDoesNotRetireTheTouchingWord() {
    for left: CGFloat in [-37, -36.999, -36, -35.999, 80, 80.999, 81] {
      XCTAssertEqual(PracticeTapePolicy.isOverflowing(wordLeft: left, wordWidth: 36.9,
        viewportWidth: 80, rightToLeft: false), left < -36)
      XCTAssertEqual(PracticeTapePolicy.isOverflowing(wordLeft: left, wordWidth: 36.9,
        viewportWidth: 80, rightToLeft: true), left >= 81)
    }
  }

  func testExactFractionalEndpointCompletesWithoutMovingAnEarlierRealFrame() {
    var channel = PromptCaretChannel()
    channel.tapeScroll(to: -48, at: 0.45, duration: 0.125)
    channel.sample(at: 0.563 - 0.000001)
    XCTAssertFalse(channel.tapeMarginReady)
    channel.sample(at: 0.563)
    XCTAssertTrue(channel.tapeMarginReady)
    XCTAssertEqual(channel.tapeMargin, -48)
  }

  func testBothModesRetireFromSmoothPresentedGeometryWithoutWaitingForAnimationCompletion() {
    for mode: PracticeTapeMode in [.letter, .word] { for rtl in [false, true] {
      let coordinator = PromptCaretMotionCoordinator(), attempt = UUID()
      let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 80, height: 60))
      defer { view.stop() }
      var retired: [PromptWordRetirement] = []
      configure(view, coordinator, attempt: attempt, active: 0, rtl: rtl, smooth: true, mode: mode, at: 0) { retired.append($0) }
      configure(view, coordinator, attempt: attempt, active: 2, rtl: rtl, smooth: true, mode: mode, at: 1) { retired.append($0) }
      view.present(at: 1.07); drain()
      XCTAssertTrue(coordinator.isAnimatingTape)
      XCTAssertTrue(retired.isEmpty)
      configure(view, coordinator, attempt: attempt, active: 3, rtl: rtl, smooth: true, mode: mode, at: 1.07) { retired.append($0) }
      drain()
      XCTAssertTrue(coordinator.isAnimatingTape, "Retirement is not a tween completion hook")
      XCTAssertEqual(retired, [.init(attemptID: attempt, firstRetainedWordIndex: 1)])
    } }
  }

  func testQueuedRetirementIsInvalidatedWhenInputReturnsToAnEarlierWord() {
    let coordinator = PromptCaretMotionCoordinator(), attempt = UUID()
    let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 80, height: 60))
    defer { view.stop() }
    var retired: [PromptWordRetirement] = []
    configure(view, coordinator, attempt: attempt, active: 2, at: 0) { retired.append($0) }
    view.present(at: 0)
    configure(view, coordinator, attempt: attempt, active: 3, at: 1) { retired.append($0) }
    configure(view, coordinator, attempt: attempt, active: 0, at: 1) { retired.append($0) }
    drain()
    XCTAssertTrue(retired.isEmpty)
  }

  func testRepeatedUpdateDoesNotNotifyOrApplyTheSamePrefixTwice() {
    let coordinator = PromptCaretMotionCoordinator(), attempt = UUID()
    let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 80, height: 60))
    defer { view.stop() }
    var retired: [PromptWordRetirement] = []
    configure(view, coordinator, attempt: attempt, active: 2, at: 0) { retired.append($0) }
    view.present(at: 0)
    for _ in 0..<3 {
      configure(view, coordinator, attempt: attempt, active: 3, at: 1) { retired.append($0) }
      drain()
    }
    XCTAssertEqual(retired, [.init(attemptID: attempt, firstRetainedWordIndex: 1)])
    for _ in 0..<3 {
      configure(view, coordinator, attempt: attempt, active: 3, retained: 1, at: 1) { retired.append($0) }
      view.present(at: 1)
    }
    XCTAssertEqual(coordinator.main.cumulativeTapeCorrection,
      ("aaa " as NSString).size(withAttributes: [.font: font]).width, accuracy: 1e-7)
  }

  func testActualSessionRetirementBlocksMissingHistoryWithoutErasingPromptInputOrReplay() throws {
    let start = Date(timeIntervalSinceReferenceDate: 913_000_000)
    var session = TypingSession(configuration: .words(7, rules: .init(freedomMode: true)), prompt: text)
    let original = session.prompt, attempt = session.automaticInputAttemptID
    func replay(_ session: TypingSession) throws -> [TypingReplayEvent] {
      var snapshot = session; snapshot.bailOut(at: start.addingTimeInterval(20))
      return try XCTUnwrap(snapshot.result()).replayEvents
    }
    let coordinator = PromptCaretMotionCoordinator()
    let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 80, height: 60))
    defer { view.stop() }
    for active in 0...3 {
      if active > 0 { session.insertBatch("aaa ", at: start.addingTimeInterval(Double(active))) }
      configure(view, coordinator, attempt: attempt, active: active, at: Double(active)) {
        session.retirePromptWords($0)
      }
      view.present(at: Double(active)); drain()
    }
    XCTAssertEqual(session.firstRetainedPromptWordIndex, 1)
    XCTAssertEqual(session.prompt, original); XCTAssertEqual(session.typed, "aaa aaa aaa ")
    let beforeReplay = try replay(session)
    configure(view, coordinator, attempt: attempt, active: 3, retained: 1, at: 4) { session.retirePromptWords($0) }
    view.present(at: 4); drain()
    XCTAssertEqual(try replay(session), beforeReplay)
    session.deleteWordBackward(at: start.addingTimeInterval(5))
    session.deleteWordBackward(at: start.addingTimeInterval(6))
    let boundaryInput = session.typed, boundaryReplay = try replay(session)
    session.deleteBackward(at: start.addingTimeInterval(7))
    session.deleteWordBackward(at: start.addingTimeInterval(8))
    XCTAssertEqual(session.typed, boundaryInput); XCTAssertEqual(boundaryInput, "aaa ")
    XCTAssertEqual(try replay(session), boundaryReplay)
    XCTAssertEqual(session.prompt, original); XCTAssertEqual(session.automaticInputAttemptID, attempt)
  }

  func testActualPrefixRemovalRendersTheSameVisiblePixelsWithoutShowingAWindow() throws {
    for rtl in [false, true] {
      let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 240, height: 60),
        styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
      let coordinator = PromptCaretMotionCoordinator(), attempt = UUID()
      let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 240, height: 60))
      window.contentView = view
      defer { view.stop(); window.contentView = nil; window.close() }
      view.layoutSubtreeIfNeeded()
      var retired: [PromptWordRetirement] = []
      let delivered = expectation(description: "Actual prefix retirement, rtl=\(rtl)")
      delivered.assertForOverFulfill = true
      let accept: (PromptWordRetirement) -> Void = { retired.append($0); delivered.fulfill() }
      configure(view, coordinator, attempt: attempt, active: 5, rtl: rtl, at: 0, notify: accept)
      view.present(at: 0)
      configure(view, coordinator, attempt: attempt, active: 6, rtl: rtl, at: 1, notify: accept)
      wait(for: [delivered], timeout: 1); view.present(at: 1)
      let boundary = try XCTUnwrap(retired.last).firstRetainedWordIndex
      XCTAssertEqual(boundary, 4)
      var images: [Data] = []
      for trimmed in [false, true] {
        if trimmed {
          configure(view, coordinator, attempt: attempt, active: 6, retained: boundary, rtl: rtl, at: 1) { _ in }
          view.present(at: 1)
        }
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:])); images.append(png)
        if let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] {
          try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(
            "tape-retirement-\(rtl ? "rtl" : "ltr")-\(trimmed ? "after" : "before").png"))
        }
      }
      XCTAssertEqual(images[0], images[1], "Retired prefix removal must not jump visible native text or markers")
      XCTAssertFalse(window.isVisible)
    }
  }

  func testRetainedAndMissingPaceTargetsDoNotJumpWhenNativePrefixRebases() throws {
    for rtl in [false, true] { for smooth in [false, true] { for pace in [0, 6] {
      let coordinator = PromptCaretMotionCoordinator(), attempt = UUID()
      let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 80, height: 60))
      defer { view.stop() }
      var retired: [PromptWordRetirement] = []
      configure(view, coordinator, attempt: attempt, active: 0, rtl: rtl, smooth: smooth, pace: pace, at: 0) { retired.append($0) }
      configure(view, coordinator, attempt: attempt, active: 5, rtl: rtl, smooth: smooth, pace: pace, at: 1) { retired.append($0) }
      view.present(at: 1.07); drain()
      configure(view, coordinator, attempt: attempt, active: 6, rtl: rtl, smooth: smooth, pace: pace, at: 1.07) { retired.append($0) }
      view.present(at: 1.07); drain()
      let boundary = try XCTUnwrap(retired.last).firstRetainedWordIndex
      XCTAssertGreaterThan(boundary, 0)
      let before = try XCTUnwrap(coordinator.pace.visibleRect)
      configure(view, coordinator, attempt: attempt, active: 6, retained: boundary, rtl: rtl,
        smooth: smooth, pace: pace, at: 1.07) { retired.append($0) }
      view.present(at: 1.07)
      let after = try XCTUnwrap(coordinator.pace.visibleRect)
      XCTAssertEqual(after.minX, before.minX, accuracy: 1e-7)
      XCTAssertEqual(after.width, before.width, accuracy: 1e-7)
    } } }
  }

  func testOverflowUsesPresentedPositionBeforeNewScrollAndNeverRetiresActiveWord() {
    for rtl in [false, true] {
      let coordinator = PromptCaretMotionCoordinator(), attempt = UUID()
      let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 80, height: 60))
      defer { view.stop() }
      var retired: [PromptWordRetirement] = []
      for active in 0...2 {
        configure(view, coordinator, attempt: attempt, active: active, rtl: rtl, at: Double(active)) { retired.append($0) }
        view.present(at: Double(active)); drain()
        XCTAssertTrue(retired.isEmpty, "The new destination is not the pre-scroll source geometry")
      }
      configure(view, coordinator, attempt: attempt, active: 3, rtl: rtl, at: 3) { retired.append($0) }
      XCTAssertTrue(retired.isEmpty, "SwiftUI configure cannot synchronously mutate its observed session")
      drain()
      XCTAssertEqual(retired, [.init(attemptID: attempt, firstRetainedWordIndex: 1)])
    }
  }

  func testStoppedOrReplacedAttemptCannotDeliverOldQueuedRetirement() {
    for stop in [false, true] {
      let coordinator = PromptCaretMotionCoordinator(), attempt = UUID()
      let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 80, height: 60))
      defer { view.stop() }
      var retired: [PromptWordRetirement] = []
      for active in 0...2 {
        configure(view, coordinator, attempt: attempt, active: active, at: Double(active)) { retired.append($0) }
        view.present(at: Double(active)); drain()
      }
      configure(view, coordinator, attempt: attempt, active: 3, at: 3) { retired.append($0) }
      if stop { view.stop() }
      else { configure(view, coordinator, attempt: UUID(), active: 0, at: 3) { retired.append($0) } }
      drain()
      XCTAssertTrue(retired.isEmpty)
    }
  }

  func testAcknowledgedPrefixRemovalPreservesTextPositionAndCorrectsBothMarkerOwners() throws {
    for rtl in [false, true] {
      let coordinator = PromptCaretMotionCoordinator(), attempt = UUID()
      let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 80, height: 60))
      defer { view.stop() }
      for active in 0...3 {
        configure(view, coordinator, attempt: attempt, active: active, rtl: rtl, at: Double(active)) { _ in }
        view.present(at: Double(active)); drain()
      }
      let before = coordinator.wordsTapeMargin
      let step = ("aaa " as NSString).size(withAttributes: [.font: font]).width
      configure(view, coordinator, attempt: attempt, active: 3, retained: 1, rtl: rtl, at: 4) { _ in }
      view.present(at: 4)
      let correction = rtl ? -step : step
      XCTAssertEqual(coordinator.wordsTapeMargin, before + correction, accuracy: 1e-7)
      XCTAssertEqual(coordinator.main.cumulativeTapeCorrection, correction, accuracy: 1e-7)
      XCTAssertEqual(coordinator.pace.cumulativeTapeCorrection, correction, accuracy: 1e-7)
      let main = try XCTUnwrap(coordinator.main.visibleRect)
      // These Latin words stay LTR even when the tape flows RTL.
      XCTAssertEqual(main.minX, 20, accuracy: 1e-7)
      XCTAssertEqual(view.accessibilityLabel(), "bbb ccc ddd eee fff ggg")
    }
  }

  func testProductionTapePassesCanonicalSessionRetirementContext() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let app = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    let start = try XCTUnwrap(app.range(of: "struct TapePracticePrompt"))
    let end = try XCTUnwrap(app.range(of: "struct ChooGlyphPalette"))
    XCTAssertTrue(app[start.lowerBound..<end.lowerBound].contains("retirement: retirement"))
    XCTAssertTrue(app.contains("retirement: practiceLineScrollContext(rendering)"))
  }
}
