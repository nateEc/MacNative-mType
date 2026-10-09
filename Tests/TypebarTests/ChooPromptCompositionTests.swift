import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class ChooPromptCompositionTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 916_600_000)
  private let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
  private let palette = ChooGlyphPalette(theme: AppTheme.paper.resolvedTheme,
    flipsCompletionAndFuture: false, usesColorfulMode: false)

  func testProductionProjectedChooReportsItsOwnViewportRows() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    XCTAssertTrue(source.contains("ChooLayerView.viewportHeight("), "Choo must measure the same independent-layer layout as its displayed prompt")
    XCTAssertTrue(source.contains("|| renderedPrompt.compositionTextMap != nil"), "Projected Choo must not retain the fixed 184-point viewport")
  }

  private func render(_ session: TypingSession, _ marked: String = "",
    style: CompositionDisplayStyle = .replace) throws -> PromptRendering {
    let value = try XCTUnwrap(PromptCompositionPresentation(session: session, composition: marked, style: style))
    return value.render { index, glyph, cell in
      let plan = PromptControlCharacterPresentation.plan(for: glyph, style: .both, isZen: value.isZen,
        compositionReplacement: cell?.text, isEmptyWordPlaceholder: index == value.emptyPlaceholderIndex)
      var text = AttributedString(plan.text)
      text.foregroundColor = glyph.state == .hidden ? .clear : glyph.state == .correct ? .green : .orange
      if cell != nil { text.underlineStyle = .single; text.appKit.underlineColor = .magenta }
      if cell == nil, let hint = plan.hint {
        var tail = AttributedString(hint); tail.baselineOffset = -12; tail.foregroundColor = .red
        text += tail
      }
      return text
    }
  }
  private func make(_ session: TypingSession, rendering: PromptRendering, width: CGFloat = 400) -> ChooLayerView {
    let ids = PromptGlyphLayout.indices(glyphs: session.promptGlyphs, words: session.promptWordPresentations,
      hideExtraLetters: session.configuration.rules.hideExtraLetters)
    let glyphs = ids.map { session.promptGlyphs[$0] }
    let view = ChooLayerView(frame: .init(x: 0, y: 0, width: width,
      height: ChooLayerView.measure(glyphs: glyphs, font: font, width: width, glyphIDs: ids, rendering: rendering)))
    view.configure(glyphs: glyphs, font: font, palette: palette, animates: true,
      frameRate: 30, glyphIDs: ids, rendering: rendering)
    return view
  }
  private func layers(_ view: ChooLayerView) -> [CATextLayer] {
    (view.layer?.sublayers?.compactMap { $0 as? CATextLayer }.filter { $0.name != "chooHint" } ?? [])
      .sorted { $0.frame.minY == $1.frame.minY ? $0.frame.minX < $1.frame.minX : $0.frame.minY < $1.frame.minY }
  }
  private func allocation(_ layer: CATextLayer) throws -> CGRect {
    var rect = layer.frame
    rect.size.width = max(1, ceil(try XCTUnwrap(layer.string as? NSAttributedString).size().width))
    return rect
  }
  private func config(_ session: TypingSession, motion: PromptCaretMotionCoordinator)
    -> PromptCaretNativeView.Configuration {
    .init(text: AttributedString(), mainOffset: nil, paceOffset: nil, mainStyle: .bar, paceStyle: .bar,
      font: font, lineSpacing: 12, rightToLeft: false, accent: .blue, motion: .off, reducesMotion: true,
      frameRate: 30, attemptID: session.automaticInputAttemptID, coordinator: motion,
      mainGlyphID: session.promptCaretGlyphIndex, automaticallyPresents: false)
  }
  private func present(_ view: ChooLayerView, time: TimeInterval = 0) throws {
    let caret = try XCTUnwrap(view.subviews.compactMap { $0 as? PromptCaretNativeView }.first)
    caret.layout(); caret.present(at: time)
  }

  func testProjectedViewportUsesActualFontRowsAndZenReservesTwoRows() throws {
    let session = TypingSession(configuration: .words(2), prompt: "ab cd")
    let rendering = try render(session), ids = Array(session.promptGlyphs.indices)
    for size in [14.0, 28.0, 56.0] {
      let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
      let row = ceil(font.ascender - font.descender + font.leading) + 12
      for count in [2, 3] {
        let height = try XCTUnwrap(ChooLayerView.viewportHeight(glyphs: session.promptGlyphs,
          font: font, width: 400, glyphIDs: ids, rendering: rendering, lineCount: count))
        XCTAssertEqual(height, (row * CGFloat(count)).rounded(.up))
      }
    }
  }

  func testProjectedViewportMatchesRealLayerRowsAfterMarkedOverflowAndResize() throws {
    var session = TypingSession(configuration: .words(4), prompt: "ab cd ef gh")
    session.insertBatch("a", at: start)
    let rendering = try render(session, "bXYZ"), map = try XCTUnwrap(rendering.compositionTextMap)
    for width in [CGFloat(65), 120, 400] {
      let view = make(session, rendering: rendering, width: width); defer { view.stopCarets() }
      let values = layers(view), cells = map.fieldRuns.flatMap(\.cells)
      XCTAssertEqual(values.count, cells.count)
      let frames = Dictionary(uniqueKeysWithValues: zip(cells.map(\.id), values.map(\.frame)))
      let expected = PromptViewportLayout.height(forRowHeights: ASLPromptLineGeometry(frames: frames).rowHeights, lineCount: 3)
      XCTAssertEqual(ChooLayerView.viewportHeight(glyphs: session.promptGlyphs, font: font, width: width,
        glyphIDs: Array(session.promptGlyphs.indices), rendering: rendering, lineCount: 3), expected)
    }
    XCTAssertEqual(session.typed, "a", "Viewport measurement must not accept marked input")
  }

  func testViewportDoesNotInventRowsForLegacyOrInvalidGeometry() throws {
    let session = TypingSession(configuration: .words(2), prompt: "ab cd"), rendering = try render(session)
    let legacy = PromptRendering(text: rendering.text, glyphCharacterOffsets: rendering.glyphCharacterOffsets)
    let ids = Array(session.promptGlyphs.indices)
    XCTAssertNil(ChooLayerView.viewportHeight(glyphs: session.promptGlyphs, font: font, width: 400,
      glyphIDs: ids, rendering: legacy, lineCount: 3))
    for width in [CGFloat.zero, -.infinity, .infinity, .nan] {
      XCTAssertNil(ChooLayerView.viewportHeight(glyphs: session.promptGlyphs, font: font, width: width,
        glyphIDs: ids, rendering: rendering, lineCount: 3))
    }
    XCTAssertNil(ChooLayerView.viewportHeight(glyphs: session.promptGlyphs, font: font, width: 400,
      glyphIDs: ids, rendering: rendering, lineCount: 0))
  }

  func testMountedChooPreferenceReachesTheRealScrollViewportAfterFontAndModeChange() throws {
    let session = TypingSession(configuration: .words(2), prompt: "ab cd"), rendering = try render(session)
    func root(size: CGFloat, count: Int) -> some View {
      let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
      return PracticePromptViewport(text: rendering.text, font: font, lineSpacing: 12,
        isRightToLeft: false, lineCount: count, measuresTextRows: false, measuresCustomRows: true) {
          ChooPracticePrompt(glyphs: session.promptGlyphs, rendering: rendering, font: font, palette: self.palette,
            isEnabled: true, reducesMotion: true, ignoresSystemReducedMotion: false,
            glyphIDs: Array(session.promptGlyphs.indices), viewportLineCount: count)
        }.frame(width: 360)
    }
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let host = NSHostingView(rootView: root(size: 14, count: 3))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 360, height: 400),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { window.close() }
    for (size, count) in [(CGFloat(14), 3), (56, 2)] {
      host.rootView = root(size: size, count: count)
      host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.15)); host.layoutSubtreeIfNeeded()
      let scroll = try XCTUnwrap(descendants(host).compactMap { $0 as? NSScrollView }.first)
      let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
      let expected = (ceil(font.ascender - font.descender + font.leading) + 12) * CGFloat(count)
      XCTAssertEqual(scroll.bounds.height, expected, accuracy: 1)
      XCTAssertFalse(window.isVisible)
      XCTAssertNotNil(descendants(host).first { $0 is ChooLayerView })
    }
  }

  func testOverflowMainCaretUsesTheLastVirtualCellAndPaceUsesCanonicalTarget() throws {
    var session = TypingSession(configuration: .words(2), prompt: "ab cd")
    session.insertBatch("a", at: start)
    let rendering = try render(session, "bXYZ"), map = try XCTUnwrap(rendering.compositionTextMap)
    let anchor = try XCTUnwrap(map.caret); XCTAssertTrue(anchor.after); XCTAssertLessThan(anchor.cellID, 0)
    let view = make(session, rendering: rendering); defer { view.stopCarets() }
    let cells = map.fieldRuns.flatMap(\.cells), values = layers(view)
    XCTAssertEqual(values.count, cells.count)
    let last = try allocation(values[try XCTUnwrap(cells.firstIndex { $0.id == anchor.cellID })])
    let target = try allocation(values[try XCTUnwrap(cells.firstIndex { $0.id == 3 })])
    let motion = PromptCaretMotionCoordinator(); var configuration = config(session, motion: motion)
    configuration.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
      fromAfter: false, targetAfter: false, fraction: 1, sequence: 1, targetGlyphID: 3) }
    view.configureCarets(configuration, glyphIDs: Array(session.promptGlyphs.indices))
    try present(view)
    XCTAssertEqual(try XCTUnwrap(motion.main.position).minX, last.maxX, accuracy: 0.1)
    XCTAssertEqual(motion.pace.position, target)
    XCTAssertEqual(session.typed, "a")
  }

  func testTargetReturnBreaksAfterTheWholeFieldIncludingRealExtras() throws {
    var session = TypingSession(configuration: .words(2), prompt: "aa\nbb")
    session.insertBatch("aaxy", at: start)
    let rendering = try render(session), map = try XCTUnwrap(rendering.compositionTextMap)
    let view = make(session, rendering: rendering); defer { view.stopCarets() }
    let values = layers(view), first = try XCTUnwrap(map.fieldRuns.first)
    for index in first.cells.indices { XCTAssertEqual(values[index].frame.minY, values[0].frame.minY) }
    XCTAssertGreaterThan(values[first.cells.count].frame.minY, values[0].frame.maxY)
  }

  func testWholeProjectedWordWrapsAsAContainerNotAsUnrelatedLetters() throws {
    let session = TypingSession(configuration: .words(2), prompt: "aa bbb")
    let rendering = try render(session), view = make(session, rendering: rendering, width: 100)
    defer { view.stopCarets() }
    let values = layers(view)
    XCTAssertEqual(values.count, 6)
    XCTAssertGreaterThan(values[3].frame.minY, values[0].frame.maxY)
    XCTAssertEqual(values[3].frame.minY, values[4].frame.minY)
    XCTAssertEqual(values[4].frame.minY, values[5].frame.minY)
  }

  func testCancelledFusedCanonicalPaceUsesFirstAndLastActualFragment() throws {
    var session = TestSessionFactory.make(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), modifiers: [.noSpaces]), customText: "a \u{301}b tail")
    session.insertBatch("a", at: start)
    let rendering = try render(session), map = try XCTUnwrap(rendering.compositionTextMap)
    let alias = try XCTUnwrap(map.canonicalAliases[0]); XCTAssertEqual(alias.count, 2)
    let view = make(session, rendering: rendering); defer { view.stopCarets() }
    let cells = map.fieldRuns.flatMap(\.cells), values = layers(view)
    let first = try allocation(values[try XCTUnwrap(cells.firstIndex { $0.id == alias.first })])
    let last = try allocation(values[try XCTUnwrap(cells.firstIndex { $0.id == alias.last })])
    let motion = PromptCaretMotionCoordinator(); var configuration = config(session, motion: motion)
    for after in [false, true] {
      configuration.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
        fromAfter: after, targetAfter: after, fraction: 1, sequence: after ? 2 : 1, targetGlyphID: 0) }
      view.configureCarets(configuration, glyphIDs: Array(session.promptGlyphs.indices)); try present(view, time: after ? 1 : 0)
      let position = try XCTUnwrap(motion.pace.position)
      XCTAssertEqual(position.minX, after ? last.maxX : first.minX, accuracy: 0.1)
      XCTAssertEqual(position.minY, after ? last.minY : first.minY, accuracy: 0.1)
    }
  }

  func testEveryStyleKeepsFinalSlotInkAndRotationAcrossCancellation() throws {
    var session = TypingSession(configuration: .words(2), prompt: "ab cd")
    session.insertBatch("a", at: start)
    let rendering = try render(session, "bXYZ"), view = make(session, rendering: rendering)
    defer { view.stopCarets() }
    let layer = try XCTUnwrap(layers(view).first), begin = layer.animation(forKey: "chooRotation")?.beginTime
    let ids = PromptGlyphLayout.indices(glyphs: session.promptGlyphs, words: session.promptWordPresentations, hideExtraLetters: false)
    for style in CompositionDisplayStyle.allCases {
      for marked in ["bXYZ", ""] {
        let next = try render(session, marked, style: style)
        view.configure(glyphs: ids.map { session.promptGlyphs[$0] }, font: font, palette: palette,
          animates: true, frameRate: 30, glyphIDs: ids, rendering: next)
        let cells = try XCTUnwrap(next.compositionTextMap).fieldRuns.flatMap(\.cells)
        XCTAssertEqual(layers(view).compactMap { ($0.string as? NSAttributedString)?.string },
          cells.map { String(ASLPromptGlyphContent(glyph: $0.glyph, text: $0.text).main.characters) })
        XCTAssertTrue(layers(view).first === layer)
        XCTAssertEqual(layer.animation(forKey: "chooRotation")?.beginTime, begin)
      }
    }
  }

  func testProductionProjectionGateDoesNotExcludeChoo() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    let start = try XCTUnwrap(source.range(of: "let usesCompositionProjection ="))
    let end = try XCTUnwrap(source.range(of: "let presentation =", range: start.upperBound..<source.endIndex))
    XCTAssertFalse(source[start.lowerBound..<end.lowerBound].contains("!practiceVisualEffect.usesChoo"))
  }

  func testUnchangedLayersReanchorAliasesWhileMissingCaretPreservesItsPreviousPosition() throws {
    var session = TypingSession(configuration: .words(2), prompt: "ab cd")
    session.insertBatch("a", at: start)
    let rendering = try render(session, "bXYZ"), map = try XCTUnwrap(rendering.compositionTextMap)
    let anchor = try XCTUnwrap(map.caret), cells = map.fieldRuns.flatMap(\.cells)
    let view = make(session, rendering: rendering); defer { view.stopCarets() }
    let motion = PromptCaretMotionCoordinator(); var configuration = config(session, motion: motion)
    configuration.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
      fromAfter: false, targetAfter: false, fraction: 1, sequence: 1, targetGlyphID: 0) }
    let ids = PromptGlyphLayout.indices(glyphs: session.promptGlyphs, words: session.promptWordPresentations, hideExtraLetters: false)
    view.configureCarets(configuration, glyphIDs: ids); try present(view)
    let originalLayers = layers(view), originalFrames = originalLayers.map(\.frame)
    XCTAssertEqual(motion.pace.position, try allocation(originalLayers[0])); XCTAssertNotNil(motion.main.position)
    let previousMain = motion.main.position
    var aliases = map.canonicalAliases; aliases[0] = [anchor.cellID]
    let changed = PromptCompositionTextMap(text: rendering.text, cellRanges: map.cellRanges,
      inkRanges: map.inkRanges, cellTexts: map.cellTexts, canonicalAliases: aliases, fieldUnits: [:],
      caret: nil, fieldRuns: map.fieldRuns)
    let next = PromptRendering(text: rendering.text, glyphCharacterOffsets: rendering.glyphCharacterOffsets,
      compositionTextMap: changed)
    view.configure(glyphs: ids.map { session.promptGlyphs[$0] }, font: font, palette: palette,
      animates: true, frameRate: 30, glyphIDs: ids, rendering: next)
    view.configureCarets(configuration, glyphIDs: ids); try present(view, time: 1)
    XCTAssertEqual(layers(view).map(\.frame), originalFrames)
    XCTAssertTrue(layers(view)[0] === originalLayers[0])
    XCTAssertEqual(motion.pace.position, try allocation(originalLayers[try XCTUnwrap(cells.firstIndex { $0.id == anchor.cellID })]))
    // The pinned caret.goTo returns before writing a position when its word
    // is missing. Preserve the channel, not a guessed canonical replacement.
    XCTAssertEqual(motion.main.position, previousMain)
    XCTAssertNotEqual(motion.main.position, originalFrames[1])
  }

  func testRemovedFieldKeepsEveryAnonymousStructuralRowWithoutRemovedInk() throws {
    var session = TypingSession(configuration: .init(mode: .quote, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(freedomMode: true), modifiers: [.noSpaces]),
      prompt: "ba\n\ncd", noSpaceWordEndIndices: [1, 4, 6], noSpaceTargetWords: ["b", "a\n\n", "cd"])
    session.removeTapePromptWords(.init(attemptID: session.automaticInputAttemptID, wordIndices: [1]))
    let rendering = try render(session, "X"), view = make(session, rendering: rendering)
    defer { view.stopCarets() }
    let map = try XCTUnwrap(rendering.compositionTextMap), values = layers(view)
    XCTAssertTrue(map.fieldRuns.contains { $0.fieldID == 1 && $0.removedReturns == 2 && $0.cells.isEmpty })
    XCTAssertEqual(values.count, 3)
    XCTAssertEqual(values[1].frame.minY - values[0].frame.minY, (values[0].frame.height + 12) * 2, accuracy: 0.1)
    XCTAssertEqual(values[1].frame.minY, values[2].frame.minY)
  }

  func testMarkedExtraReturnCannotCreateATargetStructuralRow() throws {
    var session = TypingSession(configuration: .words(2), prompt: "ab cd")
    session.insertBatch("ab", at: start)
    let view = make(session, rendering: try render(session, "\nX")); defer { view.stopCarets() }
    XCTAssertTrue(layers(view).allSatisfy { $0.frame.minY == layers(view).first?.frame.minY })
  }

  func testMountedProjectedChooCapturesOverflowCancellationAndReturnExtras() throws {
    var overflow = TypingSession(configuration: .words(2), prompt: "ab cd")
    overflow.insertBatch("a", at: start)
    var cancelled = TestSessionFactory.make(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), modifiers: [.noSpaces]), customText: "a \u{301}b tail")
    cancelled.insertBatch("a", at: start)
    var returns = TypingSession(configuration: .words(2), prompt: "aa\nbb")
    returns.insertBatch("aaxy", at: start)
    for (name, session, marked) in [("overflow", overflow, "bXYZ"), ("cancelled", cancelled, ""),
      ("return-extras", returns, "")] {
      let rendering = try render(session, marked), view = make(session, rendering: rendering)
      let ids = PromptGlyphLayout.indices(glyphs: session.promptGlyphs, words: session.promptWordPresentations, hideExtraLetters: false)
      view.configure(glyphs: ids.map { session.promptGlyphs[$0] }, font: font, palette: palette,
        animates: false, frameRate: 30, glyphIDs: ids, rendering: rendering)
      let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua); window.contentView = view
      defer { view.stopCarets(); window.contentView = nil; window.close() }
      view.layer?.backgroundColor = NSColor.white.cgColor
      view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
      let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
      view.cacheDisplay(in: view.bounds, to: bitmap)
      let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
      if let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] {
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("choo-composition-" + name + ".png"))
      }
      XCTAssertGreaterThan(png.count, 300); XCTAssertFalse(window.isVisible)
    }
  }

  func testAfterCaretUsesMeasuredLetterAdvanceNotTextLayerInkPadding() throws {
    var session = TypingSession(configuration: .words(2), prompt: "ab cd")
    session.insertBatch("a", at: start)
    let rendering = try render(session, "bXYZ"), map = try XCTUnwrap(rendering.compositionTextMap)
    let anchor = try XCTUnwrap(map.caret), cells = map.fieldRuns.flatMap(\.cells)
    let index = try XCTUnwrap(cells.firstIndex { $0.id == anchor.cellID })
    let view = make(session, rendering: rendering); defer { view.stopCarets() }
    let layer = layers(view)[index]
    let content = ASLPromptGlyphContent(glyph: cells[index].glyph, text: cells[index].text)
    let advance = ceil(ChooPromptPresentation.nativeText(content.main, font: font).size().width)
    XCTAssertGreaterThan(layer.frame.width, advance, "Raster overhang must not become letter allocation")
    let motion = PromptCaretMotionCoordinator()
    view.configureCarets(config(session, motion: motion), glyphIDs: Array(session.promptGlyphs.indices))
    try present(view)
    XCTAssertEqual(try XCTUnwrap(motion.main.position).minX, layer.frame.minX + advance, accuracy: 0.01)
  }
}
