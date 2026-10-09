import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class TapeNewlineTransitionTests: XCTestCase {
  private let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .medium)
  private let strings = ["abc", "amberviolet", "ghi", "jklmnop", "qrs", "tuv"]
  private func update(_ view: TapePromptNativeView, _ motion: PromptCaretMotionCoordinator,
    _ attempt: UUID, active: Int, retained: Int = 0, typed: String = "", smooth: Bool = true,
    rtl: Bool = false, uniform: Bool = false, mode: PracticeTapeMode = .letter,
    style: TypingCaretStyle = .bar, time: TimeInterval, onRetire: @escaping (PromptWordRetirement) -> Void) {
    var text = AttributedString(), offsets: [Int: Int] = [:], words: [TapePromptWord] = []
    for index in retained..<strings.count {
      let start = text.characters.count, string = (uniform ? "abc" : strings[index]) + (index < 5 ? "↵" : "")
      text.append(AttributedString(string))
      for character in 0..<string.count { offsets[index * 100 + character] = start + character }
      words.append(.init(index: index, glyphID: index * 100, characters: start..<(start + string.count),
        newlineCharacterOffset: index < 5 ? start + string.count - 1 : nil))
      if index < 5 { text.append(AttributedString("\n")) }
    }
    text.foregroundColor = .gray
    let glyph = active * 100 + typed.count
    var config = PromptCaretNativeView.Configuration(text: AttributedString(), mainOffset: nil, paceOffset: nil,
      mainStyle: style, paceStyle: style, font: font, lineSpacing: 0, rightToLeft: rtl,
      accent: .yellow, motion: .off, reducesMotion: false, frameRate: 60,
      attemptID: attempt, coordinator: motion, mainGlyphID: glyph)
    config.latestInput = { .init(attemptID: attempt, typed: typed, composition: "", glyphID: glyph) }
    config.mainPresentation = { .init(isVisible: true, isBlinking: false) }
    config.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
      fromAfter: false, targetAfter: false, fraction: 1, targetGlyphID: 400) }
    view.configure(rendering: .init(text: text, glyphCharacterOffsets: offsets),
      anchorCharacterIndex: offsets[glyph]!, wordAnchorCharacterIndex: offsets[active * 100]!,
      mode: mode, margin: 0.25, smoothScroll: smooth,
      retirement: .init(attemptID: attempt, activeWordID: active * 100, characterOffsets: offsets,
        smoothScroll: smooth, reducesMotion: false,
        words: words.map { .init(index: $0.index, glyphID: $0.glyphID) },
        firstRetainedWordIndex: retained, onRetire: onRetire), newlineWords: words, carets: config, at: time)
  }
  private func drainNotifications() {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.002))
  }
  private func begin(_ view: TapePromptNativeView, _ motion: PromptCaretMotionCoordinator,
    _ attempt: UUID, smooth: Bool = true, rtl: Bool = false,
    onRetire: @escaping (PromptWordRetirement) -> Void) {
    update(view, motion, attempt, active: 0, smooth: smooth, rtl: rtl, time: 0, onRetire: onRetire)
    update(view, motion, attempt, active: 1, smooth: smooth, rtl: rtl, time: 0.1, onRetire: onRetire)
    view.present(at: 0.213)
  }

  func testActualNewWordAwaitsVerticalDeletionBeforeHorizontalRequestAndAsyncNotification() throws {
    for rtl in [false, true] {
      let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 160))
      let motion = PromptCaretMotionCoordinator(), attempt = UUID()
      var retired: [PromptWordRetirement] = []
      defer { view.stop() }
      begin(view, motion, attempt, rtl: rtl) { retired.append($0) }
      let x = motion.wordsTapeMargin, height = view.subviews[0].frame.height
      update(view, motion, attempt, active: 2, rtl: rtl, time: 1) { retired.append($0) }
      view.present(at: 1.05)
      XCTAssertEqual(motion.wordsTapeMargin, x, accuracy: 1e-7, "New-word scrollTape must await lineJump")
      XCTAssertLessThan(motion.wordsMargin, 0)
      XCTAssertEqual(view.subviews[0].frame.minY, motion.wordsMargin)
      XCTAssertTrue(retired.isEmpty)
      view.present(at: 1.113)
      XCTAssertEqual(motion.wordsMargin, 0)
      // The native prefix is gone before a session callback can rebuild SwiftUI.
      XCTAssertLessThan(view.subviews[0].frame.height, height)
      XCTAssertEqual(motion.wordsTapeMargin, 0, accuracy: 1e-7)
      XCTAssertTrue(motion.isAnimatingTape)
      XCTAssertTrue(retired.isEmpty, "Session mutation is asynchronous")
      drainNotifications()
      XCTAssertEqual(retired.map(\.firstRetainedWordIndex), [1])
      XCTAssertEqual(retired.first?.attemptID, attempt)
    }
  }

  func testSameWordInputCanScrollHorizontallyDuringPendingVerticalAwait() {
    let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 320))
    let motion = PromptCaretMotionCoordinator(), attempt = UUID()
    defer { view.stop() }
    begin(view, motion, attempt) { _ in }
    update(view, motion, attempt, active: 2, time: 1) { _ in }
    view.present(at: 1.04)
    let oldX = motion.wordsTapeMargin
    update(view, motion, attempt, active: 2, typed: "g", time: 1.05) { _ in }
    XCTAssertEqual(motion.wordsTapeMargin, oldX, "Input is a request, not a presentation")
    view.present(at: 1.08)
    XCTAssertLessThan(motion.wordsTapeMargin, oldX)
    XCTAssertLessThan(motion.wordsMargin, 0)
  }

  func testNativePrefixAcknowledgementCannotCancelOrRestartTheReleasedHorizontalTween() {
    let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 320))
    let motion = PromptCaretMotionCoordinator(), attempt = UUID()
    defer { view.stop() }
    begin(view, motion, attempt) { _ in }
    update(view, motion, attempt, active: 2, time: 1) { _ in }
    view.present(at: 1.113)
    view.present(at: 1.14)
    let oldX = motion.wordsTapeMargin, correction = motion.pace.cumulativeTapeCorrection
    update(view, motion, attempt, active: 2, retained: 1, time: 1.15) { _ in }
    XCTAssertEqual(motion.wordsTapeMargin, oldX)
    XCTAssertEqual(motion.pace.cumulativeTapeCorrection, correction)
    XCTAssertTrue(motion.isAnimatingTape)
    let expected = PromptCaretMotionCoordinator()
    let width = (strings[1] as NSString).size(withAttributes: [.font: font]).width
    expected.tapeScroll(to: -width, duration: 0.125, at: 1.113)
    for time in [1.17, 1.20, 1.226] {
      expected.sample(at: time); view.present(at: time)
      XCTAssertEqual(motion.wordsTapeMargin, expected.wordsTapeMargin, accuracy: 1e-7)
    }
  }

  func testOverlappingNewlineOnlyLatestCompletionDeletesAndNotifies() {
    let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 320))
    let motion = PromptCaretMotionCoordinator(), attempt = UUID()
    var retired: [PromptWordRetirement] = []
    defer { view.stop() }
    begin(view, motion, attempt) { retired.append($0) }
    update(view, motion, attempt, active: 2, time: 1) { retired.append($0) }
    view.present(at: 1.05)
    update(view, motion, attempt, active: 3, time: 1.06) { retired.append($0) }
    view.present(at: 1.113); drainNotifications()
    XCTAssertLessThan(motion.wordsMargin, 0)
    XCTAssertTrue(retired.isEmpty, "A replaced vertical promise cannot complete")
    view.present(at: 1.173); drainNotifications()
    XCTAssertEqual(motion.wordsMargin, 0)
    XCTAssertEqual(retired.map(\.firstRetainedWordIndex), [2])
  }

  func testImmediateNewlineDeletesWithoutAssigningWordsVerticalMargin() {
    let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 320))
    let motion = PromptCaretMotionCoordinator(), attempt = UUID()
    var retired: [PromptWordRetirement] = []
    defer { view.stop() }
    begin(view, motion, attempt, smooth: false) { retired.append($0) }
    update(view, motion, attempt, active: 2, smooth: false, time: 1) { retired.append($0) }
    XCTAssertEqual(motion.wordsMargin, 0)
    XCTAssertFalse(motion.isAnimatingTape)
    drainNotifications()
    XCTAssertEqual(retired.map(\.firstRetainedWordIndex), [1])
  }

  func testRestartAndDetachInvalidatePendingVerticalCompletionAndQueuedRetirement() {
    for completes in [false, true] {
      let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 320))
      let motion = PromptCaretMotionCoordinator(), attempt = UUID()
      var retired: [PromptWordRetirement] = []
      defer { view.stop() }
      begin(view, motion, attempt) { retired.append($0) }
      update(view, motion, attempt, active: 2, time: 1) { retired.append($0) }
      view.present(at: completes ? 1.113 : 1.05)
      view.stop()
      update(view, motion, UUID(), active: 0, time: 2) { retired.append($0) }
      view.present(at: 3); drainNotifications()
      XCTAssertTrue(retired.isEmpty)
      XCTAssertEqual(motion.wordsMargin, 0)
      XCTAssertEqual(motion.wordsTapeMargin, 0)
    }
  }

  func testActualNativeOwnerAgainstCompleteSourceVerticalAndHorizontalSequence() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"],
      ProcessInfo.processInfo.environment["TYPEBAR_LINE_SCROLL_ANIME_ARCHIVE"] != nil else {
      throw XCTSkip("Requires pinned reference and locked Anime.js archive")
    }
    struct Event: Decodable {
      let type: String; let time: Double; let reason: String?
      let rendered: Bool?; let wordsX, wordsY: Double?; let first: Int?
    }
    struct Fixture: Decodable {
      let rtl, smooth, independent, overlap: Bool; let mode, style: String; let trace: [Event]
    }
    struct Evidence: Decodable { let pin: String; let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent(
      "Scripts/check-source-tape-line-composition.mjs").path, reference, "--emit-fixtures"]
    process.standardOutput = output; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw NSError(domain: "TapeNativeOwnerProbe", code: Int(process.terminationStatus)) }
    let evidence = try JSONDecoder().decode(Evidence.self, from: data)
    XCTAssertEqual(evidence.pin, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(evidence.fixtures.count, 128)
    let widthScale = ("abc" as NSString).size(withAttributes: [.font: font]).width / 36
    let measured = TapeNewlineTextLayout()
    measured.configure(text: AttributedString("abc↵"), words: [.init(index: 0, glyphID: 0,
      characters: 0..<4, newlineCharacterOffset: 3)], font: font, rightToLeft: false, resets: true)
    let rowHeight = measured.metrics.rowHeight
    for (index, fixture) in evidence.fixtures.enumerated() {
      let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 160))
      let motion = PromptCaretMotionCoordinator(), attempt = UUID()
      defer { view.stop() }
      let style: TypingCaretStyle = switch fixture.style {
        case "block": .block; case "outline": .outline; case "underline": .underline; default: .bar
      }
      var active = 0, typed = ""
      for event in fixture.trace {
        let time = event.time / 1000
        if event.type == "frame", event.rendered == true { view.present(at: time) }
        guard event.type == "sample" else { continue }
        if ["initial", "first-line", "jump-request", "independent-scroll", "overlapping-line"].contains(event.reason) {
          switch event.reason {
          case "first-line": active = 1
          case "jump-request": active = 2
          case "independent-scroll": typed = "a"
          case "overlapping-line": active = 3
          default: break
          }
          update(view, motion, attempt, active: active, typed: typed, smooth: fixture.smooth,
            rtl: fixture.rtl, uniform: true, mode: fixture.mode == "word" ? .word : .letter,
            style: style, time: time) { _ in }
        }
        // Requests and promise-internal samples can occur between frames.
        // Compare only the fully drained source frame, including native row deletion.
        guard event.reason == "frame" else { continue }
        let label = "fixture \(index) @\(event.time)ms"
        XCTAssertEqual(motion.wordsTapeMargin, try XCTUnwrap(event.wordsX) * widthScale, accuracy: 1e-6, label)
        XCTAssertEqual(motion.wordsMargin, try XCTUnwrap(event.wordsY) * rowHeight / 45, accuracy: 1e-6, label)
        XCTAssertEqual(view.subviews[0].frame.minY, motion.wordsMargin, accuracy: 1e-6, label)
        XCTAssertEqual(view.subviews[0].frame.height, CGFloat(6 - (try XCTUnwrap(event.first))) * rowHeight,
          accuracy: 1e-6, label)
      }
    }
  }

  func testBackwardInputIsNotBlockedAndCannotDeleteTheCurrentlyActiveNativePrefix() {
    for active in [0, 1] {
      let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 160))
      let motion = PromptCaretMotionCoordinator(), attempt = UUID()
      var retired: [PromptWordRetirement] = []
      defer { view.stop() }
      begin(view, motion, attempt) { retired.append($0) }
      let height = view.subviews[0].frame.height
      update(view, motion, attempt, active: 2, time: 1) { retired.append($0) }
      view.present(at: 1.04)
      update(view, motion, attempt, active: active, time: 1.05) { retired.append($0) }
      XCTAssertTrue(motion.isAnimatingTape, "Backward input has its own horizontal request")
      view.present(at: 1.113); drainNotifications()
      XCTAssertEqual(motion.wordsMargin, 0)
      XCTAssertEqual(retired.map(\.firstRetainedWordIndex), active == 0 ? [] : [1])
      if active == 0 { XCTAssertEqual(view.subviews[0].frame.height, height) }
      XCTAssertNotNil(motion.main.visibleRect)
    }
  }

  func testResizeCancelsThePendingVerticalOwnerBeforeItCanRetireWords() {
    let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 160))
    let motion = PromptCaretMotionCoordinator(), attempt = UUID()
    var retired: [PromptWordRetirement] = []
    defer { view.stop() }
    begin(view, motion, attempt) { retired.append($0) }
    let height = view.subviews[0].frame.height
    update(view, motion, attempt, active: 2, time: 1) { retired.append($0) }
    view.present(at: 1.05)
    view.setFrameSize(.init(width: 320, height: 160)); view.layout()
    view.present(at: 3); drainNotifications()
    XCTAssertTrue(retired.isEmpty)
    XCTAssertEqual(motion.wordsMargin, 0)
    XCTAssertEqual(view.subviews[0].frame.height, height)
  }

  func testActualCompletionAndSessionAcknowledgementPreserveNonemptyPixelsWithoutShowingWindow() throws {
    for rtl in [false, true] {
      let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 160),
        styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
      let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 160))
      view.layer?.backgroundColor = NSColor.black.cgColor; window.contentView = view
      let motion = PromptCaretMotionCoordinator(), attempt = UUID()
      defer { view.stop(); window.contentView = nil; window.close() }
      for (active, time) in [(0, 0.0), (1, 0.1), (2, 1.0)] {
        update(view, motion, attempt, active: active, rtl: rtl, style: .off, time: time) { _ in }
        view.present(at: active == 1 ? 0.213 : time)
      }
      var images: [NSBitmapImageRep] = []
      for stage in ["pending", "complete", "acknowledged"] {
        let time = stage == "pending" ? 1.05 : 1.113
        if stage == "acknowledged" {
          update(view, motion, attempt, active: 2, retained: 1, rtl: rtl, style: .off, time: time) { _ in }
        }
        view.present(at: time); view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap); images.append(bitmap)
        if let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] {
          try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to:
            URL(fileURLWithPath: directory).appendingPathComponent("tape-newline-transition-\(rtl ? "rtl" : "ltr")-\(stage).png"))
        }
      }
      var ink = 0, differences = 0
      for y in 0..<images[1].pixelsHigh { for x in 0..<images[1].pixelsWide {
        let before = try XCTUnwrap(images[1].colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        let after = try XCTUnwrap(images[2].colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        if before.redComponent + before.greenComponent + before.blueComponent > 0.2 { ink += 1 }
        if abs(before.redComponent - after.redComponent) + abs(before.greenComponent - after.greenComponent)
          + abs(before.blueComponent - after.blueComponent) > 0.01 { differences += 1 }
      } }
      XCTAssertGreaterThan(ink, 20)
      XCTAssertEqual(differences, 0, "Async session pruning cannot remove the prefix twice or restart its filler")
      XCTAssertFalse(window.isVisible)
    }
  }
}
