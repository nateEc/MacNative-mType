import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class TapePromptNewlineTests: XCTestCase {
  private let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .medium)
  private var nativeRowHeight: CGFloat { measuredRowHeight("abc↵") }
  private func measuredRowHeight(_ string: String) -> CGFloat {
    let storage = NSTextStorage(string: string, attributes: [.font: font])
    let manager = NSLayoutManager(), container = NSTextContainer(size: .init(width: 1000, height: 1000))
    container.lineFragmentPadding = 0
    storage.addLayoutManager(manager); manager.addTextContainer(container); manager.ensureLayout(for: container)
    return manager.usedRect(for: container).height + 12
  }
  private func fixture(_ rtl: Bool = false) -> (PromptRendering, [TapePromptWord]) {
    let string = rtl ? "אבג↵\nדהו↵\nזחט" : "abc↵\ndef↵\nghi"
    var text = AttributedString(string); text.foregroundColor = .gray
    return (.init(text: text, glyphCharacterOffsets: [0: 0, 1: 1, 2: 2, 3: 3, 4: 5, 5: 6, 6: 7, 7: 8, 8: 10, 9: 11, 10: 12]),
      [.init(index: 0, glyphID: 0, characters: 0..<4, newlineCharacterOffset: 3),
       .init(index: 1, glyphID: 4, characters: 5..<9, newlineCharacterOffset: 8),
       .init(index: 2, glyphID: 8, characters: 10..<13)])
  }
  private func config(_ coordinator: PromptCaretMotionCoordinator, attempt: UUID = UUID(),
    main: Int = 0, pace: Int = 4, rtl: Bool = false,
    mainStyle: TypingCaretStyle = .bar, paceStyle: TypingCaretStyle = .outline) -> PromptCaretNativeView.Configuration {
    var config = PromptCaretNativeView.Configuration(text: AttributedString(), mainOffset: nil, paceOffset: nil,
      mainStyle: mainStyle, paceStyle: paceStyle, font: font, lineSpacing: 0, rightToLeft: rtl,
      accent: .yellow, motion: .off, reducesMotion: false, frameRate: 60,
      attemptID: attempt, coordinator: coordinator, mainGlyphID: main)
    config.mainPresentation = { .init(isVisible: true, isBlinking: false) }
    config.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
      fromAfter: false, targetAfter: false, fraction: 1, targetGlyphID: pace) }
    return config
  }

  func testRealNativeSecondLineHasContinuousTapeIndentNotOrdinaryParagraphOrigin() throws {
    let coordinator = PromptCaretMotionCoordinator(), view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 160))
    defer { view.stop() }
    let (rendering, words) = fixture()
    view.configure(rendering: rendering, anchorCharacterIndex: 0, wordAnchorCharacterIndex: 0,
      mode: .word, margin: 0.25, smoothScroll: false, newlineWords: words,
      carets: config(coordinator), at: 0)
    let pace = try XCTUnwrap(coordinator.pace.visibleRect)
    XCTAssertEqual(pace.minX, 100 + ("abc" as NSString).size(withAttributes: [.font: font]).width, accuracy: 1e-7)
    XCTAssertEqual(pace.minY, nativeRowHeight, accuracy: 1e-7)
  }

  func testNewlineLayoutReportsFullNativeRowsForTheThreeLineViewport() throws {
    let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 160)); defer { view.stop() }
    let (rendering, words) = fixture()
    var reports: [TapePromptLayoutMetrics] = []
    view.configure(rendering: rendering, anchorCharacterIndex: 0, wordAnchorCharacterIndex: 0,
      mode: .letter, margin: 0.25, smoothScroll: false, newlineWords: words,
      onMetrics: { reports.append($0) }, carets: config(.init()), at: 0)
    XCTAssertTrue(reports.isEmpty, "Publishing SwiftUI sizing from configure must be deferred")
    RunLoop.main.run(until: Date().addingTimeInterval(0.005))
    let metrics = try XCTUnwrap(reports.last)
    XCTAssertEqual(metrics.contentHeight, metrics.rowHeight * 3, accuracy: 1e-7)
    XCTAssertEqual(metrics.rowHeight, nativeRowHeight, accuracy: 1e-7)
  }

  func testRTLRowsHaveContinuousIndentAndPositiveNativeDrawingCoordinates() throws {
    let coordinator = PromptCaretMotionCoordinator(), view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 160))
    defer { view.stop() }
    let (rendering, words) = fixture(true)
    view.configure(rendering: rendering, anchorCharacterIndex: 0, wordAnchorCharacterIndex: 0,
      mode: .word, margin: 0.25, smoothScroll: false, newlineWords: words,
      carets: config(coordinator, rtl: true), at: 0)
    let pace = try XCTUnwrap(coordinator.pace.visibleRect)
    let firstLineWidth = ("אבג" as NSString).size(withAttributes: [.font: font]).width
    let nextGlyphWidth = ("ד" as NSString).size(withAttributes: [.font: font]).width
    XCTAssertEqual(pace.minX, 300 - firstLineWidth - nextGlyphWidth, accuracy: 1e-7)
    XCTAssertEqual(pace.minY, nativeRowHeight, accuracy: 1e-7)
    let layout = TapeNewlineTextLayout()
    layout.configure(text: rendering.text, words: words, font: font, rightToLeft: true, resets: true)
    layout.request(layout.plan(at: 0, viewportWidth: 400), duration: 0, at: 0)
    for word in words { XCTAssertGreaterThanOrEqual(try XCTUnwrap(layout.wordRect(at: word.characters.lowerBound)).minX, 0) }
  }

  func testIncorrectReturnUpdatesTheFollowingIndentWithoutNewInputOrChangedText() throws {
    let coordinator = PromptCaretMotionCoordinator(), attempt = UUID()
    let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 160)); defer { view.stop() }
    let (rendering, originalWords) = fixture()
    var words = originalWords
    let configuration = config(coordinator, attempt: attempt)
    view.configure(rendering: rendering, anchorCharacterIndex: 0, wordAnchorCharacterIndex: 0,
      mode: .word, margin: 0.25, smoothScroll: false, newlineWords: words, carets: configuration, at: 0)
    let original = try XCTUnwrap(coordinator.pace.visibleRect).minX
    words[0].incorrectNewline = true
    view.configure(rendering: rendering, anchorCharacterIndex: 0, wordAnchorCharacterIndex: 0,
      mode: .word, margin: 0.25, smoothScroll: false, newlineWords: words, carets: configuration, at: 1)
    view.present(at: 1)
    XCTAssertEqual(try XCTUnwrap(coordinator.pace.visibleRect).minX - original,
      ("↵" as NSString).size(withAttributes: [.font: font]).width, accuracy: 1e-7)
    XCTAssertEqual(try XCTUnwrap(coordinator.main.visibleRect).minX, 100)
    XCTAssertEqual(view.accessibilityLabel(), String(rendering.text.characters))
  }

  func testConsecutiveReturnOnlyWordsKeepPositiveGlyphBoxesWithoutAccumulatingIndent() throws {
    let layout = TapeNewlineTextLayout()
    let words: [TapePromptWord] = [.init(index: 0, glyphID: 0, characters: 0..<1, newlineCharacterOffset: 0),
      .init(index: 1, glyphID: 1, characters: 2..<3, newlineCharacterOffset: 2),
      .init(index: 2, glyphID: 2, characters: 4..<5)]
    layout.configure(text: AttributedString("↵\n↵\nz"), words: words, font: font, rightToLeft: false, resets: true)
    layout.request(layout.plan(at: 0, viewportWidth: 400), duration: 0, at: 0)
    XCTAssertEqual(layout.plan(at: 4, viewportWidth: 400).beforeActive, 0)
    let rowHeight = max(measuredRowHeight("↵"), measuredRowHeight("z"))
    for (row, offset) in [0, 2, 4].enumerated() {
      let rect = try XCTUnwrap(layout.glyphRect(at: offset, minimumOffset: offset))
      XCTAssertGreaterThan(rect.width, 0); XCTAssertEqual(rect.minX, 0)
      XCTAssertEqual(rect.minY, CGFloat(row) * rowHeight)
    }
  }

  func testExtraReturnSymbolDoesNotCreateAnUnownedRow() throws {
    let layout = TapeNewlineTextLayout()
    let words: [TapePromptWord] = [.init(index: 0, glyphID: 0, characters: 0..<5, newlineCharacterOffset: 4),
      .init(index: 1, glyphID: 1, characters: 6..<8)]
    layout.configure(text: AttributedString("ab↵x↵\nyz"), words: words, font: font, rightToLeft: false, resets: true)
    layout.request(layout.plan(at: 0, viewportWidth: 400), duration: 0, at: 0)
    XCTAssertEqual(try XCTUnwrap(layout.glyphRect(at: 2, minimumOffset: 2)).minY, 0)
    let next = try XCTUnwrap(layout.glyphRect(at: 6, minimumOffset: 6))
    XCTAssertEqual(next.minY, nativeRowHeight)
    XCTAssertEqual(next.minX, ("ab↵x" as NSString).size(withAttributes: [.font: font]).width, accuracy: 1e-7)
    XCTAssertEqual(layout.metrics.contentHeight, nativeRowHeight * 2)
  }

  func testGraphemeOffsetsPreserveEmojiAndCombiningSequencesAcrossOwnedRows() throws {
    let layout = TapeNewlineTextLayout()
    let words: [TapePromptWord] = [.init(index: 0, glyphID: 100, characters: 0..<3, newlineCharacterOffset: 2),
      .init(index: 1, glyphID: 200, characters: 4..<6)]
    layout.configure(text: AttributedString("👩🏽‍💻é↵\nאב"), words: words, font: font, rightToLeft: false, resets: true)
    layout.request(layout.plan(at: 0, viewportWidth: 400), duration: 0, at: 0)
    let emoji = try XCTUnwrap(layout.glyphRect(at: 0, minimumOffset: 0))
    let accent = try XCTUnwrap(layout.glyphRect(at: 1, minimumOffset: 1))
    let next = try XCTUnwrap(layout.wordRect(at: 4))
    XCTAssertGreaterThan(emoji.width, 0); XCTAssertGreaterThan(accent.width, 0)
    XCTAssertEqual(accent.minX, emoji.maxX, accuracy: 1e-7)
    XCTAssertEqual(next.minX, ("👩🏽‍💻é" as NSString).size(withAttributes: [.font: font]).width, accuracy: 1e-7)
    XCTAssertEqual(next.minY, layout.metrics.rowHeight)
    XCTAssertNil(layout.glyphRect(at: 3, minimumOffset: 3), "Structural LF must not become an input glyph")
    XCTAssertTrue(layout.direction(at: 4, perGlyph: false, fallback: false))
  }

  func testChangedFillerMovesOnlyOnPresentedFramesUsingTheExistingTapeCurve() throws {
    for rtl in [false, true] {
      let layout = TapeNewlineTextLayout(), (rendering, words) = fixture()
      layout.configure(text: rendering.text, words: words, font: font, rightToLeft: rtl, resets: true)
      layout.request(layout.plan(at: 0, viewportWidth: 400), duration: 0, at: 0)
      let old = try XCTUnwrap(layout.wordRect(at: 5))
      let oldRelative = rtl ? layout.leadingEdge - old.maxX : old.minX
      let updated: [TapePromptWord] = [.init(index: 0, glyphID: 0, characters: 0..<5, newlineCharacterOffset: 4),
        .init(index: 1, glyphID: 4, characters: 6..<10, newlineCharacterOffset: 9),
        .init(index: 2, glyphID: 8, characters: 11..<14)]
      layout.configure(text: AttributedString("abcx↵\ndef↵\nghi"), words: updated, font: font, rightToLeft: rtl, resets: false)
      layout.request(layout.plan(at: 0, viewportWidth: 400), duration: 0.125, at: 1)
      let delta = ("x" as NSString).size(withAttributes: [.font: font]).width
      for time in [1.0, 1.05, 1.113] {
        layout.sample(at: time)
        let rect = try XCTUnwrap(layout.wordRect(at: 6))
        let actual = rtl ? layout.leadingEdge - rect.maxX : rect.minX
        let t = time == 1 ? 0 : min(1, (time - 1 + PromptLineScrollMotion.autoplayLead) / 0.125)
        XCTAssertEqual(actual, oldRelative + delta * PromptCaretChannel.Curve.position.value(t), accuracy: 1e-7)
      }
      XCTAssertFalse(layout.isAnimating)
    }
  }

  func testLetterScrollUsesCumulativePreviousRowsPlusCurrentWordAdvance() throws {
    let coordinator = PromptCaretMotionCoordinator(), view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 160))
    defer { view.stop() }
    let (rendering, words) = fixture()
    view.configure(rendering: rendering, anchorCharacterIndex: 6, wordAnchorCharacterIndex: 5,
      mode: .letter, margin: 0.25, smoothScroll: false, newlineWords: words,
      carets: config(coordinator, main: 5, pace: 4), at: 0)
    XCTAssertEqual(coordinator.wordsTapeMargin, -("abcd" as NSString).size(withAttributes: [.font: font]).width, accuracy: 1e-7)
    XCTAssertEqual(try XCTUnwrap(coordinator.main.visibleRect).minX, 100)
    XCTAssertEqual(try XCTUnwrap(coordinator.pace.visibleRect).minX,
      100 - ("d" as NSString).size(withAttributes: [.font: font]).width, accuracy: 1e-7)
    XCTAssertEqual(try XCTUnwrap(coordinator.main.visibleRect).minY, nativeRowHeight)
  }

  func testMetricsAreCoalescedAndCancelledAcrossStopAndRestart() {
    let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 160)); defer { view.stop() }
    let (rendering, words) = fixture()
    var reports: [TapePromptLayoutMetrics] = []
    func update(_ configuration: PromptCaretNativeView.Configuration) {
      view.configure(rendering: rendering, anchorCharacterIndex: 0, wordAnchorCharacterIndex: 0,
        mode: .word, margin: 0.25, smoothScroll: false, newlineWords: words,
        onMetrics: { reports.append($0) }, carets: configuration, at: 0)
    }
    update(config(.init())); update(config(.init())); view.stop()
    RunLoop.main.run(until: Date().addingTimeInterval(0.005)); XCTAssertTrue(reports.isEmpty)
    let configuration = config(.init())
    update(configuration); update(configuration); view.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.005)); XCTAssertEqual(reports.count, 1)
    update(configuration)
    RunLoop.main.run(until: Date().addingTimeInterval(0.005)); XCTAssertEqual(reports.count, 1)
  }

  func testRealLTRAndRTLPixelsAreDrawnOnAllRowsWithoutShowingAWindow() throws {
    for rtl in [false, true] {
      let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 160),
        styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
      let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 160))
      view.layer?.backgroundColor = NSColor.black.cgColor
      window.contentView = view
      defer { view.stop(); window.contentView = nil; window.close() }
      let (rendering, words) = fixture(rtl), coordinator = PromptCaretMotionCoordinator(), attempt = UUID()
      let configuration = config(coordinator, attempt: attempt, rtl: rtl, mainStyle: .off, paceStyle: .off)
      for moved in [false, true] {
        view.configure(rendering: rendering, anchorCharacterIndex: moved ? 5 : 0, wordAnchorCharacterIndex: moved ? 5 : 0,
          mode: .word, margin: 0.25, smoothScroll: false, newlineWords: words, carets: configuration, at: moved ? 1 : 0)
        view.present(at: moved ? 1 : 0); view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        for row in 0..<3 {
          var ink = 0
          let scale = CGFloat(bitmap.pixelsHigh) / view.bounds.height
          for y in Int(CGFloat(row) * nativeRowHeight * scale)..<Int(CGFloat(row + 1) * nativeRowHeight * scale) {
            for x in 0..<bitmap.pixelsWide {
              if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                color.alphaComponent > 0.1, color.redComponent + color.greenComponent + color.blueComponent > 0.2 { ink += 1 }
            }
          }
          XCTAssertGreaterThan(ink, 10, "\(rtl ? "RTL" : "LTR") row \(row), moved \(moved): native text must not be clipped")
        }
        if let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] {
          try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to:
            URL(fileURLWithPath: directory).appendingPathComponent("tape-newlines-\(rtl ? "rtl" : "ltr")-\(moved ? "moved" : "initial").png"))
        }
        XCTAssertFalse(window.isVisible)
      }
    }
  }

  func testRendererUsesVerticalRetirementWithoutSingleLineOverflowOrRemovingProductionFallback() throws {
    let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 80, height: 160)); defer { view.stop() }
    let (rendering, words) = fixture(), coordinator = PromptCaretMotionCoordinator(), attempt = UUID()
    var retirements: [PromptWordRetirement] = []
    for active in [0, 5, 10] {
      view.configure(rendering: rendering, anchorCharacterIndex: active, wordAnchorCharacterIndex: active,
        mode: .word, margin: 0.25, smoothScroll: false,
        retirement: .init(attemptID: attempt, activeWordID: active == 0 ? 0 : active == 5 ? 4 : 8,
          characterOffsets: rendering.glyphCharacterOffsets, smoothScroll: false, reducesMotion: false,
          words: words.map { .init(index: $0.index, glyphID: $0.glyphID) }, firstRetainedWordIndex: 0,
          onRetire: { retirements.append($0) }), newlineWords: words, carets: config(coordinator, attempt: attempt), at: Double(active))
      view.present(at: Double(active))
      RunLoop.main.run(until: Date().addingTimeInterval(0.003))
      if active < 10 { XCTAssertTrue(retirements.isEmpty, "First line must not retire via single-line overflow") }
    }
    XCTAssertEqual(retirements.map(\.firstRetainedWordIndex), [1], "Only the vertical owner's older row retires")
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let app = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    XCTAssertTrue(app.contains("settings.practiceTapeMode != .off && !session.hasPracticeNewlineContent"))
  }
}
