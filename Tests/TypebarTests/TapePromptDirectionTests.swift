import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class TapePromptDirectionTests: XCTestCase {
  private let font = NSFont.systemFont(ofSize: 28)
  private func rendering(_ string: String) -> PromptRendering {
    var text = AttributedString(string); text.foregroundColor = .gray
    return .init(text: text, glyphCharacterOffsets: Dictionary(uniqueKeysWithValues: string.enumerated().map { ($0.offset, $0.offset) }))
  }
  private func configuration(_ coordinator: PromptCaretMotionCoordinator, attempt: UUID = UUID(),
    rtl: Bool = true, glyph: Int = 0, style: TypingCaretStyle = .bar) -> PromptCaretNativeView.Configuration {
    .init(text: AttributedString(), mainOffset: nil, paceOffset: nil, mainStyle: style, paceStyle: .off,
      font: font, lineSpacing: 0, rightToLeft: rtl, accent: .yellow, motion: .off,
      reducesMotion: false, frameRate: 60, attemptID: attempt, coordinator: coordinator, mainGlyphID: glyph)
  }
  private func configure(_ view: TapePromptNativeView, _ config: PromptCaretNativeView.Configuration,
    offset: Int = 0, word: Int = 0, mode: PracticeTapeMode = .letter, at time: Double = 0) {
    view.configure(rendering: rendering("אבג דהו"), anchorCharacterIndex: offset, wordAnchorCharacterIndex: word,
      wordStartCharacterOffsets: [0: 0, 1: 0, 2: 0, 4: 4, 5: 4, 6: 4],
      mode: mode, margin: 0.25, smoothScroll: true, carets: config, at: time)
  }

  func testRTLLetterMainLocksItsTrailingEdgeToTheRightHandMarginForAllStyles() throws {
    for style: TypingCaretStyle in [.bar, .block, .outline, .underline] {
      let coordinator = PromptCaretMotionCoordinator(), view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 60))
      defer { view.stop() }
      configure(view, configuration(coordinator, style: style))
      let rect = try XCTUnwrap(coordinator.main.position)
      XCTAssertEqual(rect.maxX, 300, accuracy: 1e-7)
      XCTAssertEqual(PromptCaretPlacementPolicy.horizontalAnchor(for: rect, style: .bar, isRightToLeft: true), 300, accuracy: 1e-7)
    }
  }

  func testRTLInputScrollsWordsRightwardWhileMainStaysLockedAndBackwardInputReversesIt() throws {
    let coordinator = PromptCaretMotionCoordinator(), attempt = UUID()
    let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 60)); defer { view.stop() }
    configure(view, configuration(coordinator, attempt: attempt))
    configure(view, configuration(coordinator, attempt: attempt, glyph: 1), offset: 1, at: 1)
    view.present(at: 1.2)
    XCTAssertGreaterThan(coordinator.wordsTapeMargin, 0)
    XCTAssertEqual(coordinator.wordsTapeMargin, ("א" as NSString).size(withAttributes: [.font: font]).width, accuracy: 1)
    XCTAssertEqual(try XCTUnwrap(coordinator.main.position).maxX, 300, accuracy: 1e-7)
    configure(view, configuration(coordinator, attempt: attempt), at: 2)
    view.present(at: 2.2)
    XCTAssertEqual(coordinator.wordsTapeMargin, 0, accuracy: 1e-7)
  }

  func testRTLWordTapeMovesMainLeftWithinTheWordAndOnlyScrollsAtWordBoundary() throws {
    let coordinator = PromptCaretMotionCoordinator(), attempt = UUID()
    let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 60)); defer { view.stop() }
    configure(view, configuration(coordinator, attempt: attempt), mode: .word)
    configure(view, configuration(coordinator, attempt: attempt, glyph: 1), mode: .word, at: 1)
    view.present(at: 1.2)
    XCTAssertEqual(coordinator.wordsTapeMargin, 0, accuracy: 1e-7)
    XCTAssertLessThan(try XCTUnwrap(coordinator.main.position).maxX, 300)
    configure(view, configuration(coordinator, attempt: attempt, glyph: 4), offset: 4, word: 4, mode: .word, at: 2)
    view.present(at: 2.2)
    XCTAssertGreaterThan(coordinator.wordsTapeMargin, 0)
    XCTAssertEqual(try XCTUnwrap(coordinator.main.position).maxX, 300, accuracy: 1e-7)
  }

  func testProductionDoesNotSilentlyDisableTapeForRightToLeftContent() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let app = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    let start = try XCTUnwrap(app.range(of: "private var usesTapePractice: Bool"))
    let end = try XCTUnwrap(app.range(of: "private var showsAllPracticeLines: Bool"))
    XCTAssertFalse(app[start.lowerBound..<end.lowerBound].contains("containsRightToLeftPromptRun"))
    XCTAssertTrue(app.contains("carets: makeSpecialPromptCaretConfiguration(rightToLeft: session.configuration.usesRightToLeftPrompt)"))
    XCTAssertTrue(app.contains("makeSpecialPromptCaretConfiguration(rightToLeft: Bool = false)"), "ASL and Choo retain their own default direction")
  }

  func testRTLPreparedGlyphRangeMeasuresEachLetterWithoutTheAdjacentGlyph() {
    let storage = TapePromptTextStorage.prepare(AttributedString("אבג דהו"), font: font, rightToLeft: true)
    let manager = NSLayoutManager(), container = NSTextContainer(size: .init(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
    container.lineFragmentPadding = 0; manager.addTextContainer(container); storage.addLayoutManager(manager)
    manager.ensureLayout(for: container)
    var total: CGFloat = 0
    for index in 0..<7 {
      let range = manager.glyphRange(forCharacterRange: .init(location: index, length: 1), actualCharacterRange: nil)
      let rect = TapePromptTextStorage.advanceRect(range, manager: manager, container: container)
      XCTAssertTrue(rect.minX.isFinite); XCTAssertGreaterThan(rect.width, 0)
      let expected = index == 0 ? ("א" as NSString).size(withAttributes: [.font: font]).width
        : manager.location(forGlyphAt: index - 1).x - manager.location(forGlyphAt: index).x
      XCTAssertEqual(rect.width, expected, accuracy: 1e-7)
      total += rect.width
    }
    XCTAssertEqual(total, manager.usedRect(for: container).width, accuracy: 1e-7)
    let range = manager.glyphRange(forCharacterRange: .init(location: 0, length: 1), actualCharacterRange: nil)
    XCTAssertNotEqual(manager.boundingRect(forGlyphRange: range, in: container).width,
      TapePromptTextStorage.advanceRect(range, manager: manager, container: container).width)
  }

  func testMixedWordsChooseTheirOwnLockedEdgeIndependentlyOfTestFlow() throws {
    for rtl in [false, true] { for mode: PracticeTapeMode in [.letter, .word] {
      let coordinator = PromptCaretMotionCoordinator(), attempt = UUID()
      let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 60)); defer { view.stop() }
      func update(_ glyph: Int, word: Int, at time: Double) {
        view.configure(rendering: rendering("abc אבג"), anchorCharacterIndex: mode == .word ? word : glyph,
          wordAnchorCharacterIndex: word, wordStartCharacterOffsets: [0: 0, 1: 0, 2: 0, 4: 4, 5: 4, 6: 4],
          mode: mode, margin: 0.25, smoothScroll: false,
          carets: configuration(coordinator, attempt: attempt, rtl: rtl, glyph: glyph), at: time)
        view.present(at: time)
      }
      update(0, word: 0, at: 0)
      XCTAssertEqual(try XCTUnwrap(coordinator.main.position).minX, 100, accuracy: 1e-7)
      update(1, word: 0, at: 1)
      if mode == .letter { XCTAssertEqual(try XCTUnwrap(coordinator.main.position).minX, 100, accuracy: 1e-7) }
      else { XCTAssertGreaterThan(try XCTUnwrap(coordinator.main.position).minX, 100) }
      update(4, word: 4, at: 2)
      XCTAssertEqual(try XCTUnwrap(coordinator.main.position).maxX, 300, accuracy: 1e-7)
      update(5, word: 4, at: 3)
      if mode == .letter { XCTAssertEqual(try XCTUnwrap(coordinator.main.position).maxX, 300, accuracy: 1e-7) }
      else { XCTAssertLessThan(try XCTUnwrap(coordinator.main.position).maxX, 300) }
    } }
  }

  func testCustomZenAndPolyglotPerGlyphDirectionDoesNotReuseWholeWordDirection() throws {
    let coordinator = PromptCaretMotionCoordinator(), attempt = UUID()
    let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 60)); defer { view.stop() }
    for perGlyph in [false, true] {
      view.configure(rendering: rendering("אa"), anchorCharacterIndex: 1, wordAnchorCharacterIndex: 0,
        wordStartCharacterOffsets: [0: 0, 1: 0], checksDirectionPerGlyph: perGlyph,
        mode: .letter, margin: 0.25, smoothScroll: false,
        carets: configuration(coordinator, attempt: attempt, glyph: 1), at: 1)
      view.present(at: 1)
      let rect = try XCTUnwrap(coordinator.main.position)
      if perGlyph { XCTAssertEqual(rect.minX, 100, accuracy: 1e-7) }
      else { XCTAssertEqual(rect.maxX, 300, accuracy: 1e-7) }
    }
  }

  func testPaceAfterEdgeAndPaintFollowTargetWordDirectionNotTestDirection() throws {
    for style: TypingCaretStyle in [.bar, .block, .outline, .underline] {
      var positions: [CGRect] = []
      for after in [false, true] {
        let coordinator = PromptCaretMotionCoordinator()
        let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 60)); defer { view.stop() }
        var config = PromptCaretNativeView.Configuration(text: AttributedString(), mainOffset: nil, paceOffset: nil,
          mainStyle: .off, paceStyle: style, font: font, lineSpacing: 0, rightToLeft: false,
          accent: .yellow, motion: .off, reducesMotion: false, frameRate: 60, attemptID: UUID(), coordinator: coordinator)
        config.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
          fromAfter: false, targetAfter: after, fraction: 1, targetGlyphID: 4) }
        view.configure(rendering: rendering("abc אבג"), anchorCharacterIndex: 0, wordAnchorCharacterIndex: 0,
          wordStartCharacterOffsets: [0: 0, 1: 0, 2: 0, 4: 4, 5: 4, 6: 4],
          mode: .letter, margin: 0.25, smoothScroll: false, carets: config, at: 0)
        let rect = try XCTUnwrap(coordinator.pace.visibleRect); positions.append(rect)
        let caret = try XCTUnwrap(view.subviews.compactMap { $0 as? PromptCaretNativeView }.first)
        let host = try XCTUnwrap(caret.subviews.compactMap { $0 as? NSHostingView<PromptCaretMarkerView> }.first)
        XCTAssertEqual(host.frame.midX,
          PromptCaretPlacementPolicy.horizontalAnchor(for: rect, style: style, isRightToLeft: true), accuracy: 1e-7)
      }
      let shift = style == .bar ? positions[0].width : (" " as NSString).size(withAttributes: [.font: font]).width
      XCTAssertEqual(positions[1].minX, positions[0].minX - shift, accuracy: 1e-7)
    }
  }

  func testSameAttemptDirectionChangeAndNewAttemptResetOldHorizontalCorrections() throws {
    let coordinator = PromptCaretMotionCoordinator(), attempt = UUID()
    let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 60)); defer { view.stop() }
    configure(view, configuration(coordinator, attempt: attempt, rtl: false))
    configure(view, configuration(coordinator, attempt: attempt, rtl: false, glyph: 1), offset: 1, at: 1)
    view.present(at: 1.05)
    XCTAssertLessThan(coordinator.wordsTapeMargin, 0)
    configure(view, configuration(coordinator, attempt: attempt, glyph: 1), offset: 1, at: 1.05)
    XCTAssertGreaterThan(coordinator.wordsTapeMargin, 0)
    XCTAssertFalse(coordinator.isAnimatingTape)
    configure(view, configuration(coordinator), at: 2)
    view.present(at: 3)
    XCTAssertEqual(coordinator.wordsTapeMargin, 0)
    XCTAssertEqual(coordinator.pace.cumulativeTapeCorrection, 0)
  }

  func testRealHebrewSessionTapeDoesNotMutateInputPromptAttemptOrReplay() throws {
    var session = TypingSession(configuration: .words(3, language: .hebrew), prompt: "אבג דהו זחט")
    let time = Date(timeIntervalSinceReferenceDate: 913_100_000)
    session.insertBatch("אבג ", at: time)
    let attempt = session.automaticInputAttemptID, typed = session.typed, prompt = session.prompt
    let glyphs = session.promptGlyphs
    let rendered = PromptRendering.make(glyphs: glyphs, indices: PromptGlyphLayout.indices(
      glyphs: glyphs, words: session.promptWordPresentations, hideExtraLetters: false)) { _, glyph in AttributedString(String(glyph.character)) }
    let coordinator = PromptCaretMotionCoordinator()
    let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 60)); defer { view.stop() }
    view.configure(rendering: rendered, anchorCharacterIndex: PracticeTapePolicy.anchorCharacterIndex(session: session, rendering: rendered, mode: .letter),
      wordAnchorCharacterIndex: PracticeTapePolicy.anchorCharacterIndex(session: session, rendering: rendered, mode: .word),
      wordStartCharacterOffsets: PracticeTapePolicy.wordStartCharacterOffsets(session: session, rendering: rendered),
      mode: .letter, margin: 0.25, smoothScroll: true,
      carets: configuration(coordinator, attempt: attempt, glyph: session.promptCaretGlyphIndex ?? 0), at: 0)
    view.present(at: 1)
    XCTAssertGreaterThan(coordinator.wordsTapeMargin, 0)
    XCTAssertEqual(session.automaticInputAttemptID, attempt); XCTAssertEqual(session.typed, typed)
    XCTAssertEqual(session.prompt, prompt); XCTAssertEqual(session.firstRetainedPromptWordIndex, 0)
    session.insertBatch("דהו זחט", at: time.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: result.elapsedDuration), session.typed)
  }

  func testActualRTLTapeRendersInitialMotionAndWordPositionWithoutShowingWindow() throws {
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 70), styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
    let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 70)); window.contentView = view
    view.layer?.backgroundColor = NSColor.white.cgColor
    defer { view.stop(); window.contentView = nil; window.close() }
    view.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    let coordinator = PromptCaretMotionCoordinator(), attempt = UUID()
    var images: [Data] = []
    for (name, mode, offset, glyph, time): (String, PracticeTapeMode, Int, Int, Double) in [
      ("initial", .letter, 0, 0, 0), ("moving", .letter, 1, 1, 1.05), ("word", .word, 0, 1, 2)] {
      configure(view, configuration(coordinator, attempt: attempt, glyph: glyph), offset: offset, mode: mode, at: floor(time))
      view.present(at: time); view.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds)); view.cacheDisplay(in: view.bounds, to: bitmap)
      let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:])); images.append(data)
      var gray = 0
      for x in 0..<bitmap.pixelsWide { for y in 0..<bitmap.pixelsHigh {
        if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.8,
          color.redComponent > 0.2, color.redComponent < 0.8,
          abs(color.redComponent - color.greenComponent) < 0.04, abs(color.greenComponent - color.blueComponent) < 0.04 { gray += 1 }
      } }
      XCTAssertGreaterThan(gray, 10, "Actual native text must be drawn")
      if let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] {
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("rtl-tape-\(name).png"))
      }
    }
    XCTAssertNotEqual(images[0], images[1]); XCTAssertNotEqual(images[0], images[2])
    XCTAssertFalse(window.isVisible)
  }

  func testAdjacentOppositeDirectionWordsRemainInLogicalTapeOrder() {
    for rtl in [false, true] {
      let string = rtl ? "abc def אבג" : "אבג דהו abc"
      let coordinator = PromptCaretMotionCoordinator(), attempt = UUID()
      let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 60)); defer { view.stop() }
      var previous: CGFloat = -1
      for (time, offset) in [0, 4, 8].enumerated() {
        view.configure(rendering: rendering(string), anchorCharacterIndex: offset, wordAnchorCharacterIndex: offset,
          wordStartCharacterOffsets: [0: 0, 1: 0, 2: 0, 4: 4, 5: 4, 6: 4, 8: 8, 9: 8, 10: 8],
          mode: .word, margin: 0.25, smoothScroll: false,
          carets: configuration(coordinator, attempt: attempt, rtl: rtl, glyph: offset), at: Double(time))
        view.present(at: Double(time))
        let progress = coordinator.wordsTapeMargin * (rtl ? 1 : -1)
        XCTAssertGreaterThan(progress, previous, "Words must advance in source order, not one merged opposite-direction paragraph run")
        previous = progress
      }
    }
  }
}
